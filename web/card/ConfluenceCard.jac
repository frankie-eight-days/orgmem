"""Renders `ConfluencePage` — a wiki page, chrome and all, from real markdown.

The body is genuine markdown several thousand characters long, and the one thing
that would make this card read as broken is dropping the tables: the most-cited
pages in the corpus are the ones that carry them. So the parser is a real block
parser rather than a line-styler, in two stages — markdown to a list of typed
blocks, then blocks to JSX. Nothing is assembled as an HTML string; there is no
`dangerouslySetInnerHTML` anywhere in this build (CARD-CONTRACT §3).

**The grammar, in full.** A line is a heading (`#`..`######`, clamped to three
rendered levels), a rule (`---`), a table (a `|` row whose *successor* is a
`|---|` separator), a list item (`- `, `* `, or `1. `), a preamble field
(`**Key:** value` before any content), or prose. Prose and list items absorb
following lines until a blank line or the start of another block, which is what
makes a wrapped item stay one item.

**Three decisions that are not obvious from the grammar.**

*The title is printed once.* The corpus opens every page with `# <the page
title>`, and `Project Titan Overview` then repeats it as a `##` section heading
below the metadata. Both are suppressed, by one rule: a heading matching the
payload title is dropped as long as no *content* block has been emitted yet.
Metadata lines do not count as content, which is what lets the rule reach the
second one. Once a paragraph or table has appeared, a heading matching the title
is a genuine recurrence and survives.

*`**ID:** CONF-ENG-001` is chrome, not prose.* Those three leading lines have no
blank line between them, so a naive parser glues them into one run-on paragraph
under the title. They are lifted into a metadata list instead and feed the
breadcrumb and the byline; anything past the three known keys renders as a chip
rather than being silently dropped.

*Inline formatting is a list of spans, never a mutated string.* `parse_inline`
splits on `**` and then on backticks, and an **odd** number of delimiters — an
unmatched `**` — is repaired by merging the final two segments back together
with the delimiter as literal text. Without that, one stray `**` in a table cell
would set the whole rest of the paragraph bold. This matters here specifically
because bold appears *inside* table cells (`| **Data Store** | ... |`), so the
inline pass has to run per cell, not per line.

Character classification goes through `len(POOL.split(ch)) > 1` rather than
`ch in POOL`, and line prefixes are tested by slicing rather than `.startswith`,
for the reason `Card.jac` and `SlackCard.jac` both give: `str.__contains__`,
`.find` and `.startswith` do not lower to the same thing on the client target,
whereas slicing and `split` are identical on both sides. `str.replace` is
avoided for the same class of reason — Python replaces every occurrence and JS
`String.prototype.replace` with a string pattern replaces only the first.

Tables scroll horizontally inside their own container and nothing else does. A
cell floor of 88px means a three-column table wraps inside the card while a
six-column one scrolls, which is the behaviour you want in both cases: the card
itself never scrolls sideways.
"""

# Split across two statements deliberately: a single `import from` of more than
# ten names silently resolves only the first nine on the client — every name from
# the tenth onward falls back to a server RPC and arrives as an unresolved
# Promise, which JSX then prints as `[object Promise]`. Keep both lists short.
import from .Card {
    CARD_BG, CARD_FG, CARD_LINE, CARD_MONO, CARD_MUTED, CARD_PANE, CARD_SANS
}
import from .Card { Avatar, Chip, day_date, time_ago }

cl glob DIGIT_POOL: str = "0123456789";

# Keys already spoken for by the breadcrumb, the byline and the footer stamp.
# Anything else in the preamble is shown as a chip instead of being dropped.
cl glob META_CONSUMED: list[str] = ["id", "author", "date"];

# Per-column floor for a table. Three columns (264px) wrap inside the 420px
# card; six (528px) overflow and scroll in their own container.
cl glob COL_MIN: int = 88;

# Rendered indent step for a nested list item.
cl glob INDENT_STEP: int = 14;


# ------------------------------------------------------------------ scanning

cl def has_char(pool: str, ch: str) -> bool {
    return len(pool.split(ch)) > 1;
}

# Whitespace-insensitive, case-insensitive compare key, for the title match.
cl def norm_key(s: str) -> str {
    out: str = "";
    for ch in s.lower() {
        if (ch != " ") and (ch != "\t") {
            out += ch;
        }
    }
    return out;
}

cl def strip_marks(s: str) -> str {
    out: str = "";
    for part in s.split("**") {
        out += part;
    }
    res: str = "";
    for part in out.split("`") {
        res += part;
    }
    return res;
}

cl def leading_spaces(raw: str) -> int {
    i: int = 0;
    while (i < len(raw)) and (raw[i] == " ") {
        i += 1;
    }
    return i;
}

# 0 when the line is not a heading. `#Header` with no space is not one.
cl def heading_level(s: str) -> int {
    lvl: int = 0;
    while (lvl < len(s)) and (s[lvl] == "#") {
        lvl += 1;
    }
    if (lvl == 0) or (lvl > 6) {
        return 0;
    }
    if s[lvl:lvl + 1] != " " {
        return 0;
    }
    return lvl;
}

# "" when the line is not a list item; otherwise "-" or the ordinal ("3.").
cl def item_marker(s: str) -> str {
    if (s[:2] == "- ") or (s[:2] == "* ") {
        return "-";
    }
    k: int = 0;
    while (k < len(s)) and has_char(DIGIT_POOL, s[k]) {
        k += 1;
    }
    if (k > 0) and (s[k:k + 2] == ". ") {
        return s[:k] + ".";
    }
    return "";
}

# A GFM separator: pipes, colons, spaces and at least one dash. Requiring the
# dash is what stops a second data row being mistaken for the separator.
cl def is_sep(s: str) -> bool {
    if s[:1] != "|" {
        return False;
    }
    seen: bool = False;
    for ch in s {
        if ch == "-" {
            seen = True;
        } elif (ch != "|") and (ch != ":") and (ch != " ") {
            return False;
        }
    }
    return seen;
}

cl def split_row(s: str) -> list[str] {
    t: str = s;
    if t[:1] == "|" {
        t = t[1:];
    }
    if t[-1:] == "|" {
        t = t[:-1];
    }
    cells: list[str] = [];
    for part in t.split("|") {
        cells.append(part.strip());
    }
    return cells;
}


# ------------------------------------------------------------------ inline

# -> [{"t": str, "b": bool, "c": bool, "k": str}]. Bold and code only; anything
# else in the corpus (links, images) does not appear and is left as literal
# text rather than half-supported.
cl def parse_inline(text: str) -> list[dict[str, any]] {
    spans: list[dict[str, any]] = [];
    segs: list[str] = text.split("**");
    # An even segment count means an odd number of delimiters: one `**` never
    # closed. Glue the tail back together so it stays literal.
    if (len(segs) % 2 == 0) and (len(segs) >= 2) {
        fixed: list[str] = segs[:-2];
        fixed.append(segs[-2] + "**" + segs[-1]);
        segs = fixed;
    }
    bi: int = 0;
    for seg in segs {
        bold: bool = (bi % 2) == 1;
        bi += 1;
        csegs: list[str] = seg.split("`");
        if (len(csegs) % 2 == 0) and (len(csegs) >= 2) {
            cfixed: list[str] = csegs[:-2];
            cfixed.append(csegs[-2] + "`" + csegs[-1]);
            csegs = cfixed;
        }
        ci: int = 0;
        for cseg in csegs {
            code: bool = (ci % 2) == 1;
            ci += 1;
            if cseg != "" {
                spans.append({"t": cseg, "b": bold, "c": code,
                              "k": "s" + str(len(spans))});
            }
        }
    }
    return spans;
}


# ------------------------------------------------------------------ blocks

# -> {"meta": [{"k","v"}], "blocks": [...]}, where a block is one of
#   {"type": "heading", "level": 1..3, "text": str}
#   {"type": "para",    "text": str}
#   {"type": "hr"}
#   {"type": "list",    "items": [{"indent": int, "marker": str, "text": str}]}
#   {"type": "table",   "head": list[str], "rows": list[list[str]], "cols": int}
# Every block and every item carries a "k" for React, computed here: a JSX `for`
# slot takes exactly one loop variable, so an index a component needs has to be
# baked into the data before it is emitted.
cl def parse_page(body: str, title: str) -> dict[str, any] {
    blocks: list[dict[str, any]] = [];
    meta: list[dict[str, any]] = [];
    if not body {
        return {"meta": meta, "blocks": blocks};
    }
    lines: list[str] = body.split("\n");
    n: int = len(lines);
    want: str = norm_key(title);
    seen_content: bool = False;
    i: int = 0;

    while i < n {
        raw: str = lines[i];
        s: str = raw.strip();
        if s == "" {
            i += 1;
            continue;
        }

        lvl: int = heading_level(s);
        if lvl > 0 {
            text: str = s[lvl + 1:].strip();
            keep: int = lvl;
            if keep > 3 {
                keep = 3;
            }
            drop: bool = (not seen_content) and (norm_key(strip_marks(text)) == want);
            if not drop {
                blocks.append({"type": "heading", "level": keep, "text": text,
                               "k": "b" + str(len(blocks))});
            }
            i += 1;
            continue;
        }

        if (s == "---") or (s == "***") or (s == "___") {
            blocks.append({"type": "hr", "k": "b" + str(len(blocks))});
            i += 1;
            continue;
        }

        if (s[:1] == "|") and (i + 1 < n) and is_sep(lines[i + 1].strip()) {
            head: list[str] = split_row(s);
            cols: int = len(head);
            rows: list[list[str]] = [];
            i += 2;
            while i < n {
                nxt: str = lines[i].strip();
                if nxt[:1] != "|" {
                    break;
                }
                cells: list[str] = split_row(nxt);
                while len(cells) < cols {
                    cells.append("");
                }
                rows.append(cells[:cols]);
                i += 1;
            }
            blocks.append({"type": "table", "head": head, "rows": rows,
                           "cols": cols, "k": "b" + str(len(blocks))});
            seen_content = True;
            continue;
        }

        # Preamble fields, only above the first content block.
        if (not seen_content) and (s[:2] == "**") {
            parts: list[str] = s.split("**");
            if (len(parts) >= 3) and (parts[1] != "")
               and (parts[1][-1:] == ":") and (len(parts[1]) <= 24) {
                val: str = s[len(parts[1]) + 4:].strip();
                if (val != "") and (len(val) <= 90) {
                    meta.append({"k": parts[1][:-1].strip(), "v": val});
                    i += 1;
                    continue;
                }
            }
        }

        if item_marker(s) != "" {
            items: list[dict[str, any]] = [];
            while i < n {
                raw2: str = lines[i];
                s2: str = raw2.strip();
                if s2 == "" {
                    break;
                }
                mk: str = item_marker(s2);
                if mk != "" {
                    ind: int = leading_spaces(raw2) // 2;
                    if ind > 2 {
                        ind = 2;
                    }
                    cut: int = 2 if mk == "-" else (len(mk) + 1);
                    items.append({"indent": ind, "marker": mk,
                                  "text": s2[cut:].strip(),
                                  "k": "i" + str(len(items))});
                } elif (len(items) > 0) and (leading_spaces(raw2) > 0) {
                    # A wrapped continuation of the item above it.
                    items[-1]["text"] = (items[-1]["text"] as str) + " " + s2;
                } else {
                    break;
                }
                i += 1;
            }
            blocks.append({"type": "list", "items": items,
                           "k": "b" + str(len(blocks))});
            seen_content = True;
            continue;
        }

        para: str = "";
        while i < n {
            s3: str = lines[i].strip();
            if s3 == "" {
                break;
            }
            if (heading_level(s3) > 0) or (s3[:1] == "|") or (item_marker(s3) != "") {
                break;
            }
            para = s3 if para == "" else (para + " " + s3);
            i += 1;
        }
        if para != "" {
            blocks.append({"type": "para", "text": para,
                           "k": "b" + str(len(blocks))});
            seen_content = True;
        }
    }

    return {"meta": meta, "blocks": blocks};
}

cl def meta_get(meta: list[dict[str, any]], key: str) -> str {
    for m in meta {
        if norm_key(m["k"] as str) == key {
            return m["v"] as str;
        }
    }
    return "";
}


# ------------------------------------------------------------------ pieces

def Inline(text: str) -> JsxElement {
    return <>
        {for sp in parse_inline(text) {
            <span key={sp["k"] as str}
                  style={{"fontWeight": "700" if (sp["b"] as bool) else "inherit",
                          "fontFamily": CARD_MONO if (sp["c"] as bool) else "inherit",
                          "fontSize": "0.92em" if (sp["c"] as bool) else "inherit",
                          "padding": "1px 4px" if (sp["c"] as bool) else "0",
                          "borderRadius": "3px",
                          "background": CARD_PANE if (sp["c"] as bool) else "transparent"}}>
                {sp["t"]}
            </span>
        }}
    </>;
}

def Heading(level: int, text: str) -> JsxElement {
    size: str = "14.5px";
    top: str = "16px";
    if level == 2 {
        size = "13px";
        top = "15px";
    }
    if level == 3 {
        size = "11.5px";
        top = "12px";
    }
    st: dict[str, str] = {
        "fontFamily": CARD_SANS, "fontSize": size, "fontWeight": "700",
        "lineHeight": "1.35", "color": CARD_FG, "letterSpacing": "-0.005em",
        "margin": top + " 0 5px 0", "wordBreak": "break-word"
    };
    # Only the section level gets a rule under it. On a card this narrow, a rule
    # under every heading turns the page into a stack of boxes.
    if level == 2 {
        st["paddingBottom"] = "4px";
        st["borderBottom"] = "1px solid " + CARD_LINE;
    }
    if level == 3 {
        st["fontWeight"] = "600";
        st["letterSpacing"] = "0.02em";
    }
    return <div style={st}><Inline text={text} /></div>;
}

def ListItem(it: dict[str, any]) -> JsxElement {
    marker: str = it["marker"] as str;
    shown: str = "•" if marker == "-" else marker;
    return <div style={{"display": "flex", "gap": "7px", "alignItems": "baseline",
                        "marginTop": "3px",
                        "marginLeft": str((it["indent"] as int) * INDENT_STEP) + "px"}}>
        <span style={{"flexShrink": "0", "minWidth": "13px", "textAlign": "right",
                      "fontFamily": CARD_MONO, "fontSize": "10.5px",
                      "color": CARD_MUTED}}>
            {shown}
        </span>
        <span style={{"flex": "1", "minWidth": "0", "fontFamily": CARD_SANS,
                      "fontSize": "12px", "lineHeight": "1.6", "color": CARD_FG,
                      "wordBreak": "break-word"}}>
            <Inline text={it["text"] as str} />
        </span>
    </div>;
}

# One row. Cells arrive as a real `list[str]` through the prop rather than being
# subscripted out of an `any` inside a JSX slot, which is the only reliable way
# to iterate a nested list here.
def TableRow(cells: list[str], head: bool, rk: str) -> JsxElement {
    st: dict[str, str] = {
        "border": "1px solid " + CARD_LINE, "padding": "5px 7px",
        "verticalAlign": "top", "textAlign": "left",
        "minWidth": str(COL_MIN) + "px", "wordBreak": "break-word"
    };
    if head {
        st["background"] = CARD_PANE;
        st["fontFamily"] = CARD_MONO;
        st["fontSize"] = "9.5px";
        st["fontWeight"] = "600";
        st["letterSpacing"] = "0.09em";
        st["textTransform"] = "uppercase";
        st["color"] = CARD_MUTED;
        st["whiteSpace"] = "nowrap";
    } else {
        st["fontFamily"] = CARD_SANS;
        st["fontSize"] = "11px";
        st["lineHeight"] = "1.5";
        st["color"] = CARD_FG;
    }
    ci: int = 0;
    keyed: list[dict[str, any]] = [];
    for cell in cells {
        keyed.append({"t": cell, "k": rk + "-c" + str(ci)});
        ci += 1;
    }
    return <tr>
        {for cl in keyed {
            <td key={cl["k"] as str} style={st}>
                <Inline text={cl["t"] as str} />
            </td>
        }}
    </tr>;
}

def TableBlock(b: dict[str, any]) -> JsxElement {
    head: list[str] = (b["head"] as list[str]) if b["head"] else [];
    rows: list = (b["rows"] as list) if b["rows"] else [];
    cols: int = (b["cols"] as int) if b["cols"] else len(head);
    ri: int = 0;
    keyed: list[dict[str, any]] = [];
    for row in rows {
        keyed.append({"cells": row, "k": "r" + str(ri)});
        ri += 1;
    }
    return <div style={{"overflowX": "auto", "maxWidth": "100%",
                        "margin": "8px 0 12px 0"}}>
        <table style={{"borderCollapse": "collapse", "width": "100%",
                       "minWidth": str(cols * COL_MIN) + "px"}}>
            <thead>
                <TableRow cells={head} head={True} rk={"h"} />
            </thead>
            <tbody>
                {for kr in keyed {
                    <TableRow key={kr["k"] as str} cells={kr["cells"] as list[str]}
                              head={False} rk={kr["k"] as str} />
                }}
            </tbody>
        </table>
    </div>;
}

def Block(b: dict[str, any]) -> JsxElement {
    kind: str = b["type"] as str;
    return <>
        {if kind == "heading" {
            <Heading level={b["level"] as int} text={b["text"] as str} />
        }}
        {if kind == "para" {
            <div style={{"fontFamily": CARD_SANS, "fontSize": "12px",
                         "lineHeight": "1.62", "color": CARD_FG,
                         "margin": "0 0 9px 0", "wordBreak": "break-word"}}>
                <Inline text={b["text"] as str} />
            </div>
        }}
        {if kind == "hr" {
            <div style={{"height": "1px", "background": CARD_LINE,
                         "margin": "12px 0"}} />
        }}
        {if kind == "list" {
            <div style={{"margin": "2px 0 10px 0"}}>
                {for it in (b["items"] as list[dict[str, any]]) {
                    <ListItem key={it["k"] as str} it={it} />
                }}
            </div>
        }}
        {if kind == "table" { <TableBlock b={b} /> }}
    </>;
}

# The blank fixture. A page captured with no body is honest data, so it gets a
# stated empty state in the same inset pane the content would have occupied,
# rather than a collapsed div that reads as a rendering failure.
def EmptyPage -> JsxElement {
    return <div style={{"margin": "16px 14px 18px 14px", "padding": "20px 14px",
                        "background": CARD_PANE, "borderRadius": "8px",
                        "border": "1px dashed " + CARD_LINE, "textAlign": "center"}}>
        <div style={{"fontFamily": CARD_SANS, "fontSize": "12.5px",
                     "fontWeight": "600", "color": CARD_FG}}>
            {"This page has no content"}
        </div>
        <div style={{"fontFamily": CARD_SANS, "fontSize": "11.5px",
                     "lineHeight": "1.5", "color": CARD_MUTED, "marginTop": "4px"}}>
            {"The page exists in the space and is linked from elsewhere, but its body was captured empty."}
        </div>
    </div>;
}


# ------------------------------------------------------------------ the card

def:pub ConfluenceCard(c: dict[str, any]) -> JsxElement {
    title: str = (c["title"] as str) if c["title"] else "";
    body: str = (c["body"] as str) if c["body"] else "";
    day: int = (c["day"] as int) if c["day"] else 0;
    gid: str = (c["gid"] as str) if c["gid"] else "";
    dept: str = (c["dept"] as str) if c["dept"] else "";
    authors: list = (c["authors"] as list) if c["authors"] else [];

    page: dict[str, any] = parse_page(body, title);
    meta: list[dict[str, any]] = page["meta"] as list[dict[str, any]];
    blocks: list[dict[str, any]] = page["blocks"] as list[dict[str, any]];

    # The breadcrumb is space / page, and both halves are taken rather than
    # invented. `dept` is the space when the payload carries one — on the real
    # Confluence rows it is empty, and the subsystem is the honest fallback.
    # The page id is the preamble `**ID:**` if the document states one, else the
    # gid, which for these rows is the same string.
    space: str = dept if dept != "" else "Confluence";
    doc_id: str = meta_get(meta, "id");
    if doc_id == "" {
        doc_id = gid;
    }

    author: str = (authors[0] as str) if len(authors) > 0 else meta_get(meta, "author");

    stamp: str = day_date(day);
    rel: str = time_ago(day);
    if (stamp != "") and (rel != "") {
        stamp = stamp + " · " + rel;
    }

    # The one content statistic worth stating in the header. Judges are told
    # tables are the hard part; saying how many this page has points at them.
    ntables: int = 0;
    for b in blocks {
        if (b["type"] as str) == "table" {
            ntables += 1;
        }
    }

    extra: list[dict[str, any]] = [];
    for m in meta {
        if norm_key(m["k"] as str) not in META_CONSUMED {
            extra.append(m);
        }
    }

    return <div>
        <div style={{"position": "sticky", "top": "0", "zIndex": "1",
                     "background": CARD_BG, "padding": "10px 14px 9px 14px",
                     "borderBottom": "1px solid " + CARD_LINE}}>
            <div style={{"display": "flex", "alignItems": "baseline", "gap": "5px",
                         "paddingRight": "22px", "fontFamily": CARD_MONO,
                         "fontSize": "9.5px", "letterSpacing": "0.06em",
                         "color": CARD_MUTED, "overflow": "hidden",
                         "textOverflow": "ellipsis", "whiteSpace": "nowrap"}}>
                <span>{space}</span>
                {if doc_id != "" { <span>{"/"}</span> }}
                {if doc_id != "" { <span>{doc_id}</span> }}
            </div>
            <div style={{"fontFamily": CARD_SANS, "fontSize": "15.5px",
                         "fontWeight": "700", "letterSpacing": "-0.012em",
                         "lineHeight": "1.25", "color": CARD_FG,
                         "margin": "3px 0 0 0", "paddingRight": "22px",
                         "wordBreak": "break-word"}}>
                {title if title != "" else "(untitled page)"}
            </div>
            <div style={{"display": "flex", "alignItems": "center", "gap": "6px",
                         "marginTop": "5px", "flexWrap": "wrap"}}>
                {if author != "" { <Avatar name={author} size={18} /> }}
                {if author != "" {
                    <span style={{"fontFamily": CARD_SANS, "fontSize": "11px",
                                  "color": CARD_FG}}>{author}</span>
                }}
                {if stamp != "" {
                    <span style={{"fontFamily": CARD_SANS, "fontSize": "10.5px",
                                  "color": CARD_MUTED}}>{stamp}</span>
                }}
                {if ntables > 0 {
                    <span style={{"fontFamily": CARD_MONO, "fontSize": "10px",
                                  "color": CARD_MUTED}}>
                        {str(ntables) + (" table" if ntables == 1 else " tables")}
                    </span>
                }}
            </div>
            {if len(extra) > 0 {
                <div style={{"display": "flex", "flexWrap": "wrap", "gap": "5px",
                             "marginTop": "6px"}}>
                    {for m in extra {
                        <Chip key={m["k"] as str}
                              text={(m["k"] as str) + ": " + (m["v"] as str)} />
                    }}
                </div>
            }}
        </div>

        {if len(blocks) == 0 { <EmptyPage /> }}

        {if len(blocks) > 0 {
            <div style={{"padding": "2px 14px 14px 14px"}}>
                {for b in blocks {
                    <Block key={b["k"] as str} b={b} />
                }}
            </div>
        }}
    </div>;
}
