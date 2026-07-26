# orgmem — API contract

**Project:** organizational memory for agents. A graph of who knows what, where it's written, and
where it isn't. Built on the orgforge corpus (fictional company "Apex Athletics", 60 simulated days).

**Today's scope: STRUCTURAL ONLY. No LLM calls anywhere.** Every answer below is pure graph
traversal — deterministic, instant, no API key. The inferred/knowledge layer comes later.

Backend is Jac (`main.jac`), served with `jac start`. Frontend is a static page in `web/` that calls
those walker endpoints. This file is the boundary between the two; both sides build against it.

---

## Transport

`jac start main.jac -p 8899` exposes every top-level walker as:

```
POST /walker/<WalkerName>      body = JSON object of the walker's `has` fields
```

Response envelope: `{"reports": [ ... ]}` — `reports[0]` is the payload (verbatim; `report` does not
wrap or splice). Frontend must read `reports[0]`.

CORS: the page will be opened from `file://` or a local static server. If the browser blocks the
call, serve the page from the same origin as `jac start`, or add permissive CORS. **Backend agent:
verify this works and document whichever approach succeeded.**

---

## Node types

| Node | Key fields |
|---|---|
| `Person` | `name`, `dept`, `role`, `joined_day`, `departed_day`, `documented_pct` |
| `Department` | `name` |
| `Domain` | `name`, `aliases: list[str]`, `is_genesis_gap: bool` |
| `Event` | `event_id`, `event_type`, `day`, `is_incident` |
| `SlackThread` `Email` `ConfluencePage` `JiraTicket` `ZoomTranscript` `PullRequest` | `doc_id`, `title`, `body`, `day`, `dept` |

Artifacts are **separate node types**, not one type with a `kind` field. That is what makes
dispatch-on-arrival load-bearing: `can collect with ConfluencePage entry` vs
`can collect with SlackThread entry`. Adding a source type = adding an ability.

## Edge types (all derivable with no LLM)

| Edge | From → To | Source column |
|---|---|---|
| `Authored` | Person → Artifact | `actors` |
| `Refs` | Artifact → Artifact | `artifact_ids` |
| `Relates` (has `weight: float`) | Person → Person | `top_relationships` |
| `Estranged` (has `weight: float`) | Person → Person | `estranged_pairs` |
| `MemberOf` | Person → Department | `dept` |
| `Mentions` | Artifact → Domain | `tags` / domain `system_tags` |
| `Involves` | Event → Person | `actors` |
| `Produced` | Event → Artifact | `artifact_ids` |
| `DepartedWith` | Person → Domain | `departed_employees.knowledge_domains` |
| `CoOccurs` (has `weight: int`) | Domain → Domain | domains sharing an artifact |

**CRITICAL PARSING GOTCHA:** `actors`, `tags` and `artifact_ids` in `corpus.parquet` are stored as
**JSON strings, not lists**. Iterating them without `json.loads()` yields single characters and
silently produces a graph with zero edges. This is the single most likely way today fails.

**PERSISTENCE GOTCHA:** re-running a `with entry` block that builds the graph **duplicates it**.
Guard construction: `if not [root --> [?:Department]] { ...build... }`.

---

## Endpoints

### 1. `GraphSlice` — data for the canvas
Request: `{"dept": "Engineering_Backend", "max_nodes": 400, "day_max": 60}`
(all optional; `dept` empty = all)

Response `reports[0]`:
```json
{
  "nodes": [{"id":"...","label":"...","type":"Person|SlackThread|Domain|...","dept":"...","day":12}],
  "edges": [{"s":"...","t":"...","type":"Authored","weight":1.0}],
  "counts": {"nodes": 380, "edges": 1120, "truncated": true}
}
```
Must cap at `max_nodes` — the canvas cannot render 22k nodes. Prefer keeping Person and Domain nodes
and sampling artifacts.

### 2. `Visibility` — the PERSPECTIVE query, the flagship
Request: `{"actor": "Felix", "as_of_day": 32, "access": ["confluence","email","slack","zendesk"], "target_event": "EVT-..."}`
(`target_event` optional)

Response `reports[0]`:
```json
{
  "actor": "Felix",
  "as_of_day": 32,
  "cone": ["doc_id", "..."],          // artifact ids reachable within time+access
  "missed": ["OPP-1001"],             // relevant artifacts outside the cone
  "blocked_subsystems": ["salesforce"],
  "could_have_known": false,
  "reason": "human-readable sentence",
  "path": [["Felix","ENG-173"],["ENG-173","PR-129"]]   // edges walked, for animation
}
```
Rules: nothing with `day > as_of_day` enters the cone. Artifacts whose source system is not in
`access` are blocked. Reachability is via `Authored` / `Refs` / `Involves` from the actor.

### 3. `GapScan` — the SILENCE query
Request: `{"trigger_event_id": "EVT-38-knowledge_gap_detected-1453", "expected_response_type": "confluence_created", "window_days": 14}`

Response `reports[0]`:
```json
{
  "trigger": {"event_id":"...","event_type":"...","day":38},
  "expected": "confluence_created",
  "found": [],                        // artifacts/events matching the expected response
  "answer": false,                    // false = the expected follow-up never happened
  "searched": ["CONF-HR-001","..."],  // the bounded space actually examined — this is the proof
  "reason": "human-readable sentence"
}
```
The `searched` list matters: it is the evidence that the space was exhaustively checked, which is
exactly what retrieval cannot provide.

### 4. `WhoKnows` — structural expertise ranking
Request: `{"domain": "TitanDB", "as_of_day": 60, "limit": 10}`

Response `reports[0]`:
```json
{
  "domain": "TitanDB",
  "people": [{"name":"Janice","score":12.5,"artifacts":8,"last_touch_day":57,"departed":false}],
  "departed_with_knowledge": [{"name":"Bill","domains":[...],"documented_pct":0.2}],
  "bus_factor": 1,
  "doc_status": "DEBUGGED_ONLY"       // SPECIFIED | DOCUMENTED_ONLY | DEBUGGED_ONLY | UNDOCUMENTED
}
```
Score is structural for now: count of authored artifacts mentioning the domain, weighted by recency.
`doc_status` for today: `SPECIFIED` if a ConfluencePage mentions it, `DEBUGGED_ONLY` if only
Slack/Jira do, `UNDOCUMENTED` if nothing does.

### 5. `Expand` — click a node to grow the graph
Request: `{"node_id": "CONF-ENG-001", "hops": 1}`
Response: same shape as `GraphSlice`.

---

## Frontend layout

Single page, dark, matching `web/styles.css` (copied from Graph Lab; `kernel.js` is there too and
already renders graphs, animates walker tokens, and handles ~500 nodes).

```
┌────────────────┬──────────────────────────────────┐
│  ASK           │                                  │
│  [ input     ] │      GRAPH CANVAS                │
│                │      (nodes, edges, walker       │
│  ▸ preset Qs   │       token animating the path)  │
│                │                                  │
│  ── answer ──  │                                  │
│  verdict       │                                  │
│  reason        ├──────────────────────────────────┤
│  evidence list │  legend · counts · dept filter   │
└────────────────┴──────────────────────────────────┘
```

- **Left panel:** a question box plus preset buttons drawn from the real eval questions. Answer
  renders as a verdict line, a reason, and a clickable evidence list. Clicking evidence highlights
  that node on the canvas.
- **Canvas:** the graph. When a query runs, animate a walker token along the returned `path` and
  light up the visited nodes. **This animation is the demo** — the judge must see the walker move.
- **Node colour by type**, size by degree. Click a node → `Expand`.
- Show live counts and let the user filter by department.

Preset questions to ship (pulled from the eval set, all answerable structurally):
1. "Could Felix have known about the CRM touchpoint on day 32?" → `Visibility` (expect **no** — blocked by salesforce access)
2. "Could Janice have known about the day-3 design discussion?" → `Visibility` (expect **no** — no artifact was ever created)
3. "Was a Confluence page created after the day-38 knowledge gap?" → `GapScan`
4. "Who knows TitanDB?" → `WhoKnows` (expect Bill surfaced as departed with 20% documented)

---

## Build order

1. Ingest + structural graph, persisted. Verify counts.
2. `GraphSlice` + canvas rendering. **A picture on screen is the first milestone.**
3. `Visibility` + walker animation. This is the flagship.
4. `GapScan`, `WhoKnows`, `Expand`.

If time runs short, 1–3 alone is a demo.
