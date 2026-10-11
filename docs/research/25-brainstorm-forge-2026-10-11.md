# brainstorm v2: skill-forge rebuild and evals (2026-10-11)

Ask: the old `/brainstorm` page confused the user (they always ran `/eli5` or `/design:smoothbrain` after it) and its ideas felt basic. Rebuild with skill-forge, use workflows, prove it with evals.

## What changed

| Old (v1) | New (v2) |
|---|---|
| One agent explores, ideates and judges in one pass | `mine.mjs` cuts the repo into disjoint evidence slices; `roll.mjs` deals each blind generator a slice, idea shape, everyday persona, constraint and ambition size from an external random key |
| No check on obvious ideas | 3 hidden "typical idea" anchors; matches are filtered, never shown to generators |
| Self-judged | Refuter per idea (exists / deliberate / false premise), list-wise ranking on plain cards for surprise, value and fit, quota portfolio, one idea per theme, twin check |
| Dashboard: treemap, scatter, DAG, linked brushing, passports | One card per idea, 2-4 small SVG pictures each, plain words, assembled by script (`assemble.mjs`) and checked (`check.mjs --render`) |

Also: a defect sweep (Quick fix slot, 4 cards), a whole-repo reader and a whole-repo big-bets reader, after evals showed v2 had dropped v1's real bugs and its product-level bets; the refuter moved to Opus and now hunts false premises (code that already does the thing, wrong claims about how outside tools behave).

## Research basis (`.skill-forge/brainstorm/`, 11 files, 25 key claims cross-checked: 29 confirmed, 13 weakened, 0 fabricated)

- Sampling one prompt more saturates (Si et al. 2024: ~5% unique of 4,000); models agree with each other (Artificial Hivemind, NeurIPS 2025). Diversity comes from different inputs per generator.
- Visible draft-revise and ordinary personas cut fixation (Deng, Brucks, Toubia 2026); expert/celebrity personas narrow ideas.
- Judges reward fluent, hype-framed text (SciStyleBench 2026); 1-5 scores bunched at 3 in our own first trial, so v2 ranks list-wise.
- Pictures: one claim per picture, labels on parts, same frame every card (segmenting, small multiples, NNG plain-language study).

## Evals (3 fixtures: prr Rust CLI, meal-planner Expo app, granted-tab-groups Firefox add-on; blind, both orders)

| Round | Page pairwise (v2 wins) | Ideas, maintainer judge | Ideas, user-taste judge |
|---|---|---|---|
| 1 (b) | 6/6 clear | v1 6/6 | - |
| 2 (c) | 6/6 clear | v1 6/6 | - |
| 4 (fair format) | 6/6 clear | v1 6/6 | v2 4/6 (meal-planner, granted both orders); prr v1 |
| 5 (fresh dice, big bets, Opus refuter on prr) | 6/6 (2 "huge") | v1 4/6, prr tie 1-1 | **v2 6/6: all 3 fixtures, both orders** |
| Unseen repo (worklog), installed plugin run end to end incl. blind read | 2/2 clear; ELI5 needed: v2 no, v1 yes | tie 1-1 | **v2 2/2** (novelty 7 vs 4) |
| worklog, fresh full re-run with the folded "More bugs worth fixing" list | - | tie 1-1 (v2 novelty 7-8 vs 6) | **v2 2/2** again (novelty 7 vs 4-5) |

- Tired-reader page scores, round 4: clarity v2 7-8 vs v1 4-6; pictures helped v2 7-8 vs v1 2-5; "would still need an ELI5": v2 0/3, v1 3/3.
- User-taste judge novelty, round 5: v2 7/6.5/7 vs v1 4/4/5.5.
- skill-judge (120-point rubric): 105/120 on the first draft, 106/120 on the round-5 text (no critical issues); its top fixes were applied.
- The maintainer judge prefers long verified bug lists (v1's shape); the user said that shape feels basic. Both are reported.
- Eval artifact found: judging v2's plain card sentences against v1's technical one-liners reads as "no mechanism"; round 4 re-judged with each v2 idea carrying its evidence and first test.

## Unseen-repo check (worklog)

The installed plugin ran every SKILL.md step on a repo it had never seen: mine, roll, workflow (82 agents, ~9.5 min), assemble + check (2 fails fixed in final.json), blind read (the reader restated all 9 cards correctly; its confusions led to three skill fixes: an `about` line under the title, kind words that never break on phones, plain-word first tests). Old skill on the same repo: 15 ideas, mostly fixes. Judges: taste v2 both orders ("noticed billing is now the real job"), maintainer tie. First page judgement: v2 still needed an ELI5 (Icelandic screen words, two contradicting cards, a puzzle title, "600s", the left-out wall, repeated glosses). Fixed in the skill (twin check also catches contradictions, effect-first titles, human units, left-out list folded, each gloss once) and re-run: clarity 7 vs 5, pictures 7 vs 3, no ELI5 needed.

## Picking fixes and keeper count (10ee94d)

Two picking bugs found by the maintainer judge: a defect merged into a group whose best member was a feature idea lost its fix status (meal-planner's biggest bug vanished), and the removal slot was filled by a fix or dropped by the twin check with nothing refilling it. Fixed in 10ee94d. Re-judged meal-planner and granted: taste judge v2 2/2 on both; maintainer judge meal-planner v1 2/0 -> tie 1-1, granted v2 2/0.

Per-idea scoring (2 Opus judges per list, new and useful 1-10, keeper = both >= 7), latest lists before the use check:

| Repo | v1 keepers | v2 keepers | v2 mean new (v1) | v2 mean useful (v1) |
|---|---|---|---|---|
| meal-planner | 0 | 4 | 6.2 (4.7) | 6.1 (5.8) |
| worklog | 0 | 1 | 5.6 (4.6) | 5.5 (5.5) |
| prr | 0 | 0 | 5.8 (5.4) | 5.2 (5.2) |
| granted-tab-groups | 0 | 0 | 6.0 (5.5) | 4.9 (4.4) |

Bold ideas lose on usefulness for three repeated reasons: an existing command already covers most of it, the pain is rare for the real users, or a big build with unproven demand.

Use check, shipped after the user approved its pages: a per-idea "use check" (an agent plays the person, answers how often / what they do instead / would they switch, gate below 5). It judged everything as the repo's single current user and dropped every bold idea on prr and granted (pages became all fixes). Softened once (judge for whoever the idea serves, gate below 4); granted still lost its bold ideas. Stopped at the user's request to save usage. The softened version's pages (prr: pre-push gates, one-command ship, per-client review account, Claude-written summary; worklog: unbilled-days list, Icelandic invoice text, repo-to-ticket rule) were checked by the user by eye and approved, so it ships; it was not re-scored by the judges.

## Open

- prr lost rounds 1-5a: three picks rested on false premises; fixed by the Opus refuter (4 dead vs 1), after which prr flipped to v2 under the taste judge.
- Cost: ~60-90 agents, ~3-6M tokens, 5-8 minutes per run (Opus generators, refuters and ranking; Sonnet only shortens captions).
- Term clashes across cards (one word, two meanings on different cards) are not detected.
