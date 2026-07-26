"""`Email` — From / To / Subject / Date over a rule, prose, signature set apart.

Three decisions, all of which came out of reading the actual corpus rather than
from the shape of the format.

**The signature is the only honest source for the sender.** `authors` is
documented as `[sender, recipient]`, and in the corpus it usually is — but the
payload this card was built against carries `["Jax"]` for a message that Nora
Klein wrote *to* Jax. Trusting `authors[0]` puts the recipient on the From line.
So: the signature's full name wins when there is one, the greeting line
(`Hi Jax,`) names the recipient, and `authors` is the fallback for whichever
side is still unknown. This is also the only place the sender's job title and
outside company appear at all.

**Signature detection is deliberately conservative.** A closing marker
(`Best regards,` and friends) must be a line *by itself*, near the end, with one
to four non-empty lines after it. It fires on 326 of the 1,257 email-ish rows in
`corpus.parquet` — and when it does not fire the whole body renders as prose,
because the failure mode of a greedy rule is truncating the last paragraph of a
message, which is worse than not styling a signature.

**"External" is claimed only from the gid.** `is_external` exists on the corpus
row but not in the §1 payload, and the signature's company is not proof of
anything — an internal sender can sign with their own employer. A `gid` starting
`ext_` is, measured over the 610 `doc_type == "email"` rows, exactly precise:
251 of them, zero of which are internal (it misses 52 external ones, which is
the right direction to be wrong in). The company name beside the badge comes
from the signature and is shown only when both are known.

Text from the corpus contains non-breaking hyphens (U+2011) and curly
apostrophes and they are passed through untouched — they are most of what makes
this read as correspondence rather than as log output. The one normalisation is
`rstrip` per line, because the bodies end many lines with two spaces and a
ragged right edge is a rendering artefact, not typography.
"""

import from .Card {
    Avatar, CARD_FG, CARD_LINE, CARD_MONO, CARD_MUTED, CARD_PANE, CARD_SANS,
    accent_for, day_date, time_ago
}

# Closing markers, matched against a whole line, lowercased and stripped. Every
# one of these was seen terminating a real message in `data/corpus.parquet`.
cl glob CLOSERS: list[str] = [
    "best regards,", "kind regards,", "warm regards,", "regards,",
    "thanks,", "many thanks,", "thank you,", "best,", "sincerely,", "cheers,"
];

cl glob GREETINGS: list[str] = ["hi ", "hello ", "hey ", "dear "];

# A signature is at most this many lines of name/title/company, and the closer
# has to be this close to the end. Both bounds exist to stop the rule eating a
# paragraph that merely happens to contain the word "thanks".
cl glob SIG_MAX_LINES: int = 4;
cl glob SIG_MAX_TAIL: int = 5;


# ------------------------------------------------------------------- parsing

cl def body_lines(body: str) -> list[str] {
    out: list[str] = [];
    for ln in body.split("\n") {
        out.append(ln.rstrip());
    }
    return out;
}

cl def filled(lines: list[str]) -> list[str] {
    out: list[str] = [];
    for ln in lines {
        if ln.strip() != "" {
            out.append(ln.strip());
        }
    }
    return out;
}

cl def last_filled(lines: list[str]) -> int {
    last: int = -1;
    for i in range(len(lines)) {
        if lines[i].strip() != "" {
            last = i;
        }
    }
    return last;
}

# Index of the closing marker, or -1. Forward scan keeping the last qualifying
# hit — a reversed `range` step is one more thing to trust the JS lowering with,
# and a forward pass over a few dozen lines costs nothing.
cl def closer_index(lines: list[str]) -> int {
    last: int = last_filled(lines);
    if last < 0 {
        return -1;
    }
    found: int = -1;
    for i in range(len(lines)) {
        if (last - i) > SIG_MAX_TAIL {
            continue;
        }
        if lines[i].strip().lower() in CLOSERS {
            after: int = len(filled(lines[i + 1:]));
            if after >= 1 and after <= SIG_MAX_LINES {
                found = i;
            }
        }
    }
    return found;
}

# Blank-line-separated paragraphs. Lines inside a paragraph are rejoined with a
# single space: the corpus hard-wraps some bodies at ~95 columns and honouring
# those breaks would put a ragged edge in the middle of the card.
cl def paragraphs(lines: list[str]) -> list[str] {
    out: list[str] = [];
    cur: list[str] = [];
    for ln in lines {
        if ln.strip() == "" {
            if len(cur) > 0 {
                out.append(" ".join(cur));
                cur = [];
            }
        } else {
            cur.append(ln.strip());
        }
    }
    if len(cur) > 0 {
        out.append(" ".join(cur));
    }
    return out;
}

# "Hi Jax," -> "Jax". Bounded length so a sentence opening "Hey everyone, the
# thing is..." cannot be mistaken for an addressee.
cl def greeting_name(paras: list[str]) -> str {
    if len(paras) == 0 {
        return "";
    }
    first: str = paras[0].strip();
    if not first.endswith(",") or len(first) > 48 {
        return "";
    }
    low: str = first.lower();
    for g in GREETINGS {
        if low.startswith(g) {
            return first[len(g):len(first) - 1].strip();
        }
    }
    return "";
}

# Last comma-separated fragment of the last signature line: "Cloud Account
# Manager, AWS" -> "AWS". Shown only next to the EXTERNAL badge, so a wrong
# guess here degrades to a bare badge rather than to a false claim.
cl def sig_company(sig: list[str]) -> str {
    if len(sig) < 2 {
        return "";
    }
    tail: str = sig[len(sig) - 1];
    if "," not in tail {
        return "";
    }
    parts: list[str] = tail.split(",");
    return parts[len(parts) - 1].strip();
}


# ------------------------------------------------------------------- pieces

def Label(text: str) -> JsxElement {
    return <span style={{"fontFamily": CARD_MONO, "fontSize": "9px",
                         "letterSpacing": "0.14em", "color": CARD_MUTED,
                         "paddingTop": "3px", "whiteSpace": "nowrap"}}>
        {text}
    </span>;
}

# The blank-fixture stand-in for an avatar. A dashed ring reads as "we do not
# know who" rather than as a broken image.
def NoAvatar -> JsxElement {
    return <span style={{"display": "inline-block", "flexShrink": "0",
                         "width": "34px", "height": "34px", "borderRadius": "50%",
                         "border": "1px dashed " + CARD_LINE}} />;
}


# --------------------------------------------------------------------- card

def:pub EmailCard(c: dict[str, any]) -> JsxElement {
    title: str = (c["title"] as str) if c["title"] else "";
    body: str = (c["body"] as str) if c["body"] else "";
    authors: list = (c["authors"] as list) if c["authors"] else [];
    day: int = (c["day"] as int) if c["day"] else 0;
    gid: str = (c["gid"] as str) if c["gid"] else "";

    accent: str = accent_for("Email");

    lines: list[str] = body_lines(body);
    ci: int = closer_index(lines);

    closer: str = "";
    sig: list[str] = [];
    paras: list[str] = [];
    if ci >= 0 {
        closer = lines[ci].strip();
        sig = filled(lines[ci + 1:]);
        paras = paragraphs(lines[:ci]);
    }
    # A body that is *only* a sign-off ("Thanks,\nJax") would otherwise render
    # as an empty-body notice sitting above visible text. Nothing above the
    # closer means there is no message to set the signature apart from, so the
    # whole thing goes back to being prose.
    if ci < 0 or len(paras) == 0 {
        closer = "";
        sig = [];
        paras = paragraphs(lines);
    }

    sig_name: str = sig[0] if len(sig) > 0 else "";
    sig_rest: str = " · ".join(sig[1:]) if len(sig) > 1 else "";
    company: str = sig_company(sig);

    # Recipient first, because the greeting is the more reliable of the two
    # signals and knowing it lets the sender fall back to "the other author".
    to_name: str = greeting_name(paras);
    if to_name == "" and len(authors) >= 2 {
        to_name = authors[1] as str;
    }

    from_name: str = sig_name;
    if from_name == "" {
        for a in authors {
            if from_name == "" and (a as str) != to_name {
                from_name = a as str;
            }
        }
    }
    if from_name == "" and len(authors) > 0 {
        from_name = authors[0] as str;
    }
    if to_name == "" {
        for a in authors {
            if to_name == "" and (a as str) != from_name {
                to_name = a as str;
            }
        }
    }

    external: bool = gid.startswith("ext_");
    badge: str = ("EXTERNAL · " + company) if (external and company != "") else "EXTERNAL";

    stamp: str = day_date(day);
    if stamp != "" {
        stamp = stamp + " · " + time_ago(day);
    }

    value_style: dict[str, str] = {
        "fontFamily": CARD_SANS, "fontSize": "12.5px", "lineHeight": "1.45",
        "color": CARD_FG, "minWidth": "0", "overflowWrap": "break-word"
    };
    muted_value: dict[str, str] = {
        "fontFamily": CARD_SANS, "fontSize": "12.5px", "lineHeight": "1.45",
        "color": CARD_MUTED
    };

    return <div>
        <div style={{"padding": "12px 14px 13px 14px",
                     "borderBottom": "1px solid " + CARD_LINE}}>

            <div style={{"display": "flex", "alignItems": "center",
                         "justifyContent": "space-between", "gap": "10px",
                         "marginBottom": "11px"}}>
                <span style={{"fontFamily": CARD_MONO, "fontSize": "9px",
                              "letterSpacing": "0.18em", "color": CARD_MUTED}}>
                    {"EMAIL"}
                </span>
                {if external {
                    <span style={{"flexShrink": "0", "padding": "2px 7px",
                                  "borderRadius": "4px", "background": CARD_PANE,
                                  "border": "1px solid " + CARD_LINE,
                                  "fontFamily": CARD_MONO, "fontSize": "9px",
                                  "letterSpacing": "0.12em", "color": accent,
                                  "whiteSpace": "nowrap"}}>
                        {badge}
                    </span>
                }}
            </div>

            <div style={{"display": "flex", "gap": "11px",
                         "alignItems": "flex-start"}}>
                {if from_name != "" { <Avatar name={from_name} size={34} /> }}
                {if from_name == "" { <NoAvatar /> }}

                <div style={{"flex": "1", "minWidth": "0", "display": "grid",
                             "gridTemplateColumns": "52px minmax(0, 1fr)",
                             "columnGap": "9px", "rowGap": "4px",
                             "alignItems": "baseline"}}>

                    <Label text="FROM" />
                    <div style={value_style}>
                        {if from_name != "" {
                            <span style={{"fontWeight": "600"}}>{from_name}</span>
                        }}
                        {if from_name == "" {
                            <span style={{"color": CARD_MUTED}}>{"—"}</span>
                        }}
                        {if sig_rest != "" {
                            <span style={{"color": CARD_MUTED, "fontSize": "11.5px"}}>
                                {"  ·  " + sig_rest}
                            </span>
                        }}
                    </div>

                    <Label text="TO" />
                    <div style={value_style if to_name != "" else muted_value}>
                        {to_name if to_name != "" else "—"}
                    </div>

                    <Label text="SUBJECT" />
                    <div style={{"fontFamily": CARD_SANS, "fontSize": "13.5px",
                                 "fontWeight": "600", "lineHeight": "1.35",
                                 "color": CARD_FG, "minWidth": "0",
                                 "overflowWrap": "break-word"}}>
                        {title if title != "" else "(no subject)"}
                    </div>

                    <Label text="DATE" />
                    <div style={{"fontFamily": CARD_MONO, "fontSize": "11px",
                                 "color": CARD_MUTED}}>
                        {stamp if stamp != "" else "—"}
                    </div>
                </div>
            </div>
        </div>

        <div style={{"padding": "14px 16px 16px 16px"}}>
            {if len(paras) == 0 {
                <div style={{"border": "1px dashed " + CARD_LINE,
                             "borderRadius": "6px", "padding": "16px",
                             "textAlign": "center", "fontFamily": CARD_MONO,
                             "fontSize": "10.5px", "letterSpacing": "0.08em",
                             "color": CARD_MUTED}}>
                    {"NO MESSAGE BODY"}
                </div>
            }}

            {for i in range(len(paras)) {
                <p key={str(i)}
                   style={{"margin": "0 0 11px 0", "fontFamily": CARD_SANS,
                           "fontSize": "13px", "lineHeight": "1.72",
                           "color": CARD_FG, "overflowWrap": "break-word"}}>
                    {paras[i]}
                </p>
            }}

            {if len(sig) > 0 {
                <div style={{"marginTop": "15px", "paddingTop": "11px",
                             "borderTop": "1px solid " + CARD_LINE}}>
                    <div style={{"fontFamily": CARD_SANS, "fontSize": "12.5px",
                                 "fontStyle": "italic", "color": CARD_MUTED,
                                 "marginBottom": "5px"}}>
                        {closer}
                    </div>
                    <div style={{"fontFamily": CARD_SANS, "fontSize": "12.5px",
                                 "fontWeight": "600", "color": CARD_FG,
                                 "lineHeight": "1.5"}}>
                        {sig_name}
                    </div>
                    {for k in range(1, len(sig)) {
                        <div key={str(k)}
                             style={{"fontFamily": CARD_SANS, "fontSize": "11.5px",
                                     "color": CARD_MUTED, "lineHeight": "1.55"}}>
                            {sig[k]}
                        </div>
                    }}
                </div>
            }}
        </div>
    </div>;
}
