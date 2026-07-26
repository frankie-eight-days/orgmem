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
     Widening the canvas leftward just drags the graph back over the text. */
  left: 48%;
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

.card {
  position: relative;
  background: var(--panel);
  border: 1px solid var(--rule-lit);
  border-radius: 4px;
  padding: 0.75rem 0.875rem 0.875rem;
  box-shadow: 0 6px 20px rgba(18, 16, 14, 0.07), 0 1px 0 rgba(18, 16, 14, 0.04);
  overflow: hidden;
}

.card-chrome {
  display: flex;
  align-items: baseline;
  gap: 0.5rem;
  padding-bottom: 0.4375rem;
  border-bottom: 1px solid var(--rule);
}

.card-kind {
  font-family: var(--mono);
  font-size: 0.5625rem;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--faint);
  border: 1px solid var(--rule-lit);
  border-radius: 2px;
  padding: 0.125rem 0.3125rem;
  flex-shrink: 0;
}

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

/* ---------- responsive ---------- */

@media (max-width: 900px) {
  .hero { padding: clamp(4rem, 12vh, 7rem) 0; }
  .hero::before {
    background: linear-gradient(to bottom, var(--bg) 0, var(--bg) 52%, transparent 88%);
  }
  .slot { width: min(15rem, 46vw); }
  .card-line { font-size: 0.625rem; }
  .tr-count { font-size: 0.6875rem; }
  .tr-field { inset: 36% 0 26%; }
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
