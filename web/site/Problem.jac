"""Section 2 — the same moment, read two ways.

The earlier draft of this section put two columns of *counts* side by side —
4,966 artifacts against 10,941 events. It was true and it was abstract, and a
reader arriving with no idea what this product does cannot get anything from two
numbers they have no feel for.

So it is one concrete moment instead. On the left, a real Slack message from the
corpus, in Slack's own chrome. On the right, the three events that same message
actually surfaced, as orgforge records them. Both sides are the same eleven
seconds of company time. Your stack keeps the left one and has no representation
at all for the right one.

Everything quoted is real and checkable:

  left    slack_digital-hq_2026-03-16T13:06:00 — Jax, verbatim
  right   three `knowledge_gap_detected` rows from `event_log`, all three
          carrying `triggered_by` equal to that thread id

That last detail is the reason this pairing works rather than merely
illustrating: the corpus itself asserts the link between the artifact and the
events. We are not drawing the connection, we are reading it.

The counts survive as a strip beneath, where they now land as scale for
something the reader has already seen rather than as the argument itself.
"""

import from .SiteCard { SiteCard }

"""What the corpus stores about that moment: one message."""
cl glob WRITTEN_LINES: list[str] = [
    "stuck on ksql query latency spikes — seeing 2-3s tail when",
    "pulling telemetry from kafka into titandb, prometheus shows",
    "consumer lag climbing, any idea where the bottleneck lives..."
];

"""What orgmem builds from that one message.

An earlier draft put orgforge's own `knowledge_gap_detected` rows here under the
heading "what happened". That was wrong, and wrong in the way that matters: the
simulator emitted those events, not us. Showing them as our output would have
been claiming credit for the dataset's answer key on the page whose entire
argument is that our numbers are checkable. They are how we are *scored*, not
what we produce.

What we actually produce from this message is the edges below. Every one is
derivable from the artifact itself and nothing here required a model:

  Authored    the thread's `user` field is "Jax"
  InChannel   its `channel` field is "digital-hq"
  Mentions    the text contains "titandb", which is one of the ten registered
              knowledge domains; "kafka" and "prometheus" are not registered
              domains and so are deliberately NOT claimed as Mentions edges
  MemberOf    Jax's department, from the people table

The fourth row is the point — once TitanDB is a node rather than a string, the
former owner and the thirty-five people with demonstrated engagement are one
hop away, and none of that is written in the message.
"""
cl glob EXTRACTED: list[dict[str, any]] = [
    {
        "edge": "Authored",
        "hot": False,
        "rows": [{"k": "Jax", "v": "→ this thread"}]
    },
    {
        "edge": "InChannel",
        "hot": False,
        "rows": [{"k": "this thread", "v": "→ #digital-hq"}]
    },
    {
        "edge": "Mentions",
        "hot": True,
        "rows": [{"k": "this thread", "v": "→ TitanDB"}]
    },
    {
        "edge": "…and TitanDB is now reachable",
        "hot": True,
        "rows": [
            {"k": "former owner",   "v": "Bill — departed, 20% documented"},
            {"k": "known by",       "v": "35 people, rankable by engagement"},
            {"k": "current owner",  "v": "Janice"}
        ]
    }
];

cl def:pub written_lines() -> list[str] { return WRITTEN_LINES; }
cl def:pub extracted() -> list[dict[str, any]] { return EXTRACTED; }

"""Narrow one event's rows back to a concrete type.

`HAPPENED_EVENTS` has to be `list[dict[str, any]]` because its values are a mix
of str, bool and list. Indexing that gives `any`, and iterating `any` yields a
loop variable the checker types as `_T`, which is not subscriptable — so
`r["k"]` inside the JSX fails to compile. Passing it back through a function
with a declared return type is what restores the element type; there is nowhere
to put a local annotation inside a JSX statement slot.
"""
cl def:pub ev_rows(e: dict[str, any]) -> list[dict[str, str]] {
    return e["rows"];
}

def:pub Problem() -> JsxElement {
    lines: list[str] = written_lines();
    edges: list[dict[str, any]] = extracted();

    return <section className="sec sec-problem" id="problem">
        <h2 className="sec-h2">{"Your stack indexes what was written. Not what happened."}</h2>

        <p className="body">
            {"Day 53. Jax posts one message in #digital-hq. Every retrieval system you have will store it, embed it, and hand it back when someone searches for kafka latency — as one chunk of text, related to other chunks of text. Here is what orgmem reads out of the same message instead."}
        </p>

        <div className="vs">
            <div className="vs-side">
                <p className="vs-head">{"What was written"}</p>

                <SiteCard kind="slack" head="#digital-hq"
                          meta="day 53 · 2026-03-16 13:06"
                          people={["Jax"]}>
                    <div className="vs-msg">
                        {for (i, line) in enumerate(lines) {
                            <p className="vs-line" key={str(i)}>{line}</p>
                        }}
                    </div>
                </SiteCard>

                <p className="vs-foot">
                    {"One artifact. Indexed, embedded, retrievable — today, by anything."}
                </p>
            </div>

            <div className="vs-side vs-side-right">
                <p className="vs-head vs-head-accent">{"What orgmem reads out of it"}</p>

                <div className="ev-stack">
                    {for (i, e) in enumerate(edges) {
                        <div className={"ev" + (" ev-hot" if e["hot"] else "")} key={str(i)}>
                            <p className="ev-type">{e["edge"]}</p>
                            <ul className="ev-rows">
                                {for (j, r) in enumerate(ev_rows(e)) {
                                    <li className="ev-row" key={str(j)}>
                                        <span className="ev-k">{r["k"]}</span>
                                        <span className="ev-v">{r["v"]}</span>
                                    </li>
                                }}
                            </ul>
                        </div>
                    }}
                </div>

                <p className="vs-foot vs-foot-accent">
                    {"Three typed edges, no model involved. The fourth box is not in the message — it is what the third edge makes reachable."}
                </p>
            </div>
        </div>

        <div className="scale">
            <p className="scale-item">
                <span className="scale-n">{"4,966"}</span>
                <span className="scale-l">{"artifacts your stack can already see"}</span>
            </p>
            <p className="scale-item scale-item-accent">
                <span className="scale-n">{"10,941"}</span>
                <span className="scale-l">{"events over the same sixty days that it cannot"}</span>
            </p>
        </div>

        <blockquote className="pull">
            <p>{"A missing metric and a healthy metric look identical if you only query for what exists."}</p>
            <p>{"Every other layer of your stack has observability. The organization does not."}</p>
        </blockquote>

        {#* Credit where it belongs. orgforge emits its own ground-truth event
            stream — knowledge gaps, departures, incidents — and an earlier
            version of this section displayed those rows as though they were our
            output. They are not: they are the answer key we are scored against.
            Saying so costs nothing and is the difference between a claim that
            survives inspection and one that does not. *#}
        <p className="note">
            {"orgforge also ships a ground-truth event stream for these sixty days — knowledge gaps, departures, incident chains. That is the answer key orgmem is scored against, not something orgmem produces. Everything in the right-hand column above is derived from the artifact itself."}
        </p>
    </section>;
}

#*
Section 2's original split panel (similarity vs traversal), retired when the
site moved to the observability framing. Both SVGs are hand-tuned and their
`.split` / `.panel` / `.chunks` rules are still in `styles.jac`, so restoring
this is uncommenting plus one import.

def:pub WhySearch() -> JsxElement {
    return <section className="sec sec-search">
        <h2 className="sec-h2 sec-h2-wide">
            {"Retrieval can fail to find something. It cannot prove nothing is there."}
        </h2>

        <p className="body">
            {"Ask \"was a postmortem ever written?\" and vector search returns the nearest chunk — because top-k similarity is never exhaustive and never returns nothing. The model reads plausible context and says yes."}
        </p>

        <blockquote className="pull">
            <p>{"A graph answers by walking a bounded space and counting zero."}</p>
            <p>{"Zero neighbours is a fact, not a failure."}</p>
        </blockquote>

        <div className="split">
            <figure className="panel">
                <svg className="panel-svg" viewBox="0 0 320 200" role="img"
                     aria-label="A query vector reaching into a cloud of chunks and grabbing the nearest one.">
                    <g className="chunks">
                        <circle cx="196" cy="52" r="3" /><circle cx="238" cy="74" r="3" />
                        <circle cx="171" cy="96" r="3" /><circle cx="252" cy="122" r="3" />
                        <circle cx="209" cy="141" r="3" /><circle cx="286" cy="96" r="3" />
                        <circle cx="224" cy="34" r="3" /><circle cx="176" cy="150" r="3" />
                        <circle cx="268" cy="46" r="3" /><circle cx="243" cy="164" r="3" />
                        <circle cx="292" cy="140" r="3" /><circle cx="152" cy="66" r="3" />
                    </g>
                    <circle className="query" cx="42" cy="100" r="5" />
                    <path className="reach" d="M 47 100 L 166 96" />
                    <circle className="hit" cx="171" cy="96" r="9" />
                    <text className="svg-label" x="20" y="128">{"query"}</text>
                    <text className="svg-label svg-label-accent" x="150" y="76">{"nearest chunk"}</text>
                </svg>
                <figcaption className="panel-cap">
                    {"top-k similarity · always returns something"}
                </figcaption>
            </figure>

            <figure className="panel">
                <svg className="panel-svg" viewBox="0 0 320 200" role="img"
                     aria-label="A walker traversing outward from a node, reaching the boundary, and returning empty.">
                    <circle className="bound" cx="120" cy="100" r="76" />
                    <g className="edges">
                        <path d="M 120 100 L 176 62" /><path d="M 120 100 L 184 118" />
                        <path d="M 120 100 L 96 40" /><path d="M 120 100 L 66 132" />
                        <path d="M 176 62 L 168 34" /><path d="M 184 118 L 172 158" />
                        <path d="M 66 132 L 58 166" />
                    </g>
                    <g className="graph-nodes">
                        <circle cx="176" cy="62" r="3.5" /><circle cx="184" cy="118" r="3.5" />
                        <circle cx="96" cy="40" r="3.5" /><circle cx="66" cy="132" r="3.5" />
                        <circle cx="168" cy="34" r="3.5" /><circle cx="172" cy="158" r="3.5" />
                        <circle cx="58" cy="166" r="3.5" />
                    </g>
                    <circle className="origin" cx="120" cy="100" r="6" />
                    <text className="svg-label" x="94" y="122">{"trigger"}</text>
                    <text className="zero" x="252" y="108">{"0"}</text>
                    <text className="svg-label svg-label-accent" x="228" y="128">{"postmortems"}</text>
                </svg>
                <figcaption className="panel-cap">
                    {"bounded traversal · returns nothing, and means it"}
                </figcaption>
            </figure>
        </div>
    </section>;
}
*#
