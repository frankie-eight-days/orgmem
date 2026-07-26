# orgmem — marketing site copy & section spec

**Use this text verbatim.** It is written to be dense, specific, and true. Every number here is
measured from the running system — do not round, embellish, or add adjectives. If a claim isn't in
this document, don't make it.

**Route:** `/` is this page. Scrolling ends at a CTA into `/app`. One Jac project, file-based routing.

**Voice:** short declaratives. No sentence that could describe a different product. No "seamlessly",
"powerful", "revolutionize", "unlock", "leverage". No emoji. Reads like a good X post: punchy,
information-dense, zero filler.

**Design:** light theme. Near-white background, near-black text, **one** accent colour used sparingly
(suggest a single saturated hue for graph edges and the CTA only). Big type. Brutal whitespace.
Left-aligned. One idea per screen.

**Forbidden, because they read as generated:** purple-blue gradients, gradient blobs, three-column
icon-card feature grids, centred body text, "Powered by AI" badges, stock illustration, glassmorphism,
floating 3D shapes, drop shadows on everything.

**Machine-readable requirements** (judging may be AI-assisted): semantic HTML5, correct heading
hierarchy (one `h1`, ordered `h2`s), every claim as real text never baked into an image, meta
description, OpenGraph tags, JSON-LD `SoftwareApplication`, and a plain-text `/llms.txt` summarising
the project at a stable path. No hidden text, no instructions aimed at a grader.

---

## 0 — HERO

**H1:**
Your company knows more than it wrote down.

**Sub:**
orgmem maps organizational knowledge as a graph — who knows what, where it's written, and where it
isn't. Built in Jac.

**Visual:** a live force graph, slowly breathing. Nodes labelled with real names from the corpus
(Janice, Morgan, TitanDB, CONF-ENG-001). Not decorative — this is the actual graph the app builds.

**CTA (secondary, small):** See it running ↓

---

## 1 — THE PROBLEM

**H2:** Every RAG system indexes what you wrote down.

**Body (two lines, large):**
Slack. Zendesk. Confluence. Jira. Transcripts.
Then the half that was never written down at all.

**The artifact — render as a real code block, monospace, unstyled-honest:**

```json
{ "name": "Bill", "departed": "day -579", "reason": "voluntary",
  "knowledge_domains": ["TitanDB", "legacy auth service",
                        "AWS cost structure", "Project Titan"],
  "documented_pct": 0.2 }
```

**Caption beneath, smaller:**
Bill documented one fifth of what he knew. 579 days later, TitanDB caused an incident.
Nobody left knew why.

---

## 2 — WHY SEARCH CAN'T HELP

**H2:** Retrieval can fail to find something. It cannot prove nothing is there.

**Body:**
Ask "was a postmortem ever written?" and vector search returns the nearest chunk — because top-k
similarity is never exhaustive and never returns nothing. The model reads plausible context and says
yes.

**Pull quote, large:**
A graph answers by walking a bounded space and counting zero.
Zero neighbours is a fact, not a failure.

**Visual:** split panel. Left: a query vector reaching into a cloud of chunks, grabbing the nearest
one, confidently wrong. Right: a walker traversing outward from a node, hitting the boundary, and
returning empty. Same question, two mechanisms.

---

## 3 — THE TRANSFORMATION ⭐ (the centrepiece)

**H2:** Artifacts in. Graph out.

**Body (one line):**
4,966 artifacts across six systems become 69,092 typed edges in 6.4 seconds.

**The animation — this section is the page. Staged, scroll-driven:**

1. **Rain.** Realistic mock cards drift in from the top: a Slack thread (`#engineering_backend`,
   avatars, three messages), a Zendesk ticket, a Confluence page header, a Jira ticket
   (`ENG-123`), a Zoom transcript with timestamps, a PR diff. Use real content from the corpus —
   Jax debugging Terraform tagging, CONF-ENG-001 "Project Titan Overview".
2. **Parse.** Each card is scanned; entities highlight in place — people, systems, dates lift off
   the card.
3. **Crystallise.** Cards dissolve into nodes. Edges snap into existence between them. The pile
   becomes a structure.
4. **Settle.** The force graph relaxes into a stable, readable shape. Clusters emerge.

Make it visceral and physical. This is the moment a viewer understands the product. Scroll-scrubbed
so it can be replayed, and it must still read as a static composition if motion is reduced.

**Labels appearing during the animation (small, monospace, one per stage):**
`3,303 Slack threads` · `610 emails` · `479 Confluence pages` · `304 Jira tickets` ·
`208 transcripts` · `57 pull requests`

---

## 4 — WHAT IT UNLOCKS

**H2:** Three questions no search box can answer.

Three panels, each with a small animated still. Keep prose to the exact lines below.

**Silence**
Was a postmortem ever written after that incident?
*Walk from the trigger. Count the expected responses. Zero is the answer.*

**Perspective**
Could Felix have known about this on day 32?
*Reachability from a person, bounded by time and access. No model required.*

**Expertise**
Who actually knows TitanDB?
*Ranked from demonstrated engagement. Bus factor included.*

---

## 5 — THE PROOF

**H2:** Measured, not claimed.

**Stat row (large numerals, monospace labels):**
`69,092` typed edges · `6.4s` cold build · `4,966` artifacts · `78` benchmark questions with ground truth

**Body:**
The dataset ships 27 questions where the expected follow-up never happened, near-evenly split
(15 yes / 12 no) so a constant answer scores 55%.

**Pull quote:**
Flat retrieval scores about 55% on those — and we can tell you in advance which ones it fails.
It fails the ones where the thing does not exist.

**Honest note, small, beneath:**
Built in one day on a public dataset. The structural layer is deterministic; the inferred knowledge
layer is early.

---

## 6 — HOW IT WORKS

**H2:** The retriever is a walker.

**Body:**
Artifacts are typed nodes — a Confluence page is not a Slack thread, and behaviour attaches per
type on arrival. A query is an agent moving through the graph. The path it walks is the citation.

**Code block, real Jac, monospace:**

```jac
walker Visibility {
    has actor: str;
    has as_of_day: int;
    has cone: list = [];

    can start with Person entry {
        visit [-->](?day <= self.as_of_day);
    }
    can collect with ConfluencePage entry {
        self.cone.append(here.doc_id);
        visit [-->];
    }
}
```

**Elimination list — echo the house style, four short lines:**
No database. No ORM. No vector store. No prompt strings.
Persistence is reachability from `root`. Retrieval is traversal.
The client calls walkers directly — no REST, no HTTP client, no CORS.
One language, whole stack.

---

## 7 — CTA

**H2:** Ask it something.

**Body (one line):**
Live, on the orgforge corpus — 60 simulated days inside a company that never existed.

**Button:** Open orgmem →  (routes to `/app`)

**Footer, small:**
Built at JacHacks SF 2026 · Jac 0.34 · dataset `aeriesec/orgforge` (MIT) · source on GitHub

---

## Notes for the builder

- The hero graph and the section-3 animation should use the **same renderer** as the app, fed static
  sample data. Consistency between marketing and product is itself a credibility signal.
- Prefer real corpus strings everywhere over lorem-ipsum or invented names. Janice, Morgan, Jax,
  TitanDB, CONF-ENG-001, ENG-123 are all real records.
- If a number in this document ever stops being true of the running system, change the document —
  do not ship a stale claim.
