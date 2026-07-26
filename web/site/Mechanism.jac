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
    "Persistence is reachability from `root`. Retrieval is traversal.",
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

        {#* `source on GitHub` is deliberately not a link: nobody has given me the
            repository URL and inventing one would be the only false claim on the
            page. Wrap it in an <a> the moment the URL is known. *#}
        <footer className="foot">
            <p>
                {"Built at JacHacks SF 2026 · Jac 0.34 · dataset "}
                <code className="foot-code">{"aeriesec/orgforge"}</code>
                {" (MIT) · source on GitHub"}
            </p>
        </footer>
    </section>;
}
