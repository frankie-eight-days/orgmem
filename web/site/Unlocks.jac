"""Sections 4 and 5 — the three questions, and the measured numbers.

The three stills are small and structural rather than illustrative: each one is
a diagram of the traversal that answers its question, so the panel says the same
thing as the sentence under it in a different notation.
"""

#*
Retired when the site moved to the observability framing.

The three questions were posed as trivia — "was a postmortem ever written?" with
no subject and nobody asking. They now live in `Dataset.jac`, attached to Apex
Athletics and to specific days, which is what they were missing. The mechanism
lines survived the move almost verbatim; it was only ever the framing that was
weak.

Commented rather than deleted: the three stills are hand-tuned SVG and their
`.s-*` rules are still in `styles.jac`. To restore, uncomment and re-add
`Unlocks` to `Landing.jac`.

"""One of the three questions no search box can answer."""
def:pub Unlock(title: str, question: str, mechanism: str, children: any = None) -> JsxElement {
    return <article className="unlock">
        <div className="unlock-still" aria-hidden="true">{children}</div>
        <h3 className="unlock-h3">{title}</h3>
        <p className="unlock-q">{question}</p>
        <p className="unlock-m">{mechanism}</p>
    </article>;
}

def:pub Unlocks() -> JsxElement {
    return <section className="sec sec-unlocks">
        <h2 className="sec-h2">{"Three questions no search box can answer."}</h2>

        <div className="unlock-row">
            <Unlock title="Silence"
                    question="Was a postmortem ever written after that incident?"
                    mechanism="Walk from the trigger. Count the expected responses. Zero is the answer.">
                <svg viewBox="0 0 200 120" className="still">
                    <circle className="s-origin" cx="34" cy="60" r="6" />
                    <path className="s-edge" d="M 40 60 L 96 32" />
                    <path className="s-edge" d="M 40 60 L 96 60" />
                    <path className="s-edge" d="M 40 60 L 96 88" />
                    <circle className="s-slot" cx="104" cy="32" r="7" />
                    <circle className="s-slot" cx="104" cy="60" r="7" />
                    <circle className="s-slot" cx="104" cy="88" r="7" />
                    <text className="s-zero" x="146" y="70">{"0"}</text>
                </svg>
            </Unlock>

            <Unlock title="Perspective"
                    question="Could Felix have known about this on day 32?"
                    mechanism="Reachability from a person, bounded by time and access. No model required.">
                <svg viewBox="0 0 200 120" className="still">
                    <path className="s-cone" d="M 26 60 L 128 14 L 128 106 Z" />
                    <line className="s-cut" x1="128" y1="6" x2="128" y2="114" />
                    <circle className="s-origin" cx="26" cy="60" r="6" />
                    <circle className="s-in" cx="72" cy="46" r="3.5" />
                    <circle className="s-in" cx="94" cy="76" r="3.5" />
                    <circle className="s-in" cx="108" cy="40" r="3.5" />
                    <circle className="s-out" cx="152" cy="34" r="3.5" />
                    <circle className="s-out" cx="168" cy="82" r="3.5" />
                    <text className="s-tick" x="132" y="112">{"day 32"}</text>
                </svg>
            </Unlock>

            <Unlock title="Expertise"
                    question="Who actually knows TitanDB?"
                    mechanism="Ranked from demonstrated engagement. Bus factor included.">
                <svg viewBox="0 0 200 120" className="still">
                    <rect className="s-bar s-bar-1" x="26" y="24" width="132" height="12" rx="1" />
                    <rect className="s-bar s-bar-2" x="26" y="52" width="96" height="12" rx="1" />
                    <rect className="s-bar s-bar-3" x="26" y="80" width="54" height="12" rx="1" />
                    <text className="s-name" x="26" y="20">{"Janice"}</text>
                    <text className="s-name" x="26" y="48">{"Morgan"}</text>
                    <text className="s-name" x="26" y="76">{"Felix"}</text>
                </svg>
            </Unlock>
        </div>
    </section>;
}

*#

"""Four real SILENCE questions, verbatim from `data/eval_questions.jsonl`.

`question_text` and `ground_truth.answer` are copied exactly — a reader can grep
any of these strings in the dataset and find the row. The `why` column is
orgforge's own `absence_type`, rendered readable: `state_machine_confirmed`
means the simulator confirmed the follow-up never happened,
`state_machine_present` means it did.

Two true and two false on purpose. The whole argument for measuring SILENCE is
that a system which always answers "no, nothing was written" looks excellent on
the twelve noes and fails all fifteen yeses, which is why 55% is the number to
beat rather than 0%.
"""
cl glob SILENCE_SAMPLES: list[dict[str, str]] = [
    {
        "q": "Was a Salesforce risk flag on the related deals created in response to the incident on Day 8 involving Jax, Kaitlyn?",
        "a": "false",
        "why": "confirmed absent"
    },
    {
        "q": "Was a postmortem document created in response to the incident on Day 25 involving Deepa and Alex?",
        "a": "true",
        "why": "present in the record"
    },
    {
        "q": "Was a Zendesk support ticket created as a result of the routing of the customer email on Day 15 involving Metro United FC, Marcus?",
        "a": "false",
        "why": "confirmed absent"
    },
    {
        "q": "Was a Confluence documentation page created in response to the knowledge gap detected on Day 38 involving Morgan, specifically regarding kubernetes-deploy, terraform?",
        "a": "true",
        "why": "present in the record"
    }
];

cl def:pub silence_samples() -> list[dict[str, str]] { return SILENCE_SAMPLES; }

"""Section 5 — the numbers, and what they don't cover."""
def:pub Proof() -> JsxElement {
    return <section className="sec sec-proof">
        <h2 className="sec-h2">{"Measured, not claimed."}</h2>

        {#* The result comes first now. The corpus size moved up into the
            transformation section, where it is the point being made; repeating
            it here spent two of four slots restating throughput when the
            interesting number is accuracy against ground truth. *#}
        <dl className="stats">
            <div className="stat">
                <dt className="stat-n">{"94.7%"}</dt>
                <dd className="stat-l">{"overall · 54 of 57 scored questions"}</dd>
            </div>
            <div className="stat">
                <dt className="stat-n stat-n-accent">{"96.3%"}</dt>
                <dd className="stat-l">{"on silence questions · 55.6% for a constant answer"}</dd>
            </div>
            <div className="stat">
                <dt className="stat-n">{"76,000+"}</dt>
                <dd className="stat-l">{"typed edges"}</dd>
            </div>
            <div className="stat">
                <dt className="stat-n">{"6.4s"}</dt>
                <dd className="stat-l">{"cold build"}</dd>
            </div>
        </dl>

        <p className="body">
            {"The dataset ships 27 SILENCE questions — did the expected follow-up ever happen — near-evenly split 15 yes / 12 no, so a constant answer scores 55%. These are four of them, verbatim from eval_questions.jsonl, with the ground truth orgforge ships alongside."}
        </p>

        {#* Real questions, not paraphrases. A reader who opens the dataset can
            grep any of these `question_text` strings and find it. The mix of
            true and false is the point: a system that always says "no
            postmortem" scores well on the noes and fails every yes. *#}
        <ul className="gt-list">
            {for (i, q) in enumerate(silence_samples()) {
                <li className={"gt" + (" gt-no" if q["a"] == "false" else "")} key={str(i)}>
                    <p className="gt-q">{q["q"]}</p>
                    <p className="gt-a">
                        <span className="gt-badge">{"ground truth"}</span>
                        <span className="gt-val">{q["a"]}</span>
                        <span className="gt-why">{q["why"]}</span>
                    </p>
                </li>
            }}
        </ul>

        <blockquote className="pull">
            <p>{"Flat retrieval scores about 55% on those — and we can tell you in advance which ones it fails."}</p>
            <p>{"It fails the ones where the thing does not exist."}</p>
        </blockquote>

        <p className="note">
            {"Built in one day on a public dataset. The structural layer is deterministic; the inferred knowledge layer is early."}
        </p>
    </section>;
}
