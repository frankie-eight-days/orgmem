# Node cards — the contract

Click a node on the graph canvas, a window opens showing **the actual artifact**, rendered in the
chrome it came from. A Slack thread looks like Slack. An email looks like an email. A Confluence page
looks like a wiki page. This is not decoration: it is the answer to "is this graph real?" — a judge
clicks a dot and reads a conversation between four named engineers about Terraform tagging.

Branch: `cards`. Everything here is **new files**. The only edit to existing code is the wire-up in
§6, applied last.

---

## 1 — The payload

One server call: `node_card(gid)` in `api.jac`. Returns exactly this shape. Every field is always
present; unknown values are `""`, `0`, `[]` or `None`, never absent.

```json
{
  "gid":       "slack_engineering_backend_2026-01-01T11:43:00",
  "kind":      "SlackThread",
  "title":     "#engineering_backend",
  "body":      "Jax: stuck on enforcing aws cost-tagging...\nLiam: Can you confirm...",
  "day":       1,
  "dept":      "Engineering_Backend",
  "subsystem": "slack",

  "authors": ["Jax"],
  "domains": ["TitanDB", "terraform"],
  "refs":    [{"gid": "CONF-ENG-001", "kind": "ConfluencePage", "title": "Project Titan Overview"}],
  "event":   {"gid": "EVT-1-sprint_planned-49", "event_type": "sprint_planned", "day": 1},

  "person": null,
  "domain": null,
  "event_detail": null,
  "dept_detail": null
}
```

`kind` is one of:

```
SlackThread  Email  ConfluencePage  JiraTicket  ZoomTranscript
PullRequest  SFOpportunity  ZDTicket
Person  Domain  Event  Department
```

For the four **entity** kinds the artifact fields are empty and the matching detail block is filled:

```json
"person": {
  "name": "Bill", "dept": "Engineering_Backend", "role": "Staff Engineer",
  "joined_day": -1200, "departed_day": -579, "documented_pct": 0.2,
  "authored_count": 41,
  "top_domains": [{"name": "TitanDB", "count": 18}, {"name": "legacy auth", "count": 9}]
}

"domain": {
  "name": "TitanDB", "aliases": ["TiDB"], "is_genesis_gap": true,
  "artifact_count": 214, "doc_status": "DEBUGGED_ONLY", "bus_factor": 1,
  "people": [{"name": "Janice", "count": 8, "departed": false}],
  "departed_with": [{"name": "Bill", "documented_pct": 0.2}]
}

"event_detail": {
  "event_id": "EVT-38-knowledge_gap_detected-1453", "event_type": "knowledge_gap_detected",
  "day": 38, "is_incident": false, "unfulfilled": ["confluence_created"],
  "involves": ["Janice", "Morgan"],
  "produced": [{"gid": "...", "kind": "SlackThread", "title": "#engineering_backend"}]
}

"dept_detail": {
  "name": "Engineering_Backend", "member_count": 9,
  "members": ["Jax", "Morgan", "Yusuf"], "artifact_count": 1180
}
```

`refs` is capped at 8, `domains` at 6, `people`/`top_domains`/`members` at 8. Cards must still cope
with an empty list — most artifacts reference nothing.

---

## 2 — Body formats, measured from the corpus

**Do not invent a parser for a format you have not looked at.** Each of these was read out of
`data/corpus.parquet`. Sample before you write; `python3 -c "import pandas..."` on the parquet is
one command and it will save you an hour.

### SlackThread — `title` is `#channel`
Newline-separated. Each line is `Speaker: message`. The speaker is a single capitalised first name
followed by `: `. Message text may itself contain colons, so split on the **first** `": "` only, and
only when the prefix is short (≤ 24 chars) and has no spaces after trimming — otherwise the line is a
continuation of the previous message.

```
Jax: stuck on enforcing aws cost-tagging via terraform, module seems to ignore...
Liam: Can you confirm whether the terraform tagging module runs before the...
Yusuf: The module executes during the infra stage, so resources created by helm...
```

### ZoomTranscript — `title` is `Zoom: <topic> (<date>)`
Markdown preamble, then `---`, then turns.

```
# Zoom Meeting Transcript
**Date:** 2026-01-01
**Topic:** aws tagging strategy design
**Attendees:** Jax, Morgan, Yusuf, Tasha

---

**[12:12:00] Jax:** hey everyone, goal is to lock down an aws tagging strategy...
**[12:16:00] Morgan:** we can start by extending the existing tagging module...
```

Attendees come from the `**Attendees:**` line. Turns match `**[HH:MM:SS] Name:** text`. Some turns
wrap onto following lines — append them to the current turn.

### Email — `title` is the subject
Plain prose. Opens `Hi <name>,`, closes with a signature block (`Best regards,` / name / job title /
company). `authors` holds sender and recipient — **sender first**, e.g. `["Nora", "Jax"]`. The
signature block is worth rendering distinctly; it carries the external company name.

### ConfluencePage — `title` is the page title
Real markdown. Must handle: `#`/`##`/`###` headings, `**bold**`, `- ` bullets, and **GFM tables**
(`| a | b |` with a `|---|---|` separator row). Tables appear in the most-cited pages, so a card that
drops them looks broken.

```
# Project Titan Overview
**ID:** CONF-ENG-001
**Author:** Yusuf

## Core Architecture
| Layer | Technology | Role |
|-------|------------|------|
| **Data Store** | TitanDB (PostgreSQL) | Persistent relational store. |
```

Bodies run to several thousand characters — the card scrolls.

### JiraTicket · SFOpportunity · ZDTicket — `key: value` bodies
Thin and structured. These render as **field cards**, not prose.

```
account_name: National Olympic Training Center
stage: Proposal/Price Quote
opportunity_id: OPP-1001
```

`JiraTicket` bodies are sometimes only `title: <the title>` — i.e. no real content. That is honest
data, and the card must look deliberate when empty rather than blank: show the ticket key, dept, day
and assignee from the payload fields and say the description is empty. Do not fabricate a
description.

### PullRequest — one prose paragraph
Not a diff. Real example:

> Knowledge gap detected via reviewer audit: Taylor (expertise: general tasks) submitted PR
> '[ENG-107] Add cost-tagging metadata...' with fit=medium, gap=possible. Reviewed by Jordan.

Render as a PR header (`PR-100`, author, day, reviewer if the text names one) plus the paragraph.
**Do not fake a diff view** — there is no diff in the data and inventing one is the kind of thing
that loses a judge's trust.

---

## 3 — Jac client rules that will bite you

These are learned the hard way in this codebase. Violating them produces a blank page, not an error.

- **`glob` must be `glob:pub`** to be importable. A plain `cl glob X` compiles, passes `jac check`,
  emits no export, and blanks every route at Vite module-resolution time.
- **No `.style.css` annexes.** The annex pipeline is broken in this build — the compiler emits an
  import for a file it never writes. Use inline style dicts only.
- **No `.map()`.** Lists are emitted with statement slots: `{for m in msgs { <div>...</div> }}`.
  Conditionals are `{if cond { <div/> }}`.
- **No `dangerouslySetInnerHTML`.** Markdown is parsed into a list of typed blocks in Jac and
  emitted as JSX.
- **Restart `jac dev` after editing any `.jac`.** HMR is unreliable here; a stale module raises
  `ImportError: module 'app' not in sys.modules` and 500s, which reads exactly like a code bug.
- `has` fields compile to `useState` — assigning to one re-renders.
- Guard every server value. `body` can be `""`; `refs` can be `[]`; dotting into `None` takes down
  the whole page, not just the card.

---

## 4 — The shell: `web/card/Card.jac`

Built first, alone, because everything else imports it.

Exports:

```jac
def:pub Card(payload: dict[str, any], x: float, y: float, onClose: any) -> JsxElement
```

Responsibilities:

- **The window.** Fixed position, anchored near `(x, y)` — the click point in screen coordinates —
  and clamped so it never leaves the viewport. Width 420px, max-height 520px, `overflow: auto` on the
  body region only. Rounded, one-pixel border, a real drop shadow (this is a floating window over a
  dark canvas; it needs to lift off it — the no-shadows rule in `SITE-COPY.md` governs the
  *marketing site*, not the app).
- **A 3px accent bar** across the top in that kind's colour, taken from `TYPE_COLOR` in
  `web/GraphCanvas.jac`. This is the visual tie between the dot you clicked and the window that
  opened. It is the single most important detail in the whole feature.
- **Close.** An × in the top-right, plus `Escape`, plus click-outside.
- **Dispatch** on `payload["kind"]` to the right component. Unknown kind → a plain fallback showing
  title and body as preformatted text. Never crash.
- **The footer strip**, rendered by the shell for every kind so it is identical everywhere: authors
  (as avatar chips), domain chips, and `refs` as clickable rows. Clicking a ref calls
  `onOpenRef(gid)` — accept it as an optional prop; §6 wires it.

Exports these shared tokens, so six agents produce one product instead of six:

```jac
glob:pub CARD_BG: str    = "#11151d";
glob:pub CARD_PANE: str  = "#161b24";   # inset regions: message rows, table headers
glob:pub CARD_FG: str    = "#e6edf3";
glob:pub CARD_MUTED: str = "#8b98a9";
glob:pub CARD_LINE: str  = "rgba(150,170,200,0.16)";
glob:pub CARD_SANS: str  = "system-ui, -apple-system, sans-serif";
glob:pub CARD_MONO: str  = "ui-monospace, SFMono-Regular, Menlo, monospace";

def:pub initials(name: str) -> str;          # "Nora Klein" -> "NK", "Jax" -> "JX"
def:pub avatar_color(name: str) -> str;      # stable hash -> one of ~8 hues
def:pub day_date(day: int) -> str;           # day 1 -> "Jan 1, 2026"  (day 1 == 2026-01-01)
def:pub time_ago(day: int) -> str;           # relative to day 60 -> "22 days ago"
```

Every per-kind component has the same signature and renders **everything inside the window above the
footer**, including its own header:

```jac
def:pub SlackCard(c: dict[str, any]) -> JsxElement
```

---

## 5 — The components

One file each under `web/card/`. Each is self-contained: parser at the top of the file, component
below it, no shared parsing helpers beyond what `Card.jac` exports.

| File | Kinds | The thing that makes it read as authentic |
|---|---|---|
| `SlackCard.jac` | `SlackThread` | `#channel` header with member count; coloured initial-avatars; speaker name bold, message beneath; consecutive messages from one speaker grouped under a single avatar |
| `ZoomCard.jac` | `ZoomTranscript` | attendee chips under the topic; monospace timestamp in a left gutter, turn text in a right column |
| `EmailCard.jac` | `Email` | From/To/Subject/Date as a labelled header block above a rule; signature block set apart at the bottom |
| `ConfluenceCard.jac` | `ConfluencePage` | doc chrome — page title, `space / page` breadcrumb; headings, bullets, bold, and real bordered tables |
| `TicketCard.jac` | `JiraTicket` `PullRequest` `SFOpportunity` `ZDTicket` | ticket key in monospace + a status pill; `key: value` body as a two-column field table; PR gets its prose paragraph |
| `EntityCard.jac` | `Person` `Domain` `Event` `Department` | see below — these are the pitch |

`EntityCard.jac` carries the argument, so it gets the most care:

- **Person** — large avatar, name, role, dept. If `departed_day` is set, a muted "departed day N"
  line. `documented_pct` as a labelled bar: *"documented 20% of what they knew"*. Top domains as a
  ranked list with counts.
- **Domain** — name and aliases. **`bus_factor` as the headline number**, large, red when `1`.
  `doc_status` as a pill (`SPECIFIED` green / `DOCUMENTED_ONLY` yellow / `DEBUGGED_ONLY` orange /
  `UNDOCUMENTED` red). People who know it, ranked. Then `departed_with` — the people who took it with
  them — which is the entire product in one list.
- **Event** — event type, day, incident flag. **`unfulfilled` is the point**: render it as
  *"expected but never happened: confluence_created"* in the accent colour. Produced artifacts as
  clickable rows.
- **Department** — name, member count, member chips, artifact count. Deliberately the plainest card.

---

## 6 — Wire-up (applied last, by the integrator, not by component agents)

Three edits, total:

1. `web/GraphCanvas.jac` — add an `onNodeClick` prop, pass it to `<ForceGraph2D onNodeClick={...}>`.
   The handler receives `(node, event)`; take `event.clientX` / `event.clientY` for the anchor point.
2. `web/AppScreen.jac` — `has card: dict[str, any] = {}` plus `has cx: float` / `has cy: float`; an
   async handler that calls `node_card(gid)` and assigns; pass down through `Shell`.
3. `web/Shell.jac` — pass the props through to `GraphCanvas` and render `<Card ...>` when `card` is
   non-empty.

Nothing before this step touches a file that already exists.

---

## 7 — Where this gets built

**Not in this repo.** A live `jac dev` is serving the demo out of this working tree, and it compiles
every `.jac` under it — an unimported file with a syntax error still breaks the running app.

So components are built and verified in a standalone Jac app at

```
$SCRATCHPAD/cardlab/
```

which has its own `jac.toml`, its own `node_modules`, its own dev server, and a **gallery route**
rendering all twelve kinds at once against real fixtures. Finished, verified files are then copied
into `orgmem/web/card/` on the `cards` branch and merged by PR. Nobody touches the repo until then.

Fixtures live at `cardlab/fixtures.json` — one real record per kind, pulled straight out of
`data/corpus.parquet` and shaped as the §1 payload. Real records, including the ugly ones: the
`JiraTicket` whose body is just `title: ...`, and a Confluence page long enough to scroll.

---

## 8 — Definition of done, per agent

- `jac check` passes from the repo root.
- The card renders from a **real** payload — take an actual row out of `data/corpus.parquet`, not a
  hand-written fixture, and not one you picked because it was tidy.
- It survives an empty `body`, an empty `authors`, and a body 6,000 characters long.
- No hardcoded colours outside the tokens in §4, except the semantic status colours in `EntityCard`.
- It looks like the thing it is imitating from three metres away, which is the distance a judge will
  be standing at.
