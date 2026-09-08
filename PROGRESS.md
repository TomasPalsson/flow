# Progress

## Now
- resume: spec 003 (harness bug fixes) built and verified in this worktree, uncommitted: hooks 1163/0, scripts 1540/0, field re-probe on finance/terraform/prr green. Decide: commit + merge to main; then whether to run spec 004 (flow v2) and 005 (lesson v2) inline, with Sonnet-only agents, or later
- decide whether `.skill-forge/` (1.7 MB research workspace) is gitignored or kept

## Next
- Dogfood `/design:vary` on one real surface (a persuade page and an operate page); tune roll.mjs tunables (GLOBAL_WINDOW 8 / PROJECT_WINDOW 3 / ticket weights) from what repeats
- Decide the fate of the old `design` skill (plugins/design/skills/design): retire, or keep as a fallback
- Corroborate the 7 `confidence: verify` world cards (japanese-editorial, italian-rationalist, apothecary-label, museum-gallery, sports-broadcast, editorial-newspaper, japanese-consumer-electronics-80s) or drop them
- Tutorial slice work in progress from another session: `plugins/flow/bin/lib/tutorial.js`, `plugins/flow/scripts/tests/test_tutorial.sh` are modified and uncommitted (not touched by the vary work)
- Optional: description-triggering optimisation for `vary` via skill-creator `run_loop.py` if available

## Done
- 2026-09-05: `vary` design skill forged via skill-forge (3 research waves, 14 agents, judge 113/120 A on pass 1); plugins/design/skills/vary — 617990d
- 2026-09-05: fix(tutorial) --sandbox path resolution — 7580745
- 2026-09-05: feat(tutorial) Slice 2 runner, lessons 1-3 — 7df4be7
- 2026-09-05: `flow off` / `flow on` — fae30ab
- Done before 2026-09-05: 6 items (rename harness→flow, /lesson, install merge, skills-lint perf, doctor hang fix)

## Rulings
- Ruling: post-bash-write blamed gitignored container logs on the command — hook post-bash-write.sh gitignore filter (fail closed on ignore-file edits) + 4 tests — a false skip hides an oversized file written into an already-gitignored dir; a false keep is one noisy block
- Ruling: design direction is ASSIGNED by scripts/roll.mjs, never chosen by the model from a menu — measured argmax collapse (27/30 reverts) and ban-list rebound make prose fixes fail — if wrong, the skill produces coherent but occasionally ill-fitting looks; the user re-rolls or takes `--canon`
- Ruling: `vary` keeps `user-invocable`/`argument-hint` frontmatter despite the judge flagging them as non-spec — every installed skill in this plugin uses them and the harness honours them — if wrong, two ignored fields
- Ruling: `.vary/recent.json` (per-project roll memory) is gitignored by roll.mjs, never committed — ephemeral session state, not a design decision — if wrong, teams lose shared anti-repeat memory (reversible)

## Blocked / open questions
- new-spec: `.claude/flow.json`, `feature-plan.local.md`, `workflow-state.local.md` and `slices/` are written into the main checkout even under `--worktree`, so two parallel flows clobber each other (seen 2026-09-05); write them into the worktree instead and teach `flow next` / the `agents` alias to look there
