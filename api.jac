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
import from main { GraphSlice, Visibility, GapScan, WhoKnows, Expand, NodeCard, Inherited }

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
    DOMAIN_CACHE["names"] = names;
    DOMAIN_CACHE["ready"] = True;
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
  "key": one of "onboarding","postmortem","gap35","felix","janice_see","who","best","none"
  "domain": a subsystem name from the list below, or ""
Meaning:
  onboarding = was the new hire Janice ever given an onboarding session
  postmortem = was a postmortem written for the day-25 incident
  gap35      = was the day-35 knowledge gap ever documented
  felix      = could Felix have known about the day-32 CRM touchpoint
  janice_see = could Janice have known about the day-3 design discussion
  who        = who knows / owns a subsystem, bus factor
  best       = who is the best person to pick up, do, own, or write something
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
    if key == "none" {
        return {"intent": "none"};
    }
    return {};
}


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
    } else {
        a["title"] = text;
        a["verdict"] = "out of scope";
        a["reason"] = "This graph answers three shapes of question, and this is not one of them.";
        a["evidence"] = [
            "who knows <subsystem> — ranking and bus factor",
            "who should pick up <subsystem> — the same ranking, minus the leavers",
            "was <X> ever written after <event> — a proven absence",
            "could <person> have known about <event> — reachability on that day"
        ];
        say = "I can only answer what the graph can prove. Try one of the four shapes listed.";
        route = "no walker matched";
    }

    # The walker call, and which parser produced it. Both are shown in the UI:
    # the point of the pane is that a sentence became a traversal, and the
    # audience should be able to see which sentence became which traversal.
    a["say"] = say;
    a["route"] = route + ("  ·  parsed by " + slots["by"] if "by" in slots else "");
    a["ctx_domain"] = ctx;
    return a;
}
