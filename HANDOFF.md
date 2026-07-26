# orgmem — operational handoff

State as of 13:15, Sun 26 July 2026. Written so nothing below has to be rediscovered.

---

## Run it

```bash
cd /Users/frankwalsh/Documents/hackathons/jacHacks && source activate.sh
cd orgmem && jac dev app.jac -p 8903
```

- **App: http://localhost:8903/app** — the demo. **Site: http://localhost:8903/** — marketing.
- `jac run main.jac` builds the graph (~6s, persisted). `jac check .` → 17 passed.

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

**Working:** all four presets return correct answers checked against ground truth. Walk animates
across the full graph with camera follow. Node-count selector 400/1k/3k/5k. Idle animation is zero
(proven: two screenshots 6s apart are byte-identical). Physics bounded.

**Demo at 3k, not 400.** At 400 the Felix preset highlights 121 of 400 nodes — a gold blob. At 3k
the ratio works and every route node is present. 3k is verified safe on this machine; **5k is
untested — consider removing that button.**

**Open, in value order:**
1. **Wire the Janice onboarding preset** — `silence_EVT-7-employee_hired-1030_onboarding_session`,
   ground truth **FALSE**. Bill left owning TitanDB with 20% documented; Janice was hired day 7 to
   inherit it; **she never got an onboarding session**; incidents follow. Best question in the
   dataset and its answer is an absence. Needs `api.jac` + the preset list in `Shell.jac`.
2. Path-node size is fixed at 6× — make it adaptive so long paths don't blob.
3. Node labels don't paint (code and bundle look correct; likely sub-pixel at current zoom).
4. Marketing site whitespace/layout — light theme and the "76,000+" figure are fixed; layout unverified.

**A `Visibility` route is a one-hop STAR, not a journey** — `[[Janice, artifact1], [Janice,
artifact2], …]`. It renders as a fan from a hub, which is honest but isn't a traversal. For a true
multi-hop crossing you'd need a different query shape.

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
