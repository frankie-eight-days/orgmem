"""OrgMem UI shell — chat pane on the left, graph canvas on the right.

Pure presentation: all state and every server call live in `AppScreen`.

The pane is a conversation, but it is not a chatbot. Each turn is sent to
`chat` on the server, which resolves it to a typed intent — which walker, which
arguments — and spawns that walker; the verdict, the citation and the searched
space all come back out of the traversal. The `route` line under each answer is
the walker call the sentence resolved to, printed so the audience can see that
the sentence became a traversal and not a prompt.

The chips are the same path as typing: they send their own text through the
same parser. They are prefilled questions, not a second code path — so a chip
that works proves the typed version works too.
"""

import from react { useEffect }
import from "@jac/runtime" { Link }
import from .GraphCanvas { GraphCanvas }
import from .card.Card { Card }

# Prefilled questions. Each one is sent as literal text through `chat`, so the
# demo is exercising the parser rather than bypassing it.
glob CHIPS: list[str] = [
    "What tools do you have access to on the graph?",
    "Where are we most exposed if someone quits tomorrow?",
    "How is Janice connected to Bill?",
    "Which incidents never got a postmortem?",
    "Was Janice ever given an onboarding session?",
    "Who knows TitanDB?"
];

# Offered after an answer that came back an absence. A proven "no" always
# raises the same next question, and it is the one the graph answers best.
glob FOLLOWUP: str = "Who would be the best person to do it?";

# Walkers report their search space verbatim, which for a Slack-heavy channel
# means eight near-identical lines. Distinct lines are the informative ones.
def dedupe(items: list) -> list[str] {
    out: list[str] = [];
    for it in items {
        s: str = it as str;
        if s not in out {
            out.append(s);
        }
        if len(out) >= 6 {
            break;
        }
    }
    return out;
}

def:pub Shell(answer: dict[str, any], busy: bool, graph: dict[str, any],
              active: list[str], walked: list[list[str]],
              hops_done: int, hops_total: int,
              thread: list, onSend: Callable[[str], None],
              live: dict[str, any] = {}, turnAt: int = 0, turnMax: int = 0,
              onReset: any = None,
              card: dict[str, any] = {}, cx: float = 0.0, cy: float = 0.0,
              onNodeClick: any = None, onOpenRef: any = None,
              onCloseCard: any = None) -> JsxElement {

    has query: str = "";

    gnodes: list = (graph["nodes"] as list) if (graph and graph["nodes"]) else [];
    glinks: list = (graph["links"] as list) if (graph and graph["links"]) else [];

    # See the note in `AppScreen`: `{}` is truthy in JS and `len()` on a
    # client-side object is undefined, so emptiness is a field test, written in
    # two steps so the `and` never lands in the ternary's condition.
    raw_gid: any = card["gid"] if card else "";
    card_gid: str = (raw_gid as str) if raw_gid else "";

    # Tool calls made by the turn currently in flight. Counted rather than
    # tested for emptiness, for the same reason as `card`: `{}` is truthy in JS
    # and `len()` on a client-side object is undefined, but `len()` on a real
    # array is not.
    raw_live: any = live["trace"] if live else [];
    live_steps: int = len(raw_live as list) if raw_live else 0;

    # The follow-up is offered only when the last answer was an absence, which
    # is exactly when "so who should do it?" is the real next question.
    last_no: bool = False;
    if len(thread) > 0 {
        tail: dict[str, any] = thread[len(thread) - 1];
        last_no = (tail["role"] == "bot") and ("NO" in (tail["verdict"] as str));
    }

    # Keep the newest turn in view. The trace streams in a tool call at a time
    # and a twelve-way fan-out is taller than the pane, so without this the
    # answer lands below the fold and the room watches a blank gap.
    # Keyed on `live` too, not just `thread` — the growth happens DURING the
    # turn, which is exactly when the thread has not changed.
    useEffect(lambda {
        el: any = document.getElementById("chat-scroll");
        if el {
            el.scrollTop = el.scrollHeight;
        }
        return lambda {  };
    }, [thread, live, busy]);

    def handle_query(e: ChangeEvent) {
        query = e.target.value;
        # Grow the box to fit what has been typed. A `<textarea>` does not
        # auto-size, so height is reset to `auto` first — without that reset it
        # only ever ratchets upward and never shrinks when the text is deleted.
        el: any = e.target;
        el.style.height = "auto";
        el.style.height = str(min(el.scrollHeight as int, 132)) + "px";
    }

    # Enter sends, Shift+Enter breaks the line. A textarea's default is the
    # opposite, and the default is wrong here: the box is a question field
    # people type one sentence into, not a document editor.
    def handle_key(e: any) {
        if (e.key as str) == "Enter" and not e.shiftKey {
            e.preventDefault();
            if query != "" and not busy {
                onSend(query);
                query = "";
                el2: any = e.target;
                el2.style.height = "auto";
            }
        }
    }

    def handle_submit(e: FormEvent) {
        e.preventDefault();
        if query != "" and not busy {
            onSend(query);
            query = "";
        }
    }

    return <div style={{"display": "flex", "height": "100vh", "width": "100vw",
                        "fontFamily": "system-ui, sans-serif",
                        "background": "#0b0e14", "color": "#dbe3f0"}}>
        <aside style={{"width": "420px", "flexShrink": "0",
                       "display": "flex", "flexDirection": "column",
                       "borderRight": "1px solid #1e2534",
                       "boxSizing": "border-box"}}>

            <div style={{"padding": "20px 22px 12px 22px",
                         "borderBottom": "1px solid #1e2534"}}>
                <div style={{"display": "flex", "alignItems": "baseline",
                             "justifyContent": "space-between"}}>
                    <h1 style={{"fontSize": "18px", "letterSpacing": "0.12em",
                                "margin": "0 0 4px 0"}}>{"ORGMEM"}</h1>
                    <div style={{"display": "flex", "gap": "12px",
                                 "alignItems": "baseline"}}>
                        {if len(thread) > 0 {
                            <ResetButton onReset={onReset} />
                        }}
                        <Link to="/" style={{"fontSize": "11px", "opacity": "0.5",
                                             "color": "#dbe3f0", "textDecoration": "none"}}>
                            {"← about"}
                        </Link>
                    </div>
                </div>
                <p style={{"fontSize": "12px", "opacity": "0.55", "margin": "0"}}>
                    {"ask in english · answered by a walker, not a model"}
                </p>
            </div>

            <div id="chat-scroll"
                 style={{"flex": "1", "overflowY": "auto", "padding": "18px 22px"}}>
                {if len(thread) == 0 {
                    <div>
                        <p style={{"fontSize": "12px", "opacity": "0.5",
                                   "margin": "0 0 12px 0", "lineHeight": "1.5"}}>
                            {"Every answer below is a graph traversal. Ask one of these, or type your own — the same parser handles both."}
                        </p>
                        {for c in CHIPS {
                            <ChipButton key={c} label={c} onSend={onSend} />
                        }}
                    </div>
                }}

                {for (i, m) in enumerate(thread) {
                    <Bubble key={str(i)} msg={m} onSend={onSend} />
                }}

                {if live_steps > 0 {
                    <Bubble msg={live} onSend={onSend} />
                }}

                {if busy {
                    <p style={{"fontSize": "12px", "opacity": "0.6",
                               "margin": "8px 0",
                               "display": "flex", "gap": "8px"}}>
                        <span>
                            {"walking the graph…" if live_steps > 0
                             else "reading the question…"}
                        </span>
                        {if turnMax > 0 {
                            <span style={{"fontFamily": "ui-monospace, monospace",
                                          "opacity": "0.7", "color": "#7fb2ff"}}>
                                {"turn " + str(turnAt) + " / " + str(turnMax)}
                            </span>
                        }}
                    </p>
                }}

                {if last_no and not busy {
                    <div style={{"marginTop": "6px"}}>
                        <p style={{"fontSize": "10px", "letterSpacing": "0.1em",
                                   "opacity": "0.4", "margin": "0 0 6px 0"}}>
                            {"FOLLOW UP"}
                        </p>
                        <ChipButton label={FOLLOWUP} onSend={onSend} />
                    </div>
                }}
            </div>

            <form onSubmit={handle_submit}
                  style={{"padding": "14px 22px 18px 22px",
                          "borderTop": "1px solid #1e2534"}}>
                {#* A textarea, not an input. `<input>` scrolls a long question
                    sideways under the caret, so the beginning of your own
                    sentence disappears while you are still typing it. This
                    wraps, grows to a 132px ceiling, then scrolls.

                    The placeholder names a question the graph can actually
                    answer rather than describing the box — "Ask the graph…"
                    tells a visitor what the widget is, which they can already
                    see, and nothing about what it is FOR. *#}
                <textarea value={query} onChange={handle_query}
                          onKeyDown={handle_key}
                          rows={1}
                          placeholder="Who else knows redis-cache?"
                          style={{"width": "100%", "boxSizing": "border-box",
                                  "padding": "11px 13px",
                                  "background": "#0e131e", "color": "#dbe3f0",
                                  "border": "1px solid #26304a", "borderRadius": "8px",
                                  "fontSize": "13px", "outline": "none",
                                  "fontFamily": "inherit", "lineHeight": "1.5",
                                  "resize": "none", "overflowY": "auto",
                                  "minHeight": "42px", "maxHeight": "132px",
                                  "display": "block"}} />
                <p style={{"fontSize": "10px", "opacity": "0.32", "margin": "7px 2px 0",
                           "fontFamily": "ui-monospace, monospace"}}>
                    {"enter to ask · shift+enter for a new line"}
                </p>
            </form>
        </aside>

        <section style={{"flex": "1", "position": "relative"}}>
            <GraphCanvas data={graph} active={active} walked={walked}
                         running={hops_total > 0 and hops_done < hops_total}
                         onNodeClick={onNodeClick} />
            <div style={{"position": "absolute", "bottom": "12px", "left": "16px",
                         "fontSize": "12px", "opacity": "0.6"}}>
                {(str(len(active)) + " of " + str(len(gnodes))
                  + " nodes on the walked path") if len(active) > 0
                 else (str(len(gnodes)) + " nodes · " + str(len(glinks)) + " edges")}
            </div>
            {if hops_total > 0 {
                <div style={{"position": "absolute", "top": "16px", "right": "20px",
                             "fontSize": "12px", "fontFamily": "ui-monospace, monospace",
                             "padding": "6px 10px", "borderRadius": "6px",
                             "background": "rgba(11,14,20,0.8)",
                             "border": "1px solid #26304a", "color": "#ffd166"}}>
                    {"hop " + str(hops_done) + " / " + str(hops_total)}
                </div>
            }}
        </section>

        {if card_gid != "" {
            <Card key={card_gid} payload={card} x={cx} y={cy}
                  onClose={onCloseCard} docked={False} onOpenRef={onOpenRef} />
        }}
    </div>;
}


# The model answers in markdown and HTML collapses newlines, so a five-item
# tool list arrived as one run-on paragraph with stray backticks and asterisks
# in it. This is the smallest renderer that fixes it honestly: lines, bullets,
# and one inline emphasis style.
#
# `**bold**` is normalised to backticks rather than given its own style. Every
# bold span the model actually emits is a tool or field name — the same thing
# the backticks mark — so collapsing them to one treatment is more consistent
# than honouring both, and halves the parsing.
def:pub Rich(text: str, dim: bool = False) -> JsxElement {
    lines: list[str] = text.replace("**", "`").split("\n");
    return <div>
        {for (i, raw) in enumerate(lines) {
            <RichLine key={str(i)} raw={raw} dim={dim} />
        }}
    </div>;
}


def:pub RichLine(raw: str, dim: bool = False) -> JsxElement {
    line: str = raw.strip();
    if line == "" {
        return <div style={{"height": "8px"}} />;
    }

    bullet: bool = line.startswith("- ") or line.startswith("* ");
    body: str = line[2:] if bullet else line;

    # Odd indices are what sat between a pair of backticks.
    parts: list[str] = body.split("`");

    return <div style={{"display": "flex", "gap": "7px",
                        "margin": "0 0 5px 0",
                        "fontSize": "13px", "lineHeight": "1.5",
                        "opacity": "0.55" if dim else "1"}}>
        {if bullet {
            <span style={{"color": "#7fb2ff", "flexShrink": "0"}}>{"·"}</span>
        }}
        <span>
            {for (j, p) in enumerate(parts) {
                <span key={str(j)}
                      style={{"fontFamily": "ui-monospace, monospace",
                              "color": "#9ecbff", "fontSize": "12px"}
                             if j % 2 == 1 else {}}>{p}</span>
            }}
        </span>
    </div>;
}


# Back to the opening state. Shown only once there is something to reset, so
# the header is quiet on first load — the pane should open on the questions,
# not on its own controls.
def:pub ResetButton(onReset: any = None) -> JsxElement {
    def handle(e: MouseEvent) {
        if onReset {
            onReset();
        }
    }
    return <button onClick={handle}
                   style={{"fontSize": "11px", "cursor": "pointer",
                           "padding": "2px 8px", "borderRadius": "6px",
                           "background": "transparent", "color": "#8fa3c4",
                           "border": "1px solid #26304a"}}>
        {"↺ new chat"}
    </button>;
}


def:pub ChipButton(label: str, onSend: Callable[[str], None]) -> JsxElement {
    def handle(e: MouseEvent) {
        onSend(label);
    }
    return <button onClick={handle}
                   style={{"display": "block", "width": "100%", "textAlign": "left",
                           "padding": "9px 11px", "marginBottom": "8px",
                           "background": "#131824", "color": "#dbe3f0",
                           "border": "1px solid #26304a", "borderRadius": "8px",
                           "fontSize": "12px", "lineHeight": "1.4",
                           "cursor": "pointer"}}>{label}</button>;
}


# One turn. A user turn is the sentence; an assistant turn is the walker's
# verdict, the sentence the answer resolves to, its citations, and the walker
# call it came from.
def:pub Bubble(msg: dict[str, any], onSend: Callable[[str], None]) -> JsxElement {
    role: str = msg["role"] as str;
    if role == "user" {
        return <div style={{"marginBottom": "16px", "display": "flex",
                            "justifyContent": "flex-end"}}>
            <div style={{"maxWidth": "88%", "padding": "8px 11px",
                         "borderRadius": "10px", "background": "#1c2740",
                         "fontSize": "13px", "lineHeight": "1.45"}}>
                {msg["text"]}
            </div>
        </div>;
    }

    verdict: str = (msg["verdict"] as str) if msg["verdict"] else "";
    evidence: list[str] = dedupe((msg["evidence"] as list) if msg["evidence"] else []);
    # Present only on the help and out-of-scope answers, and absent entirely on
    # every walker answer — so it is read defensively, not indexed.
    chips: list[str] = (msg["chips"] as list[str]) if msg["chips"] else [];
    # The tools the agent actually called, in order. This is the derivation,
    # so it is rendered ABOVE the answer — the panel reads top to bottom the
    # way the work happened.
    steps: list[dict[str, any]] = (msg["trace"] as list[dict[str, any]]) if msg["trace"] else [];

    return <div style={{"marginBottom": "20px"}}>
        {if len(steps) > 0 {
            <div style={{"marginBottom": "12px", "paddingLeft": "10px",
                         "borderLeft": "2px solid #26304a"}}>
                {for (i, s) in enumerate(steps) {
                    <div key={str(i)} style={{"marginBottom": "5px"}}>
                        <p style={{"fontSize": "11px", "margin": "0",
                                   "fontFamily": "ui-monospace, monospace",
                                   "color": "#7fb2ff"}}>
                            {(s["tool"] as str) + "(" + (s["args"] as str) + ")"}
                        </p>
                        <p style={{"fontSize": "11px", "margin": "1px 0 0 0",
                                   "opacity": "0.55"}}>
                            {"↳ " + (s["note"] as str)}
                        </p>
                    </div>
                }}
            </div>
        }}
        {if verdict != "" {
            <p style={{"fontSize": "16px", "fontWeight": "600",
                       "margin": "0 0 6px 0", "color": "#ffd166"}}>{verdict}</p>
        }}
        <div style={{"margin": "0 0 10px 0"}}>
            <Rich text={msg["text"] as str} dim={False} />
        </div>
        {if msg["reason"] {
            <div style={{"margin": "0 0 10px 0",
                         "paddingLeft": "10px",
                         "borderLeft": "2px solid #1e2534"}}>
                <Rich text={msg["reason"] as str} dim={True} />
            </div>
        }}
        {if len(chips) > 0 {
            <div style={{"marginTop": "4px"}}>
                {for c in chips {
                    <ChipButton key={c} label={c} onSend={onSend} />
                }}
            </div>
        }}
        {if len(evidence) > 0 {
            <div>
                <p style={{"fontSize": "10px", "letterSpacing": "0.1em",
                           "opacity": "0.4", "margin": "0 0 4px 0"}}>{"CITED"}</p>
                {for (i, ev) in enumerate(evidence) {
                    <div key={str(i)}
                         style={{"fontSize": "11px",
                                 "fontFamily": "ui-monospace, monospace",
                                 "padding": "3px 0", "opacity": "0.8",
                                 "borderBottom": "1px solid #141a26"}}>{ev}</div>
                }}
            </div>
        }}
        {if msg["route"] {
            <p style={{"fontSize": "10px", "fontFamily": "ui-monospace, monospace",
                       "opacity": "0.45", "margin": "10px 0 0 0",
                       "wordBreak": "break-all"}}>
                {"↳ " + (msg["route"] as str)}
            </p>
        }}
    </div>;
}
