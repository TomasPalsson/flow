# Spec 006 — loop engineering: `/flow:loop`, `flow loop`, `loop-gate.sh`

Frozen 2026-09-07. Evidence: `docs/research/12-loop-engineering-2026.md` (compendium) and `.skill-forge/loop/` (raw). Read the CURRENT files in this worktree, not the research doc's line numbers.

## Objective

Give the harness one loop primitive that runs a task **until a deterministic verifier passes**, never until the model says so. Two shapes share one contract file and one state machine:

- **session** — in the current Claude Code session; a Stop hook (`loop-gate.sh`) re-feeds the per-iteration prompt while the verifier is red. Bounded by Claude Code's 8-consecutive-block cap (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`), so this shape is for ≤ 8 iterations.
- **fresh** — an outer loop of fresh `claude -p` sessions (Huntley / snarktank / Anthropic long-running-harness shape); state lives on disk and in git. Unbounded by the block cap; bounded by iterations, minutes, dollars, stall and wedge detectors.

The model never declares completion. The verifier decides; a tamper check can veto a green verifier; the model's only honest early exit is `.claude/loop/BLOCKED.md`.

## Why (one line each, evidence-graded in the compendium)
- Self-reported completion is measurably unreliable (SEAL, PROCTOR, SpecBench; Anthropic's own harness: "a later agent instance would look around ... and declare the job done"). → verifier command, run by the harness.
- Anthropic's ralph-loop exits on a `<promise>` string and says "always rely on --max-iterations as your primary safety mechanism". → caps are first-class; the promise is gone.
- Fresh context per iteration is the practitioner consensus (Huntley: "the claude code plugin isn't it"; snarktank; Factory Missions; Codex long-horizon). → `fresh` shape.
- The 8-block cap is real and per turn. → `session` shape is explicitly small.
- Agents thrash and wedge (IAL-Scan: 68 confirmed non-terminating loops; "gutter" detector). → stall + wedge detectors.
- Agents weaken tests (SEAL: "only strengthen tests" prose failed). → tamper veto at DONE.

## Out of scope (hard boundaries)
- No changes to `stop-gate.sh`, `spec-gate.sh`, `hooks/lib/hookout.sh` (a sibling worktree is rewriting them). `loop-gate.sh` is a NEW file that only sources hookout.sh's public API.
- No task-list format is imposed. The loop takes a goal, a verifier and a prompt. Templates for `tasks.json` live in the skill, not in the CLI.
- No PRD generation, no GitHub issues, no agent teams.
- `bin/flow` grows by dispatch/help lines only; logic lives in `plugins/flow/bin/lib/loop.js` (Node ≥ 18, zero deps, bash-free).
- Hooks stay bash 3.2 / BSD portable; the hook contains no loop logic (it calls `flow loop tick --hook`).

## Shared contracts (frozen)

### K-A Layout (under the git toplevel; created by `flow loop init`)
```
.claude/loop/loop.md          the contract: frontmatter + per-iteration prompt body
.claude/loop/LEARNINGS.md     append-only; "## Codebase patterns" section first, then dated entries
.claude/loop/loop.log         one line per iteration (K-E)
.claude/loop/verify.last      full stdout+stderr of the last verifier run
.claude/loop/BLOCKED.md       written by the MODEL when it cannot continue; presence stops the loop
.claude/loop/iterations/NNN.json   fresh shape only: the child `claude -p --output-format json` payload
```
`flow init` appends to `.gitignore` (idempotent): `.claude/loop/*` and `!.claude/loop/LEARNINGS.md`.

### K-B `loop.md` contract
Frontmatter between the first two `---` lines, one `key: value` per line, no nesting, values unquoted except `verify`, `goal`, `prompt_file` which are JSON-string-quoted (so shell metacharacters survive). Everything after the second `---` is the per-iteration prompt body. Keys:
```
version: 1
slug: <kebab-case from goal, ≤ 40 chars>
goal: "<one sentence>"
verify: "<shell command; exit 0 = done>"
shape: session | fresh
status: active | done | suspect | stopped
stop_reason: <empty | cap | time | budget | stall | wedge | blocked | manual | error>
session_id: <Claude Code session id for shape=session; empty for fresh>
iteration: <int, completed iterations; 0 at init>
max_iterations: <int; default 8 for session, 30 for fresh>
max_minutes: <int; default 0 = none for session, 480 for fresh>
max_usd: <number; default 0 = none; fresh only>
stall_after: <int; default 3>
verify_timeout: <seconds; default 600>
permission_mode: <default auto; fresh only>
model: <empty = CLI default; fresh only>
max_turns: <int; default 0 = none; fresh only>
base: <HEAD sha at init>
test_files: <count of test files at init, K-F>
started_at: <ISO-8601 UTC>
finished_at: <empty until terminal>
cost_usd: <number; fresh only; sum of children's total_cost_usd>
finish_reported: 0 | 1   (session shape: the one-time finishing block was delivered)
```
Unknown keys are preserved on rewrite. Rewrites are atomic (write `loop.md.tmp.<pid>` then rename). A contract whose `iteration`/`max_iterations` are non-numeric or whose `verify` is empty is **corrupt**: every command reports `corrupt contract: <why>` and `tick` returns `allow` (the loop self-disarms, ralph-loop pattern) after renaming the file to `loop.md.corrupt`.

### K-C `flow loop` CLI (`plugins/flow/bin/lib/loop.js`, `module.exports = { run(argv, cwd, env) }` returning an exit code; `bin/flow` dispatches `loop` to it)
All commands anchor at `git rev-parse --show-toplevel` (exit 1 `not a git repository` otherwise). `--json` on every read command. Help on `flow loop --help` and `flow loop <cmd> --help`.

- `init "<goal>" --verify "<cmd>" [--shape session|fresh] [--prompt-file <path> | --prompt "<text>"] [--session <id>] [--max-iterations N] [--max-minutes N] [--max-usd N] [--stall-after N] [--verify-timeout S] [--permission-mode M] [--model M] [--max-turns N] [--allow-green] [--force]`
  - Refuses (exit 1) when an `active` contract exists unless `--force` (which first `stop`s it with reason `manual`).
  - Runs the verifier once (K-D). If it passes and `--allow-green` is absent: exit 1 with `verifier already passes; nothing to loop (use --allow-green to loop anyway)`. **Red first.**
  - Records `base`, `test_files`, `started_at`; writes the contract, an empty `LEARNINGS.md` (only if absent), and the first log line `init`. Prompt body: `--prompt-file`/`--prompt` if given, else the default body (K-G).
  - Prints a 6-line summary (shape, goal, verify, caps, files) and, for shape=session, the line `armed: loop-gate.sh will re-feed the prompt on every Stop until the verifier passes`.
- `check [--json]` — runs the verifier (K-D) and the tamper check (K-F); prints `verdict: pass|fail|suspect`, `verify_rc`, `tamper: [...]`, and the last 40 lines of output. Exit 0 pass, 1 fail, 2 suspect. Never mutates the contract.
- `tick [--json|--hook] [--session <id>]` — one state transition (K-H). `--hook` prints **exactly** the Claude Code Stop JSON to emit (`{"decision":"block","reason":...}`) or nothing (allow), always exit 0; this is the only thing `loop-gate.sh` consumes.
- `run [--max-iterations N] [--max-minutes N] [--max-usd N] [--permission-mode M] [--model M] [--max-turns N] [--dry-run] [--no-checkpoint] [--worktree]` — the fresh-shape driver (K-I). Exit 0 on `done`, 2 on `suspect`, 1 on any `stopped`.
- `status [--json]` — contract summary + last log line + last 20 lines of `verify.last`. Exit 0 (exit 3 when no contract).
- `stop [--reason <text>]` — sets `status: stopped`, `stop_reason: manual` (or the given text), `finished_at`; log line. Exit 0 even when nothing was active (prints `no active loop`).
- `log [-n N]` — last N log lines (default 20).

### K-D Verifier run
`sh -c "<verify>"` with cwd = toplevel, env `CI=true`, `FLOW_LOOP=1`, stdout+stderr merged into `.claude/loop/verify.last`, killed after `verify_timeout` seconds (rc 124 → treated as fail with `verify timed out after N s` appended). Exit code 0 = pass. The signature of a run is `cksum` of the first 60 lines of output with hex hashes, timestamps and durations masked (`[0-9a-f]{7,40}` → `H`, `[0-9]+(\.[0-9]+)?(ms|s)` → `T`).

### K-E Log line (`loop.log`, append-only, one line per event)
`<iso-utc> <event> iter=<n> head=<before>..<after> verify=<rc> sig=<sig> changed=<0|1> cost=<usd|-> dur=<s> <note>` with events `init | iter | done | suspect | stop | checkpoint | error`. `flow loop log` prints these verbatim.

### K-F Tamper check (deterministic, runs at every `check`)
- `test_files` now < `test_files` at init → `test files removed: <n> → <m>`.
- `git diff <base> -- <test paths>` added lines match `\.skip\(|\.only\(|it\.todo\(|xfail|@pytest\.mark\.skip|#\[ignore\]|t\.Skip\(` → `skip/xfail added in <file>`.
- Any added line in `git diff <base>` changing `stopGate` to false or `.claude/flow.config.json` thresholds (same regex as tamper-notice) → `gate config weakened`.
- The verifier command string in the contract differs from what `init` wrote (guard: `verify_sha` key, cksum of the verify string) → `verifier rewritten`.
Test paths: `*_test.*`, `*.test.*`, `*.spec.*`, `test_*.*`, `tests/`, `__tests__/`, `spec/`. Counting uses `git ls-files` plus untracked non-ignored files. A green verifier with any tamper finding is `suspect`, never `pass`.
**Delta 2026-09-07 (adversary review):** "added lines" means the `git diff <base>` for tracked files **plus every line of every untracked, non-ignored file** (a file the model never staged is not invisible); `gate config weakened` also fires when a numeric `max*`/`complexity`/`threshold` key in a gate-config file changes value between the removed and added lines (the tamper-notice rule), and names the file. K-H rule 3: an empty `--session` against a contract bound to a session is "cannot judge" → allow. K-I: the error-streak stop is delivered by the next tick as a `finish`, like every other stop.

### K-G Default prompt body (written by `init` when no prompt is given; the skill usually supplies its own)
```
You are one iteration of a loop. The loop, not you, decides when the goal is met: it runs
`{verify}` after every iteration and stops when it exits 0. Do not claim completion.

Goal: {goal}

Each iteration:
1. Read .claude/loop/LEARNINGS.md (Codebase patterns first) and `git log --oneline {base}..HEAD`.
2. Run the verifier yourself and read the failure. Pick the ONE smallest change that moves it.
3. Make that change. Run the verifier again. Commit on green with a message that names the change.
4. Append one dated entry to .claude/loop/LEARNINGS.md: what you did, what you learned, what is next.
5. Stop. The loop will re-run the verifier and start the next iteration.

Never edit, delete, skip or weaken a test, and never change the verifier command or gate config,
to make the verifier pass; the loop checks for that and will mark the run suspect.
If the goal cannot be met (wrong premise, missing access, contradictory tests), write
.claude/loop/BLOCKED.md with what you tried and why it cannot work, then stop.
```
`{verify}`, `{goal}`, `{base}` are substituted at init.

### K-H `tick` state machine (both shapes; `run` calls the same function in-process)
Input: contract, `--session <id>` (from the hook's `session_id`), now.
1. No contract, or `status != active` and `finish_reported = 1` → `allow`.
2. `shape = fresh` and called from the hook (`--hook`) → `allow` (the driver owns fresh loops; a child `claude -p` session's own Stop hook must never block).
3. `shape = session` and `session_id` non-empty and ≠ `--session` → `allow` (ralph-loop session isolation).
4. `status ∈ {done, suspect, stopped}` and `finish_reported = 0` → set `finish_reported = 1`, return **`finish`** with the K-J finishing reason (one last continuation so the model can report); the next tick hits rule 1.
5. `BLOCKED.md` exists → `status: stopped`, `stop_reason: blocked` → rule 4.
6. Run `check`. `pass` → `status: done`; `suspect` → `status: suspect` → rule 4 (iteration counted, log `done`/`suspect`).
7. Fingerprint = `HEAD` sha + cksum of `git status --porcelain` + cksum of `git diff`. Compare with the fingerprint stored at the previous tick (`fp` key): equal → `unchanged` streak +1 else reset. Verify signature equal to previous `sig` for `stall_after` consecutive iterations with changed fingerprints → `stop_reason: wedge`. `unchanged` streak ≥ `stall_after` → `stop_reason: stall`.
8. `iteration += 1`; `iteration ≥ max_iterations` → `cap`; `max_minutes > 0` and elapsed ≥ → `time`; `max_usd > 0` and `cost_usd ≥` → `budget`. Any stop reason → `status: stopped` → rule 4.
9. Otherwise log `iter` and return **`continue`** with reason = K-J continuation text.
Every path that changes status writes `finished_at` on terminal states and appends a log line.

### K-I `run` (fresh driver) per iteration
- Preconditions: contract `active`, `shape: fresh`; `claude` on PATH (else exit 2 with `claude CLI not found; run the loop from an interactive session with shape=session instead`).
- `--dry-run`: print the plan (caps, the exact `claude -p` argv with the prompt replaced by `<prompt: N chars>`, and the tick rules) and exit 0 without spawning.
- Loop: `tick` (in-process) first — this runs the verifier BEFORE any child is spawned, so an already-green goal ends at iteration 0 ("declared done by the verifier, not the model"). On `continue`: spawn `claude -p <prompt> --output-format json --permission-mode <mode> [--model M] [--max-turns N] [--max-budget-usd <remaining>]` with cwd = toplevel and stdin closed, prompt = K-J continuation text + body. Save the JSON to `iterations/NNN.json`; add `total_cost_usd` to `cost_usd`; a non-zero exit or `is_error: true` → log `error` and count it as an unchanged iteration (three consecutive errors → `stop_reason: error`).
- After the child: if `--no-checkpoint` absent and the tree is dirty → `git add -A && git commit -q -m "loop(<slug>) iteration <n>: checkpoint"`; log `checkpoint`.
- `--worktree`: before the loop, `git worktree add -b loop/<slug> .claude/worktrees/loop-<slug> HEAD` (reuse if present), copy `.claude/loop/` into it, and run everything with that path as toplevel; print the path first.
- Prints one status line per iteration to stdout (the K-E log line) and, at the end, `flow loop status`.

### K-J Reason text (what the model reads)
Continuation (both shapes):
```
[flow loop] iteration <n+1> of <max> — goal: <goal>
verifier `<verify>` exited <rc>; last lines:
<up to 40 lines of verify.last>
<"stall warning: no change in the last k iterations" when unchanged ≥ 1>
Read .claude/loop/LEARNINGS.md, then make the ONE smallest change that moves the verifier. Do not claim completion; the loop checks.
<prompt body>
```
Finishing (`finish`), by status: `done` → "[flow loop] finished: verifier passed on iteration <n> (<duration>, <cost>). Summarise `git log --oneline <base>..HEAD`, append the final LEARNINGS entry, and end the turn."; `suspect` → "[flow loop] verifier passed but the run is SUSPECT: <findings>. Do not fix this now. Report the findings and end the turn; a human decides."; `stopped` → "[flow loop] stopped: <reason> after <n> iterations. Report what was attempted, what remains, and what blocked progress; do not continue working." Reasons are capped at 8,000 characters (Claude Code truncates hook output at 10,000).

### K-K Hook `plugins/flow/hooks/loop-gate.sh` (Stop; registered in `hooks.json` after stop-gate, timeout 660, `statusMessage: "flow: loop tick…"`)
```
. lib/hookout.sh; hook_skip_if_off
[ -f "$(hook_project_dir)/.claude/loop/loop.md" ] || exit 0      # fast path: no node spawn
have node || exit 0                                              # cannot judge → allow
out=$(node "$HERE/../bin/flow" loop tick --hook --session "$(hook_field .session_id)" 2>/dev/null) || exit 0
[ -n "$out" ] && printf '%s\n' "$out"; exit 0
```
It never reads `stop_hook_active` (the loop *wants* consecutive blocks; the 8-cap and the contract caps bound it). Tests feed a fake `flow` via `CC_FLOW_BIN` (env override honoured by the hook) so the bash tests do not depend on node behaviour.

### K-L `flow init` / `flow doctor` / `flow next`
- `init`: the `.gitignore` lines (K-A); a `.claude/loop/` dir is NOT created (init of a loop creates it).
- `doctor`: WARN `loop: active contract since <started_at> (shape <s>, iteration <n>/<max>) — flow loop status | flow loop stop` when `.claude/loop/loop.md` is `active`; FAIL when it is corrupt; `loop-gate.sh` joins the wired-hook check list.
- `next`: when a contract is `active`: shape=session → `Next: flow loop status`; shape=fresh → `Next: flow loop run`. Evaluated before the existing PROGRESS.md resume line. One early branch only.

### K-M Skill `plugins/flow/skills/loop/` (orchestrator-owned; not a developer slice)
`SKILL.md` (`name: loop`, `user-invocable: true`, `argument-hint`), `references/verifier-design.md`, `references/loop-prompt.md` (per-iteration prompt + `tasks.json` template), `references/failure-modes.md`. Invocation `/flow:loop <goal> --verify "<cmd>" [--fresh] [--max-iterations N] ...`.

## Slices (developer-owned files; nothing else)
- **Slice 1** — `plugins/flow/bin/lib/loop.js`, `plugins/flow/bin/flow` (dispatch + help + doctor/next/init deltas of K-L), `plugins/flow/scripts/tests/test_loop.sh`, `plugins/flow/scripts/tests/test_cli.sh` (only to add loop-gate.sh to the wired-hook fixture if the doctor check requires it).
- **Slice 2** — `plugins/flow/hooks/loop-gate.sh`, `plugins/flow/hooks/hooks.json` (one Stop entry), `plugins/flow/hooks/tests/test_loop_gate.sh`. Depends on Slice 1 only for the `--hook` output shape (frozen above), so it can be built against a stub.
- **Slice 3** — `docs/reference/workflows-and-cli.md` (a `flow loop` section), `docs/reference/hooks.md` (a `loop-gate.sh` row), `plugins/flow/skills/fix/SKILL.md` + `plugins/flow/skills/fix/execution-prompt.md` (replace the ralph-loop path with `/flow:loop`; keep the fallback path), `plugins/flow/README.md` (layout lines). Depends on Slice 1 and 2 for exact names.

## Oracle
Both suites green (`bash plugins/flow/hooks/tests/run.sh`, `bash plugins/flow/scripts/tests/run.sh`), `plugins/flow/scripts/skills-lint`, `node plugins/flow/bin/flow doctor`; every K-contract has at least one `t_loop_*` test naming it; an end-to-end dry run in a `tmp_repo`: `flow loop init "x" --verify "test -f done.txt"` → red; touch done.txt → `flow loop check` pass; `tick --hook` prints the finishing block once, then nothing.
