"""Renders the four entity kinds: `Person`, `Domain`, `Event`, `Department`.

The other five components render documents. This one renders the argument, so
each of the four gets exactly one focal number and everything else is set below
it in the supporting hierarchy:

  * **Person** — `documented_pct`, as a percentage set at 34px above a bar and
    the sentence "documented 20% of what they knew". A bare `0.2` is unreadable
    across a room; the sentence is the thing that lands.
  * **Domain** — `bus_factor`, red at 1. One person knowing a domain is the
    finding the product exists to surface.
  * **Event** — `unfulfilled`. Not a number: the *absence*, named. An empty
    `unfulfilled` keeps the same block and states that every expected response
    occurred, because "we checked and found nothing" is the claim retrieval
    cannot make.
  * **Department** — member count, deliberately understated. Its job is to make
    the other three feel significant by contrast.

Four things the real data does that the contract's examples do not.

**`documented_pct` is `-1.0` for anyone still employed**, meaning *unknown*, not
0%. Priya's is `-1.0`. Rendering that as −100% — or as an empty bar, which reads
as "documented nothing" — is worse than saying nothing, so the unknown case
keeps the slot and states the unknown.

**Bill's `authored_count` is 0 and every `top_domains` count is 0.** He left 579
days before day 1, which is exactly why he is the story, so a zero here is a
finding rather than missing data and is captioned as one. The ranked list must
not assume a non-zero count.

**`unfulfilled` holds artifact-slot names as they appear in the corpus** —
`jira`, `confluence`, `pr`, `slack_thread` — not event names like
`confluence_created`. The raw token is rendered in mono because that is what the
graph actually stores, with a plain-English gloss under it.

**`people` is ranked by expertise score, not by artifact count.** In the TitanDB
fixture Jax (399 artifacts) ranks below Deepa (364). The list is therefore
emitted in server order and never re-sorted, and the count column is labelled
`artifacts` so the non-monotonicity reads as two different measures rather than
as a sorting bug.

Semantic status colours are the one place §8 permits colour outside the shared
tokens. The four below are the GitHub dark semantic set, chosen because they
hold their hue separation at projector gamma; `BAD` is also the red used for a
bus factor of 1, so "this is the problem" is one colour everywhere on the card.

**`len()` on a dict is a trap on the client.** It lowers to `.length`, which is
`undefined` for a JS object — so `len(d) > 0` and `len(d) == 0` are *both*
false and every branch guarded either way disappears. This emptied all four
kinds at once while `jac check` stayed clean and the compiled module exported
normally. Presence of a detail block is therefore tested on the raw payload
value (`get_bool(c, "person")`), and `len()` is used only over lists.

`produced` rows are not clickable. The signature `EntityCard(c)` carries no
`onOpenRef`, and inventing a click target that does nothing is worse than a
static row; the shell's footer is where refs are clickable.
"""

import from .Card {
    CARD_BG, CARD_FG, CARD_LINE, CARD_MONO, CARD_MUTED, CARD_PANE, CARD_SANS,
    Avatar, Chip, accent_for, day_date, time_ago
}

# Semantic status colours — see the module docstring. GitHub dark semantic set.
cl glob GOOD: str  = "#3fb950";   # SPECIFIED; documentation coverage that is fine
cl glob WARN: str  = "#d29922";   # DOCUMENTED_ONLY
cl glob ALERT: str = "#db6d28";   # DEBUGGED_ONLY
cl glob BAD: str   = "#f85149";   # UNDOCUMENTED; bus factor 1; a departure

cl glob STATUS_FG: dict[str, str] = {
    "SPECIFIED": GOOD,
    "DOCUMENTED_ONLY": WARN,
    "DEBUGGED_ONLY": ALERT,
    "UNDOCUMENTED": BAD
};

cl glob STATUS_BG: dict[str, str] = {
    "SPECIFIED": "rgba(63,185,80,0.13)",
    "DOCUMENTED_ONLY": "rgba(210,153,34,0.13)",
    "DEBUGGED_ONLY": "rgba(219,109,40,0.13)",
    "UNDOCUMENTED": "rgba(248,81,73,0.13)"
};

# The corpus' artifact-slot vocabulary, as `unfulfilled` stores it.
cl glob SLOT_GLOSS: dict[str, str] = {
    "jira": "a Jira ticket",
    "confluence": "a Confluence page",
    "pr": "a pull request",
    "slack_thread": "a Slack thread",
    "zoom": "a Zoom transcript",
    "email": "an email",
    "zd": "a Zendesk ticket",
    "sf": "a Salesforce opportunity"
};


# ------------------------------------------------------------------ helpers

cl def humanise(token: str) -> str {
    s: str = " ".join(token.split("_")).strip();
    if s == "" {
        return "";
    }
    return s[0].upper() + s[1:];
}

cl def gloss(slot: str) -> str {
    if slot in SLOT_GLOSS {
        return SLOT_GLOSS[slot] as str;
    }
    return " ".join(slot.split("_"));
}

# `documented_pct` is 0..1, or -1.0 for unknown. Rounds half-up rather than
# truncating: 0.2 must read 20%, not 19%.
cl def pct_int(v: float) -> int {
    n: int = int(v * 100.0 + 0.5);
    if n < 0 {
        return 0;
    }
    if n > 100 {
        return 100;
    }
    return n;
}

cl def pct_color(v: float) -> str {
    if v < 0.34 {
        return BAD;
    }
    if v < 0.67 {
        return WARN;
    }
    return GOOD;
}

cl def block(d: any) -> dict[str, any] {
    return (d as dict[str, any]) if d else {};
}

cl def get_str(d: dict[str, any], k: str) -> str {
    return (d[k] as str) if (k in d) and d[k] else "";
}

cl def get_int(d: dict[str, any], k: str) -> int {
    return (d[k] as int) if (k in d) and d[k] else 0;
}

# -1.0 is the corpus' own sentinel for "not measured", so a missing key and an
# explicit unknown land on the same value by design.
cl def get_float(d: dict[str, any], k: str) -> float {
    return (d[k] as float) if (k in d) and (d[k] is not None) else -1.0;
}

cl def get_bool(d: dict[str, any], k: str) -> bool {
    return True if (k in d) and d[k] else False;
}

cl def get_list(d: dict[str, any], k: str) -> list[dict[str, any]] {
    return (d[k] as list[dict[str, any]]) if (k in d) and d[k] else [];
}

cl def get_strs(d: dict[str, any], k: str) -> list[str] {
    return (d[k] as list[str]) if (k in d) and d[k] else [];
}


# ------------------------------------------------------------------ pieces

# Section rule. Every block on every one of the four kinds opens with one of
# these, so a Person and a Domain scan at the same rhythm.
def SectionLabel(text: str, tone: str = "") -> JsxElement {
    return <div style={{"fontFamily": CARD_MONO, "fontSize": "9.5px",
                        "letterSpacing": "0.16em", "textTransform": "uppercase",
                        "color": tone if tone != "" else CARD_MUTED,
                        "marginBottom": "7px"}}>
        {text}
    </div>;
}

def Meter(frac: float, color: str, height: int = 6) -> JsxElement {
    return <div style={{"height": str(height) + "px", "borderRadius": "3px",
                        "background": "rgba(150,170,200,0.13)",
                        "overflow": "hidden", "width": "100%"}}>
        <div style={{"height": "100%", "borderRadius": "3px",
                     "background": color,
                     "width": str(pct_int(frac)) + "%"}} />
    </div>;
}

# A stated unknown, shaped like the meter it replaces so the block keeps its
# height whether the number exists or not.
def MeterUnknown -> JsxElement {
    return <div style={{"height": "6px", "borderRadius": "3px",
                        "border": "1px dashed " + CARD_LINE, "width": "100%",
                        "boxSizing": "border-box"}} />;
}

def Pill(text: str, fg: str, bg: str) -> JsxElement {
    return <span style={{"display": "inline-block", "padding": "2px 8px",
                         "borderRadius": "999px", "background": bg,
                         "border": "1px solid " + fg, "color": fg,
                         "fontFamily": CARD_MONO, "fontSize": "9.5px",
                         "letterSpacing": "0.1em", "fontWeight": "700",
                         "whiteSpace": "nowrap"}}>
        {text}
    </span>;
}

# One figure and its caption. Used for every secondary number on all four kinds.
def Stat(value: str, label: str, note: str = "") -> JsxElement {
    return <div style={{"minWidth": "0"}}>
        <div style={{"fontFamily": CARD_SANS, "fontSize": "20px",
                     "fontWeight": "700", "lineHeight": "1.1",
                     "letterSpacing": "-0.02em", "color": CARD_FG}}>
            {value}
        </div>
        <div style={{"fontFamily": CARD_SANS, "fontSize": "10.5px",
                     "color": CARD_MUTED, "marginTop": "3px"}}>
            {label}
        </div>
        {if note != "" {
            <div style={{"fontFamily": CARD_SANS, "fontSize": "10px",
                         "fontStyle": "italic", "color": CARD_MUTED,
                         "marginTop": "2px"}}>
                {note}
            </div>
        }}
    </div>;
}

# The header every entity kind shares: eyebrow, name, one sub-line.
def EntityHead(kind: str, name: str, sub: str, avatar: str = "") -> JsxElement {
    return <div style={{"display": "flex", "gap": "12px", "alignItems": "center",
                        "padding": "13px 14px 12px 14px",
                        "borderBottom": "1px solid " + CARD_LINE,
                        "background": CARD_BG}}>
        {if avatar != "" {
            <div style={{"flexShrink": "0"}}><Avatar name={avatar} size={44} /></div>
        }}
        <div style={{"flex": "1", "minWidth": "0", "paddingRight": "20px"}}>
            <div style={{"fontFamily": CARD_MONO, "fontSize": "9.5px",
                         "letterSpacing": "0.18em", "color": accent_for(kind)}}>
                {kind.upper()}
            </div>
            <div style={{"fontFamily": CARD_SANS, "fontSize": "19px",
                         "fontWeight": "700", "letterSpacing": "-0.02em",
                         "color": CARD_FG, "marginTop": "2px",
                         "overflow": "hidden", "textOverflow": "ellipsis",
                         "whiteSpace": "nowrap"}}>
                {name}
            </div>
            {if sub != "" {
                <div style={{"fontFamily": CARD_SANS, "fontSize": "11.5px",
                             "color": CARD_MUTED, "marginTop": "2px",
                             "overflow": "hidden", "textOverflow": "ellipsis",
                             "whiteSpace": "nowrap"}}>
                    {sub}
                </div>
            }}
        </div>
    </div>;
}

# The blank fixtures: an entity kind whose detail block is null. Honest data —
# the node exists, the walker returned no detail — so it gets a stated empty
# state at the same padding the real content would have used.
def NoDetail(kind: str) -> JsxElement {
    return <div style={{"margin": "16px 14px 18px 14px", "padding": "20px 14px",
                        "background": CARD_PANE, "borderRadius": "8px",
                        "border": "1px dashed " + CARD_LINE, "textAlign": "center"}}>
        <div style={{"fontFamily": CARD_SANS, "fontSize": "12.5px",
                     "fontWeight": "600", "color": CARD_FG}}>
            {"No detail for this " + kind.lower()}
        </div>
        <div style={{"fontFamily": CARD_SANS, "fontSize": "11.5px",
                     "lineHeight": "1.5", "color": CARD_MUTED, "marginTop": "4px"}}>
            {"The node is in the graph; the walker returned no attributes for it."}
        </div>
    </div>;
}

# A person in a ranked list: rank, avatar, name, a count and its unit.
def RankRow(rank: int, name: str, count: int, unit: str,
            departed: bool = False) -> JsxElement {
    return <div style={{"display": "flex", "alignItems": "center", "gap": "8px",
                        "padding": "4px 0"}}>
        <span style={{"flexShrink": "0", "width": "13px", "textAlign": "right",
                      "fontFamily": CARD_MONO, "fontSize": "10px",
                      "color": CARD_MUTED}}>
            {str(rank)}
        </span>
        <Avatar name={name} size={20} />
        <span style={{"flex": "1", "minWidth": "0", "overflow": "hidden",
                      "textOverflow": "ellipsis", "whiteSpace": "nowrap",
                      "fontFamily": CARD_SANS, "fontSize": "12px",
                      "color": CARD_FG}}>
            {name}
        </span>
        {if departed {
            <span style={{"flexShrink": "0", "fontFamily": CARD_MONO,
                          "fontSize": "9px", "letterSpacing": "0.1em",
                          "color": BAD}}>
                {"DEPARTED"}
            </span>
        }}
        <span style={{"flexShrink": "0", "fontFamily": CARD_MONO,
                      "fontSize": "10.5px", "color": CARD_FG if count > 0 else CARD_MUTED}}>
            {(str(count) + " " + unit) if count > 0 else "—"}
        </span>
    </div>;
}

# An artifact row: the kind's own accent dot, so the row ties to the graph the
# same way the card's top bar does.
def ArtifactRow(kind: str, title: str, gid: str) -> JsxElement {
    return <div style={{"display": "flex", "alignItems": "center", "gap": "7px",
                        "padding": "4px 0"}}>
        <span style={{"width": "7px", "height": "7px", "borderRadius": "50%",
                      "flexShrink": "0", "background": accent_for(kind)}} />
        <span style={{"flex": "1", "minWidth": "0", "overflow": "hidden",
                      "textOverflow": "ellipsis", "whiteSpace": "nowrap",
                      "fontFamily": CARD_SANS, "fontSize": "11.5px",
                      "color": CARD_FG}}>
            {title if title != "" else gid}
        </span>
        <span style={{"flexShrink": "0", "fontFamily": CARD_MONO,
                      "fontSize": "10px", "color": CARD_MUTED}}>{kind}</span>
    </div>;
}


# ------------------------------------------------------------------ Person

def PersonBody(p: dict[str, any], gid: str) -> JsxElement {
    name: str = get_str(p, "name");
    if name == "" {
        name = gid;
    }
    role: str = get_str(p, "role");
    dept: str = get_str(p, "dept");
    departed_day: int = get_int(p, "departed_day");
    joined_day: int = get_int(p, "joined_day");
    authored: int = get_int(p, "authored_count");
    pct: float = get_float(p, "documented_pct");
    known: bool = pct >= 0.0;

    doms: list[dict[str, any]] = get_list(p, "top_domains");
    # The walker's own payload carries `departed_domains` (bare strings) and an
    # empty `top_domains` for someone who left before the window. Same list,
    # different shape; render it rather than showing the person as domainless.
    if len(doms) == 0 {
        for d in get_strs(p, "departed_domains") {
            doms.append({"name": d, "count": 0});
        }
    }

    sub: str = role;
    if dept != "" {
        sub = (sub + " · " + dept) if sub != "" else dept;
    }
    if sub == "" {
        sub = "role not recorded";
    }

    # `departed_day` is negative for anyone who left before day 1. `time_ago`
    # returns "" for a non-positive day by design, so the distance is spelled
    # out here instead of faked through it.
    before: int = -departed_day if departed_day < 0 else 0;
    when: str = "";
    if departed_day != 0 {
        when = "day " + str(departed_day);
        if before > 0 {
            when = when + " · " + str(before) + " days before the corpus opens";
        } elif day_date(departed_day) != "" {
            when = when + " · " + day_date(departed_day) + " · " + time_ago(departed_day);
        }
    }

    ranked: list[dict[str, any]] = [];
    for d in doms[:8] {
        ranked.append({"name": get_str(d, "name"), "count": get_int(d, "count"),
                       "rank": len(ranked) + 1, "key": "d" + str(len(ranked))});
    }

    return <div>
        <EntityHead kind="Person" name={name} sub={sub} avatar={name} />

        {if departed_day != 0 {
            <div style={{"display": "flex", "alignItems": "center", "gap": "8px",
                         "padding": "8px 14px", "background": "rgba(248,81,73,0.07)",
                         "borderBottom": "1px solid " + CARD_LINE}}>
                <Pill text="DEPARTED" fg={BAD} bg="rgba(248,81,73,0.13)" />
                <span style={{"flex": "1", "minWidth": "0", "fontFamily": CARD_MONO,
                              "fontSize": "10.5px", "color": CARD_MUTED,
                              "overflow": "hidden", "textOverflow": "ellipsis",
                              "whiteSpace": "nowrap"}}>
                    {when}
                </span>
            </div>
        }}

        <div style={{"padding": "14px"}}>
            <SectionLabel text="Documentation coverage" />
            <div style={{"display": "flex", "alignItems": "baseline", "gap": "10px"}}>
                <span style={{"fontFamily": CARD_SANS, "fontSize": "34px",
                              "fontWeight": "700", "lineHeight": "1",
                              "letterSpacing": "-0.03em",
                              "color": pct_color(pct) if known else CARD_MUTED}}>
                    {(str(pct_int(pct)) + "%") if known else "—"}
                </span>
                <span style={{"flex": "1", "minWidth": "0", "fontFamily": CARD_SANS,
                              "fontSize": "12.5px", "lineHeight": "1.4",
                              "color": CARD_FG if known else CARD_MUTED}}>
                    {("documented " + str(pct_int(pct)) + "% of what they knew")
                     if known else "coverage not measured for current staff"}
                </span>
            </div>
            <div style={{"marginTop": "9px"}}>
                {if known { <Meter frac={pct} color={pct_color(pct)} /> }}
                {if not known { <MeterUnknown /> }}
            </div>

            <div style={{"display": "flex", "gap": "26px", "marginTop": "16px",
                         "paddingTop": "13px",
                         "borderTop": "1px solid " + CARD_LINE}}>
                <Stat value={str(authored)} label="artifacts authored"
                      note={"none in this window" if (authored == 0) and (departed_day != 0) else ""} />
                <Stat value={str(len(doms))} label="domains held" />
                {if joined_day > 0 {
                    <Stat value={"day " + str(joined_day)} label="joined" />
                }}
            </div>
        </div>

        {if len(ranked) > 0 {
            <div style={{"padding": "0 14px 14px 14px"}}>
                <SectionLabel text={"Domains they took with them"
                                if departed_day != 0 else "Top domains"} />
                {for r in ranked {
                    <RankRow key={r["key"] as str} rank={r["rank"] as int}
                             name={r["name"] as str} count={r["count"] as int}
                             unit="artifacts" />
                }}
            </div>
        }}
    </div>;
}


# ------------------------------------------------------------------ Domain

def DepartedWith(rows: list[dict[str, any]]) -> JsxElement {
    return <div style={{"margin": "0 14px 14px 14px", "padding": "11px 12px",
                        "background": "rgba(248,81,73,0.07)",
                        "borderLeft": "3px solid " + BAD,
                        "borderRadius": "0 8px 8px 0"}}>
        <SectionLabel text="Left with this knowledge" tone={BAD} />
        {for r in rows {
            <div key={r["key"] as str} style={{"marginTop": "9px"}}>
                <div style={{"display": "flex", "alignItems": "center", "gap": "8px"}}>
                    <Avatar name={r["name"] as str} size={26} />
                    <div style={{"flex": "1", "minWidth": "0"}}>
                        <div style={{"fontFamily": CARD_SANS, "fontSize": "13px",
                                     "fontWeight": "700", "color": CARD_FG}}>
                            {r["name"]}
                        </div>
                        <div style={{"fontFamily": CARD_SANS, "fontSize": "11px",
                                     "color": CARD_MUTED, "marginTop": "1px"}}>
                            {r["line"]}
                        </div>
                    </div>
                    <span style={{"flexShrink": "0", "fontFamily": CARD_SANS,
                                  "fontSize": "17px", "fontWeight": "700",
                                  "color": r["color"] as str}}>
                        {r["figure"]}
                    </span>
                </div>
                {if (r["known"] as bool) {
                    <div style={{"marginTop": "6px", "paddingLeft": "34px"}}>
                        <Meter frac={r["pct"] as float} color={r["color"] as str}
                               height={4} />
                    </div>
                }}
            </div>
        }}
    </div>;
}

def DomainBody(d: dict[str, any], gid: str) -> JsxElement {
    name: str = get_str(d, "name");
    if name == "" {
        name = gid;
    }
    aliases: list[str] = get_strs(d, "aliases");
    status: str = get_str(d, "doc_status");
    bus: int = get_int(d, "bus_factor");
    artifacts: int = get_int(d, "artifact_count");
    genesis: bool = get_bool(d, "is_genesis_gap");

    people: list[dict[str, any]] = get_list(d, "people");
    left: list[dict[str, any]] = get_list(d, "departed_with");

    bus_color: str = BAD if bus <= 1 else (WARN if bus == 2 else CARD_FG);
    bus_line: str = "no one still here carries it" if bus == 0 else (
        "one person carries this domain" if bus == 1 else
        str(bus) + " people could carry it");

    fg: str = (STATUS_FG[status] as str) if status in STATUS_FG else CARD_MUTED;
    bg: str = (STATUS_BG[status] as str) if status in STATUS_BG else CARD_PANE;

    # Emitted in server order — that order is the expertise ranking, and the
    # artifact counts are deliberately not monotonic in it. See the docstring.
    ranked: list[dict[str, any]] = [];
    for p in people[:8] {
        ranked.append({"name": get_str(p, "name"), "count": get_int(p, "count"),
                       "departed": get_bool(p, "departed"),
                       "rank": len(ranked) + 1, "key": "p" + str(len(ranked))});
    }

    gone: list[dict[str, any]] = [];
    for p in left {
        pct: float = get_float(p, "documented_pct");
        known: bool = pct >= 0.0;
        gone.append({
            "name": get_str(p, "name"),
            "pct": pct,
            "known": known,
            "color": pct_color(pct) if known else CARD_MUTED,
            "figure": (str(pct_int(pct)) + "%") if known else "—",
            "line": ("documented " + str(pct_int(pct)) + "% of what they knew")
                    if known else "coverage unknown",
            "key": "g" + str(len(gone))
        });
    }

    return <div>
        <EntityHead kind="Domain" name={name}
                    sub={str(artifacts) + " artifacts mention it"} />

        <div style={{"padding": "14px"}}>
            <div style={{"display": "flex", "alignItems": "flex-start", "gap": "14px"}}>
                <div style={{"flexShrink": "0"}}>
                    <div style={{"fontFamily": CARD_SANS, "fontSize": "46px",
                                 "fontWeight": "700", "lineHeight": "0.9",
                                 "letterSpacing": "-0.04em", "color": bus_color}}>
                        {str(bus)}
                    </div>
                </div>
                <div style={{"flex": "1", "minWidth": "0", "paddingTop": "2px"}}>
                    <div style={{"fontFamily": CARD_MONO, "fontSize": "9.5px",
                                 "letterSpacing": "0.16em", "color": CARD_MUTED}}>
                        {"BUS FACTOR"}
                    </div>
                    <div style={{"fontFamily": CARD_SANS, "fontSize": "13px",
                                 "fontWeight": "700", "color": bus_color,
                                 "marginTop": "3px"}}>
                        {bus_line}
                    </div>
                    <div style={{"fontFamily": CARD_SANS, "fontSize": "10.5px",
                                 "lineHeight": "1.45", "color": CARD_MUTED,
                                 "marginTop": "3px"}}>
                        {"still-employed people scoring ≥ 50% of the top contributor"}
                    </div>
                </div>
            </div>

            <div style={{"display": "flex", "flexWrap": "wrap", "gap": "6px",
                         "alignItems": "center", "marginTop": "13px",
                         "paddingTop": "12px",
                         "borderTop": "1px solid " + CARD_LINE}}>
                {if status != "" {
                    <Pill text={" ".join(status.split("_"))} fg={fg} bg={bg} />
                }}
                {if genesis {
                    <Pill text="GENESIS GAP" fg={ALERT} bg="rgba(219,109,40,0.13)" />
                }}
                {for a in aliases[:6] {
                    <Chip key={a} text={a} />
                }}
            </div>
            {if genesis {
                <div style={{"fontFamily": CARD_SANS, "fontSize": "10.5px",
                             "lineHeight": "1.45", "color": CARD_MUTED,
                             "marginTop": "7px"}}>
                    {"Predates the corpus: the decisions that created it were never written down here."}
                </div>
            }}
        </div>

        {if len(gone) > 0 { <DepartedWith rows={gone} /> }}

        {if len(ranked) > 0 {
            <div style={{"padding": "0 14px 14px 14px"}}>
                <SectionLabel text={"Who knows it · ranked by expertise"} />
                {for r in ranked {
                    <RankRow key={r["key"] as str} rank={r["rank"] as int}
                             name={r["name"] as str} count={r["count"] as int}
                             unit="artifacts" departed={r["departed"] as bool} />
                }}
            </div>
        }}
    </div>;
}


# ------------------------------------------------------------------ Event

def EventBody(e: dict[str, any], gid: str, title: str) -> JsxElement {
    etype: str = get_str(e, "event_type");
    label: str = humanise(etype) if etype != "" else (title if title != "" else gid);
    day: int = get_int(e, "day");
    incident: bool = get_bool(e, "is_incident");

    unfulfilled: list[str] = get_strs(e, "unfulfilled");
    involves: list[str] = get_strs(e, "involves");
    produced: list[dict[str, any]] = get_list(e, "produced");

    accent: str = accent_for("Event");
    sub: str = "day " + str(day);
    if day_date(day) != "" {
        sub = sub + " · " + day_date(day) + " · " + time_ago(day);
    }

    rows: list[dict[str, any]] = [];
    for r in produced[:8] {
        rows.append({"kind": get_str(r, "kind"), "title": get_str(r, "title"),
                     "gid": get_str(r, "gid"), "key": "a" + str(len(rows))});
    }

    return <div>
        <EntityHead kind="Event" name={label} sub={sub} />

        {if incident {
            <div style={{"display": "flex", "alignItems": "center", "gap": "8px",
                         "padding": "8px 14px", "background": "rgba(248,81,73,0.07)",
                         "borderBottom": "1px solid " + CARD_LINE}}>
                <Pill text="INCIDENT" fg={BAD} bg="rgba(248,81,73,0.13)" />
                <span style={{"fontFamily": CARD_SANS, "fontSize": "11px",
                              "color": CARD_MUTED}}>
                    {"escalated on the day it was detected"}
                </span>
            </div>
        }}

        <div style={{"padding": "14px"}}>
            {if len(unfulfilled) > 0 {
                <div style={{"padding": "11px 12px", "borderRadius": "0 8px 8px 0",
                             "borderLeft": "3px solid " + accent,
                             "background": "rgba(255,123,114,0.07)"}}>
                    <SectionLabel text="Expected but never happened" tone={accent} />
                    {for u in unfulfilled {
                        <div key={u} style={{"marginTop": "6px"}}>
                            <div style={{"fontFamily": CARD_MONO, "fontSize": "14px",
                                         "fontWeight": "700", "color": accent,
                                         "wordBreak": "break-word"}}>
                                {u}
                            </div>
                            <div style={{"fontFamily": CARD_SANS, "fontSize": "11px",
                                         "color": CARD_MUTED, "marginTop": "1px"}}>
                                {gloss(u) + " was expected here and was never written"}
                            </div>
                        </div>
                    }}
                </div>
            }}

            {if len(unfulfilled) == 0 {
                <div style={{"padding": "11px 12px", "borderRadius": "0 8px 8px 0",
                             "borderLeft": "3px solid " + GOOD,
                             "background": "rgba(63,185,80,0.06)"}}>
                    <SectionLabel text="Expected responses" tone={GOOD} />
                    <div style={{"fontFamily": CARD_SANS, "fontSize": "12.5px",
                                 "fontWeight": "700", "color": CARD_FG}}>
                        {"All expected responses occurred"}
                    </div>
                    <div style={{"fontFamily": CARD_SANS, "fontSize": "11px",
                                 "lineHeight": "1.45", "color": CARD_MUTED,
                                 "marginTop": "2px"}}>
                        {"Every artifact this event should have produced exists in the graph."}
                    </div>
                </div>
            }}

            {if len(involves) > 0 {
                <div style={{"marginTop": "15px"}}>
                    <SectionLabel text={"Involves · " + str(len(involves))} />
                    <div style={{"display": "flex", "flexWrap": "wrap", "gap": "10px"}}>
                        {for n in involves {
                            <span key={n} style={{"display": "inline-flex",
                                                  "alignItems": "center", "gap": "5px"}}>
                                <Avatar name={n} size={20} />
                                <span style={{"fontFamily": CARD_SANS,
                                              "fontSize": "11.5px", "color": CARD_FG}}>
                                    {n}
                                </span>
                            </span>
                        }}
                    </div>
                </div>
            }}

            {if len(rows) > 0 {
                <div style={{"marginTop": "15px"}}>
                    <SectionLabel text={"Produced · " + str(len(rows))} />
                    {for r in rows {
                        <ArtifactRow key={r["key"] as str} kind={r["kind"] as str}
                                     title={r["title"] as str} gid={r["gid"] as str} />
                    }}
                </div>
            }}

            {if (len(involves) == 0) and (len(rows) == 0) {
                <div style={{"marginTop": "15px", "fontFamily": CARD_SANS,
                             "fontSize": "11px", "color": CARD_MUTED}}>
                    {"No participants or artifacts recorded for this event."}
                </div>
            }}
        </div>
    </div>;
}


# ------------------------------------------------------------------ Department

# Deliberately the plainest of the four: two figures and a member list. Its job
# is to make the other three feel significant by contrast, so it is not
# decorated and carries no colour beyond the shared tokens.
def DeptBody(d: dict[str, any], gid: str) -> JsxElement {
    name: str = get_str(d, "name");
    if name == "" {
        name = gid;
    }
    members: list[str] = get_strs(d, "members");
    count: int = get_int(d, "member_count");
    artifacts: int = get_int(d, "artifact_count");

    return <div>
        <EntityHead kind="Department" name={" ".join(name.split("_"))}
                    sub={name if len(name.split("_")) > 1 else ""} />

        <div style={{"padding": "14px"}}>
            <div style={{"display": "flex", "gap": "30px"}}>
                <Stat value={str(count)} label="members" />
                <Stat value={str(artifacts)} label="artifacts" />
            </div>

            {if len(members) > 0 {
                <div style={{"marginTop": "16px", "paddingTop": "13px",
                             "borderTop": "1px solid " + CARD_LINE}}>
                    <SectionLabel text={("Members · showing " + str(len(members)) + " of "
                                     + str(count)) if count > len(members) else "Members"} />
                    <div style={{"display": "flex", "flexWrap": "wrap", "gap": "5px"}}>
                        {for m in members {
                            <Chip key={m} text={m} />
                        }}
                    </div>
                </div>
            }}
        </div>
    </div>;
}


# ------------------------------------------------------------------ the card

def:pub EntityCard(c: dict[str, any]) -> JsxElement {
    kind: str = (c["kind"] as str) if c["kind"] else "";
    gid: str = (c["gid"] as str) if c["gid"] else "";
    title: str = (c["title"] as str) if c["title"] else "";

    person: dict[str, any] = block(c["person"]);
    domain: dict[str, any] = block(c["domain"]);
    event_detail: dict[str, any] = block(c["event_detail"]);
    dept_detail: dict[str, any] = block(c["dept_detail"]);

    # Presence is tested on the RAW payload value, never with `len()` on the
    # dict. `len(d)` lowers to `d.length`, which on a client-side object is
    # `undefined` — so `len(d) > 0` and `len(d) == 0` are BOTH false and every
    # branch silently vanishes. That emptied all four kinds at once and is
    # invisible to `jac check`. See the module docstring.
    has_person: bool = get_bool(c, "person");
    has_domain: bool = get_bool(c, "domain");
    has_event: bool = get_bool(c, "event_detail");
    has_dept: bool = get_bool(c, "dept_detail");

    name: str = title if title != "" else gid;

    return <div>
        {if (kind == "Person") and has_person {
            <PersonBody p={person} gid={name} />
        }}
        {if (kind == "Domain") and has_domain {
            <DomainBody d={domain} gid={name} />
        }}
        {if (kind == "Event") and has_event {
            <EventBody e={event_detail} gid={name} title={title} />
        }}
        {if (kind == "Department") and has_dept {
            <DeptBody d={dept_detail} gid={name} />
        }}

        {if (kind == "Person") and (not has_person) {
            <><EntityHead kind="Person" name={name} sub="" avatar={name} />
              <NoDetail kind="Person" /></>
        }}
        {if (kind == "Domain") and (not has_domain) {
            <><EntityHead kind="Domain" name={name} sub="" />
              <NoDetail kind="Domain" /></>
        }}
        {if (kind == "Event") and (not has_event) {
            <><EntityHead kind="Event" name={name} sub="" />
              <NoDetail kind="Event" /></>
        }}
        {if (kind == "Department") and (not has_dept) {
            <><EntityHead kind="Department" name={name} sub="" />
              <NoDetail kind="Department" /></>
        }}
    </div>;
}
