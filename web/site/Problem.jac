"""Sections 1 and 2 — the problem, and why search can't reach it.

Section 2's split panel is the argument in one image: the same question asked of
two mechanisms. Both sides are drawn, not animated into existence, because the
claim is structural rather than temporal — the left panel is *always* going to
return something, and that is the point.
"""

glob DEPARTURE: str = """{ "name": "Bill", "departed": "day -579", "reason": "voluntary",
  "knowledge_domains": ["TitanDB", "legacy auth service",
                        "AWS cost structure", "Project Titan"],
  "documented_pct": 0.2 }""";

"""Section 1 — what every retrieval system is built on top of, and what it misses."""
def:pub Problem() -> JsxElement {
    return <section className="sec sec-problem">
        <h2 className="sec-h2">{"Every RAG system indexes what you wrote down."}</h2>
        <p className="big-line">{"Slack. Zendesk. Confluence. Jira. Transcripts."}</p>
        <p className="big-line big-line-muted">{"Then the half that was never written down at all."}</p>

        <pre className="code code-json"><code>{DEPARTURE}</code></pre>

        <p className="caption">
            {"Bill documented one fifth of what he knew. 579 days later, TitanDB caused an incident. Nobody left knew why."}
        </p>
    </section>;
}

"""Section 2 — the mechanism argument, with the split panel."""
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
