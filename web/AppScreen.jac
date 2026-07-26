"""The graph explorer at `/app` — all state and every server call live here.

`Shell` and `GraphCanvas` below it are pure presentation. This module owns the
one thing that makes the demo read on a projector: the walk is *replayed*, not
revealed. `Visibility` reports its `path` as ordered [source, target] edge pairs,
and a timer here uncovers one pair at a time, so the audience watches the walker
cross the graph instead of seeing a finished highlight blink into place.

Two things worth knowing about the timer:

  * The cadence lives in `HOP_MS`. Below ~300ms the hops blur together on a
    projector; above ~500ms the room gets bored.
  * It is a raw `useEffect` rather than `can with [answer] entry` because the
    interval has to be cleared on unmount, and `entry` / `exit` compile to two
    SEPARATE effect closures — a handle created in `entry` is invisible to
    `exit`, so that cleanup would silently no-op and leak a running timer.

The step counter is held in a one-element list, not a plain local: the interval
callback has to advance it across ticks, and mutating a captured list is safe
where rebinding a captured local is not.

## Why `view` exists (the bug that made the walk invisible)

`GraphSlice` caps the canvas at `max_nodes` by SAMPLING the corpus, but the
walker traverses the whole 74k-edge graph. Measured on the Janice query: only
**3 of 26** path nodes were in the rendered 400, and **0 of 25** path edges
existed as rendered links — so there was almost nothing on screen to light up.

`view` is the rendered slice with any missing path nodes and every path edge
merged in. It is held in state and rebuilt only when a new answer or a new slice
arrives — NOT per render. That identity matters as much as the contents:
force-graph re-ingests and re-heats its simulation whenever `graphData` is a new
object, so recomputing it each render would make the layout crawl under the
walker while the audience is trying to follow a token across it.
"""

import from react { useEffect }
sv import from ..api { graph_data, ask, node_card }
import from .Shell { Shell }
import from .GraphCanvas { SpeedButton }

glob HOP_MS: int = 380;

# Ticks the reveal is spread over, so the walk lasts FRAMES * HOP_MS (~6s)
# whether the walker crossed four edges or a hundred and twenty.
glob FRAMES: int = 16;

glob BLANK: dict[str, any] = {"title": "", "verdict": "", "reason": "",
                              "evidence": [], "highlight": [], "path": []};

glob EMPTY_GRAPH: dict[str, any] = {"nodes": [], "links": [], "counts": {}};

# Measured on this machine against the live server. 3k is the demo default:
# it is enough graph for the walk to read as a route THROUGH structure rather
# than a figure floating on a sparse field.
#
# The old note here said 400 was the safe default because a Visibility path
# was 121 nodes and only 9 of them landed in a 400-node slice. That stopped
# being true when the walker started recording a bounded tree instead of the
# whole cone — Felix is now 31 nodes, and every one is present at 400 as well.
# 3k is now a composition choice, not a correctness one. 5k remains untested.
glob CAPS: list[dict[str, any]] = [
    {"n": 400, "label": "400"},
    {"n": 1000, "label": "1k"},
    {"n": 3000, "label": "3k"},
    {"n": 5000, "label": "5k"}
];

# Id prefixes carry the artifact type, which is what the canvas colours by. A
# node merged in from a path has no server record to read a type off, so it is
# inferred here rather than dropped into an untyped grey blob.
def kind_of(gid: str) -> str {
    if gid.startswith("slack_") or gid.startswith("slack-") {
        return "SlackThread";
    }
    if gid.startswith("CONF") {
        return "ConfluencePage";
    }
    if gid.startswith("EVT-") {
        return "Event";
    }
    if gid.startswith("PR-") {
        return "PullRequest";
    }
    if gid.startswith("email") or gid.startswith("EM-") {
        return "Email";
    }
    if gid.startswith("zoom") {
        return "ZoomTranscript";
    }
    if gid.startswith("OPP-") or gid.startswith("ZD-") {
        return "Artifact";
    }
    if "-" in gid and gid.upper() == gid {
        return "JiraTicket";
    }
    return "Person";
}

# Slack ids are a channel and an ISO timestamp; the channel is the readable half.
def short_name(gid: str) -> str {
    if gid.startswith("slack_") {
        rest: str = gid[6:];
        cut: int = rest.find("_20");
        return rest[:cut] if cut > 0 else rest;
    }
    return gid;
}

# Every node an answer will try to light up: the ordered route plus, for the
# questions that have no route (GapScan, WhoKnows), the flat highlight.
def route_ids(ans: dict[str, any]) -> list[str] {
    out: list[str] = [];
    path: list[list[str]] = (ans["path"] as list[list[str]]) if (ans and ans["path"]) else [];
    hl: list[str] = (ans["highlight"] as list[str]) if (ans and ans["highlight"]) else [];
    for pair in path {
        for gid in pair {
            if (gid as str) not in out {
                out.append(gid as str);
            }
        }
    }
    for gid in hl {
        if (gid as str) not in out {
            out.append(gid as str);
        }
    }
    return out;
}

def merge_walk(base: dict[str, any], ans: dict[str, any]) -> dict[str, any] {
    nodes: list = (base["nodes"] as list) if (base and base["nodes"]) else [];
    links: list = (base["links"] as list) if (base and base["links"]) else [];
    if len(nodes) == 0 {
        return base if base else EMPTY_GRAPH;
    }

    path: list[list[str]] = (ans["path"] as list[list[str]]) if (ans and ans["path"]) else [];
    hl: list[str] = (ans["highlight"] as list[str]) if (ans and ans["highlight"]) else [];

    wanted: list[str] = [];
    for pair in path {
        for gid in pair {
            if (gid as str) not in wanted {
                wanted.append(gid as str);
            }
        }
    }
    for gid in hl {
        if (gid as str) not in wanted {
            wanted.append(gid as str);
        }
    }
    if len(wanted) == 0 {
        return base;
    }

    have: list[str] = [n["id"] as str for n in nodes];
    out_nodes: list = [n for n in nodes];
    for gid in wanted {
        if gid not in have {
            have.append(gid);
            out_nodes.append({"id": gid, "name": short_name(gid),
                              "type": kind_of(gid), "dept": ""});
        }
    }

    # Every path edge is added outright. Checking for an existing link first
    # would cost 25 x 2313 string compares for, measured, zero hits.
    out_links: list = [l for l in links];
    for pair in path {
        out_links.append({"source": pair[0] as str, "target": pair[1] as str,
                          "type": "walk"});
    }
    return {"nodes": out_nodes, "links": out_links, "counts": base["counts"]};
}

def:pub AppScreen -> JsxElement {
    has answer: dict[str, any] = BLANK;
    has busy: bool = False;
    has step: int = 0;
    has graph: dict[str, any] = EMPTY_GRAPH;
    has view: dict[str, any] = EMPTY_GRAPH;
    has cap: int = 3000;
    has loading: bool = False;
    has attempt: int = 0;

    # Playback speed for the walk, as a multiplier on HOP_MS. Changing it
    # restarts the reveal from step 0 — the interval is keyed on it — which is
    # the behaviour you want on stage: pick a pace, replay the walk at it.
    has speed: float = 1.0;

    # The open node card and the point it is anchored to. `{}` rather than None
    # so `Shell` never dots into a null; emptiness is tested on `gid`, because
    # `{}` is truthy in JS and `len()` on a client-side object is undefined.
    has card: dict[str, any] = {};
    has cx: float = 0.0;
    has cy: float = 0.0;

    # Casting to the concrete element types matters: `answer` is dict[str, any],
    # and a bare `list` leaves `pair` as `any`, which is not iterable (E1022).
    path: list[list[str]] = answer["path"] as list[list[str]];
    hl: list[str] = answer["highlight"] as list[str];

    # The prefix of the walk uncovered so far. A question with no ordered path
    # (GapScan, WhoKnows) has nothing to animate, so its highlight lands whole.
    walked: list[list[str]] = path[:step];
    active: list[str] = [];
    if len(path) > 0 {
        for pair in walked {
            for gid in pair {
                if gid not in active {
                    active.append(gid);
                }
            }
        }
    } else {
        active = hl;
    }

    async def run_preset(preset: str) {
        busy = True;
        answer = await ask(preset);
        busy = False;
    }

    # Clicking a dot opens the artifact it stands for. The anchor is set before
    # the await so the card lands where the click was, not where the pointer
    # drifted to while the round-trip was in flight.
    async def open_card(gid: str, x: float, y: float) {
        cx = x;
        cy = y;
        fetched: dict[str, any] = await node_card(gid);
        card = fetched if fetched else {};
    }

    # A reference row inside an open card opens the artifact it points at, in
    # place. The anchor is deliberately left alone so the window does not jump
    # out from under the cursor that just clicked inside it.
    async def open_ref(gid: str) {
        fetched: dict[str, any] = await node_card(gid);
        card = fetched if fetched else {};
    }

    def close_card {
        card = {};
    }

    async def set_cap(n: int) {
        cap = n;
        # Positional, and the local names must match `graph_data`'s parameter
        # names exactly — the caller's variable names become the JSON keys.
        dept: str = "";
        max_nodes: int = n;
        day_max: int = 60;
        include_ids: list[str] = route_ids(answer);
        loading = True;
        graph = await graph_data(dept, max_nodes, day_max, include_ids);
        loading = False;
    }

    # Retried, because the API server finishes booting AFTER the page is
    # servable: opening the app during that window returns an empty slice and,
    # with a single mount fetch, the canvas stays empty for the rest of the
    # session. Observed live. The retry is what makes "just reload it" not be
    # the demo's recovery procedure.
    async can with [attempt] entry {
        dept: str = "";
        max_nodes: int = cap;
        day_max: int = 60;
        # `include_ids` is passed even when empty. An omitted optional argument
        # is serialised by the RPC bridge as the STRING "None" (seen live in the
        # server log as `include_ids: 'None'`), which the server then iterates
        # character by character. Always send the real list.
        include_ids: list[str] = [];
        fresh: dict[str, any] = await graph_data(dept, max_nodes, day_max, include_ids);
        if fresh and fresh["nodes"] and len(fresh["nodes"] as list) > 0 {
            graph = fresh;
        } elif attempt < 6 {
            setTimeout(lambda { attempt = attempt + 1; }, 1500);
        }
    }

    # An answer's route usually lands on nodes the sampled slice never picked —
    # measured at 400: Felix 9 of 121, Janice 3 of 26, GapScan 0 of 5. So when a
    # route arrives with nodes we don't have, re-slice with those ids pinned;
    # `GraphSlice` honours `include` and brings each pinned node's real
    # neighbours with it, which is what makes the walk thread THROUGH the graph
    # instead of dangling off it. `merge_walk` below stays as the fallback for
    # anything the server still can't supply.
    async can with [answer] entry {
        ids: list[str] = route_ids(answer);
        if len(ids) == 0 {
            return;
        }
        have: list[str] = [n["id"] as str for n in ((graph["nodes"] as list) if (graph and graph["nodes"]) else [])];
        missing: list[str] = [gid for gid in ids if gid not in have];
        if len(missing) == 0 {
            return;
        }
        dept: str = "";
        max_nodes: int = cap;
        day_max: int = 60;
        include_ids: list[str] = ids;
        graph = await graph_data(dept, max_nodes, day_max, include_ids);
    }

    # Rebuilt on a new slice or a new answer, and at no other time — see the
    # module docstring on why the object's identity has to stay stable.
    can with (graph, answer) entry {
        view = merge_walk(graph, answer);
    }

    useEffect(lambda {
        total = len(answer["path"] as list);
        step = 0;
        if total == 0 {
            return lambda {  };
        }
        # Felix's cone is 120 edges wide — one edge per tick would run for 45
        # seconds. Reveal a chunk per tick instead so any walk, wide or narrow,
        # finishes in roughly FRAMES * HOP_MS regardless of its size.
        chunk = 1 if total <= FRAMES else ((total + FRAMES - 1) // FRAMES);
        counter: list[int] = [0];
        handles: list[any] = [None];
        handles[0] = setInterval(lambda {
            counter[0] = counter[0] + 1;
            step = counter[0] * chunk;
            if counter[0] * chunk >= total {
                clearInterval(handles[0]);
            }
        }, HOP_MS / speed);
        return lambda { clearInterval(handles[0]); };
    }, [answer, speed]);

    def set_speed(m: float) {
        speed = m;
    }

    vnodes: list = (view["nodes"] as list) if (view and view["nodes"]) else [];
    vlinks: list = (view["links"] as list) if (view and view["links"]) else [];

    return <div>
        <Shell answer={answer} busy={busy} graph={view}
               active={active} walked={walked}
               hops_done={step} hops_total={len(path)}
               onAsk={run_preset}
               card={card} cx={cx} cy={cy}
               onNodeClick={open_card} onOpenRef={open_ref}
               onCloseCard={close_card} />
        <div style={{"position": "fixed", "top": "16px", "left": "424px",
                     "display": "flex", "alignItems": "center", "gap": "8px",
                     "padding": "6px 10px", "borderRadius": "8px",
                     "background": "rgba(11,14,20,0.82)",
                     "border": "1px solid #26304a", "fontSize": "12px",
                     "fontFamily": "ui-monospace, monospace", "color": "#dbe3f0"}}>
            <span style={{"opacity": "0.5"}}>{"graph"}</span>
            {for c in CAPS {
                <CapButton key={c["label"] as str} n={c["n"] as int}
                           label={c["label"] as str} current={cap} onPick={set_cap} />
            }}
            <span style={{"opacity": "0.5", "paddingLeft": "6px"}}>{"walk"}</span>
            <SpeedButton mult={0.5} label="0.5x" current={speed} onPick={set_speed} />
            <SpeedButton mult={1.0} label="1x" current={speed} onPick={set_speed} />
            <SpeedButton mult={2.0} label="2x" current={speed} onPick={set_speed} />
            <SpeedButton mult={4.0} label="4x" current={speed} onPick={set_speed} />
            <span style={{"opacity": "0.6"}}>
                {"loading…" if loading
                 else (str(len(vnodes)) + " nodes · " + str(len(vlinks)) + " edges")}
            </span>
        </div>
    </div>;
}

def:pub CapButton(n: int, label: str, current: int,
                  onPick: Callable[[int], None]) -> JsxElement {
    on: bool = n == current;
    def handle(e: MouseEvent) {
        onPick(n);
    }
    return <button onClick={handle}
                   style={{"padding": "3px 9px", "borderRadius": "6px",
                           "cursor": "pointer", "fontSize": "12px",
                           "fontFamily": "ui-monospace, monospace",
                           "background": "#2b4a8b" if on else "transparent",
                           "color": "#ffffff" if on else "#8fa3c4",
                           "border": "1px solid " + ("#2b4a8b" if on else "#26304a")}}>
        {label}
    </button>;
}
