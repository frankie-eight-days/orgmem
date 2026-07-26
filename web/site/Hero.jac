"""Section 0 — the hero.

The graph is the real renderer fed the real corpus sample, running a slowly
cooling simulation so it drifts for a while and then settles. That drift is the
only motion on the screen; everything else is still.

It is laid out behind the copy rather than beside it — full height, occupying
the right of the viewport, masked to nothing before it reaches the text column.
This is a graph product and the graph should be the first thing seen, not a
thumbnail in the margin.
"""

import from .SiteGraph { SiteGraph }
import from .corpus { build_graph }

def:pub Hero() -> JsxElement {
    has data: dict[str, any] = {"nodes": [], "links": []};

    async can with entry {
        data = build_graph();
    }

    return <header className="hero">
        <div className="hero-canvas" aria-hidden="true">
            <SiteGraph data={data} height={900.0} link_alpha={0.55} />
        </div>
        <div className="shell hero-inner">
            <div className="hero-copy">
                <p className="wordmark">{"orgmem"}</p>
                <h1 className="hero-h1">{"Your company knows more than it wrote down."}</h1>
                {#* The category is named first. "Observability for
                    organizations" does more work than any description of the
                    mechanism: it tells a reader what shelf this sits on, and
                    every engineer already knows what it means to be unable to
                    see a system you are responsible for. *#}
                <p className="hero-sub">
                    {"Observability for organizations. orgmem maps who knows what, where it's written, and where it isn't — as a graph you can walk. Built in Jac."}
                </p>
                <a className="hero-cta" href="#transformation">{"See it running ↓"}</a>
            </div>
        </div>
    </header>;
}
