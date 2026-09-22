---
name: loop
description: "Run a task in an unattended loop until a deterministic verifier passes — never until the model says so. Use WHENEVER the user says /flow:loop, /loop-until, 'loop until', 'keep going until the tests pass', 'ralph', 'ralph loop', 'run this overnight', 'grind through the backlog', 'iterate until green', 'don't stop until', 'autonomous loop', 'unattended', 'loop engineering', or hands over a task with a runnable check and wants to walk away. Two shapes: in-session (Stop hook, ≤ 8 iterations, you watch) and fresh (outer loop of fresh `claude -p` sessions via `flow loop run`, capped by iterations/minutes/dollars/stall). Do NOT use for: polling on a timer (/loop 5m), a goal only a reader can judge, a one-shot fix (/fix), or a feature with human decisions inside it (/flow:next)."
user-invocable: true
argument-hint: "<goal> --verify \"<cmd>\" [--fresh] [--max-iterations N] [--max-minutes N] [--max-usd N] [--worktree]"
---

# /flow:loop — the verifier decides, not the model

A loop is a harness that re-invokes the agent while **a check the agent cannot edit** is red. The model in the loop has no completion signal: it cannot say "done", only work, commit, and stop; the harness runs the verifier and decides. This is the one design choice that separates loops that ship from loops that lie. Evidence and the full compendium: `docs/research/12-loop-engineering-2026.md` in the flow repo.

Facts that shape every decision below (verified against the vendor docs on 2026-09-07):

- A Stop hook may block a turn at most **8 times in a row** (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`). An in-session loop is therefore an 8-iteration tool. Anything longer is an outer loop of fresh `claude -p` sessions.
- Anthropic's ralph-loop plugin exits on a self-reported `<promise>` and says "always rely on `--max-iterations` as your primary safety mechanism". Caps are the mechanism; the promise is not. This skill has no promise.
- Agents weaken tests when a prose rule is all that stops them (SEAL, 2026). The loop diffs the test layer and marks a green run **suspect** when it finds fewer test files, a new skip, a loosened threshold, or a rewritten verifier.
- Fresh context per iteration is the practitioner consensus (Huntley, snarktank, Anthropic's long-running harness, Factory Missions); state lives in git plus two files: a task list and an append-only learnings log.

## Step 0 — `--yolo`: bootstrap, refuse, or arm, in one command

`/flow:loop "<idea>" --yolo` turns a one-line idea into an armed, unattended run with no question asked and no gate in the middle. Before you leave, this step is what tells you exactly what happens next:

1. **Bootstrap.** From the idea alone, produce a spec, a task list and a composed verifier — no interruption for approval. Every task item starts unproven and carries its own runnable check; the composed verifier requires every item proven AND its scoped test command green, scoped to the files the spec touches rather than the whole suite.
2. **Refuse.** Before anything is armed, `flow loop init` runs the negative control: it deliberately breaks the code the first task names and proves the verifier goes red. A verifier that survives the break, or a tree that cannot be restored, refuses to arm and leaves nothing half-armed.
3. **Arm.** Once the control passes, the run starts on its own branch, in its own working copy, and never commits to the branch you were on. Its children deny anything requiring approval rather than waiting for you, bounded by the caps in Step 4.

Whether the run finishes or hits a cap, it ends at a draft pull request naming what remains; it never records that a human verified the result — that stays yours to do when you come back.

**MANDATORY — READ ENTIRE FILE** before writing the bootstrap yourself: load [`references/yolo-bootstrap.md`](references/yolo-bootstrap.md).

## Step 1 — Pick the shape

| Question | session (Stop hook) | fresh (`flow loop run`) |
|---|---|---|
| Expected iterations | ≤ 8 | anything |
| You are watching | yes | no; report at the end |
| Task size | one verifier, one module: "make this test pass", "get lint clean", "finish this migration" | a backlog, a greenfield build, "until the suite is green", overnight |
| Context | accumulates (compaction will fire) | fresh every iteration |
| Cost cap | none (session) | `--max-usd`, summed from each child's `total_cost_usd` |

`--fresh` or any of `--max-usd`, `--worktree`, `--max-iterations > 8` selects fresh. Default is session. State the shape and why in one line before arming.

## Step 2 — Write a verifier that can fail

**MANDATORY — READ ENTIRE FILE**: load [`references/verifier-design.md`](references/verifier-design.md) before writing the command. Do not load `loop-prompt.md` yet; it is Step 3's file.

If the goal is a UI behaviour or a visual target, also load [`references/browser-verifier.md`](references/browser-verifier.md) — three named traps there each produce a verifier that cannot fail.

The verifier is one shell command, exit 0 = goal met, run by the harness with `CI=true` from the repo root, bounded by `verify_timeout` (600 s). Rules that decide whether the loop can work at all:

1. **It must be red now.** `flow loop init` runs it once and refuses a green verifier ("nothing to loop"). If the goal is already met, the answer is not a loop.
2. **It must be able to go green by editing source, not by editing the check.** A verifier that greps for a phrase the model can type is a promise in disguise. Prefer the test runner, the type checker, the build, an artefact check (`test -f dist/app.js && node -e ...`), a count (`test $(grep -rl TODO src | wc -l) -eq 0`).
3. **Compose with `&&`.** "Tests pass AND lint clean AND no TODOs" is one command. Put the fastest, most-discriminating check first.
4. **No network, no prompts, no state outside the repo.** The same command must give the same answer twice.

If the goal cannot be written as a command, write the closest command you can and keep the judgement for a human gate at the end; do not put an LLM judge in the exit path.

## Step 3 — Write the per-iteration prompt and the task list

**MANDATORY — READ ENTIRE FILE**: load [`references/loop-prompt.md`](references/loop-prompt.md). Do not reload `verifier-design.md`; the verifier is fixed by now.

Every iteration receives the same stack: where it is (iteration n of N, goal, verifier), what is red (the verifier tail), what was learned (`.claude/loop/LEARNINGS.md`, patterns first, and `git log <base>..HEAD`), the one-task rule, the prohibitions with their consequence, the honest exit, then your task body. `flow loop` supplies everything but the body; write the body to `.claude/loop/prompt.md` and pass `--prompt-file`.

The body names the task list and the rule for choosing from it. For a backlog use the `tasks.json` template from the reference (every item `passes: false`, runnable acceptance criteria, small enough for one iteration). For a single goal the body can be three lines. Never put a completion phrase in the body.

## Step 4 — Arm it

```bash
flow loop init "<goal, one sentence>" --verify "<cmd>" \
  [--shape session|fresh] [--prompt-file .claude/loop/prompt.md] \
  [--max-iterations N] [--max-minutes N] [--max-usd N] [--stall-after N]
```

`init` writes `.claude/loop/loop.md` (the contract), runs the verifier once (must be red), records the base commit and the test-file count, and prints the caps. Defaults: session 8 iterations; fresh 30 iterations, 480 minutes, `stall_after` 3.

- **session**: just start working on the task in this turn. On every Stop, `loop-gate.sh` runs `flow loop tick`, which runs the verifier and either re-feeds the prompt with the verifier tail or finishes. You will see `[flow loop] iteration n of N` at the top of each continuation. Do not run `flow loop tick` yourself.
- **fresh**: run the driver in the background and end the turn — the loop must not run inside this session's context:

```bash
flow loop run [--worktree] [--permission-mode auto] [--model <m>] [--max-turns N]   # Bash, run_in_background: true
```
`--dry-run` first prints the exact `claude -p` argv, the caps and the tick rules without spawning anything. `--worktree` builds on `loop/<slug>` under `.claude/worktrees/`, so a bad night is a `git worktree remove`, not an incident. Print the log path (`.claude/loop/loop.log`) and `flow loop status` to the user, then end the turn; the user resumes with `flow loop status` or `flow next`.

Inside an iteration (either shape), you are the model in the loop. Read the learnings, run the verifier yourself, make the ONE smallest change that moves it, run it again, commit on green with a message that names the change, append one dated learnings entry, stop. Use subagents for expensive reads (many), and exactly one for the build/test run. Never claim completion. If the goal cannot be met — wrong premise, missing access, contradictory tests — write `.claude/loop/BLOCKED.md` (what you tried, why it cannot work) and stop; the loop ends with `stopped: blocked`, which is a true statement.

## Step 5 — Finish honestly

The loop ends in one of four states; the log line says which, and `flow loop status` shows it. **MANDATORY when the status is anything but `done`**: load [`references/failure-modes.md`](references/failure-modes.md) — it maps every `stop_reason` to what the log shows and the next move.

| Status | Meaning | What you do |
|---|---|---|
| `done` | verifier green, tamper clean | summarise `git log --oneline <base>..HEAD`, final learnings entry, `/wrap` |
| `suspect` | verifier green but the test layer changed for the worse | do **not** fix it in the loop; report the findings verbatim; a human decides |
| `stopped: cap|time|budget` | caps hit | report what was attempted and what remains; the cap is a wedge signal, not a budget to raise — investigate before re-arming |
| `stopped: stall|wedge|blocked|error` | no change N×, same failure N× with churn, BLOCKED.md, or 3 child errors | read the last verifier output and `BLOCKED.md`; the fix is a better task split or a better verifier, not more iterations |
| `stopped: manual` | `flow loop stop` was run (by the user, `flow doctor`'s advice, or `init --force`) | report the state at the stop; nothing to investigate unless the user asks |

Promote durable learnings to PROGRESS.md rulings or CLAUDE.md at `/wrap`; the loop's learnings file is per run. End with `Next:` from `flow next`.

## Anti-patterns — never

- **Never write a completion phrase into a loop prompt.** The harness checks; the model reports. A phrase the model can type is a lie waiting to be told under a cap.
- **Never raise a cap to get past a wedge.** Retries saturate after two or three rounds and do not reduce test gaming (SpecBench: more search "often worsened" it). Split the task or fix the verifier.
- **Never let the verifier be something the iteration can edit** (a script inside the task's own files, a threshold in a config the prompt touches). The contract cksums the verifier string; the tamper check watches tests and gate config; CI on a protected branch is the backstop the agent's shell cannot reach.
- **Never run a fresh loop inside the current session's turn.** It is an outer loop by definition; run it in the background and end the turn.
- **Never arm a loop the user did not ask for.** The skill is user-invocable; the hook only reads a contract the CLI wrote.
- **Never edit LEARNINGS.md history.** Append. When the task list rots, regenerate it wholesale (a planning iteration) rather than patching it.

## Recovery

| Symptom | Cause | Do |
|---|---|---|
| `init` says "verifier already passes" | goal met, or verifier cannot fail | pick a verifier that is red for the real gap; `--allow-green` only for maintenance loops |
| Continuations stop after 8 with a block-cap warning | session shape hit the engine cap | `flow loop status`; re-arm as fresh, or split the task |
| `corrupt contract` in status | hand-edited `loop.md` | `flow loop stop`, `init` again |
| Child iterations end in `error` | `claude -p` failed: auth, permission mode, budget | read `.claude/loop/iterations/NNN.json`; `--dry-run` shows the argv; try `--permission-mode acceptEdits` |
| `suspect` with "test files removed" | a test file was deleted or moved | restore it; if the move was legitimate, say so and re-run `flow loop check` |
| Stale contract from another session | `flow doctor` warns | `flow loop stop --reason stale` |
