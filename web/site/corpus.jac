"""Static sample data for the marketing site.

Every name, id and string below is a real record from the orgforge corpus — the
same corpus the app runs against. The marketing surface and the product read the
same shapes so a viewer who scrolls from `/` into `/app` sees continuity, not a
brochure followed by a different program.

`cl` markers are load-bearing: this module carries no JSX and no npm import, so
placement inference would otherwise put it server-side and the client imports
would not resolve.
"""

"""A fresh graph object every call.

`react-force-graph-2d` mutates the object it is handed — it writes `x`, `y`,
`vx`, `vy` onto every node and rewrites `link.source` / `link.target` from ids
into node references. Two components sharing one `glob` would fight over the
same mutated structure, so each mount takes its own copy.
"""
cl def:pub build_graph() -> dict[str, any] {
    people = ["Janice", "Morgan", "Jax", "Bill", "Felix", "Priya", "Dmitri"];
    systems = ["TitanDB", "legacy auth service", "AWS cost structure", "Project Titan"];
    docs = ["CONF-ENG-001", "CONF-ENG-014", "CONF-OPS-003"];
    tickets = ["ENG-123", "ENG-204", "ENG-311", "ZD-2214"];
    threads = ["#engineering_backend", "#incidents", "#platform"];
    prs = ["PR #4471", "PR #4488"];

    nodes: list[dict[str, any]] = [];
    for p in people {
        nodes = nodes + [{"id": p, "name": p, "type": "person"}];
    }
    for s in systems {
        nodes = nodes + [{"id": s, "name": s, "type": "system"}];
    }
    for d in docs {
        nodes = nodes + [{"id": d, "name": d, "type": "doc"}];
    }
    for t in tickets {
        nodes = nodes + [{"id": t, "name": t, "type": "ticket"}];
    }
    for t in threads {
        nodes = nodes + [{"id": t, "name": t, "type": "thread"}];
    }
    for r in prs {
        nodes = nodes + [{"id": r, "name": r, "type": "pr"}];
    }

    pairs = [
        ["Janice", "TitanDB"], ["Janice", "CONF-ENG-001"], ["Janice", "#engineering_backend"],
        ["Morgan", "TitanDB"], ["Morgan", "ENG-123"], ["Morgan", "#incidents"],
        ["Jax", "AWS cost structure"], ["Jax", "#platform"], ["Jax", "PR #4471"],
        ["Bill", "TitanDB"], ["Bill", "legacy auth service"], ["Bill", "AWS cost structure"],
        ["Bill", "Project Titan"], ["Bill", "CONF-ENG-001"],
        ["Felix", "ENG-204"], ["Felix", "#engineering_backend"], ["Felix", "CONF-ENG-014"],
        ["Priya", "ZD-2214"], ["Priya", "legacy auth service"], ["Priya", "#incidents"],
        ["Dmitri", "PR #4488"], ["Dmitri", "CONF-OPS-003"], ["Dmitri", "ENG-311"],
        ["CONF-ENG-001", "Project Titan"], ["CONF-ENG-001", "TitanDB"],
        ["CONF-ENG-014", "legacy auth service"], ["CONF-OPS-003", "AWS cost structure"],
        ["ENG-123", "TitanDB"], ["ENG-204", "Project Titan"], ["ENG-311", "TitanDB"],
        ["ZD-2214", "legacy auth service"],
        ["#incidents", "TitanDB"], ["#engineering_backend", "Project Titan"],
        ["#platform", "AWS cost structure"],
        ["PR #4471", "AWS cost structure"], ["PR #4488", "TitanDB"],
        ["Janice", "Morgan"], ["Morgan", "Felix"], ["Jax", "Dmitri"], ["Priya", "Janice"]
    ];

    links: list[dict[str, any]] = [];
    for pr in pairs {
        links = links + [{"source": pr[0], "target": pr[1]}];
    }

    return {"nodes": nodes, "links": links};
}

"""Six mock artifacts, one per source system, shown raining in section 3.

`kind` selects the chrome the card is drawn with; `lines` is the body, rendered
verbatim. `entities` are the spans that lift off the card during the parse
stage — each must appear as a substring of some line, or the lift-off has
nothing to point at.
"""
cl glob ARTIFACTS: list[dict[str, any]] = [
    {
        "kind": "slack",
        "head": "#engineering_backend",
        "meta": "day 41 · 3 messages",
        "lines": [
            "Jax: terraform plan is showing 340 resources without cost tags",
            "Janice: that's the Titan migration, tagging was never backfilled",
            "Jax: is that written down anywhere? CONF-ENG-001 says nothing"
        ],
        "entities": ["Jax", "Janice", "CONF-ENG-001"]
    },
    {
        "kind": "jira",
        "head": "ENG-123",
        "meta": "Bug · Open · day 44",
        "lines": [
            "TitanDB connection pool exhaustion under replica lag",
            "Reporter: Morgan   Assignee: unassigned",
            "Linked: ZD-2214"
        ],
        "entities": ["TitanDB", "Morgan", "ZD-2214"]
    },
    {
        "kind": "confluence",
        "head": "CONF-ENG-001",
        "meta": "Project Titan Overview · v7 · day 12",
        "lines": [
            "Titan replaces the legacy auth service with TitanDB-backed sessions.",
            "Owner: Bill (departed)",
            "Status: partially documented"
        ],
        "entities": ["legacy auth service", "TitanDB", "Bill"]
    },
    {
        "kind": "zendesk",
        "head": "ZD-2214",
        "meta": "Priority: urgent · day 44",
        "lines": [
            "Customer cannot authenticate after the Titan cutover.",
            "Escalated to: Priya",
            "Affected: legacy auth service"
        ],
        "entities": ["Priya", "legacy auth service"]
    },
    {
        "kind": "zoom",
        "head": "Platform sync — transcript",
        "meta": "day 45 · 00:14:02",
        "lines": [
            "00:11:20  Morgan: nobody left knows why TitanDB was sharded that way",
            "00:11:38  Felix: Bill would have known",
            "00:12:04  Morgan: was a postmortem ever written?"
        ],
        "entities": ["Morgan", "TitanDB", "Felix", "Bill"]
    },
    {
        "kind": "pr",
        "head": "PR #4471",
        "meta": "merged · day 46 · +38 −4",
        "lines": [
            "+  tags = merge(var.common_tags, { cost_center = var.cost_center })",
            "-  tags = var.common_tags",
            "Author: Jax   Reviewer: Dmitri"
        ],
        "entities": ["Jax", "Dmitri"]
    }
];

"""Index of `needle` in `hay`, or -1.

Hand-rolled on slicing rather than `str.find` / `str.split`, whose client-side
semantics straddle Python and JS. Lines are three per card and cards are six, so
the quadratic scan is free and runs once at mount.
"""
cl def:pub find_at(hay: str, needle: str) -> int {
    n: int = len(needle);
    if n == 0 { return -1; }
    i: int = 0;
    while i + n <= len(hay) {
        if hay[i:i + n] == needle { return i; }
        i = i + 1;
    }
    return -1;
}

"""Split a line into alternating plain / entity runs.

This is what lets the parse stage highlight entities *in place* — the string is
cut at the real character offsets, so the accent lands on the actual token in the
actual sentence rather than on a decorative overlay.
"""
cl def:pub segment(line: str, entities: list[str]) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    rest: str = line;
    guard: int = 0;

    while len(rest) > 0 and guard < 64 {
        guard = guard + 1;
        best: int = -1;
        best_e: str = "";
        for e in entities {
            idx: int = find_at(rest, e);
            if idx >= 0 and (best < 0 or idx < best) {
                best = idx;
                best_e = e;
            }
        }
        if best < 0 {
            out = out + [{"t": rest, "e": False}];
            rest = "";
        } else {
            if best > 0 {
                out = out + [{"t": rest[0:best], "e": False}];
            }
            out = out + [{"t": best_e, "e": True}];
            rest = rest[best + len(best_e):];
        }
    }
    return out;
}

"""Who appears on each card as an avatar, keyed by the card's head.

Kept apart from `ARTIFACTS` rather than folded into it because `entities` is a
mix of people, systems and document ids — `["Jax", "Janice", "CONF-ENG-001"]` —
and rendering an avatar for CONF-ENG-001 is exactly the kind of detail that
reads as carelessness at the size these cards are shown.
"""
cl glob CARD_PEOPLE: dict[str, list[str]] = {
    "#engineering_backend":        ["Jax", "Janice"],
    "ENG-123":                     ["Morgan"],
    "CONF-ENG-001":                ["Bill"],
    "ZD-2214":                     ["Priya"],
    "Platform sync — transcript":  ["Morgan", "Felix"],
    "PR #4471":                    ["Jax", "Dmitri"]
};

cl def:pub card_people(head: str) -> list[str] {
    if head in CARD_PEOPLE { return CARD_PEOPLE[head]; }
    return [];
}

"""ARTIFACTS with each line pre-split into segments.

Computed once at mount and held in state: the scroll handler re-renders the
section on every frame, and re-splitting eighteen strings each time would be the
one avoidable cost in the sequence.
"""
cl def:pub parse_artifacts() -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for a in ARTIFACTS {
        ents: list[str] = a["entities"];
        rows: list[list[dict[str, any]]] = [];
        for ln in a["lines"] {
            rows = rows + [segment(ln, ents)];
        }
        out = out + [{
            "kind": a["kind"], "head": a["head"], "meta": a["meta"],
            "rows": rows, "entities": ents, "people": card_people(a["head"])
        }];
    }
    return out;
}

"""Where each card sits on the stage: left %, top %, and a little rotation.

Deliberately uneven — a tidy grid would read as a layout, and the point of the
rain stage is that artifacts arrive in a heap.
"""
cl glob SCATTER: list[dict[str, float]] = [
    {"x": 5.0,  "y": 9.0,  "r": -2.4},
    {"x": 38.0, "y": 4.0,  "r": 1.8},
    {"x": 68.0, "y": 16.0, "r": -1.4},
    {"x": 9.0,  "y": 47.0, "r": 2.6},
    {"x": 41.0, "y": 55.0, "r": -1.1},
    {"x": 70.0, "y": 60.0, "r": 2.1}
];

"""Human label for each card's source system, drawn in the card chrome."""
cl glob KIND_LABEL: dict[str, str] = {
    "slack": "Slack", "jira": "Jira", "confluence": "Confluence",
    "zendesk": "Zendesk", "zoom": "Zoom", "pr": "GitHub"
};

"""Per-source counts, shown as monospace labels while the cards rain."""
cl glob SOURCE_COUNTS: list[str] = [
    "3,303 Slack threads",
    "610 emails",
    "479 Confluence pages",
    "304 Jira tickets",
    "208 transcripts",
    "57 pull requests"
];

"""Accessors for the corpus tables above.

The tables are plain `glob`s rather than `glob:pub` on purpose. Incremental
(HMR) rebuilds of this module have been observed to drop `glob` symbols from the
emitted ESM export list while leaving `def`s intact — the importing module then
dies at load with "does not provide an export named ...". Exporting through
functions is the shape that survives a rebuild.

Each returns the table itself, not a copy; callers must treat the result as
read-only. Call once at component scope rather than inside a render loop.
"""
cl def:pub artifacts() -> list[dict[str, any]] { return ARTIFACTS; }

cl def:pub scatter() -> list[dict[str, float]] { return SCATTER; }

cl def:pub kind_label() -> dict[str, str] { return KIND_LABEL; }

cl def:pub source_counts() -> list[str] { return SOURCE_COUNTS; }
