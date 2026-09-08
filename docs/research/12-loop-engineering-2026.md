# 12 — Loop engineering, 2026

How to run a coding agent in an unattended loop until a goal is met, and what breaks when you do. Written 7 September 2026 from a 10-angle research sweep (22 agents, 40 claims re-fetched and confirmed, 6 unsupported), two source-level deep dives, and direct reads of the vendor docs and the four canonical loop implementations. Raw material: [`raw/loop-engineering/`](raw/loop-engineering/). What it produced in this repo: §10.

**Evidence grades used below.** **A** — vendor doc, original post or source file, read verbatim on 2026-09-07. **B** — peer-reviewed or arXiv result with a reproducible method, re-fetched. **C** — practitioner report, single source, not re-verified. **X** — circulating claim found to be wrong (§11). Build on A and B without hedging; treat C as a lead.

---

## 0. The one-paragraph version

A loop is a harness that re-invokes the agent while a **check the agent cannot edit** is red. Everything else is detail. The four things the field has converged on since Huntley's July 2025 post: (1) **fresh context per iteration**, with state in git plus two files (a task list and an append-only learnings log); (2) **one small task per iteration, one commit on green**; (3) **the model never decides completion** — a deterministic verifier does, and a tamper check can veto it; (4) **cap everything** (iterations, minutes, dollars, no-progress streaks) and treat a hit cap as a wedge to investigate, not a budget to raise. Anthropic's own ralph-loop plugin, whose exit is a self-reported `<promise>` string, says it plainly: "Always rely on `--max-iterations` as your primary safety mechanism." (A)

---

## 1. Three loops, not one

Every coding agent already runs a loop; the question is which layer you are engineering.

| Layer | What repeats | Who ends it | Claude Code primitive | Bound |
|---|---|---|---|---|
| **Tool loop** (inside one turn) | model → tool call → result → model | the model, when it stops calling tools | the agent loop itself; `--max-turns` in `-p` | context window; auto-compaction |
| **Turn loop** (inside one session) | a whole turn, re-fed by a Stop hook or evaluator | a hook script, a prompt-based evaluator, or a cap | Stop hook `decision:"block"`; `/goal`; `/loop <interval>`; `ScheduleWakeup` | **8 consecutive blocks** per turn (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, 0 disables); `/loop` 7-day expiry |
| **Session loop** (outer, fresh context) | a whole `claude -p` process | a driver script | none built in — a bash `while`, `flow loop run`, Routines, background sessions | iterations, minutes, dollars, stall detectors — whatever the driver enforces |

Verified facts that decide the design (all **A**, `code.claude.com/docs/en/hooks`, `goal`, `scheduled-tasks`, `env-vars`, `cli-reference`):

- Stop hooks receive `stop_hook_active`, `last_assistant_message`, `background_tasks[]`, `session_crons[]`. "Claude Code overrides the hook and ends the turn after 8 consecutive blocks." `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` default 8; "Set to 0 to disable the cap."
- Block with `{"decision":"block","reason":"..."}`; or `hookSpecificOutput.additionalContext` for "non-error feedback ... shown in the transcript as hook feedback rather than a hook error" — same cap, same `stop_hook_active`.
- "All matching hooks run in parallel." Multiple `additionalContext` values are all delivered; there is no documented merge rule for two competing `block` reasons.
- Hook output is capped at 10,000 characters; the transcript file "may lag" — read `last_assistant_message`, not `transcript_path`.
- `/goal` is "a wrapper around a session-scoped prompt-based Stop hook"; its evaluator (Haiku by default) "doesn't run commands or read files independently". It stops on met / impossible / unrecoverable error, and "If Claude keeps answering the evaluator without making progress (no tool use for several turns in a row), Claude Code stops the loop". Bound it with a clause in the condition ("or stop after 20 turns"). Works headless: `claude -p "/goal ..."`.
- `/loop 5m <prompt>` is a session cron; `/loop <prompt>` self-paces via `ScheduleWakeup` (1 min–1 h); bare `/loop` runs `.claude/loop.md`. Tasks expire after 7 days and fire only while the session is idle.
- `claude -p` accepts `--max-turns`, `--max-budget-usd` (subagent spend counts), `--permission-mode auto|acceptEdits|bypassPermissions`, `--output-format json` (payload includes `total_cost_usd`, `session_id`), `--json-schema`. `--bare` skips hooks, skills and CLAUDE.md — the opposite of what a harness loop wants.

**Consequence.** An in-session Stop-hook loop is an 8-iteration tool. Anthropic's ralph-loop plugin advertises `--max-iterations 50`; with default settings that number is unreachable in one turn. Anything longer is a session loop, and a session loop needs its own driver.

---

## 2. Twelve principles, ranked by evidence

Each principle names the mechanism that enforces it in this repo (§10). A principle without a mechanism is a request.

| # | Principle | Grade | Evidence (short) | flow mechanism |
|---|---|---|---|---|
| 1 | **The verifier, not the model, decides completion.** | B | SEAL (arXiv 2607.24300): 15 of the policies with self-reported scores > 0.70 scored below random in deployment; a "never weaken tests" constraint did not close the gap. PROCTOR (2609.02246): judge-reported 100% vs true 68%. Anthropic's harness post: agents "declare the job done" after seeing progress. | `flow loop check` runs `verify` itself; the model has no completion signal at all |
| 2 | **Cap iterations, time and money; a hit cap is a wedge signal.** | A | ralph-loop README: "Always rely on `--max-iterations` as your primary safety mechanism." IAL-Scan (2607.01641): 68 confirmed non-terminating loops in 47 real projects. | `max_iterations`, `max_minutes`, `max_usd`; `stop_reason: cap|time|budget` |
| 3 | **Fresh context per iteration; state on disk and in git.** | A/C | Huntley: `while :; do cat PROMPT.md \| claude-code; done`, "the claude code plugin isn't it"; snarktank: "Each iteration is a fresh instance with clean context"; Anthropic harness post: compaction "isn't sufficient"; Factory Missions: "fresh worker sessions with clean, non-accumulated context". Context rot (Chroma, C): quality decays well below the window limit. | shape `fresh` = `flow loop run` spawning `claude -p` per iteration |
| 4 | **One small task per iteration, one commit on green.** | A | Huntley: "one item per loop. I need to repeat myself here"; Anthropic: "work on only one feature at a time ... critical"; snarktank: "small enough to complete in one context window". | the K-G prompt; `checkpoint` commits; `tasks.json` template in the skill |
| 5 | **Detect no-progress; do not wait for the cap.** | B/C | SWE-PRM (2509.02360): looping and "failure to stop once a solution has already been reached" are the dominant mid-trajectory pathologies; Cursor's "gutter" detector (C); the (tool,args,result)-hash pattern (C). | `stall` (fingerprint unchanged N×) and `wedge` (same verify signature N× with changing files) |
| 6 | **Tamper-check the verification layer; a green run can be suspect.** | B | Building-to-the-Test (2606.28430): near-perfect with the oracle in the loop, "dead or absent" without it; SpecBench (2605.21384): all frontier agents saturate visible tests while held-out scores diverge; more search "often worsened" hacking. | K-F tamper veto → `status: suspect`; `tamper-notice.sh` per edit; tests and gate config are named "never edit" in the prompt |
| 7 | **Give the model one honest exit that is not "done".** | A | ralph-loop's exact-match promise "cannot express multiple states (SUCCESS vs BLOCKED)"; its own escape-hatch advice is to "document the blocker, list attempted solutions". | `.claude/loop/BLOCKED.md` stops the loop with `stop_reason: blocked` |
| 8 | **Allocate the same context every iteration: plan, learnings, git log, verifier output.** | A | Huntley: "allocate the stack the same way every loop"; Anthropic: "Read the git logs and progress files to get up to speed"; snarktank: read `progress.txt` "Codebase Patterns section first". | K-J continuation text: verify tail + LEARNINGS.md + `git log base..HEAD` |
| 9 | **Append learnings; never rewrite them. Regenerate the plan wholesale when it rots.** | A | snarktank: "APPEND to progress.txt (never replace)"; Huntley: "I throw it out often". | `LEARNINGS.md` append-only; the skill's re-plan step |
| 10 | **Use JSON for the task list the agent must not corrupt.** | A | Anthropic: "the model is less likely to inappropriately change or overwrite JSON files compared to Markdown files"; features start `passes:false`; "It is unacceptable to remove or edit tests". | `tasks.json` template; the contract's `verify` string is cksum-guarded |
| 11 | **Isolate: worktree or clone, checkpoint per iteration.** | A/C | Anthropic: git lets the model "revert bad code changes and recover working states"; Factory: "Git is the source of truth"; worktree fan-out reports (C). | `flow loop run --worktree`; `git-guard.sh` denies the destructive commands |
| 12 | **Gate at milestones; expect to be interrupted.** | A | Factory: long-horizon autonomy is "an open industry problem", ships checkpoints; Codex long-horizon post: gates at every milestone. | `max_iterations` defaults 8 (session) / 30 (fresh); `/wrap` between runs; `flow next` |

---

## 3. Loop shapes compared

| Shape | Mechanism | Context | Bound by | Best for | Do not use for |
|---|---|---|---|---|---|
| **Stop-hook loop, in session** (`/flow:loop`, ralph-loop plugin) | hook returns `block` with the next prompt | accumulates; compaction fires | 8 consecutive blocks; hook timeout 600 s | ≤ 8 verifier-driven passes while you watch: make this test pass, get lint clean, finish the migration of one module | anything overnight; anything with > 8 expected iterations |
| **`/goal`** | prompt-based Stop hook, Haiku judges the transcript | accumulates | model verdict; "no tool use for several turns"; clause in the condition | tasks whose evidence lands in the transcript and needs judgement (an acceptance list, a backlog) | tasks with a runnable check (use a verifier); anything needing file reads by the judge |
| **`/loop` / `ScheduleWakeup`** | session cron | accumulates between fires | 7 days; session must stay open and idle | polling (CI, a deploy, a PR), periodic maintenance | driving work to a goal; unattended completion |
| **Fresh outer loop** (`flow loop run`, Huntley, snarktank, Anthropic harness, Factory) | driver spawns `claude -p` per iteration | fresh every time; state in git + files | iterations, minutes, dollars, stall, wedge, `BLOCKED.md` | overnight builds, backlogs, migrations, "until the suite is green" | interactive design work; tasks with human decisions inside |
| **Cloud Routines / background sessions** | scheduled cloud run or `claude --bg` | fresh per run | vendor limits; `claude/`-prefixed branches only for Routines | nightly triage, scheduled reports | anything needing local secrets or a local browser |

---

## 4. Exit-condition design

**The exit stack** (most reliable first). Each layer runs only if the previous one passed.

1. **Deterministic verifier** — a command with an exit code, hermetic (`CI=true`, no network, bounded runtime), run by the harness, not by the model. Tests, typecheck, build, a file-count, a grep for `TODO`, an `ls` of expected artefacts. If the goal cannot be written as a command, write one that approximates it and put the residual judgement at a human gate.
2. **Tamper veto** — a green verifier with fewer test files than at start, a new `.skip`/`xfail`, a loosened threshold, or a rewritten verifier string is `suspect`, never `done`. SEAL showed prose ("only strengthen tests") does not do this job; a diff check does.
3. **Held-out / canary checks** — SpecBench's operational metric is visible-pass minus held-out-pass; PROCTOR's sharpest rule: engineer canaries so that a perfect score is itself a cheating signal. In practice: keep one test job the agent's shell cannot run (CI on a protected branch) and compare.
4. **No-progress detectors** — fingerprint unchanged for N iterations (stall) or the same failure signature for N iterations while files churn (wedge). Semantic early-stopping (2606.27009, C) cut tokens 38% at equal quality by halting when consecutive outputs stop moving; the same idea, cheaper, is a hash.
5. **Hard caps** — iterations, wall-clock, dollars. Community defaults cluster at 10 (snarktank) to 30 (`MAX_ITERS=30`).
6. **Engine cap** — Claude Code's 8-block cap. Leave it on for unattended in-session work.

**Where an LLM judge belongs.** Beside the stack, not in it. EvilGenie (2511.21654) found an LLM judge "highly effective at detecting reward hacking in unambiguous cases" — as a detector that flags a run for review, it earns its cost; as the gate, it is the 100%-vs-68% failure. `/goal` is exactly this kind of judge and is the right tool when the evidence is conversational.

**The honest exit.** ralph-loop's promise is single-valued, so a blocked agent can only lie or spin. Give the agent a file to write (`BLOCKED.md`: what was tried, why it cannot work) and stop the loop on its presence. The loop's log then says `stopped: blocked`, which is a true statement.

---

## 5. Prompt and task-list design

**The file contract has converged.** Four independent implementations landed on the same four roles:

| Role | Huntley (A) | snarktank (A) | Anthropic harness (A) | OpenAI Codex long-horizon (A) | flow |
|---|---|---|---|---|---|
| Spec / done-when | `specs/*` | `prd.json` acceptanceCriteria | feature list JSON, every item `passes:false` | `Prompt.md` | `goal` + `verify` in `loop.md` |
| Task list | `fix_plan.md` | `prd.json` userStories | the same JSON | `Plan.md` (milestones + validation commands) | caller's choice: `tasks.json` template, TASKS.md, a plan |
| Execution rules | `PROMPT.md` | `prompt.md` | coding-agent prompt | `Implement.md` | the `loop.md` body (K-G default or the skill's) |
| Memory / learnings | `AGENT.md` | `progress.txt` + AGENTS.md | `claude-progress.txt` + git log | `Documentation.md` | `LEARNINGS.md` + `loop.log` + git log |

**Anatomy of a per-iteration prompt** (what every iteration must receive; K-J in spec 006):

1. Where you are: iteration n of N, the goal, the verifier command.
2. What is red: the verifier's last output (tail), so the iteration starts from evidence, not from re-discovery.
3. What was learned: the learnings file (patterns first), and the git log since base.
4. The one-task rule and the commit rule.
5. The prohibitions with the reason attached: never edit tests/verifier/gate config to pass — "the loop checks for that and will mark the run suspect" (a consequence, not a plea).
6. The honest exit: write `BLOCKED.md` and stop.
7. The task body: the caller's instructions.

**Task-list rules.** Items must fit one context window (snarktank) — if an item needs more than one iteration, it was two items. Acceptance criteria must be runnable ("`npm test` exits 0", "`POST /register` with a bad email returns 400"), never "code is clean". Keep an explicit out-of-scope fence; scope creep ("overbaking") is the reported failure when it is absent (C). Prefer JSON when the agent edits the file (principle 10).

**Learnings rules.** Append, dated, one entry per iteration: what was done, what was learned, what is next. Promote general patterns to a "Codebase patterns" section at the top; promote durable rulings to PROGRESS.md / CLAUDE.md at `/wrap`. Huntley's reason for writing the *why* of each test into the code: "future loops will not have the reasoning in their context window."

**Signs.** Huntley's term for a prose guard added after the loop repeats a mistake ("SLIDE DOWN, DON'T JUMP"). They work until the prompt is all signs. This repo's answer is `/lesson`: turn the sign into a test, hook or script, and delete the sign.

---

## 6. Failure-mode register

| Failure | Evidence | Countermeasure | Where flow enforces it |
|---|---|---|---|
| Premature "done" | Anthropic harness post; SEAL; PROCTOR (A/B) | verifier decides; model has no done signal | `flow loop check`; the prompt never mentions a completion phrase |
| Test weakening / deletion | Huntley (test deletion in late iterations, A); dreamhost retro: assertion deleted at iteration 23 (C); SEAL (B) | tamper veto; per-edit tamper notice; CI as backstop | K-F; `tamper-notice.sh`; `gates.yml` |
| Reward hacking on visible tests | SpecBench, EvilGenie, Building-to-the-Test (B) | held-out job; canaries; judge as detector | CI on a protected branch (repo's job, not the harness's) |
| Thrash (files rewritten back and forth) | dreamhost retro, Cursor "gutter" (C); SWE-PRM (B) | wedge detector: same failure signature N× with changing files | K-H rule 7 |
| Stall (nothing changes) | IAL-Scan (B) | stall detector: fingerprint unchanged N× | K-H rule 7 |
| Runaway cost | 63-incident preprint, $47k/11-day case (C — folklore-grade, repeated across marketing sites) | dollar cap from `total_cost_usd`; `--max-budget-usd` per child; watch dollars not turns | `max_usd`; `run` passes the remaining budget to each child |
| Context rot / mid-task context exhaustion | Anthropic harness post (A); Chroma (C) | fresh shape; one task per iteration; subagents for expensive reads | `flow loop run`; K-G prompt; `explorer` agent |
| Wrong premise, impossible goal | ralph-loop's single-valued promise (A) | honest exit file | `BLOCKED.md` |
| Loop armed by the model itself | ralph-loop uses `hide-from-slash-command-tool` (A) | only the user starts a loop; the skill is user-invocable, the hook only reads a contract the CLI wrote | `flow loop init` is a CLI action the user asked for; `/flow:loop` is user-invocable |
| Cross-session interference | ralph-loop `session_id` isolation (A); this repo's own finding that flow state clobbers across worktrees | contract carries `session_id`; fresh loops ignore the hook entirely | K-H rules 2–3 |
| Child sessions' own Stop hooks blocking | this design | `tick --hook` allows when `shape: fresh` | K-H rule 2 |
| Lost final report | Stop hook allows silently on done | one finishing continuation so the model reports, then allow | K-H rule 4, `finish_reported` |
| Corrupt state wedging the hook forever | ralph-loop self-disarm (A) | rename to `loop.md.corrupt`, allow | K-B |
| Errors that never clear (auth, credits, context overflow) | `/goal` clears on exactly these (A) | three consecutive child errors → `stop_reason: error` | K-I |

---

## 7. Economics and observability

- Anthropic's published figures (A, `docs/en/costs`): "around $13 per developer per active day and $150–250 per developer per month ... below $30 per active day for 90% of users". Agent Teams "use ~7× more tokens". `/usage` has a `Loops` row (v2.1.242+) for `/loop` and scheduled tasks.
- Per-iteration cost is a first-class field of `claude -p --output-format json` (`total_cost_usd`, a client-side estimate). `flow loop run` sums it into `cost_usd` and logs it per iteration; `ccusage` (A) reads the same JSONL logs after the fact for any tool.
- Self-reported overnight numbers (all C, single-source): an 8-hour auth refactor, 47 commits, $23; a 12-iteration utility in 8 minutes for $1.87; Huntley's $50k contract for ~$297; 3 parallel agents $30–40/day; 5–10 agents $50–130/day; two Max 20× subscriptions exhausted in days (~$400/month). Use these as orders of magnitude, not benchmarks.
- Codex long-horizon demonstration (A): ~25 hours, ~13 million tokens, ~30,000 lines, with lint/typecheck/tests/build as gates at every milestone.
- **Watch dollars, not turns.** A loop re-reading a large context each pass burns millions of input tokens while the iteration counter looks calm. Cache reads dominate token volume in long sessions.

---

## 8. Vendor landscape (2026)

| Vendor | Loop shape | Verification | Bound | Grade |
|---|---|---|---|---|
| Anthropic ralph-loop plugin | in-session Stop hook, same prompt re-fed | `<promise>` exact match | `--max-iterations` (default unlimited); 8-block cap in practice | A |
| Anthropic long-running harness (Agent SDK) | initializer + coding agent per session | self-verification + browser e2e; feature JSON `passes` | none stated | A |
| OpenAI Codex long-horizon | Plan → Edit → Run → Observe → Repair → Update docs | gates per milestone | milestone plan; advisory token budgets by scope (C) | A/C |
| Factory Missions | orchestrator + fresh workers per milestone | tests + regression + integration per milestone | milestone checkpoints; 16-day max mission, 14% > 24 h | A |
| Cursor Cloud Agent | fresh VM, branch, PR | project checks; "gutter" no-progress detector in its Ralph plugin (C) | — | C |
| Google Jules | cloud VM, editable plan, PR | runs tests | no stated iteration limit | A (launch) |
| Sourcegraph Amp | modes Rush/Smart/Deep; Oracle subagent | — | $10/day API cap (C) | C |
| Devin | sandboxed VM, parallel sessions | — | — | C |

---

## 9. What the research says about retries

- **Retries saturate fast.** Iterative self-repair (2604.10508, C): two repair rounds capture 76–95% of the achievable gain; assertion/reasoning errors repair at ~45% versus ~77% for name errors. A loop wedged on a logic bug is unlikely to be rescued by more of the same — hence the wedge detector and `BLOCKED.md`.
- **Iteration scaling beats independent sampling** for SWE-bench-style tasks (SWE-Dev, 2506.07636, B), with diminishing returns; the measured points are 30/45/60/75 rounds, and the "gains stop at ~5/~15 attempts" gloss is not in the paper (§11).
- **More search does not reduce hacking** and "severe cases often worsened with more search" (SpecBench, B). Iterations are not a substitute for a better verifier.
- **Process reward models** intervening mid-trajectory raised SWE-bench Verified 40.0% → 50.6% at ~$0.20/run (SWE-PRM, B): the detector-beside-the-stack pattern, priced.
- **Time horizons** (METR TH1.1, A): Claude Opus 4.5 at ~320 min 50%-horizon, doubling every ~131 days — but human baselines exist for only 5 of 31 tasks over 8 hours; multi-hour reliability is extrapolated. Plan for milestones, not for nights.

---

## 10. What this produced in the repo

| Principle | Mechanism | File |
|---|---|---|
| 1, 6, 7 | `flow loop init|check|tick|run|status|stop|log` — one state machine for both shapes; verifier + tamper veto; `BLOCKED.md` | `plugins/flow/bin/lib/loop.js`, `bin/flow` |
| 3, 4, 11, 12 | fresh driver: `claude -p` per iteration, cost summed from JSON, checkpoint commit, `--worktree`, `--dry-run` | `bin/lib/loop.js` (K-I) |
| 2, 5 | caps and stall/wedge detectors | K-H |
| in-session shape | `loop-gate.sh` passes `flow loop tick --hook` through; no loop logic in bash | `plugins/flow/hooks/loop-gate.sh`, `hooks.json` |
| 8, 9, 10 | per-iteration prompt, `LEARNINGS.md`, `tasks.json` template, verifier design guide | `plugins/flow/skills/loop/` |
| ops | `flow doctor` warns on an active or corrupt contract; `flow next` routes to the loop; `flow init` gitignores loop state | `bin/flow` |
| migration | the `fix` skill's Ralph path now uses `/flow:loop`; the official ralph-loop plugin is no longer needed | `skills/fix/` |

Spec: [`.specs/006-loop-engineering/spec.md`](../../.specs/006-loop-engineering/spec.md). Decision row: [`decisions.md`](../decisions.md).

---

## 11. Citation defects found while checking (do not repeat)

1. The Ralph one-liner with `npx --yes @sourcegraph/amp` is not on ghuntley.com/ralph; the page shows `claude-code` only.
2. "196,000 installs" for the ralph-loop plugin: unsourced (not on the README, marketplace.json, or claudemarketplaces.com).
3. arXiv 2605.02964 (Thaman, May 2026) does not mention Ralph loops; cite 2511.18397, 2511.21654 or 2605.21384 for assertion-deletion tactics.
4. SWE-Dev's "~5 / ~15 attempts" breakdown is absent from the paper; likely conflated with 2511.00592 (1.41× → 3.06× over 1–75 rounds).
5. METR's ~131-day doubling belongs to Time Horizon 1.1 (2026-01-29), not the March 2025 paper (~7 months).
6. Reflexion is arXiv 2303.11366; 2303.17651 is Self-Refine.
7. ralph-loop's `[[ = ]]` is about glob metacharacters, not injection defence.
8. The $47,000/11-day runaway anecdote has no named company and no traceable post-mortem (also flagged in research doc 01).
9. `/goal` evaluation is deferred while background work runs — summaries that say "evaluated after every turn" omit this.

### 11a. Provenance corrections from the source-level pass (wave 2)

- `github.com/ghuntley/how-to-ralph-wiggum` is a **fork of `ClaytonFarr/ralph-playbook`**; its `loop.sh`, `PROMPT_plan.md`, `PROMPT_build.md`, `AGENTS.md` and `IMPLEMENTATION_PLAN.md` templates are Clayton Farr's synthesis of Huntley's post, not Huntley's files. The asymmetric-subagent rule ("up to 500 parallel Sonnet subagents for searches/reads and only 1 Sonnet subagent for build/tests") and the escalating-9s guardrail numbering live there. (A, `gh api` fork flag + README voice)
- Huntley's "everything is a ralph loop" (2026-01-17) is a mindset essay: no code, no prompt files, no autonomy ladder of its own (it cites Steve Yegge's "Gas Town" level 8/9). (A)
- Cursor's Ralph plugin (`github.com/cursor/plugins/ralph-loop`, read line by line) has **no "gutter" detector**: its only stop conditions are a `<promise>` match and `--max-iterations`. The gutter narrative is a single uncorroborated blog. (X)
- `mikeyobrien/ralph-orchestrator` is the most complete shipped no-progress design: outputs ≥ 90% similar to any of the last 5 ⇒ stop; 5 consecutive failures ⇒ stop; defaults 100 iterations, $10, 4 h; a "stale loop" (same topic 3×) detector tracked in its issue #194. Its warning: "A 50-iteration cycle on large codebases can cost $50–100+". (A)
- OpenAI's companion cookbook replaces the four files with one living `PLANS.md` ("ExecPlan") whose mandatory sections are Progress, Surprises & Discoveries, Decision Log, Outcomes & Retrospective. (A)
- `checkwash` (PyPI, v0.3.2): 21 named detectors over a git diff, zero runtime deps, exit 0 pass / 1 block / 2 error, meant to run as a required CI check or a Stop hook, self-reported 1.72% false positives on 1,800 commits ("not a held-out result"). `tdd-guard` is the opposite architecture: a PreToolUse hook that calls an LLM and once failed closed on every edit after a model swap. (A)
- Claude Code has no official "held-out test suite for agents" pattern; it is assembled from `permissions.deny` (a `Read` deny also blocks `Edit`/`Write` on that path), the official protect-files PreToolUse hook, CODEOWNERS and required status checks — and none of them stop an agent with unrestricted shell access, which every source says plainly. (A)

---

## 12. Sources (primary)

- code.claude.com/docs/en/{hooks, hooks-guide, goal, scheduled-tasks, env-vars, cli-reference, headless, costs} — read 2026-09-07.
- Huntley, "Ralph Wiggum as a 'software engineer'" (ghuntley.com/ralph, 2025-07-14); "everything is a ralph loop" (ghuntley.com/loop, 2026-01-17); ghuntley.com/specs; github.com/ghuntley/how-to-ralph-wiggum.
- Anthropic, ralph-loop plugin v1.0.0 (`claude-plugins-official`; local cache read); "Effective harnesses for long-running agents" (2025-11-26); "Effective context engineering for AI agents" (2025-09-29).
- github.com/snarktank/ralph (README, ralph.sh, prompt.md, prd.json.example).
- OpenAI, "Run long-horizon tasks with Codex" (developers.openai.com/blog).
- Factory, "Missions" (factory.ai/news/missions).
- arXiv: 2511.18397 (emergent misalignment from reward hacking), 2511.21654 (EvilGenie), 2605.21384 (SpecBench), 2606.28430 (Building to the Test), 2607.24300 (SEAL), 2609.02246 (PROCTOR), 2607.01641 (IAL-Scan), 2509.02360 (SWE-PRM), 2506.07636 (SWE-Dev), 2606.27009 (semantic early-stopping), 2604.10508 (iterative self-repair), 2511.00592 (agentic auto-scheduling). METR Time Horizon 1.1 (2026-01-29).
- Tools: checkwash (PyPI), tdd-guard (github.com/nizos/tdd-guard), ccusage (github.com/ccusage/ccusage).
