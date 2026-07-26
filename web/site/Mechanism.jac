"""Sections 6 and 7 — how it works, and the way in.

The code block is the walker the app actually runs, not a simplification of it.
A Jac-literate reader is the intended audience for this section and will check.
"""

import from "@jac/runtime" { Link }

glob WALKER_SRC: str = """walker Visibility {
    has actor: str;
    has as_of_day: int;
    has cone: list = [];

    can start with Person entry {
        visit [-->](?day <= self.as_of_day);
    }
    can collect with ConfluencePage entry {
        self.cone.append(here.doc_id);
        visit [-->];
    }
}""";

glob ELIMINATED: list[str] = [
    "No database. No ORM. No vector store. No prompt strings.",
    "Persistence is reachability from the root node. Retrieval is traversal.",
    "The client calls walkers directly — no REST, no HTTP client, no CORS.",
    "One language, whole stack."
];

def:pub Mechanism() -> JsxElement {
    return <section className="sec sec-mech">
        <h2 className="sec-h2">{"The retriever is a walker."}</h2>

        <p className="body">
            {"Artifacts are typed nodes — a Confluence page is not a Slack thread, and behaviour attaches per type on arrival. A query is an agent moving through the graph. The path it walks is the citation."}
        </p>

        <pre className="code code-jac"><code>{WALKER_SRC}</code></pre>

        <ul className="elim">
            {for (i, line) in enumerate(ELIMINATED) {
                <li className="elim-line" key={str(i)}>{line}</li>
            }}
        </ul>
    </section>;
}

def:pub Cta() -> JsxElement {
    return <section className="sec sec-cta">
        <h2 className="sec-h2">{"Ask it something."}</h2>

        <p className="body">
            {"Live, on the orgforge corpus — 60 simulated days inside a company that never existed."}
        </p>

        <Link className="cta-button" to="/app">{"Open orgmem →"}</Link>

        {#* Every URL here was supplied or verified, none inferred. The dataset
            card is the one already asserted in `Landing.jac`'s JSON-LD
            `isBasedOn`; the orgforge repository was given directly; the source
            link is the repository this branch is pushed to. *#}
        <footer className="foot">
            <p>
                {"Built at JacHacks SF 2026 · Jac 0.34 · dataset "}
                <a className="foot-link" href="https://huggingface.co/datasets/aeriesec/orgforge"
                   target="_blank" rel="noreferrer noopener">
                    <code className="foot-code">{"aeriesec/orgforge"}</code>
                </a>
                {" (MIT) · "}
                <a className="foot-link" href="https://github.com/tenurehq/orgforge"
                   target="_blank" rel="noreferrer noopener">{"orgforge on GitHub"}</a>
                {" · "}
                <a className="foot-link" href="https://github.com/frankie-eight-days/orgmem"
                   target="_blank" rel="noreferrer noopener">{"orgmem source"}</a>
            </p>
        </footer>
    </section>;
}
