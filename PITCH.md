# orgmem — pitch, demo script, submission copy

Everything you need for the 4-minute expo demo and the Devpost form. Numbers here are
real — from `eval_results.json`, reproducible by running the eval walker.

---

## The one-liner

> **Organizational memory for agents.** Every RAG system indexes what your company wrote
> down. This maps what your company *knows* — who knows it, where it's written, and where
> it isn't.

## The 30-second version

Information in an organization lives across Slack, email, Confluence, Jira, meeting
transcripts, pull requests — and in people's heads. Vector search indexes the first group
and is blind to the second. Worse, it structurally cannot answer the most important
question an organization has: **what do we not know we've lost?**

Retrieval can only ever *fail to find* something. It can never *establish that nothing is
there*, because top-k similarity is never exhaustive — when the answer doesn't exist, it
returns the nearest thing instead and the model confabulates from it.

A graph can prove a negative. A node with no outgoing edge of the expected type is a fact,
not a failure.

---

## The 4-minute demo script

**Time it. The money moment must land inside the first 60 seconds.**

### 0:00 — Open on the graph (10s)

Landing view, full corpus on screen.

> "This is 60 days inside a company — 22,000 artifacts. Slack, email, Confluence, Jira,
> Zoom transcripts, pull requests. Every person, every document, every system, as one
> graph. Nothing here is a database — in Jac, anything reachable from root is persistent,
> so this graph *is* the storage."

### 0:10 — The question that pays off (50s)

Click: **"Was an onboarding session created when Janice was hired on day 7?"**

Watch the walker traverse. Then the verdict: **NO.**

> "Janice was hired on day seven to take over TitanDB. Bill had left nineteen months
> earlier owning four systems, with twenty percent of his knowledge documented. She never
> got an onboarding session. Nobody noticed, because nobody was looking for a thing that
> didn't happen.
>
> A vector search cannot answer that question. You cannot retrieve a document that doesn't
> exist — it returns the nearest thing instead and tells you yes. We walk from the hiring
> event over the bounded set of things that should have followed, and count zero. **Zero
> neighbours is proof, not failure.**"

### 1:00 — Who knows what (45s)

Click **"Who knows TitanDB?"**

> "Ranked by demonstrated engagement, not by org chart. Bus factor three. And there's Bill
> — departed, four domains, twenty percent documented. That's the knowledge this company
> lost and never wrote down."

### 1:45 — The visibility cone (45s)

Click **"Could Felix have known about the CRM touchpoint on day 32?"** → **NO — blocked by
role.** Then the Janice day-3 one → **NO — because no artifact was ever created.**

> "Same query, two completely different reasons. One person was blocked by access. The
> other — the meeting happened, nobody wrote anything down, so unless you were in the room
> you could not know. **That second one is the lossy compression layer, measured.**
>
> This needs no language model at all. It's a reachability walk bounded by time and access."

### 2:30 — The scoreboard (45s)

> "The dataset ships 78 questions with machine-checkable ground truth. We score **94.7%
> overall**. On the silence questions — the ones about things that never happened —
> **26 of 27**, against a 55.6% coin-flip baseline, because the set is near-balanced and
> can't be gamed by always guessing yes.
>
> We deliberately **do not score** the 21 counterfactuals. Answering 'would this incident
> still have happened?' needs the simulator's causal model, not the artifacts. We can trace
> the chain and show the evidence; we won't claim we can prove the counterfactual."

*(That last sentence buys more credibility than any number on the slide.)*

### 3:15 — Why Jac (35s)

> "The domain is a graph, so the language that treats graphs as first-class does real work
> here. Artifact types are separate node types — a Confluence page and a Slack thread
> behave differently on arrival, so adding a seventh source is one new ability, not an
> edit to a dispatcher. The traversal path *is* the citation, so provenance is a
> by-product rather than a parallel system to keep in sync. Persistence is
> reachability from root — no database, no ORM, no migrations, no save call.
>
> And the UI is Jac too. The whole thing is one language: **95% of this codebase is Jac**,
> and there is no JavaScript in it."

### 3:50 — Close (10s)

> "Every organization is losing knowledge it can't see. This makes the absence visible."

---

## If something breaks on stage

- **The graph doesn't render** → go to the answer panel. The verdicts and evidence are the
  substance; the canvas is the garnish.
- **A preset errors** → move to the next one. Four presets, you need two.
- **Everything is down** → open `eval_results.json` and talk through the numbers. The
  benchmark result is the strongest claim you have and it doesn't need a running server.
- **Never** apologise for a broken feature and then keep poking at it. Move on; judges
  remember the recovery, not the fault.

## Questions judges will ask

**"Isn't this just GraphRAG?"**
> The pattern isn't new — the implementation is. There's no vector store, no graph database
> and no sync between them. The graph is the persistence layer, the retriever is a walker,
> and the extraction schema is the type system.

**"Why not Neo4j and Python?"**
> You'd need the database, an ORM, a query DSL, an API layer, and a separate provenance log
> — five things that drift out of sync. Here they're one artifact. And dispatch-on-arrival
> over heterogeneous node types has no clean equivalent.

**"Is the data real?"**
> It's `aeriesec/orgforge`, a public MIT-licensed simulation of a 60-day company where every
> artifact descends from one causal event log. That's *why* we can score ourselves — it
> ships ground truth. Real corpora don't.

**"What doesn't work yet?"**
> The inferred knowledge layer. Right now "who knows what" is structural — demonstrated
> engagement weighted by recency and artifact type. The next step is a typed `by llm()`
> judgement distinguishing genuine ownership from a passing mention. Everything you're
> seeing today is deterministic, which is also why it's fast and reproducible.

---

## Devpost copy

**Tagline:** Organizational memory for agents — who knows what, where it's written, and
where it isn't.

**What it does.** orgmem ingests a company's artifacts — Slack, email, Confluence, Jira,
Zoom transcripts, pull requests — into a persistent graph of people, documents, systems and
events, then answers questions retrieval cannot: whether an expected follow-up ever
happened, what a given person could have known at a point in time given their access, and
who actually holds knowledge of a system versus who merely mentioned it.

**How we built it.** Everything load-bearing is Jac. `node`/`edge` archetypes model the
domain; the eight artifact kinds are separate node types, so behaviour attaches per type
through dispatch-on-arrival — **32 walker abilities keyed on the node they land on**
(`can at_artifact with Artifact entry`, `can at_domain with Domain entry`,
`can finish with Hub exit`). Ten walkers do ingest, graph slicing, visibility-cone
reachability, gap scanning, expertise ranking, event resolution, departure analysis, node
cards and evaluation. Persistence is reachability from `root` — no database, no ORM, no
save call. The UI is Jac client components and the client/server RPC is generated. There
is **no JavaScript in the codebase**.

**The agent, and the line we refuse to cross.** You ask in English. An LLM
(`kimi-for-coding-highspeed`) runs in a tool-calling loop where **the tools *are* the
walkers** — `find_event`, `gap_scan`, `who_knows`, `could_have_known`, `inherited`,
`describe_node`, `neighbors` — and it composes them across turns. Ask *"which incidents
never got a postmortem?"* and it resolves twelve incidents, then fans out twelve
exhaustive gap scans in a single turn. Every tool call and its result streams into the
panel as it lands, and the union of the walkers' routes animates on the graph.

The division of labour is the whole design: **the model chooses which tool to call; the
walkers decide what is true.** Every verdict, citation and "N records examined" comes from
a deterministic traversal — the same code path the benchmark scores. `describe_node`
strips artifact bodies rather than truncating them, so the model *cannot* read the corpus
and *cannot* turn a proven absence into a maybe. Ask the pane what tools it has and it
tells you so itself.

**Accomplishments.** 94.7% overall (54/57 scored) on the dataset's ground-truth questions
— **96.3% on the "silence" class against a 55.6% constant baseline**. We deliberately
decline to score the 21 counterfactual questions rather than claim causal reasoning we
cannot verify from artifacts. The benchmark was re-run after the agent loop landed and is
**unchanged to the question** — because the model never touches the scored path.

**Challenges.** The interesting one was a failure the agent found for us. Asked whether a
new hire was ever onboarded, it searched for an onboarding event, found none, and answered
"no" — right answer, no proof, and exactly the failure this project exists to beat:
*not-found is not absence*. It now knows that an empty search means resolution failed, and
that absence is only ever established by an exhaustive `gap_scan` over the causal closure.

**What we learned.** Things about Jac that aren't in the docs: walkers register only for
the entry module; `sv import` of a same-project server module silently flips the build
into microservice mode; typed locals compile to `const`, so a loop that rebinds one dies
silently; and `pkill` on the dev server leaves an orphaned API child serving stale code.
All eighteen are written up in `HANDOFF.md`.

**What's next.** Letting the agent write back — proposing the missing document and the
person to own it, as a node in the same graph it just proved the gap in.

---

## Submission checklist

- [x] GitHub repo public — https://github.com/frankie-eight-days/orgmem *(verified)*
- [x] **⭐ Star github.com/jaseci-labs/jac** — an explicit requirement *(verified set)*
- [ ] Demo video recorded ← **the long pole; nothing else is blocking**
- [ ] Written description includes how Jac/Jaseci was used *(paste "Devpost copy" above)*
- [ ] Tracks selected — see below
- [ ] **Partial submission by 17:50** — required to be judged, editable afterwards
- [ ] Final by 19:15 — hard, no late entries

**There is no deployment step.** An earlier version of this list said "deploy to
jachammer.ai". No such site exists — **JacHammer is an award, not a product** (the SF
rename of "Best Use of Jac", $500), and the field manual records that a web search
hallucinated a JacHammer product and that the finding was discarded. That hallucination
had survived into this checklist. Judging is an in-person live demo — *"working demos beat
slide decks"* — so the demo runs from the laptop and the submission carries the repo URL
and the video.

## Tracks — enter all four, entry is free

| track | the sentence to lead with |
|---|---|
| **Agentic AI** (flagship) | An LLM in a tool-calling loop where the tools are graph walkers — it composes twelve exhaustive scans in one turn, and it cannot state anything a traversal did not return. |
| **Best JacHammer** ($500) | Ten walkers, 32 dispatch-on-arrival abilities, persistence by root-reachability, one language front to back, zero JavaScript. The award rewards the most *idiomatic* Jac, and the whole argument here — that a graph can prove a negative — is only expressible as traversal. |
| **AI for Defense** ($500, Initium) | Brief explicitly names *"decision support"* and *"security"*. "Who could have known what, on which day, given their access" is a compartmentalisation question; "what was never written down" is a readiness one. Honest fit, not a stretch. |
| Domain track | Whichever fits the room — the corpus is a company's own record. |
