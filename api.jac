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
import json;
import urllib.request;
import from http { HTTPMethod }
import from main { GraphSlice, Visibility, GapScan, WhoKnows, Expand, NodeCard, Inherited, EventSearch, PathBetween, Bottlenecks }

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


def gap_answer_for(trigger: str, expected: str, title: str) -> dict[str, any] {
    r = root spawn GapScan(
        trigger_event_id=trigger,
        expected_response_type=expected,
        window_days=14
    );
    if not r.reports {
        return empty_answer();
    }
    # `p` off `reports` is Any, and `in` needs a __contains__ the checker can
    # see, so it is bound to a typed local before being probed. GapScan reports
    # `{error}` for an id it does not know.
    p: dict[str, any] = r.reports[0];
    if "answer" not in p {
        a0: dict[str, any] = empty_answer();
        a0["title"] = title;
        a0["verdict"] = "unknown event";
        a0["reason"] = str(p["error"]) if "error" in p else "the graph has no such event";
        return a0;
    }
    # `searched` is the proof: the bounded space the walker actually examined.
    searched: list[str] = [s as str for s in p["searched"]];
    return {
        "title": title,
        "verdict": "YES — the follow-up exists" if p["answer"] else "NO — the silence is real",
        "reason": p["reason"],
        "evidence": [f"searched: {s}" for s in searched[:20]],
        "highlight": searched[:60],
        # The walk IS the argument here: the audience watches the walker
        # exhaust the bounded causal space and come back with nothing. A
        # verdict that appears with no visible search reads as a lookup that
        # failed rather than as a proven absence.
        "path": [[pair[0] as str, pair[1] as str] for pair in p["path"]]
    };
}


def who_answer_for(domain: str) -> dict[str, any] {
    wk = root spawn WhoKnows(domain=domain, as_of_day=60, limit=10);
    if not wk.reports {
        return empty_answer();
    }
    p: dict[str, any] = wk.reports[0];
    if "bus_factor" not in p {
        a0: dict[str, any] = empty_answer();
        a0["title"] = f"Who knows {domain}?";
        a0["verdict"] = "unknown subsystem";
        a0["reason"] = str(p["error"]) if "error" in p else f"'{domain}' is not a subsystem in this graph";
        return a0;
    }
    ev: list[str] = [
        f"{person['name']} — score {person['score']}, {person['artifacts']} artifacts"
        for person in p["people"]
    ];
    ev = ev + [
        f"DEPARTED {d['name']} — {int(d['documented_pct'] * 100)}% documented, knew {', '.join(d['domains'])}"
        for d in p["departed_with_knowledge"]
    ];
    # The highest-ranked person who has NOT left. That is the whole answer to
    # "who should pick this up", and it is a different question from "who knows
    # most about it" whenever the top of the ranking is the person who left.
    top: str = "";
    for person in p["people"] {
        if top == "" and not person["departed"] {
            top = str(person["name"]);
        }
    }
    return {
        "title": f"Who knows {domain}?",
        "verdict": f"bus factor {p['bus_factor']} · {p['doc_status']}",
        "reason": p["bus_factor_rule"],
        "evidence": ev,
        "highlight": [person["name"] for person in p["people"][:5]],
        # domain -> the artifact that mentions it -> the person who wrote it.
        # Ranking is computed over the full evidence set; this is a readable
        # sample of the route that produced it, not the whole of it.
        "path": [[pair[0] as str, pair[1] as str] for pair in p["path"]],
        "top": top,
        "bus": int(p["bus_factor"]),
        "doc": str(p["doc_status"])
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
        return gap_answer_for(
            "EVT-35-knowledge_gap_detected-1441", "confluence_created",
            "Was the day-35 knowledge gap ever written up?"
        );
    }
    return who_answer_for("TitanDB");
}


# ------------------------------------------------------------------ 5. chat
#
# The chat pane's contract, and the reason it is not a chatbot: a question is
# parsed into a typed INTENT — which walker, which arguments — and the walker
# produces the answer. Nothing in the answer path reads the corpus as text and
# nothing generates prose from it. The verdict, the citation and the searched
# space all come out of the traversal, so the pane cannot invent a fact that
# the graph does not hold. `route` is reported back to the UI so the audience
# can see the walker call the sentence resolved to.
#
# The parser below is deterministic Jac. A model can be dropped in at exactly
# one seam — `route_intent` — because its only job is to fill this same slot
# dict; everything downstream is unchanged. Left deterministic for the demo:
# it removes a network round trip and a failure mode from the stage, and the
# claim being demonstrated is about the graph, not about the parser.


# WhoKnows answers an unknown domain with the list of ones it does know, which
# is the cheapest way to get the vocabulary without exporting a glob (a plain
# `glob` does not survive a cross-module import — see the handoff).
glob DOMAIN_CACHE: dict[str, any] = {"names": [], "ready": False};

def known_domains -> list[str] {
    if DOMAIN_CACHE["ready"] {
        return DOMAIN_CACHE["names"];
    }
    names: list[str] = [];
    wk = root spawn WhoKnows(domain="", as_of_day=60, limit=1);
    if wk.reports {
        p: dict[str, any] = wk.reports[0];
        if "known" in p {
            names = [str(x) for x in p["known"]];
        }
    }
    # An EMPTY result is not cached. This bit once already: the first call can
    # land before the graph is warm, and caching that answer left the model
    # with an empty subsystem vocabulary in its prompt for the rest of the
    # process — so every domain it extracted failed validation and silently
    # became "". Cache a real answer or try again next time.
    if names {
        DOMAIN_CACHE["names"] = names;
        DOMAIN_CACHE["ready"] = True;
    }
    return names;
}


# Longest name first, so "kubernetes-deploy" is not shadowed by a shorter one
# that happens to be a prefix. Hyphens are matched as spaces too, because
# nobody types `terraform-infra` in a sentence.
def domain_in(q: str) -> str {
    best: str = "";
    for d in known_domains() {
        dl: str = d.lower();
        hit: bool = dl in q or dl.replace("-", " ") in q;
        if hit and len(dl) > len(best) {
            best = d;
        }
    }
    return best;
}


def has_any(q: str, words: list[str]) -> bool {
    for w in words {
        if w in q {
            return True;
        }
    }
    return False;
}


# ------------------------------------------------------- the model's one job
#
# The model chooses a KEY from a closed set and, optionally, a subsystem from
# the graph's own vocabulary. It never sees an artifact, never writes a
# sentence that reaches the user, and never supplies an event id — those are
# filled in by `slots_for` below from constants that are checked against the
# corpus. The worst a bad parse can do is run the wrong walker, and the walker
# still reports honestly about what it searched.
#
# The subsystem list is read out of the graph (`known_domains`), not written
# into the prompt, so the vocabulary cannot drift from the data.

glob KIMI_URL: str = "https://api.kimi.com/coding/v1/chat/completions";
glob KIMI_MODEL: str = "kimi-for-coding-highspeed";

glob INTENT_RULES: str = """You route a question about an engineering org's history to ONE graph query. Reply with JSON only.
Keys:
  "key": one of "onboarding","postmortem","gap35","felix","janice_see","who","best","help","none"
  "domain": a subsystem name from the list below, or ""
Meaning:
  onboarding = was the new hire Janice ever given an onboarding session
  postmortem = was a postmortem written for the day-25 incident
  gap35      = was the day-35 knowledge gap ever documented
  felix      = could Felix have known about the day-32 CRM touchpoint
  janice_see = could Janice have known about the day-3 design discussion
  who        = who knows / owns a subsystem, bus factor
  best       = who is the best person to pick up, do, own, or write something
  help       = the user is asking what they can ask, or what this can do
  none       = the graph cannot answer this
If the question is a follow-up with no subject of its own, use CONTEXT as the domain.
Subsystems: """;


# `.env` is read directly because the dev server does not necessarily export
# it, and a key that is present but invisible looks exactly like no key at all.
def api_key -> str {
    k: str = os.environ.get("KIMI_API_KEY", "");
    if k {
        return k;
    }
    p: str = os.path.join(HERE, ".env");
    if not os.path.exists(p) {
        return "";
    }
    with open(p) as f {
        for line in f.read().split("\n") {
            s: str = line.strip();
            if s.startswith("KIMI_API_KEY=") {
                return s[13:].strip();
            }
        }
    }
    return "";
}


# Returns `{key, domain}`, or `{}` for "the model could not be reached or did
# not answer usefully" — which is a fallback, never an error to the user.
def llm_route(text: str, ctx_domain: str) -> dict[str, str] {
    key: str = api_key();
    if not key {
        return {};
    }
    ctx_line: str = ctx_domain if ctx_domain else "none";
    body: dict[str, any] = {
        "model": KIMI_MODEL,
        "max_tokens": 400,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system",
             "content": INTENT_RULES + ", ".join(known_domains())},
            {"role": "user",
             "content": f"CONTEXT: {ctx_line}\nQUESTION: {text}"}
        ]
    };
    try {
        req = urllib.request.Request(
            KIMI_URL,
            data=json.dumps(body).encode(),
            headers={"content-type": "application/json",
                     "Authorization": "Bearer " + key}
        );
        # Short timeout on purpose: this sits in front of every question, and a
        # slow parse is worse on stage than a keyword parse.
        raw = urllib.request.urlopen(req, timeout=12).read();
        d: dict[str, any] = json.loads(raw);
        content: str = str(d["choices"][0]["message"]["content"]);
        if not content {
            return {};
        }
        out: dict[str, any] = json.loads(content);
        k2: str = str(out["key"]) if "key" in out else "";
        dm: str = str(out["domain"]) if "domain" in out else "";
        # The domain is checked against the graph rather than trusted. A model
        # that invents a subsystem gets an empty one, not a lookup failure.
        if dm and dm not in known_domains() {
            dm = "";
        }
        return {"key": k2, "domain": dm};
    } except Exception as e {
        return {};
    }
}


# Key -> walker arguments. Every id here is a constant checked against the
# corpus; nothing in this mapping comes from the model.
def slots_for(key: str, domain: str, ctx: str) -> dict[str, str] {
    if key == "onboarding" {
        return {"intent": "gap", "trigger": "EVT-7-employee_hired-1030",
                "expected": "onboarding_session",
                "title": "Was Janice ever given an onboarding session?"};
    }
    if key == "postmortem" {
        return {"intent": "gap", "trigger": "EVT-25-incident_opened-1460",
                "expected": "postmortem_created",
                "title": "Was a postmortem written for the day-25 incident?"};
    }
    if key == "gap35" {
        return {"intent": "gap", "trigger": "EVT-35-knowledge_gap_detected-1441",
                "expected": "confluence_created",
                "title": "Was the day-35 knowledge gap ever written up?"};
    }
    if key == "felix" {
        return {"intent": "see", "actor": "Felix", "day": "32",
                "event": "EVT-32-crm_touchpoint-1446",
                "title": "Could Felix have known about the CRM touchpoint on day 32?"};
    }
    if key == "janice_see" {
        return {"intent": "see", "actor": "Janice", "day": "3",
                "event": "EVT-3-design_discussion-458",
                "title": "Could Janice have known about the day-3 design discussion?"};
    }
    if key == "who" {
        return {"intent": "who", "domain": domain if domain else ctx};
    }
    if key == "best" {
        return {"intent": "best", "domain": domain if domain else ctx};
    }
    if key == "help" {
        return {"intent": "help"};
    }
    if key == "none" {
        return {"intent": "none"};
    }
    return {};
}


# Literal questions, not abstract shapes. "was <X> ever written after <event>"
# tells someone what the walker does; it does not tell them what to type. Both
# the help answer and the out-of-scope answer offer these, and the UI renders
# them as buttons that send themselves.
glob EXAMPLES: list[str] = [
    "Was Janice ever given an onboarding session?",
    "Who knows TitanDB?",
    "Who would be the best person to pick up TitanDB?",
    "Did we ever do the postmortem for the day-25 incident?",
    "Could Felix have known about the CRM touchpoint on day 32?",
    "Was the day-35 knowledge gap ever written up?"
];


# Model first, keywords second. The fallback is not decoration: it is what
# makes a dead network, an expired key or a bad parse cost nothing on stage.
def route_intent(text: str, ctx_domain: str) -> dict[str, str] {
    r: dict[str, str] = llm_route(text, ctx_domain);
    if r and r["key"] {
        s: dict[str, str] = slots_for(str(r["key"]), str(r["domain"]), ctx_domain);
        if s {
            s["by"] = KIMI_MODEL;
            return s;
        }
    }
    s2: dict[str, str] = keyword_intent(text, ctx_domain);
    s2["by"] = "keyword fallback";
    return s2;
}


# The deterministic parser. Kept whole rather than deleted — see above.
def keyword_intent(text: str, ctx_domain: str) -> dict[str, str] {
    q: str = text.lower();
    named: str = domain_in(q);

    # 1. The follow-up. Checked FIRST because "who would be the best person to
    #    do it?" also contains "who", and must not fall through to a ranking
    #    query with no subject.
    if has_any(q, ["best person", "who should", "who would", "who could",
                   "who can", "pick this up", "pick it up", "assign"]) {
        return {"intent": "best", "domain": named if named else ctx_domain};
    }

    # 2. Ranking / bus factor, which needs a named subsystem.
    if has_any(q, ["who knows", "bus factor", "who owns", "expert"]) or named {
        return {"intent": "who", "domain": named if named else ctx_domain};
    }

    # 3. Onboarding — the strongest absence in the corpus.
    if has_any(q, ["what can i ask", "what can you", "what do you", "help",
                   "examples", "how does this work", "what is this"]) {
        return {"intent": "help"};
    }

    if has_any(q, ["onboard", "warmup", "1:1", "1-on-1", "handover", "handoff"]) {
        return {"intent": "gap", "trigger": "EVT-7-employee_hired-1030",
                "expected": "onboarding_session",
                "title": "Was Janice ever given an onboarding session?"};
    }

    # 4. Postmortems. Answers YES, honestly — the day-25 incident did get one.
    if has_any(q, ["postmortem", "post mortem", "post-mortem", "incident review"]) {
        return {"intent": "gap", "trigger": "EVT-25-incident_opened-1460",
                "expected": "postmortem_created",
                "title": "Was a postmortem written for the day-25 incident?"};
    }

    if has_any(q, ["felix", "crm", "salesforce", "touchpoint"]) {
        return {"intent": "see", "actor": "Felix", "day": "32",
                "event": "EVT-32-crm_touchpoint-1446",
                "title": "Could Felix have known about the CRM touchpoint on day 32?"};
    }
    if has_any(q, ["janice", "design discussion"]) {
        return {"intent": "see", "actor": "Janice", "day": "3",
                "event": "EVT-3-design_discussion-458",
                "title": "Could Janice have known about the day-3 design discussion?"};
    }
    if has_any(q, ["documented", "written up", "write-up", "knowledge gap",
                   "confluence", "silence", "ever written"]) {
        return {"intent": "gap", "trigger": "EVT-35-knowledge_gap_detected-1441",
                "expected": "confluence_created",
                "title": "Was the day-35 knowledge gap ever written up?"};
    }
    return {"intent": "none"};
}


def pct(x: float) -> str {
    return str(int(x * 100)) + "%";
}


# One call per turn. `ctx_domain` is the whole of the conversation state the
# server needs: the subject the last answer established, so a bare follow-up
# ("who would be the best person to do it?") has something to rank.
def:pub chat(text: str, ctx_domain: str) -> dict[str, any] {
    slots: dict[str, str] = route_intent(text, ctx_domain);
    kind: str = slots["intent"];
    a: dict[str, any] = empty_answer();
    a["chips"] = [];
    say: str = "";
    route: str = "";
    ctx: str = ctx_domain;

    if kind == "best" or kind == "who" {
        dom: str = slots["domain"] if "domain" in slots else "";
        if not dom {
            a["title"] = text;
            a["verdict"] = "which subsystem?";
            a["reason"] = "Ranking is per-subsystem, and this question did not name one and did not follow one.";
            a["evidence"] = [f"known: {d}" for d in known_domains()[:12]];
            a["say"] = "Name a subsystem and I will rank it — " + ", ".join(known_domains()[:3]) + " are all in the graph.";
            a["route"] = "no walker — missing argument";
            a["ctx_domain"] = ctx;
            return a;
        }
        a = who_answer_for(dom);
        route = f"WhoKnows(domain={dom}, as_of_day=60)";
        ctx = dom;
        # An unknown subsystem comes back in the ERROR shape, which has no
        # `bus`/`doc` keys — interpolating them unconditionally 500'd the whole
        # request, so a judge typing a subsystem name slightly wrong crashed
        # the pane instead of being told the name was wrong.
        if "bus" not in a {
            a["say"] = f"'{dom}' is not a subsystem in this graph. Known: " + ", ".join(known_domains()[:8]);
            a["route"] = route;
            a["ctx_domain"] = ctx_domain;
            a["chips"] = [];
            return a;
        }
        top: str = str(a["top"]) if "top" in a else "";
        if kind == "best" {
            a["title"] = f"Who is the best person to pick up {dom}?";
            if top {
                say = f"{top} — highest-ranked person still here on {dom}, by decayed evidence weight over what they actually wrote. Bus factor {a['bus']}, {a['doc']}.";
            } else {
                say = f"Nobody currently employed has evidence in {dom}. That is the bus factor being {a['bus']}: the knowledge left with the people who did.";
            }
        } else {
            say = f"Bus factor {a['bus']} · {a['doc']}. Ranked by artifact weight decayed on a 30-day half-life, not by message count.";
        }
    } elif kind == "gap" {
        a = gap_answer_for(slots["trigger"], slots["expected"], slots["title"]);
        route = f"GapScan(trigger={slots['trigger']}, expects={slots['expected']})";
        found: bool = "YES" in str(a["verdict"]);
        n: int = len(a["highlight"] as list);
        if found {
            say = f"Yes — it exists, and here it is. {n} causally linked records were examined and the match is cited below.";
        } else {
            say = f"No. All {n} records causally reachable from that event were examined and none matched. The space is closed, so this is a proven absence, not a failed search.";
        }
        # An unanswered onboarding is only half the story. The other half is in
        # the graph too: who left just before the hire, and what left with them.
        # That is what gives the follow-up question a subject.
        if not found and slots["expected"] == "onboarding_session" {
            inh = root spawn Inherited(before_day=7);
            if inh.reports {
                d: dict[str, any] = inh.reports[0];
                doms: list[str] = [str(x) for x in d["domains"]];
                if doms {
                    ctx = doms[0];
                    # No day is quoted: `departed_day` does not survive ingest
                    # (Bill reads as -579), and a number that is visibly wrong
                    # on stage costs more than it adds.
                    say = say + f" And it matters: {d['name']} left owning {', '.join(doms)} at {pct(float(d['documented_pct']))} documented. Janice was hired on day 7 to hold it, and nobody walked her through it.";
                    a["evidence"] = [f"departed: {d['name']} — {', '.join(doms)} at {pct(float(d['documented_pct']))} documented"] + (a["evidence"] as list[str]);
                }
            }
        }
    } elif kind == "see" {
        a = visibility_answer(slots["actor"], int(slots["day"]), slots["event"]);
        a["title"] = slots["title"];
        route = f"Visibility(actor={slots['actor']}, as_of_day={slots['day']}, target={slots['event']})";
        yes: bool = "YES" in str(a["verdict"]);
        who: str = slots["actor"];
        if yes {
            say = f"Yes — there is a route from {who} to that event through channels {who} was in on that day.";
        } else {
            say = f"No — no route reaches {who} by that day. The walk below is the reachable cone; the event is not in it.";
        }
    } elif kind == "help" {
        a["title"] = "What can this answer?";
        a["reason"] = "Four kinds of question, over a 60-day corpus of 22,530 records: who knows a subsystem, who should pick one up, whether something was ever written after an event, and whether a person could have known about one on a given day.";
        a["chips"] = EXAMPLES;
        say = "Ask about who knows what, where it is written, or where it is not. Any of these run:";
        route = "no walker — asking what to ask";
    } else {
        a["title"] = text;
        a["verdict"] = "out of scope";
        a["reason"] = "The graph holds who wrote what, when, and what referenced it. It cannot answer questions outside that record — and it will say so rather than guess.";
        a["chips"] = EXAMPLES;
        say = "I can only answer what the graph can prove. These all work:";
        route = "no walker matched";
    }

    # The walker call, and which parser produced it. Both are shown in the UI:
    # the point of the pane is that a sentence became a traversal, and the
    # audience should be able to see which sentence became which traversal.
    a["say"] = say;
    # The walker answers replace `a` wholesale with their own shape, so the key
    # is re-established here rather than assumed to have survived.
    a["chips"] = a["chips"] if "chips" in a else [];
    a["route"] = route + ("  ·  parsed by " + slots["by"] if "by" in slots else "");
    a["ctx_domain"] = ctx;
    return a;
}


# ------------------------------------------------------------- 6. the agent
#
# The pane's real entry point. `chat` above resolves a sentence to ONE walker
# in one model call; this runs the model in a LOOP with the walkers exposed as
# tools, so it can resolve an event by description, fan out across several
# events, and compose two walkers into one answer. "Which incidents never got
# a postmortem?" is not a question `chat` can express at all.
#
# The division of labour is the whole design, and it is what keeps the 94.7%
# quotable:
#
#   * The MODEL decides which tool to call and writes the closing sentence.
#   * The WALKERS decide what is true. Every verdict, every citation and every
#     "N records were examined" below comes out of a deterministic traversal
#     that is unchanged from the benchmarked code path.
#
# So the model never decides reachability and never reads an artifact body. It
# cannot turn a proven absence into a maybe. The worst a bad plan produces is
# the wrong walker run against the right graph — visible in the trace, which is
# reported back and rendered.

glob MAX_TURNS: int = 6;

glob TOOLS: list[dict[str, any]] = [
    {"type": "function", "function": {
        "name": "find_event",
        "description": "Resolve a described event to its id. All filters optional and ANDed. Returns an empty list when nothing matches — never guess an id, always resolve it here first.",
        "parameters": {"type": "object", "properties": {
            "day": {"type": "integer", "description": "one exact day, 0-60"},
            "day_from": {"type": "integer", "description": "start of a day range, inclusive"},
            "day_to": {"type": "integer", "description": "end of a day range, inclusive"},
            "event_type": {"type": "string", "description": "substring match, e.g. 'incident' matches incident_opened"},
            "actor": {"type": "string", "description": "a person involved, substring match"}
        }}}},
    {"type": "function", "function": {
        "name": "gap_scan",
        "description": "Exhaustively search the causal closure of an event for an expected follow-up. Returns a PROVEN yes or no plus the number of records examined. This is the only way to establish that something never happened.",
        "parameters": {"type": "object", "properties": {
            "event_id": {"type": "string"},
            "expected": {"type": "string", "description": "e.g. postmortem_created, confluence_created, onboarding_session, zd_ticket_opened, jira_ticket_created, runbook_created"}
        }, "required": ["event_id", "expected"]}}},
    {"type": "function", "function": {
        "name": "who_knows",
        "description": "Rank people by evidence weight in a subsystem, decayed on a 30-day half-life. Returns bus factor, who has left, and who is still here.",
        "parameters": {"type": "object", "properties": {
            "domain": {"type": "string"}
        }, "required": ["domain"]}}},
    {"type": "function", "function": {
        "name": "could_have_known",
        "description": "Whether a person could have known about an event by a given day, by reachability over the channels and artifacts they had access to.",
        "parameters": {"type": "object", "properties": {
            "person": {"type": "string"},
            "as_of_day": {"type": "integer"},
            "event_id": {"type": "string"}
        }, "required": ["person", "as_of_day", "event_id"]}}},
    {"type": "function", "function": {
        "name": "bottlenecks",
        "description": "Which subsystems are one departure away from being lost — every domain whose bus factor is at or below a threshold, worst first, with who still holds it and who already left holding it. Use for any question about risk, fragility, single points of failure, or where the org is exposed.",
        "parameters": {"type": "object", "properties": {
            "max_bus": {"type": "integer", "description": "bus-factor threshold, default 2"}
        }}}},
    {"type": "function", "function": {
        "name": "path_between",
        "description": "The shortest chain of named relationships connecting two nodes, or a statement that none exists within the hop limit. This is the question a search index cannot answer: not 'are these similar' but 'how, concretely, are these two things connected'.",
        "parameters": {"type": "object", "properties": {
            "a": {"type": "string", "description": "a node id — a person's name works"},
            "b": {"type": "string"},
            "max_depth": {"type": "integer", "description": "hop limit, default 6"}
        }, "required": ["a", "b"]}}},
    {"type": "function", "function": {
        "name": "describe_node",
        "description": "Structural facts about any node: its kind, day, authors, the domains it mentions, and what it references. Returns METADATA ONLY — never the text of an artifact, which this system deliberately cannot give you.",
        "parameters": {"type": "object", "properties": {
            "gid": {"type": "string", "description": "a node id from any other tool's output"}
        }, "required": ["gid"]}}},
    {"type": "function", "function": {
        "name": "neighbors",
        "description": "The nodes directly connected to a node, with the edge type on each link. Use to explore outward from something a previous tool returned.",
        "parameters": {"type": "object", "properties": {
            "gid": {"type": "string"},
            "hops": {"type": "integer", "description": "1 or 2; default 1"}
        }, "required": ["gid"]}}},
    {"type": "function", "function": {
        "name": "inherited",
        "description": "Who left holding undocumented knowledge, and which subsystems left with them. Use when a question is about knowledge lost to a departure.",
        "parameters": {"type": "object", "properties": {
            "before_day": {"type": "integer", "description": "only departures before this day; 60 for all"}
        }}}}
];


def agent_system -> str {
    doms: str = ", ".join(known_domains());
    return "You answer questions about an engineering organisation's 60-day history by calling tools over a knowledge graph.\n"
        + "Rules:\n"
        + "- NEVER invent an event id. Resolve it with find_event first.\n"
        + "- An empty find_event means you failed to RESOLVE something. It is NOT evidence that the thing never happened, and you must never report it as one. Absence is only ever established by gap_scan.\n"
        + "- To answer 'was X ever done after Y' (a postmortem after an incident, an onboarding after a hire, a page after a gap): find the TRIGGER event Y — the incident, the hire, the gap — then call gap_scan(event_id=Y, expected=X). Do not search for X directly.\n"
        + "- gap_scan is the only way to claim something never happened, because it is exhaustive over the causal closure. Quote the number of records it examined.\n"
        + "- If you cannot resolve the trigger event, say you could not resolve it. Never turn that into a 'no'.\n"
        + "- You may call several tools in one turn to cover several events at once.\n"
        + "- Do not state anything a tool did not return. No hedging language about what might exist.\n"
        + "- The earlier-conversation block, when present, exists ONLY to resolve pronouns and bare names. It is NOT a source of facts and you must never answer from it alone — re-run the tools for the new question, every time.\n"
        + "- Finish with ONE short sentence answering the question directly. No preamble, no bullet lists.\n"
        + "- EXCEPTION: if asked what you can do or which tools you have, call nothing. List the five tools, one short line each, and close by saying that you choose which tool to call but the walkers decide what is true — you cannot see an artifact's contents and cannot turn a proven absence into a maybe.\n"
        + "Subsystems in this graph: " + doms + "\n"
        + "Common event types: incident_opened, incident_resolved, knowledge_gap_detected, employee_hired, "
        + "confluence_created, postmortem_created, retrospective, pr_review, jira_ticket_created, "
        + "customer_email_routed, inbound_external_email, design_discussion, crm_touchpoint.";
}


# One model call. Returns the raw assistant message, or `{}` on any failure —
# the loop treats that as "stop", never as an error to the user.
def llm_turn(msgs: list[any], use_tools: bool = True) -> dict[str, any] {
    key: str = api_key();
    if not key {
        return {};
    }
    body: dict[str, any] = {
        "model": KIMI_MODEL, "max_tokens": 1200, "messages": msgs
    };
    if use_tools {
        body["tools"] = TOOLS;
    }
    try {
        req = urllib.request.Request(
            KIMI_URL, data=json.dumps(body).encode(),
            headers={"content-type": "application/json",
                     "Authorization": "Bearer " + key}
        );
        raw = urllib.request.urlopen(req, timeout=25).read();
        d: dict[str, any] = json.loads(raw);
        return d["choices"][0]["message"];
    } except Exception as e {
        return {};
    }
}


# Dispatch a tool call to a walker. Returns `{result, answer}` — `result` is
# what the model sees, `answer` is the full walker payload the UI renders
# (verdict, citations, and the path the canvas animates). They are deliberately
# different: the model gets a compact summary, the user gets the evidence.
def run_tool(name: str, args: dict[str, any]) -> dict[str, any] {
    if name == "find_event" {
        day: int = int(args["day"]) if "day" in args else -1;
        et: str = str(args["event_type"]) if "event_type" in args else "";
        who: str = str(args["actor"]) if "actor" in args else "";
        d_from: int = int(args["day_from"]) if "day_from" in args else -1;
        d_to: int = int(args["day_to"]) if "day_to" in args else -1;
        r = root spawn EventSearch(day=day, day_from=d_from, day_to=d_to,
                                   event_type=et, actor=who, limit=12);
        if not r.reports {
            return {"result": {"count": 0, "events": []}, "answer": {}};
        }
        return {"result": r.reports[0], "answer": {}};
    }
    if name == "gap_scan" {
        eid: str = str(args["event_id"]) if "event_id" in args else "";
        exp: str = str(args["expected"]) if "expected" in args else "";
        a: dict[str, any] = gap_answer_for(eid, exp, f"Was a {exp} produced after {eid}?");
        return {"result": {"answer": "YES" in str(a["verdict"]),
                           "examined": len(a["highlight"] as list),
                           "reason": a["reason"]},
                "answer": a};
    }
    if name == "who_knows" {
        dom: str = str(args["domain"]) if "domain" in args else "";
        a2: dict[str, any] = who_answer_for(dom);
        if "bus" not in a2 {
            return {"result": {"error": f"'{dom}' is not a subsystem",
                               "known": known_domains()}, "answer": {}};
        }
        return {"result": {"bus_factor": a2["bus"], "doc_status": a2["doc"],
                           "still_here_top": a2["top"],
                           "ranking": (a2["evidence"] as list)[:8]},
                "answer": a2};
    }
    if name == "could_have_known" {
        p: str = str(args["person"]) if "person" in args else "";
        dy: int = int(args["as_of_day"]) if "as_of_day" in args else 60;
        ev: str = str(args["event_id"]) if "event_id" in args else "";
        a3: dict[str, any] = visibility_answer(p, dy, ev);
        a3["title"] = f"Could {p} have known about {ev} by day {dy}?";
        return {"result": {"could_have_known": "YES" in str(a3["verdict"]),
                           "reason": a3["reason"]},
                "answer": a3};
    }
    if name == "bottlenecks" {
        mb: int = int(args["max_bus"]) if "max_bus" in args else 2;
        br = root spawn Bottlenecks(max_bus=mb, as_of_day=60);
        if not br.reports {
            return {"result": {"count": 0, "domains": []}, "answer": {}};
        }
        # The inner WhoKnows walkers report into the SAME list, so reports[0]
        # is one of theirs, not the aggregate. Pick the report that carries the
        # summary key rather than trusting position.
        bp: dict[str, any] = {};
        for rep in br.reports {
            rd: dict[str, any] = rep;
            if "threshold" in rd {
                bp = rd;
            }
        }
        if not bp {
            return {"result": {"count": 0, "domains": []}, "answer": {}};
        }
        rows: list[any] = bp["domains"] as list;
        bans: dict[str, any] = empty_answer();
        bans["title"] = f"Subsystems with a bus factor of {mb} or less";
        bans["verdict"] = f"{len(rows)} subsystem(s) at risk";
        bans["reason"] = "Bus factor is the number of current employees with real evidence in the subsystem — not mentions, but weight of what they wrote, decayed on a 30-day half-life.";
        bans["evidence"] = [
            f"{r['domain']} — bus factor {r['bus_factor']}, {r['doc_status']}"
            + (f", held by {', '.join(r['still_here'])}" if r["still_here"] else ", nobody current")
            for r in rows
        ];
        bans["highlight"] = [str(r["domain"]) for r in rows];
        return {"result": bp, "answer": bans if rows else {}};
    }
    if name == "path_between" {
        pa: str = str(args["a"]) if "a" in args else "";
        pb: str = str(args["b"]) if "b" in args else "";
        md: int = int(args["max_depth"]) if "max_depth" in args else 6;
        pr = root spawn PathBetween(a=pa, b=pb, max_depth=md);
        if not pr.reports {
            return {"result": {"found": False}, "answer": {}};
        }
        pp: dict[str, any] = pr.reports[0];
        # The chain is handed to the canvas as a walk, so a connection the
        # agent describes in words is also drawn as a route across the graph.
        hops: list[list[str]] = [[str(h["from"]), str(h["to"])]
                                 for h in (pp["path"] as list)];
        ans: dict[str, any] = empty_answer();
        ans["title"] = f"How is {pa} connected to {pb}?";
        ans["verdict"] = (f"connected in {len(hops)} hop(s)" if pp["found"]
                          else "no route found");
        ans["reason"] = str(pp["reason"]);
        ans["evidence"] = [f"{h['from']} -{h['edge']}-> {h['to']}"
                           for h in (pp["path"] as list)];
        ans["path"] = hops;
        ans["highlight"] = [str(h["to"]) for h in (pp["path"] as list)];
        return {"result": pp, "answer": ans if hops else {}};
    }
    if name == "describe_node" {
        gid: str = str(args["gid"]) if "gid" in args else "";
        c: dict[str, any] = node_card(gid);
        # `body` is REMOVED, not truncated. The claim this project makes is
        # that the model cannot invent a fact because it never reads the
        # corpus; handing it artifact prose here would quietly retire that
        # claim in exchange for slightly better narration. Metadata is enough
        # to navigate by, and navigation is the model's whole job.
        return {"result": {
            "gid": c["gid"], "kind": c["kind"], "title": c["title"],
            "day": c["day"], "dept": c["dept"], "subsystem": c["subsystem"],
            "authors": c["authors"], "domains": c["domains"],
            "references": (c["refs"] as list)[:10],
            "note": "metadata only — this system does not expose artifact text to the model"
        }, "answer": {}};
    }
    if name == "neighbors" {
        gid2: str = str(args["gid"]) if "gid" in args else "";
        hp: int = int(args["hops"]) if "hops" in args else 1;
        if hp > 2 {
            hp = 2;
        }
        sl: dict[str, any] = expand_node(gid2, hp);
        nodes: list = (sl["nodes"] as list)[:25];
        links: list = (sl["links"] as list)[:40];
        return {"result": {
            "count": len(sl["nodes"] as list),
            "nodes": [{"id": n["id"], "type": n["type"]} for n in nodes],
            "edges": [{"from": l["source"], "type": l["type"], "to": l["target"]}
                      for l in links]
        }, "answer": {}};
    }
    if name == "inherited" {
        bd: int = int(args["before_day"]) if "before_day" in args else 60;
        r2 = root spawn Inherited(before_day=bd);
        if not r2.reports {
            return {"result": {"found": False}, "answer": {}};
        }
        return {"result": r2.reports[0], "answer": {}};
    }
    return {"result": {"error": f"no such tool '{name}'"}, "answer": {}};
}


# A one-line summary of what a tool did, for the trace shown in the panel.
# Arguments rendered to one line HERE rather than in the client. Iterating a
# dict's items on the client lowers to JS object semantics and is a needless
# risk for something the server already holds as a plain dict.
def arg_line(args: dict[str, any]) -> str {
    parts: list[str] = [];
    for (k, v) in args.items() {
        parts.append(str(k) + "=" + str(v));
    }
    return ", ".join(parts);
}


def trace_note(name: str, res: dict[str, any]) -> str {
    if name == "find_event" {
        n: int = int(res["count"]) if "count" in res else 0;
        return f"{n} event(s) matched" if n > 0 else "no event matched";
    }
    if name == "gap_scan" {
        hit: bool = bool(res["answer"]) if "answer" in res else False;
        ex: int = int(res["examined"]) if "examined" in res else 0;
        return (f"found it — {ex} records examined" if hit
                else f"nothing — {ex} records examined, space closed");
    }
    if name == "who_knows" {
        if "error" in res {
            return "unknown subsystem";
        }
        return f"bus factor {res['bus_factor']} · {res['doc_status']}";
    }
    if name == "could_have_known" {
        return "reachable" if res["could_have_known"] else "not reachable";
    }
    if name == "bottlenecks" {
        return str(res["count"]) + " subsystem(s) at or under the threshold";
    }
    if name == "path_between" {
        return str(res["reason"]) if "reason" in res else "no route";
    }
    if name == "describe_node" {
        return (str(res["kind"]) + " · " + str(res["title"])[:40]) if res["kind"] else "unknown node";
    }
    if name == "neighbors" {
        return str(res["count"]) + " neighbour(s)";
    }
    if name == "inherited" {
        return str(res["name"]) + " left holding " + ", ".join([str(x) for x in res["domains"]]) if ("name" in res and res["name"]) else "no departure found";
    }
    return "done";
}


def:pub agent(text: str) -> dict[str, any] {
    if not api_key() {
        # No key, no loop. The single-call parser still answers the four
        # canned shapes, so the pane degrades instead of going dark.
        return chat(text, "");
    }

    msgs: list[any] = [
        {"role": "system", "content": agent_system()},
        {"role": "user", "content": text}
    ];
    trace: list[dict[str, any]] = [];
    answers: list[dict[str, any]] = [];
    final: str = "";
    turn: int = 0;

    while turn < MAX_TURNS {
        turn += 1;
        m: dict[str, any] = llm_turn(msgs);
        if not m {
            break;
        }
        calls: list[any] = (m["tool_calls"] as list) if "tool_calls" in m and m["tool_calls"] else [];
        if not calls {
            final = str(m["content"]) if "content" in m and m["content"] else "";
            break;
        }
        msgs.append(m);
        for tc in calls {
            fn: dict[str, any] = tc["function"];
            name: str = str(fn["name"]);
            args: dict[str, any] = {};
            try {
                args = json.loads(str(fn["arguments"]));
            } except Exception as e {
                args = {};
            }
            out: dict[str, any] = run_tool(name, args);
            res: dict[str, any] = out["result"];
            if out["answer"] {
                answers.append(out["answer"]);
            }
            trace.append({"tool": name, "args": arg_line(args),
                          "note": trace_note(name, res)});
            msgs.append({"role": "tool", "tool_call_id": tc["id"],
                         "content": json.dumps(res)});
        }
    }

    # Union of everything the walkers lit up. Several walkers can run in one
    # question — three gap scans over three incidents — and the canvas shows
    # all of it as one search.
    path: list[list[str]] = [];
    hl: list[str] = [];
    ev: list[str] = [];
    for a4 in answers {
        # Per-answer slice as well as a global cap, so a fan-out of twelve
        # scans shows a bit of each rather than all of the first one.
        for pair in (a4["path"] as list)[:12] {
            if len(path) < 90 {
                path.append([pair[0] as str, pair[1] as str]);
            }
        }
        # Capped. Twelve gap scans union to 581 nodes, which paints the
        # starburst the walk-as-a-tree work removed — a lit blob reads as
        # "everything is relevant", which is the opposite of the claim.
        for g in (a4["highlight"] as list)[:14] {
            gs: str = g as str;
            if gs not in hl and len(hl) < 140 {
                hl.append(gs);
            }
        }
        for e2 in (a4["evidence"] as list)[:6] {
            es: str = e2 as str;
            if es not in ev {
                ev.append(es);
            }
        }
    }

    # One walker answered, so its verdict IS the answer and gets the headline.
    # Several walkers answered, so the headline is the model's sentence and the
    # verdicts live in the trace — no single one of them is the answer.
    verdict: str = str(answers[0]["verdict"]) if len(answers) == 1 else "";
    reason: str = str(answers[0]["reason"]) if len(answers) == 1 else "";
    ctx: str = "";
    for a5 in answers {
        if "top" in a5 {
            ctx = str(a5["title"]).replace("Who knows ", "").replace("?", "");
        }
    }

    if not final and not answers {
        final = "I could not resolve that against the graph.";
    }

    return {
        "title": text, "verdict": verdict, "reason": reason,
        "evidence": ev[:10], "highlight": hl, "path": path,
        "say": final, "chips": [], "ctx_domain": ctx,
        "route": f"{len(trace)} tool call(s) · {turn} turn(s) · {KIMI_MODEL}",
        "trace": trace
    };
}


# ---------------------------------------------------- 7. the agent, streamed
#
# `agent` above runs the whole loop server-side and returns once. That is the
# right shape for a script and the wrong one for a person: a question with a
# twelve-way fan-out sits on "walking the graph…" for fifteen seconds with
# nothing to read, and the most interesting part of this system — which tool it
# reached for, and what came back — happens entirely out of sight.
#
# `agent_step` runs exactly ONE model turn and hands the conversation back, so
# the client can loop and paint each turn as it lands. State travels in the
# round trip rather than living on the server: no session table, no expiry, no
# cross-request races, and a reload simply starts a new question.
def:pub agent_step(text: str, state: str, history: str) -> dict[str, any] {
    if not api_key() {
        one: dict[str, any] = chat(text, "");
        return {"done": True, "state": "", "steps": [], "answer": one,
                "turn": 1, "max_turns": 1};
    }

    msgs: list[any] = [];
    answers: list[any] = [];
    turn: int = 0;
    if state {
        try {
            st: dict[str, any] = json.loads(state);
            msgs = st["msgs"] as list;
            answers = st["answers"] as list;
            turn = int(st["turn"]);
        } except Exception as e {
            msgs = [];
        }
    }
    if not msgs {
        # Prior turns are replayed as ONE reference message rather than as a
        # real transcript. The loop rewrites `msgs` every step, so replaying
        # tool calls verbatim would re-enter old tool_call/tool pairs and the
        # model would answer the previous question again. A summary carries
        # what pronouns need — who "her" is, which subsystem "it" was — without
        # dragging the old plan along with it.
        msgs = [{"role": "system", "content": agent_system()}];
        if history {
            msgs.append({"role": "user",
                         "content": "Earlier in this conversation (context only — do not re-answer these):\n"
                                    + history
                                    + "\n\nResolve any pronoun or bare name in the next question against the above."});
        }
        msgs.append({"role": "user", "content": text});
    }

    turn += 1;
    steps: list[dict[str, any]] = [];
    m: dict[str, any] = llm_turn(msgs);
    calls: list[any] = (m["tool_calls"] as list) if (m and "tool_calls" in m and m["tool_calls"]) else [];

    # No tool calls, or the model failed, or we are out of turns: this is the
    # last step, so assemble the same payload `agent` would have returned.
    if not calls or turn >= MAX_TURNS {
        final: str = str(m["content"]) if (m and "content" in m and m["content"]) else "";
        # Out of turns mid-exploration. The model has results in hand but was
        # about to reach for another tool, so asking it again WITH tools just
        # burns the budget again. One tool-less turn forces it to answer from
        # what it already has — which beats discarding real findings and
        # printing "I could not resolve that", as it did when asked what was
        # connected to TitanDB after four useful calls.
        # Guarded on `final` alone. The earlier `len(msgs) > 2` check meant a
        # first turn that produced neither a tool call nor content — which
        # happens when reasoning eats the whole token budget — fell straight
        # through to "I could not resolve that", with nothing even attempted.
        if not final {
            msgs.append({"role": "user",
                         "content": "Stop searching. Answer now, in one or two short sentences, using only what the tools above already returned. If they were not enough, say exactly what is still unresolved."});
            m2: dict[str, any] = llm_turn(msgs, False);
            final = str(m2["content"]) if (m2 and "content" in m2 and m2["content"]) else "";
        }
        if not final and not answers {
            final = "I could not resolve that against the graph.";
        }
        return {"done": True, "state": "", "steps": [],
                "answer": assemble(text, answers, final, turn),
                "turn": turn, "max_turns": MAX_TURNS};
    }

    msgs.append(m);
    for tc in calls {
        fn: dict[str, any] = tc["function"];
        name: str = str(fn["name"]);
        args: dict[str, any] = {};
        try {
            args = json.loads(str(fn["arguments"]));
        } except Exception as e {
            args = {};
        }
        out: dict[str, any] = run_tool(name, args);
        res: dict[str, any] = out["result"];
        if out["answer"] {
            answers.append(out["answer"]);
        }
        steps.append({"tool": name, "args": arg_line(args),
                      "note": trace_note(name, res)});
        msgs.append({"role": "tool", "tool_call_id": tc["id"],
                     "content": json.dumps(res)});
    }

    return {
        "done": False,
        "state": json.dumps({"msgs": msgs, "answers": answers, "turn": turn}),
        "steps": steps,
        "answer": {},
        "turn": turn,
        "max_turns": MAX_TURNS
    };
}


# The union of everything the walkers lit up, plus the headline rules. Shared
# by `agent` and `agent_step` so the streamed and unstreamed paths cannot drift
# apart in what they claim.
# "0 walker(s) · 1 turn(s)" reads like a stub. This line is the receipt for the
# answer above it, so it is worth spelling out.
def route_line(walkers: int, turns: int) -> str {
    t: str = f"{turns} turn" + ("" if turns == 1 else "s");
    if walkers == 0 {
        return f"answered from the tool definitions · no walker run · {t} · {KIMI_MODEL}";
    }
    w: str = f"{walkers} walker" + ("" if walkers == 1 else "s");
    return f"{w} · {t} · {KIMI_MODEL}";
}


def assemble(text: str, answers: list[any], final: str, turns: int) -> dict[str, any] {
    path: list[list[str]] = [];
    hl: list[str] = [];
    ev: list[str] = [];
    for a4 in answers {
        for pair in (a4["path"] as list)[:12] {
            if len(path) < 90 {
                path.append([pair[0] as str, pair[1] as str]);
            }
        }
        for g in (a4["highlight"] as list)[:14] {
            gs: str = g as str;
            if gs not in hl and len(hl) < 140 {
                hl.append(gs);
            }
        }
        for e2 in (a4["evidence"] as list)[:6] {
            es: str = e2 as str;
            if es not in ev {
                ev.append(es);
            }
        }
    }
    verdict: str = str(answers[0]["verdict"]) if len(answers) == 1 else "";
    reason: str = str(answers[0]["reason"]) if len(answers) == 1 else "";
    ctx: str = "";
    for a5 in answers {
        if "top" in a5 {
            ctx = str(a5["title"]).replace("Who knows ", "").replace("?", "");
        }
    }
    return {
        "title": text, "verdict": verdict, "reason": reason,
        "evidence": ev[:10], "highlight": hl, "path": path,
        "say": final, "chips": [], "ctx_domain": ctx,
        "route": route_line(len(answers), turns),
        "trace": []
    };
}
