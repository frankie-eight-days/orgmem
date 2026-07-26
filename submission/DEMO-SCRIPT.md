# orgmem: demo video script

**Target: 90 seconds.** Two minutes is the ceiling. Every line below is the shortest version that
still carries the argument.

Rules for the recording:
- **No preamble.** Do not say your name, the hackathon, or "so what I built is". Start on the claim.
- **One take per section, cut between.** Don't try to nail 90 seconds in one pass.
- **Talk over the motion.** Never narrate a click ("now I'm going to click on..."). Click, keep talking.
- If a line feels long while you're saying it, cut the second half. The bold phrases are the ones that
  must survive.

---

## 0:00 to 0:20 | The site (20s)

*Screen: hero, then scroll steadily through the sections. Keep scrolling while you talk.*

> "Every RAG system indexes what your company wrote down.
>
> **This maps what your company knows.** Who knows it, where it's written, and where it isn't.
>
> Four thousand artifacts across six systems become a typed graph in about six seconds. Slack,
> email, Confluence, Jira, transcripts, pull requests."

*Land the scroll on the transformation animation (artifacts raining in and resolving into the graph)
and let it play for two or three seconds without talking. That shot does the work.*

---

## 0:20 to 0:35 | Open the app, click a node (15s)

*Screen: cut to `/app`. Chat pane left, graph right.*

> "Same graph, running. Every node is a person, a document, a system, or an event."

*Click a node. Card opens.*

> "Click anything and you get the artifact itself. **The traversal path is the citation**, so
> provenance isn't a second system I had to keep in sync. It's a by-product of the walk."

---

## 0:35 to 1:05 | The question that pays off (30s)

*This is the money moment. Everything before it is setup.*

*Type into the chat pane:*

```
Was Janice ever given an onboarding session?
```

*Let the walk animate. Don't talk over the first second of it.*

> "Janice was hired on day seven to take over TitanDB. The person who owned it left nineteen months
> earlier with twenty percent of his knowledge documented.
>
> The answer is **no**. She never got one. Nobody noticed, because **nobody was looking for a thing
> that didn't happen**.
>
> Vector search cannot answer that. You can't retrieve a document that doesn't exist, so it returns
> the nearest thing and tells you yes. This walks from the hiring event over the bounded set of
> things that should have followed, and counts zero. **Zero neighbours is proof, not failure.**"

---

## 1:05 to 1:20 | The follow-up (15s)

*Type the bare follow-up. Do not re-name the system. The point is that it resolves context.*

```
Who would be the best person to pick it up?
```

> "It carries the subject over. Ranked by demonstrated engagement, not by the org chart.
>
> And a model never touched the answer. **It only picked which walker to run.** The verdict, the
> evidence and the path all come out of the graph."

---

## 1:20 to 1:30 | Close (10s)

*Screen: back out to the full graph, or hold on the answer with citations visible.*

> "94.7% on 78 ground-truth questions. **96.3% on the ones about things that never happened**,
> against a 55.6% baseline.
>
> Written end to end in Jac. No database, no ORM, no JavaScript.
>
> Every organization is losing knowledge it can't see. **This makes the absence visible.**"

---

## If you have 30 more seconds and want them

Insert between the follow-up and the close. Cut this first if you're over.

*Type:*

```
Could Felix have known about the CRM touchpoint on day 32?
```

> "**No, blocked by role.** Same question shape as Janice's, completely different reason. One person
> was blocked by access. The other, the meeting happened and nobody wrote anything down, so unless
> you were in the room you could not know.
>
> **That second one is the lossy compression layer, measured.**"

---

## Safe questions (all verified in the app's own examples list)

Use these exact sentences. They're the ones the router and the keyword fallback both handle.

- `Was Janice ever given an onboarding session?`
- `Who knows TitanDB?`
- `Who would be the best person to pick up TitanDB?`
- `Did we ever do the postmortem for the day-25 incident?`
- `Could Felix have known about the CRM touchpoint on day 32?`
- `Was the day-35 knowledge gap ever written up?`

## If something breaks while recording

You're recording, not presenting live, so the answer is almost always "stop and re-take". But:

- **Chat pane hangs** → the model router is unreachable. It falls back to the keyword parser on its
  own, so the same sentence still works. Re-send it.
- **Graph doesn't render** → record the chat pane full-width. The verdict and citations are the
  substance; the canvas is the garnish.
- **A question routes wrong** → use the exact sentences from the list above, which is where the
  fallback keywords come from.
- Never record an apology for a broken feature. Cut and re-take.

---

## The 20-second version, if you need one

For a Devpost embed where attention is short.

> "Every RAG system indexes what your company wrote down. This maps what your company *knows*.
>
> Was Janice given an onboarding session when she was hired? **No.** Nobody noticed, because nobody
> was looking for a thing that didn't happen. Vector search can't answer that. A graph can, because
> **zero neighbours is proof, not failure**.
>
> 94.7% on 78 ground-truth questions. Written end to end in Jac."
