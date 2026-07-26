"""`ZoomTranscript` — a meeting transcript, rendered as one.

Three decisions worth knowing.

**The gutter is the whole illusion.** A transcript reads as a transcript because
the timestamps form a straight monospace column down the left and the speech
hangs off it. Put the timestamp inline with the text and the same data reads as
a chat log. So: a fixed 54px gutter, `ui-monospace`, tabular figures, and the
turn body in a flex column beside it that is allowed to wrap as far as it likes
without ever moving the times.

**The parser never uses the `---` separator.** Every one of the 208 transcripts
in the corpus has one, but a turn's own text may contain anything, and a body
split on the first `---` is a body that loses everything before a stray rule.
Instead the whole body is walked line by line: labelled preamble lines
(`**Date:**`, `**Topic:**`, `**Attendees:**`) are picked off wherever they
appear, turn lines are matched positionally, `---` and the `#` heading are
dropped, and **any other non-empty line after a turn has started is a
continuation of that turn**. That last rule is load-bearing: 30 lines across the
corpus wrap, and most of them are numbered agenda items, so continuations are
kept as separate lines rather than joined with a space — joining turns a
three-item list into one run-on sentence.

**Attendees are chips, authors are avatars.** The attendee row comes from
`**Attendees:**`, not from `authors` — `authors` is the artifact's recorded
actors and is a subset — and it is rendered with `Chip`, deliberately not with
`Avatar`. The shell's footer already renders `authors` as an avatar row directly
below, and on a meeting whose attendees and authors coincide, two identical
avatar rows eight lines apart read as a rendering bug. Mono chips under the topic
say "invited to this meeting"; the footer avatars say "spoke on the record".

String handling is deliberately narrow: `len`, slicing on non-negative indices,
`.split`, `.strip`, `.lower`. No `.find` (`jac check` W6002 — it reads as
`Array.find` on the client target) and no negative slice indices.

**Every parser below carries an explicit `cl`, and must keep it.** Codespace
inference colours a declaration client-side only if it uses JSX or an npm
import, and the client pull explicitly *skips* access-tagged declarations — so a
`def:pub` of pure string code is placed on the **server** and compiled into an
RPC endpoint. It type-checks, it renders, and nothing warns: the only symptom is
`POST /function/parse_zoom` in the dev-server log and a network round trip every
time a card opens. `ZoomCard` itself needs no marker; its JSX colours it.
"""

import from .Card {
    CARD_FG, CARD_LINE, CARD_MONO, CARD_MUTED, CARD_PANE, CARD_SANS,
    Chip, avatar_color, day_date
}

cl glob DATE_LABEL: str = "**Date:**";
cl glob TOPIC_LABEL: str = "**Topic:**";
cl glob ATTENDEES_LABEL: str = "**Attendees:**";


# ------------------------------------------------------------------ parser

# `line` is already stripped. True only for a well-formed
# `**[HH:MM:SS] Name:** text` opener — everything else is a continuation, which
# is the safe direction to fail in: a mis-detected turn drops text into a new
# speaker's mouth, a mis-detected continuation only glues it to the right one.
cl def is_turn(line: str) -> bool {
    if len(line) < 15 {
        return False;
    }
    if line[0:3] != "**[" {
        return False;
    }
    if line[5:6] != ":" or line[8:9] != ":" or line[11:12] != "]" {
        return False;
    }
    return line[12:13] == " ";
}

cl def label_value(line: str, label: str) -> str {
    n: int = len(label);
    if len(line) < n or line[0:n] != label {
        return "";
    }
    return line[n:len(line)].strip();
}

"""Body -> `{topic, date, attendees, turns, unparsed}`.

`turns` is `[{id, time, speaker, lines}]`; `lines` always holds at least the
opening line and gains one entry per wrapped continuation. `unparsed` is the
raw body, returned only when not a single turn matched, so that a format this
parser has not seen degrades to legible text instead of a blank card.
"""
cl def:pub parse_zoom(body: str) -> dict[str, any] {
    topic: str = "";
    date: str = "";
    attendees: list[str] = [];
    turns: list[dict[str, any]] = [];

    for raw in body.split("\n") {
        line: str = raw.strip();
        if line == "" or line == "---" {
            continue;
        }

        v: str = label_value(line, DATE_LABEL);
        if v != "" {
            date = v;
            continue;
        }
        v = label_value(line, TOPIC_LABEL);
        if v != "" {
            topic = v;
            continue;
        }
        v = label_value(line, ATTENDEES_LABEL);
        if v != "" {
            for a in v.split(",") {
                name: str = a.strip();
                if name != "" {
                    attendees = attendees + [name];
                }
            }
            continue;
        }

        if is_turn(line) {
            rest: list[str] = line[13:len(line)].split(":**", 1);
            if len(rest) == 2 {
                speaker: str = rest[0].strip();
                text: str = rest[1].strip();
                if speaker != "" and len(speaker) <= 32 {
                    turns = turns + [{
                        "id": str(len(turns)) + "-" + line[3:11],
                        "time": line[3:11],
                        "speaker": speaker,
                        "lines": [text] if text != "" else []
                    }];
                    continue;
                }
            }
        }

        # Not a turn opener. Either preamble chrome we drop, or a wrapped line
        # belonging to the turn above it.
        if len(turns) > 0 {
            last: dict[str, any] = turns[len(turns) - 1];
            last["lines"] = (last["lines"] as list) + [line];
        }
    }

    return {
        "topic": topic,
        "date": date,
        "attendees": attendees,
        "turns": turns,
        "unparsed": body.strip() if len(turns) == 0 else ""
    };
}

"""`title` -> `{topic, date}`, for `Zoom: <topic> (YYYY-MM-DD)`.

A fallback only: the `**Topic:**` line is the authoritative one. The trailing
` (YYYY-MM-DD)` is a fixed 13 characters, so it comes off by length rather than
by a reverse search, and a title shaped any other way passes through whole.
"""
cl def:pub parse_zoom_title(title: str) -> dict[str, str] {
    t: str = title.strip();
    if t[0:6] == "Zoom: " {
        t = t[6:len(t)].strip();
    }
    date: str = "";
    n: int = len(t);
    if n > 13 {
        tail: str = t[n - 13:n];
        if tail[0:2] == " (" and tail[12:13] == ")" {
            date = tail[2:12];
            t = t[0:n - 13].strip();
        }
    }
    return {"topic": t, "date": date};
}

"""Split turn text into alternating plain / backticked runs.

Turn text carries real code — ``required_tags = { "CostCenter" = var.cost_center }``
— and the braces inside it are why this is a hand-written split rather than any
markdown pass. An unbalanced trailing backtick is emitted as literal text with
its backtick restored, because a transcript is not obliged to be valid markdown
and silently eating a character from a quoted command is worse than showing one.
"""
cl def:pub code_spans(text: str) -> list[dict[str, any]] {
    parts: list[str] = text.split("`");
    out: list[dict[str, any]] = [];
    last: int = len(parts) - 1;
    i: int = 0;
    for p in parts {
        if i % 2 == 1 and i != last {
            out = out + [{"t": p, "code": True}];
        } elif i % 2 == 1 {
            out = out + [{"t": "`" + p, "code": False}];
        } elif p != "" {
            out = out + [{"t": p, "code": False}];
        }
        i = i + 1;
    }
    return out;
}


# ------------------------------------------------------------------ pieces

# Calling an imported `def:pub` **by name** emits an HTTP bridge call, even when
# the callee is `cl` and the symbol is already imported from `./Card.js`. Read
# out of the live client bundle: `avatar_color(speaker)` lowered to
# `__jacCallFunction("avatar_color", {"name": speaker})` while the import sat
# unused two lines above it. Binding the function to a local first defeats it —
# same bundle, `let f = avatar_color; return f(name);`, no request. `:pub` is
# what triggers it: the ES backend bridges access-tagged declarations across
# module boundaries, which is the same rule that keeps them off the client pull.
#
# One call per turn, so a ten-turn transcript was ten round trips before this.
# Delete these two shims the day the shell exports helpers the bridge leaves
# alone; nothing else in this file depends on them.
cl def speaker_color(name: str) -> str {
    f: any = avatar_color;
    return f(name) as str;
}

cl def business_day_date(day: int) -> str {
    f: any = day_date;
    return f(day) as str;
}


def TurnLine(text: str, idx: int) -> JsxElement {
    return <div style={{"fontFamily": CARD_SANS, "fontSize": "12px",
                        "lineHeight": "1.62", "color": CARD_FG,
                        "marginTop": "3px" if idx > 0 else "2px",
                        "overflowWrap": "anywhere"}}>
        {for s in code_spans(text) {
            <span key={(s["t"] as str) + str(s["code"])}>
                {if s["code"] {
                    <code style={{"fontFamily": CARD_MONO, "fontSize": "11px",
                                  "background": CARD_PANE, "color": CARD_FG,
                                  "border": "1px solid " + CARD_LINE,
                                  "borderRadius": "3px", "padding": "1px 4px"}}>
                        {s["t"]}
                    </code>
                }}
                {if not s["code"] { <span>{s["t"]}</span> }}
            </span>
        }}
    </div>;
}

# The gutter width is the one measurement in this file: eight monospace digits
# at 10.5px plus the column gap. Fixed, never content-derived — a gutter that
# resizes with its longest timestamp is a gutter that jitters between cards.
def Turn(time: str, speaker: str, lines: list[str]) -> JsxElement {
    return <div style={{"display": "flex", "gap": "10px", "alignItems": "flex-start",
                        "padding": "7px 14px 8px 14px"}}>
        <span style={{"width": "54px", "flexShrink": "0", "fontFamily": CARD_MONO,
                      "fontSize": "10.5px", "lineHeight": "1.6", "color": CARD_MUTED,
                      "fontVariantNumeric": "tabular-nums", "paddingTop": "1px"}}>
            {time}
        </span>
        <div style={{"flex": "1", "minWidth": "0"}}>
            <div style={{"fontFamily": CARD_SANS, "fontSize": "11.5px",
                         "fontWeight": "700", "letterSpacing": "0.01em",
                         "color": speaker_color(speaker)}}>
                {speaker}
            </div>
            {for (i, ln) in enumerate(lines) {
                <TurnLine key={str(i)} text={ln as str} idx={i} />
            }}
            {if len(lines) == 0 {
                <div style={{"fontFamily": CARD_SANS, "fontSize": "12px",
                             "fontStyle": "italic", "color": CARD_MUTED,
                             "marginTop": "2px"}}>
                    {"(no speech recorded)"}
                </div>
            }}
        </div>
    </div>;
}


# ------------------------------------------------------------------ the card

def:pub ZoomCard(c: dict[str, any]) -> JsxElement {
    title: str = (c["title"] as str) if c["title"] else "";
    body: str = (c["body"] as str) if c["body"] else "";
    day: int = (c["day"] as int) if c["day"] else 0;

    parsed: dict[str, any] = parse_zoom(body);
    from_title: dict[str, str] = parse_zoom_title(title);

    topic: str = parsed["topic"] as str;
    if topic == "" {
        topic = from_title["topic"];
    }

    # The date shown is the transcript's own, in the ISO form the artifact
    # records, and only falls back to the walker's business-day calendar when
    # the body carries no date at all. The footer already renders `day` in prose;
    # the header stating the same date in a second format would invite the reader
    # to check whether they agree.
    date: str = parsed["date"] as str;
    if date == "" {
        date = from_title["date"];
    }
    if date == "" {
        date = business_day_date(day);
    }

    attendees: list = parsed["attendees"] as list;
    turns: list = parsed["turns"] as list;
    unparsed: str = parsed["unparsed"] as str;

    return <div>
        <div style={{"padding": "12px 14px 11px 14px"}}>
            <div style={{"display": "flex", "alignItems": "baseline", "gap": "10px"}}>
                <span style={{"flex": "1", "minWidth": "0", "fontFamily": CARD_MONO,
                              "fontSize": "9.5px", "letterSpacing": "0.16em",
                              "color": CARD_MUTED}}>
                    {"ZOOM MEETING"}
                </span>
                {if date != "" {
                    <span style={{"flexShrink": "0", "fontFamily": CARD_MONO,
                                  "fontSize": "10px", "color": CARD_MUTED}}>
                        {date}
                    </span>
                }}
            </div>

            <div style={{"fontFamily": CARD_SANS, "fontSize": "15px",
                         "fontWeight": "600", "lineHeight": "1.3",
                         "color": CARD_FG, "marginTop": "5px"}}>
                {topic if topic != "" else "(untitled meeting)"}
            </div>

            {if len(attendees) > 0 {
                <div style={{"marginTop": "9px"}}>
                    <div style={{"fontFamily": CARD_MONO, "fontSize": "9.5px",
                                 "letterSpacing": "0.14em", "color": CARD_MUTED,
                                 "marginBottom": "5px"}}>
                        {"ATTENDEES · " + str(len(attendees))}
                    </div>
                    <div style={{"display": "flex", "flexWrap": "wrap", "gap": "5px"}}>
                        {for a in attendees {
                            <Chip key={a as str} text={a as str} />
                        }}
                    </div>
                </div>
            }}
        </div>

        {if len(turns) > 0 {
            <div style={{"borderTop": "1px solid " + CARD_LINE,
                         "padding": "3px 0 9px 0"}}>
                {for t in turns {
                    <Turn key={t["id"] as str} time={t["time"] as str}
                          speaker={t["speaker"] as str}
                          lines={t["lines"] as list[str]} />
                }}
            </div>
        }}

        {if len(turns) == 0 and unparsed != "" {
            <pre style={{"margin": "0", "padding": "10px 14px 14px 14px",
                         "borderTop": "1px solid " + CARD_LINE,
                         "fontFamily": CARD_MONO, "fontSize": "11.5px",
                         "lineHeight": "1.55", "color": CARD_MUTED,
                         "whiteSpace": "pre-wrap", "overflowWrap": "anywhere"}}>
                {unparsed}
            </pre>
        }}

        {if len(turns) == 0 and unparsed == "" {
            <div style={{"margin": "0 14px 14px 14px", "padding": "16px 14px",
                         "border": "1px dashed " + CARD_LINE, "borderRadius": "7px",
                         "background": CARD_PANE, "textAlign": "center"}}>
                <div style={{"fontFamily": CARD_MONO, "fontSize": "9.5px",
                             "letterSpacing": "0.16em", "color": CARD_MUTED}}>
                    {"NO TRANSCRIPT"}
                </div>
                <div style={{"fontFamily": CARD_SANS, "fontSize": "12px",
                             "lineHeight": "1.5", "color": CARD_MUTED,
                             "marginTop": "6px"}}>
                    {"This meeting was recorded in the graph, but no transcript text was captured."}
                </div>
            </div>
        }}
    </div>;
}
