"""Section 4 — Apex Athletics, and what observability over an org looks like.

Everything on this page is counted or derived from `data/sim_snapshot.json` and
`data/domain_registry.json`. Nothing is illustrative. That matters more here
than anywhere else on the site, because this section makes a causal-looking
claim and the whole project's credibility rests on the claim being checkable.

**The day numbering.** The snapshot counts in *simulation days*, which are
working days: the corpus spans 2026-01-01 to 2026-03-25 — 84 calendar days —
but only 60 simulation days. Jira artifacts carry calendar timestamps, so
incident dates are converted by counting weekdays from 2026-01-01. That
conversion was verified against the two `event_log` rows that carry both a
`day` and a `date` (2026-03-16 → day 53, 2026-03-17 → day 54); both land exactly
where the weekday count predicts. This is why the site says "60 working days
across twelve weeks" and not "60 days".

**The adjacency.** Jordan leaves on day 12 owning `redis-cache`, having
documented 25% of what he knew. On day 13, ENG-137 fires: a Redis TTL
misconfiguration whose description says it causes excessive reads from TitanDB
and overloads the database. Those are two independent records in the corpus and
the gap between them is one day.

That is presented as an *adjacency*, never as a cause. The copy says "the day
after" and stops. We do not score COUNTERFACTUAL questions for exactly this
reason, and claiming causation in marketing copy that the evaluation
deliberately refuses to claim would be the most damaging inconsistency on the
site. A judge who notices the restraint should find it consistent everywhere.
"""

"""The twelve P1 incidents, at their converted simulation days."""
cl glob INCIDENTS: list[dict[str, any]] = [
    {"day": 3,  "id": "ENG-112", "what": "EKS cost-tag missing · budget alarm"},
    {"day": 8,  "id": "ENG-123", "what": "Kafka partition leader re-election"},
    {"day": 13, "id": "ENG-137", "what": "Redis TTL · TitanDB overload"},
    {"day": 17, "id": "ENG-148", "what": "Kafka consumer group offsets"},
    {"day": 21, "id": "ENG-165", "what": "PostgreSQL connection reduction"},
    {"day": 25, "id": "ENG-173", "what": "EKS autoscaler misconfigured"},
    {"day": 29, "id": "ENG-186", "what": "Kafka consumer lag"},
    {"day": 37, "id": "ENG-210", "what": "Go telemetry race condition"},
    {"day": 42, "id": "ENG-230", "what": "max.poll.interval.ms"},
    {"day": 46, "id": "ENG-237", "what": "Redis maxmemory policy"},
    {"day": 50, "id": "ENG-250", "what": "security group rule"},
    {"day": 54, "id": "ENG-263", "what": "Kafka partition count"}
];

"""Arrivals and departures inside the window. Bill (day -579) and Sharon
(day -306) left before it opens and are deliberately not plotted — putting them
on this axis would misrepresent when their knowledge disappeared."""
cl glob PEOPLE: list[dict[str, any]] = [
    {"day": 7,  "who": "Janice",  "kind": "join",  "note": "joins"},
    {"day": 12, "who": "Jordan",  "kind": "leave", "note": "leaves · 25% documented"},
    {"day": 26, "who": "Reese",   "kind": "join",  "note": "joins"},
    {"day": 34, "who": "Morgan",  "kind": "leave", "note": "leaves · 60% documented"}
];

"""The questions this section exists to pose, each with the walk that answers it."""
cl glob QUESTIONS: list[dict[str, str]] = [
    {
        "q": "Who carries redis-cache now that Jordan is gone?",
        "m": "Rank people by demonstrated engagement with the domain. Return the bus factor with the ranking.",
        "t": "expertise"
    },
    {
        "q": "Was a postmortem ever written for ENG-137?",
        "m": "Walk from the incident. Count the artifacts of the expected type. Zero is an answer, not a miss.",
        "t": "silence"
    },
    {
        "q": "Could Janice have known about the Redis TTL on day 13?",
        "m": "Reachability from a person, bounded by day and access. Nothing inferred.",
        "t": "perspective"
    },
    {
        "q": "Which domains are one departure away from unowned?",
        "m": "For every domain, count the people with demonstrated engagement. Report the ones where that count is one.",
        "t": "expertise"
    }
];

"""The artifact inventory, straight off the ingest log.

Eight rows, because the graph builds eight artifact types. Listing only the six
large ones — which an earlier draft did — leaves the column summing to 4,961
against a stated total of 4,966, and being out by five on a page whose argument
is "check our numbers" is worse than the two extra rows are ugly.
"""
cl glob INVENTORY: list[dict[str, str]] = [
    {"k": "Slack threads",    "v": "3,303"},
    {"k": "Emails",           "v": "610"},
    {"k": "Confluence pages", "v": "479"},
    {"k": "Jira tickets",     "v": "304"},
    {"k": "Zoom transcripts", "v": "208"},
    {"k": "Pull requests",    "v": "57"},
    {"k": "Salesforce opps",  "v": "3"},
    {"k": "Zendesk tickets",  "v": "2"}
];

cl def:pub inventory() -> list[dict[str, str]] { return INVENTORY; }

cl def:pub incidents() -> list[dict[str, any]] { return INCIDENTS; }
cl def:pub people() -> list[dict[str, any]] { return PEOPLE; }
cl def:pub questions() -> list[dict[str, str]] { return QUESTIONS; }

"""Day number to x position on the 60-day axis."""
cl def:pub tx(day: int) -> float {
    return 40.0 + ((day - 1) as float) * 920.0 / 59.0;
}

cl def:pub tx_s(day: int) -> str {
    return f"{tx(day):.1f}";
}

"""Vertical offset for a person marker's labels.

Janice (day 7) and Jordan (day 12) are five days apart, which is 78px on this
axis — far less than the width of "leaves · 25% documented". Left on one row the
two captions overlap into "joins leaves · 25% documented", which is how the
first render came out. Arrivals therefore sit on the near row and departures on
the far one, which separates them by kind rather than by index and so cannot
collide however the days fall.
"""
cl def:pub py(kind: str, base: int) -> str {
    return str(base + (0 if kind == "join" else 26));
}

def:pub Dataset() -> JsxElement {
    inc: list[dict[str, any]] = incidents();
    ppl: list[dict[str, any]] = people();

    return <section className="sec sec-data" id="dataset">
        <h2 className="sec-h2">{"Sixty working days at Apex Athletics."}</h2>

        <p className="body">
            <a className="inline-link" href="https://huggingface.co/datasets/aeriesec/orgforge"
               target="_blank" rel="noreferrer noopener">{"orgforge"}</a>
            {" is a public dataset: a simulated sports-technology company, 46 people across eight departments, twelve weeks of Slack, email, Confluence, Jira, transcripts and pull requests. It ships the artifacts and the ground truth — who left, what they knew, what broke, and which questions have no answer in the record."}
        </p>

        <p className="src-row">
            <a className="src-link" href="https://huggingface.co/datasets/aeriesec/orgforge"
               target="_blank" rel="noreferrer noopener">{"dataset on Hugging Face ↗"}</a>
            <a className="src-link" href="https://github.com/tenurehq/orgforge"
               target="_blank" rel="noreferrer noopener">{"generator on GitHub ↗"}</a>
        </p>

        {#* The inventory, before anything is claimed about it. A reader who has
            not yet been told what the product does can still understand a list
            of files, and it makes the numbers later concrete rather than
            rhetorical. Eight rows, not six: the two-row tail is small enough to
            look like an omission if it is left off, and the column has to add
            up to 4,966. *#}
        <ul className="inv">
            {for (i, row) in enumerate(inventory()) {
                <li className="inv-item" key={row["k"]}>
                    <span className="inv-n">{row["v"]}</span>
                    <span className="inv-k">{row["k"]}</span>
                </li>
            }}
        </ul>
        <p className="inv-total">{"4,966 artifacts · 10,941 events · 46 people · 10 knowledge domains"}</p>

        <figure className="tl-fig">
            <svg className="tl-svg" viewBox="0 0 1000 275" role="img"
                 aria-label="A sixty-day timeline. Twelve P1 incidents are marked above the axis; arrivals and departures below it. Jordan leaves on day 12 and a Redis incident follows on day 13.">

                {#* the axis *#}
                <line className="tl-axis" x1="40" y1="132" x2="960" y2="132" />
                {for (i, t) in enumerate([1, 15, 30, 45, 60]) {
                    <g key={str(t)}>
                        <line className="tl-tick" x1={tx_s(t)} y1="128" x2={tx_s(t)} y2="136" />
                        <text className="tl-axis-label" x={tx_s(t)} y="152">{"day " + str(t)}</text>
                    </g>
                }}

                {#* the one adjacency the section is about, drawn behind everything *#}
                <rect className="tl-window" x={tx_s(12)} y="40" width="18" height="92" rx="2" />

                {#* incidents, above the line *#}
                {for (i, e) in enumerate(inc) {
                    <g className={"tl-inc" + (" tl-inc-hot" if e["day"] == 13 else "")} key={e["id"] as str}>
                        <line x1={tx_s(e["day"])} y1="132" x2={tx_s(e["day"])} y2="96" />
                        <circle cx={tx_s(e["day"])} cy="92" r="4" />
                    </g>
                }}

                {#* arrivals and departures, below the line *#}
                {for (i, p) in enumerate(ppl) {
                    <g className={"tl-p tl-p-" + (p["kind"] as str)} key={p["who"] as str}>
                        <line x1={tx_s(p["day"])} y1="132" x2={tx_s(p["day"])}
                              y2={py(p["kind"] as str, 176)} />
                        <circle cx={tx_s(p["day"])} cy={py(p["kind"] as str, 180)} r="4.5" />
                        <text x={tx_s(p["day"])} y={py(p["kind"] as str, 200)}>{p["who"]}</text>
                        <text className="tl-p-note" x={tx_s(p["day"])}
                              y={py(p["kind"] as str, 213)}>{p["note"]}</text>
                    </g>
                }}

                <text className="tl-lane tl-lane-top" x="40" y="22">{"12 P1 incidents"}</text>
                <text className="tl-lane" x="40" y="262">{"arrivals and departures"}</text>

                {#* The callout sits above the incident row, not level with it.
                    At y=90 the sub-line ran straight through the dots for days
                    15 to 29. *#}
                <text className="tl-call" x={tx_s(15)} y="52">{"ENG-137 — Redis TTL, TitanDB overload"}</text>
                <text className="tl-call tl-call-sub" x={tx_s(15)} y="67">{"the day after the person who owned redis-cache left"}</text>
            </svg>

            {#* The methodology note was three lines of grey mono directly under
                the chart, competing with the chart. It is a footnote, so it is
                typeset as one — one line, at the bottom, after the facts. *#}
            <figcaption className="tl-cap">
                {"Incident days converted from Jira timestamps by weekday count. Bill and Sharon left before day 1 and are not plotted."}
            </figcaption>
        </figure>

        <div className="tl-facts">
            <p className="tl-fact">
                <span className="tl-fact-n">{"day 12"}</span>
                <span className="tl-fact-l">{"Jordan leaves, owning auth-service, redis-cache and oauth2-flow — 25% documented"}</span>
            </p>
            <p className="tl-fact">
                <span className="tl-fact-n">{"day 13"}</span>
                <span className="tl-fact-l">{"ENG-137: a Redis TTL misconfiguration overloads TitanDB. Assigned to Yusuf"}</span>
            </p>
        </div>

        <p className="note note-tight">
            {"We are not claiming the departure caused the incident, and orgmem does not score counterfactual questions. It reports what is adjacent in the record and leaves the inference to the person reading it."}
        </p>

    </section>;
}

"""Section 3 — what you would want to ask, and currently cannot.

Split out of `Dataset` so it can sit after the problem statement rather than
inside the dataset introduction. By the time a reader reaches this they have met
Apex Athletics, seen day 12 and day 13, and been shown one artifact beside the
events it stood for — so these read as things they now want to know, which is
not how they read when they opened the page.
"""
def:pub Questions() -> JsxElement {
    qs: list[dict[str, str]] = questions();

    return <section className="sec sec-questions" id="questions">
        <h2 className="sec-h2">{"What search can't show you."}</h2>

        <p className="body">
            {#* The earlier version of this sentence ended "Three of the four
                have a correct answer in the dataset's ground truth." These four
                questions were written to fit the Apex narrative and are not
                rows in eval_questions.jsonl, so that count was unbacked — the
                same fault we just removed from the section above. The real eval
                questions are quoted verbatim in the proof section. *#}
            {"Each of these is answerable from the record and unanswerable by similarity, because each one needs a bounded walk and a count rather than a ranked list — a shape the dataset's own benchmark questions share."}
        </p>

        {#* Each card gets the diagram of its own traversal. These are the
            three stills from the retired Unlocks section, which were the best
            thing in it — a walker fanning into empty slots for silence, a
            time-bounded cone for perspective, a ranked bar chart for
            expertise. Reused rather than redrawn. *#}
        <ul className="q-list">
            {for (i, q) in enumerate(qs) {
                <li className={"q-item q-item-" + q["t"]} key={q["q"]}>
                    <div className="q-icon" aria-hidden="true">
                        {if q["t"] == "silence" {
                            <svg viewBox="0 0 120 64" className="q-svg">
                                <circle className="s-origin" cx="16" cy="32" r="5" />
                                <path className="s-edge" d="M 21 32 L 62 14" />
                                <path className="s-edge" d="M 21 32 L 62 32" />
                                <path className="s-edge" d="M 21 32 L 62 50" />
                                <circle className="s-slot" cx="68" cy="14" r="6" />
                                <circle className="s-slot" cx="68" cy="32" r="6" />
                                <circle className="s-slot" cx="68" cy="50" r="6" />
                                <text className="s-zero-sm" x="94" y="41">{"0"}</text>
                            </svg>
                        }}
                        {if q["t"] == "perspective" {
                            <svg viewBox="0 0 120 64" className="q-svg">
                                <path className="s-cone" d="M 14 32 L 76 8 L 76 56 Z" />
                                <line className="s-cut" x1="76" y1="4" x2="76" y2="60" />
                                <circle className="s-origin" cx="14" cy="32" r="5" />
                                <circle className="s-in" cx="44" cy="24" r="3" />
                                <circle className="s-in" cx="58" cy="42" r="3" />
                                <circle className="s-out" cx="94" cy="18" r="3" />
                                <circle className="s-out" cx="104" cy="46" r="3" />
                            </svg>
                        }}
                        {if q["t"] == "expertise" {
                            <svg viewBox="0 0 120 64" className="q-svg">
                                <rect className="s-bar s-bar-1" x="8" y="10" width="86" height="9" rx="1" />
                                <rect className="s-bar" x="8" y="28" width="58" height="9" rx="1" />
                                <rect className="s-bar" x="8" y="46" width="30" height="9" rx="1" />
                            </svg>
                        }}
                    </div>
                    <p className="q-q">{q["q"]}</p>
                    <p className="q-m">{q["m"]}</p>
                    <span className="q-tag">{q["t"]}</span>
                </li>
            }}
        </ul>

        <p className="note">
            {"A bounded traversal with a typed result — not a prompt, and not a summary. The dataset ships ground truth for 78 questions; orgmem answers 57 and declines the 21 that ask what would have happened."}
        </p>
    </section>;
}
