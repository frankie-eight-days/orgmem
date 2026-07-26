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
domain; artifact types are separate node types so behaviour attaches per type via
dispatch-on-arrival. Six walkers do ingest, graph slicing, visibility-cone reachability,
gap scanning, expertise ranking and evaluation. Persistence is reachability from `root` —
no database, no ORM, no save call. The UI is Jac client components; the client/server RPC
is generated. **95% of the codebase is Jac; there is no JavaScript.**

**Accomplishments.** 94.7% on the dataset's 78 ground-truth questions — 26/27 on the
"silence" class against a 55.6% baseline. We deliberately decline to score the
counterfactual class rather than claim causal reasoning we can't verify from artifacts.

**What we learned.** Several things about the Jac client that aren't in the docs: walkers
register only for the entry module; `sv import` of a same-project server module silently
flips the build into microservice mode; and HMR leaves stale modules that 500 on the next
call, so restart `jac dev` after editing any `.jac`.

**What's next.** The inferred knowledge layer — typed `by llm()` judgements separating
demonstrated ownership from passing mention — layered onto the structural graph that
already exists.

---

## Submission checklist

- [ ] GitHub repo public — https://github.com/frankie-eight-days/orgmem
- [ ] Demo video recorded
- [ ] Written description includes how Jac/Jaseci was used *(the "How we built it" section)*
- [ ] **⭐ Star github.com/jaseci-labs/jac** — an explicit requirement
- [ ] Deployed to jachammer.ai, env vars set there (not committed)
- [ ] Tracks selected — Agentic AI + one domain track + JacHammer
- [ ] **Partial submission by 17:50** — required to be judged, editable afterwards
- [ ] Final by 19:15 — hard, no late entries
