# orgmem — organizational memory as a spatial graph.
#
# Structural layer only: every answer below is pure traversal over edges derived
# from columns. No `by llm()` anywhere, no API key, deterministic.
#
#   jac run   main.jac            -> ingest + print counts
#   jac start main.jac -p 8899    -> serve every :pub walker at POST /walker/<Name>

import json;
import os;
import time;
import pandas;


# ---------------------------------------------------------------- archetypes

node Ent {
    has gid: str;
    has label: str = "";
    has kind: str = "";
}

node Person(Ent) {
    has name: str = "";
    has dept: str = "";
    has role: str = "";
    has joined_day: int = 0;
    has departed_day: int = 0;
    has documented_pct: float = -1.0;
}

node Department(Ent) {
    has name: str = "";
}

node Domain(Ent) {
    has name: str = "";
    has aliases: list[str] = [];
    has is_genesis_gap: bool = False;
}

node Event(Ent) {
    has event_id: str = "";
    has event_type: str = "";
    has day: int = 0;
    has is_incident: bool = False;
    # artifact_ids keys present with an empty value: the simulation declared a
    # document slot for this event and nothing was ever written into it. This
    # is the corpus telling you, in its own hand, where the silence is.
    has unfulfilled: list[str] = [];
}

# Artifacts are separate node types, not one type with a `kind` field — that is
# what lets a walker dispatch on arrival (`can x with ConfluencePage entry`).
node Artifact(Ent) {
    has doc_id: str = "";
    has title: str = "";
    has body: str = "";
    has day: int = 0;
    has dept: str = "";
    has subsystem: str = "";
}

node SlackThread(Artifact) {}
node Email(Artifact) {}
node ConfluencePage(Artifact) {}
node JiraTicket(Artifact) {}
node ZoomTranscript(Artifact) {}
node PullRequest(Artifact) {}
node SFOpportunity(Artifact) {}
node ZDTicket(Artifact) {}

# Index nodes keep the hub's fan-out at 5 instead of 16,000.
# A public Slack channel. Membership is inferred from having posted in it —
# the corpus has no roster — which models "would this reach them through
# normal channels" without assuming everyone reads everything.
node Channel(Ent) { has name: str = ""; }

node Index { has kind: str; }
node Hub { has label: str = "orgmem"; }

edge Authored {}
edge Refs {}
edge Relates { has weight: float = 1.0; }
edge Estranged { has weight: float = 0.5; }
edge MemberOf {}
edge Mentions {}
edge Involves {}
edge Produced {}
edge DepartedWith {}
edge CoOccurs { has weight: float = 1.0; }
edge Concerns {}
edge InChannel {}
edge Subscribes {}

# Relative evidence weight of each artifact type when ranking expertise. A
# specification outweighs a debugging thread by an order of magnitude; without
# this every prolific Slack user outranks the person who wrote the spec.
glob KIND_WEIGHT: dict[str, float] = {
    "ConfluencePage": 8.0, "PullRequest": 3.0, "JiraTicket": 2.5,
    "ZoomTranscript": 1.5, "Email": 1.2, "SFOpportunity": 1.0,
    "ZDTicket": 1.0, "SlackThread": 0.3
};

# Parsed corpus, handed from the pandas layer to the graph builder.
obj Loaded {
    has people: list[dict[str, any]] = [];
    has depts: list[str] = [];
    has domains: list[dict[str, any]] = [];
    has artifacts: list[dict[str, any]] = [];
    has events: list[dict[str, any]] = [];
    has prs: list[dict[str, any]] = [];
    has relates: list[any] = [];
    has estranged: list[any] = [];
    has departed: list[any] = [];
}


# ---------------------------------------------------------------- module state

glob HUB: Hub = Hub(label="orgmem");
glob IDX_PERSON: Index = Index(kind="Person");
glob IDX_DEPT: Index = Index(kind="Department");
glob IDX_DOMAIN: Index = Index(kind="Domain");
glob IDX_ART: Index = Index(kind="Artifact");
glob IDX_EVENT: Index = Index(kind="Event");
glob IDX_CHANNEL: Index = Index(kind="Channel");

# id -> node, so a walker can find its entry point in O(1) and then traverse.
glob PEOPLE: dict[str, Person] = {};
glob DEPTS: dict[str, Department] = {};
glob DOMAINS: dict[str, Domain] = {};
glob ARTS: dict[str, Artifact] = {};
glob EVENTS: dict[str, Event] = {};
glob CHANNELS: dict[str, Channel] = {};
glob STATS: dict[str, any] = {};

glob REPO_DIR: str = os.path.dirname(os.path.abspath(__file__));
glob DATA_DIR: str = os.path.join(REPO_DIR, "data");

glob SUBSYSTEM: dict[str, str] = {
    "slack": "slack", "email": "email", "confluence": "confluence",
    "jira": "jira", "zoom_transcript": "zoom", "pr": "git",
    "sf_opp": "salesforce", "zd_ticket": "zendesk"
};

glob ART_CLASS: dict[str, any] = {
    "slack": SlackThread, "email": Email, "confluence": ConfluencePage,
    "jira": JiraTicket, "zoom_transcript": ZoomTranscript, "pr": PullRequest,
    "sf_opp": SFOpportunity, "zd_ticket": ZDTicket
};

# An expected downstream response names either an event type or an artifact type.
glob EXPECTED_ARTIFACT: dict[str, str] = {
    "confluence_created": "ConfluencePage",
    "postmortem_created": "ConfluencePage",
    "runbook_created": "ConfluencePage",
    "jira_ticket_created": "JiraTicket",
    "sf_deals_risk_flagged": "SFOpportunity",
    "zd_ticket_opened": "ZDTicket",
    "pr_review": "PullRequest",
    "email_sent": "Email",
    "customer_email_routed": "Email"
};


# ---------------------------------------------------------------- helpers

# Anything coming back from pandas is untyped; funnel it through these so the
# checker sees a concrete container.
def anylist(x: any) -> list[any] {
    return list(x);
}


# Parse one of the JSON-string columns. `facts` has two empty sentinels (None
# and ""), and a few rows hold neither an object nor an array.
def jl(s: any, fallback: any) -> any {
    if isinstance(s, str) and s.strip() {
        if s.startswith("[") or s.startswith("{") {
            return json.loads(s);
        }
    }
    return fallback;
}


def node_dict(n: any) -> dict[str, any] {
    d: dict[str, any] = {"id": n.gid, "label": n.label, "type": n.kind};
    if isinstance(n, Person) {
        d["dept"] = n.dept;
        d["day"] = n.joined_day;
        d["departed"] = n.departed_day != 0;
    } elif isinstance(n, Artifact) {
        d["dept"] = n.dept;
        d["day"] = n.day;
        d["subsystem"] = n.subsystem;
    } elif isinstance(n, Event) {
        d["dept"] = "";
        d["day"] = n.day;
        d["is_incident"] = n.is_incident;
    } else {
        d["dept"] = "";
        d["day"] = 0;
    }
    return d;
}


# Outgoing typed edges of `n` whose target is in the emitted node set. Reads
# endpoints off the edge anchor rather than zipping two traversals, so it
# cannot silently misalign.
def out_edges(n: any, included: dict[str, bool]) -> list[any] {
    res: list[any] = [];
    for e in [edge n-->] {
        et: str = type(e).__name__;
        if et == "GenericEdge" {
            continue;
        }
        t: any = e.__jac__.target.archetype;
        if not isinstance(t, Ent) {
            continue;
        }
        if t.gid not in included {
            continue;
        }
        res.append({
            "s": n.gid, "t": t.gid, "type": et,
            "weight": float(getattr(e, "weight", 1.0))
        });
    }
    return res;
}


def slice_payload(nodes: list[any], truncated: bool) -> dict[str, any] {
    included: dict[str, bool] = {};
    for n in nodes {
        included[n.gid] = True;
    }
    out_n: list[any] = [];
    out_e: list[any] = [];
    for n in nodes {
        out_n.append(node_dict(n));
        for e in out_edges(n, included) {
            out_e.append(e);
        }
    }
    return {
        "nodes": out_n,
        "edges": out_e,
        "counts": {"nodes": len(out_n), "edges": len(out_e), "truncated": truncated}
    };
}


def find_node(gid: str) -> any {
    if gid in PEOPLE { return PEOPLE[gid]; }
    if gid in ARTS { return ARTS[gid]; }
    if gid in EVENTS { return EVENTS[gid]; }
    if gid in DOMAINS { return DOMAINS[gid]; }
    if gid in DEPTS { return DEPTS[gid]; }
    if gid in CHANNELS { return CHANNELS[gid]; }
    return None;
}


# Some artifacts reach the whole company regardless of who wrote them: ticket
# trackers and code review are org-readable, and a public Slack channel is a
# noticeboard. A postmortem counts too, because incidents get announced.
# Deliberately NOT broadcast: DMs, external email, and team retrospectives —
# those need direct participation, which is what makes the silence real.
def broadcast(a: any) -> bool {
    k: str = str(a.kind);
    if k == "JiraTicket" or k == "PullRequest" {
        return True;
    }
    if k == "SlackThread" {
        return len([a ->:InChannel:->]) > 0;
    }
    if k == "ConfluencePage" {
        for e in [a <-:Produced:<-] {
            if e.is_incident {
                return True;
            }
        }
    }
    return False;
}


def allowed(a: any, access: list[str]) -> bool {
    if not access {
        return True;
    }
    return a.subsystem in access;
}


# ---------------------------------------------------------------- ingest

def load_data -> Loaded {
    t0: float = time.time();
    df: any = pandas.read_parquet(os.path.join(DATA_DIR, "corpus.parquet"));
    snap: dict[str, any] = json.load(open(os.path.join(DATA_DIR, "sim_snapshot.json")));
    registry: list[any] = anylist(json.load(open(os.path.join(DATA_DIR, "domain_registry.json"))));

    # `day` is a 0 sentinel on 9,544 rows including every Confluence page and
    # 99.7% of Slack. Recover it as the Nth business day from 2026-01-01.
    bd: dict[str, int] = {};
    for (i, t) in enumerate(anylist(pandas.bdate_range("2026-01-01", "2026-06-01"))) {
        bd[str(t.strftime("%Y-%m-%d"))] = i + 1;
    }

    # `actors` carries bots, vendors and customer orgs too. stress_snapshot is
    # billed as the roster but holds 7 vendors (Datadog, HashiCorp, …) and 8
    # external contacts alongside the staff. Employees are the single-token
    # names; the only two-token exception is the new hire Ethan Patel, who is
    # recovered from new_hires. Without this filter the canvas shows an
    # "Amazon Web Services" person and centrality crowns a monitoring tool.
    vendors: dict[str, bool] = {
        "HashiCorp": True, "Datadog": True, "GitHub": True,
        "Confluent": True, "CloudBees": True
    };
    roster: dict[str, bool] = {};
    for k in anylist(snap["stress_snapshot"].keys()) {
        if " " not in str(k) and str(k) not in vendors {
            roster[str(k)] = True;
        }
    }
    departed: dict[str, dict[str, any]] = {};
    for e in anylist(snap["departed_employees"]) {
        departed[str(e["name"])] = e;
        roster[str(e["name"])] = True;
    }
    hires: dict[str, dict[str, any]] = {};
    for h in anylist(snap["new_hires"]) {
        hires[str(h["name"])] = h;
        roster[str(h["name"])] = True;
    }

    domains: list[dict[str, any]] = [];
    for r in registry {
        domains.append({
            "name": str(r["domain"]),
            "aliases": [str(x) for x in anylist(r.get("system_tags", []))],
            "is_genesis_gap": bool(r.get("is_genesis_gap", False))
        });
    }

    # Deploy escape hatches, read from the platform environment (never a file).
    # Defaults ingest everything: the full 22,530 rows build in ~9s, well inside
    # a build timeout. Set ORGMEM_SKIP_EVENTS=1 for an artifacts-only graph
    # (~3s), or ORGMEM_MAX_EVENTS=N to cap the sim_event rows.
    skip_events: bool = os.environ.get("ORGMEM_SKIP_EVENTS", "") == "1";
    max_events: int = int(os.environ.get("ORGMEM_MAX_EVENTS", "0") or "0");

    artifacts: list[dict[str, any]] = [];
    events: list[dict[str, any]] = [];
    dept_votes: dict[str, dict[str, int]] = {};
    dept_names: dict[str, bool] = {};

    for row in anylist(df.itertuples()) {
        cat: any = row.category;
        if not isinstance(cat, str) {
            continue;                       # 6,622 telemetry / dept-plan rows
        }
        actors: list[str] = [str(a) for a in anylist(jl(row.actors, [])) if str(a) in roster];
        tags: list[str] = [str(x) for x in anylist(jl(row.tags, []))];
        refs_raw: any = jl(row.artifact_ids, {});
        refs: list[str] = [];
        if isinstance(refs_raw, dict) {
            for v in anylist(refs_raw.values()) {
                if isinstance(v, str) and v {
                    refs.append(v);
                }
            }
        }
        day: int = bd.get(str(row.date), int(row.day));
        dept: str = str(row.dept) if isinstance(row.dept, str) else "";
        if dept {
            dept_names[dept] = True;
            for a in actors {
                if a not in dept_votes {
                    dept_votes[a] = {};
                }
                dept_votes[a][dept] = dept_votes[a].get(dept, 0) + 1;
            }
        }
        if cat == "artifact" {
            dt: str = str(row.doc_type);
            if dt not in ART_CLASS {
                continue;
            }
            chan: str = "";
            if dt == "slack" {
                tt: str = str(row.title).strip();
                # 418 of the 431 channels are DMs / group DMs; those are private
                # and must never widen anyone's cone.
                if tt.startswith("#") and not tt.startswith("#dm_") {
                    chan = tt;
                }
            }
            artifacts.append({
                "channel": chan,
                "doc_id": str(row.doc_id), "doc_type": dt,
                "title": str(row.title)[:200], "body": str(row.body)[:1200],
                "day": day, "dept": dept, "actors": actors, "tags": tags,
                "refs": refs
            });
        } elif cat == "sim_event" {
            if skip_events {
                continue;
            }
            if max_events > 0 and len(events) >= max_events {
                continue;
            }
            # `facts.gap_areas` / `orphaned_domains` name the domains a
            # knowledge-gap event is about, comma-joined or as a list. This is
            # the causal link the SILENCE questions turn on.
            fx: any = jl(row.facts, {});
            edomains: list[str] = [];
            if isinstance(fx, dict) {
                for key in ["gap_areas", "orphaned_domains", "domains"] {
                    raw: any = fx.get(key, []);
                    if isinstance(raw, str) {
                        for part in raw.split(", ") {
                            if part and part not in edomains { edomains.append(part); }
                        }
                    } elif isinstance(raw, list) {
                        for part in anylist(raw) {
                            if str(part) not in edomains { edomains.append(str(part)); }
                        }
                    }
                }
            }
            unful: list[str] = [];
            if isinstance(refs_raw, dict) {
                for (rk, rv) in refs_raw.items() {
                    if not rv {
                        unful.append(str(rk));
                    }
                }
            }
            events.append({
                "event_id": str(row.doc_id), "event_type": str(row.doc_type),
                "day": day, "is_incident": bool(row.is_incident),
                "actors": actors, "refs": refs, "domains": edomains,
                "unfulfilled": unful
            });
        }
    }

    people: list[dict[str, any]] = [];
    for name in sorted(roster.keys()) {
        votes: dict[str, int] = dept_votes.get(name, {});
        best: str = "";
        bestn: int = 0;
        for (dname, c) in votes.items() {
            if c > bestn {
                best = dname;
                bestn = c;
            }
        }
        dep: dict[str, any] = departed.get(name, {});
        hire: dict[str, any] = hires.get(name, {});
        if not best {
            best = str(dep.get("dept", "") or hire.get("dept", "") or "");
        }
        people.append({
            "name": name,
            "dept": best,
            "role": str(hire.get("role", "") or dep.get("reason", "") or ""),
            "joined_day": int(hire.get("day", 0)),
            "departed_day": int(dep.get("day", 0)),
            "documented_pct": float(dep.get("documented_pct", -1.0))
        });
    }

    prs: list[dict[str, any]] = [];
    for p in anylist(snap["pr_registry"]) {
        who: list[str] = [str(p.get("author", ""))];
        for rv in anylist(p.get("reviewers", [])) {
            who.append(str(rv));
        }
        pday: int = 0;
        comments: list[any] = anylist(p.get("comments", []));
        if comments {
            pday = bd.get(str(comments[0].get("date", "")), 0);
        }
        linked: list[str] = [];
        for x in [p.get("linked_ticket", ""), p.get("ticket_id", "")] {
            if isinstance(x, str) and x {
                linked.append(x);
            }
        }
        prs.append({
            "doc_id": str(p["pr_id"]),
            "title": str(p.get("title", ""))[:200],
            "body": str(p.get("description", ""))[:1200],
            "day": pday,
            "actors": [w for w in who if w in roster],
            "linked": linked
        });
    }

    print(f"[ingest] parsed corpus in {time.time() - t0:.1f}s");
    return Loaded(
        people=people, depts=sorted(dept_names.keys()), domains=domains,
        artifacts=artifacts, events=events, prs=prs,
        relates=anylist(snap["top_relationships"]),
        estranged=anylist(snap["estranged_pairs"]),
        departed=anylist(snap["departed_employees"])
    );
}


def build_graph {
    t0: float = time.time();
    d: Loaded = load_data();

    HUB ++> IDX_PERSON;
    HUB ++> IDX_DEPT;
    HUB ++> IDX_DOMAIN;
    HUB ++> IDX_ART;
    HUB ++> IDX_EVENT;
    HUB ++> IDX_CHANNEL;

    n_edges: int = 0;

    for dp in d.depts {
        dnode: Department = Department(gid=dp, label=dp, kind="Department", name=dp);
        DEPTS[dp] = dnode;
        IDX_DEPT ++> dnode;
    }

    for p in d.people {
        pname: str = str(p["name"]);
        pnode: Person = Person(
            gid=pname, label=pname, kind="Person", name=pname,
            dept=str(p["dept"]), role=str(p["role"]),
            joined_day=int(p["joined_day"]), departed_day=int(p["departed_day"]),
            documented_pct=float(p["documented_pct"])
        );
        PEOPLE[pname] = pnode;
        IDX_PERSON ++> pnode;
        if pnode.dept in DEPTS {
            pnode +>:MemberOf():+> DEPTS[pnode.dept];
            n_edges += 1;
        }
    }

    for dm in d.domains {
        dmname: str = str(dm["name"]);
        dmnode: Domain = Domain(
            gid=dmname, label=dmname, kind="Domain", name=dmname,
            aliases=[str(x) for x in anylist(dm["aliases"])],
            is_genesis_gap=bool(dm["is_genesis_gap"])
        );
        DOMAINS[dmname] = dmnode;
        IDX_DOMAIN ++> dmnode;
    }

    for a in d.artifacts {
        aid: str = str(a["doc_id"]);
        cls: any = ART_CLASS[str(a["doc_type"])];
        anode: Artifact = cls(
            gid=aid, label=str(a["title"]) or aid, kind=str(cls.__name__),
            doc_id=aid, title=str(a["title"]), body=str(a["body"]),
            day=int(a["day"]), dept=str(a["dept"]),
            subsystem=SUBSYSTEM[str(a["doc_type"])]
        );
        ARTS[aid] = anode;
        IDX_ART ++> anode;
    }

    # The 60 real pull requests live in the snapshot; the corpus `pr` rows are
    # reviewer-audit records that carry the id but none of the content.
    for p in d.prs {
        pid: str = str(p["doc_id"]);
        if pid in ARTS {
            continue;
        }
        prnode: PullRequest = PullRequest(
            gid=pid, label=str(p["title"]) or pid, kind="PullRequest",
            doc_id=pid, title=str(p["title"]), body=str(p["body"]),
            day=int(p["day"]), dept="Engineering_Backend", subsystem="git"
        );
        ARTS[pid] = prnode;
        IDX_ART ++> prnode;
    }

    # Dedupe subscriptions through a dict rather than re-reading each person's
    # edges per thread — that check was ~9k traversals over 2.3k threads.
    subbed: dict[str, bool] = {};
    for a in d.artifacts {
        cname: str = str(a["channel"]);
        if not cname {
            continue;
        }
        if cname not in CHANNELS {
            cn: Channel = Channel(gid=cname, label=cname, kind="Channel", name=cname);
            CHANNELS[cname] = cn;
            IDX_CHANNEL ++> cn;
        }
        ARTS[str(a["doc_id"])] +>:InChannel():+> CHANNELS[cname];
        n_edges += 1;
        for who in anylist(a["actors"]) {
            wn: str = str(who);
            key: str = wn + "|" + cname;
            if wn in PEOPLE and key not in subbed {
                subbed[key] = True;
                PEOPLE[wn] +>:Subscribes():+> CHANNELS[cname];
                n_edges += 1;
            }
        }
    }

    for e in d.events {
        eid: str = str(e["event_id"]);
        etype: str = str(e["event_type"]);
        enode: Event = Event(
            gid=eid, label=etype, kind="Event",
            event_id=eid, event_type=etype,
            day=int(e["day"]), is_incident=bool(e["is_incident"]),
            unfulfilled=[str(x) for x in anylist(e["unfulfilled"])]
        );
        EVENTS[eid] = enode;
        IDX_EVENT ++> enode;
    }

    print(f"[ingest] nodes built in {time.time() - t0:.1f}s");

    # --- Authored: Person -> Artifact, from `actors`
    for a in d.artifacts {
        an: Artifact = ARTS[str(a["doc_id"])];
        for who in anylist(a["actors"]) {
            PEOPLE[str(who)] +>:Authored():+> an;
            n_edges += 1;
        }
    }
    for p in d.prs {
        pid2: str = str(p["doc_id"]);
        if pid2 not in ARTS {
            continue;
        }
        pn: Artifact = ARTS[pid2];
        for who in anylist(p["actors"]) {
            PEOPLE[str(who)] +>:Authored():+> pn;
            n_edges += 1;
        }
        for ref in anylist(p["linked"]) {
            rid: str = str(ref);
            if rid in ARTS and rid != pid2 {
                pn +>:Refs():+> ARTS[rid];
                n_edges += 1;
            }
        }
    }

    # --- Refs: Artifact -> Artifact, from `artifact_ids` (values that resolve)
    for a in d.artifacts {
        aid2: str = str(a["doc_id"]);
        an2: Artifact = ARTS[aid2];
        for ref in anylist(a["refs"]) {
            rid2: str = str(ref);
            if rid2 in ARTS and rid2 != aid2 {
                an2 +>:Refs():+> ARTS[rid2];
                n_edges += 1;
            }
        }
    }

    # --- Involves: Event -> Person, Produced: Event -> Artifact
    for e in d.events {
        en2: Event = EVENTS[str(e["event_id"])];
        for who in anylist(e["actors"]) {
            en2 +>:Involves():+> PEOPLE[str(who)];
            n_edges += 1;
        }
        for ref in anylist(e["refs"]) {
            rid3: str = str(ref);
            if rid3 in ARTS {
                en2 +>:Produced():+> ARTS[rid3];
                n_edges += 1;
            }
        }
        # Concerns: Event -> Domain, the gap/incident's declared subject matter.
        for dnm in anylist(e["domains"]) {
            if str(dnm) in DOMAINS {
                en2 +>:Concerns():+> DOMAINS[str(dnm)];
                n_edges += 1;
            }
        }
    }

    # --- Relates / Estranged: Person -> Person
    for r in d.relates {
        a0: str = str(r[0]);
        a1: str = str(r[1]);
        if a0 in PEOPLE and a1 in PEOPLE {
            PEOPLE[a0] +>:Relates(weight=float(r[2])):+> PEOPLE[a1];
            n_edges += 1;
        }
    }
    for r in d.estranged {
        b0: str = str(r[0]);
        b1: str = str(r[1]);
        if b0 in PEOPLE and b1 in PEOPLE {
            PEOPLE[b0] +>:Estranged(weight=float(r[2])):+> PEOPLE[b1];
            n_edges += 1;
        }
    }

    # --- DepartedWith: Person -> Domain
    for dep in d.departed {
        dn: str = str(dep["name"]);
        if dn not in PEOPLE {
            continue;
        }
        for dmn in anylist(dep["knowledge_domains"]) {
            dms: str = str(dmn);
            if dms in DOMAINS {
                PEOPLE[dn] +>:DepartedWith():+> DOMAINS[dms];
                n_edges += 1;
            }
        }
    }

    # --- Mentions: Artifact -> Domain by alias match; CoOccurs from co-mention
    alias: list[any] = [];
    for (dname2, dnode2) in DOMAINS.items() {
        keys: list[str] = [x.lower() for x in dnode2.aliases];
        keys.append(dname2.lower());
        alias.append((dname2, keys));
    }
    co: dict[any, int] = {};
    n_mentions: int = 0;
    for a in d.artifacts {
        an3: Artifact = ARTS[str(a["doc_id"])];
        hay: str = (
            str(a["title"]) + " " + str(a["body"]) + " "
            + " ".join([str(t) for t in anylist(a["tags"])])
        ).lower();
        hit: list[str] = [];
        for (dname3, keys2) in alias {
            for k in keys2 {
                if k in hay {
                    hit.append(str(dname3));
                    break;
                }
            }
        }
        for h in hit {
            an3 +>:Mentions():+> DOMAINS[h];
            n_mentions += 1;
        }
        for i in range(len(hit)) {
            for j in range(i + 1, len(hit)) {
                pairkey: any = (hit[i], hit[j]);
                co[pairkey] = co.get(pairkey, 0) + 1;
            }
        }
    }
    n_edges += n_mentions;

    n_co: int = 0;
    for (pairkey2, w) in co.items() {
        DOMAINS[pairkey2[0]] +>:CoOccurs(weight=float(w)):+> DOMAINS[pairkey2[1]];
        n_co += 1;
    }
    n_edges += n_co;

    by_type: dict[str, int] = {};
    for (aid3, anode3) in ARTS.items() {
        by_type[anode3.kind] = by_type.get(anode3.kind, 0) + 1;
    }
    STATS["nodes"] = {
        "Person": len(PEOPLE), "Department": len(DEPTS), "Domain": len(DOMAINS),
        "Artifact": len(ARTS), "Event": len(EVENTS), "Channel": len(CHANNELS)
    };
    STATS["artifact_types"] = by_type;
    STATS["edges_total"] = n_edges;
    STATS["mentions"] = n_mentions;
    STATS["cooccurs"] = n_co;
    STATS["build_seconds"] = round(time.time() - t0, 1);
}


# ---------------------------------------------------------------- 1. GraphSlice

walker :pub GraphSlice {
    has dept: str = "";
    has max_nodes: int = 400;
    has day_max: int = 60;

    # Node ids that MUST appear in the slice, whatever the cap or the filters
    # say. The caller passes the ids an answer is going to highlight, so the
    # canvas can light up its route without re-fetching a different layout.
    # Unknown ids are skipped rather than erroring — the caller is allowed to
    # hand over a union of ids gathered from several answers.
    has include: list[str] = [];
    # Per-included-node neighbour allowance. An included node with none of its
    # own neighbours present renders as an isolated star hanging off the graph;
    # a handful of real neighbours puts it back in a neighbourhood. Neighbours
    # are best-effort and share the leftover budget with the artifact sample.
    has neighbors: int = 4;

    # The payload is mirrored onto the walker as well as reported. Over HTTP the
    # report lands in data.reports[0]; the generated client surfaces the walker
    # archetype instead. Carrying it in both places means `counts` is present
    # whichever transport the caller uses, and it is never absent — the client
    # reads it unconditionally.
    has nodes: list[any] = [];
    has edges: list[any] = [];
    has counts: dict[str, any] = {"nodes": 0, "edges": 0, "truncated": False};

    can start with Root entry { visit HUB; }

    can slice with Hub entry {
        keep: list[any] = [];
        # `seen` is what makes the three passes composable: an included id that
        # is also a Person must not be emitted twice, or the renderer gets two
        # nodes with the same id.
        seen: dict[str, bool] = {};
        pinned: list[any] = [];
        for gid in self.include {
            n: any = find_node(str(gid));
            if n is None or n.gid in seen {
                continue;
            }
            seen[n.gid] = True;
            keep.append(n);
            pinned.append(n);
        }
        # People, Domains and Departments always survive the cap; artifacts are
        # sampled evenly across the corpus so the canvas stays renderable.
        for p in [IDX_PERSON-->[?:Person]] {
            if p.gid in seen {
                continue;
            }
            if not self.dept or p.dept == self.dept {
                seen[p.gid] = True;
                keep.append(p);
            }
        }
        for dm in [IDX_DOMAIN-->[?:Domain]] {
            if dm.gid in seen {
                continue;
            }
            seen[dm.gid] = True;
            keep.append(dm);
        }
        for dp in [IDX_DEPT-->[?:Department]] {
            if dp.gid in seen {
                continue;
            }
            if not self.dept or dp.name == self.dept {
                seen[dp.gid] = True;
                keep.append(dp);
            }
        }
        # Half of whatever is left goes to the pinned nodes' neighbourhoods, so
        # seeding a large include list cannot starve the background sample down
        # to nothing — the slice still has to look like the org, not like the
        # answer.
        nb_budget: int = max(0, (self.max_nodes - len(keep)) // 2);
        if pinned and nb_budget > 0 and self.neighbors > 0 {
            # Adjacency census over the pinned set first. A walker's route is
            # often NOT a chain of graph edges — Visibility reaches a thread
            # through `Person -Subscribes-> Channel <-InChannel- Artifact`, so
            # the two ends of its recorded hop share a neighbour rather than an
            # edge. Pinning both ends and nothing else leaves them unconnected
            # on screen no matter how correct the answer is.
            adj: dict[str, int] = {};
            near: dict[str, any] = {};
            for pn in pinned {
                for nb in [pn-->] + [pn<--] {
                    if not isinstance(nb, Ent) or nb.gid in seen {
                        continue;
                    }
                    adj[nb.gid] = adj.get(nb.gid, 0) + 1;
                    near[nb.gid] = nb;
                }
            }
            # Connectors — adjacent to two or more pinned nodes — buy the most
            # structure per slot: one Channel can rejoin a dozen pinned threads.
            for gid in adj.keys() {
                if nb_budget <= 0 {
                    break;
                }
                if adj[gid] < 2 {
                    continue;
                }
                seen[gid] = True;
                keep.append(near[gid]);
                nb_budget -= 1;
            }
            # Then a few plain neighbours each, so a pinned node that shares
            # nothing with the rest still lands somewhere rather than floating.
            for pn in pinned {
                if nb_budget <= 0 {
                    break;
                }
                taken: int = 0;
                for nb in [pn-->] + [pn<--] {
                    if taken >= self.neighbors or nb_budget <= 0 {
                        break;
                    }
                    if not isinstance(nb, Ent) or nb.gid in seen {
                        continue;
                    }
                    seen[nb.gid] = True;
                    keep.append(nb);
                    taken += 1;
                    nb_budget -= 1;
                }
            }
        }
        cand: list[any] = [];
        for a in [IDX_ART-->[?:Artifact]] {
            if a.gid in seen {
                continue;
            }
            if a.day > self.day_max {
                continue;
            }
            if self.dept and a.dept != self.dept {
                continue;
            }
            cand.append(a);
        }
        room: int = self.max_nodes - len(keep);
        truncated: bool = room < len(cand);
        if room > 0 and cand {
            step: int = max(1, len(cand) // room);
            i: int = 0;
            while i < len(cand) and len(keep) < self.max_nodes {
                if cand[i].gid not in seen {
                    seen[cand[i].gid] = True;
                    keep.append(cand[i]);
                }
                i += step;
            }
        }
        payload: dict[str, any] = slice_payload(keep, truncated);
        self.nodes = payload["nodes"];
        self.edges = payload["edges"];
        self.counts = payload["counts"];
        report payload;
    }
}


# ---------------------------------------------------------------- 2. Visibility

# Max edges recorded per source node for the canvas animation. Display only —
# see `Visibility.hop`. 5 keeps a walk under ~40 nodes, which reads as a route
# on a projector; 120 (the old uncapped fan) read as a gold blob.
glob FAN_MAX: int = 5;


walker :pub Visibility {
    has actor: str = "";
    has as_of_day: int = 60;
    has access: list[str] = [];
    has target_event: str = "";
    has max_nodes: int = 1500;

    has cone: list[str] = [];
    has path: list[list] = [];
    has fan: dict[str, int] = {};
    has linked: dict[str, bool] = {};
    has blocked: list[str] = [];
    has seen: dict[str, bool] = {};
    has ok: bool = True;
    has use_channels: bool = True;  # count public-channel membership as reach
    has quiet: bool = False;        # nested runs (EvalRun) suppress the report
    has could: bool = False;        # verdict, readable off the walker instance
    has verdict: str = "";
    has reason: str = "";
    has missed: list[str] = [];
    has evidence_artifacts: list[str] = [];
    has blocked_subsystems: list[str] = [];

    can start with Root entry { visit HUB; }

    can begin with Hub entry {
        if self.actor not in PEOPLE {
            self.ok = False;
            report {"error": f"unknown actor '{self.actor}'", "known": len(PEOPLE)};
            return;
        }
        p: Person = PEOPLE[self.actor];
        self.seen[p.gid] = True;
        # The actor is the one node that is linked by definition — it is where
        # the route starts, so `hop` has a root to grow the tree from.
        self.linked[p.gid] = True;
        visit p;
    }

    # From a person: everything they wrote, and every event they were in.
    #
    # Channels are traversed FIRST, and the order is load-bearing for the
    # display only. The authored artifacts are a flat person->artifact fan; the
    # channels are the one branch with real depth under them. Running authored
    # first spent the person's whole edge budget on depth-1 spokes and the walk
    # flattened back to a star. Membership of `cone` — and therefore the
    # verdict — is unaffected: an artifact reachable both ways is admitted once
    # whichever arm reaches it first, so the set is identical either way.
    can at_person with Person entry {
        # Public channels this person posts in. Anything said in a room you are
        # in reaches you through normal channels, whether or not you replied —
        # this is what "would they have learned about it" actually means.
        #
        # The channel is recorded as its own hop. Attributing these artifacts
        # straight to the person (the old behaviour) threw away the only
        # intermediate node in the route, which is why every recorded pair
        # shared one source and the walk had no second hop to show. Reading
        # `person -> #qa_support -> thread -> the page it cites` is the claim
        # this demo is making; `person -> thread` was not.
        if self.use_channels {
            for ch in [here ->:Subscribes:->] {
                self.hop(str(here.gid), str(ch.gid));
                for a in [ch <-:InChannel:<-] {
                    if self.admit(a, str(ch.gid)) {
                        visit a;
                    }
                }
            }
        }
        for a in [here ->:Authored:->] {
            if self.admit(a, here.gid) {
                visit a;
            }
        }
        for e in [here <-:Involves:<-] {
            if e.day > self.as_of_day or e.gid in self.seen {
                continue;
            }
            if len(self.seen) >= self.max_nodes {
                continue;
            }
            self.seen[e.gid] = True;
            self.hop(str(here.gid), str(e.gid));
            visit e;
        }
    }

    # An event hands the walker the artifacts it produced.
    can at_event with Event entry {
        for a in [here ->:Produced:->] {
            if self.admit(a, here.gid) {
                visit a;
            }
        }
    }

    # Dispatch-on-arrival: every artifact subtype lands here, extends the cone,
    # and pushes its own outgoing references.
    can at_artifact with Artifact entry {
        self.cone.append(here.doc_id);
        # Reference lineage is bidirectional for visibility: seeing a ticket
        # also surfaces the PR that links to it, not just the docs it links out
        # to. Following only outgoing Refs loses a third of the PERSPECTIVE set.
        for a in [here ->:Refs:->] {
            if self.admit(a, here.gid) {
                visit a;
            }
        }
        for a in [here <-:Refs:<-] {
            if self.admit(a, here.gid) {
                visit a;
            }
        }
    }

    # Records ONE edge for the canvas to animate. Traversal is deliberately NOT
    # affected by this: `cone` — which decides the verdict — is built in
    # `admit` regardless of whether the hop was recorded, so capping breadth
    # here cannot move an eval score.
    #
    # The cap is the whole point. A person reaches ~120 artifacts in one step,
    # and recording all of them produced a 120-spoke star: every pair shared
    # the same source, so the "walk" was one hop replayed 16 times and 30% of
    # the canvas turned gold. Capping the fan per source makes BFS render as a
    # tree that goes DEEP instead of wide, which is what reads as traversal.
    # `linked` is what keeps this a TREE rather than a forest. Without it the
    # cap orphans whole subtrees: once the person's 5 slots are spent, the
    # remaining channels never get their connecting edge, but their artifacts
    # still record `channel -> artifact` — measured as 35 distinct sources of
    # which only 6 were reachable from the actor. A route the audience cannot
    # trace back to the person it started at is not a route.
    def hop(src: str, dst: str) {
        if len(self.path) >= 200 {
            return;
        }
        if src not in self.linked {
            return;
        }
        n: int = self.fan[src] if src in self.fan else 0;
        if n >= FAN_MAX {
            return;
        }
        self.fan[src] = n + 1;
        self.linked[dst] = True;
        self.path.append([src, dst]);
    }

    # Time + access gate. Records the edge walked, for the frontend animation.
    def admit(a: any, src: str) -> bool {
        if a.gid in self.seen {
            return False;
        }
        if a.day > self.as_of_day {
            return False;
        }
        if not allowed(a, self.access) {
            if a.subsystem not in self.blocked {
                self.blocked.append(a.subsystem);
            }
            return False;
        }
        if len(self.seen) >= self.max_nodes {
            return False;
        }
        self.seen[a.gid] = True;
        self.hop(src, a.gid);
        return True;
    }

    can finish with Hub exit {
        if not self.ok {
            return;
        }
        relevant: list[str] = [];
        blocked_rel: list[str] = [];
        late: list[str] = [];
        evidence: list[str] = [];
        reason: str = "";
        code: str = "NO_TARGET_EVENT";
        could: bool = False;
        missed: list[str] = [];

        if self.target_event and self.target_event not in EVENTS {
            code = "UNKNOWN_EVENT";
            reason = f"no event '{self.target_event}' exists in the graph";
        } else {
            if self.target_event {
                evt: Event = EVENTS[self.target_event];
                for a in [evt ->:Produced:->] {
                    relevant.append(str(a.doc_id));
                    if not allowed(a, self.access) {
                        if str(a.subsystem) not in blocked_rel {
                            blocked_rel.append(str(a.subsystem));
                        }
                    } elif a.day > self.as_of_day {
                        late.append(str(a.doc_id));
                    }
                }
                incone: dict[str, bool] = {};
                for c in self.cone {
                    incone[c] = True;
                }
                # An artifact is in reach if the walk found it, or if it is
                # broadcast and the actor holds that subsystem by the cutoff.
                for a in [evt ->:Produced:->] {
                    if str(a.doc_id) in incone {
                        continue;
                    }
                    if a.day <= self.as_of_day and allowed(a, self.access) and broadcast(a) {
                        incone[str(a.doc_id)] = True;
                    }
                }
                missed = [r for r in relevant if r not in incone];
                evidence = [r for r in relevant if r in incone];
                could = bool(relevant) and not missed;

                # A declared-but-empty artifact slot means the document that
                # should exist never did. Being in the room is then the only
                # way to know, so presence in a channel is not enough.
                direct: bool = PEOPLE[self.actor] in [evt ->:Involves:->];
                if evt.unfulfilled and not direct {
                    could = False;
                    for slot in evt.unfulfilled {
                        if slot not in missed {
                            missed.append(slot);
                        }
                    }
                }

                # Three distinct ways the answer can be "no", and they are not
                # interchangeable: a role wall, a document that never existed,
                # and a document that existed only later.
                if evt.unfulfilled and not direct {
                    code = "NEVER_CREATED";
                    reason = f"No {', '.join(evt.unfulfilled)} artifact was generated for the {evt.event_type} on day {evt.day}; awareness would have required direct participation, and {self.actor} was not a participant";
                } elif not relevant {
                    code = "NEVER_CREATED";
                    reason = f"No artifact was ever generated for the {evt.event_type} on day {evt.day}; awareness would have required direct participation, so {self.actor} could not have known through normal channels";
                } elif could {
                    code = "IN_CONE";
                    reason = f"All {len(relevant)} artifact(s) of the event were in {self.actor}'s visibility cone by day {self.as_of_day} via direct involvement or document references";
                } elif blocked_rel {
                    code = "ACCESS_BLOCKED";
                    reason = f"{self.actor} had access to {sorted(self.access)} but the event's artifacts live in {sorted(blocked_rel)}; blocked by role from: {sorted(blocked_rel)}";
                } elif late {
                    code = "AFTER_AS_OF_DAY";
                    reason = f"{len(late)} artifact(s) of the event were not created until after day {self.as_of_day}, so they were outside {self.actor}'s cone at the time of asking";
                } else {
                    code = "NOT_REACHABLE";
                    reason = f"{len(missed)} artifact(s) of the event were never reachable from anything {self.actor} authored or participated in by day {self.as_of_day}";
                }
            } else {
                reason = f"{self.actor} could reach {len(self.cone)} artifact(s) by day {self.as_of_day}; no target event was given";
            }
        }

        self.could = could;
        self.verdict = code;
        self.reason = reason;
        self.missed = missed;
        self.evidence_artifacts = evidence;
        self.blocked_subsystems = blocked_rel;
        if self.quiet {
            return;
        }
        # The walker's own `has` fields are echoed back in the HTTP envelope;
        # drop the traversal bookkeeping so the response stays small.
        self.seen = {};
        self.fan = {};
        report {
            "actor": self.actor,
            "as_of_day": self.as_of_day,
            "cone": self.cone[:400],
            "cone_size": len(self.cone),
            "missed": missed,
            "evidence_artifacts": evidence,
            "blocked_subsystems": blocked_rel,
            "blocked_encountered": self.blocked,
            "could_have_known": could,
            "verdict": code,
            "reason": reason,
            "path": self.path[:120]
        };
    }
}


# ---------------------------------------------------------------- 3. GapScan

walker :pub GapScan {
    has trigger_event_id: str = "";
    has expected_response_type: str = "";
    has window_days: int = 14;
    has max_nodes: int = 400;

    has searched: list[str] = [];
    has found: list[str] = [];
    has path: list[list] = [];
    has domains: list[str] = [];
    has seen: dict[str, bool] = {};
    has lo: int = 0;
    has hi: int = 0;
    has ok: bool = True;
    has quiet: bool = False;
    has answer: bool = False;
    has reason: str = "";
    has searched_count: int = 0;

    can start with Root entry { visit HUB; }

    can begin with Hub entry {
        if self.trigger_event_id not in EVENTS {
            self.ok = False;
            report {"error": f"unknown event '{self.trigger_event_id}'"};
            return;
        }
        e: Event = EVENTS[self.trigger_event_id];
        self.lo = e.day;
        self.hi = e.day + self.window_days;
        self.seen[e.gid] = True;
        visit e;
    }

    # The bounded space is the CAUSAL closure of the trigger: the artifacts it
    # produced, whatever those reference, and the events that produced those —
    # not everything the trigger's actors happened to touch that fortnight.
    # Widening it to the actor/time sweep makes every SILENCE answer "yes".
    can at_event with Event entry {
        if here.gid == self.trigger_event_id {
            for d in [here ->:Concerns:->] {
                if str(d.name) not in self.domains {
                    self.domains.append(str(d.name));
                }
            }
            for a in [here ->:Produced:->] {
                self.consider(a);
                if self.admit(str(a.gid), str(here.gid)) { visit a; }
            }
            return;
        }
        self.consider(here);
        for a in [here ->:Produced:->] {
            self.consider(a);
            if self.admit(str(a.gid), str(here.gid)) { visit a; }
        }
    }

    # Dispatch-on-arrival: the reference graph out of an artifact, plus the
    # events that emitted it, are the only legitimate continuations.
    can at_artifact with Artifact entry {
        for a in [here ->:Refs:->] {
            self.consider(a);
            if self.admit(str(a.gid), str(here.gid)) { visit a; }
        }
        for a in [here <-:Refs:<-] {
            self.consider(a);
            if self.admit(str(a.gid), str(here.gid)) { visit a; }
        }
        for e in [here <-:Produced:<-] {
            if e.day >= self.lo and e.day <= self.hi {
                self.consider(e);
                if self.admit(str(e.gid), str(here.gid)) { visit e; }
            }
        }
    }

    # Gate a node into the walk exactly once, under the size cap. `src` is
    # recorded only so the canvas can animate the search; it has no effect on
    # `searched`, `found`, or the verdict.
    #
    # Animating this one matters more than it looks. The SILENCE claim is that
    # the space is CLOSED — watching the walker exhaust a small bounded region
    # and come back with nothing is the argument. A verdict that appears
    # without a visible search just looks like a lookup that failed.
    def admit(gid: str, src: str) -> bool {
        if gid in self.seen or len(self.seen) >= self.max_nodes {
            return False;
        }
        self.seen[gid] = True;
        if len(self.path) < 200 {
            self.path.append([src, gid]);
        }
        return True;
    }

    # Add a node to the searched space and test it against the expectation.
    def consider(n: any) -> None {
        if n.gid not in self.searched {
            self.searched.append(n.gid);
        }
        want_art: str = EXPECTED_ARTIFACT.get(self.expected_response_type, "");
        hit: bool = False;
        if isinstance(n, Event) and n.event_type == self.expected_response_type {
            hit = True;
        }
        # Artifacts are not day-filtered: the closure is already causally
        # bounded, and the doc that revealed a gap often predates its detection.
        if want_art and isinstance(n, Artifact) and n.kind == want_art {
            hit = True;
        }
        if hit and n.gid not in self.found {
            self.found.append(n.gid);
        }
    }

    can finish with Hub exit {
        if not self.ok {
            return;
        }
        e: Event = EVENTS[self.trigger_event_id];
        ans: bool = bool(self.found);
        self.answer = ans;
        self.searched_count = len(self.searched);
        if self.quiet {
            return;
        }
        subject: str = f" concerning {', '.join(self.domains)}" if self.domains else "";
        reason: str = "";
        if ans {
            reason = f"yes — {len(self.found)} {self.expected_response_type} record(s) are causally linked to the {e.event_type} on day {e.day}{subject}; {len(self.searched)} linked records were examined";
        } else {
            reason = f"no — the {e.event_type} on day {e.day}{subject} produced no {self.expected_response_type}. All {len(self.searched)} records causally reachable from it were examined and none matched; the space is closed, so this is a proven absence rather than a failed search";
        }
        self.reason = reason;
        self.seen = {};
        report {
            "trigger": {"event_id": e.event_id, "event_type": e.event_type, "day": e.day},
            "expected": self.expected_response_type,
            "domains": self.domains,
            "found": self.found[:50],
            "answer": ans,
            "searched": self.searched[:300],
            "searched_count": len(self.searched),
            "window_days": self.window_days,
            "reason": reason,
            "path": self.path[:120]
        };
    }
}


# ---------------------------------------------------------------- 4. WhoKnows

walker :pub WhoKnows {
    has domain: str = "";
    has as_of_day: int = 60;
    has limit: int = 10;

    has score: dict[str, float] = {};
    has counts: dict[str, int] = {};
    has last: dict[str, int] = {};
    has kinds: dict[str, int] = {};
    has specs: dict[str, int] = {};
    has departed: list[dict[str, any]] = [];
    has people: list[any] = [];
    has path: list[list] = [];
    has lit: dict[str, bool] = {};
    has bus_factor: int = 0;
    has doc_status: str = "UNDOCUMENTED";
    has ok: bool = True;

    can start with Root entry { visit HUB; }

    can begin with Hub entry {
        if self.domain not in DOMAINS {
            self.ok = False;
            report {"error": f"unknown domain '{self.domain}'", "known": sorted(DOMAINS.keys())};
            return;
        }
        visit DOMAINS[self.domain];
    }

    can at_domain with Domain entry {
        for p in [here <-:DepartedWith:<-] {
            self.departed.append({
                "name": p.name,
                "domains": [x.name for x in [p ->:DepartedWith:->]],
                "documented_pct": p.documented_pct,
                "departed_day": p.departed_day
            });
        }
        # Record domain -> artifact for the canvas. Capped, because TitanDB is
        # mentioned by 214 artifacts and lighting all of them is a blob rather
        # than a route. Scoring below is unaffected — it iterates the full set.
        for a in [here <-:Mentions:<-] {
            if a.day > self.as_of_day {
                continue;
            }
            if len(self.path) < FAN_MAX {
                self.path.append([str(here.gid), str(a.gid)]);
                self.lit[str(a.gid)] = True;
            }
            visit a;
        }
    }

    # Arrival on the artifact does the scoring. Evidence weight is the artifact
    # type (a spec is worth ~27 Slack messages) decayed by staleness on a
    # 30-day half-life, so "wrote the spec last week" beats "chatted a lot in
    # January". Without both terms the ranking is just who talks most.
    can at_artifact with Artifact entry {
        self.kinds[here.kind] = self.kinds.get(here.kind, 0) + 1;
        kw: float = KIND_WEIGHT.get(here.kind, 1.0);
        age: float = float(self.as_of_day - here.day);
        if age < 0.0 {
            age = 0.0;
        }
        w: float = kw * (0.5 ** (age / 30.0));
        for p in [here <-:Authored:<-] {
            pn: str = str(p.name);
            # Second display hop: artifact -> its author. Only from artifacts
            # that were themselves recorded, so the route stays a connected
            # tree rooted at the domain rather than a scatter of pairs.
            if str(here.gid) in self.lit {
                self.path.append([str(here.gid), pn]);
            }
            self.score[pn] = self.score.get(pn, 0.0) + w;
            self.counts[pn] = self.counts.get(pn, 0) + 1;
            if here.kind == "ConfluencePage" {
                self.specs[pn] = self.specs.get(pn, 0) + 1;
            }
            if here.day > self.last.get(pn, 0) {
                self.last[pn] = here.day;
            }
        }
    }

    can finish with Hub exit {
        if not self.ok {
            return;
        }
        ranked: list[any] = [];
        for (nm, sc) in self.score.items() {
            ranked.append((sc, nm));
        }
        ranked.sort(reverse=True);

        for pair in ranked[:self.limit] {
            nm2: str = str(pair[1]);
            self.people.append({
                "name": nm2,
                "score": round(float(pair[0]), 1),
                "artifacts": self.counts[nm2],
                "specs_authored": self.specs.get(nm2, 0),
                "last_touch_day": self.last.get(nm2, 0),
                "departed": PEOPLE[nm2].departed_day != 0
            });
        }

        # Bus factor: still-here people carrying at least half the evidence
        # weight of the strongest contributor.
        top: float = float(ranked[0][0]) if ranked else 0.0;
        bus: int = 0;
        for pair in ranked {
            if float(pair[0]) >= 0.5 * top and PEOPLE[str(pair[1])].departed_day == 0 {
                bus += 1;
            }
        }

        status: str = "UNDOCUMENTED";
        if self.kinds.get("ConfluencePage", 0) > 0 {
            status = "SPECIFIED";
        } elif self.kinds.get("Email", 0) > 0 or self.kinds.get("ZoomTranscript", 0) > 0 {
            status = "DOCUMENTED_ONLY";
        } elif self.kinds {
            status = "DEBUGGED_ONLY";
        }

        self.bus_factor = bus;
        self.doc_status = status;
        report {
            "domain": self.domain,
            "people": self.people,
            "departed_with_knowledge": self.departed,
            "bus_factor": bus,
            "bus_factor_rule": "still-employed people scoring >= 50% of the top contributor",
            "doc_status": status,
            "evidence_by_type": self.kinds,
            "as_of_day": self.as_of_day,
            "path": self.path[:120]
        };
    }
}


# ------------------------------------------------------- 4a. EventSearch

# The resolver the agent loop leans on hardest. A question names an event in
# words — "the incident on day 25", "when Janice was hired" — and a walker
# needs an id. This turns the words into ids and returns NOTHING when there is
# no match, which is what stops the model inventing one: it cannot proceed
# past an empty result, and the loop reports the miss rather than guessing.
#
# All three filters are optional and AND together. `event_type` matches as a
# substring so "incident" finds "incident_opened".
walker :pub EventSearch {
    has day: int = -1;
    has event_type: str = "";
    has actor: str = "";
    has limit: int = 12;

    has hits: list[dict[str, any]] = [];

    can start with Root entry { visit HUB; }

    can begin with Hub entry {
        want: str = self.event_type.lower();
        who: str = self.actor.lower();
        for (gid, e) in EVENTS.items() {
            if self.day >= 0 and int(e.day) != self.day {
                continue;
            }
            if want and want not in str(e.event_type).lower() {
                continue;
            }
            people: list[str] = [str(p.name) for p in [e ->:Involves:->]];
            if who {
                found: bool = False;
                for p2 in people {
                    if who in p2.lower() {
                        found = True;
                    }
                }
                if not found {
                    continue;
                }
            }
            if len(self.hits) >= self.limit {
                break;
            }
            self.hits.append({
                "event_id": str(e.gid), "event_type": str(e.event_type),
                "day": int(e.day), "is_incident": bool(e.is_incident),
                "involves": people[:6]
            });
        }
        report {"count": len(self.hits), "events": self.hits};
    }
}


# --------------------------------------------------------- 4b. Inherited

# "Nobody onboarded the new hire — so whose work did they inherit?"
#
# The chat pane's follow-up question ("who would be the best person to do it?")
# needs a SUBJECT, and the honest way to find one is structural rather than
# guessed: the most recent departure before the hire, and the domains that left
# with that person. `DepartedWith` is only drawn where the departed person
# actually owned evidence in the domain, so this is a record of what walked out
# of the door, not an assumption about who was supposed to hand over to whom.
walker :pub Inherited {
    has before_day: int = 60;

    has name: str = "";
    has day: int = -1;
    has documented_pct: float = -1.0;
    has domains: list[str] = [];

    can start with Root entry { visit HUB; }

    can begin with Hub entry {
        # Ranked by how little of the knowledge was written down, NOT by
        # `departed_day`. That column does not survive ingest intact — Bill
        # comes back as day -579 — so ordering on it would silently pick the
        # wrong person. Having a `DepartedWith` edge at all is the reliable
        # signal that someone left holding something; `documented_pct` is the
        # reliable measure of how much of it left with them.
        worst: float = 2.0;
        for (nm, p) in PEOPLE.items() {
            doms: list[str] = [str(d.name) for d in [p ->:DepartedWith:->]];
            if not doms {
                continue;
            }
            pct: float = float(p.documented_pct);
            if pct < 0.0 or pct >= worst {
                continue;
            }
            worst = pct;
            self.name = str(p.name);
            self.day = int(p.departed_day);
            self.documented_pct = pct;
            self.domains = doms;
        }
        report {
            "name": self.name, "departed_day": self.day,
            "documented_pct": self.documented_pct, "domains": self.domains
        };
    }
}


# ---------------------------------------------------------------- 5. Expand

walker :pub Expand {
    has node_id: str = "";
    has hops: int = 1;
    has max_nodes: int = 200;

    has nodes: list[any] = [];
    has edges: list[any] = [];
    has counts: dict[str, any] = {"nodes": 0, "edges": 0, "truncated": False};

    can start with Root entry { visit HUB; }

    can begin with Hub entry {
        n: any = find_node(self.node_id);
        if n is None {
            # Still hand back a well-formed, empty slice so the canvas can
            # render nothing instead of throwing on a missing key.
            report {
                "nodes": [], "edges": [],
                "counts": {"nodes": 0, "edges": 0, "truncated": False},
                "error": f"unknown node '{self.node_id}'"
            };
            return;
        }
        seen: dict[str, bool] = {};
        keep: list[any] = [n];
        seen[n.gid] = True;
        frontier: list[any] = [n];
        h: int = 0;
        while h < self.hops and frontier and len(keep) < self.max_nodes {
            nxt: list[any] = [];
            for cur in frontier {
                for nb in [cur-->] + [cur<--] {
                    if not isinstance(nb, Ent) {
                        continue;
                    }
                    if nb.gid in seen {
                        continue;
                    }
                    if len(keep) >= self.max_nodes {
                        break;
                    }
                    seen[nb.gid] = True;
                    keep.append(nb);
                    nxt.append(nb);
                }
            }
            frontier = nxt;
            h += 1;
        }
        payload: dict[str, any] = slice_payload(keep, len(keep) >= self.max_nodes);
        self.nodes = payload["nodes"];
        self.edges = payload["edges"];
        self.counts = payload["counts"];
        report payload;
    }
}


# ---------------------------------------------------------------- 6. Eval

# Scores the shipped walkers against data/eval_questions.jsonl. The graph
# answers the questions with the same code path the UI calls — the harness
# spawns the real walkers rather than re-implementing their logic, so the
# number it prints is the number the demo earns.
walker :pub EvalRun {
    has qtype: str = "";        # "" = all, or PERSPECTIVE / SILENCE
    has limit: int = 0;         # 0 = every question
    has show: bool = True;      # include the per-question table

    can start with Root entry { visit HUB; }

    can go with Hub entry {
        rows: list[any] = [];
        tally: dict[str, list[int]] = {};   # type -> [correct, scored]
        skipped: dict[str, int] = {};
        n: int = 0;

        for line in anylist(open(os.path.join(DATA_DIR, "eval_questions.jsonl"))) {
            if not str(line).strip() {
                continue;
            }
            q: dict[str, any] = json.loads(str(line));
            qt: str = str(q["question_type"]);
            if self.qtype and qt != self.qtype {
                continue;
            }
            if self.limit > 0 and n >= self.limit {
                break;
            }
            gt: dict[str, any] = q["ground_truth"];

            # COUNTERFACTUAL asks whether an outcome would survive removing a
            # cause. That is the simulator's internal counterfactual and is not
            # decidable from the artifacts, so it is reported as skipped rather
            # than guessed at.
            if qt == "COUNTERFACTUAL" {
                skipped[qt] = skipped.get(qt, 0) + 1;
                continue;
            }

            n += 1;
            got: bool = False;
            want: bool = False;
            detail: str = "";

            if qt == "PERSPECTIVE" {
                want = bool(gt["could_actor_have_known"]);
                acc: list[str] = [str(x) for x in anylist(q.get("subsystem_access", []))];
                w: Visibility = HUB spawn Visibility(
                    actor=str(q["actor"]), as_of_day=int(q["as_of_day"]),
                    access=acc, target_event=str(q["event_id"]), quiet=True
                );
                got = w.could;
                detail = w.verdict;
            } elif qt == "SILENCE" {
                want = bool(gt["answer"]);
                w2: GapScan = HUB spawn GapScan(
                    trigger_event_id=str(q["trigger_event_id"]),
                    expected_response_type=str(q["expected_response_type"]),
                    quiet=True
                );
                got = w2.answer;
                detail = f"searched={len(w2.searched)}";
            } else {
                skipped[qt] = skipped.get(qt, 0) + 1;
                n -= 1;
                continue;
            }

            if qt not in tally {
                tally[qt] = [0, 0];
            }
            tally[qt][1] += 1;
            ok: bool = got == want;
            if ok {
                tally[qt][0] += 1;
            }
            rows.append({
                "id": str(q["question_id"])[:62], "type": qt,
                "expected": want, "got": got, "pass": ok, "detail": detail
            });
        }

        summary: list[any] = [];
        tot_c: int = 0;
        tot_n: int = 0;
        for (k, v) in tally.items() {
            tot_c += v[0];
            tot_n += v[1];
            summary.append({
                "type": k, "correct": v[0], "scored": v[1],
                "accuracy": round(100.0 * float(v[0]) / float(v[1]), 1) if v[1] else 0.0
            });
        }

        # A constant answer is the baseline any honest report has to beat.
        base: dict[str, list[int]] = {};
        for r in rows {
            t: str = str(r["type"]);
            if t not in base {
                base[t] = [0, 0];
            }
            base[t][1] += 1;
            if bool(r["expected"]) {
                base[t][0] += 1;
            }
        }
        baseline: list[any] = [];
        for (k2, v2) in base.items() {
            hi: int = max(v2[0], v2[1] - v2[0]);
            baseline.append({
                "type": k2,
                "always_true": round(100.0 * float(v2[0]) / float(v2[1]), 1),
                "best_constant": round(100.0 * float(hi) / float(v2[1]), 1)
            });
        }

        # One line the UI can put on screen during the demo.
        parts: list[str] = [];
        for sm in summary {
            bl: str = "";
            for b in baseline {
                if b["type"] == sm["type"] {
                    bl = f" vs {b['best_constant']}% baseline";
                }
            }
            parts.append(f"{sm['type']} {sm['correct']}/{sm['scored']} = {sm['accuracy']}%{bl}");
        }
        headline: str = " | ".join(parts);

        out: dict[str, any] = {
            "headline": headline,
            "summary": summary,
            "overall": {
                "correct": tot_c, "scored": tot_n,
                "accuracy": round(100.0 * float(tot_c) / float(tot_n), 1) if tot_n else 0.0
            },
            "constant_baseline": baseline,
            "skipped": skipped,
            "skipped_note": "COUNTERFACTUAL asks whether an outcome survives removing a cause. That is the simulator's internal counterfactual and is not decidable from the artifacts, so it is excluded rather than guessed.",
            "failures": [r for r in rows if not bool(r["pass"])],
            "rows": rows
        };

        # Persist inside the repo so the score is reproducible and reviewable.
        fh: any = open(os.path.join(REPO_DIR, "eval_results.json"), "w");
        fh.write(json.dumps(out, indent=2));
        fh.close();

        if not self.show {
            out["rows"] = [];
        }
        report out;
    }
}


# ---------------------------------------------------------------- 7. NodeCard

# Every key the card contract names, present and empty. The client dots into
# this payload without checking for absence, so a MISSING key blanks the whole
# page while an empty one just renders an empty section.
def blank_card(gid: str, kind: str) -> dict[str, any] {
    return {
        "gid": gid, "kind": kind, "title": "", "body": "",
        "day": 0, "dept": "", "subsystem": "",
        "authors": [], "domains": [], "refs": [], "event": None,
        "person": None, "domain": None, "event_detail": None, "dept_detail": None
    };
}


# A clickable row in the card's reference list. `title` falls back to the id so
# a row is never blank — 1,400 artifacts carry an empty title.
def ref_row(a: any) -> dict[str, any] {
    return {"gid": a.gid, "kind": a.kind,
            "title": str(a.title) if a.title else str(a.gid)};
}


# One node, everything the card needs to render it. The five abilities below are
# the whole point of the archetype split: the walker arrives and the node's own
# type decides which shape comes back, so there is no `if kind ==` ladder and no
# way for a Person to be filled in with an artifact's fields.
#
# `here` is the arrived-at node and `self` is the walker — the reverse of a node
# ability, where `here` is not bound at all.
walker :pub NodeCard {
    has gid: str = "";

    can start with Root entry {
        n: any = find_node(self.gid);
        if n is None {
            # Unknown ids reach here routinely: the canvas merges path nodes the
            # slice never had, and a ref can point at an artifact outside the
            # ingested set. An empty card is the answer, not an error.
            report blank_card(self.gid, "");
            return;
        }
        if (isinstance(n, Artifact) or isinstance(n, Person) or isinstance(n, Domain)
            or isinstance(n, Event) or isinstance(n, Department)) {
            visit n;
            return;
        }
        # Channel is a real node type with no card of its own — it renders
        # through the shell's fallback rather than crashing the dispatch.
        other: dict[str, any] = blank_card(str(n.gid), str(n.kind));
        other["title"] = str(n.label);
        report other;
    }

    # Fires for all eight artifact archetypes, which is why they subclass
    # Artifact rather than carrying a `kind` field.
    can on_artifact with Artifact entry {
        c: dict[str, any] = blank_card(str(here.gid), str(here.kind));
        c["title"] = str(here.title);
        c["body"] = str(here.body);
        c["day"] = int(here.day);
        c["dept"] = str(here.dept);
        c["subsystem"] = str(here.subsystem);
        c["authors"] = [str(p.name) for p in [here <-:Authored:<-]][:8];
        c["domains"] = [str(d.name) for d in [here ->:Mentions:->]][:6];
        c["refs"] = [ref_row(a) for a in [here ->:Refs:->]][:8];
        # The event that produced this artifact, if the simulation recorded one.
        # At most one in the corpus, so the first is the only.
        for e in [here <-:Produced:<-] {
            c["event"] = {"gid": str(e.gid), "event_type": str(e.event_type),
                          "day": int(e.day)};
            break;
        }
        report c;
    }

    can on_person with Person entry {
        c: dict[str, any] = blank_card(str(here.gid), "Person");
        c["title"] = str(here.name);
        c["dept"] = str(here.dept);
        # What someone knows is not stored anywhere — it is derived by walking
        # their authored artifacts and tallying what those artifacts mention.
        tally: dict[str, int] = {};
        n_auth: int = 0;
        for a in [here ->:Authored:->] {
            n_auth += 1;
            for d in [a ->:Mentions:->] {
                tally[str(d.name)] = tally.get(str(d.name), 0) + 1;
            }
        }
        ranked: list[any] = [];
        for (nm, ct) in tally.items() {
            ranked.append((ct, nm));
        }
        ranked.sort(reverse=True);
        c["person"] = {
            "name": str(here.name), "dept": str(here.dept), "role": str(here.role),
            "joined_day": int(here.joined_day),
            "departed_day": int(here.departed_day),
            "documented_pct": float(here.documented_pct),
            "authored_count": n_auth,
            "top_domains": [{"name": str(r[1]), "count": int(r[0])}
                            for r in ranked[:8]],
            "departed_domains": [str(d.name) for d in [here ->:DepartedWith:->]]
        };
        report c;
    }

    # `bus_factor`, `doc_status` and the ranked people are NOT computed here —
    # `WhoKnows` already owns that scoring, and `api.jac` layers its report on
    # top of this one so there is exactly one definition of a bus factor.
    can on_domain with Domain entry {
        c: dict[str, any] = blank_card(str(here.gid), "Domain");
        c["title"] = str(here.name);
        c["domain"] = {
            "name": str(here.name),
            "aliases": [str(x) for x in here.aliases],
            "is_genesis_gap": bool(here.is_genesis_gap),
            "artifact_count": len([here <-:Mentions:<-]),
            "doc_status": "", "bus_factor": 0, "people": [],
            "departed_with": [
                {"name": str(p.name), "documented_pct": p.documented_pct}
                for p in [here <-:DepartedWith:<-]
            ][:8]
        };
        report c;
    }

    can on_event with Event entry {
        c: dict[str, any] = blank_card(str(here.gid), "Event");
        c["title"] = str(here.event_type);
        c["day"] = int(here.day);
        c["event_detail"] = {
            "event_id": str(here.event_id), "event_type": str(here.event_type),
            "day": int(here.day), "is_incident": bool(here.is_incident),
            # The document slots the simulation opened and never filled. This
            # list is the silence, stated by the corpus in its own hand.
            "unfulfilled": [str(x) for x in here.unfulfilled],
            "involves": [str(p.name) for p in [here ->:Involves:->]][:8],
            "produced": [ref_row(a) for a in [here ->:Produced:->]][:8]
        };
        report c;
    }

    can on_dept with Department entry {
        c: dict[str, any] = blank_card(str(here.gid), "Department");
        c["title"] = str(here.name);
        c["dept"] = str(here.name);
        members: list[str] = [str(p.name) for p in [here <-:MemberOf:<-]];
        # Artifacts carry their department as a string, not an edge — counting
        # them means a scan of the artifact table rather than a traversal.
        n_art: int = 0;
        for (aid, a) in ARTS.items() {
            if a.dept == here.name {
                n_art += 1;
            }
        }
        c["dept_detail"] = {
            "name": str(here.name), "member_count": len(members),
            "members": members[:8], "artifact_count": n_art
        };
        report c;
    }
}


# ---------------------------------------------------------------- 8. Stats

walker :pub Stats {
    can start with Root entry { visit HUB; }
    can go with Hub entry { report STATS; }
}


# ---------------------------------------------------------------- boot

with entry {
    # Guard construction: this block runs again on every `jac run` and on every
    # `jac start` boot, and an unguarded rebuild would double the graph.
    if not [IDX_DEPT-->[?:Department]] {
        build_graph();
    }
    print("[orgmem]", json.dumps(STATS));
}
