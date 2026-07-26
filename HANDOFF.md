# orgmem — operational handoff

State as of 13:15, Sun 26 July 2026. Written so nothing below has to be rediscovered.

---

## Run it

```bash
cd /Users/frankwalsh/Documents/hackathons/jacHacks && source activate.sh
cd orgmem && jac dev app.jac -p 8903
```

- **App: http://localhost:8903/app** — the demo. **Site: http://localhost:8903/** — marketing.
- `jac run main.jac` builds the graph (~6s, persisted). `jac check .` → 25 passed.
- **`jac run eval.jac`** reproduces the 94.7% — **stop the dev server first** (gotcha 13).

## THE RESTART RULE — most important line in this file

**After editing ANY `.jac` file, do a full restart. Never trust hot reload.**

```bash
pkill -f "jac dev"
rm -rf .jac/client/compiled     # BEFORE starting, never while running
(jac dev app.jac -p 8903 > /tmp/dev.log 2>&1 &)
```

Then check `grep -icE "readonly|globalAlpha|does not provide|not found" /tmp/dev.log` → must be **0**.
HTTP 200 alone is meaningless — the shell always returns 200 while the bundle is broken.

**If the page shows an import/export error, do NOT debug the source.** Three times today the source
was correct and the compiled bundle was stale. Restart first, diagnose second.

**Only one agent/person restarts at a time.** Five concurrent `jac dev` processes made port 8903
refuse connections and truncated the log mid-check.

---

## Jac gotchas found the hard way (not in the docs)

1. **`glob` needs `:pub` to cross a module boundary.** A plain `glob` imported by another module
   fails at *bundle* time with `does not provide an export named 'X'`, which reads like a stale
   build. Same rule as `def:pub`.
2. **Incremental rebuilds silently DROP `glob` exports.** Reproduced twice: a clean build exports
   all globals, then an edit to that file produces a rebuild with them missing and no source change.
   **`def` exports survive.** So prefer `cl def:pub accessor() { return GLOB; }` over exported globs.
   This is why `corpus.jac` uses accessors.
3. **Omitted optional args arrive as STRINGS over the RPC bridge.** A `None` default arrives as
   `'None'`; a `= []` default arrives as `['[', ']']` (the characters of `"[]"`). **Both are truthy**,
   so `if arg` fallbacks silently never fire. **Always pass optional arguments explicitly.**
4. **`include` is a reserved word** — the parameter is named `include_ids`.
5. **Typed locals compile to `const`.** `x: list[str] = [];` then `x = y;` later throws
   *"Attempted to assign to readonly property"* — and only on the branch that rebinds.
6. **`here` is not defined in node/edge abilities** (use `self`); `visitor` is not defined in walker
   abilities. Runtime NameError, invisible to the type checker.
7. **Re-running a graph-building `with entry` duplicates the graph.** Guard it:
   `if not [root --> [?:Department]] { ...build... }`.
8. **`jac dev <file>` roots the project at that file's directory** — `jac dev web/ui.jac` treats
   `web/` as the project root and ignores the parent `jac.toml`.
9. **Walkers only register for the ENTRY module.** With `entry-point = "main.jac"` and the client in
   `app.jac`, no `/walker/*` routes existed and calls 405'd. `app.jac` imports the walker names, so
   pointing the entry there registers all of them.
10. **`sv import` of a same-project server module flips the build into microservice mode** — it
    auto-detects a service, starts a gateway on :8000 and ignores `-p`. Use `def:pub` wrapper
    endpoints in the entry module that `root spawn` the walker instead.
11. **`nodePointerAreaPaint(node, colour, ctx, scale)`** takes a colour STRING as arg 2, unlike
    `nodeCanvasObject(node, ctx, scale)`. Passing the same function to both crashes with
    *"Cannot create property 'globalAlpha' on string"*.
12. **`corpus.parquet`'s `actors`, `tags`, `artifact_ids` are JSON strings, not lists.** Without
    `json.loads()` you iterate single characters and silently build a graph with zero edges.
13. **`jac dev` exposes NO `/walker/*` routes** — only `/function/<name>` for `def:pub`. `POST
    /walker/EvalRun` 405s. That is why **`eval.jac`** exists: `jac run eval.jac` with the dev server
    stopped is the only way to reproduce the benchmark. Both processes open the same `.jac/` store,
    so do not run them at once.
14. **`jac check` prints ~150 warnings for `main.jac` alone.** Always pipe it (`| tail -3`) or the
    one line you need is buried. The check *hook* blocks on errors only, not warnings.
15. **Adding a parameter to a walker method must be done in ONE edit with every call site**, or the
    hook rejects the intermediate state and you cannot proceed. Write the method and all callers
    together.
16. **Returning a new `graphData` object re-heats the whole force simulation.** This is the single
    biggest perf lever in the app — see the note below.

---

## The numbers (from `eval_results.json`, reproducible)

| | |
|---|---|
| Graph | 76,787 edges · 46 people · 4,966 artifacts · 10,941 events · builds in ~6s |
| **Overall** | **94.7%** (54/57 scored) |
| **SILENCE** | **96.3%** (26/27) vs **55.6%** constant baseline |
| PERSPECTIVE | 93.3% (28/30) vs 63.3% best-constant |
| COUNTERFACTUAL | **deliberately not scored** (21 skipped) |

**Say the refusal out loud on stage.** Declining to claim causal reasoning we can't verify from
artifacts buys more credibility with these judges than another percentage point.

---

## Known state / open items

**Working:** all four presets return correct answers checked against ground truth, and **all four
now animate as connected trees** (they did not — `gap` and `who` had no path at all). Node cards
open on click. Node-count selector 400/1k/3k/5k, **default 3k**. Walk playback speed 0.5/1/2/4x.
Clear button. Composed radial layout with department sectors; mist edges hidden; labels paint.

### The walk is a TREE now, not a star — and how

`Visibility` used to record every reachable artifact as an edge from the person: 120 pairs, all
sharing one source, depth 1. It rendered as a 120-spoke starburst that lit 121 of 400 nodes.
Three changes in `main.jac`, all **display-only** (`cone` still decides the verdict and is built
regardless, so the benchmark cannot move):

- The **channel is recorded as its own hop**. `person -> #qa_support -> thread` was being
  flattened to `person -> thread`, throwing away the only intermediate node in the route.
- **`FAN_MAX`** caps recorded edges per source, so BFS renders as a tree that goes deep, not wide.
- **`linked`** keeps it a tree rather than a forest. Without it the cap orphans subtrees: once the
  person's budget is spent, later channels never get their connecting edge but their children
  still record — measured 35 sources of which only 6 were reachable from the actor.

Channels are traversed **before** authored artifacts, because the flat authored fan otherwise
spends the whole budget on depth-1 spokes. Order does not change `cone` membership.

Felix: 120 edges / 121 nodes / depth 1 → **30 edges / 31 nodes / depth 2 / 0 orphans**.

### The perf fix that mattered

`merge_walk` in `web/AppScreen.jac` returned a **new object** every answer. force-graph re-ingests
and re-heats its simulation whenever `graphData` changes identity, so d3-force restarted over
3,000 nodes and 23,000 links exactly when the walk began — the layout crawling under the walker
*was* the lag. Measured: at 3k, **all 30 path edges and all path nodes are already in the slice**
(`preset_seed` pins them), so the old unconditional append was also duplicating 30 links. It now
returns `base` unchanged when nothing is missing. **Do not reintroduce a fresh object here.**

### Contrast

Type hues are tuned to sit calmly on `#0b0e14`, which is exactly what makes them read as *dark*
once everything else drops to 10% ink. Lit nodes get a bright fill (`LIT_NODE`), the type hue as an
inner ring, gold outside. The old "gold is a ring, never a fill" rule was defending against a
121-node amber blob and no longer applies at 30 nodes.

**Open, in value order:**
1. **Person card mis-maps two fields.** `role` is read from the departure REASON (Bill renders as
   `role: "voluntary"`) and `dept` looks like the department that recorded the exit, not the one
   they worked in. Visible if anyone clicks a departed person on stage. Unverified: whether
   `authored_count: 0` is real for everyone or only for pre-window departures — check a current
   employee before trusting any Person card.
2. **Wire the Janice onboarding preset** — `silence_EVT-7-employee_hired-1030_onboarding_session`,
   ground truth **FALSE**. Bill left owning TitanDB with 20% documented; Janice was hired day 7 to
   inherit it; **she never got an onboarding session**; incidents follow. Best question in the
   dataset and its answer is an absence.
3. **5k is still untested** — consider removing that button before the demo.
4. Marketing site layout unverified. A `site` worktree/branch exists at `../orgmem-site` on port
   8910 and has not been merged.
5. The `gap` route's third hop loops back to the trigger event (`EVT-38 -> CONF-HR-001 -> EVT-38`).
   Honest — the causal closure includes the event that produced the artifact — but it draws as a
   small loop.

---

## Git

- Repo: **https://github.com/frankie-eight-days/orgmem** — public, GitHub reports **100% Jac**.
- **Watch the branch.** An agent created `cards` and commits landed there while `main` sat behind;
  `git push origin main` then reported "everything up-to-date" and was telling the truth. Now on
  `main` tracking `origin/main`. **Verify pushes with `git ls-remote origin main`, not exit codes.**
- Ignored: `.env` (holds a live Kimi key — **rotate after the event**), `.jac/`, `dist/`.

## Submission — 17:50 partial is a hard gate

- [ ] Deploy to **jachammer.ai** (paste the GitHub URL; set env vars in their UI, never in the repo)
- [ ] Demo video
- [ ] Written description covering how Jac was used → **`PITCH.md`** has it
- [ ] **⭐ Star github.com/jaseci-labs/jac** — explicit requirement
- [ ] Tracks: Agentic AI + a domain track + JacHammer
- [ ] **Partial submission by 17:50** — required to be judged, editable after. Final 19:15, hard.

**`PITCH.md`** has the timed 4-minute script, the Devpost copy, judge Q&A, and a break-glass plan.
