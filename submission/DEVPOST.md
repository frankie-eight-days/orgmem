# orgmem: Devpost story

**Tagline:** Organizational memory for agents. Retrieval finds what your company wrote down.
orgmem proves what it never did.

---

## Inspiration

I recently onboarded at a Fortune 5 company, and the thing that struck me wasn't that the
documentation was bad. The documentation is *good*. There's a lot of it. It still wasn't enough,
because the part I actually needed lives in people's heads: what happened, when, and who was in the
room.

A huge amount of the work is reconstructing sequence. Why does this system look like this? Who
decided that? Was there a handoff when the person who built it left? That's a PM-shaped question,
and no amount of well-written documentation answers it, because nobody writes down the thing they
assume everybody already knows. It's tribal knowledge, and the tribe doesn't know it's a tribe.

What I wanted was to see the whole thing as a graph, with people, documents, systems, and events and
the edges between them, so I could look at it myself instead of asking six people and triangulating.
That's orgmem.

## What it does

orgmem ingests a company's artifacts (Slack, email, Confluence, Jira, Zoom transcripts, pull
requests) into a persistent graph of people, documents, systems, and events. Then it answers
questions retrieval structurally cannot:

- **Did the expected follow-up ever happen?** Janice was hired on day 7 to take over TitanDB from
  someone who left 19 months earlier owning four systems with 20% of his knowledge documented. Was
  an onboarding session ever created? **No.** Nobody noticed, because nobody was looking for a thing
  that didn't happen.
- **What could this person have known on this date?** Bounded by their access and by what actually
  existed at that moment. That separates "they were blocked by permissions" from "the meeting
  happened and nobody wrote anything down."
- **Who actually knows this system?** Ranked by demonstrated engagement rather than by org chart,
  including the people who already left.

The core claim is narrow and I think it's right: **a graph can prove a negative and top-k similarity
cannot.** Vector search can only ever *fail to find* something. It can never establish that nothing
is there, because when the answer doesn't exist it returns the nearest thing instead and the model
confabulates from it. A node with no outgoing edge of the expected type is a fact, not a miss.

## How I built it

The first problem was data. I needed a corpus that looked like a real organization's exhaust:
multi-channel, with people and time and enough mess to be honest. That turned out to be genuinely
hard to find. I landed on **orgforge** and pulled its default dataset from Hugging Face.

The real design work was the schema, deciding how to turn a pile of artifacts into a graph worth
querying. What's a node, what's an edge, what's an event versus a document, and where the time
dimension lives. That decision determines every question you can ask afterward, and it's the part I'd
spend more time on if I did it again.

Everything load-bearing is Jac:

- `node` / `edge` archetypes model the domain. Each artifact type is its own node type, so behavior
  attaches per type through dispatch-on-arrival rather than a switch statement.
- **Ten public walkers** do graph slicing, visibility-cone reachability, gap scanning, expertise
  ranking, event search, inheritance, expansion, node detail, stats, and evaluation.
- **Persistence is reachability from `root`.** No database, no ORM, no save call. The graph *is* the
  storage.
- The UI is Jac client components and the client/server RPC is generated. There is no JavaScript.

Final graph: **76,787 edges over 46 people, 4,966 artifacts, and 10,941 events, built in ~6 seconds.**

After the graph came the demo and the marketing site, then iterating on the demo until it looked like
something instead of a debug view.

## Challenges I ran into

**The biggest challenge was that the models don't know Jac.** Jac is a fast-moving language and the
training data is stale or simply wrong, so every assistant I used confidently generated syntax that
doesn't exist. I built a knowledge base up front, a distilled wiki of the language read directly out
of the compiler source, about 49k words, with the places where the official docs and the actual
implementation disagree called out explicitly. It helped. It was not enough. Retrieval over docs is a
much worse substitute for knowing a language than I expected, and what this ecosystem really wants is
a fine-tuned model that writes Jac natively.

So I found the sharp edges the slow way. A sample:

- Omitted optional arguments arrive as **strings** over the RPC bridge. A `None` default arrives as
  `'None'`, and a `= []` default arrives as `['[', ']']`. Both are truthy, so `if arg` fallbacks
  silently never fire.
- Typed locals compile to `const`, so rebinding one throws *"Attempted to assign to readonly
  property"*, and only on the branch that rebinds.
- Walkers register only for the **entry** module, so with the wrong entry point every `/walker/*`
  route 405s and the source looks perfectly correct.
- Incremental rebuilds silently drop `glob` exports. `def` exports survive.

Twelve more are written up in the repo's `HANDOFF.md`. The meta-lesson was harsher than any single
bug: **verify the artifact, not the status message.** Three separate times a build reported success
while serving a stale bundle, and once a `git push` correctly reported "up to date" while pushing a
branch that didn't contain the work.

## Accomplishments that I'm proud of

I'm trained as an **electrical engineer**, not a software engineer, and I didn't know anything about
graphs when I started. Getting from there to a working graph model of an organization, and picking up
a language built around object-spatial programming on the way, is the part I'm actually stoked about.
Jac made full-stack development dramatically more approachable than I expected it to be.

On the numbers: **94.7%** overall on the dataset's 78 ground-truth questions, and **96.3% (26/27)**
on the SILENCE class against a 55.6% constant baseline. That's the class that asks whether something
never happened, which is the whole thesis.

And one deliberate non-accomplishment: **I don't score the COUNTERFACTUAL class at all.** Those
questions ask what *would* have happened, and I can't verify a causal claim from artifacts alone.
Skipping 21 questions costs me a higher headline number. Claiming causal reasoning I can't back up
would cost more.

## What I learned

Graphs, mostly. How to think in nodes and edges instead of tables and joins, and how much a schema
decision constrains every question you can ask later. Beyond that: persistence-by-reachability
genuinely removes an entire layer of the stack, a language can make full-stack work feel small, and
when the tooling is newer than the model's training data you have to build your own ground truth and
then distrust every success message you get.

## What's next for orgmem

**A real-time ingest engine.** The current graph is built from a static corpus, and the obvious next
step is a live one that updates as artifacts land.

The goal that pulls everything forward is a **digital twin of an organization**: a continuously
updated graph that executives and senior leaders can query directly. Right now, understanding what's
happening inside a large company means passing information up through layers, and every layer is
lossy. Things get summarized, softened, and dropped, and what didn't get written down disappears
entirely. orgmem measures that loss today. The version I want to build removes it.
