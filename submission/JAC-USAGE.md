# How orgmem uses Jac and Jaseci

*Devpost field: "Explain how you use Jac and/or other Jaseci tools in your project."*

---

orgmem is written in Jac end to end. **32 `.jac` files, zero `.py` files, zero `.js` files.** The
graph model, the traversal logic, the evaluation harness, the HTTP layer, and the web UI are all Jac.
Nothing here is a Python application with Jac sprinkled on top, and the object-spatial parts are
doing real work rather than standing in for a class hierarchy.

**The domain is modeled as archetypes, not as tables.** 13 node types and 13 edge types. Every
artifact channel is its own node type (`SlackThread`, `Email`, `ConfluencePage`, `JiraTicket`,
`PullRequest`, `ZoomTranscript`, `ZDTicket`, `SFOpportunity`) alongside `Person`, `Department`,
`Domain`, and `Event`. The edges are typed and carry the semantics: `Authored`, `Mentions`,
`Involves`, `Concerns`, `MemberOf`, `Subscribes`, `InChannel`, `Produced`, `Refs`, `Relates`,
`CoOccurs`, `Estranged`, and `DepartedWith`. Asking "who actually knows TitanDB" is an edge-type
question, not a `WHERE` clause.

**Behavior attaches to node types through dispatch-on-arrival.** Walkers declare abilities like
`can on_person with Person entry` and `can on_artifact with Artifact entry`, so the walker doesn't
branch on what it found. It arrives somewhere and the right code runs. That is the feature that made
the visibility-cone walk tractable: one traversal handles eight artifact types without a switch
statement, because each type answers for itself.

**Persistence is reachability from `root`.** There is no database, no ORM, no migration, and no save
call anywhere in the project. The graph is built once from the corpus and it is simply there on the
next run because it hangs off `root`. Removing the entire storage layer from a hackathon build is not
a small thing, and it is the single Jac feature I would most miss going back to anything else.

**Ten public walkers** carry the query surface: `GraphSlice`, `Visibility`, `GapScan`, `WhoKnows`,
`EventSearch`, `Inherited`, `Expand`, `EvalRun`, `NodeCard`, and `Stats`. The two that make the
product's argument are `Visibility`, which walks the reachability cone bounded by time and access to
determine what a given person could have known on a given date, and `GapScan`, which enumerates the
bounded set of artifacts that *should* have followed an event and counts how many exist. Zero
neighbors of the expected edge type is a provable negative, which is exactly the answer a vector
index cannot return.

**The web app is Jac client components** and the client/server RPC is generated rather than
hand-written. There is no JavaScript in the repo. The UI calls `def:pub` endpoints in the entry
module that `root spawn` the walkers, and the same graph the walkers traverse is what renders on
screen.

**A language model routes the question. It does not answer it.** This distinction is the whole
design, so I want to be exact about it. When you type a sentence into the chat pane, a model reads it
and picks which walker to spawn and with which arguments. That is the entire job. The verdict, the
evidence, the citations, and the highlighted path on the canvas all come back out of the graph
traversal itself, deterministically. The model never sees the corpus and never writes an answer.

Two consequences I care about. First, routing degrades safely: `route_intent` tries the model, and if
the network is dead or the key expired or the parse is bad it falls through to `keyword_intent`, a
deterministic parser that is kept whole rather than deleted, so a bad network costs nothing on stage.
Second, the benchmark is model-free entirely. `jac run eval.jac` spawns the walkers directly and
returns the same 94.7% every time, because there is nothing stochastic in the path between a question
and its answer.

The next layer is the one that genuinely wants a model inside the graph: typed `by llm()` judgements
separating demonstrated ownership from a passing mention. The structural layer had to be right first,
and it needed no model at all.

**Tooling:** `jac dev` for the live full-stack loop, `jac check` in a pre-commit hook, `jac run` for
the evaluation harness, and `jac.toml` for both Python and npm dependencies in one manifest.

One hard-won detail worth passing to the next person: walkers register only for the **entry** module.
With `entry-point = "main.jac"` and the client mounted in `app.jac`, no `/walker/*` routes exist and
every call 405s while the source looks perfectly correct. Pointing `entry-point` at `app.jac`, which
imports the walker names, registers all ten. That one is not in the docs, and neither are the twelve
others written up in the repo's `HANDOFF.md`.
