"""Force-directed canvas for the org graph.

**The node set never changes.** The full slice is on screen from load, through
the walk, and after it. A query changes emphasis and camera, never the data:
watching a token cross a large graph is the demo, and swapping in a small
subgraph destroys exactly the thing worth showing.

  * **Idle** — every node coloured by type, nothing animating, physics settled.
  * **Walking** — the untouched graph drops back to a dark field; the walked
    prefix is bright, fat and labelled, with particles on the edges already
    crossed. The camera eases to each new hop so the action stays in frame, and
    the layout is frozen so the walker is not chasing a moving target.

`walked` is the prefix of the walk uncovered so far — `AppScreen` reveals it one
edge at a time, so the motion IS the walker traversing, not decoration.

Performance, learned the hard way: `linkDirectionalParticles` as a constant puts
particles on EVERY edge (~2,300 here, redrawn every frame) and stutters a
laptop. Particles come from an accessor and are zero everywhere except the
walked edges.

Four library quirks handled here:

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

glob TYPE_COLOR: dict[str, str] = {
    "Person": "#5ec8f8",
    "Department": "#c792ea",
    "Domain": "#8bd450",
    "Event": "#ff7b72",
    "ConfluencePage": "#f7c948",
    "SlackThread": "#f79ac0",
    "Email": "#ffa657",
    "JiraTicket": "#79c0ff",
    "ZoomTranscript": "#a5d6ff",
    "PullRequest": "#d2a8ff"
};

glob WALK_COLOR: str = "#ffd166";

# Hard dim, not a polite fade: at 400 nodes the trail only reads if the rest of
# the field drops nearly out of the picture.
glob DIM_NODE: str = "rgba(110,130,165,0.16)";
glob DIM_LINK: str = "rgba(150,170,200,0.05)";
glob IDLE_LINK: str = "rgba(150,170,200,0.22)";

# A link end is either the id string it was built with or, after the first
# simulation tick, the node object the library swapped in. Subscripting a JS
# string with "id" yields undefined, so the truthy check picks the right one.
def end_id(v: any) -> str {
    inner: any = v["id"];
    return (inner as str) if inner else (v as str);
}

def:pub GraphCanvas(data: dict[str, any], active: list[str],
                    walked: list[list[str]]) -> JsxElement {
    has boxRef: Ref[HTMLDivElement] = Ref();
    has fgRef: Ref[any] = Ref();
    has w: int = 0;
    has h: int = 0;

    # Server data is guarded, never trusted: walkers can return None, an empty
    # report or a partial shape, and dotting into that takes down the whole page.
    nodes: list = (data["nodes"] as list) if (data and data["nodes"]) else [];
    lit: list[str] = active if active else [];
    hops: list[list[str]] = walked if walked else [];
    hop: int = len(hops);
    walking: bool = len(lit) > 0;

    # Undirected keys for the edges walked so far — the walker's direction and
    # the link's stored direction are not guaranteed to agree.
    keys: list[str] = [];
    for pair in hops {
        keys.append((pair[0] as str) + "|" + (pair[1] as str));
        keys.append((pair[1] as str) + "|" + (pair[0] as str));
    }

    def measure {
        if boxRef.current {
            w = boxRef.current.clientWidth as int;
            h = boxRef.current.clientHeight as int;
        }
    }

    def find_node(gid: str) -> any {
        for n in nodes {
            if (n["id"] as str) == gid {
                return n;
            }
        }
        return None;
    }

    def walk_member(n: any) -> bool {
        return (n["id"] as str) in lit;
    }

    def is_walked(link: any) -> bool {
        return (end_id(link.source) + "|" + end_id(link.target)) in keys;
    }

    def link_color(link: any) -> str {
        if is_walked(link) {
            return WALK_COLOR;
        }
        return DIM_LINK if walking else IDLE_LINK;
    }

    def link_width(link: any) -> float {
        return 2.6 if is_walked(link) else 0.6;
    }

    # The ONLY moving thing in the app: edges the walker has already crossed.
    # Everything else returns 0, walking or idle.
    def particles(link: any) -> int {
        return 5 if is_walked(link) else 0;
    }

    def particle_speed(link: any) -> float {
        return 0.024;
    }

    def particle_width(link: any) -> float {
        return 4.0;
    }

    def particle_color(link: any) -> str {
        return WALK_COLOR;
    }

    def node_color(n: any) -> str {
        if (n["id"] as str) in lit {
            return WALK_COLOR;
        }
        base: str = (TYPE_COLOR[n["type"]] as str) if (n["type"] in TYPE_COLOR) else "#8899bb";
        return DIM_NODE if walking else base;
    }

    def node_size(n: any) -> float {
        return 9.0 if ((n["id"] as str) in lit) else 1.4;
    }

    # Drawn over the default painting, and only for nodes on the path —
    # labelling 400 nodes at once would be unreadable and expensive. The dark
    # pass underneath is a cheap shadow so labels survive a bright edge behind.
    def draw_label(n: any, ctx: any, scale: float) {
        if not walking {
            return;
        }
        if (n["id"] as str) not in lit {
            return;
        }
        text: str = (n["name"] as str) if n["name"] else (n["id"] as str);
        if len(text) > 24 {
            text = text[:23] + "…";
        }
        size: float = 12.0 / (scale as float);
        ctx.font = "600 " + str(size) + "px system-ui, sans-serif";
        ctx.textAlign = "center";
        ctx.fillStyle = "rgba(11,14,20,0.85)";
        ctx.fillText(text, (n["x"] as float) + (0.7 / (scale as float)),
                     (n["y"] as float) - (8.3 / (scale as float)));
        ctx.fillStyle = "rgba(255,232,175,0.96)";
        ctx.fillText(text, n["x"], (n["y"] as float) - (9.0 / (scale as float)));
    }

    can with entry {
        measure();
    }

    # Camera, not data: ease to the node the walker just reached. The dep is the
    # int `hop`, not the `walked` list — a dep array compares by identity, and a
    # fresh list every render would re-fire this every render.
    can with [hop] entry {
        if not fgRef.current {
            return;
        }
        if hop == 0 {
            fgRef.current.zoomToFit(600, 60);
            return;
        }
        # Frame the whole trail rather than chasing the newest node: a walk that
        # fans out from one hub would otherwise jerk the camera between spokes.
        # `zoomToFit` takes a node filter and sets centre AND zoom in one eased
        # move — issuing separate `centerAt` and `zoom` transitions every hop
        # makes them fight and leaves the camera stranded mid-animation.
        fgRef.current.zoomToFit(340, 90, walk_member);
    }

    return <div ref={boxRef} style={{"width": "100%", "height": "100%",
                                     "position": "relative"}}>
        {if w > 0 {
            <ForceGraph2D
                ref={fgRef}
                graphData={data}
                width={w}
                height={h}
                backgroundColor="#0b0e14"
                nodeLabel="name"
                nodeColor={node_color}
                nodeVal={node_size}
                nodeRelSize={3}
                nodeCanvasObject={draw_label}
                nodeCanvasObjectMode="after"
                linkColor={link_color}
                linkWidth={link_width}
                linkDirectionalParticles={particles}
                linkDirectionalParticleWidth={particle_width}
                linkDirectionalParticleSpeed={particle_speed}
                linkDirectionalParticleColor={particle_color}
                warmupTicks={90 if len(nodes) > 1200 else 40}
                cooldownTicks={0 if (walking or len(nodes) > 1200) else 60}
                d3AlphaDecay={0.06}
                d3VelocityDecay={0.35}
            />
        }}
        {if len(nodes) == 0 {
            <p style={{"position": "absolute", "top": "50%", "left": "50%",
                       "transform": "translate(-50%, -50%)", "fontSize": "13px",
                       "opacity": "0.4"}}>{"no graph data"}</p>
        }}
    </div>;
}
