"""Section 3 — artifacts in, graph out.

A tall scroll track with a sticky viewport inside it. One scalar, `p`, says how
far the reader has moved through the track; every card position, every entity
lift, and the graph's arrival are pure functions of `p`. Nothing is timed, so
scrolling back up plays the sequence in reverse for free.

Four stages overlap rather than queue, because a hard cut between them reads as
four animations instead of one process:

    p 0.02 - 0.36   rain         cards fall in, staggered by index
    p 0.30 - 0.56   parse        a scan line crosses each card, entities lift off
    p 0.56 - 0.78   crystallise  cards shrink toward centre and dissolve
    p 0.55 - 0.88   settle       the force graph arrives, then its edges snap in

Under `prefers-reduced-motion` no scroll listener is attached at all and every
element is drawn at its terminal value — cards landed, entities lifted, graph
present — which is the composition the sequence was designed to arrive at.
"""

import from .SiteGraph { SiteGraph }
import from .motion { clamp01, ramp, ease_out, ease_in, quantize }
import from .corpus { build_graph, parse_artifacts, scatter, kind_label, source_counts }

"""Where the cards converge as they dissolve — the graph's centre of mass."""
glob FOCUS_X: float = 48.0;
glob FOCUS_Y: float = 44.0;

def:pub Transform() -> JsxElement {
    has track: Ref[HTMLDivElement] = Ref();
    has p: float = 0.0;
    has reduced: bool = False;
    has cards: list[dict[str, any]] = [];
    has data: dict[str, any] = {"nodes": [], "links": []};

    # Corpus tables reach this module through accessor functions rather than
    # exported globals — see the note in corpus.jac. Bind each once per render
    # so the call never lands inside a loop body.
    slots: list[dict[str, float]] = scatter();
    kinds: dict[str, str] = kind_label();
    counts: list[str] = source_counts();

    """Read scroll position off the track and normalise to 0..1.

    Rounded to three places so an unchanged value is a no-op assignment and
    React bails out of the render instead of redrawing six cards for a
    sub-pixel scroll.
    """
    def measure() {
        el: any = track.current;
        if not el { return; }
        span: float = (el.offsetHeight as float) - (window.innerHeight as float);
        if span <= 0.0 { return; }
        top: float = el.getBoundingClientRect().top as float;
        p = round(clamp01(0.0 - top / span), 3);
    }

    async can with entry {
        cards = parse_artifacts();
        data = build_graph();

        w: any = window;
        if w.matchMedia("(prefers-reduced-motion: reduce)").matches {
            reduced = True;
        } else {
            w.addEventListener("scroll", measure, {"passive": True});
            w.addEventListener("resize", measure);
            measure();
        }
    }

    # ---- stage scalars -------------------------------------------------

    """Rain: each card gets its own window, so they arrive as a sequence."""
    def rain_at(i: int) -> float {
        if reduced { return 1.0; }
        s: float = (i as float) * 0.048;
        return ease_out(ramp(p, 0.02 + s, 0.28 + s));
    }

    """Parse: the scan line crossing the card, and the entity lift that follows."""
    def parse_at(i: int) -> float {
        if reduced { return 1.0; }
        s: float = (i as float) * 0.022;
        return ramp(p, 0.30 + s, 0.50 + s);
    }

    """Crystallise: the card giving up its shape."""
    def melt_at(i: int) -> float {
        if reduced { return 0.0; }
        s: float = (i as float) * 0.018;
        return ease_in(ramp(p, 0.56 + s, 0.76 + s));
    }

    # ---- styles --------------------------------------------------------

    def slot_style(i: int) -> dict[str, str] {
        s: dict[str, float] = slots[i];
        r: float = rain_at(i);
        m: float = melt_at(i);

        # Fall in from above the viewport, then be pulled toward the focus
        # point as the card dissolves. Both are on the same transform so the
        # two stages blend instead of fighting.
        dy: float = (1.0 - r) * -880.0;
        pull_x: float = (FOCUS_X - s["x"]) * 0.62 * m;
        pull_y: float = (FOCUS_Y - s["y"]) * 0.62 * m;
        rot: float = s["r"] * (1.0 - m);
        scale: float = 1.0 - 0.42 * m;

        return {
            "left": f"{s['x']:.2f}%",
            "top": f"{s['y']:.2f}%",
            "opacity": f"{r * (1.0 - m):.3f}",
            "transform": "translate3d(" + f"{pull_x:.2f}vw" + ", "
                + f"{dy:.1f}px" + ", 0) translateY(" + f"{pull_y:.2f}vh" + ") rotate("
                + f"{rot:.2f}deg" + ") scale(" + f"{scale:.3f}" + ")"
        };
    }

    def card_style(i: int) -> dict[str, str] {
        m: float = melt_at(i);
        return {"filter": "blur(" + f"{m * 7.0:.2f}px" + ")"};
    }

    """The scan line: a hairline that sweeps top to bottom during parse."""
    def scan_style(i: int) -> dict[str, str] {
        q: float = parse_at(i);
        vis: float = 0.0 if (q <= 0.0 or q >= 1.0 or reduced) else 1.0;
        return {"top": f"{q * 100.0:.1f}%", "opacity": f"{vis:.1f}"};
    }

    """An entity chip lifting off its card, staggered across the card's entities."""
    def chip_style(i: int, k: int, n: int) -> dict[str, str] {
        if reduced {
            return {"opacity": "1", "transform": "translateY(-34px)"};
        }
        q: float = ramp(parse_at(i), 0.15 + (k as float) * 0.16, 0.75 + (k as float) * 0.16);
        m: float = melt_at(i);
        rise: float = ease_out(q) * -46.0;
        spread: float = ((k as float) - ((n as float) - 1.0) / 2.0) * 8.0 * q;
        return {
            "opacity": f"{q * (1.0 - m):.3f}",
            "transform": "translate(" + f"{spread:.1f}px" + ", " + f"{rise:.1f}px" + ")"
        };
    }

    """A text run inside a card line — accented once its card has been scanned."""
    def run_class(i: int, is_entity: any) -> str {
        if not is_entity { return "run"; }
        return "run run-entity" if parse_at(i) > 0.35 else "run run-pending";
    }

    def counter_style(i: int) -> dict[str, str] {
        if reduced { return {"opacity": "1"}; }
        return {"opacity": f"{ramp(p, 0.04 + (i as float) * 0.038, 0.12 + (i as float) * 0.038):.3f}"};
    }

    graph_in: float = 1.0 if reduced else ease_out(ramp(p, 0.55, 0.80));
    edge_in: float = 1.0 if reduced else ramp(p, 0.66, 0.88);

    def stage_style() -> dict[str, str] {
        return {
            "opacity": f"{(0.55 if reduced else graph_in):.3f}",
            "transform": "scale(" + f"{0.90 + 0.10 * graph_in:.3f}" + ")"
        };
    }

    return <section className="tr" id="transformation">
        <div className="tr-track" ref={track}>
            <div className="tr-sticky">

                {#* The heading rides inside the sticky viewport so it is on
                    screen for the whole track — see the note in styles.jac. *#}
                <div className="tr-head">
                    <div className="shell">
                        <h2 className="tr-h2">{"Artifacts in. Graph out."}</h2>
                        <p className="tr-lede">
                            {"4,966 artifacts across six systems become 76,000+ typed edges in 6.4 seconds."}
                        </p>
                    </div>
                </div>

                <div className="tr-graph" style={stage_style()} aria-hidden="true">
                    <SiteGraph data={data} height={760.0} breathing={False}
                               labels={True}
                               link_alpha={quantize(edge_in * 0.62, 20)}
                               node_alpha={quantize(graph_in, 20)} />
                </div>

                <div className="tr-field">
                    {for (i, c) in enumerate(cards) {
                        <div className="slot" key={c["head"] as str} style={slot_style(i)}>
                            <article className="card" style={card_style(i)}>
                                <div className="card-chrome">
                                    <span className="card-kind">{kinds[c["kind"]]}</span>
                                    <span className="card-head">{c["head"]}</span>
                                </div>
                                <p className="card-meta">{c["meta"]}</p>
                                {for (j, row) in enumerate(c["rows"]) {
                                    <p className="card-line" key={str(j)}>
                                        {for (k, run) in enumerate(row) {
                                            <span className={run_class(i, run["e"])} key={str(k)}>{run["t"]}</span>
                                        }}
                                    </p>
                                }}
                                <span className="card-scan" style={scan_style(i)}></span>
                            </article>
                            <div className="chips" aria-hidden="true">
                                {for (k, ent) in enumerate(c["entities"]) {
                                    <span className="chip" key={str(k)}
                                          style={chip_style(i, k, len(c["entities"]))}>{ent}</span>
                                }}
                            </div>
                        </div>
                    }}
                </div>

                <div className="tr-counts">
                  <div className="shell">
                    <ul className="tr-count-list">
                        {for (i, label) in enumerate(counts) {
                            <li className="tr-count" key={label} style={counter_style(i)}>{label}</li>
                        }}
                    </ul>
                  </div>
                </div>

            </div>
        </div>
    </section>;
}
