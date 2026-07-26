"""OrgMem UI shell — question panel on the left, graph canvas on the right.

Pure presentation: all state and every server call live in `AppScreen`. Every
answer arrives in one shape (verdict / reason / evidence / highlight / path), so
one panel renders all four questions and the canvas always knows what to light
up.

The free-text box resolves a typed question to one of the four walker queries by
keyword and says which one it picked. It is not a natural-language front end and
does not pretend to be one — the four questions below are the ones the graph can
answer, and the box is a faster way to reach them than the buttons.
"""

import from "@jac/runtime" { Link }
import from .GraphCanvas { GraphCanvas }

glob PRESETS: list[dict[str, str]] = [
    {"key": "felix", "label": "Could Felix have known about the CRM touchpoint on day 32?"},
    {"key": "janice", "label": "Could Janice have known about the day-3 design discussion?"},
    {"key": "gap", "label": "Was a Confluence page written after the day-38 gap?"},
    {"key": "titan", "label": "Who knows TitanDB?"}
];

# Keyword → preset. First match wins, so the more specific terms come first.
glob ROUTES: list[dict[str, str]] = [
    {"word": "felix", "key": "felix"},
    {"word": "crm", "key": "felix"},
    {"word": "salesforce", "key": "felix"},
    {"word": "janice", "key": "janice"},
    {"word": "design", "key": "janice"},
    {"word": "confluence", "key": "gap"},
    {"word": "gap", "key": "gap"},
    {"word": "silence", "key": "gap"},
    {"word": "wrote", "key": "gap"},
    {"word": "titandb", "key": "titan"},
    {"word": "titan", "key": "titan"},
    {"word": "knows", "key": "titan"},
    {"word": "bus factor", "key": "titan"}
];

def resolve_preset(text: str) -> str {
    q: str = text.lower();
    for r in ROUTES {
        if r["word"] in q {
            return r["key"];
        }
    }
    return "";
}

# Walkers report their search space verbatim, which for a Slack-heavy channel
# means eight near-identical lines. Distinct lines are the informative ones.
def dedupe(items: list) -> list[str] {
    out: list[str] = [];
    for it in items {
        s: str = it as str;
        if s not in out {
            out.append(s);
        }
        if len(out) >= 8 {
            break;
        }
    }
    return out;
}

def label_for(key: str) -> str {
    for p in PRESETS {
        if p["key"] == key {
            return p["label"];
        }
    }
    return "";
}

def:pub Shell(answer: dict[str, any], busy: bool, graph: dict[str, any],
              active: list[str], walked: list[list[str]],
              hops_done: int, hops_total: int,
              onAsk: Callable[[str], None]) -> JsxElement {

    has query: str = "";

    # Nothing from the server is dotted into unguarded: any walker can come back
    # None, empty or half-shaped, and one bad subscript takes down the page.
    verdict: str = (answer["verdict"] as str) if (answer and answer["verdict"]) else "";
    raw_evidence: list = (answer["evidence"] as list) if (answer and answer["evidence"]) else [];
    evidence: list = dedupe(raw_evidence);
    hidden: int = len(raw_evidence) - len(evidence);
    gnodes: list = (graph["nodes"] as list) if (graph and graph["nodes"]) else [];
    glinks: list = (graph["links"] as list) if (graph and graph["links"]) else [];
    matched: str = resolve_preset(query);

    def handle_query(e: ChangeEvent) {
        query = e.target.value;
    }

    def handle_submit(e: FormEvent) {
        e.preventDefault();
        key: str = resolve_preset(query);
        if key != "" {
            onAsk(key);
        }
    }

    return <div style={{"display": "flex", "height": "100vh", "width": "100vw",
                        "fontFamily": "system-ui, sans-serif",
                        "background": "#0b0e14", "color": "#dbe3f0"}}>
        <aside style={{"width": "400px", "flexShrink": "0", "padding": "24px",
                       "overflowY": "auto", "borderRight": "1px solid #1e2534",
                       "boxSizing": "border-box"}}>
            <div style={{"display": "flex", "alignItems": "baseline",
                         "justifyContent": "space-between"}}>
                <h1 style={{"fontSize": "18px", "letterSpacing": "0.12em",
                            "margin": "0 0 4px 0"}}>{"ORGMEM"}</h1>
                <Link to="/" style={{"fontSize": "11px", "opacity": "0.5",
                                     "color": "#dbe3f0", "textDecoration": "none"}}>
                    {"← about"}
                </Link>
            </div>
            <p style={{"fontSize": "12px", "opacity": "0.55", "margin": "0 0 20px 0"}}>
                {"who knows what · where it is written · where it is not"}
            </p>

            <form onSubmit={handle_submit}>
                <input value={query} onChange={handle_query}
                       placeholder="Ask the graph…"
                       style={{"width": "100%", "boxSizing": "border-box",
                               "padding": "10px 12px", "marginBottom": "6px",
                               "background": "#0e131e", "color": "#dbe3f0",
                               "border": "1px solid #26304a", "borderRadius": "8px",
                               "fontSize": "13px", "outline": "none"}} />
            </form>
            <p style={{"fontSize": "11px", "opacity": "0.45", "margin": "0 0 14px 0",
                       "minHeight": "15px"}}>
                {("↵ runs: " + label_for(matched)) if (query != "" and matched != "")
                 else ("no walker matches that — try one below" if query != "" else "")}
            </p>

            {for p in PRESETS {
                <PresetButton key={p["key"]} pkey={p["key"]} label={p["label"]}
                              onAsk={onAsk} />
            }}

            <p style={{"fontSize": "12px", "opacity": "0.6", "marginTop": "18px",
                       "minHeight": "16px"}}>
                {"walking the graph…" if busy else ""}
            </p>

            {if verdict != "" {
                <div style={{"marginTop": "8px", "paddingTop": "16px",
                             "borderTop": "1px solid #1e2534"}}>
                    <p style={{"fontSize": "12px", "opacity": "0.6",
                               "margin": "0 0 8px 0"}}>{answer["title"]}</p>
                    <p style={{"fontSize": "17px", "fontWeight": "600",
                               "margin": "0 0 8px 0", "color": "#ffd166"}}>{verdict}</p>
                    <p style={{"fontSize": "13px", "lineHeight": "1.55",
                               "margin": "0 0 14px 0"}}>{answer["reason"]}</p>
                    <p style={{"fontSize": "11px", "letterSpacing": "0.1em",
                               "opacity": "0.5", "margin": "0 0 6px 0"}}>
                        {"EVIDENCE · " + str(len(evidence)) + " shown"
                         + ((" of " + str(len(raw_evidence))) if hidden > 0 else "")}
                    </p>
                    {for (i, ev) in enumerate(evidence) {
                        <div key={str(i)}
                             style={{"fontSize": "12px", "fontFamily": "ui-monospace, monospace",
                                     "padding": "4px 0", "borderBottom": "1px solid #141a26",
                                     "opacity": "0.85"}}>{ev}</div>
                    }}
                </div>
            }}
        </aside>

        <section style={{"flex": "1", "position": "relative"}}>
            <GraphCanvas data={graph} active={active} walked={walked} />
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
    </div>;
}

def:pub PresetButton(pkey: str, label: str, onAsk: Callable[[str], None]) -> JsxElement {
    def handle(e: MouseEvent) {
        onAsk(pkey);
    }
    return <button onClick={handle}
                   style={{"display": "block", "width": "100%", "textAlign": "left",
                           "padding": "10px 12px", "marginBottom": "8px",
                           "background": "#131824", "color": "#dbe3f0",
                           "border": "1px solid #26304a", "borderRadius": "8px",
                           "fontSize": "13px", "lineHeight": "1.4",
                           "cursor": "pointer"}}>{label}</button>;
}
