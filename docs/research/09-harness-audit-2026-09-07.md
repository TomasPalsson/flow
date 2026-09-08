# Harness audit, 7 September 2026 — bugs and smoothness

Three adversarial reviews (hooks correctness, hooks friction, CLI + scripts) plus two research sweeps (07-harness-smoothness-2026.md, 08-reference-harness-inventory-2026.md). Every finding below has an executed receipt in the agent transcripts; the top three were re-run by the orchestrator. Baseline before any change: hooks suite 586/0, scripts suite 1112/0, `flow doctor` 26 pass / 5 warn / 0 fail.

Note on deployment: `~/.claude/skills -> /home/tomas/Desktop/Projects/flow/plugins` (the MAIN checkout). Edits in a worktree are not live until merged.

## Headline

Hook dispatch is not slow (every event 7–43 ms wall here). The "not smooth" feeling comes from hooks that act on files the model did not touch, nag on pre-existing conditions, and inject text on mistake-free turns. Two safety hooks also have real holes.

## Bugs, by severity

### Fatal

| # | Where | Bug | Receipt |
|---|---|---|---|
| B1 | hooks/git-guard.sh:52-69, :113 | Only inspects `T[0]` of each part, so any part prefixed by a shell keyword (`then`, `do`, `time`, `nohup`, `else`, `{`) skips every rule. | `if true; then git push --force origin main; fi` → ALLOWED; `if [ -d x ]; then rm -rf /; fi` → ALLOWED; `for b in a b; do git branch -D "$b"; done` → ALLOWED. Bare forms deny correctly. No test covers a keyword-prefixed part. |
| B2 | hooks/post-bash-write.sh:24, :56-64, :123-136 | Write-indicator regex matches `2>/dev/null`, `node`, `python`, `tee`, `<<` in read-only commands; then attributes EVERY file newer than the tool stamp to the command and runs format-lint + size-guard + tamper-notice on each. format-lint then rewrites files the model never edited. | Fired live three times during the audit on `git checkout -- file 2>&1`; `ruff format` re-dirtied the file being reverted; reported "size_guard.py:140 main is 61 lines" (pre-existing in HEAD). 140 ms/file, ~7 s at the 50-file cap. |
| B3 | bin/lib/tutorial.js:121-163 | `flow tutorial --sandbox <existing dir>` unconditionally overwrites README.md, runs `git init`, and creates a `<dir>-bin` sibling. Lesson 1 text claims "nothing here can touch your real machine"; runInSandbox is a plain `sh -c` with the real env. | README replaced with "# flow tutorial sandbox", exit 0; a command inside the "sandbox" wrote a file outside it. |

### Significant — hooks

| # | Where | Bug |
|---|---|---|
| B4 | hooks/format-lint.sh:130-164 | ruff and shfmt run with no project config (biome/prettier are correctly config-gated at :109-114). ruff on size_guard.py: +42/−9 churn; shfmt on format-lint.sh: 92/92 churn. 28 of the harness's own shell files are not shfmt-canonical, so every touch ships whitespace noise. |
| B5 | hooks/size-guard.sh:78 | Judges the whole file, not the delta. 58 tracked source files already exceed 400 lines (bin/flow 2234, stop-gate.sh 551, check-all 452…), so every edit to them emits an exit-2 nag and escalates to a `/lesson` suggestion on the second. size_guard.py fails its own gate (main is 61 lines). |
| B6 | hooks/stop-gate.sh:165-167 | `git status --porcelain` non-empty counts as "changed this turn", overriding the find-newer test. On any dirty repo a read-only turn runs the full test-changed/check-all sweep. |
| B7 | hooks/stop-gate.sh:160-162 | find-newer excludes neither `build/` nor `__pycache__/` and applies no check-ignore, so Python bytecode from a `python3 -c` blocks the turn on a pre-existing red gate. post-bash-write.sh prunes both; stop-gate never got the fix. |
| B8 | hooks/stop-gate.sh:161 | In a git worktree `.git` is a file; `-not -path '*/.git/*'` does not exclude it and `_sg20_is_source ".git"` returns true → "`.git` changed this turn without a plan". |
| B9 | hooks/stop-gate.sh:545-549, SPEC C10 vs C1 | The wedge valve "degrades to exit 2", but exit 2 on Stop also blocks. The valve changes wording, never releases. Real cap is `stop_hook_active` (one block per turn) and Claude Code's 8-block override. |
| B10 | hooks/lib/hookout.sh:90-99 | "ignore file uncommitted this turn" has no turn scoping: any dirty `.gitignore` anywhere disables the git-ignore exemption for the whole repo for the whole session, so format-lint runs formatters on gitignored files. |
| B11 | hooks/lesson-nudge.sh:33-37 | Matches 8 of 9 benign prompts ("why did you add that import?", "you keep using shfmt, is that intentional?"). Also fires on system task-notifications, which are not user prompts (observed twice this session). Violates the no-nudge-noise rule. |
| B12 | hooks/rtk-rewrite.sh:21-24 | Prints "[rtk] WARNING: rtk is not installed" to stderr on every Bash call on Linux. rtk-fast.sh hardcodes /Users/tomas and BSD stat (unregistered, dead). Panel edit 1 ordered removal; never landed. |
| B13 | hooks/worklog-hook.sh:15 + hooks.json (7 registrations, 2 matcher-less) | `exec worklog hook-run` propagates a third-party exit code: exit 2 from worklog would DENY every tool call including Read. Binary absent here, so today it is ~2 wasted spawns per tool call. |
| B14 | hooks/session-context.sh:27-34 | 20-line cap: repo state uses 7–8 lines, so any PROGRESS.md ≥ 12 lines silently drops REVIEW.md note, harness overrides, the worktree-mismatch warning, and the entire `flow next` block. Dead in practice in this repo (27-line PROGRESS.md). |
| B15 | hooks/tamper-notice.sh:53-56 | Diffs against HEAD, so a justified `.skip(` from turn 1 re-nags on every later edit of the file and escalates to `/lesson` on the second. |
| B16 | hooks/git-guard.sh:140 | Newline → `;` normalisation means a heredoc whose body line starts with `git reset --hard` or `rm -rf /` is denied: the model cannot write a deploy script or runbook fixture via heredoc. |
| B17 | hooks/spec-gate.sh:160-163, stop-gate.sh:184-191 | No `pwd -P` on the project dir: with a symlinked CLAUDE_PROJECT_DIR the relpath strip fails, spec-gate denies editing `.claude/flow.config.json` (its own escape hatch) and stop-gate stops running plan-lint on the plan. |

### Significant — CLI and scripts

| # | Where | Bug |
|---|---|---|
| B18 | scripts/new-spec:207-209 | `git checkout -b` / `git worktree add` exit status discarded; writes `.claude/flow.json` naming a branch that was never created. Title with no ASCII alnum → slug "", dir `.specs/004-`, branch `flow/`, exit 0. |
| B19 | scripts/new-spec:207, bin/flow:2043, session-context.sh:102 | Worktree path recorded un-normalised (`$TOPLEVEL/../code-worktrees/...`); consumers compare by string equality to `rev-parse --show-toplevel` → permanent false "worktree mismatch" once the Blocked-item fix lands. |
| B20 | scripts/slice-overlap:98-100 | Does not strip CR (plan-lint does). CRLF plan: two slices owning the same file pass, and `--waves` schedules them concurrently. |
| B21 | bin/flow:1835-1838 | `flow next` returns prose for `resume:` bullets (`` `flow next` — vary design skill committed… ``), not a runnable command. |
| B22 | bin/flow:2042-2051 | Branch mismatch prints `agents flow/login` (a branch, not a directory). |
| B23 | bin/flow:2014-2026 | `flow next` reads cwd, not git toplevel; from `plugins/flow` an active flow is invisible. |
| B24 | bin/flow:1346-1360, :1388-1428 | `flow install --dotfiles --force` takes `--force` as the path; creates 8 dangling symlinks reported as green "create". Marketplace root falls back to a hardcoded `~/Desktop/Projects/flow` instead of REPO_ROOT. |
| B25 | bin/flow:717-730 | `flow doctor` 3.4–6.3 s; 4.9 s is skills-lint, which only ever WARNs. Everything else in the CLI is under 60 ms. |

### Improvable

- `flow init --force` overwrites PROGRESS.md/REVIEW.md with no backup (install --force backs up).
- `workflow-lint` default path `~/.claude/workflows` is stale post-cutover.
- Generated gates.yml has no `npm ci` / `pip install` step.
- `flow tutorial` not wired into `main()` dispatch (slice in flight).
- session-context.sh:118 `have harness` fallback is dead (renamed to `flow`).
- git-guard.sh:92 lists `stash|rebase|merge` with no rule (dead, can shadow a later subcommand).
- 110 lines duplicated verbatim between spec-gate.sh and stop-gate.sh; three divergent path-exclusion lists (format-lint/size-guard, stop-gate, post-bash-write) — B7 and B8 are the consequences.
- `_lesson_nudge` keys on the first reason line, which for format-lint/tamper-notice is the file path, so cross-file recurrences never count.
- Hooks cite SPEC sections C19–C23 that do not exist in docs/SPEC.md (ends at C17).

## What the research says (delta vs 01-harness-engineering-2026.md)

- Anthropic runs all matching hooks of one event in parallel: per-event cost ≈ max, not sum. Stacking is cheap in time; the hazard is two hooks modifying the same tool input (docs warn against it; issue #88338 last-registered-wins).
- New since 01: hooks accept an `if:` filter in permission-rule syntax (`Bash(git *)`, `Edit(*.ts)`) that avoids the spawn entirely; Stop hooks may return `hookSpecificOutput.additionalContext` (continues the turn without the red "hook error" label, v2.1.163); `FileChanged` fires for every writer including Bash (the vendor's answer to the gap post-bash-write closes); `asyncRewake` runs a check off the critical path and interrupts only on failure; `/skill-doctor` (v2.1.261) lists never-invoked skills and their cost; `permissions.deny` is shell-aware (subshells, `$()`, loop bodies) where git-guard is a regex.
- The smoothest public setups: superpowers (282k stars) has one SessionStart hook and blocks nothing; gsd has 13 hooks, one blocks, off by default; Anthropic's security-guidance hook is `if:`-gated to `Bash(git commit:*)` and `asyncRewake`. Boris Cherny's format hook ends in `|| true`. Cherny: "every six months, delete your CLAUDE.md, skills, hooks and see what the model does."
- Consensus principles: advisory by default, block only for named invariants; expensive checks gated on command identity, never a substring guess; never point a formatter at a file the model did not write; zero steady-state context injection (flow already does this best, and it is what makes 24 registrations survivable); CI and tests are the real gate.
- Judged justified in flow (keep): Stop test gate, spec-gate on flow/* branches, tamper-notice (detectors do not decay; prohibitions do), PreCompact/PostCompact, `flow off`.

## Ranked fix plan (friction removed ÷ safety lost)

1. git-guard: resolve the git/rm/chmod subcommand anywhere in the part after stripping leading shell keywords; add tests for `then`/`do`/`time`/`nohup` prefixes and for heredoc bodies not being parts (B1, B16). Move fixed-shape denies (`git push --force`, `git reset --hard`, `rm -rf /`) into `permissions.deny` as well.
2. post-bash-write: `if:`-gate or anchor the write verbs (no `2>`/`>/dev/null` triggers); intersect the newer-set with `git diff --name-only` + untracked; never run format-lint from here (B2). Evaluate `FileChanged` as the replacement.
3. format-lint: config-gate ruff and shfmt like biome/prettier; exit 0 (advisory) on formatter failure (B4). One-time `shfmt -w` sweep of the 28 harness files as its own commit.
4. size-guard: baseline-aware — fire only when the edit pushes a file/function over the limit or grows one already over (B5).
5. stop-gate: drop the porcelain "changed" test, keep find-newer; prune `build/`, `__pycache__/`, `.git` file, check-ignore; share one exclusion list with post-bash-write (B6–B8). Make the wedge valve `hook_ok` + stdout, or fix C10 (B9).
6. lesson-nudge: keep only unambiguous complaint verbs and explicit markers; ignore prompts that are system notifications (B11).
7. Delete rtk-rewrite.sh/rtk-fast.sh registrations and files; collapse worklog to one registration guarded by `have worklog` at SessionStart, never `exec` unguarded (B12, B13).
8. session-context: budget PROGRESS.md at 8 lines, always print `flow next` and mismatch notes (B14). tamper-notice: diff against the turn-start blob or a per-file ack stamp (B15).
9. hookout: scope the .gitignore fail-closed rule to ignore files newer than the turn stamp (B10); `pwd -P` the project dir once in hookout and use it everywhere (B17).
10. new-spec: check git exit codes before writing flow.json; normalise the worktree path with `rev-parse --show-toplevel`; reject empty slugs (B18, B19). slice-overlap: strip CR (B20).
11. flow next: extract the backticked command in `resume:` bullets, print `git checkout <branch>` for branch mismatch, resolve paths from toplevel (B21–B23). flow install: reject flag-shaped path values, verify link targets exist, use REPO_ROOT (B24). doctor: skills-lint under `--deep` only (B25).
12. tutorial: refuse a non-empty `--sandbox` target without `--force`, drop the isolation claim (B3).
13. Standing: run `/skill-doctor`; ablate the plugin with `--safe-mode` each model release and record in PROGRESS.md.
