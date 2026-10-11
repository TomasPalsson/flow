---
name: brainstorm
description: "Brainstorms fresh, project-specific improvement ideas for an existing codebase and shows each as a plain-word card with 2-4 small pictures: safe bets, something to remove, stretches, wild cards, and a couple of real bugs worth a quick fix. Behind it, blind idea agents each get a different slice of the code, idea shape and everyday persona; ideas any assistant would give are dropped and the rest are checked against the code. Use when the user asks to brainstorm, 'what should I build next', 'how can I improve this', 'ideas for this repo', 'what's missing', 'what would make this better', or wants product, UX or DX ideas for code they have. Not for growing one idea the user already has (use develop-idea), judging an idea (use scrutinize-idea), or explaining how code works (use design:smoothbrain)."
argument-hint: "[focus path or theme] [--cells N]"
user-invocable: true
---

# Brainstorm

One model asked for ideas gives the ideas every model gives. Asking it again, or harder, gives the same ideas. Different ideas come from different inputs. So this skill splits the repo into slices, deals each blind agent its own slice, shape and persona by dice, removes the typical ideas afterwards, and draws only the winners.

The reader is tired. The page is one card per idea, the same frame every time, with small pictures that each prove one thing. No dashboards.

## Steps

`<skill>` below means this skill's folder. Run every script with `node`. All paths absolute.

**1. Scope.** The repo is the git root of the current directory unless the user names one. A focus ("only the CLI", a path) goes to `--focus`. Anything else the user said about what matters goes to the workflow as `ask`. Do not ask questions first; run.

**2. Mine.** Make a run dir and cut the repo into evidence slices:
```
node <skill>/scripts/mine.mjs --repo <repo> --out ~/.brainstorm/<repo-name>/<YYYY-MM-DD>-<HHMM> [--focus <path>]
```
It writes `project.md`, `tree.txt`, `slices/*.md` and `slices.json`. Read `project.md`. Exit 1 means no slice reached 3 evidence items (a repo of a few files): read the repo's files yourself, write one `slices/whole-repo.md` packet that cites them by `path:line`, list it in `slices.json` as `[{"id":"whole-repo","title":"the whole repo","n_items":<n>,"strength":0.5,"primary_files":[...],"packet":"slices/whole-repo.md"}]`, and go on.

**3. Roll.** Let the dice deal the cells. Never pick or edit cells yourself: the model picks the same ones every run.
```
node <skill>/scripts/roll.mjs --slices <run>/slices.json --repo <repo-name> --json [--cells N]
```
It prints `{key, cells}` and writes `<run>/cells.json`. Default 8 cells plus one wild cell. Every run gets a `subtract` cell first. The decks it deals from are `data/lenses.json` (idea shapes), `data/personas.json` and `data/constraints.json`; edit those, not the cells, to change what can be dealt.

**4. Run the workflow.** Make `<run>/pictures/`, then:
```
Workflow({ scriptPath: "<skill>/workflow/brainstorm.js",
           args: { repo, run, skill, date: "<YYYY-MM-DD>", cells: <cells from cells.json>, focus, ask } })
```
`repo` = absolute repo path; `run` = the run dir from step 2; `skill` = this skill's folder; `cells` = the `cells` array itself (paste the JSON, not a path: workflow scripts cannot read files); `focus` and `ask` may be omitted.

It runs, in parallel, blind generators (one per cell, each with an ambition size: a big bet, a feature, or a quick win), one sweep for the sharpest real defects, one whole-repo reader, and three hidden "typical ideas" anchors. Then it groups same-move ideas, marks the typical ones, refutes each against the code, and ranks the survivors on plain cards three ways (surprise, usefulness, fit to this project), each twice. It picks 3 safe bets, 2 wild cards, 2 stretches (wild cards and stretches must fit this project), 3 quick fixes from the defect sweep and a remove idea, one idea per problem, then has one reader swap out any two picks that are the same idea, then writes a plain card and draws 2-4 pictures for each pick. It returns the page data. Wait for it; do not redo its work by hand. No Workflow tool in this session: say this skill needs it, and stop.

If it returns `error: no ideas generated`, read the `silent` reasons, then re-roll once (step 3 with no flags) and rerun. Two empty runs: tell the user the repo gave the generators too little to work with, and why.

**5. Build and check the page.** Write the returned object, plus `"key"` from step 3, to `<run>/final.json` (drop `stats`; keep it in `<run>/stats.json`). Then:
```
node <skill>/scripts/assemble.mjs --run <run>
node <skill>/scripts/check.mjs <run>/page.html --render
```
Fix every FAIL at its source. Word counts (sentence, title, caption) are fixed in `final.json`. Overlaps, cut-off or tiny labels are fixed in that picture's SVG file under `<run>/pictures/`. Read [`references/page.md`](references/page.md) before editing a card or picture; skip it when check passes first time. Re-run both scripts until check passes.

**6. Blind read.** Screenshot the page and hand only the PNGs to a fresh reader:
```
node <skill>/scripts/shot.mjs <run>/page.html <run>/read-390.png --width 390 --full
```
Spawn one Agent (`model: sonnet`): "You have never seen this project. Using only these screenshots, for each numbered card say in one sentence what changes and for whom. Then list every word, picture or label you could not understand." Compare each answer with the card's `sentence`. Where the reader got it wrong or listed something, fix that card (plainer words, a gloss, a redrawn or deleted picture) and rebuild. One round, then ship.

**7. Ship.** If the Artifact tool is available, rebuild with `--artifact` and publish `<run>/page.html`; otherwise give the file path. The chat reply is three lines: the headline, the link or path, and the titles of the safe bets. Mention the run key so a run can be compared later.

## Rules the workflow depends on

- **Blind generators.** No generator sees another's ideas, the typical list, or earlier runs. Shared ideas make every agent converge.
- **No ban lists in generator prompts.** Naming the obvious ideas plants them. The anchors run beside the generators and their list is only used to filter afterwards. Typical ideas are shown to the user under "What we left out", so the reader sees what was skipped on purpose.
- **Ordinary personas.** A nurse turned developer, the author after nine months away. Never "a principal engineer" or a famous founder: expert and celebrity personas narrow the ideas.
- **Judges see plain cards and rank, not score.** No titles, no lens names, no markdown: polished wording wins with judges, so it is removed first. Judges rank all survivors against each other (1-5 scores bunch in the middle). Effort is never a divisor.
- **Wild cards are protected.** They are picked by surprise, not by score. The reader sees them labelled as bets with a first test that could kill them.
- **Text first, pictures last.** Ideas are chosen on text. Clear drawings make ideas look better than they are, so nothing is drawn before the choice.
- **Plain words.** Sentences of 20 words or fewer. The project's own nouns, each glossed once. No skill jargon on the page (tiers, levels, lenses, slices).

## Shortcuts that break it

- **Hand-writing or hand-editing `page.html`.** The next assemble overwrites it, and the frame is what lets a tired reader learn one card and read the rest. Edit `final.json` or an SVG, then assemble.
- **Choosing, editing or re-rolling cells until you like them.** The model picks the same favourites every run; that is the sameness this skill exists to break. Re-roll only after an empty run.
- **Adding ideas of your own to the page.** They skip the refuter and the typical-idea filter, so they are exactly the ideas the filter would drop.
- **Shipping on a green check without the blind read.** check.mjs proves labels fit, not that anyone understands the card.
- **Redrawing a failing picture again and again.** Two tries, then delete it from `final.json`.

## When things go wrong

| Symptom | Do this |
|---|---|
| `mine.mjs` finds no git | Fine; history slices are skipped. Say so in the reply. |
| Most ideas match a typical idea (`stats.json` `typical_hits` high) | The repo is mature or tiny. Ship fewer cards; never pad. |
| A drawing keeps failing check | Delete that picture from `final.json`. A card with fewer honest pictures beats a broken one. |
| Check FAILs on a word count | Shorten the text in `final.json`; never loosen the checker. |
| No Chrome for shot/check `--render` | Run check without `--render`, skip the blind read, and say the page was not looked at. |

## Done when

- `check.mjs --render` prints no FAIL.
- The blind reader's sentence matches the card on every card but at most one.
- Every idea cites a real `path:line` that the refuter opened.
- The reply is three lines plus the run key.
