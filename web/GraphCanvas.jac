"""Force-directed canvas for the org graph.

**The node set never changes.** The full slice is on screen from load, through
the walk, and after it. A query changes emphasis and camera, never the data:
watching a token cross a large graph is the demo, and swapping in a small
subgraph destroys exactly the thing worth showing.

  * **Idle** — a composed map: domains at the centre, departments and channels
    inside, people in the main ring, events and artifacts as an outer halo, one
    wedge per department. Nothing animates; the physics has stopped.
  * **Walking** — the untouched graph drops back to a dark field, the walked
    prefix is gold and glowing, and particles run on the *frontier* hops only.

## Composition, not physics (docs/GRAPH-VIZ-TECHNIQUES.md §0)

Link density here is 7.7 edges/node at the 3k slice — far above the ~3 where
node-link layouts stop being readable. No amount of charge tuning fixes that.
Two things do:

  * **A skeleton the physics only textures.** Every node is given a target
    point from (type ring x department sector), is *seeded* at that point so the
    first frame is already composed, and is then held there by `forceRadial` +
    `forceX`/`forceY`. `forceManyBody` and `forceCollide` are demoted to
    anti-overlap duty with a hard `distanceMax` — uncapped many-body is what
    turns 3,000 nodes into a ball.
  * **Showing far fewer edges.** Of 23,008 links at 3k, ~580 are structural
    (`MemberOf`, `CoOccurs`, `Relates`, `Refs`, `Subscribes`, …). The remaining
    ~22,400 `Authored`/`Mentions`/`Involves`/`InChannel` links are *mist*:
    hidden by default and revealed only for the hovered node's ego network.

Departments are the sectors, but 2,422 of 3,000 nodes arrive with `dept: ""`.
Rather than dump them all at angle 0, `seed_layout` propagates a department
across authorship-ish links, so a Slack thread sits in the wedge of the person
who wrote it. Anything still unassigned gets a deterministic golden-angle
position, which spreads rather than clumps.

## Performance, learned the hard way

  * `linkDirectionalParticles` as a constant puts particles on EVERY edge
    (23,008 here, redrawn every frame) and stutters a laptop. Particles come
    from an accessor and are zero everywhere except the hops revealed by the
    current tick, and only while the walker is still running.
  * Every per-link and per-node accessor is a single property read. Anything
    derived — walked, visible, class, hue, label — is *stamped onto the object*
    when the walk or the data changes, never recomputed inside an accessor. The
    previous version rebuilt two strings and ran a linear scan per link, per
    accessor, per frame.
  * `ctx.shadowBlur` is a per-pixel convolution. It runs in `onRenderFramePre`
    over the walked links only (tens of them), never from an accessor.

## Jac gotchas this file is written around

  * **`node` and `edge` are reserved words.** `node["x"] = 1;` does not parse as
    a subscript assignment — it is read as an archetype declaration and produces
    a wall of `Expected identifier, got '['`.
  * **Typed locals compile to `const`.** `x: float = a; x = b;` inside a branch
    silently creates a *new* binding, so the outer value never changes. Every
    mutable value below is a conditional expression or a list slot, never a
    reassignment.
  * **There is no `Math`.** `sin_`/`cos_` are Horner-form Taylor series; the
    checker rejects `Math.cos` as an unknown attribute.
  * **Lambda bodies are braced:** `lambda (d: any) { expr; }`, not `lambda d: expr`.
  * `dict[k]` on a missing key yields `undefined`, which is not `False` — every
    boolean stamped onto a link uses `k in d` so `linkVisibility` gets a real
    bool.

## Four library quirks handled here

  * It sizes itself to the *window* unless given explicit width/height, so the
    graph hangs off-centre inside a pane.
  * A string passed to `linkColor` is read as a property NAME, not a colour —
    colours have to come from an accessor function.
  * Once the simulation starts, it REPLACES each link's `source`/`target` id
    with the node object itself. Any accessor that compares against ids has to
    cope with both forms, which is what `end_id` below is for.
  * `nodePointerAreaPaint` takes (node, COLOUR, ctx, scale) — a different
    signature from `nodeCanvasObject`'s (node, ctx, scale). Handing the same
    painter to both sets `globalAlpha` on a string and kills the page.
"""

cl import from "react-force-graph-2d" { default as ForceGraph2D }
cl import from "d3-force-3d" { forceCollide, forceRadial, forceX, forceY }

# --- colour (docs/GRAPH-VIZ-TECHNIQUES.md §5A.4, authoritative for dark) ------
# Four hues, correlated with ring radius, so colour reinforces position instead
# of adding a channel to decode. The old ten-colour map had three
# indistinguishable blues spanning the Person/artifact boundary and an amber
# artifact class that collided with the walk accent.
glob C_DOMAIN: str = "#7FE0A8";
glob C_PERSON: str = "#7CC7F5";
glob C_EVENT: str = "#B98CFF";
glob C_DEPT: str = "#8494AD";
glob C_ART: str = "#6E7C93";

# Reserved EXCLUSIVELY for the walk and the active hop. Nothing else is gold.
glob WALK_COLOR: str = "#FFD166";
glob BG: str = "#0b0e14";

# The key, in the order a viewer meets these on screen. Shape matters as much as
# hue here — `paint_node` gives Domain a ringed circle, Event a diamond, and
# Department/Channel a square, so a legend of four coloured dots would document
# the palette while hiding the actual encoding.
#
# Person and Artifact have no custom mark: they ride the library's own filled-dot
# path, which is why they are listed as plain circle and dot. Keep this table in
# agreement with `paint_node` and `hue_of` — nothing enforces that it stays true.
glob LEGEND: list[dict[str, str]] = [
    {"k": "Person",           "s": "circle",  "c": C_PERSON},
    {"k": "Domain",           "s": "ring",    "c": C_DOMAIN},
    {"k": "Event",            "s": "diamond", "c": C_EVENT},
    {"k": "Dept / Channel",   "s": "square",  "c": C_DEPT},
    {"k": "Artifact",         "s": "dot",     "c": C_ART},
    {"k": "on the walk",      "s": "circle",  "c": WALK_COLOR}
];

# Near-white with a warm bias, so a lit node reads as lit against DIM_NODE at
# 10% ink AND sits in the same family as the gold path without competing with
# it. Pure #FFFFFF goes cold next to #FFD166 and looks like a rendering bug.
glob LIT_NODE: str = "#FFF4DA";

# Raised from the light-theme values: sRGB is steep near black, so an alpha
# that reads as "quiet" on white reads as "gone" on #0b0e14 (§5A.2).
glob DIM_NODE: str = "rgba(220,228,240,0.10)";
glob DIM_LINK: str = "rgba(220,228,240,0.07)";

# Idle edge alphas, raised from 0.24 / 0.13. The old values were set against the
# worry that light-on-dark accumulates — six overlapping strokes drift toward
# white and sRGB compresses hard near black, so a safe alpha for one edge is a
# haze for a bundle. That is real, but the correction overshot: at 0.24 the
# backbone was barely separable from the ground and the ego edges were, in
# practice, invisible.
#
# These are the highest values where a six-deep bundle still reads as strokes
# rather than fog. If the canvas ever renders denser than 3k nodes, check this
# again rather than assuming it still holds.
glob IDLE_LINK: str = "rgba(226,234,246,0.42)";
glob EGO_LINK: str = "rgba(226,234,246,0.24)";

# Structural edges: ~260 of the 23,008 at the 3k slice. Everything else —
# Authored, Mentions, Involves, Produced, InChannel, Subscribes — is mist and
# stays hidden until its node is hovered. `Subscribes` is deliberately NOT here
# despite being structural: 320 person->channel edges run from the people ring
# clean across the middle of the composition, and they were the single biggest
# source of visual noise in the idle view.
glob BACKBONE: dict[str, bool] = {
    "MemberOf": True, "CoOccurs": True, "Relates": True, "Estranged": True,
    "DepartedWith": True, "Concerns": True, "Refs": True, "walk": True
};

# Type -> ring radius, before the density scale in `seed_layout`. Artifact types
# get slightly different radii so the halo has internal structure without
# needing eight hues nobody can read at 3px.
glob RING: dict[str, float] = {
    "Domain": 75.0, "Department": 150.0, "Channel": 190.0, "Person": 235.0,
    "Event": 268.0, "ConfluencePage": 300.0, "JiraTicket": 316.0,
    "SlackThread": 332.0, "Email": 348.0, "ZoomTranscript": 362.0,
    "PullRequest": 376.0, "SFOpportunity": 388.0, "ZDTicket": 388.0
};

glob BASE_VAL: dict[str, float] = {
    "Domain": 6.0, "Department": 4.2, "Channel": 3.0, "Person": 3.0,
    "Event": 1.0
};

# Types whose sector must NOT be inferred from their neighbours — see the
# comment in `seed_layout`.
glob ANCHOR: dict[str, bool] = {
    "Domain": True, "Department": True, "Person": True
};

# Edge types that carry a usable department from one end to the other.
glob DEPT_FLOW: dict[str, bool] = {
    "Authored": True, "InChannel": True, "Involves": True, "Produced": True,
    "Mentions": True, "Refs": True
};

# §3's table, one column per graph size. Repulsion scales roughly as -k/density:
# as more nodes share the canvas you need LESS per-pair charge and MORE collide,
# because collide is bounded and charge is a long-range field that compounds.
glob FORCE_SMALL: dict[str, float] = {
    "charge": -190.0, "dmax": 420.0, "ldist": 44.0, "lstr": 0.30,
    "pad": 6.0, "cstr": 0.9, "rstr": 0.30, "sstr": 0.05
};
glob FORCE_MID: dict[str, float] = {
    "charge": -45.0, "dmax": 180.0, "ldist": 26.0, "lstr": 0.12,
    "pad": 2.0, "cstr": 0.7, "rstr": 0.38, "sstr": 0.07
};
glob FORCE_BIG: dict[str, float] = {
    "charge": -26.0, "dmax": 130.0, "ldist": 22.0, "lstr": 0.05,
    "pad": 1.4, "cstr": 0.6, "rstr": 0.50, "sstr": 0.10
};

glob TAU: float = 6.283185307179586;
glob PI: float = 3.141592653589793;
glob HALF_PI: float = 1.5707963267948966;
glob PHI: float = 0.6180339887498949;


# Horner-form Taylor to x^9, argument reduced to [-pi, pi]. Max error ~1e-5,
# which is four orders of magnitude below one graph unit. Written out because
# the client codespace has no `Math` the type checker will accept.
def sin_(a: float) -> float {
    m: float = a % TAU;
    x: float = (m - TAU) if m > PI else m;
    x2: float = x * x;
    return x * (1.0 - x2 / 6.0 * (1.0 - x2 / 20.0 *
                (1.0 - x2 / 42.0 * (1.0 - x2 / 72.0))));
}

def cos_(a: float) -> float {
    return sin_(a + HALF_PI);
}


def hue_of(kind: str) -> str {
    if kind == "Domain" {
        return C_DOMAIN;
    }
    if kind == "Person" {
        return C_PERSON;
    }
    if kind == "Event" {
        return C_EVENT;
    }
    if kind == "Department" or kind == "Channel" {
        return C_DEPT;
    }
    return C_ART;
}


# A link end is either the id string it was built with or, after the first
# simulation tick, the node object the library swapped in. Subscripting a JS
# string with "id" yields undefined, so the truthy check picks the right one.
def end_id(v: any) -> str {
    inner: any = v["id"];
    return (inner as str) if inner else (v as str);
}


# --- layout ------------------------------------------------------------------

# Everything positional is decided once, here, and written onto the node
# objects: `__tx`/`__ty` (the target the sector forces pull toward) and an
# initial `x`/`y` seeded at that target. Seeding matters — d3 only assigns a
# random position to nodes that arrive without one, so a pre-seeded graph is
# already composed on frame 1 and the settle is texture rather than an
# explosion.
def seed_layout(items: list, links: list) {
    count: int = len(items);
    if count == 0 {
        return;
    }
    # Rings scale with node count: 2,400 artifacts will not fit on a circle
    # sized for 400. Area, not radius, is what has to grow.
    scale: float = 1.0 if count <= 400 else ((count / 400.0) ** 0.5);

    by_id: dict[str, any] = {};
    for it in items {
        by_id[it["id"] as str] = it;
        it["__dept"] = (it["dept"] as str) if it["dept"] else "";
    }

    # Two propagation rounds so an artifact inherits the wedge of the person who
    # authored it, and a thread inherits it from the artifact.
    for _p in range(2) {
        for l in links {
            if (l["type"] as str) not in DEPT_FLOW {
                continue;
            }
            a: any = by_id[end_id(l["source"])];
            b: any = by_id[end_id(l["target"])];
            if not a or not b {
                continue;
            }
            # Propagate only INTO evidence. A Domain that inherits a
            # department gets yanked into that wedge, and since the ten domains
            # are mentioned by artifacts from every department they all end up
            # in whichever wedge won the race — the whole core collapses into
            # one clump. Domains, Departments and People keep their own answer.
            if a["__dept"] and (not b["__dept"]) and (b["type"] not in ANCHOR) {
                b["__dept"] = a["__dept"];
            } elif b["__dept"] and (not a["__dept"]) and (a["type"] not in ANCHOR) {
                a["__dept"] = b["__dept"];
            }
        }
    }

    names: list[str] = [];
    for it in items {
        d: str = it["__dept"] as str;
        if d and d not in names {
            names.append(d);
        }
    }
    names.sort();
    slot: dict[str, int] = {};
    for si in range(len(names)) {
        slot[names[si]] = si;
    }
    nd: int = len(names) if len(names) > 0 else 1;
    wedge: float = TAU / nd;

    for i in range(count) {
        it2: any = items[i];
        kind: str = it2["type"] as str;
        base: float = (RING[kind] as float) if (kind in RING) else 332.0;
        r: float = base * scale;
        # Golden-angle offset: deterministic, and spreads consecutive nodes of
        # the same type around the ring instead of stacking them.
        frac: float = (i * PHI) % 1.0;
        dep: str = it2["__dept"] as str;
        ang: float = ((slot[dep] as int) * wedge + (frac - 0.5) * wedge * 0.88)
                     if (dep and dep in slot) else (frac * TAU);
        # A little radial jitter so the rings breathe rather than reading as
        # drawn circles.
        rr: float = r * (0.93 + 0.14 * ((i * 0.7548776662) % 1.0));
        tx: float = cos_(ang) * rr;
        ty: float = sin_(ang) * rr;
        it2["__tx"] = tx;
        it2["__ty"] = ty;
        it2["__ring"] = rr;
        if not it2["__seeded"] {
            it2["x"] = tx;
            it2["y"] = ty;
            it2["__seeded"] = True;
        }
        it2["__hue"] = hue_of(kind);
        full: str = (it2["name"] as str) if it2["name"] else (it2["id"] as str);
        it2["__label"] = full if len(full) <= 26 else (full[:25] + "…");
        it2["__deg"] = 0;
        it2["__lw"] = 0.0;
    }

    for l2 in links {
        t: str = l2["type"] as str;
        bb: bool = t in BACKBONE;
        l2["__class"] = "backbone" if bb else "mist";
        l2["__walked"] = False;
        l2["__active"] = False;
        l2["__vis"] = bb;
        a2: any = by_id[end_id(l2["source"])];
        b2: any = by_id[end_id(l2["target"])];
        if a2 {
            a2["__deg"] = (a2["__deg"] as int) + 1;
        }
        if b2 {
            b2["__deg"] = (b2["__deg"] as int) + 1;
        }
    }
}


# Priority-ordered label candidates, rebuilt only when the data or the walk
# changes. Drawing labels from `onRenderFramePost` instead of
# `nodeCanvasObject` is what makes this possible: the painter is called in graph
# iteration order, so it cannot drop a low-priority label that collides with a
# high-priority one (§6.1).
def label_candidates(items: list, lit: dict[str, bool],
                     tips: dict[str, bool]) -> list {
    out: list = [];
    # The frontier first. A 120-edge fan lights 120 nodes at once, and naming
    # all of them is the same blob problem the gold had — the hop the walker is
    # ON is what the room needs read out.
    for n0 in items {
        if (n0["id"] as str) in tips {
            n0["__prio"] = 0;
            out.append(n0);
        }
    }
    for nl in items {
        if (nl["id"] as str) in lit and (nl["id"] as str) not in tips {
            nl["__prio"] = 1;
            out.append(nl);
        }
    }
    for n1 in items {
        if n1["type"] == "Domain" and (n1["id"] as str) not in lit {
            n1["__prio"] = 1;
            out.append(n1);
        }
    }
    for n2 in items {
        k: str = n2["type"] as str;
        if (k == "Department" or k == "Channel") and (n2["id"] as str) not in lit {
            n2["__prio"] = 2;
            out.append(n2);
        }
    }
    for n3 in items {
        if n3["type"] == "Person" and (n3["id"] as str) not in lit
           and (n3["__deg"] as int) >= 40 {
            n3["__prio"] = 3;
            out.append(n3);
        }
    }
    return out[:110];
}


# Greedy occlusion test, factored out so the caller never has to rebind a typed
# local (which in Jac silently shadows rather than assigns).
def box_hit(placed: list, x0: float, y0: float, x1: float, y1: float) -> bool {
    for b in placed {
        bx: float = b["x"] as float;
        by: float = b["y"] as float;
        if x0 < (bx + (b["w"] as float)) and x1 > bx
           and y0 < (by + (b["h"] as float)) and y1 > by {
            return True;
        }
    }
    return False;
}


def:pub GraphCanvas(data: dict[str, any], active: list[str],
                    walked: list[list[str]], running: bool = False,
                    onNodeClick: any = None) -> JsxElement {
    has boxRef: Ref[HTMLDivElement] = Ref();
    has fgRef: Ref[any] = Ref();
    has prepRef: Ref[any] = Ref();
    has labelRef: Ref[any] = Ref();
    has walkRef: Ref[any] = Ref();
    has prevRef: Ref[any] = Ref();
    has w: int = 0;
    has h: int = 0;
    has hoverId: str = "";

    # Server data is guarded, never trusted: walkers can return None, an empty
    # report or a partial shape, and dotting into that takes down the whole page.
    nodes: list = (data["nodes"] as list) if (data and data["nodes"]) else [];
    links: list = (data["links"] as list) if (data and data["links"]) else [];
    lit: list[str] = active if active else [];
    hops: list[list[str]] = walked if walked else [];
    hop: int = len(hops);
    walking: bool = len(lit) > 0;

    mq: any = matchMedia("(prefers-reduced-motion: reduce)");
    reduced: bool = (mq.matches) as bool if mq else False;

    # Prepared during render, not in an effect: the seeded x/y have to exist
    # BEFORE force-graph ingests the data, or d3 assigns random positions and
    # the composition is gone. Keyed on object identity, so it runs once per
    # slice rather than once per render.
    if prepRef.current != data {
        seed_layout(nodes, links);
        prepRef.current = data;
        labelRef.current = None;
    }

    lit_map: dict[str, bool] = {};
    for gid in lit {
        lit_map[gid as str] = True;
    }

    # Nodes reached by the hops this tick revealed. These are the walker's
    # current position; they get the labels and the hot glow.
    tip_map: dict[str, bool] = {};

    # Undirected keys for the edges walked so far — the walker's direction and
    # the link's stored direction are not guaranteed to agree. `front` is the
    # chunk of hops this tick revealed: the only edges that get particles.
    keys: dict[str, bool] = {};
    front: dict[str, bool] = {};
    prev: int = (prevRef.current as int) if prevRef.current else 0;
    grew: int = (hop - prev) if (hop - prev) > 0 else 1;
    for hi in range(hop) {
        pair: list[str] = hops[hi];
        k1: str = (pair[0] as str) + "|" + (pair[1] as str);
        k2: str = (pair[1] as str) + "|" + (pair[0] as str);
        keys[k1] = True;
        keys[k2] = True;
        if hi >= (hop - grew) {
            front[k1] = True;
            front[k2] = True;
            tip_map[pair[0] as str] = True;
            tip_map[pair[1] as str] = True;
        }
    }

    # Ego reveal: hovering a node lifts its own mist edges out of hiding. This is
    # what pays for hiding 22,000 links by default — "watch what this one person
    # touches" is a better demo beat than a hairball.
    ego: dict[str, bool] = {};
    if hoverId and not walking {
        for le in links {
            s0: str = end_id(le["source"]);
            t0: str = end_id(le["target"]);
            if s0 == hoverId or t0 == hoverId {
                ego[s0 + "|" + t0] = True;
            }
        }
    }

    # One pass over the links per walk step, stamping booleans the accessors then
    # read directly. The accessors themselves never compute anything.
    walk_links: list = [];
    for l in links {
        lk: str = end_id(l["source"]) + "|" + end_id(l["target"]);
        wk: bool = lk in keys;
        l["__walked"] = wk;
        l["__active"] = wk and (lk in front);
        l["__vis"] = wk or (l["__class"] == "backbone") or (lk in ego);
        if wk {
            walk_links.append(l);
        }
    }
    walkRef.current = walk_links;

    # Highlighted nodes shrink as the path grows, so a 121-node fan reads as a
    # constellation rather than one gold blob (the fixed 6x size was the bug).
    lit_n: int = len(lit);
    raw_val: float = 9.0 if lit_n <= 10 else (90.0 / lit_n);
    lit_val: float = raw_val if raw_val > 2.4 else 2.4;

    if (not labelRef.current) or walking {
        labelRef.current = label_candidates(nodes, lit_map, tip_map);
    }

    def measure {
        if boxRef.current {
            w = boxRef.current.clientWidth as int;
            h = boxRef.current.clientHeight as int;
        }
    }

    def walk_member(n: any) -> bool {
        return (n["id"] as str) in lit_map;
    }

    # --- accessors: property reads only, no derivation ---------------------
    def link_visible(l: any) -> bool {
        return l["__vis"] as bool;
    }

    def link_color(l: any) -> str {
        if l["__walked"] {
            return WALK_COLOR;
        }
        if walking {
            return DIM_LINK;
        }
        return IDLE_LINK if l["__class"] == "backbone" else EGO_LINK;
    }

    # Walked edges carry the answer, so they get the width budget: 3.2 against a
    # 0.8 backbone is a 4x ratio, where 2.4 against 0.55 read as "slightly
    # thicker" once the idle alphas came up. The idle widths rise too — a
    # hairline at 0.30 disappears entirely on a high-DPI display, which is what
    # made the ego edges look like they were not being drawn at all.
    def link_width(l: any) -> float {
        if l["__walked"] {
            return 3.2;
        }
        return 0.8 if l["__class"] == "backbone" else 0.5;
    }

    # Walked edges are straight so the glow underlay in `render_pre` traces them
    # exactly; everything else keeps one CONSTANT sign of curvature, which makes
    # parallel runs read as bundles instead of crosshatch.
    def link_curve(l: any) -> float {
        if l["__walked"] {
            return 0.0;
        }
        return 0.14 if l["__class"] == "backbone" else 0.22;
    }

    def link_arrow(l: any) -> float {
        return 4.0 if l["__walked"] else 0.0;
    }

    # The ONLY moving thing in the app, and only on the frontier: the hops
    # revealed by the current tick, while the walker is still running. Trailing
    # hops keep the gold and the glow but stop animating.
    def particles(l: any) -> int {
        if reduced {
            return 0;
        }
        return 3 if (running and l["__active"]) else 0;
    }

    def particle_speed(l: any) -> float {
        return 0.052;
    }

    def particle_width(l: any) -> float {
        return 3.5;
    }

    def particle_color(l: any) -> str {
        return WALK_COLOR;
    }

    # A lit node is painted BRIGHT, not merely un-dimmed. The type hues are
    # chosen to sit calmly on #0b0e14 at rest, which is exactly what makes them
    # read as dark once every other node has dropped to 10% ink — the contrast
    # the eye judges is lit-vs-dimmed, and a mid-blue against near-black does
    # not carry it.
    #
    # The earlier rule was "gold is a ring, never a fill", because filling a
    # 121-node path made one amber blob. That path is 30 nodes now, so the
    # constraint it was defending against no longer exists and the fill is
    # affordable. Hue survives as the ring in `paint_node`, so type is still
    # legible on the route.
    def node_color(n: any) -> str {
        if (n["id"] as str) in lit_map {
            return LIT_NODE;
        }
        return DIM_NODE if walking else (n["__hue"] as str);
    }

    def node_size(n: any) -> float {
        if (n["id"] as str) in lit_map {
            return lit_val;
        }
        k: str = n["type"] as str;
        return (BASE_VAL[k] as float) if (k in BASE_VAL) else 0.45;
    }

    # Custom marks only where they are readable and cheap: there are 10 domains,
    # 17 departments/channels and ~560 events, against 2,400 artifacts that stay
    # on the library's own filled-dot path. Eight artifact types do not need
    # eight marks — nobody can read that distinction at 3px.
    def node_mode(n: any) -> str {
        k: str = n["type"] as str;
        if k == "Domain" or k == "Department" or k == "Channel" or k == "Event" {
            return "replace";
        }
        return "after";
    }

    def paint_node(n: any, ctx: any, scale: float) {
        k: str = n["type"] as str;
        shaped: bool = k == "Domain" or k == "Department" or k == "Channel"
                       or k == "Event";
        on: bool = (n["id"] as str) in lit_map;
        if (not shaped) and (not on) {
            return;
        }
        x: float = n["x"] as float;
        y: float = n["y"] as float;
        r: float = (node_size(n) ** 0.5) * 4.0;
        col: str = node_color(n);

        if shaped {
            # Knockout first: on dark the edges passing behind a node are
            # emissive, so without it the node sits in a haze and loses its
            # silhouette. Skipped for Events — there are ~560 of them at 4px,
            # where the knockout costs a fill per frame and buys no silhouette.
            if k != "Event" {
                ctx.beginPath();
                ctx.fillStyle = BG;
                ctx.arc(x, y, r + 2.6, 0, TAU);
                ctx.fill();
            }
            if k == "Domain" {
                ctx.beginPath();
                ctx.fillStyle = col;
                ctx.arc(x, y, r, 0, TAU);
                ctx.fill();
                ctx.beginPath();
                ctx.strokeStyle = col;
                ctx.lineWidth = 1.4 / scale;
                ctx.arc(x, y, r + 3.0, 0, TAU);
                ctx.stroke();
            } elif k == "Event" {
                ctx.beginPath();
                ctx.fillStyle = col;
                ctx.moveTo(x, y - r);
                ctx.lineTo(x + r, y);
                ctx.lineTo(x, y + r);
                ctx.lineTo(x - r, y);
                ctx.closePath();
                ctx.fill();
            } else {
                # Department and Channel. These used to be stroke-only, which
                # read as empty boxes — a hollow glyph among filled circles and
                # diamonds looks like a rendering fault rather than a third
                # type, and that is exactly how it was reported.
                #
                # Filled at reduced alpha with a solid edge instead: the square
                # still reads as its own shape, but as a *quieter* node rather
                # than an unfinished one. The fill goes on first so the stroke
                # sits crisply on top of it.
                ctx.beginPath();
                ctx.fillStyle = col;
                ctx.globalAlpha = 0.30;
                ctx.rect(x - r, y - r, r * 2.0, r * 2.0);
                ctx.fill();
                ctx.globalAlpha = 1.0;

                ctx.beginPath();
                ctx.strokeStyle = col;
                ctx.lineWidth = 1.4 / scale;
                ctx.rect(x - r, y - r, r * 2.0, r * 2.0);
                ctx.stroke();
            }
        }

        # Two rings on a lit node: the type hue immediately outside the bright
        # fill, so the route still says WHAT each node is, then gold outside
        # that to bind it to the path. The fill went bright (see `node_color`)
        # because a 30-node path can carry it where a 121-node one could not.
        if on {
            ctx.beginPath();
            ctx.strokeStyle = n["__hue"] as str;
            ctx.lineWidth = 1.4 / scale;
            ctx.arc(x, y, r + 1.6, 0, TAU);
            ctx.stroke();
            ctx.beginPath();
            ctx.strokeStyle = WALK_COLOR;
            ctx.lineWidth = 2.0 / scale;
            ctx.arc(x, y, r + 3.4, 0, TAU);
            ctx.stroke();
        }
    }

    # Glow lives here, under the links, not in an accessor: shadowBlur is a
    # per-pixel convolution and this pass touches only the walked edges. ALWAYS
    # save/restore — canvas shadow state is sticky and a leak silently applies
    # glow to the whole graph and tanks the frame rate.
    def render_pre(ctx: any, scale: float) {
        wl: any = walkRef.current;
        if not wl {
            return;
        }
        if len(wl as list) == 0 {
            return;
        }
        ctx.save();
        ctx.shadowColor = WALK_COLOR;
        ctx.strokeStyle = "rgba(255,209,102,0.55)";
        ctx.lineCap = "round";
        ctx.shadowBlur = 14.0 / scale;
        ctx.lineWidth = 3.4 / scale;
        for l in (wl as list) {
            # ACTIVE ONLY. Glowing all 120 trailing hops was both the frame-rate
            # cost and the "gold blob" look: shadowBlur is a per-pixel
            # convolution, and 120 overlapping bloomed strokes composite toward
            # white on a near-black field until the fan is a solid mass.
            if not l["__active"] {
                continue;
            }
            s: any = l["source"];
            t: any = l["target"];
            if (not s["id"]) or (not t["id"]) {
                continue;
            }
            ctx.beginPath();
            ctx.moveTo(s["x"], s["y"]);
            ctx.lineTo(t["x"], t["y"]);
            ctx.stroke();
        }
        ctx.restore();
    }

    # Labels last, in priority order, with a greedy occlusion cull. A constant
    # 12 SCREEN px (12/k) is what makes zoom feel semantic: labels don't balloon,
    # more of them just appear.
    def render_post(ctx: any, scale: float) {
        cands: any = labelRef.current;
        if not cands {
            return;
        }
        fs: float = 12.0 / scale;
        ctx.font = "500 " + str(fs) + "px ui-sans-serif, system-ui, sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "bottom";
        ctx.lineJoin = "round";
        placed: list = [];
        for n in (cands as list) {
            if len(placed) > 58 {
                break;
            }
            prio: int = n["__prio"] as int;
            if prio > 1 and scale < 1.25 {
                continue;
            }
            if prio > 2 and scale < 1.9 {
                continue;
            }
            text: str = n["__label"] as str;
            if not text {
                continue;
            }
            # Cached in em, not px, so it survives every zoom change.
            cached: float = n["__lw"] as float;
            em: float = cached if cached > 0.0
                        else ((ctx.measureText(text).width as float) / fs);
            if cached <= 0.0 {
                n["__lw"] = em;
            }
            tw: float = em * fs;
            x: float = n["x"] as float;
            y: float = (n["y"] as float) - 9.0 / scale;
            if box_hit(placed, x - tw / 2.0, y - fs, x + tw / 2.0, y) {
                continue;
            }
            placed.append({"x": x - tw / 2.0, "y": y - fs,
                           "w": tw, "h": fs * 1.35});
            # 4/k, not 3/k: light glyphs bloom outward and the edges behind them
            # are emissive, so a thinner knockout gets swallowed.
            ctx.lineWidth = 4.0 / scale;
            ctx.strokeStyle = BG;
            ctx.strokeText(text, x, y);
            if prio == 0 {
                ctx.fillStyle = WALK_COLOR;
            } elif prio == 2 {
                ctx.fillStyle = C_DEPT;
            } else {
                ctx.fillStyle = "rgba(220,228,240,0.92)";
            }
            ctx.fillText(text, x, y);
        }
    }

    # force-graph hands the click handler (node, event) — the node is the datum
    # the simulation is holding, so its `id` is the gid, and the event is a real
    # DOM MouseEvent whose viewport coordinates are where the card anchors.
    def handle_node_click(n: any, ev: any) {
        if not onNodeClick {
            return;
        }
        if not n {
            return;
        }
        onNodeClick(n["id"] as str, (ev.clientX as float), (ev.clientY as float));
    }

    def handle_hover(n: any, p: any) {
        hoverId = (n["id"] as str) if n else "";
    }

    # The only honest moment to frame the graph is when the engine says it has
    # stopped: a `zoomToFit` issued at mount fits an empty bounding box and
    # leaves the composition stranded in a corner of the canvas. Guarded on
    # `hop == 0` so a mid-walk reheat cannot yank the camera off the trail.
    def handle_stop {
        fg: any = fgRef.current;
        if fg and hop == 0 {
            fg.zoomToFit(0 if reduced else 450, 40);
        }
    }

    can with entry {
        measure();
    }

    # The skeleton. Registered on the imperative handle rather than as props
    # because `forceRadial`, `forceX`, `forceY` and `forceCollide` are not
    # registered by default — only 'link', 'charge' and 'center' are — and
    # 'center' has to be REMOVED or it fights the radial force for no gain.
    can with (data, w) entry {
        fg: any = fgRef.current;
        if not fg {
            return;
        }
        if len(nodes) == 0 {
            return;
        }
        cnt: int = len(nodes);
        P: dict[str, float] = FORCE_BIG if cnt > 1200
                              else (FORCE_MID if cnt > 250 else FORCE_SMALL);
        fg.d3Force("center", None);
        fg.d3Force("collide", forceCollide(lambda (d: any) {
            (node_size(d) ** 0.5) * 4.0 + (P["pad"] as float);
        }).strength(P["cstr"]).iterations(1));
        fg.d3Force("radial", forceRadial(lambda (d: any) {
            d["__ring"] as float;
        }, 0.0, 0.0).strength(P["rstr"]));
        fg.d3Force("x", forceX(lambda (d: any) {
            d["__tx"] as float;
        }).strength(P["sstr"]));
        fg.d3Force("y", forceY(lambda (d: any) {
            d["__ty"] as float;
        }).strength(P["sstr"]));
        fg.d3Force("charge").strength(P["charge"]).distanceMax(P["dmax"]);
        fg.d3Force("link").distance(P["ldist"]).strength(P["lstr"]);
        fg.d3ReheatSimulation();
    }

    # Camera, not data: the dep is the int `hop`, not the `walked` list — a dep
    # array compares by identity, and a fresh list every render would re-fire
    # this every render.
    can with [hop] entry {
        prevRef.current = hop;
        fg: any = fgRef.current;
        if not fg {
            return;
        }
        if hop == 0 {
            fg.zoomToFit(0 if reduced else 600, 50);
            return;
        }
        # Frame the whole trail rather than chasing the newest node, and only on
        # the first hop and after the last: panning every hop is the fastest way
        # to make a projector audience seasick and it destroys spatial memory.
        if hop == 1 or (not running) {
            fg.zoomToFit(0 if reduced else 700, 90, walk_member);
        }
        # `refresh` is documented on the force-graph ref but is NOT present on
        # the handle the Jac client hands back — calling it unguarded throws
        # "fg.refresh is not a function" and kills the walk effect.
        if fg.refresh {
            fg.refresh();
        }
    }

    return <div ref={boxRef} style={{"width": "100%", "height": "100%",
                                     "position": "relative"}}>
        {if w > 0 {
            <ForceGraph2D
                ref={fgRef}
                graphData={data}
                width={w}
                height={h}
                backgroundColor={BG}
                nodeLabel="name"
                nodeColor={node_color}
                nodeVal={node_size}
                nodeRelSize={4}
                nodeCanvasObject={paint_node}
                nodeCanvasObjectMode={node_mode}
                onNodeClick={handle_node_click}
                onNodeHover={handle_hover}
                linkVisibility={link_visible}
                linkColor={link_color}
                linkWidth={link_width}
                linkCurvature={link_curve}
                linkDirectionalArrowLength={link_arrow}
                linkDirectionalArrowRelPos={0.85}
                linkDirectionalParticles={particles}
                linkDirectionalParticleWidth={particle_width}
                linkDirectionalParticleSpeed={particle_speed}
                linkDirectionalParticleColor={particle_color}
                onEngineStop={handle_stop}
                onRenderFramePre={render_pre}
                onRenderFramePost={render_post}
                warmupTicks={140 if reduced else (18 if len(nodes) > 1200 else 30)}
                cooldownTicks={0 if reduced else (60 if len(nodes) > 1200 else 90)}
                d3AlphaDecay={0.06}
                d3AlphaMin={0.03}
                d3VelocityDecay={0.6}
                autoPauseRedraw={not running}
                enableNodeDrag={False}
                enablePointerInteraction={not running}
                linkHoverPrecision={2}
                minZoom={0.05}
            />
        }}
        {#* The key. Drawn as SVG glyphs rather than coloured dots because the
            canvas distinguishes types by SHAPE as well as hue — a circle, a
            ringed circle, a diamond and a square — and a legend of four
            identical dots would document the colours while hiding the thing a
            viewer actually needs to decode. Each glyph here is the same
            construction `paint_node` uses.

            `pointer-events: none` throughout: the canvas underneath owns drag,
            hover and click, and a legend that swallows a click on the node
            behind it is worse than no legend. *#}
        {if len(nodes) > 0 {
            # Below the toolbar, not beside it. At `top: 12px` this sat directly
            # on top of the node-count selector — `pointer-events: none` meant
            # the buttons still worked, which is worse: a control you can click
            # but cannot read. 72px clears the toolbar's height plus its offset.
            #
            # (A `{#* *#}` JSX comment does not go here. Inside an `{if cond {`
            # body we are in Jac statement context, not JSX children, and the
            # JSX comment form is a parse error there.)
            <div style={{"position": "absolute", "top": "72px", "left": "12px",
                         "padding": "10px 12px", "borderRadius": "8px",
                         "background": "rgba(11,14,20,0.72)",
                         "border": "1px solid rgba(226,234,246,0.10)",
                         "backdropFilter": "blur(6px)",
                         "pointerEvents": "none", "userSelect": "none",
                         "fontFamily": "ui-monospace, monospace",
                         "fontSize": "10px", "lineHeight": "1.9",
                         "color": "rgba(220,228,240,0.62)", "zIndex": "3"}}>
                {for (i, row) in enumerate(LEGEND) {
                    <div key={row["k"]}
                         style={{"display": "flex", "alignItems": "center",
                                 "gap": "8px"}}>
                        <svg width="14" height="14" viewBox="0 0 14 14"
                             style={{"flex": "none", "display": "block"}}>
                            {if row["s"] == "circle" {
                                <circle cx="7" cy="7" r="4" fill={row["c"] as str} />
                            }}
                            {if row["s"] == "ring" {
                                <g>
                                    <circle cx="7" cy="7" r="3" fill={row["c"] as str} />
                                    <circle cx="7" cy="7" r="5.5" fill="none"
                                            stroke={row["c"] as str} strokeWidth="1" />
                                </g>
                            }}
                            {if row["s"] == "diamond" {
                                <path d="M 7 2 L 12 7 L 7 12 L 2 7 Z"
                                      fill={row["c"] as str} />
                            }}
                            {if row["s"] == "square" {
                                <rect x="2.5" y="2.5" width="9" height="9"
                                      fill={row["c"] as str} fillOpacity="0.30"
                                      stroke={row["c"] as str} strokeWidth="1.2" />
                            }}
                            {if row["s"] == "dot" {
                                <circle cx="7" cy="7" r="2.2" fill={row["c"] as str} />
                            }}
                        </svg>
                        <span>{row["k"]}</span>
                    </div>
                }}
            </div>
        }}
        {if len(nodes) == 0 {
            <p style={{"position": "absolute", "top": "50%", "left": "50%",
                       "transform": "translate(-50%, -50%)", "fontSize": "13px",
                       "opacity": "0.4"}}>{"no graph data"}</p>
        }}
    </div>;
}


# Playback speed for the walk. Lives here rather than in `AppScreen` so the
# canvas owns every control that changes what the canvas is doing; `AppScreen`
# holds the multiplier and divides `HOP_MS` by it.
def:pub SpeedButton(mult: float, label: str, current: float,
                    onPick: Callable[[float], None]) -> JsxElement {
    on: bool = mult == current;
    def handle(e: MouseEvent) {
        onPick(mult);
    }
    return <button onClick={handle}
                   style={{"padding": "3px 8px", "borderRadius": "6px",
                           "cursor": "pointer", "fontSize": "12px",
                           "fontFamily": "ui-monospace, monospace",
                           "background": "#2b4a8b" if on else "transparent",
                           "color": "#ffffff" if on else "#8fa3c4",
                           "border": "1px solid " + ("#2b4a8b" if on else "#26304a")}}>
        {label}
    </button>;
}
