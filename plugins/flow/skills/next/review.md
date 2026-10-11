---
name: flow-review
description: How /flow:next reviews a per-task diff and a whole-branch diff — the seven adversary lenses (structure and docs advisory) with their self-commit protocol, severity buckets and verdict enum, the anchored 0–100 confidence re-score with the ≥80 keep rule, the bounded fix ladder, carried verdicts, and the stall rule. Loaded in the building and gating states.
---

# Flow Review

One protocol, two callers: the `building` state reviews a single task's diff, the `gating` state reviews the whole branch. The saved `review-diff` workflow implements this exactly; every other mode runs it inline. **The implementer never reviews its own work** — scanner ≠ fixer ≠ verifier is the whole point of this file.

If you cannot spawn a fresh reviewer (you are running inside a subagent), do not review your own diff. Stop, report "review not run: nested — rerun /flow:next from the main session", and write no PASS file. A self-review reads as a pass and is not one.

## Lenses

Each reviewer gets the brief path, the diff path, and at `gating` the repo's `REVIEW.md` when one exists at the repo root (with `review-diff`, the `reviewMd` argument; inline, hand each lens the path) — nothing else. A rule that file or the repo `CLAUDE.md` states and the diff breaks is a finding that cites the file and the rule; a rule a linter or hook already enforces is skipped, and so is a rule about process (how to run tools, commit habits, which package manager to use): only a rule checkable against the diff text is a finding. It must **re-open the diff itself** — a finding built from another agent's summary is a rumor.

| Lens | Asks |
|---|---|
| **correctness** | Does this do what the brief says, on the error and edge paths too? Off-by-one, unhandled rejection, wrong default, lost await, broken invariant. When the diff adds a command, migration, loop, deploy step or queue consumer: what does a second run do, what does a crash after each write leave behind, and can related writes be left half-applied with no way to reconcile them? |
| **gaming** | Was the gate satisfied rather than the problem? Skipped/xfail'd/deleted tests, assertions weakened to `toBeDefined()`, a threshold lowered, a stub left in the Green commit, behavior special-cased to the test's input. With Bash, run a mutation canary: flip one condition the diff added in a `git archive` copy outside the repo and run the related test; a surviving non-equivalent mutant is significant, and a test that cannot run there is NEEDS-TOOL, never a pass (steps in `agents/adversary.md`). |
| **security** | Untrusted input reaching a sink, authz checked in the wrong layer, a secret in the diff, an injection or traversal path. Agent features: model output, tool output and model-produced URLs are untrusted, so they are parsed, schema-validated and allowlisted before eval, SQL, shell, innerHTML, a file path, fetch or a persist write; the system prompt is not a security boundary; no secrets or other tenants' data in the context; Destructive tools require confirmation; token, rate and recursion limits are set. Also computed-path deletes, a loosened security control, an unnamed outbound host, and sibling parity: when a guard lands on one handler, check each peer handler on the same resource (full predicates in `agents/adversary.md`). |
| **cross-file** | Does this agree with the rest of the branch? Duplicated concept under a second name, a contract from `design.md` drifted, two tasks owning one file. At `gating` it also diffs `spec.md` and `design.md` against Base: a contract edit made on the branch with no `## Amendment` in `spec.md` and no `Ruling:` in `NOTES.md` is a blocking finding, because an agent that edits the contract to match its code passes a drift check against its own edit. |
| **slop** | Is this generic, duplicated, or plausible-looking but unproven? See `skills/no-slop/references/adversary-lens.md` for the checklist and evidence rule. |
| **structure** | Did the diff move complexity or remove it? Is there a restructuring under which branches, helpers or layers disappear? Whole-branch only, and advisory: its findings never block, they go into the PR body under `Could be smaller:`. Also match five smells, each phrased "possible <smell>": Feature Envy, Shotgun Surgery, Divergent Change, Message Chains, Refused Bequest (full definitions in `agents/adversary.md`); a standard the repo documents wins. |
| **docs** | Did the diff make a claim in a README, CLAUDE.md, `docs/` or `.specs` file false: a path, command, count, env var or symbol name? Quote the doc line and the diff line. Whole-branch only, and advisory: findings are listed in the PR body under `## Docs drift`, never block, and are not auto-fixed. Never style. |

**Which lenses run where is fixed, never a per-run choice**: `building` runs exactly **correctness + gaming + slop** on each task diff — the trio the saved `build-slices` workflow is pinned to, so every mode reviews a task identically. `gating` runs **all seven** on the branch diff, matching `review-diff`'s defaults; `structure` and `docs` are advisory there, returned in `advisory` and never in the blocking `verified` list. A task-level security or cross-file worry is not dropped, it is caught at `gating` where the whole branch is visible.

**One question per task, under correctness**: name one plausible wrong implementation of this task (error swallowed, boundary off by one, prefix match with no separator, running total from zero) — would these tests fail on it? A no is a finding.

**Self-commit protocol**: each reviewer states, before reporting, what it checked and what it deliberately did **not** check and why. A lens with no findings returns `verdict: CLEAN` and its `checked` list — **empty is a legitimate result**, and a reviewer that reads silence as failure manufactures the difference.

**Coverage**: in `review-diff` each lens also returns `filesRead`, the changed files it opened. The list of changed files comes from `review-package` (`<out>.files`, minus lockfiles, `*.min.*`, `dist/` and paths containing `generated`), never from the lens. A blocking lens with no findings that missed any of them is logged `lens:<name> incomplete (read N/M files)` and the review returns `incomplete: true` with the lens in `incompleteLenses`: silence from a lens that did not read the diff is not a clean pass. The recall sentence in that lens prompt ("a wrong suspicion costs nothing here because a separate scorer checks each one") belongs to `review-diff` only, where every finding is re-scored; the per-task review has no scorer and keeps the guard below against manufactured findings.

**Predates the change**: `review-package` also writes `<out>.anchors`, one `file:line` per line the diff adds. `review-diff` tags each finding `scope: in_diff` when its `file:line` is an anchor. A finding elsewhere survives only when it carries an `enabling_line` that is itself an anchor (a new caller of an old sink: the cross-file lens's whole job); otherwise it is returned in `predates[]`, never re-scored and never blocking. The caller appends each as `- Discovered: <file>:<line> — <what> — predates change — defer` to `NOTES.md` (a workflow cannot write it). Advisory lenses look outside the diff by design and are not tagged. Inline, read the `.anchors` file the same way.

**What it could not judge** goes in an optional `cannotVerify: [{ requirement, check }]`, where `check` is a runnable read-only command or grep. Before the task is ticked the orchestrator runs each check: a failing one becomes a `significant` finding in the ladder (with the command output as its receipt), a passing one is logged, and a check that would write or reach the network is refused and listed rather than run. `build-slices` and `review-diff` both do this; inline, run them yourself. A diff-only reviewer's silence about a requirement is then a command that ran, not an assumption.

## Finding shape and severity

Every finding: `{ predicate, severity, file, line, scenario, receipt }` — `scenario` is concrete inputs → wrong output; `receipt` is the `file:line` that proves it. A finding with no receipt is an opinion and is dropped before scoring.

- **fatal** — wrong behavior, data loss, security. Blocks the task.
- **significant** — a correctness risk or a missing test for a P0 behavior. Blocks the task.
- **minor** — style or preference. Never blocking; at most 3 per review. `build-slices` returns them as `minors: [{ task, finding }]`; the caller (inline mode too) writes each as `- Minor: T### <finding>` to `NOTES.md`, and the whole-branch reviewer at `gating` gets that list to triage. They surface only through `flow digest --json`.

Severity follows effect on the user even when the brief is silent: a missing behaviour a reasonable user expects (empty input, a failed call) is a correctness finding, not a downgrade. A finding the brief itself mandates (for example a `toBeDefined()`-only test the brief asks for) is labelled **plan-mandated**, still blocks, and goes straight to a Ruling or `--amend` so the human decides, because the implementer cannot fix a wrong brief inside the fix ladder. A warning or error log line in the test run at head but not at Base is a significant finding (correctness lens); warnings already present at Base are not.

Whole-branch lens: a hunk that changes pre-existing lines outside the feature (a formatter's or not) is a finding, and a gate-fix commit does not exempt it. Any changed or removed line in an existing test file is severity **fatal** and blocks the task.

Reviewer `verdict` is one of `CLEAN` / `FINDINGS` / `BLOCKED` (could not read the diff).

## Confidence re-score (independent, anchored)

Before scoring, `review-diff` runs `${CLAUDE_PLUGIN_ROOT}/scripts/receipt-check` over every unique finding. A finding may carry an optional `quote`, one verbatim line from the cited file. `receipt-check` marks each receipt `verified`, `moved` (the quote is elsewhere in the same file, so the line is corrected), `unsupported`, `unverifiable` (no quote) or `failed` (the file is neither at head nor deleted in the diff, or the quote appears nowhere). Only `failed` dismisses, with the reason `receipt-check: <reason>`; the others go on to scoring, and the scorer is never told the disposition. A removed or deleted test line counts as present, because the diff's `-` lines are searched too.

Every unique finding — deduped by `file + line bucket (line / 5, rounded down) + the first 12 words of the predicate` after folding case, `code` spans, numbers and punctuation, with the lenses that raised it kept in `lenses[]` — goes to a **different** agent than the one that raised it. That agent gets the claim only (predicate, location, severity and the failing input), fenced as untrusted text: not the finder's receipt, its lens, how many lenses agreed, or the check disposition. It re-opens the diff and scores 0–100 against fixed anchors:

- **0** — not a real issue. **25** — style or preference. **50** — plausible, unverified.
- **75** — verified real, low impact. **100** — verified real, correctness or security impact, demonstrated by a test you ran or confirmed by reading with file:line.

Anchors, exact text sent to the scorer: `0 = not a real issue; 25 = style or preference; 50 = plausible, unverified; 75 = verified real, low impact; 100 = verified real, correctness or security impact, demonstrated by a test you ran or confirmed by reading with file:line.`

Score whether the finding is real, not whether a justification for it exists; a commit message, comment or citation claiming a measurement never lowers the score.

The scorer also returns `how`: `demonstrated` (a test it ran) or `read` (confirmed by reading, with file:line). A first score of 50 or below gets exactly one fresh scorer, which sees the first reason and is told to try a different input before rejecting. The second score is final.

**Keep `score >= 80`; drop the rest** and report how many were dropped. A finding from a blocking lens with 75 <= score < threshold is verified real with low impact: it goes to the `lowImpact` list, which never blocks and is printed in the PR body (`shared/pr-body.md`, `## Low impact`); a 75 from an advisory lens is dropped like any other. The anchors are fixed text: never paraphrase them per run, or the threshold stops meaning the same thing between tasks.

**Security findings skip the scorer.** A finding with lens=security goes to a refutation panel of three `adversary` agents (REACHABILITY, IMPACT, DEFENSES), each given the fenced claim. A voter answers `TRUE_POSITIVE`, `FALSE_POSITIVE` or `PREDATES_CHANGE` with a severity and its reasoning. Code does the tally: the finding stays only when exactly 3 voters answered and at least 2 of 3 said `TRUE_POSITIVE`; confidence is `high` only at 3 of 3. The final severity is the lower median of the `TRUE_POSITIVE` severities, and applies only when it is lower than the reported one, so a panel can lower a severity and never raise it. Two `PREDATES_CHANGE` votes dismiss the finding as `predates change`. A panel with fewer than 3 voters dismisses it as `panel incomplete (n/3)` and marks the review `incomplete`. A scorer cannot decide a security finding that a panel has already judged.

## Fix ladder (bounded)

Per surviving fatal or significant finding:

0. **Triage first.** The fixer sorts each finding into *contract-misread* (the task's contract is wrong, not the code) or *code-defect*. A misread is not coded around: it returns a Ruling and an `--amend` proposal, because the plan is append-only and only an Amendment may change a task. The fixer may also dispute a finding, **with a receipt**: a `path:line`, a command, or a grep showing no callers. Each disputed finding goes to a fresh scorer (the anchors above, never the implementer's say-so); a score under 80 drops it and the result records it as `rejected-upheld`, a score of 80 or more carries it into the next round. A dispute with no receipt counts as not addressed.
1. **Rounds 1–3** — the same implementer fixes it, with the finding text and its receipt. Re-run `TEST_CMD` after each round. For a finding with no executed receipt (PLAUSIBLE), run its evidence step first; if that does not show the failure, record the finding as not reproduced instead of changing code. A plan-mandated finding skips the rounds (see above).
2. **Rounds 4–5** — a **fresh** implementer on a stronger model (`opus`), told what the first three attempts tried and why each failed.
3. **Then stop and record a ruling** in `NOTES.md`: `Ruling: <finding> — parked — <why> — <cost if wrong>`. Each parked finding gets a class: **known-open** (a later task can build on the code safely; the text goes into the Known gaps block of later tasks whose `files:` overlap) or **load-bearing** (a later task would build on a defect; later waves wait and the workflow returns `blocked: true`). A task too large to finish in one ladder is parked with `re-cut at --amend`: new task ids are appended, the original line is never edited. Continue to the next task only when nothing is load-bearing; the ruling surfaces again in the PR body.

**Long-run discipline** (`build-slices`): a developer's `gaps[]` (surprises the plan did not predict) and the known-open findings of earlier waves reach the briefs of later-wave tasks as one fenced `## Known gaps` block, so a wave does not rediscover what the last one learned. After the implement step a runner executes the task's own `verify:` command and reports the exit it saw; a non-zero exit parks the task before any review, whatever the developer reported. When a wave of three or more tasks ends with fewer than two thirds unparked, the workflow stops before the next wave with `stopReason: 'wave breaker'`: the failures are a pattern and the next wave would build on them.

**Scoped re-look**: record `FIX_BASE` (the HEAD sha) before each fix round. After it, package `FIX_BASE..HEAD` and make one adversary look at that round alone against the previous round's findings. It returns `{ verdicts: [{ finding, status: ADDRESSED | NOT_ADDRESSED, receipt }], newBreakage[], outOfScope[] }`. The next round's findings are the NOT_ADDRESSED ones plus `newBreakage`; a finding with no verdict is NOT_ADDRESSED. `outOfScope` notes are not findings: they go to `discovered` (a `Discovered:` line in `NOTES.md`) and never extend the ladder. Re-running every lens over the whole branch each round is what kept the ladder running to round 5 on untouched code.

**Test ids survive**: before the task, and after each fix round, list the collected test ids (`pytest --collect-only -q`, `cargo test -- --list`, `vitest list`; an unknown runner falls back to the count). Every id that existed before must still be listed unless the task line names it with `(replaces: ...)`. A lost id parks the task with `test removed: <id>`; a body swapped for a trivial one under the same name is still the gaming lens's to find.

**Doubt-stall**: when every finding was disputed or dropped two rounds running, stop with `doubt-stall` instead of looping; the human decides.

**Implementer concerns**: a developer that finishes `DONE_WITH_CONCERNS` hands its `concerns` to the adversaries as places to attack, after their self-commit. They are not evidence and never a ground to pass. A `BLOCKED` developer parks the task with no review.

**Inline mode keeps a ledger** so a `/clear` mid-ladder resumes at the right round (the saved `build-slices` workflow keeps its round in memory and needs none). After each round append one line to `NOTES.md`: `- Fix: T### round R/5 (X addressed, Y open; <sha>..<sha>)`. On re-entry read the last `Fix:` line for the task and continue at R+1; the round count alone decides the model, so R+1 >= 4 uses `opus` and a fresh implementer. Without the line, a restart begins at round 1 and skips both the cap and the escalation.

Revert any fix that worsens the scan. Never delete, skip, or weaken a test to clear a finding — the Stop gate and the tamper notice put that on the record anyway.

**Carried verdicts**: a finding already scored and dropped is **never re-litigated** while the code it points at is unchanged. Re-score only findings whose `file:line` moved in the latest diff.

**Stall rule**: `build-slices` makes this executable (`stopReason` `stalled`): if the surviving finding count (NOT_ADDRESSED plus `newBreakage`) does not decrease between two consecutive fix rounds, stop laddering and escalate — the agent is churning, not converging. Say so plainly, park what remains with rulings, and let the `unverified` human gate decide.

Credit: adapted from obra/superpowers skills/subagent-driven-development/re-review-prompt.md and docs/superpowers/specs/2026-07-15-sdd-fix-loop-redesign-design.md @ 1be8e34 (MIT).
