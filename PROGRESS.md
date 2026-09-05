# Progress

## Now
- (one bullet: what is being worked on right now)

## Next
- (none)

## Done
- (none yet)

## Rulings
- Ruling: post-bash-write blamed gitignored container logs on the command — hook post-bash-write.sh gitignore filter (fail closed on ignore-file edits) + 4 tests — a false skip hides an oversized file written into an already-gitignored dir; a false keep is one noisy block
- Ruling: hooks resolved the project from the session start dir, not the edited file — hookout.sh hook_project_dir (file's repo, bounded to worktrees of the session repo) + 9 tests in test_project_dir.sh — a wrong fallback silently reads another checkout's plan and state (2026-09-05)

## Blocked / open questions
- (none)
