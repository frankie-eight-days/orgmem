# Which nodes to show on the canvas

Derived by rebuilding `main.jac`'s `build_graph()` in Python/NetworkX against
`data/corpus.parquet` + `data/sim_snapshot.json` + `data/domain_registry.json` and computing
centrality on the real graph. The replica reproduces the shipped census exactly:
**15,985 nodes / 76,787 edges** (46 Person, 10 Domain, 8 Department, 14 Channel, 10,941 Event,
4,966 Artifact — 3,303 SlackThread, 610 Email, 479 ConfluencePage, 304 JiraTicket, 208
ZoomTranscript, 57 PullRequest, 3 SFOpportunity, 2 ZDTicket).

Every id below is verified present in the built graph. Betweenness is `k=500`-sample
approximate (`nx.betweenness_centrality(U, k=500, seed=7)`) on the undirected simple projection
(15,985 nodes / 76,464 edges after multi-edge collapse). Degree is undirected simple degree.

---

## 1. Top recommendation

**Stop sampling artifacts. Curate a fixed 217-node "hero" view, and make the second-biggest change
an edge filter, not a node filter.**

The idle view should be a hand-specified set:

> **46 people + 10 domains + 8 departments + 18 narrative nodes + the 12 complete incident chains
> (48 events, 13 Jira, 12 Confluence, 11 PRs, 12 `#incidents` Slack threads) + 34 diversity extras
> (6 Zoom, 6 Email, 5 Confluence, 4 Jira, 4 PR, 8 Slack, 3 SF opps, 2 ZD tickets)**
> = **217 nodes, 1,028 edges, e/n = 4.74**, 2 components, 1 isolate (`ZD-102`).

Then drop all but the single most-specific `Mentions` edge per artifact → **760 edges, e/n = 3.50**,
which lands on the empirical readability boundary (§2). That one edge rule removes 236 of the 346
`Mentions` edges in the view and is where most of the visible hairball actually lives.

**Read §6 before anything else if you are short on time.** The demo's narrative chain has a missing
link in the data — `Janice → TitanDB` does not exist as an edge and no event creates it — and no
amount of node selection fixes that.

Do **not** include `Channel` nodes in the idle view. Adding all 14 costs 354 edges (333 of them
`Subscribes`) and pushes e/n from 4.74 to **5.98** while adding two isolates — the channels are
person-magnets that pull every person into a single blob. Keep channels for the expand-on-click
path only.

Why this beats every alternative tested:

| view | n | e | e/n | comps | note |
|---|---|---|---|---|---|
| **current `GraphSlice(400)`** | 400 | ~2,154 | **5.38** | 10 | strided artifacts; 232/400 are Slack; 0 events |
| k-core ≥ 17 | 115 | 1,528 | **13.29** | 1 | 64/115 are Slack threads — an all-Slack skeleton |
| k-core ≥ 15 | 382 | 5,614 | **14.70** | 1 | worse; k-core *concentrates* the hairball |
| people+domains+depts only | 64 | 155 | 2.42 | 1 | legible but no artifacts, no story |
| 12 incident chains (closed nbhd) | 112 | 321 | **2.87** | 1 | the most legible real substructure in the corpus |
| **recommended S5** | **217** | **1,028** | **4.74** | 2 | all 12 node types present |
| **S5 + specific-`Mentions` filter** | **217** | **760** | **3.50** | 2 | **ship this** |

k-core is the tempting answer and it is the wrong one here: the 17-core is 32 people, 10 domains,
9 channels and **64 Slack threads** — it strips the periphery and exposes a skeleton made entirely
of chat. It also *raises* density (e/n 13–15), because peeling low-degree nodes leaves only the
mutually-dense part. It is a good diagnostic, not a good view.

Query-result views need no policy change: `Visibility` already caps at 1,500 and `GraphCanvas.jac`
already filters to the walked subgraph. Target **25–60 nodes** there, which is what the module
docstring already claims, and it is the right number (§2). (Note: `docs/GRAPH-VIZ-TECHNIQUES.md`
§7.1 argues you should *dim* rather than swap `graphData` for the query view. I agree — with a
curated 217-node idle view that is now affordable, which it was not at 400.)

---

## 1b. How this fills the rings in `GRAPH-VIZ-TECHNIQUES.md`

That document specifies the composition: `forceRadial` type rings crossed with department sectors,
Domains at the centre, People in the main ring, Events and artifacts as an outer halo. This
document decides who stands in each ring. Mapping the recommended 217:

| ring | `RING` r | circumference | spacing needed | capacity | **this selection** | fill |
|---|---|---|---|---|---|---|
| Domain (core) | 30 | 188 u | ~19 u (disc + ring) | **9** | **10** | **101%** ⚠ |
| Department | 85 | 534 u | ~20 u (square + label) | 26 | 8 | 30% |
| Person | 165 | 1,037 u | ~14 u | 74 | 46 | 62% |
| Event | 285 | 1,791 u | ~8 u (diamond) | 223 | 65 | 29% |
| Artifact halo | 320 | 2,011 u | ~6 u (1.5 px hollow dot) | 335 | 89 | 27% |

**One correction to the sibling doc, argued:** `RING.Domain = 30` does not fit 10 domains. The
circle has 188 graph units of circumference; ten discs drawn with a surrounding ring need ~19 u of
arc each just to not touch, so the core ring is at 101% before `forceCollide` starts pushing.
Domains are the always-labelled semantic anchors (§6.2 of that doc), and their labels are the
longest strings in the ring — "legacy auth service", "AWS cost structure". **Raise
`RING.Domain` to 55–60** (circumference 345–377, ~35 u each) and pull `RING.Department` to 105 to
keep the gap. Everything else in that doc's geometry stands unchanged.

Two consequences that follow directly from the ring budget:

- **The composition is not what caps the node count — edges are.** The rings could hold ~640 nodes
  single-file. The recommended view uses 217 and fills the outer two rings to about a quarter. If
  you want a denser-looking halo you can add artifacts up to ~250 and stay inside the ring budget —
  but each additional artifact drags 3–9 `Mentions` edges toward the centre with it, and that is
  what fails first. Add nodes only after the edge filter in §8 is in place, and re-measure e/n.
- **The under-filled Event and artifact rings are a feature.** Angular gaps between department
  sectors are what make the sectors legible as sectors. A 100%-full halo is an annulus, which reads
  as a solid ring, not as seven wedges.

### The sector force has nothing to bind to for 83 of the 217 nodes

`node_dict()` (`main.jac:188–212`) emits `dept` for `Person` and `Artifact` only. **`Event`,
`Domain`, `Department` and `Channel` all get `d["dept"] = ""`.** In the recommended view that is
65 Events + 10 Domains + 8 Departments = 83 nodes with no sector. The sibling doc's
`forceX`/`forceY` sends every one of them to target 0, i.e. the centre.

For Domains that is correct and intended. For the other two it is a bug in the picture:

- **`Department` nodes cannot sit in their own sector.** The dept name lives in `n.name`, not
  `n.dept`. Fix in `node_dict`: `d["dept"] = n.name` for `Department`. One line, and the
  department ring becomes eight labelled anchors, one per wedge — which is exactly the
  "region label" effect §6.2 of the sibling doc asks for.
- **All 65 Events pile onto angle 0.** Derive an Event's dept from its first `Involves` Person.
  Measured: every one of the 48 incident-chain events involves at least one Person, so coverage is
  100% for the chain events; the 18 narrative events include departures whose Person is
  mis-departmented (see §7).
- **30 of the 89 artifacts also have `dept == ""`.** Corpus-wide it is far worse: only **1,203 of
  4,966 artifacts (24%) carry a dept at all** (Engineering_Backend 472, Sales_Marketing 233,
  Engineering_Mobile 176, QA_Support 144, Design 71, Product 58, HR_Ops 49, none 3,763). The
  recommended selection is much better than the corpus average — 59 of 89 (66%) — because incident
  artifacts are consistently Engineering_Backend. Fall back to the dept of the artifact's first
  `Authored` author to close the remaining 30.

Without those three fixes the ring layout will render with a crowded core and a dense spike of
Events and artifacts at 0°. It will look like a bug, and it is a cheap one to avoid.

---

## 2. How many nodes is legible

**Plainly: 400 cannot be made legible with the current node mix, and ~120 is too few. 217 is the
number, and it is a node-mix problem more than a node-count problem.**

The three-way answer, since the question was posed as 400-vs-120:

- **400 fails on edges, not on nodes.** The current slice is 400 nodes / ~2,154 edges (e/n 5.38).
  A ring layout does not fix that — `GRAPH-VIZ-TECHNIQUES.md` §1 says the same thing, and its own
  400-node column recommends hiding all "mist" edges by default to cope. If you hide the mist you
  have thrown away `Authored`, `Refs` and `Mentions`, which is 91% of the edges, and what remains
  is 46 `MemberOf` + 45 `CoOccurs` + 51 `Relates`/`Estranged` + 13 `DepartedWith` = 155 edges —
  and every one of those connects two skeleton nodes, so **all 336 sampled artifacts would have
  no visible edge at all**. A ring of disconnected dots is tidy, not legible.
- **~120 loses the story.** The narrative set (§6) alone is 33 nodes and the twelve incident chains
  are 96 more. At 120 you can have the skeleton and the story, or the skeleton and type diversity,
  but not both — and the artifact halo would hold ~20 dots, which misrepresents a corpus that is
  4,966 artifacts.
- **217 is where all three constraints meet.** Skeleton (64) + narrative (21) + chains (96) + type
  diversity (34) + specific-`Mentions` filter → e/n 3.50, inside the published band, with all
  twelve node types present, and rings filled to 27–62% so the sectors stay readable.

If the density has to come down further, cut from the diversity bucket (§5), not from the chains.
Measured: dropping the 8 top-betweenness Slack threads takes the view to **209 nodes / 888 edges
(e/n 4.25)**, or **663 edges (e/n 3.17)** with the `Mentions` filter applied — 140 edges saved for
8 nodes, because those are precisely the threads that touch 5–9 domains each. That is the cheapest
density lever available and it costs nothing narratively.

Targets, research-backed:

- **Idle / hero view: 200–250 nodes, edge density ≤ 3–4 edges per node.** Yoghourdjian et al.'s
  survey of empirical graph-visualisation studies reports that the effective upper limit for
  node-link layouts sits around a **link density (|E|/|V|) of ≈3**, above which the surplus of edges
  guarantees non-planarity and edge crossings dominate the picture. Node count matters less than
  density — the current view fails on density (5.38) more than on count.
- **Query / walk view: 25–60 nodes.** Yoghourdjian et al.'s cognitive-load study found people
  degrade badly at **path-following in dense graphs beyond ~50 nodes, and beyond ~100 nodes even at
  low density**. A walker traversal is literally a path-following task, so it is governed by the
  strictest of the published limits.
- Ghoniem, Fekete & Castagliola found node-link diagrams lose to matrix representations on most
  tasks **above ~20 nodes** — with **path-finding the one consistent exception** where node-link
  wins throughout. That is the justification for keeping the node-link idiom at all: the demo's
  hero interaction *is* path-finding.
- Projector-specific: at 1280×720 effective projection with the current `nodeRelSize={3}`, 217
  nodes at ~11px labels means roughly 1 node per 4,200 px² — enough for the ~30 labelled nodes the
  walk view shows to be read from the back of a room. 400 nodes at the current settings is ~2,300
  px² per node and labels are suppressed entirely (`draw_label` returns early when not walking),
  which is why the idle view reads as texture.

Sources:
[Yoghourdjian et al. 2018, *Exploring the Limits of Complexity: A Survey of Empirical Studies on Graph Visualisation*, Visual Informatics 2(4)](https://arxiv.org/abs/1809.00270) ·
[Yoghourdjian et al. 2021, *Scalability of Network Visualisation from a Cognitive Load Perspective*, IEEE TVCG](https://pubmed.ncbi.nlm.nih.gov/33301404/) ·
[Ghoniem, Fekete & Castagliola 2005, *On the Readability of Graphs Using Node-Link and Matrix-Based Representations*, Information Visualization 4(2)](https://journals.sagepub.com/doi/10.1057/palgrave.ivs.9500092)

---

## 3. What is actually wrong with the current view

`GraphSlice` (`main.jac:791–853`) keeps every Person, Domain and Department, then fills the
remaining ~336 slots by **striding** the artifact list (`step = len(cand) // room`). Consequences,
measured:

1. **It is 58% Slack.** A stride over the artifact list samples proportionally, and Slack is 66% of
   artifacts. Simulated: 232 SlackThread, 43 Email, 35 Confluence, 21 Jira, 4 PR, 1 SF opp, **0
   Zoom, 0 ZD**. Two of the eight artifact types never appear.
2. **It shows zero events.** `IDX_EVENT` is never traversed. All 10,941 events — including every
   `employee_departed`, `employee_hired`, `incident_opened` and `knowledge_gap_detected` — are
   invisible in the idle view. The story is 100% in the events.
3. **Density 5.38, and it is `Mentions`-driven.** 13,492 of the graph's 76,787 edges are
   `Artifact→Domain` alias matches. 1,420 artifacts mention **4 or more** domains; 294 mention 8+.
   The alias list is so generic (`"titan"`, `"auth"`, `"deploy"`, `"flow"`) that "legacy auth
   service" alone attracts 1,801 mention edges and "auth-service" 1,763. Ten domain nodes with
   1,000–2,700 degree apiece are the hairball.
4. **It fragments.** 10 components and 9 isolated nodes, because a strided artifact often has no
   surviving neighbour.

---

## 4. Which nodes earn a place, with scores

### People — the hubs and the bridges

Betweenness is the useful signal: Jax and Priya are structurally *between* everything else, and
Marcus is a bridge nobody would guess from degree alone.

| person | degree | betweenness | core | dept | role in the picture |
|---|---|---|---|---|---|
| Priya | 3,637 | 0.1392 | 17 | Design | highest degree in the entire graph |
| Jax | 2,908 | **0.1490** | 17 | Engineering_Backend | highest betweenness; in 27 of the 48 incident-chain event slots |
| Marcus | 1,451 | 0.0899 | 17 | Sales_Marketing | bc rank 3 on degree rank 9 — the eng↔sales bridge |
| Chloe | 1,966 | 0.0695 | 17 | — | |
| Deepa | 2,228 | 0.0598 | 17 | Engineering_Backend | 12 incident-chain slots |
| Nadia | 1,956 | 0.0499 | 17 | — | |
| Sarah | 1,654 | 0.0444 | 17 | — | |
| Patty | 1,619 | 0.0302 | 17 | — | |
| Yusuf | 1,698 | 0.0269 | 17 | Engineering_Backend | 16 incident-chain slots; claims redis-cache day 14 |
| Karen | 1,291 | 0.0263 | 17 | HR_Ops | signs Janice's offer letter |
| Morgan | 1,275 | 0.0170 | 17 | Engineering_Backend | departs day 34, 60% documented |
| Janice | **380** | 0.0103 | 15 | Engineering_Backend | new hire day 7 — low degree, high narrative value |
| Jordan | 563 | 0.0058 | 17 | Engineering_Mobile | departs day 12, 25% documented |
| Bill | **433** | 0.0002 | 6 | *(mislabelled, see §7)* | the genesis gap; **bc rank ~40th** |
| Sharon | 463 | 0.0006 | 7 | Engineering_Mobile | second genesis gap |
| Reese | 159 | 0.0031 | 15 | *(mislabelled)* | lowest-degree person in the graph |

**Bill would be sampled away by any centrality-based rule.** Degree 433 puts him below 30 other
people; betweenness 0.00021 puts him ~40th of 46; core number 6 means every k-core ≥ 7 view drops
him. This is the single strongest argument for a pinned narrative set (§6).

Ship **all 46 people**. They cost 46 nodes and 155 edges total when paired with domains and
departments (e/n 2.42) and they are the entities a human viewer recognises.

### Domains — the true super-hubs

| domain | degree | betweenness | mentions | owner (registry) | former |
|---|---|---|---|---|---|
| legacy auth service | 2,694 | 0.0503 | 1,801 | — | Bill, Sharon |
| Project Titan | 2,402 | 0.0444 | 1,509 | Sam | Bill, Sharon |
| AWS cost structure | 2,197 | 0.0366 | 1,304 | — | Bill, Sharon |
| auth-service | 2,152 | 0.0344 | 1,763 | Janice | Jordan |
| oauth2-flow | 1,789 | 0.0350 | 1,400 | Janice | Jordan |
| **TitanDB** | 1,769 | 0.0192 | 1,332 | **Janice** | **Bill** |
| terraform-infra | 1,689 | 0.0274 | 1,476 | Reese/Sanjay | Morgan |
| redis-cache | 1,600 | 0.0233 | 1,211 | Yusuf | Jordan |
| mobile analytics | 1,515 | 0.0286 | 1,050 | — | Sharon |
| kubernetes-deploy | 859 | 0.0134 | 646 | Sanjay | Morgan |

Ship **all 10**. They are only 10 nodes and they are what "org knowledge" means. But they carry
13,492 mention edges between them, so the edge filter in §8 is mandatory if they are shown.

### Departments and channels

8 departments (`Engineering_Backend`, `Engineering_Mobile`, `Sales_Marketing`, `Product`, `HR_Ops`,
`QA_Support`, `Design`, `CEO`). Degrees 1–9; betweenness ~0. They cost nothing (46 `MemberOf`
edges) and give the layout its lobes. **Ship all 8.** `CEO` has degree 1 — one person, one edge;
keep it, it reads as a real org chart.

14 public channels; `#digital-hq` is the only structurally significant one (degree 877, bc 0.0326 —
higher than any single artifact in the corpus by 20×). **Ship zero by default**; expose
`#digital-hq` and `#incidents` on demand.

### Artifacts — best of each type by betweenness

These are the diversity picks. Every one verified present.

**ConfluencePage** (479) — `CONF-ENG-444` bc 0.00072 "Design: API contract alignment" ·
`CONF-ENG-424` 0.00071 "Clarify terraform state suggestion" · `CONF-ENG-021` 0.00056 (day 2,
touches 8 domains) · `CONF-ENG-272` 0.00054 · `CONF-ENG-338` 0.00051 (9 domains, the widest-reaching
page in the corpus).

**JiraTicket** (304) — `ENG-210` bc 0.00135, degree 38, **4 departments** — the single highest-bc
artifact of any type that is not Slack · `ENG-186` 0.00079 (deg 35, 8 domains) · `ENG-123` 0.00075
· `ENG-263` 0.00046 (deg 35, 8 domains) · `ENG-223` 0.00053 · `ENG-106` 0.00044.

**ZoomTranscript** (208) — `zoom_2026-03-06_30075fb2` bc 0.00032 "Define QA metrics for Redis
incident", **5 depts** · `zoom_2026-03-24_c4459b00` 0.00031, 5 depts · `zoom_2026-01-13_b437ed3e`
0.00026, core 14 · `zoom_2026-03-13_01a5921b` · `zoom_2026-02-02_c47b22c6` (Sales↔Eng, 5 depts) ·
`zoom_2026-01-20_31a3f2c5` "Cache incident mitigation plan".

**PullRequest** (57) — `PR-131` bc 0.00063 · `PR-152` 0.00044 · `PR-145` 0.00032 (deg 18) ·
`PR-127` 0.00031.

**Email** (610) — `ext_email_arun_8_6` bc 0.00055 "Terraform-infra Module v2.4" ·
`ext_email_arun_17_6` 0.00054 · `ext_email_ravi_6_6` 0.00050 (deg 16, all 9 domains) ·
`ext_email_yara_27_6` 0.00049 · `ext_email_mona_31_6` 0.00048.

**SlackThread** (3,303) — `slack_digital-hq_2026-03-26T15:47:50.080480` bc 0.00161 (deg 25, core 17,
9 domains) · `slack_digital-hq_2026-01-28T09:00:00` 0.00150 (**7 departments**, 7 domains) ·
`slack_sales_marketing_2026-03-09T17:06:42.036661` 0.00143 · `slack_digital-hq_2026-03-05T12:12:00`
0.00108 (7 depts) · `slack_engineering_mobile_2026-01-08T10:38:45.183009` 0.00106 ·
`slack_digital-hq_2026-01-20T15:08:00` 0.00104 · `slack_digital-hq_2026-02-25T16:27:10.321088`
0.00102 · `slack_digital-hq_2026-03-27T14:05:14.150617` 0.00100.

**SFOpportunity** (3, ship all) — `OPP-1001` degree **85** (Nat'l Olympic Training Center),
`OPP-1002` degree 78 bc 0.00038 (Metro United FC), `OPP-1003` degree 25.
**ZDTicket** (2, ship both) — `ZD-101` degree 5, `ZD-102` degree **1** (it will be an isolate in any
view that omits its one neighbour; accept it or pin the neighbour).

Note the scale gap: the best artifact in the corpus (`slack_digital-hq_2026-03-26…`, bc 0.00161) is
**92× less central than Jax**. Artifacts are never structurally important individually; they earn
their place by *type representation* and by *being on a story*, which is why the quota is by type
and not by score.

### Which of the 3,303 Slack threads are interchangeable texture

Census: median degree **7**, p90 17, p99 23, max 31. **1,626 threads (49%) have degree ≤ 6.** 131
have betweenness exactly **0.0**. 1,012 are DMs (`slack_dm_*`, excluded from `Channel` membership
by `load_data` because DMs are private); 2,291 sit in one of the 14 public channels.

A thread earns a place in the idle view if and only if it satisfies one of three tests. Everything
else — **3,219 of 3,303, i.e. 97%** — is interchangeable texture and should be collapsed (§9), not
sampled:

| test | count | why |
|---|---|---|
| on an incident chain (`slack_incidents_*` produced by an `incident_opened` event) | **12** | narrative, pinned |
| `core == 17` (the maximum core number in the graph) | **64** | the only threads structurally embedded in the dense middle |
| betweenness ≥ 0.001 | **8** | the genuine cross-department bridges, all ≥5 departments |

The three sets overlap (the 8 top-bc threads are all core 17), giving **84 distinct threads** that
are individually defensible; the recommended view takes 21 of them. Every remaining thread is
distinguishable from its neighbours only by timestamp. Note that 1,661 threads touch ≥3
departments — being a cross-department thread is *typical*, not distinguishing, which is why the
test is betweenness and not department count.

### Cross-department bridges

1,868 artifacts touch ≥3 departments — and they are **1,661 Slack, 202 Zoom, 5 Jira, 0 Confluence,
0 Email, 0 PR**. Only 24 artifacts in the whole corpus touch all 7 staffed departments, and 23 of
them are Slack (`#digital-hq` ×20, `#sales_marketing` ×3) plus one `#standup` thread. If you want a
visible cross-department bridge, it has to be a Slack thread or a Zoom transcript; nothing else
crosses. Best single pick: **`slack_digital-hq_2026-01-28T09:00:00`** (7 depts, 7 domains, bc
0.00150).

---

## 5. Quota table

Total **217 nodes**. All 12 node types present; no type below 2.

| bucket | type | count | how chosen | pinned? |
|---|---|---|---|---|
| skeleton | Person | **46** | all | yes |
| skeleton | Domain | **10** | all | yes |
| skeleton | Department | **8** | all | yes |
| narrative | Event | 18 | §6 fixed list (departures, hires, gaps, ownership claims) | **yes — never sample** |
| narrative | Email | 1 | `hr_outbound_janice_4_offer_letter` | **yes** |
| narrative | ConfluencePage | 1 | `CONF-HR-001` (day-38 gap response) | **yes** |
| narrative | SlackThread | 1 | `slack_digital-hq_2026-01-09T13:32:00` | **yes** |
| incident chains | Event | 48 | all 12 × (escalation, opened, resolved, postmortem) | **yes** |
| incident chains | JiraTicket | 13 | the 12 P1 tickets + `PR-111` (mistyped, see §7) | **yes** |
| incident chains | ConfluencePage | 12 | the 12 postmortems | **yes** |
| incident chains | PullRequest | 11 | the 12 fix PRs minus `PR-111` | **yes** |
| incident chains | SlackThread | 12 | the 12 `slack_incidents_*` threads | **yes** |
| diversity | ZoomTranscript | 6 | top betweenness | no |
| diversity | Email | 5 | top betweenness | no |
| diversity | ConfluencePage | 5 | top betweenness, excluding postmortems | no |
| diversity | SlackThread | 8 | top betweenness (all ≥5 depts) | no |
| diversity | JiraTicket | 4 | top betweenness, excluding incident tickets | no |
| diversity | PullRequest | 4 | top betweenness, excluding fix PRs | no |
| diversity | SFOpportunity | 3 | all | no |
| diversity | ZDTicket | 2 | all | no |
| — | Channel | **0** | excluded; +354 edges for 14 nodes | — |

Resulting census: Person 46, Event 65, SlackThread 21, ConfluencePage 18, JiraTicket 17,
PullRequest 15, Domain 10, Department 8, ZoomTranscript 6, Email 6, SFOpportunity 3, ZDTicket 2.

Defence of the numbers: the skeleton (64) is fixed and cheap (e/n 2.42). The 96 incident-chain nodes
are the only substructure in the corpus that is simultaneously *complete*, *repeated 12×* and
*sparse* (e/n 2.87) — they give the picture visible rhythm, twelve near-identical motifs, which is
what makes a viewer perceive structure rather than noise. The 34 diversity extras exist purely so
every colour in `TYPE_COLOR` is on screen; they are the only bucket safe to trim if density needs
to come down further. Trimming Slack from 8 to 4 costs the least (~30 edges each).

---

## 6. The narrative chain — exact ids, never sample these

> ## ⚠ THE CHAIN IS BROKEN AT ITS MOST IMPORTANT LINK
>
> **There is no edge from `Janice` to `TitanDB` in the graph, and there is no event in the corpus
> where Janice takes ownership of TitanDB.** The inheritance — the single beat the whole demo
> turns on — cannot be drawn today, no matter which nodes are pinned. `TitanDB`'s only `Person`
> neighbour is `Bill`. Fix before the demo: emit an `Owns` edge from
> `domain_registry.json[*].primary_owner` (10 edges, one per domain; `titandb.primary_owner`
> **is** `"Janice"`, `former_owner` `"Bill"`). Details and two further corrections below.

Three corrections to the scripted story first, because the renderer will otherwise pin nodes that
do not carry the claimed meaning:

1. **There is no `Janice → TitanDB` edge in the graph.** `Person→Domain` exists only as
   `DepartedWith`. `domain_registry.json` records `titandb.primary_owner = "Janice"`, but
   `build_graph()` never reads `primary_owner`. `TitanDB`'s only Person neighbour is **Bill**.
   The inheritance — the beat the whole demo turns on — is not renderable today. **Add an `Owns`
   edge from `registry[*].primary_owner`** (10 edges total) or synthesise it in the view layer.
2. **Janice never claims TitanDB in the event log.** Her two `domain_ownership_claimed` events on
   day 12 name **`auth-service`** and **`oauth2-flow`** (facts: `pathway: incident_resolution`,
   `documentation_coverage: 0.45`), triggered the same day Jordan departs owning exactly those
   domains at 25% documented. That is a *better* verifiable story than the scripted one and it is
   two hops from TitanDB via `CoOccurs`.
3. **"She never gets an onboarding session" is false as stated.** Janice has 5 `mentoring` events
   and 2 `1on1` events in days 7–9 (Yusuf, Raj, Tom, Zoe, Chris, Jordan, Mike). What *is* true and
   sharper: **Janice appears in 0 of the 48 incident-chain event slots** (Jax 27, Yusuf 16, Deepa 12,
   Hanna 10, Kaitlyn 9, Liam 8, Priya 7, Chloe 6, Alex 6, Sanjay 4, Sarah 2, Sam 2, Taylor 2, Raj 1).
   The nominal owner of TitanDB/auth-service/oauth2-flow is absent from every incident, including
   `ENG-165`, the one whose title names the TitanDB RDS. So is Bill. **Say that instead.**

### The chain, in order (33 nodes, all verified present)

**Act 1 — the genesis gap**

| id | type | notes |
|---|---|---|
| `Bill` | Person | `documented_pct 0.2`, role CTO, `departed_day -579` |
| `EVT--579-employee_departed-1` | Event | facts: `is_genesis_gap: true`, 4 knowledge domains |
| `EVT--579-knowledge_gap_detected-2` | Event | `Concerns` → TitanDB, legacy auth service, AWS cost structure, Project Titan |
| `TitanDB` | Domain | `is_genesis_gap: true`; `DepartedWith` ← Bill |
| `legacy auth service`, `AWS cost structure`, `Project Titan` | Domain | Bill's other three |
| `EVT-1-knowledge_gap_detected-56` | Event | day 1; facts carry `documented_pct 0.2`, `live_documentation_coverage 0.2`, `days_since_departure 580`, `triggered_by: slack_engineering_backend_2026-01-01T15:54:00` |

Bill is attached to **427** `knowledge_gap_detected` events with the identical signature
`(ppl={Bill}, doms={TitanDB, legacy auth service, AWS cost structure, Project Titan})` — one every
day for 60 days, several per day. Pin **two** of them (`EVT--579-…-2` and `EVT-1-…-56`) and collapse
the rest (§9).

**Act 2 — the hire**

| id | type | notes |
|---|---|---|
| `EVT-4-hr_outbound_email-712` | Event | Karen → Janice |
| `hr_outbound_janice_4_offer_letter` | Email | the only Email in the narrative set |
| `EVT-7-employee_hired-1030` | Event | facts: `expertise: [Python, FastAPI, PostgreSQL, **TitanDB**]`, `cold_start: true` |
| `Janice` | Person | `joined_day 7`, degree 380 |
| `EVT-7-knowledge_gap_detected-1054` | Event | day 7, her first: Jax asks about the IAM timeline, `outcome: unresolved` |
| `slack_digital-hq_2026-01-09T13:32:00` | SlackThread | the thread that gap was detected in; Janice + Jax + Dave + Marc + Sophie + Sarah |
| `EVT-12-employee_departed-1345` | Event | Jordan, day 12, 25% documented, owns auth-service/redis-cache/oauth2-flow |
| `EVT-12-domain_ownership_claimed-1381` | Event | Janice ← `auth-service`, coverage 0.45 |
| `EVT-12-domain_ownership_claimed-1382` | Event | Janice ← `oauth2-flow`, coverage 0.45 |
| `auth-service`, `oauth2-flow` | Domain | |

**Act 3 — the incident** (`ENG-165`, day 21–24, the one whose body names TitanDB)

| id | type | notes |
|---|---|---|
| `EVT-21-escalation_chain-1388` | Event | Yusuf → Jax |
| `EVT-21-incident_opened-1387` | Event | day 21; `Produced` → `ENG-165`, `slack_incidents_2026-01-29T10:30:00` |
| `ENG-165` | JiraTicket | "P1 incident ENG-165: A recent reduction in the PostgreSQL connection pool size on the **TitanDB** RDS…"; degree 30; `Mentions` TitanDB, Project Titan, legacy auth service, auth-service |
| `slack_incidents_2026-01-29T10:30:00` | SlackThread | `Refs` → ENG-165 |
| `EVT-24-incident_resolved-1430` | Event | day 24; Jax + Yusuf; `Produced` → ENG-165, `PR-120` |
| `PR-120` | PullRequest | the fix; authored Jax + Yusuf + Deepa |
| `EVT-24-postmortem_created-1429` | Event | Yusuf + Jax + Deepa |
| `CONF-ENG-187` | ConfluencePage | the postmortem; `Refs` → ENG-165, `Mentions` → TitanDB |

Verified edges on this chain (95 edges over the 33 nodes, e/n 2.88). The load-bearing ones:

```
Bill        --DepartedWith--> TitanDB | legacy auth service | AWS cost structure | Project Titan
Bill        --Involves(rev)-> EVT--579-employee_departed-1
                              EVT--579-knowledge_gap_detected-2
                              EVT-1-knowledge_gap_detected-56
TitanDB     --Concerns(rev)-> EVT--579-knowledge_gap_detected-2, EVT-1-knowledge_gap_detected-56
TitanDB     --CoOccurs------> Project Titan | oauth2-flow | legacy auth service | auth-service | AWS cost structure
Janice      --Authored------> hr_outbound_janice_4_offer_letter
                              slack_digital-hq_2026-01-09T13:32:00
Janice      --Involves(rev)-> EVT-7-employee_hired-1030
                              EVT-7-knowledge_gap_detected-1054
                              EVT-12-domain_ownership_claimed-1381 / -1382
hr_outbound_janice_4_offer_letter --Produced(rev)--> EVT-7-employee_hired-1030
auth-service --DepartedWith(rev)--> Jordan       (Jordan --DepartedWith--> oauth2-flow)
Jordan      --Involves(rev)-> EVT-12-employee_departed-1345
EVT-21-escalation_chain-1388 --Produced--> ENG-165
EVT-21-incident_opened-1387  --Produced--> ENG-165, slack_incidents_2026-01-29T10:30:00
ENG-165     --Refs----------> PR-120
ENG-165     --Produced(rev)-> EVT-24-incident_resolved-1430
PR-120      --Produced(rev)-> EVT-24-incident_resolved-1430
EVT-24-postmortem_created-1429 --Produced--> CONF-ENG-187, ENG-165
CONF-ENG-187 --Refs---------> ENG-165 ;  --Mentions--> TitanDB, Project Titan, oauth2-flow,
                                          legacy auth service, auth-service
TitanDB     --Mentions(rev)-> ENG-165, slack_incidents_2026-01-29T10:30:00, PR-120
```

**MISSING edge to synthesise:** `Janice --Owns--> TitanDB` (and `--Owns-->` auth-service,
oauth2-flow). Without it the two halves of the story touch only through `TitanDB --CoOccurs-->
auth-service`, a 2-hop path that no viewer will read as inheritance.

### Also pin (the other three departures, for symmetry)

`Sharon` + `EVT--306-employee_departed-3` (day −306, 32% documented, `mobile analytics`);
`Morgan` + `EVT-34-employee_departed-1543` (day 34, layoff, 60% documented, `kubernetes-deploy` +
`terraform-infra`); `EVT-26-employee_hired-1450` (Reese) + `EVT-26-employee_hired-1451`
(Ethan Patel); `EVT-2-domain_ownership_claimed-215` (Sam ← Project Titan, coverage 0.40);
`EVT-14-domain_ownership_claimed-1455` (Yusuf ← redis-cache, coverage 0.85).

And pin the demo's own query targets, which `api.jac` hardcodes:
`EVT-38-knowledge_gap_detected-1453` (Morgan, kubernetes-deploy + terraform-infra) and its answer
artifact **`CONF-HR-001`** — the gap-scan walker's whole verdict rests on these two, and a sampler
would drop both.

### The 12 incident chains — full id list

Every chain is `escalation_chain → incident_opened → {Jira, #incidents Slack} → incident_resolved
→ {PR} → postmortem_created → {Confluence}`. 112 nodes closed-neighbourhood, 321 edges, **1
connected component, e/n 2.87** — the most legible substructure in the dataset, and the strongest
visual argument that this graph has shape.

| day | escalation | opened | Jira | `#incidents` Slack | resolved | PR | postmortem | Confluence |
|---|---|---|---|---|---|---|---|---|
| 3–6 | `EVT-3-escalation_chain-376` | `EVT-3-incident_opened-375` | `ENG-112` | `slack_incidents_2026-01-05T12:16:00` | `EVT-6-incident_resolved-1027` | `PR-106` | `EVT-6-postmortem_created-1026` | `CONF-ENG-054` |
| 8–11 | `EVT-8-escalation_chain-1220` | `EVT-8-incident_opened-1219` | `ENG-123` | `slack_incidents_2026-01-12T12:59:00` | `EVT-11-incident_resolved-1342` | `PR-109` | `EVT-11-postmortem_created-1341` | `CONF-ENG-078` |
| 13–16 | `EVT-13-escalation_chain-1397` | `EVT-13-incident_opened-1396` | `ENG-137` | `slack_incidents_2026-01-19T12:35:00` | `EVT-16-incident_resolved-1479` | `PR-111` ⚠ | `EVT-16-postmortem_created-1478` | `CONF-ENG-129` |
| 17–20 | `EVT-17-escalation_chain-1324` | `EVT-17-incident_opened-1323` | `ENG-148` | `slack_incidents_2026-01-23T10:00:00` | `EVT-20-incident_resolved-1335` | `PR-119` | `EVT-20-postmortem_created-1334` | `CONF-ENG-150` |
| **21–24** | `EVT-21-escalation_chain-1388` | `EVT-21-incident_opened-1387` | **`ENG-165`** | `slack_incidents_2026-01-29T10:30:00` | `EVT-24-incident_resolved-1430` | `PR-120` | `EVT-24-postmortem_created-1429` | `CONF-ENG-187` |
| 25–28 | `EVT-25-escalation_chain-1461` | `EVT-25-incident_opened-1460` | `ENG-173` | `slack_incidents_2026-02-04T11:03:00` | `EVT-28-incident_resolved-1522` | `PR-129` | `EVT-28-postmortem_created-1521` | `CONF-ENG-223` |
| 29–32 | `EVT-29-escalation_chain-1553` | `EVT-29-incident_opened-1552` | `ENG-186` | `slack_incidents_2026-02-10T12:37:00` | `EVT-32-incident_resolved-1524` | `PR-130` | `EVT-32-postmortem_created-1523` | `CONF-ENG-260` |
| 37–40 | `EVT-37-escalation_chain-1318` | `EVT-37-incident_opened-1316` | `ENG-210` | `slack_incidents_2026-02-20T11:51:00` | `EVT-40-incident_resolved-1438` | `PR-139` | `EVT-40-postmortem_created-1436` | `CONF-ENG-311` |
| 42–45 | `EVT-42-escalation_chain-1362` | `EVT-42-incident_opened-1361` | `ENG-230` | `slack_incidents_2026-02-27T10:04:00` | `EVT-45-incident_resolved-1524` | `PR-143` | `EVT-45-postmortem_created-1523` | `CONF-ENG-354` |
| 46–49 | `EVT-46-escalation_chain-1549` | `EVT-46-incident_opened-1548` | `ENG-237` | `slack_incidents_2026-03-05T12:03:00` | `EVT-49-incident_resolved-1520` | `PR-149` | `EVT-49-postmortem_created-1519` | `CONF-ENG-383` |
| 50–53 | `EVT-50-escalation_chain-1548` | `EVT-50-incident_opened-1547` | `ENG-250` | `slack_incidents_2026-03-11T10:24:00` | `EVT-53-incident_resolved-1606` | `PR-150` | `EVT-53-postmortem_created-1605` | `CONF-ENG-419` |
| 54–57 | `EVT-54-escalation_chain-1632` | `EVT-54-incident_opened-1631` | `ENG-263` | `slack_incidents_2026-03-17T10:25:00` | `EVT-57-incident_resolved-1472` | `PR-159` | `EVT-57-postmortem_created-1471` | `CONF-ENG-438` |

Two orphan `escalation_chain` events not attached to a ticket: `EVT-12-escalation_chain-1380`
(Chloe, Raj), `EVT-34-escalation_chain-1472` (Jax, Deepa). Include or drop, no structural effect.

⚠ **`PR-111` is a JiraTicket node, not a PullRequest.** It arrives in the corpus as a `pr`-typed
row that `build_graph` maps to `ART_CLASS["pr"] = PullRequest`… but it is reached via
`EVT-16-incident_resolved-1479 --Produced-->` and lands in the graph with `kind == "JiraTicket"`.
It will render the wrong colour. Either recolour by id prefix or accept the one-node blemish.

Five of the 12 tickets carry a `Mentions` edge to TitanDB: `ENG-123`, `ENG-165`, `ENG-186`,
`ENG-230`, `ENG-263`. `ENG-165` is the only one whose *body text* says TitanDB.

---

## 7. Two data bugs the renderer will otherwise display

1. **Bill renders in `HR_Ops`.** `load_data()` assigns dept by majority vote over corpus rows.
   Bill appears in 428 rows, but only 7 carry a dept: HR_Ops 2, Sales_Marketing 2,
   Engineering_Backend 1, QA_Support 1, Product 1. A 2–2 tie resolved by dict order puts the CTO in
   HR Ops. `snap["departed_employees"]` says `Engineering_Backend`. **Reese** is likewise placed in
   `Product` (36 votes) though `new_hires` says `Engineering_Backend`. Fix: for anyone in
   `departed_employees` or `new_hires`, prefer the snapshot dept over the vote — that is 7 people
   including every narrative figure.
2. **`Janice` has a `Relates` edge to `John`**, who is in the roster via `stress_snapshot` but has
   no dept and no artifacts. Harmless, but `John` shows up at degree 42 inside the recommended
   view; check that is intended before pinning.

---

## 8. Edge filtering beats node sampling

This is the highest-leverage change after the node list. In the recommended 217-node view the edge
budget is:

```
Mentions 346 | Authored 268 | Involves 132 | Produced 87 | MemberOf 46 | CoOccurs 45
Estranged 41 | Refs 30 | DepartedWith 13 | Relates 10 | Concerns 10
```

**`Mentions` is 34% of edges and carries almost no information** — it is a substring match against
aliases like `"titan"`, `"auth"`, `"flow"`, `"deploy"`. Keeping only the *most specific* mention per
artifact (lowest global mention count, i.e. an IDF tiebreak — `kubernetes-deploy` 646 beats
`legacy auth service` 1,801) drops 236 edges and takes the view to **760 edges, e/n 3.50**, inside
the published readability band, with zero nodes removed.

A principled alternative is the **disparity filter** (Serrano, Boguñá & Vespignani, PNAS 2009),
which keeps edges whose weight deviates significantly from a null model of uniform local weight
assignment, at a chosen α. It is the right tool for the weighted `CoOccurs` layer (45 edges,
weights 1–1,000+) and for `Relates`/`Estranged`. For unweighted `Mentions` the IDF rule above is
simpler and does the same job. Cite the filter, use it on `CoOccurs` if you want to thin the
domain–domain clique from 45 edges to ~15.
[Serrano et al. 2009, *Extracting the multiscale backbone of complex weighted networks*, PNAS 106(16)](https://www.pnas.org/doi/10.1073/pnas.0808904106)

`Estranged` (41) vs `Relates` (10) is worth a deliberate decision: the graph has **4× more
estrangements than close relationships**, and drawing them all in the idle view will read as a mess
of red. Either show both with distinct colours (they are the org-health story) or show neither.

---

## 9. If you must sample: what to use, and what to collapse instead

**The method, named, with its parameter: pinned-seed quota sampling with a specific-`Mentions` edge
filter. Formally — pin set P (§6, 117 nodes), per-type quotas Q (§5), rank within type by
betweenness, then keep edge (a, d) of type `Mentions` iff d = argmin over a's mentioned domains of
that domain's global mention count. Parameter: 1 mention edge per artifact.** That is what replaces
the current sampler.

To be precise about what is being replaced: the current `GraphSlice` is not uniform random, it is
**stride** sampling — `step = len(cand) // room`, then `cand[0::step]`. That is worse than uniform
random in one specific way: `cand` arrives in corpus order, so the stride is correlated with time
and doc type, which is how the view ended up 58% Slack with zero Zoom and zero ZD tickets. Uniform
random would at least have been unbiased.

**Recommendation: don't sample the idle view at all — curate it. Sample only inside
expand-on-click.** For that path:

- **Snowball / BFS from the clicked node, depth 2, degree-capped.** This is what `Expand`
  (`main.jac:1367`) already does. Keep it. BFS overestimates clustering, which is a real bias, but
  for a 1–2 hop neighbourhood view that bias is the *point* — the user asked "what is around this
  node".
- **Forest-fire sampling** (Leskovec & Faloutsos, KDD 2006) is the literature's best general answer:
  random-walk and forest-fire samplers "match very accurately both static as well as evolutionary
  graph patterns, with sample sizes down to about 15% of the original graph," while edge sampling
  performs poorly. Use it if you ever need a *representative* 1,000-node slice for a statistic. Do
  not use it for the demo view — it optimises for distributional fidelity, not legibility, and it
  gives no guarantee that Bill survives (he wouldn't; degree 433 of 15,985 nodes).
  [Leskovec & Faloutsos 2006, *Sampling from large graphs*, KDD '06](https://dl.acm.org/doi/10.1145/1150402.1150479)
- **k-core: use as a diagnostic, not a view.** Measured core-number distribution: 67 nodes at
  core 0, 2,661 at 1, and a long tail to a maximum core of **17**. The 17-core is 115 nodes — 32
  people, 10 domains, 9 channels, **64 Slack threads** — and its density is 13.29 e/n, five times
  the current view. k-core answers "who is in the dense middle" (answer: chat), not "what should be
  drawn". Its one genuinely useful output is the core number as a **node-size channel**: Priya, Jax
  and every heavy contributor sit at 17; Bill sits at 6; Reese at 15.
- **Spanning-subgraph / backbone extraction**: covered by §8. Prefer thinning edges over dropping
  nodes — every node dropped is a labelled entity a viewer could have recognised; every `Mentions`
  edge dropped is a substring coincidence.

### Collapse, don't drop

Two aggregations are unambiguously worth it, and the numbers are lopsided:

**1. Knowledge-gap events → one super-node per departed employee.** 2,435
`knowledge_gap_detected` events reduce to **655 distinct `(people, domains)` signatures**, and four
signatures alone account for **1,478 events (61%)**:

| signature | count |
|---|---|
| Sharon × {AWS cost structure, Project Titan, legacy auth service, mobile analytics} | **455** |
| Bill × {AWS cost structure, Project Titan, TitanDB, legacy auth service} | **427** |
| Jordan × {auth-service, oauth2-flow, redis-cache} | **379** |
| Morgan × {kubernetes-deploy, terraform-infra} | **203** |

Four super-nodes labelled *"427 knowledge gaps traced to Bill"* replace 1,478 identical red dots and
say something a hairball cannot. This is the single best aggregation available in the dataset. Keep
two real gap events pinned (`EVT-1-knowledge_gap_detected-56`, `EVT-38-knowledge_gap_detected-1453`)
so the expand-on-click has real leaves to reveal.

**2. Slack → per-channel super-nodes, expandable.** 3,303 threads, of which **2,291 sit in one of
14 public channels** and ~1,012 are DMs with no channel (`#dm_*` titles are deliberately excluded by
`load_data`). Collapsing to 14 channel nodes is a 236:1 reduction and the channels already exist as
`Channel` nodes with real degrees (`#digital-hq` 877, `#sales_marketing` 259,
`#engineering_mobile` 245, `#design` 184, `#engineering` 178, `#incidents` 170,
`#engineering_backend` 165, `#product` 145, `#hr_ops` 145, `#qa_support` 135, `#standup` 77,
`#system-alerts` 22).

**But do not put them in the idle view.** Measured: adding all 14 channels to the recommended view
costs 354 edges (333 `Subscribes` + 21 `InChannel`) and moves e/n from 4.74 → 5.98, worse than the
current hairball, because 46 people × ~7 channels each is a near-complete bipartite graph.
Per-channel collapse is the right *drill-down* affordance: click `#digital-hq`, expand to its
threads. Per-person collapse (person → "142 Slack threads") is worse still — it duplicates
information the `Authored` edge already conveys.

Everything else should be sampled by type quota (§5), not aggregated: 479 Confluence pages and 304
Jira tickets are heterogeneous enough that a "Confluence" super-node says nothing.

---

## 10. Implementation notes

- `GraphSlice` (`main.jac:791`) needs a new selection body, not a bigger `max_nodes`. Suggested
  shape: a module-level `glob PINNED: list[str]` holding the §6 ids, plus per-kind quotas applied
  over `IDX_ART-->` and a new `IDX_EVENT-->` traversal (events are currently never emitted).
- Precompute betweenness offline and store it as a node attribute; do not compute it at request
  time (the `k=500` approximation takes ~90s on this graph).
- `slice_payload` already filters edges to the included node set, so a curated node list
  automatically yields a consistent edge list. The `Mentions` thinning in §8 has to happen in
  `out_edges` (`main.jac:213`) or it will not take effect.
- `GraphCanvas.jac` is already correct for this: `nodeRelSize={3}`, particles only on walked edges,
  labels only when walking. At 217 nodes you can afford to **label the 64 skeleton nodes in the idle
  view too** — that is the change that makes it read as an org rather than a texture. Raise
  `cooldownTicks` from 60; a 217-node layout settles well within budget and the extra ticks buy a
  cleaner arrangement.
- Colour is out of scope for this document (the canvas is dark, `#0b0e14`, and the palette is being
  revised separately). The one thing node *selection* imposes on the visual encoding: the
  recommended view puts **`SFOpportunity` and `ZDTicket` on screen**, and neither has an entry in
  `TYPE_COLOR` today. Whatever encoding replaces it — `GRAPH-VIZ-TECHNIQUES.md` §5 argues for shape
  over colour, which handles this cleanly — needs marks for all twelve types in the census at the
  end of §5 here, not the ten currently defined.

---

## 11. Addendum — four defects found in an independent re-derivation

Added 2026-07-26 by a second agent that rebuilt `build_graph()` from scratch (15,971 nodes /
73,847 edges — the small delta against the census above is `Channel`/`InChannel`/`Subscribes`,
which that replica omitted, so trust §1's census over this one). It **independently reproduced**
this document's two headline findings — the missing `Janice → TitanDB` edge and the Bill-in-HR_Ops
dept bug — which is worth knowing: two separate derivations agree, so both are real.

The four items below are **not covered anywhere above** and are all cheap fixes.

### 11.1 No `incident_opened` event has a `Concerns` edge — all 12 are silently dropped

§8's edge budget shows `Concerns 10` in the recommended view. That number is low for a reason:
**every one of the 5,071 `Concerns` edges in the graph comes from `knowledge_gap_detected`
events, and none from incidents.** Verified:

```
EVT-8-incident_opened-1219 : facts domains = ['TitanDB, legacy auth service, AWS cost structure, Project Titan',
                                              'mobile analytics, legacy auth service, AWS cost structure, Project Titan']
                             Concerns edges = []
EVT-42-incident_opened-1361: facts domains = ['TitanDB, legacy auth service, AWS cost structure, Project Titan']
                             Concerns edges = []
EVT-25-incident_opened-1460, EVT-29-incident_opened-1552, EVT-54-incident_opened-1631 — same, all []
```

Cause: `load_data` (`main.jac` ~line 423) handles `facts.gap_areas` two ways — a `str` is split on
`", "`, a `list` is taken verbatim. On `incident_opened` events the value is **a list whose single
element is a comma-joined string**, so it takes the list branch, never splits, and
`"TitanDB, legacy auth service, AWS cost structure, Project Titan" in DOMAINS` is false. Silent
no-op. `knowledge_gap_detected` is unaffected because its `gap_areas` is a proper list.

Fix — split list elements too:

```
elif isinstance(raw, list) {
    for part in anylist(raw) {
        for piece in str(part).split(", ") {          # <-- add this inner loop
            if piece and piece not in edomains { edomains.append(piece); }
        }
    }
}
```

This gives `incident → Domain` for the 5 incidents whose facts name domains, closing the loop from
gap to consequence. Note the chain is not *broken* today — §6 correctly routes it through
`ENG-165 --Mentions--> TitanDB` — but the event-layer link a walker would naturally follow is
absent.

### 11.2 `facts.domain` is never read — all 7 `domain_ownership_claimed` events are unlinked

§6 correctly identifies `EVT-12-domain_ownership_claimed-1381/-1382` as Janice claiming
`auth-service` and `oauth2-flow`. What it doesn't say: **neither event has a `Concerns` edge**,
because the domain lives in `facts.domain`, and `load_data` only reads `gap_areas`,
`orphaned_domains` and `domains`. Both events have `domains: []` and degree 1 (`Involves` only).

Fix: add `"domain"` to the key list on ~line 423. One word, and all 7 ownership-claim events link
to their domain — which makes §6's *better verifiable story* (Janice inherits Jordan's orphaned
domains the day he leaves) actually drawable.

### 11.3 `day_max: 60` filters nothing

`GraphSlice.day_max` defaults to 60 and gates `if a.day > self.day_max { continue; }`. **Every
artifact in the corpus has `day <= 60`**, so the filter removes zero nodes:

```
ConfluencePage 479/479   Email 610/610   JiraTicket 304/304   PullRequest 57/57
SFOpportunity 3/3        SlackThread 3303/3303   ZDTicket 2/2   ZoomTranscript 208/208
```

It looks like a working time control and is not one. If the demo wants a time scrub, `day` is
populated and usable — but it needs a real range, and the current parameter will mislead anyone
who tries it on stage.

### 11.4 The `Mentions` alias explosion, quantified per alias

§8 correctly identifies `Mentions` as the dominant edge class and proposes an IDF tiebreak. Here
is the measurement behind that, which makes the case unarguable — hit counts for every alias in
`domain_registry.system_tags`:

| Domain | Alias hits (artifacts matched) |
|---|---|
| legacy auth service | `service` **1,539**, `auth` 950, `legacy` 359, `legacy auth service` 200 |
| auth-service | `service` **1,539**, `auth` 950, `auth-service` 364 |
| terraform-infra | `terraform` 1,311, `infra` 1,063, `terraform-infra` 408 |
| redis-cache | `redis` 1,167, `cache` 1,025, `redis-cache` 96 |
| AWS cost structure | `aws` 992, `cost` 969, `structure` 194, `aws cost structure` 64 |
| TitanDB | `titandb` 2,548, `titan` 1,332 |
| Project Titan | `titan` **1,332**, `project` 326, `project titan` 92 |
| oauth2-flow | `auth` 950, `flow` 682, `oauth2` 90, `oauth2-flow` 14 |
| mobile analytics | `mobile` 760, `analytics` 472, `mobile analytics` 106 |
| kubernetes-deploy | `deploy` 629, `kubernetes` 209, `kubernetes-deploy` 100 |

Mean **2.72 domains per artifact**; distribution `0:1629  1:702  2:392  3:392  4:431  5:430
6:371  7:325  8:199  9:87  10:8`. `"service"` alone links 1,539 artifacts to two different
domains, and `"titan"` cannot separate `TitanDB` from `Project Titan` — fatal, since the company's
product *is* Project Titan.

**Longest-matching-alias** (a simpler variant of §8's IDF rule, and it beats it on ties involving
`titandb`) cuts corpus-wide `Mentions` from **13,492 → 3,337** while leaving every domain a
meaningful population:

```
terraform-infra 1,002   mobile analytics 539   TitanDB 456   legacy auth service 372
kubernetes-deploy 253   AWS cost structure 193  oauth2-flow 187  auth-service 130
Project Titan 119       redis-cache 86
```

Because each artifact then belongs to exactly *one* domain, it also gives every artifact an
unambiguous angular home in the sector layout — a property the IDF rule shares but which is worth
stating explicitly, since it is what makes `GRAPH-VIZ-TECHNIQUES.md`'s composition work.

> Rejected alternative, measured: blocklisting generic aliases and requiring length ≥ 8 gives 722
> `Mentions` edges but leaves **4,410 of 4,966 artifacts with no domain at all**. Marginally
> better density, far worse layout and story. Longest-alias wins.

### 11.5 One correction to §6.3

§6 note 3 says Janice has "5 `mentoring` events and 2 `1on1` events in days 7–9". Across the full
60 days the count is **72 `mentoring`/`1on1` events involving Janice**, spread over days 7–60. This
strengthens rather than weakens that section's argument: the scripted "she never gets an
onboarding session" claim is not merely imprecise, it is contradicted 72 times, and a Jac-literate
judge who queries it will find them all.

§6's replacement claim (Janice is absent from all 48 incident-chain slots) is verified and is the
better line. A second verified claim, usable alongside it: **Janice authored zero
`ConfluencePage` nodes in 60 days** — 132 Slack threads, 3 PRs, 1 email, 1 Zoom transcript, and
not one document. It exercises the artifact-type distinction the whole node schema exists to make.

### 11.6 Priority against the clock

| Fix | Lines | Value |
|---|---|---|
| §8 / §11.4 `Mentions` thinning | ~5 | Highest. Removes the hairball at its source. |
| §11.1 `Concerns` split | ~3 | High. Restores incident → domain in the event layer. |
| §11.2 `facts.domain` | 1 word | High per line. Makes the inheritance beat drawable. |
| §7.1 dept from snapshot | ~2 | Medium. Stops Bill rendering in the wrong wedge. |
| §6 `Owns` edge | ~10 | Highest narrative value, but touches the schema — do it only after the above land. |
| §11.3 `day_max` | note only | Low. Don't demo the time control. |
