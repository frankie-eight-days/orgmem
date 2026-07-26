"""OrgMem server endpoints — the seam between the graph and the UI.

`main.jac` owns the graph and the walkers. This module spawns them and
normalises every walker report into one answer shape:

    {title, verdict, reason, evidence, highlight, path}

so the panel renders any question the same way, the canvas always knows what to
light up, and `path` gives the animation an ordered edge list to walk.

Lives apart from `app.jac` on purpose: client components reach these through
`sv import from ..api`, and an `sv import` aimed at the entry module's own
client section does not register the endpoint (see `jac-fullstack-patterns`).

Note: a triple-quoted string as the first statement of a function body does NOT
parse as a docstring here — the parser reads it as an expression and folds the
following `if` into a ternary, so the whole body fails to parse. Function-level
notes below are `#` comments for that reason.
"""

import os;
import from http { HTTPMethod }
import from main { GraphSlice, Visibility, GapScan, WhoKnows, Expand, NodeCard }

glob HERE: str = os.path.dirname(os.path.abspath(__file__));


# `/llms.txt` is a conventional path, so it cannot be a `/function/<name>`
# route — `@restspec` is what lets a `def:pub` claim a literal path. The SPA
# catch-all would not have covered it either: that only serves extensionless
# paths, and this one ends in `.txt`.
#
# The content is read at request time rather than import time so the site agent
# can rewrite `web/site/llms.txt` without a server restart.
@restspec(method=HTTPMethod.GET, path="/llms.txt")
def:pub llms_txt -> str {
    p: str = os.path.join(HERE, "web", "site", "llms.txt");
    if not os.path.exists(p) {
        return "";
    }
    with open(p) as f {
        return f.read();
    }
}

glob ACCESS: list[str] = ["confluence", "email", "slack", "zendesk"];


# A fresh dict every call. Returning a shared glob would let `ask` write a
# title into the fallback and have it stick for every later question.
def empty_answer -> dict[str, any] {
    return {"title": "", "verdict": "", "reason": "",
            "evidence": [], "highlight": [], "path": []};
}


# Shared shape for GraphSlice and Expand — both walkers report the same thing.
def slice_payload(r: any) -> dict[str, any] {
    if not r.reports {
        return {"nodes": [], "links": [], "counts": {}};
    }
    p = r.reports[0];
    nodes = [
        {"id": n["id"], "name": n["label"], "type": n["type"], "dept": n["dept"]}
        for n in p["nodes"]
    ];
    links = [
        {"source": e["s"], "target": e["t"], "type": e["type"]}
        for e in p["edges"]
    ];
    return {"nodes": nodes, "links": links, "counts": p["counts"]};
}


# The demo presets are fixed and structural — no model call, so running them is
# cheap — which means the set of ids any of them can highlight is knowable
# before the user clicks anything. Union those ids once and hand them to the
# first slice, and every preset's route is already on screen, in its real
# neighbourhood, when the answer arrives. The alternative is re-fetching per
# answer, which reshuffles the force layout under the user.
glob PRESETS: list[str] = ["felix", "janice", "gap", "who"];

# A dict, not a bare list glob, because a function can mutate a glob's contents
# but rebinding one needs a global declaration. `ready` rather than `if not ids`
# so a genuinely empty result is still cached instead of recomputed each call.
glob SEED: dict[str, any] = {"ids": [], "ready": False};


# Node ids one answer will light up: its `highlight` set plus both endpoints of
# every `path` edge, de-duplicated in first-seen order.
def answer_ids(a: dict[str, any]) -> list[str] {
    ids: list[str] = [];
    for h in a["highlight"] {
        g: str = str(h);
        if g not in ids {
            ids.append(g);
        }
    }
    for pair in a["path"] {
        for e in pair {
            g2: str = str(e);
            if g2 not in ids {
                ids.append(g2);
            }
        }
    }
    return ids;
}


# Computed on first use rather than at import, so a slow or broken walker
# degrades one request instead of preventing the server from booting.
def preset_seed -> list[str] {
    if SEED["ready"] {
        return SEED["ids"];
    }
    ids: list[str] = [];
    for name in PRESETS {
        for gid in answer_ids(ask(name)) {
            if gid not in ids {
                ids.append(gid);
            }
        }
    }
    SEED["ids"] = ids;
    SEED["ready"] = True;
    return ids;
}


# `include_ids` is a hard guarantee, not a hint: every id in it comes back in
# `nodes`, with its real edges. Omitting it does NOT mean "no guarantees" — it
# falls back to the cached preset seed, which is the whole point of the
# pre-seeding: the page's first slice already contains everything any preset can
# highlight, so clicking one never needs a re-fetch and the layout never
# reshuffles.
#
# Named `include_ids` rather than `include` because `include` is a Jac keyword —
# and the RPC turns the CALLER's local variable names into the JSON keys, so a
# client would have to spell it out too.
#
# The seed is added UNCONDITIONALLY and `include_ids` is added on top, rather
# than one falling back to the other. That is not a style choice — an omitted
# argument cannot be detected on a `/function/` route. The binder stringifies
# whatever default it finds and coerces the result to the declared type, so the
# call the client actually makes arrives as `include_ids: ['[', ']']` for a
# `= []` default and `include_ids: 'None'` for a `= None` one. Both are truthy,
# so any `if include_ids` fallback silently never fires. Verified against the
# server's own "Executing function 'graph_data' with params:" log line, 0.34.3.
#
# Adding instead of choosing makes that irrelevant: those junk values are just
# ids that resolve to nothing, and GraphSlice already skips unknown ids.
def:pub graph_data(dept: str, max_nodes: int, day_max: int,
                   include_ids: list[str] | None = None) -> dict[str, any] {
    seed: list[str] = [];
    for s in preset_seed() {
        seed.append(s);
    }
    if include_ids {
        for g in include_ids {
            gs: str = str(g);
            if gs not in seed {
                seed.append(gs);
            }
        }
    }
    return slice_payload(root spawn GraphSlice(
        dept=dept, max_nodes=max_nodes, day_max=day_max, include=seed
    ));
}


def:pub expand_node(node_id: str, hops: int) -> dict[str, any] {
    return slice_payload(root spawn Expand(node_id=node_id, hops=hops));
}


# Same shape as `empty_answer`: a fresh dict per call, and every key the card
# contract names. The client reads all fifteen without checking for absence.
def empty_card(gid: str) -> dict[str, any] {
    return {
        "gid": gid, "kind": "", "title": "", "body": "",
        "day": 0, "dept": "", "subsystem": "",
        "authors": [], "domains": [], "refs": [], "event": None,
        "person": None, "domain": None, "event_detail": None, "dept_detail": None
    };
}


# One click on the canvas, one call. `NodeCard` dispatches on the node's own
# archetype, so the eight artifact kinds come back with artifact fields and the
# four entity kinds come back with a detail block — never both.
#
# Domain is the one kind that needs two walkers. `bus_factor` and `doc_status`
# are not stored on the node: they are the output of `WhoKnows`'s decayed
# evidence scoring, and the card must show the SAME number the "who knows
# TitanDB" answer shows or the demo contradicts itself on stage. So the ranking
# is spawned here and layered onto the card rather than reimplemented.
#
# `as_of_day` is 60 to match `who_answer` — the corpus ends at day 60, and a
# different cutoff would silently give the card a different bus factor.
def:pub node_card(gid: str) -> dict[str, any] {
    if not gid {
        return empty_card("");
    }
    r = root spawn NodeCard(gid=gid);
    if not r.reports {
        return empty_card(gid);
    }
    c: dict[str, any] = r.reports[0];
    if c["kind"] != "Domain" or not c["domain"] {
        return c;
    }
    d: dict[str, any] = c["domain"];
    wk = root spawn WhoKnows(domain=str(d["name"]), as_of_day=60, limit=8);
    if not wk.reports {
        return c;
    }
    p = wk.reports[0];
    # WhoKnows reports {error, known} for a name it does not recognise. Every
    # Domain node is by construction known to it, but the card degrades to the
    # structural fields rather than raising if that ever stops being true.
    if "bus_factor" not in p {
        return c;
    }
    d["bus_factor"] = int(p["bus_factor"]);
    d["doc_status"] = str(p["doc_status"]);
    d["people"] = [
        {"name": x["name"], "count": x["artifacts"], "departed": x["departed"]}
        for x in p["people"][:8]
    ];
    d["departed_with"] = [
        {"name": x["name"], "documented_pct": x["documented_pct"]}
        for x in p["departed_with_knowledge"][:8]
    ];
    return c;
}


def visibility_answer(actor: str, as_of_day: int, target_event: str) -> dict[str, any] {
    # `target_event` is optional to the walker but not to the demo: without it
    # Visibility reports the reachable cone and stops ("no target event was
    # given"), so there is no blocked subsystem to name and no `path` to
    # animate. These are the same event ids the benchmark scores against.
    r = root spawn Visibility(actor=actor, as_of_day=as_of_day, access=ACCESS,
                              target_event=target_event);
    if not r.reports {
        return empty_answer();
    }
    p = r.reports[0];

    # `path` arrives as ordered [source, target] edge pairs. The canvas walks it
    # edge by edge; the panel and the node highlighting want the flattened node
    # ids in first-seen order, so derive both from the one list.
    hops: list[str] = [];
    path: list[list[str]] = [];
    for pair in p["path"] {
        path.append([pair[0] as str, pair[1] as str]);
        for gid in pair {
            if gid not in hops {
                hops.append(gid);
            }
        }
    }

    blocked = p["blocked_subsystems"];
    ev: list[str] = [f"blocked subsystem: {b}" for b in blocked];
    ev = ev + [f"never saw: {m}" for m in p["missed"][:8]];
    ev = ev + [f"in the cone: {c}" for c in p["cone"][:8]];

    return {
        "title": "",
        "verdict": "YES — could have known" if p["could_have_known"] else "NO — could not have known",
        "reason": p["reason"],
        "evidence": ev,
        "highlight": hops,
        "path": path
    };
}


def gap_answer -> dict[str, any] {
    r = root spawn GapScan(
        trigger_event_id="EVT-38-knowledge_gap_detected-1453",
        expected_response_type="confluence_created",
        window_days=14
    );
    if not r.reports {
        return empty_answer();
    }
    p = r.reports[0];
    # `searched` is the proof: the bounded space the walker actually examined.
    searched: list[str] = [s as str for s in p["searched"]];
    return {
        "title": "Was a Confluence page written after the day-38 knowledge gap?",
        "verdict": "YES — the follow-up exists" if p["answer"] else "NO — the silence is real",
        "reason": p["reason"],
        "evidence": [f"searched: {s}" for s in searched[:20]],
        "highlight": searched[:60],
        "path": []
    };
}


def who_answer -> dict[str, any] {
    wk = root spawn WhoKnows(domain="TitanDB", as_of_day=60, limit=10);
    if not wk.reports {
        return empty_answer();
    }
    p = wk.reports[0];
    ev: list[str] = [
        f"{person['name']} — score {person['score']}, {person['artifacts']} artifacts"
        for person in p["people"]
    ];
    ev = ev + [
        f"DEPARTED {d['name']} — {int(d['documented_pct'] * 100)}% documented, knew {', '.join(d['domains'])}"
        for d in p["departed_with_knowledge"]
    ];
    return {
        "title": "Who knows TitanDB?",
        "verdict": f"bus factor {p['bus_factor']} · {p['doc_status']}",
        "reason": p["bus_factor_rule"],
        "evidence": ev,
        "highlight": [person["name"] for person in p["people"][:5]],
        "path": []
    };
}


def:pub ask(preset: str) -> dict[str, any] {
    if preset == "felix" {
        a = visibility_answer("Felix", 32, "EVT-32-crm_touchpoint-1446");
        a["title"] = "Could Felix have known about the CRM touchpoint on day 32?";
        return a;
    }
    if preset == "janice" {
        a = visibility_answer("Janice", 3, "EVT-3-design_discussion-458");
        a["title"] = "Could Janice have known about the day-3 design discussion?";
        return a;
    }
    if preset == "gap" {
        return gap_answer();
    }
    return who_answer();
}
