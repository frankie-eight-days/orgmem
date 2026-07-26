"""Section 3b — what the arrows actually mean.

The moving graph either side of this section is doing the "look, a graph" job
already. This element's only job is the thing a force simulation is structurally
incapable of showing: that the nodes are *typed*, that the edges are *named*, and
that the names are what make a traversal answerable.

Five edges are drawn, not thirteen. The full set is listed underneath in mono,
because a marketing diagram that renders every edge type is a diagram nobody
reads — but omitting them entirely would misrepresent the schema to exactly the
audience most likely to check. Drawn is a subset; stated is complete.

`DepartedWith` is drawn in the accent and dashed because it is the only edge on
the diagram that describes an absence, and it is the one the case study above
turns on. Everything else on this page is a fact about what exists.

Node and edge names are copied from the archetype declarations, not paraphrased.
"""

"""The eight concrete artifact types, all sharing the `Artifact` base."""
cl glob ARTIFACT_TYPES: list[str] = [
    "SlackThread", "Email", "ConfluencePage", "JiraTicket",
    "ZoomTranscript", "PullRequest", "ZDTicket", "SFOpportunity"
];

"""Every edge archetype in the graph, drawn or not."""
cl glob EDGE_TYPES: list[str] = [
    "Authored", "Refs", "Mentions", "Involves", "MemberOf", "Concerns",
    "Produced", "Relates", "CoOccurs", "InChannel", "Subscribes",
    "Estranged", "DepartedWith"
];

cl def:pub artifact_types() -> list[str] { return ARTIFACT_TYPES; }
cl def:pub edge_types() -> list[str] { return EDGE_TYPES; }

def:pub Schema() -> JsxElement {
    types: list[str] = artifact_types();
    edges: list[str] = edge_types();

    return <section className="sec sec-schema" id="schema">
        <h2 className="sec-h2">{"The arrows have names."}</h2>

        <p className="body">
            {"A vector index stores one kind of thing and one kind of relationship: this chunk is near that chunk. The graph stores twelve node types and thirteen edge types, and the name on the edge is what lets a walker ask a specific question instead of a similar one."}
        </p>

        <figure className="schema-fig">
            <svg className="schema-svg" viewBox="0 0 880 390" role="img"
                 aria-label="Graph schema: a Person authors Artifacts, which reference other Artifacts and mention Domains. Events involve People, People belong to Departments, and a departure edge links a Person to the Domain they took with them.">

                {#* edges first, so nodes paint over their endpoints *#}
                <g className="sch-edges">
                    <path d="M 196 200 L 350 200" />
                    <path d="M 512 200 L 664 200" />
                    <path d="M 430 168 L 430 104" />
                    <path d="M 152 168 L 152 104" />
                    <path d="M 152 232 L 152 296" />
                </g>

                {#* Anchored on Jordan, not on Jax. Drawn from Jax's box it
                    read as "Jax departed with TitanDB", which is false twice
                    over — he is still there and it is not his domain. A
                    labelled edge leaving the wrong node is worse than no
                    edge. *#}
                <path className="sch-edge-absent" d="M 486 322 Q 620 330 742 236" />

                <g className="sch-labels">
                    <text x="273" y="194">{"Authored"}</text>
                    <text x="588" y="194">{"Mentions"}</text>
                    <text x="442" y="142">{"Refs"}</text>
                    <text x="164" y="142">{"Involves"}</text>
                    <text x="164" y="272">{"MemberOf"}</text>
                    <text className="sch-label-absent" x="392" y="352">{"DepartedWith"}</text>
                    <text className="sch-label-absent sch-label-sub" x="392" y="368">
                        {"Jordan → redis-cache · 25% documented"}
                    </text>
                </g>

                {#* Every box carries the type AND the instance from the
                    sections above — Jax, his thread, TitanDB, Jordan. An
                    abstract Person→Artifact→Domain diagram is correct and
                    tells a reader nothing they can attach to; the same diagram
                    labelled with the message they just read is the same
                    information arriving somewhere. *#}

                {#* Person *#}
                <g className="sch-node sch-node-person">
                    <rect x="76" y="176" width="152" height="52" rx="4" />
                    <text x="152" y="199">{"Person"}</text>
                    <text className="sch-inst" x="152" y="217">{"Jax"}</text>
                </g>

                {#* Artifact — drawn as a stack, because it is eight types *#}
                <g className="sch-node sch-node-artifact">
                    <rect className="sch-stack" x="366" y="164" width="152" height="52" rx="4" />
                    <rect className="sch-stack" x="360" y="170" width="152" height="52" rx="4" />
                    <rect x="354" y="176" width="152" height="52" rx="4" />
                    <text x="430" y="199">{"SlackThread"}</text>
                    <text className="sch-inst" x="430" y="217">{"#digital-hq · day 53"}</text>
                </g>

                {#* Domain *#}
                <g className="sch-node sch-node-domain">
                    <rect x="668" y="176" width="152" height="52" rx="4" />
                    <text x="744" y="199">{"Domain"}</text>
                    <text className="sch-inst" x="744" y="217">{"TitanDB · 35 know it"}</text>
                </g>

                {#* Event *#}
                <g className="sch-node sch-node-event">
                    <rect x="76" y="52" width="152" height="52" rx="4" />
                    <text x="152" y="75">{"Event"}</text>
                    <text className="sch-inst" x="152" y="93">{"ENG-137 · day 13"}</text>
                </g>

                {#* Artifact, again — the target of Refs *#}
                <g className="sch-node sch-node-artifact">
                    <rect x="354" y="52" width="152" height="52" rx="4" />
                    <text x="430" y="75">{"ConfluencePage"}</text>
                    <text className="sch-inst" x="430" y="93">{"CONF-ENG-001"}</text>
                </g>

                {#* Department *#}
                <g className="sch-node sch-node-dept">
                    <rect x="76" y="296" width="152" height="52" rx="4" />
                    <text x="152" y="319">{"Department"}</text>
                    <text className="sch-inst" x="152" y="337">{"Engineering_Backend"}</text>
                </g>
            </svg>

            <figcaption className="schema-cap">
                {"Five of thirteen edge types. "}
                <span className="schema-cap-accent">{"DepartedWith"}</span>
                {" is the one that describes an absence — a person who left, and the domain that left with them."}
            </figcaption>
        </figure>

        <div className="schema-lists">
            <div className="schema-list">
                <h3 className="schema-h3">{"Artifact subtypes"}</h3>
                <ul className="schema-ul">
                    {for (i, t) in enumerate(types) {
                        <li className="schema-li" key={t}>{t}</li>
                    }}
                </ul>
            </div>
            <div className="schema-list">
                <h3 className="schema-h3">{"Edge types"}</h3>
                <ul className="schema-ul">
                    {for (i, e) in enumerate(edges) {
                        <li className="schema-li" key={e}>{e}</li>
                    }}
                </ul>
            </div>
        </div>

        <p className="note">
            {"Behaviour attaches per type on arrival — a walker entering a ConfluencePage runs different code than one entering a SlackThread. That dispatch is the language feature the whole retrieval layer is built on."}
        </p>
    </section>;
}
