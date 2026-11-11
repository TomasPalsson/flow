# 19 — The autonomous on-ramp: from a raw idea to an armed loop with no human in the middle, 2026

Why `/flow:loop <idea>` does nothing today, why `/goal` must not be bolted onto it, and what a zero-gate `--yolo` on-ramp has to replace the human read with so that walking away is still honest. Written 22 September 2026 from a 3-angle sweep (native-primitive research against `code.claude.com` docs plus string-level reads of the Claude Code 2.1.278 binary on this machine; a full path:line map of flow's own spec→next→loop pipeline; a digest of this repo's prior loop rulings). Peer documents: [`12-loop-engineering-2026.md`](12-loop-engineering-2026.md) settles the loop mechanics and is not repeated here; [`15-ui-loop-verification-2026.md`](15-ui-loop-verification-2026.md) settles verifier hardening and supplies §5's negative control; [`11-flow-redesign-2026.md`](11-flow-redesign-2026.md) owns the router's state machine.

**Evidence grades.** **A** — vendor doc or source file read verbatim. **B** — arXiv/peer-reviewed result. **C** — practitioner report, single source, not re-verified. **M** — measured on this machine during the sweep. **X** — circulating claim found to be wrong.

---

## 0. The one-paragraph version

The user's proposed shape, `/goal` + `/flow:loop <idea>`, is one command too many and one judge too many. `/goal` is real and well built (A, `code.claude.com/docs/en/goal`; confirmed in the 2.1.278 binary by the strings `goal_check`, `tengu_goal_achieved`, `CLAUDE_CODE_GOAL_CHECKIN_MINUTES` — M), but its evaluator "judges your condition against what Claude has surfaced in the conversation. It doesn't run commands or read files independently" (A, verbatim). That is a transcript judge, which is the precise thing this repo already ruled out of the exit path (`PROGRESS.md:40`), and it is the self-assessment trap every practitioner source names as the first failure mode. Worse, it does not merely fail to help: `/goal` is itself a session-scoped prompt-based Stop hook (A) and shares one consecutive-block budget with flow's own Stop hook — the binary's counter is `let xt = a.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8; if (xt > 0 && St > xt)`, telemetered as `tengu_stop_hook_block_count {…, goal_active}` (M). Stacking them halves the loop. The real gap is elsewhere and is pure glue: `/flow:loop <idea>` dies in one second because `flow loop init` exits 1 without `--verify` (A, `bin/lib/loop/init.js:209`), nothing in the repo turns a spec into a `tasks.json`, and spec and loop contain zero references to each other in either direction (M, greps in §3). The field's answer is unanimous and has one shape: **bootstrap once, loop forever** — snarktank's `/prd` → `prd.json` → `ralph.sh`, Anthropic's initializer-agent → coding-agent (A). Nobody bootstraps from a raw idea with zero human input, so a `--yolo` on-ramp is genuinely new ground; what makes it defensible is that the human read it removes was buying exactly one thing — *proof that the generated verifier can fail* — and that proof is mechanisable as a **negative control** (§5), a design this repo already scoped and deferred (`15:362`). Zero-gate is therefore acceptable if and only if the bootstrap breaks the app on purpose and refuses to arm unless the verifier goes red.

---

## 1. `/goal`: what it is, and the three reasons it cannot be the exit condition

Verified locally: `which claude` → `/Users/tomas/.local/bin/claude` → `/Users/tomas/.local/share/claude/versions/2.1.278`, `claude --version` → **2.1.278** (M). The binary is a single Bun standalone executable, so there is no per-command file; the evidence is strings, all of which match the documented behaviour (M).

| Property | Value | Grade |
|---|---|---|
| Invocation | `/goal <condition>` sets **and immediately starts a turn**; `/goal` bare = status; `/goal clear` (aliases stop/off/reset/none/cancel) | A |
| Storage | session-scoped, one goal per session, condition ≤ 4,000 chars; restored on `--continue`/`--resume`/picker since 2.1.239; `/clear` removes it | A |
| Judge | a **separate small fast model** (Haiku by default on the Claude API), reading the conversation | A |
| Verdicts | *not yet met* (reason fed back as next-turn guidance) · *met* (clears, records achieved) · *impossible* (clears, records failed) | A |
| Turn limit | **no flag exists**; you write "or stop after 20 turns" into the condition text and the evaluator judges that clause from the transcript | A |
| Underlying mechanism | "a wrapper around a session-scoped prompt-based Stop hook" | A |
| Hard stop | several turns with no tool use → Claude Code stops, warns, returns control **with the goal still set** | A |
| Clears the goal | unrecoverable context overflow, auth failure, exhausted credits, model unavailable | A |
| Keeps the goal | rate limit, usage limit, overload (3 retries), a hook that ended the turn | A |
| Background work | defers evaluation; check-in at 30 min then ×2 backoff to 4×, tunable by `CLAUDE_CODE_GOAL_CHECKIN_MINUTES` (`0` disables check-ins *and* retries); ≤ 3 idle check-ins per goal | A |
| Headless | `claude -p "/goal <condition>"` runs the whole loop in one invocation; needs `--output-format stream-json --verbose` to print anything before the end | A |
| Requires | workspace trust; unavailable under `disableAllHooks` or `allowManagedHooksOnly` | A |
| Model-facing twin | a `ProposeGoal` tool, setting `auto` (default) \| `alwaysAsk` \| `disabled`; cannot clear a goal | A |

The three disqualifications, in order of severity:

1. **The judge does not run anything.** It reads what the model surfaced. If the transcript says "all 412 tests pass", the judge has no way to disagree. This is the self-assessment trap, and the numbers behind it are already in this repo's evidence base: SEAL — 15/N policies self-reporting > 0.70 scored *below random* in deployment (B, `12:45`); PROCTOR — judge-reported 100% against a true 68% (B, `12:45`).
2. **The turn bound is prose.** With no `--max-turns` equivalent, "stop after 20 turns" is evaluated by the same model that evaluates the substantive condition. `03-agents-commands-memory-goal.md:306` already flagged this soft-vs-hard gap as the open question for unattended runs; the 2.1.278 docs confirm it is still prose.
3. **It occupies the slot flow needs.** See §2.

**None of this makes `/goal` bad.** It is the right tool for a condition only a reader can judge — triage a channel until every report is answered, keep refining a draft until it reads well. `12:83` already sited it correctly: the judge belongs *beside* the stack, not in it. The error is putting it in the exit path of a build.

---

## 2. The collision nobody documents: one block budget, two Stop hooks

From the 2.1.278 binary (M):

```js
let xt = a.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8;
if (xt > 0 && St > xt) /* "A hook blocked the turn from ending ${St} consecutive times — overriding and ending turn." */
```

Three consequences:

- Default 8, tested as `St > xt`: the **8th block is allowed, the 9th is overridden**. `12:22` and `skills/loop/SKILL.md` are correct to call the session shape an 8-iteration tool.
- `xt > 0` means **`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=0` disables the cap entirely** (M, read from the binary; **not in the docs** — treat as unstable and do not build on it).
- The telemetry event is `tengu_stop_hook_block_count {count, is_subagent, hit_max_turns, hit_cap, goal_active}`. `goal_active` is a *label on the same counter*, which strongly implies an active `/goal` and a plugin Stop hook interleave on one budget rather than one replacing the other. **UNVERIFIED by execution** — no billable run was made — but it is the safe assumption, and it means shipping guidance that says "use `/goal` with `/flow:loop`" would silently halve the session loop.

**Ruling for this repo: `/flow:loop` never recommends, sets, or composes with `/goal`.** If a future skill does both, it must say they share the cap.

The same applies to Anthropic's own `ralph-loop` plugin (`anthropics/claude-plugins-official/plugins/ralph-loop`): a Stop hook that re-feeds the same prompt and exits on an **exact string match** of `--completion-promise` (A). It occupies the same slot with a strictly weaker judge than `/goal`, and its own README says "Always rely on `--max-iterations` as your primary safety mechanism" (A). flow has no promise by design; nothing to borrow here.

---

## 3. Where `/flow:loop <idea>` dies today

It dies at step one. `flow loop init` returns 1 when `--verify` is absent (A, `bin/lib/loop/init.js:209-212`) and returns 1 again when the verifier is already green (`:214-218`, escapable only with `--allow-green`, `:62`). Writing that verifier is hand work the skill hands back to the operator (`skills/loop/SKILL.md:31-44`).

The four structural gaps:

| # | Gap | Receipt |
|---|---|---|
| 1 | No verifier generator anywhere | `init.js:209-212`; `skills/loop/SKILL.md:31-44` |
| 2 | No spec→`tasks.json` generator; the only bridge is a prompt a human pastes | `skills/loop/references/loop-prompt.md:84-95`; made deliberate by `.specs/006-loop-engineering/spec.md:24` ("No task-list format is imposed") |
| 3 | Zero glue both ways — `grep -rn loop skills/spec/` → nothing; `grep -rn "\.specs" bin/lib/loop/` → nothing (M) | — |
| 4 | Arming any loop blacks out the router: every `flow next` returns `loop-active` with `why: null` until `flow loop stop` | `bin/flow:2736-2755`, called at `:2775` |

And two facts that constrain any design:

- **`--unattended` is not code.** `grep -rn unattended bin/ hooks/ scripts/` hits tests only; `flow next` parses `--json --force --peek` (`bin/flow:2841-2848`). It is a prose instruction the model reads in `skills/next/SKILL.md:100` and `skills/spec/SKILL.md:53`.
- **Two lines no machine may write:** `Approved:` and `Verified:` (`skills/next/SKILL.md:121`; enforced at `router.js:471` and `:529`). No flag clears them, by design.

The current idea→shipped path carries **five human gates minimum** — prep interview, spec discovery turn, `unapproved`, `unverified`, merge — plus one per `CHK###` checkpoint (`router.js:486-491`).

What already works and needs only a caller: `flow loop run --shape fresh` is a real outer driver of `claude -p` children with iteration/minute/dollar/stall caps (`bin/lib/loop/driver.js:44-51,91-93`; defaults 30 iterations / 480 minutes / stall 3 at `init.js:68-69`), and the tamper veto is live — `init.js:151-170` records `verify_sha` and, **unconditionally since f37caa9**, `target_sha` over the verify script's own bytes (`init.js:160`, checked at `tamper.js:216-219`). The cheapest cheat in doc 15 — rewriting the verify script to `exit 0` — is therefore **closed** (A, re-read 22 Sep 2026); doc 15 §10's Stage 1 is done and this document supersedes its "still open" framing.

---

## 4. The field's shape: bootstrap once, loop forever

Four independent implementations, one structure (A unless noted):

- **snarktank/ralph** — `/prd` skill interviews the user → `tasks/prd-<feature>.md`; `/ralph` converts it → `prd.json` with per-story `passes: false`; `scripts/ralph/ralph.sh [max_iterations]` runs one story per iteration, typecheck + tests, commit only on green.
- **Anthropic, "Effective Harnesses for Long-Running Agents"** — a two-phase bootstrap: an **initializer agent** writes `init.sh`, `claude-progress.txt` and the first git commit; a **coding agent** then runs every session with the same prompt. Feature list is JSON, `"passes": false`, with the guardrail "It is unacceptable to remove or edit tests because this could lead to missing or buggy functionality." Named failure modes: **over-ambition** (context exhausted mid-implementation, broken state left) and **premature completion** (a later instance surveys finished features and declares the project done).
- **anthropics/cwc-long-running-agents** — the primitives as readable hooks: `verify-gate.sh` (default-FAIL: every criterion starts false, the agent must `Read` the evidence file before flipping it in `test-results.json`), `track-read.sh`, `commit-on-stop.sh`, `kill-switch.sh` (blocks all tool calls while an `AGENT_STOP` file exists), `steer.sh` (injects `STEER.md` mid-run), `agents/evaluator.md` (fresh-context grader, no Write/Edit).
- **Huntley** (C) — "one task per loop", fresh agent, clean context, identical prompt; warns against multi-agent complexity.

**The finding that matters for `--yolo`:** in every one of these, step one is *interactive*. snarktank's PRD skill asks questions. Anthropic's initializer is a separate, supervised phase. **No published harness bootstraps a verifier from a raw idea with zero human input.** A `--yolo` on-ramp is not a port of an existing pattern; it is an extension of one, and it must carry its own justification.

---

## 5. What the human read was buying, and the four machine substitutes

Strip the one confirmation gate and you lose exactly one thing: **a person looking at the generated verifier and judging whether it could ever fail.** Everything else at that gate (task count, caps, worktree name) is cosmetic. So the design question is narrow: what proves a machine-written verifier can fail, without a person?

**Substitute 1 — the negative control (the load-bearing one).** Before arming, deliberately break the thing under test and require the verifier to exit non-zero; then restore and require it to return to its original verdict. A verifier that stays green through a deliberate break cannot fail and must not be armed. This is not new invention: `15:362` scoped it as Stage 3 and deferred it with the trigger "ship it the first time a real loop produces a green run whose verifier wasn't reading the app." **`--yolo` is that trigger.** The break must be mechanical and revertible — e.g. `git stash` a required source file, or inject a sentinel failure into the module the first task names — and it must run *after* `init`'s existing red check, which only proves the verifier is red *now*, not that it is red *because of the app*.

**Substitute 2 — the default-FAIL task contract.** Every `tasks.json` item starts `passes: false` and may only be flipped after the evidence exists (Anthropic's `verify-gate.sh` pattern, A). The global verifier must be a conjunction of *all items pass* **AND** the suite is green, so the JSON alone can never end the loop — `skills/loop/references/verifier-design.md:§5` already states this rule; `--yolo` makes it mandatory rather than advisory.

**Substitute 3 — the tamper veto (already built, already sufficient).** `tamper.js` counts test files, watches for new `.skip(`/`xfail`/`#[ignore]`, regexes gate config, and hashes both the verify string and the verify script's bytes (`init.js:151-170`, `tamper.js:216-219`). A green run that trips any of these is `suspect`, and `suspect` is not fixable inside the loop. Under `--yolo` this is the only thing standing between an unwatched night and a deleted test suite, so it must be **fail-closed**: any tamper finding stops the run rather than marking and continuing.

**Substitute 4 — deterministic caps, with the money one first.** `--max-budget-usd` is the real bound for headless runs: a hard dollar cap, subagent spend included, spawning fails with `Budget limit reached` at the cap (A, 2.1.217+). Prefer it over `--max-turns`, which is real but **hidden from `claude --help` in 2.1.278** (M) and counts turns, not cost. Pair with `--permission-prompts none` (A, 2.1.259+): anything that would prompt is denied, Claude is told nobody can approve, `AskUserQuestion` is removed from the toolset, and denials land in `result.permission_denials` — the correct posture for a run with no operator.

**What none of these substitute for:** reward hacking against the visible suite only. The countermeasure is unchanged from `12` and `verifier-design.md:§4` — one test job the agent's shell cannot reach (CI on a protected branch, or a held-out directory under `permissions.deny`), compared against the local pass rate.

---

## 6. The design

`/flow:loop <idea> --yolo` gains a **Step 0 — bootstrap**, run once, interactively-shaped but answering its own questions:

1. **Spec.** Route the idea through the existing `/flow:spec` machinery (`scripts/new-spec` allocates `.specs/NNN-<slug>/` and writes `.current`). Under `--yolo` every DECISION gate resolves on the stated recommendation and is recorded as an Assumption — the behaviour `skills/next/SKILL.md:100` already describes in prose, now actually exercised.
2. **Task list.** Derive `.claude/loop/tasks.json` from TASKS.md: every item `passes: false`, priority-ordered, each carrying a runnable `verify`, each small enough for one context window (the over-ambition counter).
3. **Verifier.** Compose it from the spec's own verify lines, fastest and most discriminating first, as one command per `verifier-design.md:§2`. The global verifier is *all items pass* AND the suite.
4. **Negative control (§5.1).** Break, assert red, restore, assert the original verdict. **Refuse to arm on a verifier that survives the break.** This replaces the human read and is the reason `--yolo` is defensible at all.
5. **Arm.** `flow loop init … --shape fresh --worktree` then `flow loop run` in the background, with `--max-budget-usd` set and `--permission-prompts none`. Print the log path and end the turn.
6. **Land.** The run ends at a **draft PR**. `Approved:` and `Verified:` remain human (`skills/next/SKILL.md:121`). Five gates become one, and that one is at the end, where a person reads finished work instead of guessing at a plan.

No `/goal` anywhere in this path.

---

## 7. What must be fixed before anyone walks away

| # | Defect | Receipt | Why it blocks `--yolo` |
|---|---|---|---|
| 1 | A blank/unparseable `started_at` silently disables the max-minutes cap (NaN compares false); `corruptReason` never checks the field | `.specs/ISSUES.md:12` (I-002); `bin/lib/loop/tick.js:62`; `bin/lib/loop/contract.js:80-86` | the wall-clock bound is the one an unattended overnight run leans on; without it only `max_iterations` (default 30) applies |
| 2 | `loop-active` preempts the whole router with `why: null` | `bin/flow:2736-2755` | you come back in the morning, type `flow next`, and the pipeline is dark with no explanation |
| 3 | Tamper findings mark `suspect` and continue | `bin/lib/loop/tamper.js`, `skills/loop/SKILL.md` step 5 | with no operator watching, `suspect` must be a **stop**, not a label |

(1) and (2) are small and independent of the design; they can land first.

---

## 8. Anti-patterns for this feature

- **Never let `/goal` judge a build.** §1. And never ship guidance pairing it with a plugin Stop hook without stating the shared 8-block cap (§2).
- **Never arm a verifier that has not failed on purpose.** §5.1. `init`'s existing red check proves the verifier is red today; only the negative control proves it is red *because of the app*.
- **Never let a completion phrase into the loop.** Unchanged from `12` and `skills/loop/SKILL.md`. The `ralph-loop` plugin's `--completion-promise` is exactly the design this repo rejected.
- **Never auto-resolve an irreversible.** `--yolo` resolves DECISION gates on the recommendation; it must still stop on anything the spec route classifies as irreversible.
- **Never raise a cap to get past a wedge.** 2 repair rounds capture 76–95% of achievable gain (B, `12:166-170`); more search "often worsened" hacking (SpecBench, B).
- **Never regenerate the spec mid-loop.** Regeneration is a planning iteration that implements nothing (`loop-prompt.md:§6`).

---

## 9. Open and unverified

- Whether an active `/goal` and a plugin Stop hook literally interleave on one counter, or one replaces the other. The shared `goal_active` telemetry label implies interleaving; not executed (§2).
- `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=0` = unlimited — read from the binary, absent from docs. Unstable.
- Whether `--bare` disables `/goal` (bare skips hooks; `/goal` requires hooks). Inferred, not tested.
- Binary-present, doc-absent flags — `--task-budget`, `--rewind-files`, `--resume-session-at`, `--resume-drops-turn`, `--workload`. Do not build on them.
- **"Missions"** as a Claude Code feature: **no source found at all.** Prior references to it in this repo's notes should be treated as X until someone produces a citation.
- Checkpointing / `/rewind` is real (auto-snapshot before each prompt, 100 per session, ~30-day sweep) but **interactive only** — no headless flag drives it. Do not plan recovery around it.
- I-001 (the scripts suite red at base, ~96–107 unrelated failures) means the generated verifier still cannot be "the whole suite". `--yolo` must scope the suite to the files the spec touches, exactly as specs already do.

---

## 10. Sources (primary)

`code.claude.com/docs/en/goal` · `code.claude.com/docs/en/hooks-guide` · `code.claude.com/docs/en/hooks` · `code.claude.com/docs/en/headless` · `code.claude.com/docs/en/cli-reference` · `code.claude.com/docs/en/checkpointing` · `claude.com/blog/getting-started-with-loops` · `claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more` · `github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-loop` · `github.com/anthropics/cwc-long-running-agents` · `anthropic.com/engineering/effective-harnesses-for-long-running-agents` · `ghuntley.com/loop/` · `github.com/snarktank/ralph` · local binary `/Users/tomas/.local/share/claude/versions/2.1.278` · this repo: `bin/lib/loop/{init,tick,tamper,driver,contract}.js`, `bin/lib/router.js`, `bin/flow`, `skills/{loop,spec,next}/`, `.specs/ISSUES.md`, `docs/research/{03,11,12,15}`
