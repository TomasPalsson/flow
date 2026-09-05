# Progress

## Now
- (one bullet: what is being worked on right now)

## Next
- new-spec: `.claude/flow.json`, `feature-plan.local.md`, `workflow-state.local.md` and `slices/` are written into the main checkout even under `--worktree`, so two parallel flows clobber each other (seen 2026-09-05); write them into the worktree instead and teach `flow next` / the `agents` alias to look there

## Done
- (none yet)

## Rulings
- Ruling: post-bash-write blamed gitignored container logs on the command — hook post-bash-write.sh gitignore filter (fail closed on ignore-file edits) + 4 tests — a false skip hides an oversized file written into an already-gitignored dir; a false keep is one noisy block

## Blocked / open questions
- new-spec: `.claude/flow.json`, `feature-plan.local.md`, `workflow-state.local.md` and `slices/` are written into the main checkout even under `--worktree`, so two parallel flows clobber each other (seen 2026-09-05); write them into the worktree instead and teach `flow next` / the `agents` alias to look there
