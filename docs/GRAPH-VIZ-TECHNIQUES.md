# Making the org graph look designed, not dumped

Implementation guide for `web/GraphCanvas.jac`. Target: `react-force-graph-2d`, **dark canvas**
(`--bg #0b0e14`), ~400 nodes / ~1,100–2,300 edges at full slice, ~30–60 nodes in a walk subgraph,
running on a laptop driving a projector for four minutes.

> **Theme note (revised 2026-07-26).** An earlier draft of this document was written against the
> light marketing-site palette (`#FBFAF7` / `#12100E` / `#E5432B`). **That was wrong for the
> canvas**: light theme is the marketing site only; the app canvas is dark, `#0b0e14`. Every
> colour literal below has been corrected in place. **§5A is the authoritative dark colour
> specification** — read it before implementing any colour, and treat any stray light-theme value
> elsewhere as a bug in this document.
>
> Three recommendations genuinely *changed* rather than merely inverting, because light-on-dark is
> not the mirror of dark-on-light. They are flagged **⇄ CHANGED** where they appear:
> **§4.1/§4.2** (mist edges — additive bloom means "mist as texture" no longer works at 400
> nodes), **§5A.4** (monochrome-by-alpha is *weaker* on dark; a small hue set comes back), and
> **§8.7** (glow is now available and is the best projector effect on the page).

Every prop name and default in here was checked against the `react-force-graph` and `d3-force`
docs on 2026-07-26; sources are linked at the bottom of each section.

---

## 0. Top recommendation (read this, then skim the rest)

**Stop asking a physics simulation to produce composition. Give it a skeleton and let it do
texture only.**

The specific combination:

| Layer | Decision |
|---|---|
| **Layout** | Concentric **type rings** (`forceRadial` per node type) crossed with **department sectors** (`forceX`/`forceY` toward a per-department angle). `forceManyBody` and `forceCollide` are demoted to anti-overlap duty. Domains at the centre, Departments inside them, People in the main ring, artifacts + Events as an outer halo. |
| **Settle** | Visible settle for ~1.5 s on first mount, then **freeze**. `d3AlphaDecay 0.05`, `d3AlphaMin 0.02`, `cooldownTicks 90`. Never `d3AlphaDecay=0`. |
| **Edges** | Three classes. *Backbone* (`CoOccurs`, `Relates` above a weight floor) at `rgba(220,228,240,0.20)`. *Mist* (everything else) **hidden by default on dark** — see §4.1 ⇄. *Walked* at `#FFD166`, width 2.4 + glow. Constant `linkCurvature` 0.12–0.22 so parallel runs read as bundles instead of crosshatch. |
| **Nodes** | Four semantic tiers by **hue**, artifacts monochrome by alpha, all types **distinguished by shape** — Domain = filled disc with a ring, Person = filled disc, Department = hollow square, Event = diamond, artifacts = 1.5 px hollow dot. Accent (`#FFD166`) reserved exclusively for walk / active hop. Full spec in §5A. |
| **Labels** | Drawn in `onRenderFramePost`, **not** `nodeCanvasObject`, so you control iteration order and can do priority-ordered occlusion culling. Always label Domains; label People above a degree threshold once zoom `k > 1.3`; label everything in the focus set. Knock every label out with a `#0b0e14` stroke at `4/k` (thicker than on light — §6.1). |
| **Query result** | **Dim the rest, do not swap `graphData`.** Keep the same node positions the judge already learned, drop non-focus links to `linkVisibility=false`, drop non-focus nodes to 10 % ink, then `zoomToFit(700, 90, n => focus.has(n.id))`. |
| **Traversal** | Hop-by-hop at **320 ms/hop**. Per hop: `emitParticle(link)` ×2 staggered 60 ms, then flip `link.__walked = true`. Path stays lit afterwards. `linkDirectionalParticleSpeed ≈ 0.05` (not 0.02 — see §7). |
| **Reduced motion** | No settle animation (`warmupTicks 150`, `cooldownTicks 0`), no particles, instant path reveal, all camera `ms = 0`. |

**Why this and not "tune the forces harder":** the graph's link density is ~2.9–5.8 edges/node.
The practitioner rule of thumb is that node-link layouts stop being readable above a link density
of about 3, because past that the graph is guaranteed non-planar and edge crossings dominate the
picture regardless of how good the layout is
([Untangling Hairballs](https://link.springer.com/chapter/10.1007/978-3-662-45803-7_9),
[Trimming the Hairball, Microsoft Research](https://microsoft.com/en-us/research/uploads/prod/2018/12/TrimmingTheHairball.pdf)).
This graph is at or above that line at full slice. No amount of `charge` tuning fixes it. What
fixes it is (a) removing most edges from the default view and (b) imposing structure the viewer
can name in words — "domains in the middle, people around them, evidence on the outside, one
wedge per department". A judge can describe that layout out loud after two seconds. They cannot
describe a hairball.

**Why this is also *prettier*:** a constrained force layout keeps the organic, hand-drawn quality
of physics (nothing is on a grid, the rings breathe unevenly, cluster density varies) while
having a readable global composition. It looks like a Gephi showcase map rather than a
`d3.forceSimulation()` default — and that gap is almost entirely composition, not rendering.

---

## 1. Why hairballs happen, and what actually fixes them

Force-directed layout models nodes as mutually repelling particles and edges as springs. Three
things make it collapse:

1. **High link density.** As node count grows linearly, possible edges grow quadratically. Above
   ~3 edges/node the spring forces overwhelm repulsion and everything converges toward a
   centroid.
2. **High-degree hubs.** A person who authored 60 artifacts drags all 60 into the same well.
   Local density variation — the thing you actually want to see — gets flattened.
3. **High conductance.** If the graph has no strong community structure to separate, the layout
   has nothing to separate it *into*. `Refs` and `Mentions` edges cut across every department,
   so the org graph's natural communities are weak.

The fixes practitioners actually use, in descending order of effect:

| Fix | Effect | Applies here? |
|---|---|---|
| **Show fewer edges** | Largest single win. Edge clutter, not node count, is what makes a hairball. | Yes — default-hide `Refs`, `Mentions`, `Authored`; show on hover/selection. |
| **Impose layout structure** (radial, layered, grouped) | Turns "blob" into "diagram". | Yes — this is the top recommendation. |
| **Aggregate/collapse** (roll artifacts into their author or domain, expand on click) | Cuts node *and* edge count together. | Optional stretch — a "collapse artifacts" toggle showing one sized disc per person. |
| **Edge bundling** | Good for many edges / few nodes. Expensive, and unsupported by `react-force-graph`. | Approximate with curvature only — see §4. |
| **Statistical backboning** (keep only edges significant under a null model) | Principled, but a research-grade detour. | No. Use the cheap version: weight threshold on `Relates`/`CoOccurs`. |
| **Matrix view** | Genuinely clutter-free but reads as a spreadsheet on a projector. | No — kills the demo. |

Sources: [Untangling the hairball (Tiago Peixoto)](https://skewed.de/lab/posts/hairball/),
[Trimming the Hairball (Microsoft Research)](https://microsoft.com/en-us/research/uploads/prod/2018/12/TrimmingTheHairball.pdf),
[Untangling Hairballs (Nocaj/Ortmann/Brandes)](https://link.springer.com/chapter/10.1007/978-3-662-45803-7_9),
[Grooming the hairball](https://www.researchgate.net/publication/281050201_Grooming_the_hairball_-_how_to_tidy_up_network_visualizations).

---

## 2. Layout alternatives, and which wins for this graph

| Layout | Reads well when | For the org graph |
|---|---|---|
| **Plain d3-force** | < 150 nodes, density < 2 | Fails at 400. This is the current state. |
| **ForceAtlas2** (Gephi) | Community structure exists; you want scale-free graphs to spread | Better spread than d3 defaults, but no JS implementation is wired into `react-force-graph`. Porting it is a day of work you don't have. |
| **Fruchterman–Reingold** | Small, uniform-degree graphs | Same failure mode as d3-force, worse convergence. |
| **Hierarchical / layered (DAG)** | The graph *is* a DAG | `dagMode` exists (`td`/`bu`/`lr`/`rl`/`radialout`/`radialin`) but the org graph has cycles (`Refs`, `CoOccurs`, `Relates`) so you'd be fighting `onDagError` constantly. Skip. |
| **Radial / concentric by type** | Nodes fall into a small number of semantic tiers | **Winner.** 4 tiers, each with an obvious meaning. |
| **Sectored / grouped (group-in-a-box)** | Nodes have a categorical grouping you want spatially separated | **Winner, combined with the above.** Departments are the grouping. |
| **Arc diagram** | You want zero edge ambiguity and have a good node ordering | Beautiful, but wastes the whole canvas on one axis and cannot show a walk moving *through* space. Good fallback for a *single* relation (e.g. Person↔Person only). |
| **Matrix** | Density is genuinely too high for node-link | Clutter-free and honest, but visually inert. Not a demo asset. |
| **Chord / hive plot** | Few categories, many cross-category edges | A chord diagram of *department → department* knowledge flow is a strong secondary panel. Not the main canvas. |

### The recommended structure

```
          ┌──────────── Engineering_Backend sector ─────────────┐
                 · · artifacts (halo, r ≈ 300–360)
              ○  ○  ○   people (ring, r ≈ 165)
                 ▪ department (r ≈ 85)
                    ●  domains (core, r ≈ 0–45)
```

Radii, angles and forces:

```js
// pick once, from data; keep stable across renders
const RING = { Domain: 30, Department: 85, Person: 165, Event: 285,
               ConfluencePage: 320, SlackThread: 320, Email: 320,
               JiraTicket: 320, ZoomTranscript: 320, PullRequest: 320 };

// each department gets a wedge
const depts = [...new Set(nodes.map(n => n.dept).filter(Boolean))].sort();
const angle = d => 2 * Math.PI * depts.indexOf(d) / depts.length;
```

- `forceRadial(n => RING[n.type] ?? 300, 0, 0).strength(0.38)` — puts each type on its ring.
- `forceX(n => n.dept ? Math.cos(angle(n.dept)) * (RING[n.type]??300) : 0).strength(0.07)` and
  the matching `forceY` with `Math.sin` — pulls each node toward its department's angle.
  Strength 0.07 is deliberately weak: it should *bias* the ring, not snap nodes to spokes.
  Nodes with no `dept` (Domains) get target 0 and drift to the centre.
- `forceManyBody().strength(-45).distanceMax(180)` — local de-clumping only. The
  `distanceMax` cap is the single most important number here: uncapped many-body is what turns a
  400-node graph into a ball, because every node pulls on every other node's far field.
- `forceCollide()` at each node's drawn radius + 2 px — the actual anti-overlap.
- `forceLink().distance(26).strength(l => 0.12)` — links become a *hint*, not the layout driver.
  Weak link strength is what lets the radial structure survive.
- **Drop `forceCenter`** when using `forceRadial` + `forceX`/`forceY`. `forceCenter` only
  translates the whole system; it fights the radial force and contributes nothing.

This settles in well under 100 ticks because the positional forces are convex and don't
oscillate.

Sources: [d3-force](https://d3js.org/d3-force),
[forceInABox / group-in-a-box](https://github.com/john-guerra/forceInABox),
[d3 force registry](https://github.com/vasturiano/d3-force-registry),
[D3 in Depth: force layout](https://www.d3indepth.com/force-layout/).

---

## 3. Concrete `d3-force` values

### Defaults you are overriding (verified)

| Thing | Default |
|---|---|
| `simulation.alpha` | `1` |
| `simulation.alphaMin` | `0.001` |
| `simulation.alphaDecay` | `0.0228…` = `1 - 0.001**(1/300)` → **300 ticks to stop** |
| `simulation.velocityDecay` | `0.4` (velocity ×0.6 per tick) |
| `forceManyBody().strength` | `-30`; `theta` `0.9`; `distanceMin` `1`; `distanceMax` `Infinity` |
| `forceLink().distance` | `30`; `strength` `1 / Math.min(deg(source), deg(target))`; `iterations` `1` |
| `react-force-graph` `d3AlphaDecay` | `0.0228`, `d3VelocityDecay` `0.4`, `d3AlphaMin` `0`, `warmupTicks` `0`, `cooldownTicks` `Infinity`, `cooldownTime` `15000` |

Note `d3AlphaMin` defaults to **`0`** in `react-force-graph` (not `0.001`) — the component relies
on `cooldownTicks`/`cooldownTime` to stop instead. Set it explicitly.

Note also that `forceLink`'s default strength already divides by degree — so hub links are
already weak. Don't "fix" hubs by lowering link strength globally; cap `distanceMax` on charge
instead.

### Recommended values by graph size

Below, `r(n)` is the node's drawn radius in graph units (see §5).

| Force / prop | **~50 nodes** (walk / ego view) | **~150 nodes** (dept slice) | **~400 nodes** (full slice) |
|---|---|---|---|
| `forceManyBody().strength` | `-190` | `-110` | `-45` |
| `.distanceMax` | `420` | `300` | `180` |
| `.theta` | `0.9` | `0.9` | `0.9` |
| `forceLink().distance` | `44` | `34` | `26` |
| `forceLink().strength` | leave default | `0.18` | `0.12` |
| `forceCollide().radius` | `r(n) + 6` | `r(n) + 4` | `r(n) + 2` |
| `forceCollide().strength` / `.iterations` | `0.9` / `2` | `0.85` / `1` | `0.7` / `1` |
| `forceRadial(...).strength` | `0.30` | `0.34` | `0.38` |
| sector `forceX`/`forceY` strength | `0.05` | `0.06` | `0.07` |
| `forceCenter` | omit | omit | omit |
| `d3AlphaDecay` | `0.035` | `0.045` | `0.05` |
| `d3AlphaMin` | `0.02` | `0.02` | `0.02` |
| `d3VelocityDecay` | `0.45` | `0.50` | `0.55` |
| `warmupTicks` | `20` | `40` | `60` |
| `cooldownTicks` | `140` | `110` | `90` |

Rule of thumb behind the charge column: repulsion should scale roughly as `-k / density`. As
nodes get closer together (more of them in the same canvas), you need *less* per-pair repulsion
and *more* collision — collide is O(n log n) and bounded; charge is a long-range field that
compounds.

`d3VelocityDecay` above ~0.6 makes the settle look sluggish and syrupy; below ~0.3 the graph
visibly wobbles past its resting state. 0.45–0.55 is the band that looks intentional.

### The `d3AlphaDecay = 0` problem

Setting `d3AlphaDecay={0}` means `alpha` never decays, so it never crosses `alphaMin`, so the
simulation **never stops**. Consequences, all of which the previous attempt hit at once:

- Every frame runs the full force pass: Barnes–Hut many-body at O(n log n), link + collide at
  O(n) with `iterations` passes, forever. At 400 nodes / 2,300 links that's a real per-frame cost
  with zero visual payoff once the layout has converged.
- `autoPauseRedraw` (default `true`) only pauses the canvas when the engine has stopped. With
  `alphaDecay=0` it can never engage, so you also pay a **full canvas repaint every frame**,
  forever — 400 node paints + 2,300 stroked paths + whatever `nodeCanvasObject` does.
- A projector mirror commonly forces a second, larger framebuffer. Combined with
  `devicePixelRatio ≥ 2` on the laptop panel, you are rasterising several times the pixels you
  were testing against.
- The "breathing" it buys is illusory anyway: once the layout converges, residual motion is
  sub-pixel jitter, which reads as a shimmer artefact rather than life.

If you want ambient motion, get it without the simulation: add a tiny per-node
`sin(t * ω + n.__phase)` offset inside your painter and accept that you're paying only the
repaint, not the physics — and even then, budget it. On this graph the honest answer is: **let it
freeze.** A still, well-composed map reads as confident. A twitching one reads as unfinished.

---

## 4. Edge treatment

Edge clutter is the actual enemy. In priority order:

### 4.1 Show fewer edges by default

Classify every link at data-load time (once — not in an accessor):

```js
const BACKBONE = new Set(["CoOccurs", "Relates", "MemberOf", "DepartedWith"]);
link.__class = link.__walked ? "walked"
             : BACKBONE.has(link.type) && (link.weight ?? 1) >= WEIGHT_FLOOR ? "backbone"
             : "mist";
```

Then, at 400 nodes, set `linkVisibility={l => l.__class !== "mist"}` as the *default* view and
reveal mist edges only for the hovered/selected node's ego network. This alone converts the
hairball into a legible skeleton — and the reveal-on-hover is itself a good demo beat ("watch what
this one person touches").

#### ⇄ CHANGED — "keep the mist as texture" was a light-theme option and does not survive on dark

The light-theme draft offered a second choice: keep all ~2,300 mist edges visible at `alpha
0.04–0.06` as atmospheric texture. **Do not do that on `#0b0e14`.** Not because the value needs
inverting, but because the compositing arithmetic is different:

- **Dark-on-light is bounded; light-on-dark is not.** Six overlapping ink strokes at `α 0.045` on
  white composite to `1 − 0.955⁶ ≈ 0.24` toward the ink — soft grey that plateaus gracefully as
  density climbs. Six light strokes at the same `α` on near-black composite to the same `0.24`
  *toward white*, which on a black field is a self-illuminated haze. Dense regions don't settle
  into grey, they bloom into a glowing blob, and the blob is brightest exactly where the graph is
  densest — i.e. it highlights the hairball instead of hiding it.
- **The fix isn't a lower alpha.** Because sRGB is steep near black, an isolated stroke needs
  *more* alpha on dark to register at all (§5A.2). So the alpha that survives 6× overlap makes a
  lone edge invisible, and the alpha that makes a lone edge visible blows out at 6×. There is no
  single value that does both. On white, that tension is mild enough to split the difference; on
  black it isn't.

So: **hide mist by default, always, on dark.** If you must show some, cap it at `α 0.05` *and*
cut the mist edge count at the data layer rather than tuning the alpha. The reveal-on-hover path
is now the primary mechanism, not the fallback.

### 4.2 Opacity and width from weight

```js
linkColor={l =>
  l.__class === "walked"   ? "#FFD166" :
  l.__class === "backbone" ? `rgba(220,228,240,${0.14 + 0.20 * Math.min(1, (l.weight ?? 1) / 3)})` :
                             "rgba(220,228,240,0.05)"}   // only drawn when revealed on hover
linkWidth={l =>
  l.__class === "walked"   ? 2.4 :
  l.__class === "backbone" ? 0.5 + 1.0 * Math.min(1, (l.weight ?? 1) / 3) :
                             0.30}
```

The backbone ramp is `0.14 → 0.34`, not the light theme's `0.10 → 0.26`. Both ends move up
because sRGB compresses hard near black: a light stroke at `α 0.10` on `#0b0e14` measures ~1.09:1
contrast, where an ink stroke at `α 0.10` on `#FBFAF7` measures ~1.24:1. Equal alphas are *not*
equal presence. The mist width also drops `0.35 → 0.30`, since light strokes gain apparent weight
from irradiation (§5A.2).

Encode weight in **both** width and opacity. On a projector, opacity alone washes out and width
alone reads as noise; together they survive gamma-mangling.

### 4.3 Curvature

`linkCurvature` (number/string/func, default `0`; `0` = straight, `1` ≈ semicircle).

- `0.12` for backbone edges, `0.22` for mist edges. The differential is deliberate: the mist
  bows further out of the way of the structural lines.
- Curvature also disambiguates reciprocal pairs (`A→B` and `B→A` would otherwise overdraw). Use
  `linkCurveRotation` only in 3D — it's a no-op consideration in 2D.
- Sign matters visually. A *consistent* sign makes the whole graph look like it's rotating
  (pleasant, coherent). Alternating signs look chaotic. Use one constant.

### 4.4 Edge bundling — don't

Force-directed edge bundling (FDEB) and hierarchical edge bundling are the textbook answers to
dense edges, and they *are* beautiful
([Hierarchical edge bundling / D3](https://observablehq.com/@d3/hierarchical-edge-bundling),
[data-to-viz](https://www.data-to-viz.com/graph/edge_bundling.html)). But:

- `react-force-graph-2d` has no bundling support; you'd have to compute control points yourself
  and draw every edge through a custom `linkCanvasObject`, losing all the built-in link handling
  including particles.
- Hierarchical bundling requires the edges to connect *leaves of a hierarchy*. Your graph is not a
  hierarchy, and forcing one (dept → person → artifact) discards the domain edges that are the
  whole point.
- FDEB is O(E² ) -ish per iteration. At 2,300 edges that's a precompute you don't want mid-demo.

The radial-sector layout plus constant curvature already produces *visual* bundling for free:
edges between two department wedges naturally run as a coherent arc-shaped stream. Take that and
move on.

### 4.5 Arrows

Skip `linkDirectionalArrowLength` on the full graph — 2,300 arrowheads is 2,300 extra filled
triangles and they're illegible at that scale. Use arrows only on walked edges
(`linkDirectionalArrowLength={l => l.__walked ? 4 : 0}`, `linkDirectionalArrowRelPos 0.85`), where
direction is meaningful and the count is ~30.

---

## 5. Visual encoding that survives a projector

Projector reality: lower effective contrast, gamma shift toward washed-out, viewers 3–8 m away.
Design for the worst seat.

### Hard floors

- Smallest meaningful node: **≥ 6 screen px diameter**.
- Smallest label: **≥ 12 screen px**.
- Body text contrast: **≥ 4.5:1** against `#0b0e14`. `rgba(220,228,240,0.45)` is roughly the lowest
  fill that still reads as "a dot is there"; don't go below it for anything that matters. (That is
  a higher alpha than the light theme's `0.35` floor — see §5A.2 for why.)
- Never encode anything load-bearing in hue alone at this distance. Position and shape survive;
  hue and fine grey levels do not.

### Node sizing — the formula you need

`react-force-graph` computes node radius as `Math.sqrt(nodeVal) * nodeRelSize`. It is **area**,
not radius. So `nodeVal=7, nodeRelSize=3` gives radius ≈ 7.9 graph units, and doubling `nodeVal`
gives only a 1.41× radius. Size by degree with an explicit sqrt already applied if you want linear
visual growth:

```js
nodeRelSize={4}
nodeVal={n => n.__focus ? 9 : ({Domain: 6, Department: 4, Person: 3, Event: 1.6}[n.type] ?? 0.7)}
```

### Marks by type

See **§5A.4** for the full colour table and the argument about hue vs monochrome. The shape
vocabulary is unchanged from the light draft and is the load-bearing part:

| Type | Mark |
|---|---|
| `Domain` | disc + 1.5 px concentric ring, 3 px gap |
| `Department` | hollow square, 1.2 px stroke, no fill |
| `Person` | filled disc |
| `Event` | diamond; incidents get a 1 px accent ring |
| artifacts (8 types) | 1.5 px hollow dot, stroke only |

Do **not** try to distinguish the eight artifact types visually at the full-graph level. Nobody can
read an eight-way distinction in a 3 px mark. They're one visual class ("evidence"); the
distinction appears in labels and the hover card, where it's readable.

### Halos and rings

For any node that must pop against dense edges — active node, hover, focus set — draw a
**`#0b0e14`** disc at `r + 3` *before* the mark. That knockout is what separates a node from the
edges passing behind it, and it's cheap. Same trick for labels (§6).

On dark this matters *more* than it did on light: the edges passing behind a node are now
self-illuminated rather than absorbing, so without a knockout a node sits in a bright haze and
loses its silhouette. Budget `r + 3.5` where edges are dense.

---

## 5A. Dark colour specification (authoritative)

Everything in this section is computed against **`--bg #0b0e14`** (relative luminance `0.0043`).
Contrast ratios are WCAG 2.1 and were calculated, not estimated.

### 5A.1 Tokens

```css
--bg:      #0b0e14;   /* canvas                                    */
--panel:   #121722;   /* hover cards, side panels                  */
--rule:    #1E2637;   /* hairlines, sector dividers                */
--faint:   #4A566B;   /* de-emphasised text                        */
--muted:   #8494AD;   /* secondary labels, department region names */
--ink:     #DCE4F0;   /* primary text + primary node fill  15.1:1  */
--accent:  #FFD166;   /* walk / active hop ONLY            13.4:1  */
```

### 5A.2 Why light-on-dark is not the mirror of dark-on-light

Three separate effects, all pushing different directions. Getting these confused is how dark
themes end up either invisible or glaring.

1. **sRGB is steep near black, so low alphas under-deliver.** The encoding curve means small
   `α` changes near the black end produce very small *luminance* changes. Measured: an ink stroke
   at `α 0.10` on `#FBFAF7` gives ~1.24:1 contrast; a `--ink` stroke at `α 0.10` on `#0b0e14`
   gives ~1.09:1. **Consequence: raise every low alpha by roughly 1.4–1.6× when porting a value
   from the light draft.** That is where the `0.35 → 0.45` node floor and the `0.10 → 0.14`
   backbone floor come from.

2. **Overlap composites additively, so high densities over-deliver.** Covered in §4.1 ⇄. Light
   strokes stack *toward white* without bound; ink strokes stack *toward ink* and plateau. This
   pulls the opposite way from (1), which is why there is no single scale factor and why the mist
   tier had to be dropped rather than retuned.

3. **Irradiation makes light marks look fatter.** A light shape on a dark field appears
   dimensionally larger than a dark shape of identical geometry on a light field — an optical
   effect in the eye, amplified by any display bloom. **Consequence: shave ~10–15 % off stroke
   widths and use one font weight lighter than you would on paper.** Hence mist width `0.35 →
   0.30`, and §6.1's move to weight 400–500 for labels.

(1) and (3) are why "just invert the alphas" produces something that looks simultaneously washed
out and blurry.

### 5A.3 The accent: drop `#E5432B` on the canvas, keep `#FFD166`

**Verdict: the site's vermilion does not survive the move to dark. Use `#FFD166`.**

| Candidate | Contrast on `#0b0e14` | Verdict |
|---|---|---|
| `#E5432B` (site accent) | **4.76:1** | Too dark. See below. |
| `#FF6B4A` (lightened vermilion) | 6.86:1 | Workable if brand continuity is mandatory |
| `#FFD166` (current app value) | **13.4:1** | **Use this** |

Three reasons, in order of weight:

- **4.76:1 is not enough for the one thing that must dominate.** The accent's entire job is to be
  the first thing the eye lands on. At 4.76:1 it is *dimmer* than `--ink` at 15.1:1 — the walk
  path would be less salient than the labels it passes. That inverts the hierarchy.
- **Saturated red is the worst hue on near-black.** Red carries the least luminance per unit
  saturation of any primary, so a "vivid" red is always a *dark* colour. Pair that with a dark
  field and you get the classic red-on-black chromatic-aberration shimmer, worst for viewers with
  uncorrected vision — i.e. some fraction of any audience at 8 m.
- **Projectors kill it first.** Lifted blacks (§5A.5) compress the bottom of the range. A 4.76:1
  pair on a laptop panel can land near 3:1 in a lit room; a 13.4:1 pair still has margin.

**On losing the brand colour:** that's fine, and worth saying out loud if asked. The canvas and
the marketing site are different surfaces with different jobs. The accent on the canvas is doing
*salience*, not *recall* — nobody identifies a product from a highlight colour on a graph they see
for four minutes. The site keeps `#E5432B`; the canvas gets the colour that wins at 8 m. If
someone insists on continuity, `#FF6B4A` at 6.86:1 is the compromise, and it costs about a third
of the walk path's pop.

Accent usage, in full — unchanged from the light draft, and the scarcity rule still governs:

- walked links + walked nodes
- the currently-active hop (accent ring, pulsing once)
- `Event` nodes that are incidents (1 px ring only, never a fill)
- nothing else

Hover does **not** get the accent on dark. Use `--ink` at full opacity plus the knockout ring
instead — that reads as "lit" against the dimmed field without competing with the walk.

### 5A.4 ⇄ CHANGED — a small hue set comes back

The light draft argued for **monochrome ink at four alpha levels, type carried by shape alone**.
Half that argument was specific to the light background and does not hold here.

The argument had two legs. **Leg 1 — accent scarcity —** survives and is in fact *stronger*: a
single bright element on a dark field is more salient than a single dark element on a light field,
so reserving `#FFD166` buys more here than it did there.

**Leg 2 — "grey levels don't read at distance, so use shape" — inverts.** The claim was that four
alpha steps of ink are hard to tell apart across a room. True on white; **worse on black**, for
the reason in §5A.2(1): sRGB compression near the black end means the *available* number of
perceptually distinct steps between `#0b0e14` and `#DCE4F0` is smaller than between `#FBFAF7` and
`#12100E`. A four-level monochrome ramp that was merely marginal on light becomes genuinely
ambiguous on dark.

Something has to carry the semantic tier, and shape alone can't do it at 3 px. So hue comes back —
but **four hues, not the ten currently in `web/GraphCanvas.jac`**:

| Type | Colour | Contrast | Mark |
|---|---|---|---|
| `Domain` | `#7FE0A8` mint | 12.1:1 | disc + concentric ring |
| `Person` | `#7CC7F5` cyan | 10.4:1 | filled disc |
| `Event` | `#B98CFF` violet | 7.5:1 | diamond |
| `Department` | `#8494AD` (`--muted`) | 5.6:1 | hollow square, stroke only |
| artifacts (all 8) | `#6E7C93` | 4.6:1 | 1.5 px hollow dot, stroke only |
| walk / active | `#FFD166` | 13.4:1 | — |

Hue is deliberately **correlated with the ring radius** from §2 — mint at the centre, cyan in the
people ring, violet and grey in the halo — so colour reinforces position rather than adding an
independent channel to decode. The artifact mass stays monochrome, which is where the light
draft's instinct was right: eight types in one grey is correct, and their differentiation is
positional (which sector, which ring) plus on-demand.

**On the existing ten-hue palette in `GraphCanvas.jac`** (`Person #5ec8f8`, `Department #c792ea`,
`Domain #8bd450`, `Event #ff7b72`, `ConfluencePage #f7c948`, `SlackThread #f79ac0`, `Email
#ffa657`, `JiraTicket #79c0ff`, `ZoomTranscript #a5d6ff`, `PullRequest #d2a8ff`) — retire it. Two
concrete defects, beyond being too many:

- **Three near-identical blues.** `#5ec8f8` (Person), `#79c0ff` (Jira) and `#a5d6ff` (Zoom) are
  indistinguishable at 3 px across a room, and they span the Person/artifact boundary — the one
  distinction that actually matters.
- **`#f7c948` (ConfluencePage) collides with the walk accent.** An amber artifact class sitting
  next to an amber walk path is disqualifying on its own: the highlight must be unique or it
  stops being a highlight.

The palette is not bad work — it's a reasonable dark-theme categorical set. It's solving the wrong
problem. Eight artifact types don't need eight hues; they need one hue and a legible position.

### 5A.5 Projector caveat, stated honestly

Dark canvases are *riskier* on projectors than light ones, and since the decision is made, plan
for it rather than discover it:

- **Black levels lift.** A projector cannot emit "no light", and ambient room light adds more.
  `#0b0e14` will present as a dark grey, compressing everything at the bottom of the range. Every
  contrast ratio in this section is a laptop-panel number and an upper bound.
- **Practical rule: raise all alphas ~20–30 % from what looks right on your panel**, and never
  rely on a distinction below ~3:1 measured. If two things need to be told apart, give them
  different *shapes* as well.
- **Check the room before the room checks you.** If the venue is bright and the projector is weak,
  the dark canvas will grey out globally. There is no in-app fix at that point — the only lever is
  raising `--bg` toward `#151A24`, which costs contrast everywhere. Worth a five-minute test on
  the actual hardware if you get the chance.
- Avoid large gradients. Dark gradients band visibly on 8-bit projectors; if one is unavoidable,
  dither it with low-amplitude noise.

---

## 6. Labels

An unlabelled graph is decoration; a fully-labelled one is soup. The rules:

### 6.1 Draw labels in `onRenderFramePost`, not `nodeCanvasObject`

This is the key structural decision. `nodeCanvasObject(node, ctx, globalScale)` is invoked in
graph iteration order, so you cannot decide "draw the important labels first, drop whatever
collides". `onRenderFramePost(ctx, globalScale)` runs once per frame with the canvas already
transformed into graph coordinates, so you can sort by priority and cull:

```js
onRenderFramePost={(ctx, k) => {
  if (k < 1.3 && !focusActive) return;                 // level-of-detail gate
  const placed = [];                                    // screen-space boxes
  for (const n of labelCandidates) {                    // pre-sorted by priority
    const fs = 12 / k;                                  // → 12 screen px, always
    ctx.font = `${fs}px ui-sans-serif, system-ui, sans-serif`;
    const w = n.__lw ?? (n.__lw = ctx.measureText(n.__label).width / fs); // cache in em
    const box = { x: n.x - (w*fs)/2, y: n.y - fs*2, w: w*fs, h: fs*1.4 };
    if (placed.some(p => overlaps(p, box))) continue;   // greedy occlusion cull
    placed.push(box);
    ctx.textAlign = "center"; ctx.textBaseline = "bottom";
    ctx.lineWidth = 4 / k; ctx.strokeStyle = "#0b0e14";  // knockout, thicker than on light
    ctx.strokeText(n.__label, n.x, n.y - 8/k);
    ctx.fillStyle = n.__focus ? "#FFD166" : "rgba(220,228,240,0.92)";
    ctx.fillText(n.__label, n.x, n.y - 8/k);
  }
}}
```

Three details that matter:

- **`ctx.measureText` per node per frame is a real cost.** Cache the measured width *in em* on the
  node object (`n.__lw`) so it survives zoom changes — width in em is scale-invariant.
- **`placed.some(...)` is O(L²).** Fine up to ~60 labels. Above that, bucket `placed` into a
  screen-space grid of ~32 px cells and only test the 4 cells the box touches.
- **`12 / k`** keeps the label at a constant *screen* size regardless of zoom. This is what makes
  semantic zoom feel right — labels don't balloon when you zoom in, more of them just appear.

Two dark-specific adjustments to the code above:

- **The knockout is `4/k`, not `3/k`.** Light glyphs bloom outward (§5A.2(3)) and the edges behind
  them are now emissive rather than absorbing, so a 3 px knockout gets swallowed. 4 px is the
  minimum that reliably separates a label from a bright edge crossing behind it.
- **Use font weight 400–500, not 600.** Light-on-dark text reads roughly one weight heavier than
  the same weight on light. Specifying the weight you'd use on paper produces labels that look
  chunky and, at small sizes, smeared. `500` on dark ≈ `600` on light.
- Label fill is `rgba(220,228,240,0.92)`, and the `--muted` `#8494AD` is the right value for
  department region names — it holds 5.6:1, which is enough for large sparse text and keeps them
  visually subordinate to node labels.

### 6.2 Which labels, when

Priority-sorted candidate list, rebuilt only when data or focus changes:

1. Focus-set nodes (during a walk / after a query) — **always**, ignore the zoom gate.
2. `Domain` nodes — always. There are few of them and they're the semantic anchors.
3. `Department` nodes — always, rendered as small caps in `--muted`, placed on the sector's outer
   edge rather than at the node, so they read as *region labels* for the wedge.
4. `Person` nodes with degree ≥ P75 — only when `k > 1.3`.
5. Everything else — only when hovered, or when `k > 2.5`.

The department-name-as-region-label trick is worth doing: five or six words laid around the ring
turn an abstract diagram into a map. It's most of the difference between "a graph" and "our
company".

Sources: [Minimizing overlapping labels in interactive visualizations](https://towardsdatascience.com/minimizing-overlapping-labels-in-interactive-visualizations-b0eabd62ef0/),
[Fast point-feature label placement for dynamic visualizations](https://arxiv.org/pdf/1209.5766).

---

## 7. Focus + context

### 7.1 The query-result question: dim, don't replace

The current code filters `graphData` down to the focus subgraph. Don't. Swapping `graphData`
re-seeds the simulation, so every node jumps to a new position, and the judge loses the mental map
they just built. **Dim + zoom** preserves it, and the "the rest of the org is still there, greyed
out" framing is a stronger story than "here is a small disconnected graph".

```js
// on query result
const focus = new Set(result.node_ids);
graphData.nodes.forEach(n => { n.__focus = focus.has(n.id); });
graphData.links.forEach(l => {
  l.__focus = focus.has(id(l.source)) && focus.has(id(l.target));
});
fg.current.zoomToFit(700, 90, n => n.__focus);
```

with accessors:

```js
nodeColor={n => n.__focus ? hueOf(n) : "rgba(220,228,240,0.10)"}
linkVisibility={l => l.__focus || l.__class === "backbone"}
linkColor={l => l.__focus ? "#FFD166" : "rgba(220,228,240,0.07)"}
```

The dimmed floor is `0.10`, not the light draft's `0.07`, and the dimmed link is `0.07`, not
`0.05` — both raised per §5A.2(1), since at `0.07` on `#0b0e14` a node is genuinely gone rather
than merely quiet. Note also that the focused nodes keep their **hue** (`hueOf(n)` from §5A.4)
rather than going to flat ink: on dark, the dimmed field is so recessive that the focus set can
afford full colour without the view becoming busy.

Keeping the backbone visible while dimming the mist gives you *context* (the shape of the org is
still legible) without *clutter*. That's the whole point of focus+context.

### 7.2 Semantic zoom

Three tiers, driven by `k` from `onZoom({k, x, y})` (store it in a ref, not state — see §9):

| `k` | Shown |
|---|---|
| `< 1.3` | Marks only. Domain + Department labels. Mist edges as texture. |
| `1.3 – 2.5` | + high-degree Person labels. Mist edges at full (still low) opacity. |
| `> 2.5` | + all labels that survive occlusion culling. Artifact marks grow to 3 px. |

### 7.3 Ego networks / expand-on-click

`onNodeClick(node, event)` → set an ego set of the node plus its 1-hop neighbours, apply the same
dim treatment, `centerAt(node.x, node.y, 400)` and `zoom(2.2, 400)`. This is the cheapest
interactive beat in the whole app and it always lands in a demo, because the graph visibly
*answers* a click.

Fisheye / degree-of-interest distortion: technically the classic answer, but it requires
per-frame coordinate warping of every node and the resulting picture is hard to screenshot and
harder to narrate. Dim + zoom achieves the same goal legibly. Skip fisheye.

---

## 8. Animating the traversal so it's unmistakable

Goal: from eight metres away, a judge can see *a thing moving along a line, one hop at a time*,
and afterwards the route it took is still on screen.

### 8.1 Timing

| Beat | Duration |
|---|---|
| One hop | **320 ms** (range 250–400; go 380 ms if someone is narrating each hop) |
| Particle transit | should complete within the hop — see the speed formula below |
| Node arrival pulse | 220 ms, ease-out, ring expands `r → r + 8` while fading `0.9 → 0` |
| Pause between path segments | 500 ms if the walk has logical phases worth naming |
| Final `zoomToFit` over the path | 700 ms |

Total for a 12-hop walk ≈ 4 s. That's the right length: long enough to watch, short enough that a
4-minute demo can run it twice.

### 8.2 `linkDirectionalParticleSpeed` — get this number right

Speed is a **fraction of the link's length traversed per frame**. At 60 fps, transit time is
`1 / (speed × 60)` seconds. So:

- `0.02` (the current value) → **~830 ms per transit**. Far too slow for a 320 ms hop; the
  particle is still crawling along hop 1 when hop 3 starts, which is exactly what turns a walk
  into a smear.
- For a 320 ms hop: `speed ≈ 1 / (0.32 × 60) ≈ **0.052**`.
- For a 400 ms hop: `≈ 0.042`.

Keep `linkDirectionalParticleWidth` at **3.5** on dark. (The light draft said 3, reasoning that a
high-contrast accent on near-white blobs out. On `#0b0e14` the opposite pressure applies: the
token is competing with its own glow — §8.7 — and irradiation makes it read *smaller* relative to
a bloomed halo, so it needs a little more body. Do not go to 4.5+; past that it stops reading as a
travelling point and starts reading as a growing segment.)

### 8.3 The hop loop

```js
async function walk(path) {           // path: [[srcId, tgtId], ...]
  if (reduced) { path.forEach(markWalked); fg.current.refresh(); return; }
  fg.current.autoPauseRedraw = false;                     // keep the canvas alive
  for (const [s, t] of path) {
    const link = linkIndex.get(key(s, t));
    fg.current.emitParticle(link);
    setTimeout(() => fg.current.emitParticle(link), 60);  // two-token stagger reads richer
    link.__active = true;
    await sleep(320);
    link.__active = false;
    link.__walked = true;                                 // permanent
    nodeById.get(t).__walked = true;
    nodeById.get(t).__pulseAt = performance.now();
    fg.current.refresh();
  }
  fg.current.zoomToFit(700, 90, n => n.__walked);
  fg.current.autoPauseRedraw = true;
}
```

`emitParticle(link)` emits a **single non-cyclical** particle, which is exactly the semantics you
want for one hop. Prefer it over a persistent `linkDirectionalParticles` count, which spawns an
endless cyclic stream and keeps the redraw loop pinned forever.

Optionally set `linkDirectionalParticles={l => l.__active ? 2 : 0}` so the *current* hop also has a
continuous stream — that's at most one link's worth of cost and makes the active edge unambiguous.
Never a constant: a constant puts particles on all ~2,300 edges, redrawn every frame. (The current
code already avoids this and the file's header comment correctly records why — keep that comment.)

### 8.4 The arrival pulse

Drawn in `nodeCanvasObject` (mode `"after"`), reading a timestamp off the node:

```js
const age = performance.now() - (n.__pulseAt ?? -1e9);
if (age < 220) {
  const p = age / 220;
  ctx.beginPath();
  ctx.arc(n.x, n.y, r + 8 * p, 0, 2 * Math.PI);
  ctx.strokeStyle = `rgba(255,209,102,${0.95 * (1 - p)})`;
  ctx.lineWidth = 2 / k;
  ctx.stroke();
}
```

A single expanding ring is more legible at distance than any easing subtlety. Resist adding a
second effect.

The ring starts at `0.95` rather than the light draft's `0.9`: an expanding ring thins as it grows
while its alpha falls, and on dark the tail end disappears sooner (§5A.2(1)). Starting slightly
hotter keeps the full 220 ms legible.

### 8.5 Camera

**Do not `centerAt` every hop.** Per-hop panning is the fastest way to make a projector audience
seasick and it destroys spatial memory. Instead:

- `zoomToFit(600, 120, n => pathNodes.has(n.id))` **once, before** the walk starts, so the whole
  route is on screen.
- Only pan mid-walk if the next node is outside the viewport — check with
  `graph2ScreenCoords(n.x, n.y)` against `[0, width] × [0, height]` with a 60 px margin.
- `zoomToFit(700, 90, n => n.__walked)` once at the end, to settle on the result.

### 8.6 After the walk

Leave it lit. Walked links stay `#FFD166` at width 2.4 (with the glow from §8.7 still applied),
walked nodes stay at full `--ink` with labels forced on, everything else drops to 10 % ink. The
still frame of the finished path *is* the screenshot the judges remember — treat it as a designed
end state, not as "whatever's left over".

On dark this end state is materially stronger than its light-theme equivalent: an amber path
glowing over a dimmed near-black field is close to the platonic "knowledge graph" image, and it
photographs well under room lights. Budget a beat of silence on it.

### 8.7 ⇄ CHANGED — glow, the one technique dark gains

Not an inversion of anything in the light draft — **a capability that did not exist there.** On
near-white, `ctx.shadowBlur` reads as a smudge or a printing defect, which is why the light
version never mentioned it. On `#0b0e14` it reads as *emission*, and it is the single most
striking effect available on this page for the cost.

```js
// inside linkCanvasObject / nodeCanvasObject, for walked + active elements ONLY
ctx.save();
ctx.shadowColor = "#FFD166";
ctx.shadowBlur  = (l.__active ? 16 : 8) / k;   // graph units -> constant screen blur
ctx.strokeStyle = "#FFD166";
ctx.lineWidth   = 2.4 / k;
// ... stroke the path ...
ctx.restore();                                  // ALWAYS restore; shadow state is sticky
```

Rules, all of which matter:

- **Walked and active elements only.** Never the backbone, never a node type, never hover. Glow is
  a second scarce channel and it should coincide exactly with the accent — same elements, same
  colour. Two glowing things and it stops meaning anything.
- **Blur scales with `1/k`** so it stays a constant apparent size across zoom, exactly like label
  font size.
- **`shadowBlur` is genuinely expensive** — it is a per-pixel convolution, and it is the one
  effect in this document that can move you off 60 fps by itself. It is affordable here *only*
  because it applies to ~30 links and ~30 nodes. Never put it on an accessor that could return
  truthy for the whole graph. If frames drop during the walk, this is the first thing to cut, and
  cutting it costs you polish rather than legibility.
- **Always `save()`/`restore()`.** Canvas shadow state persists across draw calls; a missing
  `restore()` silently applies glow to every subsequent element and tanks the frame rate in a way
  that looks like a mysterious general slowdown.
- Under `prefers-reduced-motion`, keep the glow (it is static, not motion) but drop the
  `__active`/`__walked` distinction to a single value — the pulsing difference between 16 and 8 is
  the animated part.

---

## 9. `react-force-graph-2d` props that matter

Verified against the [react-force-graph README](https://github.com/vasturiano/react-force-graph)
and [force-graph](https://github.com/vasturiano/force-graph), 2026-07-26.

### Data

| Prop | Type / default | Notes |
|---|---|---|
| `graphData` | `{nodes, links}`, `{nodes:[], links:[]}` | Mutating in place + `refresh()` is much cheaper than replacing the object. Replacing re-seeds positions. |
| `nodeId` | string, `"id"` | |
| `linkSource` / `linkTarget` | string, `"source"` / `"target"` | After the first tick the library **replaces the id with the node object**. Any accessor comparing to ids must handle both — the existing `end_id()` helper is correct and must be kept. |

### Nodes

| Prop | Signature / default | Notes |
|---|---|---|
| `nodeRelSize` | number, `4` | radius = `sqrt(nodeVal) * nodeRelSize` |
| `nodeVal` | num/str/func, `"val"` | area-like, see §5 |
| `nodeLabel` | str/func, `"name"` | native tooltip; accepts an HTML string |
| `nodeColor` | str/func, `"color"` | **a plain string is read as a property name, not a colour** — always pass a function |
| `nodeVisibility` | bool/str/func, `true` | |
| `nodeCanvasObject` | `(node, ctx, globalScale) => void` | |
| `nodeCanvasObjectMode` | str/func, `"replace"` | `replace` \| `before` \| `after` |
| `nodePointerAreaPaint` | `(node, color, ctx, globalScale) => void` | paint a *solid* shape in `color` to define the hit area |

### Links

| Prop | Signature / default | Notes |
|---|---|---|
| `linkColor` | str/func, `"color"` | same string-is-a-property-name trap |
| `linkWidth` | num/str/func, `1` | |
| `linkOpacity` | number, `0.2` | applies only to the *default* colour path; irrelevant once you return rgba from `linkColor` |
| `linkVisibility` | bool/str/func, `true` | cheapest clutter control there is |
| `linkCurvature` | num/str/func, `0` | `1` ≈ semicircle |
| `linkLineDash` | `number[]`/str/func | 2D only |
| `linkCanvasObject` | `(link, ctx, globalScale) => void` | avoid — you lose built-in particles |
| `linkCanvasObjectMode` | str/func, `"replace"` | |
| `linkDirectionalArrowLength` | num/str/func, `0` | |
| `linkDirectionalArrowRelPos` | num/str/func, `0.5` | |
| `linkDirectionalParticles` | num/str/func, `0` | count of *cyclic* particles |
| `linkDirectionalParticleSpeed` | num/str/func, `0.01` | fraction of link length **per frame** |
| `linkDirectionalParticleWidth` | num/str/func, `0.5` | |
| `linkDirectionalParticleColor` | str/func, `"color"` | function, not string |
| `linkDirectionalParticleOffset` | num/str/func, `0` | stagger multiple particles |
| `linkPointerAreaPaint` | `(link, color, ctx, globalScale) => void` | |
| `linkHoverPrecision` | number, `4` | lower = cheaper hit-testing |

### Engine

| Prop | Default | Notes |
|---|---|---|
| `d3AlphaDecay` | `0.0228` | **never `0`** |
| `d3VelocityDecay` | `0.4` | |
| `d3AlphaMin` | `0` | set to `0.02` so it actually converges |
| `warmupTicks` | `0` | ticks run *before* first paint — use to skip the ugly early phase |
| `cooldownTicks` | `Infinity` | ticks after which it freezes |
| `cooldownTime` | `15000` ms | whichever of the two hits first |
| `onEngineTick` | `() => void` | keep this empty or trivial; it's per-tick |
| `onEngineStop` | `() => void` | good place for the first `zoomToFit` |
| `dagMode` | — | `td`/`bu`/`lr`/`rl`/`radialout`/`radialin`; needs an acyclic graph |
| `forceEngine` | `"d3"` | |

### Container / render

`width`, `height` (**both default to the *window*, not the parent — always pass explicit pixels**,
which the current code correctly does via `boxRef`), `backgroundColor`, `minZoom` (`0.01`),
`maxZoom` (`1000`), `autoPauseRedraw` (`true`), `onRenderFramePre(ctx, globalScale)`,
`onRenderFramePost(ctx, globalScale)`.

### Interaction

`onNodeClick(node, event)`, `onNodeHover(node, prevNode)`, `onLinkHover(link, prevLink)`,
`onBackgroundClick(event)`, `onZoom({k,x,y})`, `onZoomEnd({k,x,y})`, `enableNodeDrag` (`true`),
`enablePointerInteraction` (`true`), `enableZoomInteraction`, `enablePanInteraction`,
`showPointerCursor`.

### Imperative methods (via `ref`)

| Method | Notes |
|---|---|
| `d3Force(name, [force])` | default registered forces are **`'link'`, `'charge'`, `'center'`**. Add `'collide'`, `'radial'`, `'x'`, `'y'` yourself. Remove `'center'` with `d3Force('center', null)`. |
| `d3ReheatSimulation()` | resets alpha to 1 |
| `zoomToFit([ms=0], [px=10], [nodeFilterFn])` | the filter argument is the important one |
| `centerAt([x], [y], [ms])` / `zoom([k], [ms])` | |
| `emitParticle(link)` | one non-cyclical particle |
| `refresh()` | force redraw after mutating node/link objects in place |
| `getGraphBbox([nodeFilterFn])` | `{x:[min,max], y:[min,max]}` |
| `screen2GraphCoords(x, y)` / `graph2ScreenCoords(x, y)` | for the off-screen check in §8.5 |
| `pauseAnimation()` / `resumeAnimation()` | pause while a modal is open |

### Wiring the custom forces

```js
import { forceCollide, forceRadial, forceX, forceY } from "d3-force-3d";

useEffect(() => {
  const fg = ref.current; if (!fg) return;
  fg.d3Force("center", null);
  fg.d3Force("collide", forceCollide(n => radiusOf(n) + 2).strength(0.7));
  fg.d3Force("radial", forceRadial(n => RING[n.type] ?? 300, 0, 0).strength(0.38));
  fg.d3Force("x", forceX(n => sectorX(n)).strength(0.07));
  fg.d3Force("y", forceY(n => sectorY(n)).strength(0.07));
  fg.d3Force("charge").strength(-45).distanceMax(180);
  fg.d3Force("link").distance(26).strength(0.12);
}, [nodeCount]);
```

Import from **`d3-force-3d`**, which is what `react-force-graph` uses internally. Plain `d3-force`
forces happen to work in 2D (they operate on `x/y/vx/vy`) but matching the bundled version avoids
subtle mismatches and a duplicate dependency.

---

## 10. Performance checklist for the demo laptop

Ordered by how much each one bites:

1. **Never `d3AlphaDecay=0`.** See §3.
2. **Never a constant `linkDirectionalParticles`.** Accessor returning 0 for all but the active
   link.
3. **Precompute, don't derive per frame.** The current `is_walked()` builds two strings and does
   an `in list` linear scan, and it's called by four separate accessors on every link on every
   frame. At 2,300 links × 4 × 60 fps that's ~550k string allocations/second and a linear scan
   each time. Replace with a boolean stamped on the link object (`l.__walked`) whenever the walk
   state changes. Same for `__class`, `__focus`, `__label`, `__lw`.
4. **Cache `ctx.measureText`.** Store width in em on the node (`n.__lw`); it's zoom-invariant.
5. **`enablePointerInteraction={false}` during the walk** and whenever nothing is hoverable. It
   removes an entire off-screen hit-test render pass.
6. **`linkHoverPrecision={2}`** (from `4`) once you do want hover.
7. **`autoPauseRedraw` stays `true`** except during the walk animation.
8. **`enableNodeDrag={false}`** on the full graph — dragging reheats the simulation, and a judge
   nudging a node into a 3-second re-settle mid-demo is a bad time.
9. **Cap the slice.** `max_nodes: 400` is already in the contract; 400 is a reasonable ceiling for
   a canvas renderer with custom painters. If you need more, that's a Cosmograph/WebGL problem,
   not a tuning problem.
10. **Test at projector resolution.** Mirroring often forces a different framebuffer size; profile
    at 1920×1080 scaled, not just the laptop panel.
11. **`ctx.shadowBlur` only on walked/active elements** (§8.7). It is a per-pixel convolution and
    the one dark-theme-specific way to lose 60 fps. Always `save()`/`restore()` around it — leaked
    shadow state applies glow to everything drawn afterwards.

### `prefers-reduced-motion`

```js
const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
```

- `warmupTicks={reduced ? 150 : 60}` and `cooldownTicks={reduced ? 0 : 90}` — the layout arrives
  already settled, with no visible animation.
- All particles off; path revealed in one `refresh()`.
- Every camera call with `ms = 0`.
- The arrival pulse skipped entirely (walked nodes just render in their final state).
- Listen for changes (`mql.addEventListener("change", ...)`) rather than reading once at mount.

---

## 11. Reference-quality examples, and what specifically makes them work

| Example | What to steal |
|---|---|
| [Hierarchical edge bundling / D3 (Observable)](https://observablehq.com/@d3/hierarchical-edge-bundling) | The **hover interaction**, not the bundling. Hovering one leaf splits its edges into two colours — incoming vs outgoing — and dims everything else to near-nothing. That single interaction turns a dense ring into a readable answer. Copy this exactly for `onNodeHover`. |
| [Arc diagram / D3 (Observable)](https://observablehq.com/@d3/arc-diagram) | Proof that **node ordering is a design decision**. The same data looks like noise or like structure depending purely on the sort. Your equivalent lever is the department sector order — order departments by how much they co-occur, not alphabetically, and the cross-arcs get shorter and the picture calms down. |
| [D3 gallery](https://observablehq.com/@d3/gallery) | Broad, but note how consistently the good ones use **one accent against a neutral field**. Almost none of the memorable examples are polychrome. |
| [Elijah Meeks — Effective Network Visualization with D3](http://elijahmeeks.com/networkviz/) | The clearest practitioner argument that layout choice, not styling, is what makes networks legible. Good ammunition if someone wants to "just tune the forces". |
| [Cosmograph](https://cosmograph.app/examples) ([IIB Awards writeup](https://www.informationisbeautifulawards.com/showcase/5231-cosmograph)) | GPU-side force simulation, up to ~1M nodes. Not the right tool for 400 nodes with custom canvas marks — but look at the *aesthetic*: extremely fine, low-opacity edges as a continuous field, small bright nodes on top. That "edges as mist, nodes as stars" separation is directly what §4.2's opacity values are chasing. |
| [Gephi showcase](https://gephi.github.io/) | The canonical "beautiful network map" look. What makes those images work is almost always: strong community separation from the layout, **labels sized by degree with most labels omitted**, and a single-hue-plus-neutral palette. Note how few nodes are labelled in any Gephi image you find beautiful. |
| [Graph aesthetics (Mastering Gephi, O'Reilly)](https://www.oreilly.com/library/view/mastering-gephi-network/9781783987344/ch03s06.html) | Explicit aesthetic criteria — spacing, sizing, colouring, labelling — with the right caveat: aesthetics must enhance the relationships, not obscure them. |
| [data-to-viz: hierarchical edge bundling](https://www.data-to-viz.com/graph/edge_bundling.html) | Honest about when bundling helps and when it lies about connectivity. Read before anyone proposes bundling. |

The common thread in every genuinely beautiful one: **a lot has been left out.** Fewer edges,
fewer labels, fewer colours, more empty space. The instinct to show all the data is what produces
hairballs.

---

## 12. Migration notes for the current `web/GraphCanvas.jac`

What's already right and should survive:

- `boxRef` + explicit `width`/`height` (the component otherwise sizes to `window`).
- `end_id()` handling both id-string and node-object link ends.
- Accessor functions for colour rather than strings.
- Particles from an accessor, zero everywhere except walked edges.
- Bounded simulation (`warmupTicks` / `cooldownTicks`) rather than infinite.
- **The `#0b0e14` background — this was right all along.** The light-theme draft of this document
  wrongly told you to change it. Leave it.
- **`WALK_COLOR = "#ffd166"` — also right all along.** §5A.3 re-derives it independently as the
  best available accent on this background. Leave it (optionally uppercase it for consistency).
- The header comment documenting all of the above — keep it, extend it.

What changes:

| Now | Change to |
|---|---|
| 10-colour `TYPE_COLOR` map | 4-hue semantic set + monochrome artifact mass (§5A.4). Retire `#f7c948` in particular — it collides with `WALK_COLOR`. |
| Three near-identical blues (`#5ec8f8`, `#79c0ff`, `#a5d6ff`) | One `Person` cyan `#7CC7F5`; artifacts go monochrome `#6E7C93` |
| No glow | `ctx.shadowBlur` on walked + active elements only (§8.7) |
| Filters `graphData` to focus set during a walk | Keeps full `graphData`, dims non-focus (§7.1) |
| `is_walked()` recomputed per accessor per frame | `l.__walked` boolean stamped on the link object |
| Labels in `nodeCanvasObject` | Labels in `onRenderFramePost` with priority ordering + occlusion cull (§6.1) |
| `linkDirectionalParticleSpeed 0.02` | `0.052` for a 320 ms hop (§8.2) |
| `linkDirectionalParticleWidth 4.0` | `3.5` (§8.2) |
| `nodeCanvasObject` label fill `rgba(255,230,166,0.92)` | `rgba(220,228,240,0.92)`, with a `#0b0e14` knockout at `4/k` (§6.1) |
| Non-walk dim `rgba(120,140,175,0.3)` / link `rgba(150,170,200,0.10)` | `rgba(220,228,240,0.10)` / `rgba(220,228,240,0.07)` (§7.1) |
| `d3AlphaDecay 0.06`, `d3VelocityDecay 0.35` | `0.05` / `0.55` at 400 nodes (§3) |
| default `'center'` force, no collide/radial | `d3Force('center', null)` + collide + radial + sector x/y (§9) |
| no reduced-motion handling | §10 |
