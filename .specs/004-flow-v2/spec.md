# Spec 004 — flow v2: `/flow:spec`, `/flow:next`

Source of truth for the design: docs/research/11-flow-redesign-2026.md (§3 design, §3.4 state table, §3.5 TASKS.md grammar, §3.6 routes, §3.7 verification, §5 migration, §7 backlog). Read it in full before your slice. This spec freezes the deltas the developer asked for on top of it and the ownership split. Spec 003 (bug build) has landed; read the CURRENT files, not the research doc's line numbers.

## Developer's requirements (binding)

1. Two slash commands: `/flow:spec <idea>` (the only door) and `/flow:next` (the only build verb). No goal/unattended loop command in this spec.
2. No GitHub in the pipeline. Work items live in `.specs/NNN-slug/TASKS.md`. `flow publish` mirrors open tasks to issues only when asked.
3. **Every `/flow:next` turn ends with a `/clear` recommendation**, and pickup after `/clear`, crash, or compaction comes from disk alone. The router recomputes position from files on every call; nothing lives in the transcript. The last line of every `/flow:next` turn is exactly: `Next: /clear, then /flow:next` (or the router's own `Next:` line when the state is a hard gate for the user, e.g. `Next: read .specs/003-x/TASKS.md, reply "approved"`).
4. Small changes pay no spec ceremony (route `bounded`); approval never scales down (one "go?").
5. Workflows parallelise waves: when a wave has ≥3 ready `[P]` tasks, `/flow:next` runs the `build-slices` Workflow; otherwise fresh `developer` subagents in one message (≤4).

## Rules for every slice

Same as spec 003 "Rules for every slice" (repo root, ownership, bash 3.2 portability, red-then-green tests in owned files, unique `t_` names, run both suites and paste summary lines, never weaken a test, the deployed harness's size-guard nags are noise). Additionally: `bin/flow` is already ~2,400 lines; put NEW subcommand code in `plugins/flow/bin/lib/<name>.js` modules (`router.js`, `lint.js`, `tick.js`) required from `bin/flow`, so `bin/flow` grows by dispatch lines only. Node ≥18, zero deps.

## Shared contracts (frozen)

K-A Layout under the git toplevel:
```
.specs/.current            one line: NNN-slug
.specs/.next-call-count    integer; reset to 0 by any state change (router compares a state hash)
.specs/LEDGER.md           append-only; `<date> <route> — <title> — <sha>` per shipped feature; `Ruling: …` lines
.specs/BLOCKED.md          presence sentinel → router state 1a
.specs/NNN-slug/spec.md | design.md (optional) | TASKS.md | NOTES.md | PASS-<sha>.md | verify/ | review/ (gitignored)
.specs/archive/<YYYY-MM-DD>-NNN-slug/
```
`new-spec` gains `--current` (writes `.specs/.current`) and keeps everything else. `.gitignore` gets `.specs/*/review/`.

K-B `TASKS.md` grammar (11 §3.5), parsed ONLY by `scripts/flow-lint`; header lines `Spec: | Design: | Base: <sha> | Route: bounded|oneshot|dispatch | Test: <cmd>`, optional `Approved: <date> by user`, `Verified: <date> by user`; sections `## Behaviors` (table), `## Phase N — <title>` with `Goal:` and `Independent test:` lines, `## Gates`; task lines:
```
- [ |x|~] <ID> [P]? <description> — files: <p1,p2> — verify: <`cmd` | human: <observable>> [— after: <IDs>] [— dropped: <reason>] [— done: <sha>]
```
IDs: `T###` tasks, `CHK###` human checkpoints, `G###` gates. `flow lint --json` → `{ok, errors:[{line,id,rule,message,fix}], warnings:[...], info:[...], waves:[[ids],[ids]], tasks:[{id,state,parallel,files,verify,after,done,phase}], header:{...}}`. Rules per 11 §3.5 (ERROR: `[P]` overlap within a wave, missing `verify:`, `[x]` sha not in `Base..HEAD` or its commit touches none of `files:`, an ID present at `HEAD:` and absent now, `[~]` without `dropped:`; WARN: phase without Goal/Independent test; INFO: `Route: oneshot` with >5 tasks). Every ERROR has a `fix:` string.

K-C `flow next --json` → `{state:<name>, state_no:<0..13>, command:<runnable token>, why:<prose>, after:"/clear" | null, gates:{blocked,lint_error,unreachable_done,scan_failed,consecutive_calls}, feature:{dir,slug,route,base}|null, wave:{ids:[...],parallel:bool}|null}`. Human output: `Next: <command>` / `Why: <why>` / `Then: /clear` (only when `after` is set, i.e. states 4,6,7,8,10,11 after work). `command` is ALWAYS one runnable token that the plugin ships or a git/gh command; a test asserts every literal in the state table resolves. Resolution: `$FLOW_SPEC` → `.specs/.current` → exact branch `flow/<slug>` → state 3. Before routing, the completeness scan (state 1b) REPORTS other approved features with unchecked tasks and stops (default) unless `--force`. PROGRESS.md is never consulted by the router (delete the early return). Anchored at `git rev-parse --show-toplevel`.

K-D `flow tick <ID> [--dir <spec-dir>]` is the only writer of `[x]`: verifies the ID exists and is unchecked, that HEAD is not the `Base:` (something was committed), appends `— done: <short sha of HEAD>`, resets `.next-call-count`. `flow tick CHK### --by user` for checkpoints. Exit 1 with a `fix:` on any violation.

K-E stop-gate additions (hooks slice): (1) an `[x]` line in the active TASKS.md without `— done:` blocks the turn with `fix: run flow tick <ID>`; (2) spec-gate/stop-gate "approved plan" = active `TASKS.md` with `Approved:` AND `flow lint` ok; the deny text prints the first lint ERROR and its `fix:`; (3) the C20 source-file gate reads the active feature from `.specs/.current`; no `.claude/feature-plan.local.md` anywhere.

K-G Routes (11 §3.6): `bounded` (0 intent gaps, 0 irreversibles, ≤2 files, existing flow in repo) → nothing under `.specs/NNN/`, plan in chat, one "go?", one LEDGER line; `oneshot` (0 gaps, 0 irreversibles, ≤5 tasks) → TASKS.md only; `dispatch` → spec.md + TASKS.md (+ design.md). `/flow:spec` computes the facts, states the route as a fact ("Reply 'oneshot' to downgrade"), ratchet one-way via `/flow:next --escalate`.

## Slices

### F1 — flow-lint + task-brief (model: opus; runs first). Owns: NEW `plugins/flow/scripts/flow-lint` (bash 3.2, `--json`, `--waves`), NEW `plugins/flow/scripts/task-brief` (from slice-brief, task granularity, records BASE before dispatch), NEW `plugins/flow/scripts/tests/test_flow_lint.sh`, `plugins/flow/scripts/tests/fixtures/tasks-*.md` (new fixtures). Do not delete plan-lint/slice-overlap/slice-brief yet (F5 does).
Implement K-B fully with fixtures for every rule (good, overlap-in-wave, overlap-across-waves-ok, missing verify, lying tick (needs a tmp_repo with commits), vanished id, dropped without reason, CRLF, unicode). `--waves` prints `wave N: T002 T003`. Exit 1 on ERROR, 0 otherwise. Budget ~500 lines; split helpers into `scripts/lib/flow-lint-*.sh` sourced files if needed (you own `scripts/lib/`).

### F2 — router + CLI (model: opus). Owns: `plugins/flow/bin/flow` (dispatch lines + deletions in computeNext/cmdNext only), NEW `plugins/flow/bin/lib/router.js`, `lint.js` (wrapper over scripts/flow-lint), `tick.js`, `publish.js`, `use.js`; `plugins/flow/scripts/new-spec` (`--current`), `plugins/flow/scripts/tests/test_next.sh`, NEW `plugins/flow/scripts/tests/test_flow_v2_cli.sh`, `plugins/flow/scripts/tests/test_flow.sh` (new-spec tests).
Implement K-C, K-D, `flow use`, `flow publish` (gh issues from unchecked T### lines, idempotent by title, never called by anything else). Keep `flow doctor/init/off/on/install/tutorial/lesson` untouched except: `doctor` gets a `specs-state` check (prints the router state, FAIL on state 0/1d/1e) and `next` help text. Tests: one per state row using fixture `.specs/` trees in `tmp_repo`; `next` identical from root and subdir; every `command` literal in the table is either a shipped subcommand/slash command (grep the plugin) or starts with `git `/`gh `; `.next-call-count` increments and resets; `tick` receipts.

### F3 — hooks retarget (model: opus). Owns: `plugins/flow/hooks/stop-gate.sh`, `plugins/flow/hooks/spec-gate.sh`, `plugins/flow/hooks/lib/specgate.sh`, `plugins/flow/hooks/tests/test_stop_gate.sh`, `plugins/flow/hooks/tests/test_spec_gate.sh`, `plugins/flow/hooks/tests/test_quality.sh` (stop tests only), `docs/SPEC.md` (C7/C10/C20 wording).
Implement K-E. The approved-plan predicate becomes `active TASKS.md has Approved: && flow-lint ok`; resolve the active feature exactly like the router (`$FLOW_SPEC` → `.specs/.current` → branch). Replace every `feature-plan.local.md` reference. Lint at Stop only when the ACTIVE TASKS.md is in the turn's change set. Print the lint objection + `fix:` in deny/block text. Add the sha-less `[x]` block. Update SPEC.md C7 to point at K-B. Tests for each.

### F4 — skills and commands (model: opus). Owns: `plugins/flow/commands/` (NEW: `spec.md`, `next.md`), `plugins/flow/.claude-plugin/plugin.json` (add `"commands"`), `plugins/flow/skills/flow/**` (rewrite → the `/flow:next` skill ~200 lines + `execution-prompt.md` moved from feature + `review.md` kept; delete `steps/`, `orchestration.md`, `planning.md`), `plugins/flow/skills/flow-spec/**` (cuts per 11 §3.3 + route gate + `--amend` + `--interview` + `--unattended`; delete the flow-to-issues hand-off), `plugins/flow/flow-templates/TASKS.md` and `spec.md` (new templates), `plugins/flow/workflows/build-slices.js` (consume TASKS.md waves via task-brief), `plugins/flow/README.md`, `docs/reference/workflows-and-cli.md`, `docs/reference/agents-and-commands.md`, `plugins/flow/scripts/tests/test_commands.sh`, `test_workflows.sh`, `test_spec_prose.sh`, `test_wave5_prose.sh` (prose tests that reference the old skills).
`/flow:next` skill must: read `flow next --json` first and do exactly that state's action; per task use `task-brief` + fresh `developer` subagent (≤4 in one message) or the Workflow when ≥3 ready `[P]`; re-run each task's `verify:` itself; `flow tick` in the same turn; run the phase `Independent test:` at boundaries; gates → `PASS-<sha>.md`; write `verify/` evidence for CHK; ship via `gh pr create --draft` → `gh pr ready`; archive via `git mv`; `--unattended` semantics; `--escalate`; `--qa` (runs the qa skill); and END EVERY TURN with the `/clear` line from requirement 3. `/flow:spec` must compute the route facts, do ONE batched discovery turn (pre-answered assumptions list), write per route, `flow use`, run `flow lint`, print "This run will stop for you N times", and end with the router's `Next:` line. `commands/*.md`: frontmatter `description`, `argument-hint`; body: "Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/<x>/SKILL.md` with arguments: $ARGUMENTS" (verify the plugin command naming yields `/flow:spec` and `/flow:next`; if a nested dir is needed, use it). Run `plugins/flow/scripts/skills-lint` and `workflow-lint` on your output.

### F5 — deletions and cross-refs (model: sonnet; runs AFTER F1–F4). Owns: `plugins/flow/skills/feature/**` (delete; execution-prompt.md already moved by F4 — verify), `plugins/flow/skills/flow-to-issues/**` (delete), `plugins/flow/skills/flow-handoff/**` (delete), `plugins/flow/skills/shared/review.md` (delete), `plugins/flow/scripts/plan-lint`, `slice-overlap`, `slice-brief` (delete once nothing references them — grep first; if a hook/test still references plan-lint, leave it and report), `plugins/flow/skills/flow-deepen/SKILL.md`, `qa/SKILL.md`, `fix/SKILL.md`, `ultracode/SKILL.md`, `audit/SKILL.md` (cross-reference edits only), `plugins/flow/scripts/tests/test_lint.sh`, `test_wave5.sh`, `test_plugin_refs.sh`, `plugins/flow/flow-templates/CLAUDE.project.md`, `docs/reference/scripts.md`, `docs/reference/plugins.md`, `PROGRESS.md` (Now/Next only).
Delete, fix every dangling reference (`grep -rn 'flow-to-issues\|flow-handoff\|feature-plan.local\|slice-brief\|slice-overlap\|plan-lint\|/feature\b' plugins docs`), keep suites green (rewrite tests that tested deleted things into tests of their replacements or remove them with a note), run `skills-lint`, `flow doctor`.

### F6 — integration + dry run (model: opus; last). Owns: everything.
Both suites green; `skills-lint`, `workflow-lint`, `flow doctor`; then an end-to-end dry run in a temp git repo with a tiny node project: `new-spec --current`, hand-write a valid TASKS.md with 3 tasks (2 `[P]`), `flow next` through states 5→6→(commit+tick)→8→(PASS)→9→(Verified)→11, asserting each `Next:` line; `flow lint` on a lying tick. Report receipts, the final suite lines, and everything still open.
