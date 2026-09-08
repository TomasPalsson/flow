# Progress

## Now
- resume: spec 004 (flow v2) built in this worktree, uncommitted — `/flow:spec` + `/flow:next` are the only two doors, `.specs/NNN-slug/TASKS.md` is the whole build state, `flow next|lint|tick|use|publish` is the CLI. F1-F6 landed (flow-lint, task-brief, router, hooks retarget, skills rename, deletions, integration). F6's end-to-end dry run walked a throwaway node repo through states 5 -> 6 (wave 0) -> tick -> 6 (wave 1) -> 8 -> PASS -> 9 -> Verified -> 11, caught a lying tick in both `flow lint` and `flow next`, proved `flow next` byte-identical from root and subdir, and confirmed spec-gate/stop-gate deny-and-name-the-objection. Suites at baseline: hooks 1236/8, scripts 1815/57, zero failures attributable to spec 004. Decide: commit + merge to main
- resume: spec 003 (harness bug fixes) built and verified in this worktree, uncommitted: hooks 1163/0, scripts 1540/0, field re-probe on finance/terraform/prr green. Decide: commit + merge to main
- resume: `flow next` — loop engineering landed on this branch (spec 006; 19 commits since 093f969): merge to main, then dogfood `/flow:loop` on one real backlog
- decide whether `.skill-forge/` (research workspaces: design-v2, loop) is gitignored or kept

## Next
- Dogfood `/flow:spec` then `/flow:next` on one real feature end to end; confirm every turn really ends with `Next: /clear, then /flow:next`
- Dogfood `/flow:loop --fresh` overnight on a real project (candidates: any of the ~20 `.claude/` projects under ~/Desktop/Projects; none has run `flow init` yet) and tune the defaults (30 iterations / 480 min / stall 3) from the log
- Merge order with the sibling worktrees: this branch touches `hooks.json` (one Stop entry), `bin/flow` (dispatch/doctor/next/init deltas) and `skills/fix`; the harness-audit worktree plans `flow goal` — build `flow goal` on `flow loop run` rather than a second driver
- Optional: `checkwash` as an opt-in verifier prefix in the loop skill once it has a held-out false-positive number
- `/flow-deepen` now appends a `## Phase N — Deepening` section to the spec's `TASKS.md` (F6 retargeted it off the dead `issues/` contract). Nothing has exercised that path yet — dogfood it once on a shipped spec
- Dogfood `/design:vary` on one real surface (a persuade page and an operate page); tune roll.mjs tunables (GLOBAL_WINDOW 8 / PROJECT_WINDOW 3 / ticket weights) from what repeats
- Decide the fate of the old `design` skill (plugins/design/skills/design): retire, or keep as a fallback
- Corroborate the 7 `confidence: verify` world cards (japanese-editorial, italian-rationalist, apothecary-label, museum-gallery, sports-broadcast, editorial-newspaper, japanese-consumer-electronics-80s) or drop them
- Tutorial slice work in progress from another session: `plugins/flow/bin/lib/tutorial.js`, `plugins/flow/scripts/tests/test_tutorial.sh` are modified and uncommitted (not touched by the vary work)
- Optional: description-triggering optimisation for `vary` via skill-creator `run_loop.py` if available

## Done
- 2026-09-07: loop engineering — research 12 (10-angle sweep + 2 source-level dives, 40 claims confirmed), spec 006, `flow loop` CLI (`bin/lib/loop/`, 7 subcommands, K-A..K-L), `loop-gate.sh` Stop hook, `/flow:loop` skill (judge 110/120 A), fix skill off ralph-loop, docs; two headless probes ($0.79 and $0.80, one iteration each) — 130b2f2 and earlier
- 2026-09-05: `vary` design skill forged via skill-forge (3 research waves, 14 agents, judge 113/120 A on pass 1); plugins/design/skills/vary — 617990d
- 2026-09-05: fix(tutorial) --sandbox path resolution — 7580745
- 2026-09-05: feat(tutorial) Slice 2 runner, lessons 1-3 — 7df4be7
- 2026-09-05: `flow off` / `flow on` — fae30ab
- Done before 2026-09-05: 6 items (rename harness→flow, /lesson, install merge, skills-lint perf, doctor hang fix)

## Rulings
- Ruling: a loop exits on a verifier command the harness runs, never on a model-emitted phrase — `flow loop check` + K-F tamper veto + `BLOCKED.md`, 115 `t_loop_*` tests — if wrong, a goal with no runnable check must go through `/goal` or a human gate instead of a loop
- Ruling: the in-session loop shape is capped at Claude Code's 8 consecutive Stop-hook blocks and says so; anything longer is `flow loop run` (fresh `claude -p` per iteration) — verified verbatim in code.claude.com/docs/en/hooks — if wrong, users see a block-cap warning at iteration 8 and re-arm as fresh
- Ruling: workflow/subagent briefs are passed as ABSOLUTE paths when working in a worktree — the build-slices run resolved `.claude/slices/1-brief.md` against the main checkout and a developer read a stale brief for another feature — if wrong, one wasted agent run
- Ruling: prep recommends WITH the question (hypothesis + confidence), not after like grill-me — Pocock's own later addition and Osmani's interview-me; a stated guess the user can correct is not a leading question — if wrong, users anchor on the guess; flip rule 2 in prep/SKILL.md
- Ruling: PREP.md lives in `.specs/NNN-<slug>/` allocated by prep; `new-spec --reuse` keeps the number — one dir per idea, no move step — if wrong, an abandoned prep occupies a number (harmless)
- Ruling: prep turns are plain text; AskUserQuestion only if a question is option-shaped — free text is where the user's own words come from — reversible per skill edit
- Ruling: post-bash-write blamed gitignored container logs on the command — hook post-bash-write.sh gitignore filter (fail closed on ignore-file edits) + 4 tests — a false skip hides an oversized file written into an already-gitignored dir; a false keep is one noisy block
- Ruling: design direction is ASSIGNED by scripts/roll.mjs, never chosen by the model from a menu — measured argmax collapse (27/30 reverts) and ban-list rebound make prose fixes fail — if wrong, the skill produces coherent but occasionally ill-fitting looks; the user re-rolls or takes `--canon`
- Ruling: `vary` keeps `user-invocable`/`argument-hint` frontmatter despite the judge flagging them as non-spec — every installed skill in this plugin uses them and the harness honours them — if wrong, two ignored fields
- Ruling: `.vary/recent.json` (per-project roll memory) is gitignored by roll.mjs, never committed — ephemeral session state, not a design decision — if wrong, teams lose shared anti-repeat memory (reversible)

## Blocked / open questions
- new-spec: `.claude/flow.json` is written into the main checkout even under `--worktree`, so two parallel flows clobber each other (seen 2026-09-05); write it into the worktree instead. (`feature-plan.local.md`, `workflow-state.local.md` and `.claude/slices/` were the other half of this report and are gone as of spec 004 — the state is `.specs/NNN-slug/TASKS.md`, which `--worktree` does place correctly. Open question: does `flow next` still need `.claude/flow.json` at all now that resolution is `$FLOW_SPEC` → `.specs/.current` → branch?)
