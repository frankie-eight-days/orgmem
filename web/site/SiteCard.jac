"""Light-theme source chrome for the transformation cards.

The app's cards (`web/card/*.jac`) render each artifact in the chrome it came
from — a Slack thread looks like Slack, a Jira ticket looks like Jira. That is
the right idea for this section too, but those components cannot be reused
directly here: they carry their palette as *inline* styles from `CARD_BG` /
`CARD_FG` / `CARD_LINE`, which are dark and which no stylesheet on this side can
override, since inline styles win the cascade. Re-themeing them would mean
editing `web/card/`, which this worktree does not own.

So this module reproduces the *chrome* — the parts that say "this is Slack" and
"this is Jira" — against the site's cream palette, and leaves the body rows to
the caller. The caller keeps rendering its own rows because the parse animation
in `Transform.jac` needs per-run spans it controls; handing the body over would
mean handing the animation over with it.

Everything here is presentational. `kind` is one of the six keys in
`corpus.jac`'s `KIND_LABEL`; an unrecognised kind degrades to a plain header
rather than throwing, because a card missing its chrome is a much smaller
failure on stage than a card missing entirely.

`cl` is load-bearing on the helpers: they return `str`, not `JsxElement`, so
without it the codespace pass leaves them on the server and every card render
becomes an RPC round trip.
"""

"""Initials for an avatar chip — one letter, which is all that fits at 18px."""
cl def:pub initial(name: str) -> str {
    if len(name) == 0 { return "?"; }
    return name[0:1];
}

"""A stable hue per name so the same person is the same colour on every card.

Summed code points rather than a hash function: the corpus has 46 people and
this only has to be stable within one page, not collision-free.
"""
cl def:pub avatar_hue(name: str) -> int {
    total: int = 0;
    i: int = 0;
    while i < len(name) {
        total = total + ord(name[i:i + 1]);
        i = i + 1;
    }
    return (total * 47) % 360;
}

cl def:pub avatar_style(name: str) -> dict[str, str] {
    h: int = avatar_hue(name);
    return {
        "background": "hsl(" + str(h) + " 46% 92%)",
        "color": "hsl(" + str(h) + " 52% 32%)"
    };
}

"""The label that sits in the source badge — the product, not the node type."""
cl def:pub source_name(kind: str) -> str {
    names: dict[str, str] = {
        "slack": "Slack",
        "jira": "Jira",
        "confluence": "Confluence",
        "zendesk": "Zendesk",
        "zoom": "Zoom",
        "pr": "GitHub"
    };
    if kind in names { return names[kind]; }
    return kind;
}

"""Per-source accent, used for the badge and the top rule.

These are the six source colours desaturated toward the cream ground. The app
uses fully saturated brand colours on near-black; the same values on `#FBFAF7`
read as clip art, so each is pulled toward its own muted form.
"""
cl def:pub source_tint(kind: str) -> str {
    tints: dict[str, str] = {
        "slack": "#4A154B",
        "jira": "#1F5FBF",
        "confluence": "#2A6BB8",
        "zendesk": "#0F5E56",
        "zoom": "#2166C4",
        "pr": "#3E3B58"
    };
    if kind in tints { return tints[kind]; }
    return "#6E675F";
}

cl def:pub tint_style(kind: str) -> dict[str, str] {
    return {"color": source_tint(kind)};
}

cl def:pub rule_style(kind: str) -> dict[str, str] {
    return {"background": source_tint(kind)};
}

"""The status word a ticket-like artifact carries, or empty for the rest."""
cl def:pub status_of(kind: str, meta: str) -> str {
    if kind == "jira" {
        if "Open" in meta { return "Open"; }
        return "";
    }
    if kind == "zendesk" {
        if "urgent" in meta { return "Urgent"; }
        return "";
    }
    if kind == "pr" {
        if "merged" in meta { return "Merged"; }
        return "";
    }
    return "";
}

"""The chrome around one artifact. `children` are the caller's body rows.

`style` exists for the transformation section, which blurs each card as it
dissolves into the graph. That has to land on the same element as the card's own
box — a wrapper div would blur the chrome and the body at different times
because the two would no longer share a stacking context.
"""
def:pub SiteCard(kind: str, head: str, meta: str, people: list[str],
                 style: dict[str, str] = {}, children: any = None) -> JsxElement {

    status: str = status_of(kind, meta);

    return <article className={"card card-" + kind} style={style}>

        {#* A hairline in the source's colour, the way every one of these tools
            marks its own surface. Cheaper than a full brand header and it
            survives being scaled to 40% during the crystallise stage. *#}
        <span className="card-rule" style={rule_style(kind)} aria-hidden="true"></span>

        <div className="card-chrome">
            <span className="card-source" style={tint_style(kind)}>{source_name(kind)}</span>
            <span className="card-head">{head}</span>
            {if status != "" {
                <span className={"card-status card-status-" + kind}>{status}</span>
            }}
        </div>

        <div className="card-sub">
            <div className="card-faces" aria-hidden="true">
                {for (k, who) in enumerate(people) {
                    <span className="face" key={str(k)} style={avatar_style(who)}>
                        {initial(who)}
                    </span>
                }}
            </div>
            <span className="card-meta">{meta}</span>
        </div>

        {children}
    </article>;
}
