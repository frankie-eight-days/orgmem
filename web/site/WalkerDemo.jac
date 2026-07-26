"""Section 7 — the walker, running.

Code on the left, the graph it is walking on the right, one scalar (`step`)
driving both. The point of the pairing is that the highlighted line and the lit
node are the *same fact* shown twice: a reader who does not read Jac can follow
the traversal, and a reader who does can check that the animation matches the
semantics.

The code is `GapScan` from `main.jac`, abridged but not paraphrased — every line
shown appears in the file. The two things cut are the size-cap guard in
`admit()` and the `<-:Refs:<-` / `<-:Produced:<-` reverse traversals, both
because they double the step count without changing what the section teaches.
The comment about the causal closure is kept verbatim; it is the most
load-bearing sentence in the walker.

Syntax highlighting is a hand-tokenised table rather than a highlighter
dependency. That sounds worse than it is: the source is fixed and eight lines
long, an npm highlighter would be ~40kB to colour text that never changes, and
the CSP-free hackathon build has enough moving parts already. The token classes
are the five that carry meaning in Jac — keyword, type, string, comment, edge
reference — and edge references get their own colour because `->:Produced:->`
is the construct this whole section exists to explain.

**The interval is never cleared.** `Landing` mounts this once and never
unmounts it, so there is nothing to leak into; adding teardown would mean
threading a cleanup return through the client codespace's effect handling,
which is not a thing this build does reliably. If this component is ever
reused somewhere it can unmount, that changes.
"""

"""One line of the walker, as (text, class) runs.

Class keys: "k" keyword · "t" type · "s" string · "c" comment · "e" edge
reference · "" plain.
"""
cl glob CODE: list[list[dict[str, str]]] = [
    [{"t": "walker", "c": "k"}, {"t": " GapScan {", "c": ""}],
    [{"t": "    has", "c": "k"}, {"t": " trigger_event_id: ", "c": ""},
     {"t": "str", "c": "t"}, {"t": " = ", "c": ""}, {"t": "\"\"", "c": "s"}, {"t": ";", "c": ""}],
    [{"t": "    has", "c": "k"}, {"t": " window_days: ", "c": ""},
     {"t": "int", "c": "t"}, {"t": " = ", "c": ""}, {"t": "14", "c": "s"}, {"t": ";", "c": ""}],
    [{"t": "    has", "c": "k"}, {"t": " searched: ", "c": ""},
     {"t": "list", "c": "t"}, {"t": "[", "c": ""}, {"t": "str", "c": "t"},
     {"t": "] = [];", "c": ""}],
    [{"t": "    has", "c": "k"}, {"t": " found: ", "c": ""},
     {"t": "list", "c": "t"}, {"t": "[", "c": ""}, {"t": "str", "c": "t"},
     {"t": "] = [];", "c": ""}],
    [{"t": "", "c": ""}],
    [{"t": "    can", "c": "k"}, {"t": " begin ", "c": ""}, {"t": "with", "c": "k"},
     {"t": " ", "c": ""}, {"t": "Hub", "c": "t"}, {"t": " ", "c": ""},
     {"t": "entry", "c": "k"}, {"t": " {", "c": ""}],
    [{"t": "        e: ", "c": ""}, {"t": "Event", "c": "t"},
     {"t": " = EVENTS[", "c": ""}, {"t": "self", "c": "k"},
     {"t": ".trigger_event_id];", "c": ""}],
    [{"t": "        ", "c": ""}, {"t": "self", "c": "k"},
     {"t": ".hi = e.day + ", "c": ""}, {"t": "self", "c": "k"},
     {"t": ".window_days;", "c": ""}],
    [{"t": "        ", "c": ""}, {"t": "visit", "c": "k"}, {"t": " e;", "c": ""}],
    [{"t": "    }", "c": ""}],
    [{"t": "", "c": ""}],
    [{"t": "    # The bounded space is the CAUSAL closure of the trigger:", "c": "c"}],
    [{"t": "    # the artifacts it produced, whatever those reference, and", "c": "c"}],
    [{"t": "    # the events that produced those. Widening it to an", "c": "c"}],
    [{"t": "    # actor/time sweep makes every SILENCE answer \"yes\".", "c": "c"}],
    [{"t": "    can", "c": "k"}, {"t": " at_event ", "c": ""}, {"t": "with", "c": "k"},
     {"t": " ", "c": ""}, {"t": "Event", "c": "t"}, {"t": " ", "c": ""},
     {"t": "entry", "c": "k"}, {"t": " {", "c": ""}],
    [{"t": "        ", "c": ""}, {"t": "for", "c": "k"}, {"t": " a ", "c": ""},
     {"t": "in", "c": "k"}, {"t": " [here ", "c": ""},
     {"t": "->:Produced:->", "c": "e"}, {"t": "] {", "c": ""}],
    [{"t": "            ", "c": ""}, {"t": "self", "c": "k"},
     {"t": ".consider(a);", "c": ""}],
    [{"t": "            ", "c": ""}, {"t": "if", "c": "k"}, {"t": " ", "c": ""},
     {"t": "self", "c": "k"}, {"t": ".admit(a.gid) { ", "c": ""},
     {"t": "visit", "c": "k"}, {"t": " a; }", "c": ""}],
    [{"t": "        }", "c": ""}],
    [{"t": "    }", "c": ""}],
    [{"t": "", "c": ""}],
    [{"t": "    can", "c": "k"}, {"t": " at_artifact ", "c": ""}, {"t": "with", "c": "k"},
     {"t": " ", "c": ""}, {"t": "Artifact", "c": "t"}, {"t": " ", "c": ""},
     {"t": "entry", "c": "k"}, {"t": " {", "c": ""}],
    [{"t": "        ", "c": ""}, {"t": "for", "c": "k"}, {"t": " a ", "c": ""},
     {"t": "in", "c": "k"}, {"t": " [here ", "c": ""},
     {"t": "->:Refs:->", "c": "e"}, {"t": "] {", "c": ""}],
    [{"t": "            ", "c": ""}, {"t": "self", "c": "k"},
     {"t": ".consider(a);", "c": ""}],
    [{"t": "            ", "c": ""}, {"t": "if", "c": "k"}, {"t": " ", "c": ""},
     {"t": "self", "c": "k"}, {"t": ".admit(a.gid) { ", "c": ""},
     {"t": "visit", "c": "k"}, {"t": " a; }", "c": ""}],
    [{"t": "        }", "c": ""}],
    [{"t": "    }", "c": ""}],
    [{"t": "}", "c": ""}]
];

"""The demo graph. Positions are hand-placed — five nodes do not need a
simulation, and a fixed layout means the animation lands identically every
run, which a force layout cannot promise."""
cl glob DEMO_NODES: list[dict[str, any]] = [
    {"id": "evt", "x": 52.0,  "y": 118.0, "label": "incident",   "sub": "day 8",       "kind": "event"},
    {"id": "a1",  "x": 152.0, "y": 52.0,  "label": "#incidents", "sub": "SlackThread", "kind": "slack"},
    {"id": "a2",  "x": 152.0, "y": 186.0, "label": "ENG-112",    "sub": "JiraTicket",  "kind": "jira"},
    {"id": "a3",  "x": 262.0, "y": 50.0,  "label": "CONF-054",   "sub": "runbook",     "kind": "conf"},
    {"id": "a4",  "x": 262.0, "y": 148.0, "label": "PR-106",     "sub": "PullRequest", "kind": "pr"}
];

cl glob DEMO_EDGES: list[dict[str, str]] = [
    {"a": "evt", "b": "a1", "rel": "Produced"},
    {"a": "evt", "b": "a2", "rel": "Produced"},
    {"a": "a1",  "b": "a3", "rel": "Refs"},
    {"a": "a2",  "b": "a4", "rel": "Refs"}
];

"""The traversal, one row per step.

`line` is the code line to highlight, `lit` the nodes visited so far, `edge`
the edge being crossed, `searched` the running count. The final row is the
answer: four artifacts examined, zero of the expected type.
"""
cl glob STEPS: list[dict[str, any]] = [
    {"line": 7,  "lit": [],                            "edge": "",       "searched": 0, "note": "bind the trigger event"},
    {"line": 9,  "lit": ["evt"],                        "edge": "",       "searched": 0, "note": "visit it"},
    {"line": 17, "lit": ["evt"],                        "edge": "",       "searched": 0, "note": "follow Produced"},
    {"line": 19, "lit": ["evt", "a1"],                  "edge": "evt-a1", "searched": 1, "note": "a Slack thread"},
    {"line": 19, "lit": ["evt", "a1", "a2"],            "edge": "evt-a2", "searched": 2, "note": "a Jira ticket"},
    {"line": 24, "lit": ["evt", "a1", "a2"],            "edge": "",       "searched": 2, "note": "follow Refs"},
    {"line": 26, "lit": ["evt", "a1", "a2", "a3"],      "edge": "a1-a3",  "searched": 3, "note": "a runbook, not a postmortem"},
    {"line": 26, "lit": ["evt", "a1", "a2", "a3", "a4"], "edge": "a2-a4",  "searched": 4, "note": "a pull request"},
    {"line": 4,  "lit": ["evt", "a1", "a2", "a3", "a4"], "edge": "",       "searched": 4, "note": "the space is exhausted"}
];

cl def:pub code_lines() -> list[list[dict[str, str]]] { return CODE; }
cl def:pub demo_nodes() -> list[dict[str, any]] { return DEMO_NODES; }
cl def:pub demo_edges() -> list[dict[str, str]] { return DEMO_EDGES; }
cl def:pub steps() -> list[dict[str, any]] { return STEPS; }

"""Narrow a step's `lit` list back to a concrete type — see the same pattern in
`Problem.jac`. Indexing a `dict[str, any]` yields `any`, and `x in any` does not
type-check inside a JSX slot."""
cl def:pub step_lit(s: dict[str, any]) -> list[str] { return s["lit"]; }
cl def:pub code_runs(l: list[dict[str, str]]) -> list[dict[str, str]] { return l; }

"""Node lookup by id, for drawing edges between placed nodes."""
cl def:pub node_at(id: str) -> dict[str, any] {
    for n in DEMO_NODES {
        if n["id"] == id { return n; }
    }
    return {"x": 0.0, "y": 0.0, "label": "", "sub": "", "kind": "", "id": ""};
}

cl def:pub fmt(v: any) -> str { return f"{v:.1f}"; }

def:pub WalkerDemo() -> JsxElement {
    has step: int = 0;

    # The step counter the interval actually reads.
    #
    # `step` alone does not work here. `has` compiles to `useState`, and the
    # closure passed to `setInterval` captures the value of `step` from the
    # render that created it — which is 0, forever. Every tick then computes
    # `0 + 1` and the animation freezes on step 1. Verified before this fix:
    # three headless frames 1.25s apart all reported `visit e`, one lit node.
    #
    # A ref is stable across renders, so the callback reads and writes the live
    # value and assigns the result to state purely to trigger the re-render.
    #
    # (A docstring will not go here — one placed between two `has` declarations
    # is a parse error, `Missing ';'`. Docstrings bind to definitions.)
    has cursor: Ref[any] = Ref();

    all_steps: list[dict[str, any]] = steps();
    lines: list[list[dict[str, str]]] = code_lines();
    nodes: list[dict[str, any]] = demo_nodes();
    edges: list[dict[str, str]] = demo_edges();

    async can with entry {
        w: any = window;
        if w.matchMedia("(prefers-reduced-motion: reduce)").matches {
            # Terminal state, no motion: the whole traversal shown at once.
            step = 8;
            return;
        }
        cursor.current = 0;
        def tick() {
            cursor.current = (cursor.current + 1) % 9;
            step = cursor.current;
        }
        w.setInterval(tick, 1150);
    }

    cur: dict[str, any] = all_steps[step];
    lit: list[str] = step_lit(cur);

    def line_class(i: int) -> str {
        return "wd-line wd-line-on" if i == cur["line"] else "wd-line";
    }

    def node_class(id: str) -> str {
        base: str = "wd-node";
        if id in lit { base = base + " wd-node-on"; }
        if id == "evt" { base = base + " wd-node-trigger"; }
        return base;
    }

    def edge_class(a: str, b: str) -> str {
        key: str = a + "-" + b;
        on: bool = (a in lit) and (b in lit);
        cls: str = "wd-edge wd-edge-on" if on else "wd-edge";
        return cls + " wd-edge-live" if key == cur["edge"] else cls;
    }

    return <section className="sec sec-walk" id="walker">
        <h2 className="sec-h2">{"The retriever is a walker."}</h2>

        <p className="body">
            {"Not a query against a store — an agent moving through the graph, with behaviour attached per node type on arrival. This is GapScan from main.jac, answering \"was a postmortem ever written after the day-8 incident?\". The highlighted line and the lit node are the same step."}
        </p>

        <div className="wd">
            <div className="wd-code">
                <pre className="wd-pre"><code>
                    {for (i, l) in enumerate(lines) {
                        <span className={line_class(i)} key={str(i)}>
                            {for (j, r) in enumerate(code_runs(l)) {
                                <span className={"tok tok-" + r["c"]} key={str(j)}>{r["t"]}</span>
                            }}
                            {"\n"}
                        </span>
                    }}
                </code></pre>
            </div>

            <div className="wd-stage">
                <svg className="wd-svg" viewBox="0 0 330 230" role="img"
                     aria-label="A walker traversing outward from a day-8 incident through the artifacts it produced and what those reference, finding no postmortem.">

                    {#* The bound, drawn. A traversal that cannot show its
                        boundary is not evidence of anything. *#}
                    <rect className="wd-bound" x="14" y="12" width="302" height="206" rx="8" />
                    <text className="wd-bound-label" x="24" y="30">{"bounded causal closure"}</text>

                    {for (i, e) in enumerate(edges) {
                        <line className={edge_class(e["a"], e["b"])} key={e["a"] + e["b"]}
                              x1={fmt(node_at(e["a"])["x"])} y1={fmt(node_at(e["a"])["y"])}
                              x2={fmt(node_at(e["b"])["x"])} y2={fmt(node_at(e["b"])["y"])} />
                    }}

                    {for (i, n) in enumerate(nodes) {
                        <g className={node_class(n["id"] as str)} key={n["id"] as str}>
                            <circle cx={fmt(n["x"])} cy={fmt(n["y"])} r="7" />
                            <text className="wd-label" x={fmt(n["x"])}
                                  y={fmt((n["y"] as float) - 14.0)}>{n["label"]}</text>
                            <text className="wd-sub" x={fmt(n["x"])}
                                  y={fmt((n["y"] as float) + 22.0)}>{n["sub"]}</text>
                        </g>
                    }}
                </svg>

                <div className="wd-read">
                    <p className="wd-note">{cur["note"]}</p>
                    <dl className="wd-counts">
                        <div className="wd-count">
                            <dt>{"searched"}</dt>
                            <dd>{str(cur["searched"])}</dd>
                        </div>
                        <div className={"wd-count" + (" wd-count-zero" if step == 8 else "")}>
                            <dt>{"postmortems found"}</dt>
                            <dd>{"0"}</dd>
                        </div>
                    </dl>
                </div>
            </div>
        </div>

        <blockquote className="pull">
            <p>{"Four artifacts examined, zero of the expected type."}</p>
            <p>{"The bound is what turns that zero into an answer instead of a shrug."}</p>
        </blockquote>

        <ul className="elim">
            {for (i, line) in enumerate([
                "No database. No ORM. No vector store. No prompt strings.",
                "Persistence is reachability from the root node. Retrieval is traversal.",
                "The client calls walkers directly — no REST, no HTTP client, no CORS.",
                "One language, whole stack."
            ]) {
                <li className="elim-line" key={str(i)}>{line}</li>
            }}
        </ul>
    </section>;
}
