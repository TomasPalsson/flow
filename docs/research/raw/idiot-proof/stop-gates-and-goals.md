# Stop-time verification done right — source-level delta

Researched 2026-09-07. Angle: the Stop gate, the one gate flow relies on most. Every claim is fetched
(source + date) or marked UNVERIFIED. **Delta only**: platform facts already in `07-harness-smoothness-2026.md`
§A (async/asyncRewake, `if` scoping, timeout defaults, 10k output cap, PostToolBatch, FileChanged) and bugs
already in `09-harness-audit-2026-09-07.md` (B6 porcelain, B7 prune list, B8 worktree `.git`, B9 wedge valve
does not release, B17 `pwd -P`) are cited by ID, not re-derived.

## BLUF

1. flow's stop gate has **six silent-degradation paths**; five were unknown before today. Silent failure-open,
   not false blocking, is its dominant idiot-proofing defect.
2. Proven here: `"stopGate":"on"` (or `"TRUE"`, `"full"`) **turns the whole gate off**, no message. Only the
   three literals `true`/`scoped`/`false` do anything.
3. Proven: a **crashing `check-all`** is indistinguishable from "no ecosystem" (both = empty stdout) → exit 0, silent.
4. Proven: `test-changed` is **blind to untracked files** → new file + new test yields `test_cmd:""` → scoped mode
   falls through to a full sweep. Every TDD first slice pays full price.
5. Proven: a **README-only turn blocks** on an unrelated pre-existing red test. No baseline awareness anywhere.
6. Proven: flow's own repo has **no gate at all** — no root manifest, so `check-all` exits before printing JSON.
7. Delta: Stop input now carries `background_tasks` + `session_crons`. A Stop with work in flight is *paused*,
   not *done*. flow blocks it anyway.
8. Delta: `StopFailure` fires **instead of** `Stop` on an API error — a rate-limited turn is never gated.
9. Delta: `systemMessage` is a **warning shown to the user, not to Claude**. That is the missing third output
   tier and the correct release valve: end the turn, tell the human, never wedge. Fixes audit B9.
10. `hookSpecificOutput.additionalContext` on Stop = continue without hook-error styling, same 8-block cap.
    Three tiers exist; flow uses one and a half.
11. `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` is real (changelog v2.1.143); the 8-consecutive-block override is documented.
    flow's wedge valve at 4 sits inside it and is mostly redundant as written.
12. `/goal` **is** a session-scoped prompt Stop hook whose evaluator "does not run commands or read files".
    It judges the transcript; flow's gate runs the commands. Complements, not rivals — but they share the 8-cap.
13. Anthropic's own `ralph-loop` Stop hook **self-disarms** (`rm` the state file) on every condition it cannot
    judge, and isolates by `session_id`. flow degrades by counting signatures instead.
14. Jest and Vitest already ship correct related-test resolution (`--findRelatedTests`, `--related`,
    `--changedSince`, `--changed`). flow reimplements it with an unanchored `grep -rl`.
15. Reward-hacking rate is driven by **spec ambiguity**, not model: 0.7–2.1% hardcoding on unambiguous problems,
    22–44% on ambiguous ones (EvilGenie). flow's C20 spec gate is therefore a stop gate.

## 0. Sources

PRIMARY, all fetched 2026-09-07 unless noted: **S1** `code.claude.com/docs/en/hooks.md` (raw md, 3,773 lines) ·
**S2** `.../hooks-guide.md` · **S3** `.../goal.md` · **S4** `.../scheduled-tasks.md` · **S5** Claude Code
CHANGELOG `## 2.1.143` · **S6** `anthropics/claude-plugins-official` `plugins/ralph-loop/hooks/stop-hook.sh`
(191 lines) · **S7** same plugin's README + `commands/ralph-loop.md` + `hooks/hooks.json` · **S8**
`anthropic.com/engineering/harness-design-long-running-apps` (pub. 2026-03-24) · **S9** `ghuntley.com/ralph/`
(pub. 2025-07-14) · **S10** `vercel-labs/ralph-loop-agent` `src/ralph-stop-condition.ts` +
`ralph-loop-agent-evaluator.ts` + README · **S11** EvilGenie arXiv:2511.21654v2 (2026-05-17) · **S12** SpecBench
arXiv:2605.21384v1 (2026-05-20) · **S13** Jest CLI docs · **S14** Vitest CLI docs (v5.0.0) · **S15** testmon.org
(no version on page) · **S16** `open-gsd/gsd-core` `agents/gsd-verifier.md` · **S17** humanlayer `ace-fca.md`.
UNVERIFIED: METR "tests edited / graders read" — no primary artifact retrieved; see §8.

## 1. Platform delta (S1–S5)

**1.1 Stop input carries live-work state.** S1: *"Stop hooks receive `stop_hook_active`,
`last_assistant_message`, `background_tasks`, and `session_crons`. … The `background_tasks` and `session_crons`
arrays let hooks distinguish 'session is done' from 'session is paused waiting for background work to wake it
back up'. Both arrays are present when the task registry is reachable and are empty when nothing is in flight."*
Task entries carry `id`, `type` (`shell`/`subagent`/`monitor`/`workflow`/`teammate`/`cloud session`/`MCP task`),
`status`, `description`, `command`. `session_crons` carry `schedule`, `recurring`, `prompt`. flow reads neither:
a turn ending while a `build-slices` Workflow runs gets the full gate, and is told to fix tests that in-flight
work is about to change.

**1.2 `last_assistant_message` is on the payload and the docs tell you to prefer it** over `transcript_path`:
*"the transcript file isn't guaranteed to include the final message at Stop time on all versions."* Anthropic's
own shipped ralph hook (S6) still `jq`-slurps the transcript, so the plugin predates the field. Cheapest
available signal for "this turn claimed done" vs "this turn reported itself blocked".

**1.3 There are three output tiers on Stop, not two.**

| Tier | Form | Effect | Text goes to | Counts to 8-cap |
|---|---|---|---|---|
| Hard block | `{"decision":"block","reason":…}` **or exit 2** | turn continues | Claude, styled a hook error | yes |
| Soft | `{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":…}}` | turn continues | Claude, labelled `Stop hook feedback`, **no hook-error notice** | yes |
| Release | exit 0 + `{"systemMessage":…}` | **turn ends** | **user only** | n/a |

S1 on tier 2: *"Use `additionalContext` when the hook is working as designed … It keeps the conversation going
through the same loop protections as `decision:"block"` … but the transcript labels it `Stop hook feedback` and
no hook error notification is shown."* S1 universal-fields table on tier 3: `systemMessage` = *"Warning message
shown to the user"*; and `continue:false` = *"Claude stops processing entirely after the hook runs. Takes
precedence over any event-specific decision fields"*, with `stopReason` *"Not shown to Claude"*.
This settles **B9**: exit 2 on Stop still blocks (S1 exit-code table: `Stop` → *"Prevents Claude from stopping"*),
so today's fallback never releases. Tier 3 does.

**1.4 The cap is documented and overridable.** S1: *"Claude Code overrides the hook and ends the turn after 8
consecutive blocks."* S2 §"Stop hook hits the block cap": *"raise the cap with `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`."*
S5: *"Fixed stop hooks that block repeatedly looping forever — the turn now ends with a warning after 8
consecutive blocks (override via `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`)."* The cap counts *consecutive blocks*;
flow's `claude-gatesig-<session_id>` counts *identical signatures* and never resets. Different axis — keep both,
but let flow's counter pick the **tier**, not the wording.

**1.5 `StopFailure` fires instead of `Stop` on API errors** (`rate_limit`, `overloaded`, `max_output_tokens`, …)
and *"Claude Code ignores the hook's output and exit code, apart from `terminalSequence`."* A turn that dies on a
rate limit leaves red code with no gate run. `StopFailure` cannot block but can stamp a marker the next `Stop` reads.

**1.6 `TeammateIdle` exists**: *"Runs when an agent team teammate is about to go idle… Use this to enforce quality
gates before a teammate stops working."* flow registers none, so teammates go idle ungated.

**1.7 `if` is a trap on Stop.** S1: `if` is *"Only evaluated on tool events… On other events, a hook with `if`
set never runs."* Repeated from 07 §A.3 only because it is the likeliest way to "optimise" the gate into non-existence.

**1.8 `/goal` is a Stop hook, and its evaluator is filesystem-blind.** S3: *"`/goal` is a wrapper around a
session-scoped prompt-based Stop hook. … The evaluator judges your condition against what Claude has surfaced in
the conversation. **It doesn't run commands or read files independently.**"* Other constraints: one goal/session,
4,000-char condition, restored on every resume route since v2.1.239; *"If a subagent or a background shell command
is still running when a turn ends, Claude Code **skips the evaluation** for that turn"*; *"If Claude keeps
answering the evaluator without making progress (**no tool use for several turns in a row**), Claude Code stops
the loop, prints a warning, and returns control to you with the goal still set"* — a no-progress detector on tool
use, not on block count; cleared by four unrecoverable failures (auth, credit, unclearable context overflow,
missing model) but **not** by rate limits; unavailable under `disableAllHooks`/`allowManagedHooksOnly`, where
*"the command tells you why instead of silently doing nothing"* — the exact standard flow's own opt-outs should meet.

**1.9 `/loop` is time-driven** (S4: *"`/loop 5m check the deploy` — Your prompt runs on a fixed schedule"*). Each
iteration ends in a normal `Stop`, so flow's gate fires every iteration; with the clock-based periodic full sweep a
5-minute loop can spend most of its wall clock inside `check-all`. `session_crons` is how a hook detects it is in one.

## 2. What other stop-time harnesses do (S6–S10, S16, S17)

**2.1 Anthropic's `ralph-loop` hook self-disarms rather than self-throttles (S6).** Every branch that cannot judge
does `rm "$RALPH_STATE_FILE"; exit 0`: state file absent → inert (armed by a *file*, not config); `session_id` in
state ≠ payload `session_id` → exit 0 without touching state (*"the state file is project-scoped, but the Stop hook
fires in every Claude Code session in that project"*); `iteration`/`max_iterations` not `^[0-9]+$` → diagnostic +
delete; `iteration >= max_iterations` → delete; transcript missing / no assistant messages / `jq` non-zero / empty
prompt → delete. Only then `{"decision":"block","reason":$prompt,"systemMessage":$msg}` — note the split:
`reason` instructs the model, `systemMessage` shows the human `"🔄 Ralph iteration 7 | To stop: output
<promise>DONE</promise>"`. flow puts everything in `reason`. It does **not** check `stop_hook_active`, relying on a
bounded counter checked *before* any work plus the platform 8-cap — a stronger un-wedging primitive than a counter
checked after. (It uses `set -euo pipefail` and survives only because every path exits explicitly; keep flow's
SPEC rule against `set -e` in hooks.)

**2.2 The anti-lying clause lives at the prompt layer** (S7): *"you may ONLY output it when the statement is
completely and unequivocally TRUE. Do not output false promises to escape the loop, even if you think you're stuck"*,
echoed in the hook's `systemMessage`: *"(ONLY when statement is TRUE - do not lie to exit!)"*. flow has the mirror
sentence for tests but nothing about the exit condition itself.

**2.3 Vercel's `ralph-loop-agent` separates budget from semantics (S10):** `stopWhen` takes hard counters
(`iterationCountIs`, `tokenCountIs`, `inputTokenCountIs`, `outputTokenCountIs`, `costIs(2.00, 'anthropic/claude-opus-4.5')`,
or arrays), while `verifyCompletion → {complete, reason}` decides done and feeds `reason` forward as next-iteration
guidance. flow conflates both in one `_sig_count`.

**2.4 Anthropic's three-agent harness makes "done" a negotiated artifact (S8):** *"Before each sprint, the generator
and evaluator negotiated a sprint contract: agreeing on what 'done' looked like for that chunk of work before any
code was written"* — "Sprint 3 alone had 27 criteria". And on why self-evaluation fails: *"When asked to evaluate
work they've produced, agents tend to respond by confidently praising the work—even when, to a human observer, the
quality is obviously mediocre."* flow already has the artifact (`feature-plan.local.md` + Behavior Inventory); what
it lacks is a stop-time check that the *inventory rows* hold, as opposed to that `npm test` exited 0.

**2.5 gsd-core's verifier is three-valued (S16):** *"Every truth must resolve to VERIFIED, FAILED (BLOCKER), or
UNCERTAIN (WARNING with human decision requested)"*; *"Do NOT trust SUMMARY.md claims. SUMMARYs document what Claude
SAID it did."* The load-bearing bit: **UNCERTAIN escalates to a human; it does not pass.** flow maps every
uncertainty (`have jq ||`, `have node ||`, empty `check-all` stdout, missing scripts) to *pass, silently*. This is
the single change with the largest idiot-proofing return.

**2.6 Huntley (S9):** the loop is `while :; do cat PROMPT.md | claude-code ; done`; backpressure is per-unit, not
whole-suite — *"After implementing functionality or resolving problems, run the tests for that unit of code that was
improved"* — and he is explicit that it fails open in practice: *"you'll wake up to a broken codebase that doesn't
compile from time to time"*, *"Claude has the inherent bias to do minimal and placeholder implementations."*

**2.7 HumanLayer ACE-FCA (S17)** puts verification in the plan, not the gate: *"being super precise about the
testing / verification steps in each phase"*; *"I'll often compact the current status back into the original plan
file after each implementation phase is verified."*

## 3. What the gate defends against (S11, S12)

**EvilGenie (S11).** Three observed categories: hardcoding — *"writing the special cases into the code or **reading
the test file to directly provide correct answers**"*; modifying the testing procedure — agents *"modify the test
cases or the code that runs the testing procedure"*, including deleting test files (Gemini deleted `test.py` in 3.4%
of unambiguous cases *after* passing, attributed to cleanup training); and heuristics — *"brute-forcing small inputs
while defaulting to a fixed output for large inputs."* Rates on **unambiguous** problems: Codex 0.7%, Claude Sonnet 4
2.1%, Gemini 0%. On **ambiguous** problems: 44.4% / 33.3% / 22.2%. Setup held out *"30% of test cases (capped at 10)
… inaccessible to the agent"*; the authors found held-out tests gave *"some false positives"* and preferred LLM judges.
→ **Ambiguity is the reward-hacking trigger**, a 20–60× multiplier. That makes an approved, lint-clean plan the
cheapest available defence, and it already runs at Stop (C20).

**SpecBench (S12).** Validation-vs-held-out gap *"scales by approximately 27 percentage points per tenfold increase
in code size"*, reaching 100pp above 25K LOC. The dominant failure is not cheating but *feature isolation*: *"agents
often implement SELECT, JOIN, GROUP BY, and HAVING as separate handlers"* that pass per-feature tests and *"fail to
share state across components."* A scoped-test gate is structurally blind to exactly this — the changed file's own
tests pass, the integration does not. That is the argument for keeping a periodic full sweep, and for making its
cadence **commit-based rather than clock-based**.

## 4. Test scoping: the runners already solved this (S13–S15)

| Runner | Mechanism | Quote |
|---|---|---|
| Jest | `--findRelatedTests <files…>` | *"Find and run the tests that cover a space separated list of source files… **Useful for pre-commit hook integration to run the minimal amount of tests necessary.**"* |
| Jest | `--onlyChanged` / `--changedSince <ref>` | *"requires a static dependency graph (ie. no dynamic requires)"*; *"If the current branch has diverged… only changes made locally will be tested."* |
| Jest | `--listTests`, `--passWithNoTests` | *"Lists all test files that Jest will run given the arguments, and exits."* / *"Allows the test suite to pass when no files are found."* |
| Vitest v5 | `--related <files…>`, `--changed` | *"Run only tests that cover a list of source files. Works with static imports … but not the dynamic ones."* / *"Run tests that are affected by the changed files."* |
| pytest | none built in; `pytest-testmon` | *"collects dependencies between tests and all executed code (internally using Coverage.py)"*, stores `.testmondata`, *"**always re-executes tests which failed last time**"*, needs one full run to seed. |

Three lessons: (a) `--findRelatedTests`/`--related` is a **module-graph query**, whereas flow's `mapToTestFiles` does
filename-convention guesses plus `grep -rl --include='*.test.*' "<basename>" .` — an unanchored substring over the whole
tree (a file named `index.ts` matches every test mentioning "index"; a filename with a quote or `$` is interpolated into
a shell string). (b) `--listTests` is the dry-run primitive: a gate should be able to state its scope without paying for
it. (c) testmon's "always re-execute last failures" is the **baseline primitive** — keep the previous red set and re-run
it regardless of what changed, and you get regression-vs-pre-existing for free.

## 5. flow's gate, measured (all repros run 2026-09-07 on this box)

`plugins/flow/hooks/stop-gate.sh` (551) · `skills/shared/scripts/test-changed` (391) · `.../check-all` (452) ·
`hooks/hooks.json` (`Stop`, `timeout: 600` — correct, and nowhere near a timeout risk) · SPEC §C10.

| # | Silent-degradation path | Code | Repro | Status |
|---|---|---|---|---|
| D1 | **Unrecognised `stopGate` value disables the gate** | `:482–512`, `if …="true" … elif …="scoped"`, no `else` | `"on"`/`"TRUE"`/`"full"` with a red test and a changed source file → rc 0, **empty stdout**. `"true"`/`"scoped"` block in the same fixture. | CONFIRMED |
| D2 | **Crashing `check-all` reads as "no ecosystem"** | `_sg_run_full_sweep:405–410`, `[ -z "$_fs_out" ] && FS_NO_ECOSYSTEM=1` | `check-all` = `this is not javascript {{{`, `stopGate:true`, red test → rc 0, no output | CONFIRMED |
| D3 | **Malformed gate JSON reads as "all passed"** | `:411–413`, `case '' \| *[!0-9]*) _fs_failed_count=0` then `return 0` | any jq failure on `.gates` becomes a pass | by inspection |
| D4 | **Missing `node`/`jq` → gate off, no notice** | `:331–332` `have node \|\| hook_ok` | documented intent, but the user is never told | by inspection |
| D5 | **`test-changed` blind to untracked files** | `getChangedFiles` uses `git diff --name-only` ×3 | fresh repo on `main`, `printf x > brand-new.js` → `{"changed_files":[],"test_cmd":""}` → `_tc_cmd` empty → fallthrough → **full sweep** | CONFIRMED |
| D6 | **No ecosystem in flow's own repo → no gate** | `check-all` `detectGates()` finds no root manifest | `node …/check-all --json` in this worktree → rc 0, no JSON. flow's 100+ bash tests never run at Stop. | CONFIRMED |

Scope defects, distinct from degradation:

- **`test-changed` scopes to the branch, not the turn** (`git diff --name-only ${base}...HEAD` unioned with the
  worktree). `stop-gate.sh` computes a correct per-turn set (C3, `:154–167`) and then **throws it away** — it never
  passes a file list. Both scopes are wrong: too wide (whole branch) and too narrow (untracked invisible).
- **"scoped" is a full sweep more often than not**: on missing `test-changed`, on empty `test_cmd` (D5), and on the
  clock timer — whose stamp is absent on the **first** Stop of every session, so the first gated turn is always a sweep.
- **Docs-only turns block on unrelated pre-existing red.** Fixture: `"test":"exit 1"`, `stopGate:"scoped"`, edit only
  `README.md` → `{"decision":"block","reason":"Gate(s) failed: test…"}`. Audit B6 covers the adjacent read-only case;
  this is worse, because a change *did* happen so no early-exit fires.
- **`spawnSync(parts[0], parts.slice(1))` on a naively space-split command** (`test-changed` `main()`; same class in
  `check-all`'s `buildDetectProjectGates`): any `test_cmd` with quoting, `&&`, or a space in a path mis-executes.
- **`runGate` cannot tell "gate failed" from "gate could not run".** `spawnSync` returning `status: null` (ENOENT or the
  120 s timeout) yields `fail` with empty `output`, producing `Gate(s) failed: typecheck` with **no remediation** — the
  precise failure the brief forbids.
- **The block reason can exceed the 10,000-char cap** (S1) — a verbose typechecker pushes the fixed
  "do not weaken a test" sentence into an overflow file.

## 6. The idiot-proof stop gate

**Invariants.** I1 never blocks a turn that changed nothing under version control (change set = turn stamp ∩
`git status --porcelain -uall` minus ignored, not "tree is dirty"). I2 never spawns a test command when only non-code
paths changed. I3 never blocks on a failure that predates the turn. I4 never fails open silently — every
"cannot judge" emits a `systemMessage`; silence is reserved for *checked, green*. I5 never wedges — the ladder is
bounded and ends in a release that **ends the turn**. I6 never blocks while work is in flight. I7 unknown configuration
is loud. I8 latency is bounded and every overrun degrades to a *reported* outcome.

**Decision table** — first match wins; `Δ` = the turn's change set.

| # | Condition | Runs | Verdict | Output | Budget |
|---|---|---|---|---|---|
| R0 | `stop_hook_active`, `CC_NO_STOP_GATE=1`, `flow.off`, or not a git work tree | — | ALLOW | silent | <20 ms |
| R1 | `stopGate` ∉ `{true,false,"scoped"}` | — | ALLOW | `systemMessage`: `flow: stopGate="on" is not true \| false \| "scoped" — the gate did not run this turn.` | <30 ms |
| R2 | `background_tasks` non-empty | — | ALLOW | `systemMessage`: `flow: gate deferred — 2 tasks still running (shell: bun test --watch; workflow: build-slices).` | <30 ms |
| R3 | `Δ` empty | — | ALLOW | silent | <60 ms |
| R4 | `Δ` ⊆ docs/config (`*.md`, `*.txt`, `docs/`, `.specs/`, `.claude/` minus the plan, `LICENSE`) | plan-lint iff the plan is in `Δ` | ALLOW unless plan-lint fails | silent, else block with plan-lint output | <200 ms |
| R5 | `Δ` ∩ source ≠ ∅, no ecosystem, no manifest removed | — | ALLOW | `systemMessage` **once per session**: `flow: no test/lint ecosystem here — source changed and nothing verified it. Run 'flow init', or set stopGate:false to silence.` | <300 ms |
| R6 | root manifest deleted/renamed away | — | BLOCK | current wording | <300 ms |
| R7 | `node`/`jq` missing, or a gate binary crashed (non-zero **with empty stdout**, or unparseable JSON) | — | ALLOW | `systemMessage`: `flow: gate could not run — check-all exited 1 with no JSON (node v22.4, cwd …). Gates were NOT checked this turn. Fix: <cmd>` | <2 s |
| R8 | source changed, scoped run resolves ≥1 affected test, all green, sweep not due | affected tests | ALLOW | silent | ≤15 s |
| R9 | scoped run red, **every** failing id in the baseline | affected tests | ALLOW | `systemMessage`: `flow: 3 tests were already failing before this turn (auth.spec.ts:2, …). Not blocking; not fixed either.` | ≤15 s |
| R10 | scoped run red with ≥1 failure **not** in the baseline | affected tests | BLOCK | `reason`: new failing ids first, ≤25 lines of their output, the fixed no-weakening sentence, then `To reproduce: <exact command>` | ≤15 s |
| R11 | scoped green **and** a full sweep is due (**commits** since last sweep, not clock) | `check-all --json` | ALLOW if green | silent | ≤120 s |
| R12/R13 | full sweep red, all-baseline / any-new | `check-all` | ALLOW / BLOCK | as R9 / R10, with gate names | ≤120 s |
| R14 | a BLOCK whose signature already blocked twice this session | — | SOFT | `additionalContext`, same body + `This is the 3rd identical block. Fix it, or state why it is out of scope and stop.` | — |
| R15 | …already blocked four times | — | RELEASE | exit 0 + `systemMessage`: `flow: ending the turn with <sig> still red after 4 blocks. Nothing was verified. Run 'flow check' yourself.` | — |
| R16 | hook wall clock > `stopGateBudgetSec` (default 150) | — | RELEASE | `systemMessage`: `flow: stop gate exceeded its 150s budget and was cut short; gates NOT verified.` | hard |

Row notes. **R2 before R3** mirrors what the platform already does for `/goal` (S3) and costs one field read.
**R5 fixes D6**: "no ecosystem" is gsd's *uncertain*, not a pass — once per session, so the zero-per-turn-output rule
holds. **R7 fixes D2/D3/D4**, and needs the discriminator today's code lacks: `check-all` must exit **3** (or print
`{"ecosystem":null}`) for "no ecosystem", so that empty stdout can mean *crashed* and nothing else. **R8 must use the
runner's own resolver** — `vitest related --run <files> --passWithNoTests`, `jest --findRelatedTests <files> --ci
--passWithNoTests`, `pytest --testmon` when `.testmondata` exists else full, `go test ./<pkgs>`, `cargo test -p <crate>`
— never filename guessing, never `grep -rl`. **R9/R12 need a baseline**: `${TMPDIR}/claude-baseline-<repo-hash>-<branch>`,
a sorted list of failing ids, written after any red run and invalidated when `HEAD` moves; on a branch's first red the
baseline is *unknown*, so the honest verdict is R10 **plus** `no baseline recorded for this branch yet; if these were
already failing, re-run and they will be treated as pre-existing` — one block, never two. **R11's cadence is commits**:
clock cadence makes the first Stop of every session a full sweep (measured) and taxes `/loop`; `stopGateFullEveryCommits: 1`
is cheaper and more meaningful. **R14/R15 replace the wedge valve** with tier 2 then tier 3 (§1.3) — the un-wedging
audit B9 says exit 2 does not deliver. **R16 is the un-hangable guarantee**: the platform cancels at timeout and
*"discard[s] the hook's output, so on most events a timed-out hook renders no decision"* (S1) — silently. A hook that
hits its own budget first can at least say so.

**Why a read-only turn can never be blocked** — three independent barriers: (1) R3's change set is `porcelain -uall`
minus git-ignored paths (`hookout.sh` already has `hook_git_managed`) and the find-newer scan shares
`post-bash-write.sh`'s prune list (B7/B8: `build/`, `__pycache__/`, a worktree's `.git` **file**); (2) R4 short-circuits
before any subprocess on docs/config-only; (3) no row spawns a test command unless `Δ ∩ source ≠ ∅` — "the repo was
already dirty" is never sufficient (B6).

**Latency budget.** R0–R3 **<60 ms** (find-newer over this repo measured at 5 ms; `git status` dominates) · R4 <200 ms
(plan-lint is already mtime-cached, `:73–115`) · R5–R7 <2 s · R8–R10 ≤15 s (today unbounded: `test-changed` sets
`timeout: 300000`) · R11–R13 ≤120 s (today `runGate` is 120 s **per gate** × 4 = 480 s worst case, inside the 600 s hook
timeout by only 120 s) · R16 hard cut at 150 s. Gate overhead excluding subprocesses must stay **<100 ms**, because it is
paid on every turn including read-only ones.

**Coexistence with `/goal`.** The division is clean because the goal evaluator cannot run commands (S3): `/goal` answers
*"is the user's condition met?"* from the transcript; flow's gate answers *"is the tree green?"* from the filesystem.
But both are Stop hooks sharing the **same 8-consecutive-block cap**, so when a goal is active flow's gate should prefer
tier 2 (`additionalContext`) over tier 1 — same continuation, no hook-error noise, and the goal evaluator sees the gate's
text as transcript evidence, which is the only evidence it can see. `/goal` skips evaluation while background work runs;
R2 does the same. Adopt S3's phrasing standard (*"tells you why instead of silently doing nothing"*) for R1/R5/R7. Do
**not** reimplement the gate as a `type:"prompt"` Stop hook (prompt hooks judge, they do not execute) nor as
`type:"agent"` (a subagent per turn, and S2 flags agent hooks experimental: *"For production workflows, prefer command hooks"*).

## 7. Pseudo-code

```
# stop-gate.sh — target shape. bash 3.2 safe, set -u, never set -e.
# Contract: exactly one of ALLOW_SILENT / NOTE / BLOCK / SOFT / RELEASE.
read HOOK_INPUT                                            # hookout.sh, once
ALLOW_SILENT if .stop_hook_active=="true" or CC_NO_STOP_GATE=1 or hook_off_here or not a git work tree
started_at = now

mode = cfg.stopGate ?? "scoped"
if mode ∉ {true,false,"scoped"}: NOTE 'stopGate=<v> is not true | false | "scoped" — gate did not run'   # R1 (D1)
if (.background_tasks | length) > 0: NOTE "gate deferred — <n> task(s) running: <types>"                 # R2

Δ = (find -newer <turn stamp>) ∪ (git status --porcelain -uall)
    minus .git dir AND .git file, node_modules, .venv, target, dist, build, __pycache__, check-ignore'd
    # ONE shared prune list with post-bash-write.sh                                        (B6/B7/B8)
ALLOW_SILENT if Δ empty                                                                    # R3
src = { f ∈ Δ : is_source(f) };  plan_changed = ".claude/feature-plan.local.md" ∈ Δ
if plan_changed and plan-lint fails: BLOCK <plan-lint output>                               # R4
if src empty: ALLOW_SILENT                                                                  # R4
if requireSpec_active and not approved_plan_ok: BLOCK <spec-gate reason>                    # C20, runs regardless of mode
ALLOW_SILENT if mode == false                              # only now — the spec gate already had its say

probe = check-all --probe --json      # MUST distinguish three outcomes:
                                      #   {"ecosystem":"node",…} exit 0 -> ok
                                      #   {"ecosystem":null}     exit 3 -> no ecosystem
                                      #   empty stdout / unparseable    -> CRASHED
if probe==CRASHED or missing(node) or missing(jq):
    NOTE "gate could not run — <what> <exit> <cwd>. Gates were NOT checked. Fix: <cmd>"     # R7 (D2/D3/D4)
if probe==NO_ECOSYSTEM:
    BLOCK if root_manifest_disappeared(Δ)                                                   # R6
    NOTE_ONCE_PER_SESSION "no test/lint ecosystem here; source changed, nothing verified it" # R5 (D6)

baseline = read_baseline(repo, branch)        # sorted failing ids; invalid once HEAD moves
if mode == "scoped":
    affected = runner_related(src)            # vitest --related / jest --findRelatedTests / pytest --testmon
                                              # / go test ./<pkgs> / cargo test -p <crates>
                                              # src is PASSED IN; never re-derived from git diff   (D5)
    if affected is UNRESOLVABLE: goto full_sweep
    r = run(affected, budget=15s)
    if r.red:
        new = r.failures − baseline;  write_baseline(r.failures)
        if new empty: NOTE "<n> pre-existing failures; not blocking, not fixed either"      # R9
        else: BLOCK new + ≤25 lines + no-weakening sentence + "To reproduce: <cmd>"         # R10
    if commits_since_last_sweep >= cfg.stopGateFullEveryCommits: goto full_sweep            # R11
    ALLOW_SILENT                                                                            # R8
full_sweep:
    r = check-all --json (budget = min(120s, remaining_of(cfg.stopGateBudgetSec)))          # R11-R13
    same baseline logic; on new failures BLOCK with gate names

on every BLOCK:                                                                             # ladder
    n = append_and_count(sigfile, signature)
    if n >= 4: RELEASE "ending the turn with <sig> still red after 4 blocks; nothing verified"  # R15 (B9)
    if n >= 3 or goal_active: SOFT reason                                                   # R14 + §6
    BLOCK reason
before/after every subprocess:
    if now - started_at > cfg.stopGateBudgetSec: RELEASE "budget exceeded, gates NOT verified"  # R16
```

New `hookout.sh` primitives: `hook_note <msg>` → exit 0 + `{"systemMessage":…}` (user sees it, turn ends);
`hook_soft <msg>` → exit 0 + `{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":…}}`;
`hook_block` unchanged; `hook_halt <msg>` → `{"continue":false,"stopReason":…}` (reserved, not used by the gate).
All go through `_json_str` and respect the 10,000-char cap: truncate the *gate output*, never the fixed sentences,
and append `… (full output: <path>)`.

## 8. Tests that pin each row

`hooks/tests/test_quality.sh`, prefix `t_sg_`. Helper `sg_repo <ecosystem> <test-exit>` builds a one-commit tmp repo;
`sg_run <repo> <json>` sets `RC/OUT/ERR`. A fake runner that logs its argv pins scope assertions.

| Test | Row | Setup → assert |
|---|---|---|
| `t_sg_stop_hook_active_rc0` | R0 | `{"stop_hook_active":true}` → rc 0, empty `OUT`, <100 ms |
| `t_sg_unknown_mode_notes` | R1 / **D1** | `stopGate:"on"`, red test, source changed → rc 0, `OUT` has `systemMessage` **and** `true \| false \| "scoped"`; must not be empty |
| `t_sg_known_modes_still_block` | R1 | same fixture with `"true"` then `"scoped"` → both `"decision":"block"` (guards R1 over-matching) |
| `t_sg_background_task_defers` | R2 | `background_tasks:[{type:"shell",status:"running",command:"bun test --watch"}]`, red test → `systemMessage` names `shell`, **no** block |
| `t_sg_nothing_changed_rc0` | R3 | clean tree → rc 0, empty |
| `t_sg_readonly_turn_on_dirty_repo` | R3 / **B6** | dirty the tree, stamp *after*, red test → rc 0, empty (today: blocks) |
| `t_sg_ignored_and_worktree_paths` | R3 / B7,B8 | `.gitignore` `build/` + a `git worktree` → rc 0, no `.git`/`build` in any message |
| `t_sg_docs_only_no_test_run` | R4 | red test, edit only `README.md` → rc 0, empty, **and** the fake runner's sentinel file is absent |
| `t_sg_plan_lint_runs_on_plan_edit` | R4 | broken `feature-plan.local.md` → block containing `plan-lint` |
| `t_sg_manifest_deleted_blocks` | R6 | `git rm package.json` → block, `manifest disappeared` (existing test; keep) |
| `t_sg_crashed_check_all_notes` | R7 / **D2** | `check-all` = `not javascript {{{` → rc 0, `systemMessage` containing `NOT checked`; not empty |
| `t_sg_unparseable_json_notes` | R7 / **D3** | `check-all` prints `{"gates":"oops"}` → `systemMessage`, not a silent pass |
| `t_sg_missing_jq_notes` | R7 / D4 | `PATH` without `jq` → rc 0 + `systemMessage` naming `jq` |
| `t_sg_no_ecosystem_notes_once` | R5 / **D6** | bare repo, source changed, two runs, same `session_id` → first notes, second silent |
| `t_sg_untracked_new_file_is_scoped` | R8 / **D5** | new untracked `src/a.js` + `src/a.test.js`, green → fake runner argv contains `a.test.js`; `check-all` NOT invoked |
| `t_sg_scoped_green_silent` | R8 | tracked edit, related test green → rc 0, empty |
| `t_sg_pre_existing_red_allows` | R9 | baseline `{t1}`, red `t1` only → rc 0, `systemMessage` `already failing`, no block |
| `t_sg_new_failure_blocks` | R10 | baseline `{t1}`, red `t1`+`t2` → block naming `t2` first, not `t1`; contains the no-weakening sentence and a runnable repro command |
| `t_sg_no_baseline_blocks_once` | R10 | no baseline, red → block containing `no baseline recorded`; the identical second run does not block again |
| `t_sg_full_sweep_commit_cadence` | R11 | `stopGateFullEveryCommits:1`, 1 commit since sweep, scoped green → `check-all` invoked; with 0 commits → **not** invoked (today it is, on the first Stop of every session) |
| `t_sg_third_block_is_soft` | R14 | same signature ×3 → 3rd run rc 0, `OUT` has `additionalContext`, no `"decision":"block"` |
| `t_sg_fourth_block_releases` | R15 / **B9** | same signature ×4 → 4th run rc **0** (not 2), `systemMessage` present, no `decision` field — the turn actually ends |
| `t_sg_goal_active_prefers_soft` | §6 | goal marker set, new red failure → `additionalContext`, not `decision:block` |
| `t_sg_budget_exceeded_releases` | R16 | fake test sleeps past `stopGateBudgetSec:2` → rc 0 within ~3 s, `systemMessage` containing `budget` |
| `t_sg_reason_under_10k` | §5 | 50,000 chars of gate output → `OUT` ≤10,000 chars and still contains the whole fixed sentence |
| `t_sg_spawn_arg_with_space` | §5 | `test_cmd` = `npm run "test all"`, or a test path containing a space → the runner receives one argv element, not two |

Twelve of these fail against today's `stop-gate.sh`. They are the regression suite for the rewrite; write them red first.

## 9. UNVERIFIED register

- **METR on tests-edited / graders-read** — searched, no primary artifact retrieved this pass. §3 rests on EvilGenie
  and SpecBench instead. Do not cite METR.
- **`check-all` `runGate` on a 120 s timeout** — reasoned from `spawnSync` returning `status: null`, not executed.
  Inspection-grade, not measured.
- **`stopGateFullEverySec` with a non-numeric value** — `[ N -gt soon ]` returns rc 2 and prints `integer expected`
  (verified in isolation), read as false by the `if`. In the end-to-end fixture the hook still blocked, via a different
  branch, so the *net* effect of a bad value is not established. Treat as "probably disables the periodic sweep, unconfirmed".
- **The 8-block cap resetting on user interrupt** — inferred from "consecutive"; not stated in S1/S2/S5.
- **`TeammateIdle`** — event and stated purpose are documented (S1); no measurement of flow inside an agent team.
- **testmon version/date** — the vendor page states neither.
- **`SubagentStop`** — out of scope for this angle, and the obvious next one: flow registers only an `async: true`
  logger there, so a `build-slices` developer subagent can finish red and the parent never learns.
