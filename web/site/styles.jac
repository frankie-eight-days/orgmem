"""The site's stylesheet, injected at mount.

Not a `.style.css` annex. The annex pipeline in this toolchain build copies the
CSS through verbatim — `:global(...)` is not stripped, class names are not
hashed — and emits `import "./Landing.css"` for a file it never writes, which
fails the Vite build outright:

    Failed to resolve import "./Landing.css" from "compiled/web/site/Landing.js"

So the stylesheet lives here as a string and `Landing` writes it into a single
`<style id="orgmem-site-css">` element on mount. It is one real stylesheet in the
document, subject to the cascade like any other; the only thing given up is
build-time scoping, which is why every class below is prefixed and owned by this
directory.

The site is LIGHT and the product at `/app` is DARK, deliberately. That is the
ordinary shape of this pair — a warm off-white page that argues, a dark tool that
works — and the two are not meant to be reconciled. Nothing here should be
"corrected" toward the app's palette; `/app` owns its own colours inline in
`web/Shell.jac` and `web/GraphCanvas.jac` and is unaffected by this stylesheet.

`cl` is load-bearing: no JSX and no npm import in this module.
"""

cl glob:pub SITE_CSS: str = """
:root {
  --bg: #FBFAF7;
  --ink: #12100E;
  --muted: #6E675F;
  --faint: #A49C93;
  --rule: #E4DFD6;
  --rule-lit: #D5CEC2;
  --panel: #FFFEFB;
  --accent: #E5432B;

  --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
  --gutter: clamp(1.25rem, 4.5vw, 4rem);

  /* One content column, shared by every section, so the left edge of the hero
     headline and the left edge of the transformation heading are the same
     line down the whole page. */
  --col: 1160px;
}

html { scroll-behavior: smooth; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--ink);
  font-family: system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif;
  font-synthesis-weight: none;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}

::selection { background: var(--accent); color: var(--bg); }

/* `overflow-x: clip` and NOT `overflow-x: hidden`. `hidden` on either axis makes
   the element a scroll container, and a `position: sticky` descendant then
   sticks to *that* container — which never scrolls — so the transformation
   section's sticky viewport silently stopped sticking and its 420vh track
   became 420vh of blank page. `clip` clips without the scroll container. */
.site { display: block; overflow-x: clip; }

/* The shared content column. */
.shell {
  width: min(var(--col), 100%);
  margin: 0 auto;
  padding: 0 var(--gutter);
  box-sizing: border-box;
}

.graph-box { width: 100%; position: relative; overflow: hidden; }
.graph-box canvas { display: block; }

/* ---------- 0 · hero ---------- */

.hero {
  position: relative;
  min-height: 100vh;
  display: grid;
  align-items: center;
  overflow: hidden;
  border-bottom: 1px solid var(--rule);
}

/* Full height, but starting to the right of the text column rather than
   full-bleed behind it. On a dark ground a graph can sit under the copy and
   read as atmosphere; on cream the wash needed to keep text legible over it
   just bleaches the graph, so the honest arrangement here is to give it its own
   region and let the mask feather the seam. */
.hero-canvas {
  position: absolute;
  top: 0;
  bottom: 0;

  /* `fit()` scales the graph to fill whatever box it is handed, so the box's
     left edge — not a mask — is what keeps the graph clear of the headline.
     Widening the canvas leftward just drags the graph back over the text.

     That edge is DERIVED, not guessed. It used to be `left: 48%`, and 48% of
     the viewport is unrelated to where the text column actually ends, so the
     box overlapped the copy at every width measured — 57px at 1440, 48px at
     1280, 66px at 1100. Whether you SAW the collision depended on where the
     simulation happened to drop a node that run, which is exactly the kind of
     bug that behaves in development and lands a node inside a word on stage.

     So compute the real right edge of the copy from the same quantities that
     produce it — the shell's centring, its gutter, and `.hero-copy`'s 34rem —
     and start the canvas a fixed gap after it. Change any of those and this
     follows; it cannot drift out of agreement with them. The 34rem below is
     the one duplicated constant, and it is spelled the same way on purpose. */
  left: calc(
    max(0px, (100vw - var(--col)) / 2)   /* shell centring   */
    + var(--gutter)                      /* shell padding    */
    + 34rem                              /* .hero-copy width */
    + 2.5rem                             /* breathing gap    */
  );
  right: 0;
  z-index: 0;
  display: flex;
  align-items: center;
  overflow: hidden;
  pointer-events: none;
  -webkit-mask-image: linear-gradient(to right, transparent 0, #000 10%, #000 88%, transparent 100%);
  mask-image: linear-gradient(to right, transparent 0, #000 10%, #000 88%, transparent 100%);
}

/* A wash of the page ground over the left of the hero. Legibility of the
   headline then does not depend on where the simulation happens to put its
   nodes this run — which is the kind of thing that looks fine in development
   and lands a node in the middle of a word on stage. */
.hero::before {
  content: "";
  position: absolute;
  inset: 0;
  z-index: 1;
  pointer-events: none;
  /* Only as far as the text column needs. Anything wider bleaches the graph. */
  background: linear-gradient(
    100deg,
    var(--bg) 0,
    var(--bg) 30%,
    color-mix(in srgb, var(--bg) 55%, transparent) 40%,
    transparent 48%
  );
}

.hero-inner { position: relative; z-index: 2; }

/* Width in `rem`, not `ch`: `ch` resolves against the *container's* font size
   (16px), so a 34ch column is 272px wide no matter how large the headline
   inside it is — which is how a 5.5rem h1 ended up wrapping over seven lines. */
.hero-copy { max-width: 34rem; }

.wordmark {
  font-family: var(--mono);
  font-size: 0.75rem;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--accent);
  margin: 0 0 clamp(1.25rem, 3vh, 2rem);
}

.hero-h1 {
  font-size: clamp(2.25rem, 3.7vw, 3.5rem);
  line-height: 1.02;
  letter-spacing: -0.03em;
  font-weight: 560;
  margin: 0;
  text-wrap: balance;
}

.hero-sub {
  margin: clamp(1.25rem, 2.5vh, 1.75rem) 0 0;
  max-width: 44ch;
  font-size: clamp(0.9375rem, 1.05vw, 1.0625rem);
  line-height: 1.6;
  color: var(--muted);
}

.hero-cta {
  display: inline-block;
  margin-top: clamp(1.75rem, 3.5vh, 2.5rem);
  font-family: var(--mono);
  font-size: 0.8125rem;
  letter-spacing: 0.04em;
  color: var(--accent);
  text-decoration: none;
  border-bottom: 1px solid color-mix(in srgb, var(--accent) 35%, transparent);
  padding-bottom: 0.25rem;
}

.hero-cta:hover { border-bottom-color: var(--accent); }

/* ---------- 3 · the transformation ---------- */

.tr { position: relative; }

/* The scroll track. Its height IS the animation's duration: 300vh of scrolling
   maps onto p = 0..1, roughly three unhurried flicks of a trackpad. */
.tr-track { height: 300vh; position: relative; }

.tr-sticky {
  position: sticky;
  top: 0;
  height: 100vh;
  overflow: hidden;
}

/* The heading lives INSIDE the sticky viewport rather than in a section above
   it. It is on screen for the whole track, so there is no scroll position at
   which the reader is looking at an unlabelled animation — and no screen that
   is only animation, which is what produced the blank frames. */
.tr-head {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  z-index: 2;
  padding: clamp(2.5rem, 7vh, 4.5rem) 0 clamp(2.5rem, 6vh, 4rem);
  pointer-events: none;
  /* Cards fall from above the viewport and cross this band on the way down.
     The wash lets them pass *behind* the heading instead of through it. */
  background: linear-gradient(to bottom, var(--bg) 0, var(--bg) 58%, transparent 100%);
}

.tr-h2 {
  font-size: clamp(1.75rem, 2.9vw, 2.75rem);
  line-height: 1.04;
  letter-spacing: -0.03em;
  font-weight: 560;
  margin: 0;
}

.tr-lede {
  margin: 0.875rem 0 0;
  font-size: clamp(0.9375rem, 1.05vw, 1.0625rem);
  line-height: 1.55;
  color: var(--muted);
  max-width: 46ch;
}

.tr-graph {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  transform-origin: 50% 52%;
  will-change: transform, opacity;
}

.tr-graph > * { width: 100%; }

/* The card stage is inset from the top so the rain lands *below* the heading
   rather than through it, and from the bottom so it clears the counters. */
.tr-field { position: absolute; inset: 28% 0 12%; z-index: 1; }

.slot {
  position: absolute;
  width: min(20rem, 26vw);
  will-change: transform, opacity;
}

/* No drop shadow — the site's stated rule, which this card was breaking. The
   cards read as lifted anyway because they sit on `--panel` over `--bg` and
   carry a source-coloured rule along the top edge. */
.card {
  position: relative;
  background: var(--panel);
  border: 1px solid var(--rule-lit);
  border-radius: 4px;
  padding: 0.875rem 0.875rem 0.875rem;
  overflow: hidden;
}

/* The source hairline. Every one of these products marks its own surface with
   its colour somewhere; one rule is the cheapest way to say "this came from
   Slack" without reproducing a whole brand header at 40% scale. */
.card-rule {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 2px;
}

.card-chrome {
  display: flex;
  align-items: baseline;
  gap: 0.5rem;
}

.card-source {
  font-family: var(--mono);
  font-size: 0.5625rem;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  font-weight: 600;
  flex-shrink: 0;
}

.card-status {
  margin-left: auto;
  font-family: var(--mono);
  font-size: 0.5625rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--muted);
  border: 1px solid var(--rule-lit);
  border-radius: 999px;
  padding: 0.0625rem 0.375rem;
  flex-shrink: 0;
}

.card-status-jira { color: #1F5FBF; border-color: color-mix(in srgb, #1F5FBF 34%, var(--rule)); }
.card-status-zendesk { color: var(--accent); border-color: color-mix(in srgb, var(--accent) 40%, var(--rule)); }
.card-status-pr { color: #5B4B9B; border-color: color-mix(in srgb, #5B4B9B 34%, var(--rule)); }

/* Faces and timestamp share one row, the way every one of these tools puts
   the author beside the time. */
.card-sub {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0.5rem 0 0.5rem;
  padding-bottom: 0.4375rem;
  border-bottom: 1px solid var(--rule);
}

.card-faces { display: flex; flex-shrink: 0; }

.face {
  width: 1.125rem;
  height: 1.125rem;
  border-radius: 50%;
  font-family: var(--mono);
  font-size: 0.5625rem;
  font-weight: 600;
  line-height: 1.125rem;
  text-align: center;
  border: 1px solid var(--panel);
  margin-right: -0.25rem;
}

.card-sub .card-meta { margin: 0; }

.card-head {
  font-family: var(--mono);
  font-size: 0.75rem;
  font-weight: 500;
  color: var(--ink);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.card-meta {
  margin: 0.4375rem 0 0.5rem;
  font-family: var(--mono);
  font-size: 0.625rem;
  color: var(--faint);
}

.card-line {
  margin: 0 0 0.3125rem;
  font-size: 0.6875rem;
  line-height: 1.5;
  color: var(--muted);
  overflow-wrap: anywhere;
}

.card-line:last-of-type { margin-bottom: 0; }

.run { transition: color 220ms ease, background-color 220ms ease; }

/* Entities before their card is scanned: ordinary text, nothing given away. */
.run-pending { color: inherit; }

/* After the scan line passes: the token itself is marked, in place. */
.run-entity {
  color: var(--accent);
  background: color-mix(in srgb, var(--accent) 10%, transparent);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 10%, transparent);
  border-radius: 1px;
}

.card-scan {
  position: absolute;
  left: 0;
  right: 0;
  height: 1px;
  background: var(--accent);
  box-shadow: 0 0 12px 2px color-mix(in srgb, var(--accent) 40%, transparent);
  pointer-events: none;
}

.chips {
  position: absolute;
  left: 0;
  right: 0;
  top: -0.25rem;
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem;
  justify-content: center;
  pointer-events: none;
}

.chip {
  font-family: var(--mono);
  font-size: 0.625rem;
  line-height: 1;
  padding: 0.25rem 0.4375rem;
  border: 1px solid var(--accent);
  border-radius: 2px;
  background: var(--bg);
  color: var(--accent);
  white-space: nowrap;
  will-change: transform, opacity;
}

.tr-counts {
  position: absolute;
  left: 0;
  right: 0;
  bottom: clamp(1.75rem, 5vh, 3rem);
  z-index: 2;
  pointer-events: none;
}

.tr-count-list {
  margin: 0;
  padding: 0;
  list-style: none;
  display: grid;
  gap: 0.3125rem;
}

.tr-count {
  font-family: var(--mono);
  font-size: 0.75rem;
  letter-spacing: -0.01em;
  color: var(--muted);
}

.tr-count::before {
  content: "";
  display: inline-block;
  width: 0.375rem;
  height: 0.375rem;
  margin-right: 0.5rem;
  vertical-align: 0.05em;
  background: var(--accent);
}

/* ---------- prose sections ---------- */

/* Every argued section shares one column and one rhythm. `.sec` is the column
   itself rather than a wrapper around `.shell`, because these sections are
   plain prose — there is nothing full-bleed inside them that would need to
   escape the column, which is the only reason `.hero` and `.tr` need the
   separate `.shell`. */
.sec {
  width: min(var(--col), 100%);
  margin: 0 auto;
  padding: clamp(5rem, 13vh, 9rem) var(--gutter);
  box-sizing: border-box;
}

.sec-h2 {
  font-size: clamp(1.75rem, 3.1vw, 2.75rem);
  line-height: 1.08;
  letter-spacing: -0.028em;
  font-weight: 560;
  margin: 0 0 clamp(1.5rem, 3.5vh, 2.5rem);
  max-width: 24ch;
}

/* The one heading that is a full sentence and needs the room to stay on two
   lines rather than four. */
.sec-h2-wide { max-width: 34ch; }

.body {
  font-size: clamp(1rem, 1.15vw, 1.125rem);
  line-height: 1.62;
  color: var(--muted);
  max-width: 62ch;
  margin: 0 0 1.5rem;
}

.caption {
  font-size: 0.9375rem;
  line-height: 1.55;
  color: var(--muted);
  max-width: 56ch;
  margin: 1.25rem 0 0;
}

.note {
  font-size: 0.875rem;
  line-height: 1.6;
  color: var(--faint);
  max-width: 62ch;
  margin: 2.5rem 0 0;
  padding-top: 1.25rem;
  border-top: 1px solid var(--rule);
}

/* The two display lines in the problem statement. The second is the turn, so
   it is the same size and a lighter ink rather than smaller — shrinking it
   would read as a footnote when it is the actual point. */
.big-line {
  font-size: clamp(1.375rem, 2.4vw, 2rem);
  line-height: 1.22;
  letter-spacing: -0.02em;
  font-weight: 400;
  margin: 0 0 0.375rem;
}

.big-line-muted { color: var(--faint); margin-bottom: 0; }

/* ---------- code ---------- */

/* `overflow-x: auto` on the block, so a long line scrolls the block and never
   the page. */
.code {
  font-family: var(--mono);
  font-size: 0.8125rem;
  line-height: 1.65;
  background: var(--panel);
  border: 1px solid var(--rule);
  border-radius: 4px;
  padding: 1.25rem 1.375rem;
  margin: 2rem 0 0;
  overflow-x: auto;
  max-width: 100%;
  box-sizing: border-box;
  color: var(--ink);
  tab-size: 4;
}

.code code { font: inherit; color: inherit; white-space: pre; }
.code-json { color: var(--muted); }
.code-jac { border-left: 2px solid var(--accent); }

/* ---------- pull quote ---------- */

.pull {
  margin: 2.5rem 0 0;
  padding-left: clamp(1rem, 2vw, 1.75rem);
  border-left: 2px solid var(--accent);
  max-width: 54ch;
}

.pull p {
  font-size: clamp(1.125rem, 1.7vw, 1.5rem);
  line-height: 1.38;
  letter-spacing: -0.018em;
  margin: 0 0 0.5rem;
}

.pull p:last-child { margin-bottom: 0; color: var(--muted); }

/* ---------- 2 · the split panel ---------- */

.split {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: clamp(1.25rem, 3vw, 2.5rem);
  margin: clamp(2.5rem, 6vh, 4rem) 0 0;
}

.panel {
  margin: 0;
  background: var(--panel);
  border: 1px solid var(--rule);
  border-radius: 5px;
  padding: 1.25rem;
}

.panel-svg { display: block; width: 100%; height: auto; }

.panel-cap {
  font-family: var(--mono);
  font-size: 0.75rem;
  letter-spacing: -0.01em;
  color: var(--muted);
  margin-top: 1rem;
  padding-top: 0.875rem;
  border-top: 1px solid var(--rule);
}

/* Left panel — similarity. Everything is grey except the thing it grabbed,
   because "it returned something" is the whole claim. */
.chunks circle { fill: var(--rule-lit); }
.query { fill: var(--muted); }
.reach { stroke: var(--faint); stroke-width: 1.25; stroke-dasharray: 3 3; fill: none; }
.hit { fill: none; stroke: var(--accent); stroke-width: 1.5; }

/* Right panel — traversal. The boundary is the argument: it is drawn, so the
   space being searched is visibly finite. */
.bound { fill: none; stroke: var(--rule-lit); stroke-width: 1; stroke-dasharray: 4 4; }
.edges path { stroke: var(--rule-lit); stroke-width: 1; fill: none; }
.graph-nodes circle { fill: var(--muted); }
.origin { fill: var(--accent); }

.svg-label {
  font-family: var(--mono);
  font-size: 10px;
  fill: var(--muted);
}

.svg-label-accent { fill: var(--accent); }

.zero {
  font-family: var(--mono);
  font-size: 30px;
  font-weight: 600;
  fill: var(--accent);
}

/* ---------- 4 · the three unlocks ---------- */

.unlock-row {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: clamp(1.25rem, 3vw, 2.5rem);
}

.unlock { margin: 0; }

.unlock-still {
  background: var(--panel);
  border: 1px solid var(--rule);
  border-radius: 5px;
  padding: 0.75rem;
  margin-bottom: 1.25rem;
}

.still { display: block; width: 100%; height: auto; }

.unlock-h3 {
  font-size: 1.0625rem;
  font-weight: 560;
  letter-spacing: -0.015em;
  margin: 0 0 0.5rem;
}

.unlock-q {
  font-size: 0.9375rem;
  line-height: 1.45;
  margin: 0 0 0.75rem;
}

.unlock-m {
  font-family: var(--mono);
  font-size: 0.75rem;
  line-height: 1.5;
  color: var(--muted);
  margin: 0;
}

/* The three stills. Shared vocabulary: accent = the thing being asked about,
   grey = structure, dashed = a boundary. */
.s-origin { fill: var(--accent); }
.s-edge { stroke: var(--rule-lit); stroke-width: 1.25; fill: none; }
.s-slot { fill: none; stroke: var(--rule-lit); stroke-width: 1.25; stroke-dasharray: 3 3; }
.s-zero { font-family: var(--mono); font-size: 26px; font-weight: 600; fill: var(--accent); }
.s-cone { fill: color-mix(in srgb, var(--accent) 8%, transparent); stroke: none; }
.s-cut { stroke: var(--accent); stroke-width: 1.25; stroke-dasharray: 3 3; }
.s-in { fill: var(--muted); }
.s-out { fill: var(--rule-lit); }
.s-tick { font-family: var(--mono); font-size: 10px; fill: var(--accent); }
.s-bar { fill: var(--rule-lit); }
.s-bar-1 { fill: var(--accent); }
.s-name { font-family: var(--mono); font-size: 10px; fill: var(--muted); }

/* ---------- 5 · the numbers ---------- */

.stats {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: clamp(1rem, 2.5vw, 2rem);
  margin: 0 0 clamp(2.5rem, 6vh, 3.5rem);
  padding-bottom: clamp(2rem, 5vh, 3rem);
  border-bottom: 1px solid var(--rule);
}

.stat { margin: 0; }

.stat-n {
  font-size: clamp(1.75rem, 3.2vw, 2.75rem);
  line-height: 1;
  letter-spacing: -0.035em;
  font-weight: 560;
  font-variant-numeric: tabular-nums;
}

.stat-l {
  font-family: var(--mono);
  font-size: 0.75rem;
  line-height: 1.45;
  color: var(--muted);
  margin: 0.625rem 0 0;
}

/* ---------- 6 · mechanism ---------- */

.elim {
  list-style: none;
  margin: 2.5rem 0 0;
  padding: 0;
  display: grid;
  gap: 0.875rem;
  max-width: 54ch;
}

.elim-line {
  font-size: 0.9375rem;
  line-height: 1.5;
  color: var(--muted);
  padding-left: 1.5rem;
  position: relative;
}

/* An em-rule rather than a bullet: these are subtractions, and a list of
   things that are *not* there should not be typeset as an inventory. */
.elim-line::before {
  content: "";
  position: absolute;
  left: 0;
  top: 0.7em;
  width: 0.75rem;
  height: 1px;
  background: var(--accent);
}

.elim-line code,
.foot-code {
  font-family: var(--mono);
  font-size: 0.9em;
  color: var(--ink);
}

/* ---------- 7 · the walker, running ---------- */

/* Code and stage side by side, code slightly wider — it is the thing being
   read; the graph is the thing being glanced at to confirm what was read. */
.wd {
  display: grid;
  grid-template-columns: minmax(0, 1.15fr) minmax(0, 1fr);
  gap: clamp(1.25rem, 3vw, 2.25rem);
  align-items: start;
  margin: clamp(2rem, 5vh, 3rem) 0 0;
}

.wd-code {
  background: var(--panel);
  border: 1px solid var(--rule);
  border-left: 2px solid var(--accent);
  border-radius: 5px;
  padding: 1.125rem 0;
  overflow-x: auto;
}

.wd-pre {
  margin: 0;
  font-family: var(--mono);
  font-size: 0.75rem;
  line-height: 1.7;
  tab-size: 4;
}

.wd-pre code { font: inherit; white-space: pre; }

/* Each line is a block so the active-line wash spans the full width rather
   than only the glyphs. */
.wd-line {
  display: block;
  padding: 0 1.25rem;
  border-left: 2px solid transparent;
  margin-left: -2px;
  transition: background-color 200ms ease, border-color 200ms ease;
}

.wd-line-on {
  background: color-mix(in srgb, var(--accent) 9%, transparent);
  border-left-color: var(--accent);
}

/* Five token classes, which is all Jac needs here. Edge references get their
   own colour because `->:Produced:->` is the construct this section exists to
   explain — colouring it like punctuation would bury the point. */
.tok-k { color: #9B2C7F; }
.tok-t { color: #1F5FBF; }
.tok-s { color: #2F7A4E; }
.tok-c { color: var(--faint); font-style: italic; }
.tok-e { color: var(--accent); font-weight: 600; }

.wd-stage {
  background: var(--panel);
  border: 1px solid var(--rule);
  border-radius: 5px;
  padding: 1rem 1rem 1.125rem;
}

.wd-svg { display: block; width: 100%; height: auto; }

.wd-bound {
  fill: none;
  stroke: var(--rule-lit);
  stroke-width: 1;
  stroke-dasharray: 5 4;
}

.wd-bound-label {
  font-family: var(--mono);
  font-size: 8.5px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  fill: var(--faint);
}

.wd-edge {
  stroke: var(--rule-lit);
  stroke-width: 1.25;
  transition: stroke 260ms ease, stroke-width 260ms ease;
}

.wd-edge-on { stroke: var(--muted); }
.wd-edge-live { stroke: var(--accent); stroke-width: 2; }

.wd-node circle {
  fill: var(--bg);
  stroke: var(--rule-lit);
  stroke-width: 1.5;
  transition: fill 260ms ease, stroke 260ms ease;
}

.wd-node-on circle { fill: var(--muted); stroke: var(--muted); }
.wd-node-trigger circle { stroke: var(--accent); }
.wd-node-trigger.wd-node-on circle { fill: var(--accent); stroke: var(--accent); }

.wd-label,
.wd-sub {
  font-family: var(--mono);
  text-anchor: middle;
  transition: fill 260ms ease;
}

.wd-label { font-size: 10px; fill: var(--ink); }
.wd-sub { font-size: 8.5px; fill: var(--faint); }
.wd-node-on .wd-sub { fill: var(--muted); }

.wd-read {
  margin-top: 0.75rem;
  padding-top: 0.875rem;
  border-top: 1px solid var(--rule);
}

/* Fixed height so the counters do not jump as the note text changes length. */
.wd-note {
  font-family: var(--mono);
  font-size: 0.75rem;
  color: var(--accent);
  margin: 0 0 0.75rem;
  min-height: 2.4em;
}

.wd-counts { display: flex; gap: 1.75rem; margin: 0; }
.wd-count dt {
  font-family: var(--mono);
  font-size: 0.625rem;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--faint);
}

.wd-count dd {
  margin: 0.25rem 0 0;
  font-size: 1.375rem;
  font-weight: 560;
  font-variant-numeric: tabular-nums;
  line-height: 1;
}

.wd-count-zero dd { color: var(--accent); }

/* ---------- 7 · the way in ---------- */

.sec-cta { text-align: center; }
.sec-cta .sec-h2 { max-width: none; margin-left: auto; margin-right: auto; }
.sec-cta .body { margin-left: auto; margin-right: auto; }

.cta-button {
  display: inline-block;
  margin-top: 1rem;
  padding: 0.9375rem 2rem;
  background: var(--accent);
  color: var(--bg);
  text-decoration: none;
  border-radius: 999px;
  font-size: 1rem;
  font-weight: 500;
  letter-spacing: -0.01em;
  transition: background 140ms ease;
}

.cta-button:hover { background: color-mix(in srgb, var(--accent) 84%, var(--ink)); }

.foot {
  margin-top: clamp(4rem, 10vh, 6rem);
  padding-top: 1.5rem;
  border-top: 1px solid var(--rule);
}

.foot p {
  font-family: var(--mono);
  font-size: 0.75rem;
  line-height: 1.6;
  color: var(--faint);
  margin: 0;
}

/* Links carry an underline rather than a colour change alone — colour-only
   links fail contrast checks and read as decoration on a page this quiet. */
.foot-link {
  color: var(--muted);
  text-decoration: underline;
  text-underline-offset: 0.2em;
  text-decoration-color: var(--rule-lit);
}

.foot-link:hover { color: var(--accent); text-decoration-color: var(--accent); }

.inline-link {
  color: inherit;
  text-decoration: underline;
  text-underline-offset: 0.15em;
  text-decoration-color: var(--accent);
  text-decoration-thickness: 1.5px;
}

.inline-link:hover { color: var(--accent); }

/* Source links under the dataset introduction. Set as a quiet pair rather than
   inline in the prose so a reader can find them without the paragraph turning
   into a link farm. */
.src-row {
  display: flex;
  flex-wrap: wrap;
  gap: 1.5rem;
  margin: 1.25rem 0 0;
}

.src-link {
  font-family: var(--mono);
  font-size: 0.75rem;
  color: var(--muted);
  text-decoration: underline;
  text-underline-offset: 0.25em;
  text-decoration-color: var(--rule-lit);
}

.src-link:hover { color: var(--accent); text-decoration-color: var(--accent); }

/* ---------- 2 · written vs happened ---------- */

/* The same moment, twice. Equal columns and no connector between them: an
   arrow would imply the right column is derived from the left, when the claim
   is that they are two readings of one event and your stack only keeps one. */
.vs {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: clamp(1.25rem, 3vw, 2.5rem);
  align-items: start;
  margin: clamp(2rem, 5vh, 3rem) 0 0;
}

.vs-head {
  font-family: var(--mono);
  font-size: 0.6875rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--muted);
  margin: 0 0 1rem;
}

.vs-head-accent { color: var(--accent); }

/* The Slack card here is shown at reading size, not at the 26vw the
   transformation stage uses, so it needs its own width and line height. */
.vs .card { width: 100%; box-sizing: border-box; }
.vs-msg { margin: 0; }

.vs-line {
  font-size: 0.8125rem;
  line-height: 1.5;
  color: var(--ink);
  margin: 0 0 0.125rem;
}

.vs-foot {
  font-size: 0.8125rem;
  line-height: 1.5;
  color: var(--muted);
  margin: 1rem 0 0;
}

.vs-foot-accent { color: var(--ink); }

.ev-stack { display: grid; gap: 0.5rem; }

.ev {
  background: var(--panel);
  border: 1px solid var(--rule);
  border-radius: 4px;
  padding: 0.75rem 0.875rem;
}

.ev-hot { border-color: color-mix(in srgb, var(--accent) 34%, var(--rule)); }

.ev-type {
  font-family: var(--mono);
  font-size: 0.6875rem;
  color: var(--accent);
  margin: 0 0 0.5rem;
}

.ev-rows { list-style: none; margin: 0; padding: 0; }

.ev-row {
  display: flex;
  gap: 0.75rem;
  align-items: baseline;
  font-family: var(--mono);
  font-size: 0.6875rem;
  line-height: 1.6;
}

.ev-k { color: var(--faint); flex: none; min-width: 8.5rem; }
.ev-v { color: var(--ink); }

/* Scale, after the concrete example rather than instead of it. */
.scale {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: clamp(1.25rem, 3vw, 2.5rem);
  margin: clamp(2rem, 4vh, 2.5rem) 0 0;
  padding-top: clamp(1.5rem, 3vh, 2rem);
  border-top: 1px solid var(--rule);
}

.scale-item { margin: 0; display: flex; gap: 0.875rem; align-items: baseline; }

.scale-n {
  font-size: clamp(1.5rem, 2.8vw, 2.125rem);
  line-height: 1;
  letter-spacing: -0.035em;
  font-weight: 560;
  font-variant-numeric: tabular-nums;
  flex: none;
}

.scale-item-accent .scale-n { color: var(--accent); }

.scale-l { font-size: 0.875rem; line-height: 1.45; color: var(--muted); }

/* ---------- 1 · the ledger (retired with the first draft of section 2) ---------- */

/* Two columns, equal weight, no arrow or "vs" between them. The comparison is
   doing the work; decorating it would suggest the left column is wrong, and
   the argument is not that indexing artifacts is wrong — it is that it is half
   the picture. */
.ledger {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: clamp(1rem, 2.5vw, 2rem);
  margin: clamp(2rem, 5vh, 3rem) 0 0;
}

.ledger-col {
  background: var(--panel);
  border: 1px solid var(--rule);
  border-radius: 5px;
  padding: clamp(1.25rem, 2.5vw, 1.875rem);
}

/* The right column is the one with no tooling. Marked with the accent rather
   than a darker ground: the site is light and a dark panel here would read as
   "this half is bad" instead of "this half is unaddressed". */
.ledger-col-dark { border-color: color-mix(in srgb, var(--accent) 34%, var(--rule)); }

.ledger-head {
  font-family: var(--mono);
  font-size: 0.6875rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--muted);
  margin: 0 0 1rem;
}

.ledger-col-dark .ledger-head { color: var(--accent); }

.ledger-total {
  font-size: clamp(2rem, 4vw, 3rem);
  line-height: 1;
  letter-spacing: -0.04em;
  font-weight: 560;
  font-variant-numeric: tabular-nums;
  margin: 0;
}

.ledger-sub {
  font-size: 0.8125rem;
  color: var(--muted);
  margin: 0.5rem 0 1.5rem;
}

.ledger-rows { list-style: none; margin: 0; padding: 0; }

.ledger-row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  gap: 1rem;
  padding: 0.5rem 0;
  border-top: 1px solid var(--rule);
}

.ledger-k { font-size: 0.875rem; color: var(--muted); }

.ledger-v {
  font-family: var(--mono);
  font-size: 0.875rem;
  font-variant-numeric: tabular-nums;
  color: var(--ink);
  flex: none;
}

.ledger-foot {
  font-family: var(--mono);
  font-size: 0.6875rem;
  letter-spacing: 0.02em;
  color: var(--faint);
  margin: 1.25rem 0 0;
  padding-top: 0.875rem;
  border-top: 1px solid var(--rule);
}

.ledger-foot-accent { color: var(--accent); }

/* ---------- 3b · the schema ---------- */

.schema-fig { margin: clamp(2rem, 5vh, 3rem) 0 0; }
.schema-svg { display: block; width: 100%; height: auto; }

.sch-edges path { stroke: var(--rule-lit); stroke-width: 1.25; fill: none; }

/* The only edge on the diagram describing an absence. */
.sch-edge-absent {
  stroke: var(--accent);
  stroke-width: 1.25;
  stroke-dasharray: 5 4;
  fill: none;
}

.sch-labels text {
  font-family: var(--mono);
  font-size: 11px;
  fill: var(--muted);
  text-anchor: middle;
}

.sch-label-absent { fill: var(--accent) !important; }

.sch-node rect {
  fill: var(--panel);
  stroke: var(--rule-lit);
  stroke-width: 1;
}

.sch-node text {
  font-family: var(--mono);
  font-size: 12px;
  fill: var(--ink);
  text-anchor: middle;
}

/* The instance line under each type name — the concrete thing from the
   sections above, set quieter than the type it is an instance of. */
.sch-inst { font-size: 10px !important; fill: var(--muted) !important; }
.sch-label-sub { font-size: 9.5px !important; opacity: 0.85; }

/* The stacked outlines behind the Artifact box — eight subtypes, one shape. */
.sch-stack { fill: var(--panel); stroke: var(--rule); opacity: 0.75; }

.sch-node-person rect { stroke: var(--muted); }
.sch-node-domain rect { stroke: color-mix(in srgb, var(--accent) 45%, var(--rule-lit)); }

.schema-cap {
  font-size: 0.8125rem;
  line-height: 1.55;
  color: var(--muted);
  margin-top: 1.25rem;
  max-width: 62ch;
}

.schema-cap-accent { font-family: var(--mono); color: var(--accent); }

.schema-lists {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: clamp(1.25rem, 3vw, 2.5rem);
  margin: clamp(2rem, 5vh, 3rem) 0 0;
}

.schema-h3 {
  font-family: var(--mono);
  font-size: 0.6875rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--muted);
  font-weight: 400;
  margin: 0 0 0.875rem;
}

.schema-ul {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 0.375rem;
}

.schema-li {
  font-family: var(--mono);
  font-size: 0.75rem;
  color: var(--muted);
  background: var(--panel);
  border: 1px solid var(--rule);
  border-radius: 3px;
  padding: 0.25rem 0.5rem;
}

/* ---------- 4 · the dataset and its timeline ---------- */

.sec-h3 {
  font-size: clamp(1.125rem, 1.9vw, 1.5rem);
  line-height: 1.2;
  letter-spacing: -0.02em;
  font-weight: 560;
  margin: clamp(3rem, 7vh, 4.5rem) 0 1.5rem;
}

/* The artifact inventory. A wrapping row of number-over-label pairs rather
   than a table: it is scanned, not read, and a table would invite comparison
   between rows that carries no meaning. */
.inv {
  list-style: none;
  margin: clamp(1.75rem, 4vh, 2.5rem) 0 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: clamp(1.25rem, 3vw, 2.75rem) clamp(1.5rem, 3.5vw, 3rem);
}

.inv-item { display: flex; flex-direction: column; gap: 0.3125rem; }

.inv-n {
  font-size: clamp(1.125rem, 1.8vw, 1.5rem);
  line-height: 1;
  letter-spacing: -0.03em;
  font-weight: 560;
  font-variant-numeric: tabular-nums;
}

.inv-k {
  font-family: var(--mono);
  font-size: 0.6875rem;
  color: var(--muted);
}

.inv-total {
  font-family: var(--mono);
  font-size: 0.75rem;
  color: var(--faint);
  margin: 1.5rem 0 0;
  padding-top: 1rem;
  border-top: 1px solid var(--rule);
}

.tl-fig { margin: clamp(2rem, 5vh, 3rem) 0 0; }
.tl-svg { display: block; width: 100%; height: auto; overflow: visible; }

.tl-axis { stroke: var(--rule-lit); stroke-width: 1; }
.tl-tick { stroke: var(--rule-lit); stroke-width: 1; }

/* Axis labels and lane headings are scaffolding — they should be legible and
   then disappear. The first pass had them at the same weight as the data,
   which is what made the chart read as noisy: six shades of grey all saying
   "read me". Now there are three levels and only one of them is loud. */
.tl-axis-label,
.tl-lane {
  font-family: var(--mono);
  font-size: 10px;
  fill: color-mix(in srgb, var(--faint) 62%, transparent);
  text-anchor: middle;
}

.tl-lane { text-anchor: start; letter-spacing: 0.1em; text-transform: uppercase; }

/* The day-12 marker: a band rather than a line, so the eye reads an interval
   ("around here") and not an instant, which is the honest visual claim. */
.tl-window { fill: color-mix(in srgb, var(--accent) 9%, transparent); }

.tl-inc line { stroke: var(--rule-lit); stroke-width: 1.25; }
.tl-inc circle { fill: var(--muted); }
.tl-inc-hot line { stroke: var(--accent); stroke-width: 1.5; }
.tl-inc-hot circle { fill: var(--accent); }

.tl-p line { stroke: var(--rule-lit); stroke-width: 1.25; }
.tl-p text {
  font-family: var(--mono);
  font-size: 11px;
  fill: var(--ink);
  text-anchor: middle;
}

/* A departure and an arrival are not equally interesting on this chart. The
   name of someone who left is set in ink and the "25% documented" beside it
   carries the accent; an arrival stays grey. */
.tl-p-leave text { font-weight: 600; }
.tl-p-note { font-size: 9px !important; fill: var(--faint) !important; }
.tl-p-leave .tl-p-note { fill: var(--accent) !important; }
.tl-p-join text { fill: var(--muted); }

.tl-p-join circle { fill: none; stroke: var(--muted); stroke-width: 1.5; }
.tl-p-leave circle { fill: var(--accent); }
.tl-p-leave line { stroke: var(--accent); }

.tl-call {
  font-family: var(--mono);
  font-size: 11px;
  fill: var(--accent);
  text-anchor: start;
}

.tl-call-sub { font-size: 10px !important; fill: var(--muted) !important; }

.tl-cap {
  font-family: var(--mono);
  font-size: 0.6875rem;
  line-height: 1.6;
  color: var(--faint);
  margin-top: 1.5rem;
  max-width: 72ch;
}

.tl-facts {
  display: grid;
  gap: 0.75rem;
  margin: clamp(2rem, 4vh, 2.5rem) 0 0;
  padding-left: clamp(1rem, 2vw, 1.75rem);
  border-left: 2px solid var(--accent);
}

.tl-fact { display: flex; gap: 1rem; align-items: baseline; margin: 0; }

.tl-fact-n {
  font-family: var(--mono);
  font-size: 0.8125rem;
  color: var(--accent);
  flex: none;
  width: 4rem;
}

.tl-fact-l { font-size: 0.9375rem; line-height: 1.5; }

.note-tight { margin-top: 1.5rem; }

/* ---------- the observability questions ---------- */

.q-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: clamp(1rem, 2vw, 1.5rem);
}

.q-item {
  position: relative;
  background: var(--panel);
  border: 1px solid var(--rule);
  border-radius: 5px;
  padding: 1.375rem 1.5rem 2.75rem;
}

/* The traversal diagram for each question, sitting above it like a chart's
   thumbnail. Sized so all four cards align regardless of question length. */
.q-icon {
  height: 3.5rem;
  margin-bottom: 1rem;
  display: flex;
  align-items: center;
}

.q-svg { height: 100%; width: auto; overflow: visible; }
.s-zero-sm { font-family: var(--mono); font-size: 20px; font-weight: 600; fill: var(--accent); }

.q-q {
  font-size: 1.0625rem;
  line-height: 1.35;
  letter-spacing: -0.015em;
  margin: 0 0 0.75rem;
}

.q-m {
  font-family: var(--mono);
  font-size: 0.75rem;
  line-height: 1.55;
  color: var(--muted);
  margin: 0;
}

.q-tag {
  position: absolute;
  left: 1.5rem;
  bottom: 1.25rem;
  font-family: var(--mono);
  font-size: 0.625rem;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--accent);
}

.q-item-silence { border-color: color-mix(in srgb, var(--accent) 34%, var(--rule)); }

.stat-n-accent { color: var(--accent); }

/* ---------- real ground-truth questions ---------- */

.gt-list {
  list-style: none;
  margin: clamp(2rem, 4vh, 2.5rem) 0 0;
  padding: 0;
  display: grid;
  gap: 0.625rem;
}

.gt {
  background: var(--panel);
  border: 1px solid var(--rule);
  border-left: 2px solid color-mix(in srgb, var(--accent) 55%, var(--rule));
  border-radius: 4px;
  padding: 1rem 1.125rem;
}

/* The "no" answers get the accent edge — those are the ones flat retrieval
   gets wrong, and the ones this project exists to answer. */
.gt-no { border-left-color: var(--accent); }

.gt-q { font-size: 0.9375rem; line-height: 1.5; margin: 0 0 0.625rem; }

.gt-a { display: flex; align-items: baseline; gap: 0.625rem; margin: 0; flex-wrap: wrap; }

.gt-badge {
  font-family: var(--mono);
  font-size: 0.5625rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--faint);
}

.gt-val {
  font-family: var(--mono);
  font-size: 0.8125rem;
  font-weight: 600;
  color: var(--muted);
}

.gt-no .gt-val { color: var(--accent); }

.gt-why { font-family: var(--mono); font-size: 0.6875rem; color: var(--faint); }

/* ---------- responsive ---------- */

@media (max-width: 900px) {
  .hero { padding: clamp(4rem, 12vh, 7rem) 0; }

  /* Below 900px there is no room for a column of text beside a graph, so the
     arrangement changes rather than compresses: the canvas goes full-bleed and
     the wash turns vertical, putting the copy on top of the graph instead of
     next to it. The derived left edge above would otherwise push the canvas
     off-screen entirely at these widths. */
  .hero-canvas { left: 0; -webkit-mask-image: none; mask-image: none; }
  .hero::before {
    background: linear-gradient(to bottom, var(--bg) 0, var(--bg) 52%, transparent 88%);
  }
  .slot { width: min(15rem, 46vw); }
  .card-line { font-size: 0.625rem; }
  .tr-count { font-size: 0.6875rem; }
  .tr-field { inset: 36% 0 26%; }

  /* The argued sections collapse to one column. The stats keep two rather than
     one, because four single-file numbers read as a list of trivia where a 2×2
     block still reads as a result. */
  .split { grid-template-columns: minmax(0, 1fr); }
  .unlock-row { grid-template-columns: minmax(0, 1fr); gap: 2.5rem; }
  .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 2rem 1.5rem; }
  .ledger { grid-template-columns: minmax(0, 1fr); }
  .schema-lists { grid-template-columns: minmax(0, 1fr); }
  .q-list { grid-template-columns: minmax(0, 1fr); }
  .vs { grid-template-columns: minmax(0, 1fr); gap: 2.5rem; }
  .wd { grid-template-columns: minmax(0, 1fr); gap: 1.5rem; }
  .scale { grid-template-columns: minmax(0, 1fr); gap: 1.25rem; }
  .ev-k { min-width: 7rem; }

  /* The timeline is the one element that cannot usefully reflow — sixty days
     compressed to a phone width puts four labels on top of each other. It
     scrolls inside its own figure instead, at a width where the labels still
     resolve. The figure scrolls; the page never does. */
  .tl-fig { overflow-x: auto; }
  .tl-svg { min-width: 46rem; }
}

/* ---------- reduced motion ---------- */

/* The track collapses to a single screen and the composition is drawn at its
   terminal state — cards landed, entities lifted, graph present. Nothing is
   hidden, nothing moves. */
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  .tr-track { height: 100vh; }
  .tr-sticky { position: relative; }
  .run { transition: none; }
}
""";
