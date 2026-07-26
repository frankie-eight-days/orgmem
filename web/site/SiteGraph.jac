"""The site's force-graph renderer.

Deliberately the same library the app canvas uses, so the graph on `/` and the
graph in `/app` are the same object drawn with a different palette rather than a
marketing illustration of one. Fed static corpus data instead of a walker.

Nodes are drawn monochrome; the accent is spent only on edges, which is where
the structure actually lives.
"""

cl import from "react-force-graph-2d" { default as ForceGraph2D }

# Drawn for a LIGHT ground (see the note in styles.jac — the site is light, the
# app is dark, on purpose). Anchors are near-black and artifacts a mid warm grey:
# on cream, a graph needs weight to read at all, and the pale end of a palette
# that works on black disappears entirely here.
glob INK: str = "#12100E";
glob MUTED: str = "#7C756B";
glob LABEL: str = "#12100E";

"""Radius by node type, in SCREEN pixels — people and systems read as anchors,
artifacts as dust. Divided by the camera scale at paint time so the dots stay
this size however far `fit()` has zoomed in; the alternative is that filling the
hero with the graph also inflates every node into a forty-pixel blob."""
glob NODE_SIZE: dict[str, float] = {
    "person": 4.4, "system": 5.2, "doc": 2.6,
    "ticket": 2.4, "thread": 2.6, "pr": 2.4
};

def:pub SiteGraph(data: dict[str, any], height: float, breathing: bool = True,
                  labels: bool = True, link_alpha: float = 0.30,
                  node_alpha: float = 1.0) -> JsxElement {
    has box: Ref[HTMLDivElement] = Ref();
    has fg: Ref[any] = Ref();
    has width: float = 0.0;

    def measure() {
        if box.current {
            width = box.current.clientWidth as float;
        }
    }

    """Scale the camera so the laid-out graph fills its box.

    Default d3 charge and link distance produce a cluster roughly 300px across
    regardless of how large the canvas is, so on a full-bleed hero the graph
    rendered as a small knot in the middle of a lot of nothing. `zoomToFit` is a
    camera move, not a layout change: node radii scale with it, and the label
    size is already divided by `scale`, so text stays the same size on screen.
    """
    def fit() {
        if fg.current {
            fg.current.zoomToFit(600, 70);
        }
    }

    async can with entry {
        # Measured three times on purpose. The site stylesheet is written into
        # <head> by `Landing`'s own mount effect, and React runs a child's
        # effects BEFORE its parent's — so the first `measure()` here reads the
        # box before any of the layout CSS exists, when the unstyled div is as
        # wide as the document. The graph was then rendered at 1440px inside a
        # 740px column and its centre of mass sat off the right edge of the
        # screen. The deferred calls land after the stylesheet has applied.
        measure();
        setTimeout(measure, 0);
        setTimeout(measure, 250);
        window.addEventListener("resize", measure);
    }

    # The graph element only exists once a width has been measured, so the ref
    # is null during the mount effect above — the fit has to wait for `width`.
    can with [width] entry {
        if width > 0.0 {
            # Re-fit a few times while the simulation is still spreading, so a
            # graph that is drifting outward does not walk off its own canvas.
            setTimeout(fit, 900);
            setTimeout(fit, 2400);
            setTimeout(fit, 6000);
            setTimeout(fit, 12000);
        }
    }

    """Canvas painter: a filled dot plus, for the anchor types, a label."""
    def paint_node(n: any, ctx: any, scale: float) {
        t: str = n.type as str;
        r_px: float = NODE_SIZE[t] if t in NODE_SIZE else 2.4;
        r: float = r_px / scale;
        is_anchor: bool = t == "person" or t == "system";

        ctx.globalAlpha = node_alpha;
        ctx.beginPath();
        ctx.arc(n.x, n.y, r, 0, 6.283185307179586, False);
        ctx.fillStyle = INK if is_anchor else MUTED;
        ctx.fill();

        if labels and is_anchor {
            size: float = 11.0 / scale;
            ctx.font = str(size) + "px ui-monospace, SFMono-Regular, Menlo, monospace";
            ctx.textAlign = "left";
            ctx.textBaseline = "middle";
            ctx.fillStyle = LABEL;
            ctx.fillText(n.name, n.x + r + 4.0 / scale, n.y);
        }
        ctx.globalAlpha = 1.0;
    }

    """Edges are the only place the accent is spent inside the graph."""
    def link_colour(l: any) -> str {
        return "rgba(229, 67, 43, " + f"{link_alpha:.3f}" + ")";
    }

    return <div ref={box} className="graph-box" style={{"height": str(height) + "px"}}>
        {if width > 0.0 {
            <ForceGraph2D
                ref={fg}
                graphData={data}
                width={width}
                height={height}
                backgroundColor="rgba(0,0,0,0)"
                nodeCanvasObject={paint_node}
                linkColor={link_colour}
                linkWidth={0.32}
                enableZoomInteraction={False}
                enablePanInteraction={False}
                enableNodeDrag={breathing}
                warmupTicks={60}
                cooldownTicks={3000 if breathing else 0}
                d3AlphaDecay={0.008 if breathing else 0.03}
                d3VelocityDecay={0.86 if breathing else 0.4}
            />
        }}
    </div>;
}
