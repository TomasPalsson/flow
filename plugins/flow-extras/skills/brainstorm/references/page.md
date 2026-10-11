---
name: page
description: The brainstorm page contract - final.json fields, the card frame, the picture catalog and the SVG drawing rules. Read by picture agents and before running assemble.mjs or check.mjs.
---

# The brainstorm page

One card per idea, the same frame on every card, so the reader learns how to read a card once. Each card has 2 to 4 small pictures. Each picture proves one claim. There are no charts, no maps of all ideas, no graphs, no filters.

`scripts/assemble.mjs` writes the page from `final.json` and the SVG files. A model never writes the page HTML. `scripts/check.mjs` checks it.

## final.json

```json
{
  "repo": "prr",
  "key": "9f2c1a77",
  "generated_at": "2026-10-11",
  "about": "prr is a command-line tool that tells developers which pull request their branch belongs to.",
  "headline": "prr guesses where you are; these ideas make it look first.",
  "ideas": [{
    "id": "i3",
    "slot": "safe | stretch | wild | remove | fix",
    "title": "Show why prr thinks there is no PR",
    "sentence": "When gh is logged out, prr says so, instead of saying no PR exists.",
    "for_whom": "anyone whose gh login expired",
    "why_here": "Judges gave it the top value score; the bug is at src/main.rs:338.",
    "first_test": "Log out of gh, run prr status, read the message.",
    "gives_up": "One more branch in pr_exists.",
    "size": { "blocks": 1, "words": "about an hour" },
    "pictures": [{ "id": "p1", "caption": "Today: logged out looks like 'no PR'.", "file": "pictures/i3-p1.svg" }],
    "words": [{ "term": "gh", "gloss": "GitHub's command-line tool" }],
    "evidence": [{ "where": "src/main.rs:338", "what": "pr_exists returns false on any gh error" }],
    "risks": ["gh error text changes between versions"],
    "needs": []
  }],
  "dropped": {
    "obvious": ["Add integration tests", "Improve the README"],
    "dead": [{ "title": "Add a --json flag", "why": "already exists: src/main.rs:88" }],
    "count": 31
  }
}
```

- `about` (optional) = one sentence: what the project is and who uses it. The page prints it right under the title, before the headline, so a cold reader knows what this is about.
- `more_fixes` (optional) = array of `{title, where, what}` for small real bugs found and checked in the code but not worth a card: `title` in plain words, <= 12 words; `where` = `path:line`; `what` = one sentence. When non-empty the page prints a muted "More bugs worth fixing" section (closed list) after the cards and before "What we left out". Anything but an array of objects with those three non-empty strings fails assemble with exit 3.
- `slot` words on the page: safe = "Safe bet", stretch = "Stretch", wild = "Wild card", remove = "Remove", fix = "Quick fix".
- `title` <= 8 words, starts with a verb. `sentence` <= 20 words, active voice, says what changes for whom.
- `size.blocks` 1 = hours, 2 = days, 3 = weeks, 0 = not sure. The page prints a fixed word per block count; `words` is kept for the record only.
- `words` = every project term or tool name a newcomer would not know, glossed in 6 words or fewer. Glosses show on the card under the title.
- `needs` = other idea ids this needs first. The page says "Needs idea 2 first" in words. Never draw it.
- `pictures` may be empty only for an idea with no honest picture (a rename, a policy). That card shows its sentence only.

## The card frame (what assemble.mjs draws)

Top of the page: the headline, then one sentence on how to read a card and a one-line key of the kinds, then a row of numbered chips (number, slot word, title) that link to the cards. Then the cards in slot order: safe, remove, stretch, wild, fix. At the end: "What we left out" (the obvious ideas we dropped on purpose, and ideas that turned out to exist already), then the run key.

Each card: number + slot word, title, the gloss line, the sentence, the pictures in a row (each with its caption under it), a size badge, "Why it's here", "First test", and a closed "Proof from the code" section (evidence, gives up, risks). Pictures stack in one column on a phone.

## Picture catalog

Pick by the idea's kind. Each picture must carry a claim no other picture on the card carries. The first picture shows what a person sees or does (a screen, a terminal, a message, a moment). No picture shows code structure (folders, files, functions, boxes for modules): in a blind read, newcomers could not decode them. Function and file names belong in "Proof from the code", not in titles, sentences, captions or pictures.

| Kind of idea | Pictures | Types |
|---|---|---|
| Take something away | 2 | before (heavy) / after (light), same layout, removed thing ghosted |
| Make something visible | 2-3 | today (hidden) / after (visible) / who sees it |
| Automate a manual step | 3 | today's loop / new loop / time or count saved |
| Faster | 2-3 | one run before / same run after on the same scale / where the time goes |
| Safer | 3 | the bad moment today / the guard / what the person sees instead |
| New ability | 3 | who needs it / how it works in 3 steps / after |
| Tiny tidy | 1-2 | before / after |

Picture types: **terminal** (a pane with up to 4 real output lines, the changed line marked), **log line** (one line split into labelled parts), **file tree** (up to 8 lines, + added, ghosted removed), **diff** (3-6 lines, + and - signs, not colour alone), **flow** (3-5 labelled boxes, "then" arrows, a clock where time is lost), **three steps** (3 boxes, one real value moving through), **moment** (one person, one plain thought line, the thing they touch), **time bar** (to scale, real numbers only). A **terminal** or **diff** picture shows what a person sees in their own terminal or editor, not the project's internals.

## SVG drawing rules

1. `viewBox="0 0 360 220"` (a strip may use `0 0 360 160`). No width or height attributes.
2. `role="img"`, a `<title>` with the claim, a `<desc>` that says the picture in one full sentence.
3. Colours only through CSS variables: `var(--ink)`, `var(--paper)`, `var(--muted)`, `var(--line)`, `var(--accent)`, `var(--accent-soft)`, `var(--card)`. No hex, no gradients, no shadows, no filters, no `<image>`, no `<foreignObject>`, no `<script>`, no `<style>`.
4. Text: `font-family="var(--font)"` or `var(--mono)` for code, `font-size` 14 or more. At most 12 `<text>` elements. Labels are 1-3 words and touch the thing they name. No legend, no numbered key.
5. At most about 14 shapes besides text. Leave 12 units of empty margin on every side.
6. The accent colour goes only on the thing that changes. Pair it with a shape cue (thicker outline, a +, bold text) so it survives greyscale.
7. Before and after pictures use the same layout and positions. Only the changed thing differs. A removed thing is ghosted: dashed outline, `opacity="0.4"`.
8. An arrow means "then" and carries a verb label ("sends", "checks"). Use nesting or a bracket for "is part of".
9. Real names and real numbers from the evidence only. An unknown number is left out, never guessed. Write numbers in human units ("10 min", "2 h", not "600s"). Screen words in another language: label the part in plain English and put the original word after it in brackets, once.
10. No mascots, no metaphor icons (a rocket for "fast"), no decoration. The picture must still say its claim with the caption covered.
11. Ids: prefix every `id` with the idea and picture id (`i3p1-arrow`). assemble.mjs also rewrites ids, but do not rely on it.

Preview a drawing before returning it: `node <skill>/scripts/shot.mjs <file.svg> <file.png> --width 390`, then Read the PNG and fix the worst problem (overlap, cut-off text, a label that floats away from its shape).

## Failure modes to check by eye

- A picture that would fit another idea's card just as well: decoration. Redraw or delete it.
- Two pictures on one card saying the same thing: delete one.
- A hard word in the sentence with no gloss.
- Text that runs into another shape, or off the picture.
- A number that does not come from the evidence.
