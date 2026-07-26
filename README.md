# orgmem

**Organizational memory for agents.** Every RAG system indexes what a company wrote down. This maps
what a company *knows* — who knows it, where it's written, and where it isn't.

Built at **JacHacks SF 2026** (Founders Inc. @ Fort Mason, 26 July 2026).

---

## The problem

Information in an organization is scattered across Slack, email, Confluence, Jira, meeting
transcripts, pull requests — and, crucially, across people's heads. Vector search indexes the first
group and is blind to the second. It is also structurally unable to answer the most important
question an organization has:

> **What do we not know we've lost?**

Retrieval can only ever *fail to find* something. It cannot *establish that nothing is there*,
because top-k similarity search is never exhaustive — when the answer doesn't exist, it returns the
nearest thing instead, and the model confabulates from it.

A graph can prove a negative. A node with no outgoing edge of the expected type is a fact, not a
failure. That difference is what this project is built on.

## What it does

Given an organization's artifacts, orgmem builds a graph of people, documents, systems and events,
then answers three classes of question that flat retrieval cannot:

- **Silence** — *"An incident opened on day 8. Was a postmortem ever written?"* Answered by walking
  from the trigger event over a bounded space and counting zero. The bounded space is the proof.
- **Perspective** — *"Could Felix have known about this on day 32, given his access?"* A reachability
  walk from a person, bounded by time and by system access. Needs no language model at all.
- **Expertise and risk** — *"Who knows TitanDB?"* Ranked from demonstrated engagement, with bus
  factor and documentation status. Surfaces domains whose only knowledgeable people have left.

## Why Jac

The domain is a graph, so the language that treats graphs as a first-class data model does real work
here rather than decorative work.

- **`node` / `edge` archetypes model the domain directly.** Artifact types are *separate node types*
  (`SlackThread`, `ConfluencePage`, `JiraTicket`, `ZoomTranscript`, `Email`, `PullRequest`), so
  behaviour attaches per type via dispatch-on-arrival. Adding a seventh source means adding an
  ability, not editing a dispatcher.
- **Walkers are the query engine.** A traversal isn't a query against a store — it's an agent moving
  through the graph, and the path it walked *is* the citation. Provenance is a by-product, not a
  parallel system to keep in sync.
- **Persistence is a language feature.** Everything reachable from `root` survives the process.
  There is no database, no ORM, no schema migration and no save call in this project.
- **One language across the stack.** The UI is Jac client components; the RPC between client and
  server is generated rather than hand-written.

## Data

Built on [`aeriesec/orgforge`](https://huggingface.co/datasets/aeriesec/orgforge) (MIT) — a public
dataset simulating 60 days inside a fictional sports-wearables company, "Apex Athletics". Every
artifact descends from a single causal event log, which is what makes it a genuine graph rather than
a pile of documents. It ships with 78 evaluation questions carrying machine-checkable ground truth.

The large data files are not committed. To fetch:

```python
from datasets import load_dataset
load_dataset("aeriesec/orgforge")
```

## Running it

Requires the Jac toolchain (0.34.x, Python ≥ 3.14).

```bash
jac check main.jac        # type + ownership check
jac run   main.jac        # build the graph (persists to .jac/data/)
jac start main.jac        # serve walkers
jac dev                   # client with hot reload
```

The graph builds once and persists. Re-running does not rebuild it.

## Status

Hackathon build, one day. The structural layer — all edges derivable from the data with no model
calls — is the foundation; the inferred knowledge layer (typed `by llm()` judgements about who
genuinely *knows* a domain versus who merely mentioned it) sits on top of it.

## Credits

Dataset: `aeriesec/orgforge`, MIT. Graph rendering uses open-source npm libraries. Everything else
written during the event.
