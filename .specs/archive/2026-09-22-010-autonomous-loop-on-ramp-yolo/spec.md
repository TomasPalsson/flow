# Spec: Autonomous loop on-ramp (`--yolo`)

**Created**: 2026-09-22 · **Route**: dispatch

## TL;DR

> Read this block. If it answers your question, stop here.

**Problem**: `/flow:loop` cannot start from an idea. It demands a goal, a verifier and a task list written by hand, and the supervised path around it stops for a human five times. So nobody can hand over a piece of work and leave.

**Solution**: `/flow:loop "<idea>" --yolo` bootstraps the spec, the task list and the verifier itself, proves the verifier can actually fail before arming, then runs unattended for up to four hours and leaves a draft PR.

**Who it's for**: the loop operator — anyone running flow in any repo, their own or a shared one — who wants to state an intent, walk away, and come back to finished work waiting for review.

**MVP cut line**: everything tagged `MUST` in §4.1 ships. `SHOULD` is v1.1. `MAY` is backlog.

**Key decision**: the human read of the generated verifier is replaced by a **negative control** — the bootstrap deliberately breaks the code under test and refuses to arm unless the verifier goes red. Zero-gate is defensible only because of this check; without it, `--yolo` is an unwatched agent grading its own homework.

## 1. Context

### 1.1 Problem statement

An operator with an idea has two bad options. The supervised path (`/flow:spec` → `/flow:next`) produces good work but stops for approval, for every checkpoint, for verification and for the PR — five interruptions minimum, so it cannot run while they are away. The unattended path (`/flow:loop`) has a real driver with caps and a tamper veto, but it refuses to start without a verifier command, and writing that command is the hard, careful part of the job. Nothing in the system turns an idea into the three inputs the driver needs, so the driver's autonomy is unreachable.

The reason it was never automated is a genuine risk, not an oversight: a machine-written verifier that cannot fail turns four unattended hours into four hours of confident nonsense, and the person who would have caught it is asleep.

**Current workaround**: the operator writes the goal, the verifier and the task list by hand, then arms the loop — roughly the same effort as doing the first task themselves.

### 1.2 Roles

> Every requirement below names one of these roles. A requirement with no role is incomplete.

| Role | What they do | Key characteristic |
|------|--------------|--------------------|
| Loop operator | states an idea, arms the run, leaves | not present while it runs; cannot answer a question |
| Reviewer | reads the draft PR when the run ends | usually the same person, four hours later, with no memory of the run |
| Repo co-owner | owns other branches and CI in a shared repo | never consented to this run; must be unaffected by it |

**Primary actor**: the loop operator.
**Hidden stakeholders**: repo co-owners, whose branches, protected refs and CI minutes an unattended run could otherwise disturb.

## 2. Scope

### 2.1 In scope

- Turning a one-line idea into a spec, a task list and a verifier without asking a question
- Proving the generated verifier can fail, and refusing to arm when it cannot
- Running unattended under caps of time and iterations, in an isolated branch and working copy
- Ending at a draft pull request that names what was done and what remains
- Stopping the run outright — not flagging it — when the test layer is tampered with
- Two prerequisite defects that make an unattended run untrustworthy today (§4.1 FR-01, FR-02)

### 2.2 Non-goals

> Binding. A change here is an amendment, not an interpretation.

- **No `/goal` integration of any kind.** Its evaluator judges the conversation transcript rather than running anything, and it shares one eight-block budget with flow's own stop hook, so pairing them would halve the loop while weakening the exit condition.
- **No completion phrase, promise, or any model-emitted done signal.** The exit condition is a command the harness runs.
- **The reviewer still confirms the work.** A machine may record that the plan was accepted; only a person records that the result was verified, and the pull request stays draft until they do.
- **No automatic merge, no push to a protected branch, and no commit to the branch the operator was standing on.**
- **The generated verifier does not run the repository's continuous-integration suite.** That job stays out of the agent's reach on purpose, as the independent check the reviewer reads afterwards.
- Not a supervised-mode change: `/flow:spec` and `/flow:next` keep every gate they have today.

## 3. Journeys

### Journey 1 — Arm and leave (loop operator)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | a repo with a working test command and a clean tree | the operator states an idea with `--yolo` | within one turn: a spec directory, a task list where every item is unproven, a composed verifier that has been shown to fail on purpose, an isolated branch and working copy, a background run, and a printed log location — no question asked |
| Error | the same, but no command can be composed that distinguishes done from not-done | the operator states the idea with `--yolo` | nothing is armed; the run exits non-zero naming which of the three inputs could not be produced; the tree is exactly as it was |
| Edge | the generated verifier passes even when the code under test is deliberately broken | the bootstrap runs its negative control | arming is refused, the break is reverted, and the reason names the file that was broken and the verdict that did not change |

### Journey 2 — Come back four hours later (reviewer)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | a finished run | the reviewer asks for status | a draft pull request exists; the summary names every completed item, the commits behind them, and which cap ended the run |
| Error | a run that stopped early | the reviewer asks for status | the stopping reason is one of the named states, the work so far is committed, and the reviewer is told what remains — never that it finished |
| Edge | the run went green but a test file was removed or a check was skipped | the reviewer asks for status | the run stopped at that moment rather than continuing; the finding is reported verbatim and no pull request claims success |

### Journey 3 — Somebody else's repo (repo co-owner)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | a shared repo with a protected main branch and continuous integration | a run completes | a new branch and a draft pull request exist; the protected branch, every other branch and the operator's original working copy are untouched |
| Error | the operator's current branch has uncommitted work | the operator arms the run | the run refuses to start rather than committing or discarding that work |
| Edge | the run hits its money cap mid-task | the cap fires | the partial task is not committed, the branch is left at the last green commit, and the draft pull request is opened anyway naming what remains |

## 4. Requirements

### 4.1 Functional requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | A loop contract whose start time is missing or unreadable MUST be treated as corrupt rather than run | a contract with a blanked or unreadable start time is reported corrupt and does not run |
| FR-02 | MUST | When a loop is active, the router MUST state which loop, at which iteration, and how to inspect it, instead of returning an empty reason | the router's reason field is non-empty and names the goal and the status command while a loop is armed |
| FR-03 | MUST | The loop operator MUST be able to arm a full run from a single idea with no question asked and no gate in the middle | one command on a fixture repo produces spec, task list, verifier and an armed run |
| FR-04 | MUST | The bootstrap MUST prove the composed verifier fails when the code under test is broken, and MUST refuse to arm when it does not | a fixture whose verifier always succeeds is refused, with a non-zero exit and a reason naming the unchanged verdict; the file broken is the first one named by the first task, and a first task naming no tracked file is refused rather than skipped |
| FR-05 | MUST | The negative control MUST leave the working tree byte-identical to its state before the check, whether it passed, failed, or was interrupted | the tree's checksum before and after is equal in all three cases |
| FR-06 | MUST | Every generated task item MUST start unproven and carry its own runnable check; the overall verifier MUST require every item proven AND the scoped test command green | a task list whose items are all marked proven, with a red test command, does not end the run |
| FR-07 | MUST | A tamper finding MUST stop the run under `--yolo` rather than mark it and continue | a run whose test-file count drops stops at that iteration with the tamper reason |
| FR-08 | MUST | The run MUST take place on its own branch in its own working copy, and MUST NOT commit to the branch the operator was on | after a run, the operator's original branch is at the commit it started at |
| FR-09 | MUST | Unattended child sessions MUST be launched such that anything requiring approval is denied rather than left waiting | the dry run's printed arguments contain the no-prompt setting |
| FR-10 | MUST | The run MUST end at a draft pull request whether it finished or hit a cap, and MUST NOT record the reviewer's verification | the pull request exists, is draft, and the verification line is absent |
| FR-11 | MUST | Anything that fails during the bootstrap MUST refuse to arm and exit non-zero, leaving nothing half-armed | after any induced bootstrap failure, no contract file exists |
| FR-12 | SHOULD | The final report SHOULD name which cap ended the run, so the operator can tune one number | the report names exactly one of the cap reasons |
| FR-13 | SHOULD | The composed verifier SHOULD scope its test command to the files the spec touches rather than the whole suite | the composed command names a scoped target, not the full run |
| FR-14 | MAY | The bootstrap MAY record each auto-resolved decision as an assumption with its confidence | assumptions appear in the spec with confidence values |

## 5. Non-functional requirements

| Dimension | Number | How it is measured |
|-----------|--------|--------------------|
| Default wall-clock cap | 240 minutes | the armed contract's minute cap |
| Default money cap | none (user ruling 2026-09-22); `--max-usd` still sets one | the armed contract's `max_usd` is 0 |
| Default iteration cap | 40 | the armed contract's iteration cap |
| Stall tolerance | 3 iterations with no change | the armed contract's stall setting |
| Negative-control cost | exactly 2 extra verifier runs | count of verifier invocations during the check |
| Negative-control time bound | ≤ 2 × the verifier timeout (1200 s at the default) | the check aborts and refuses to arm past this |
| Bootstrap questions asked | 0 | no prompt is emitted between the command and the armed run |
| Human gates between arming and the pull request | 0 | count of stops in the run log |

## 6. Launch criteria

- [ ] Every MUST in §4.1 has a passing test
- [ ] A fixture with a verifier that cannot fail is refused, and the refusal names why
- [ ] A contract with a blanked start time no longer runs uncapped
- [ ] The working tree is provably unchanged after a negative control, including when interrupted
- [ ] A dry run shows the no-prompt setting in the child arguments
- [ ] One real run on a throwaway repo reaches a draft pull request with no human input
- [ ] The scoped test command used as the gate is green on this machine

## 7. Assumptions

| # | Assumption | Confidence | Blast radius if wrong |
|---|------------|-----------|-----------------------|
| A1 | The negative control's induced break is a strong enough proxy for "the verifier reads the app" | Med | a verifier that passes the control but is still blind to a whole class of failure; the run wastes its caps |
| A2 | Four hours and 40 iterations are the right defaults for a typical feature | Low | runs end at a cap with partial work; the operator tunes one number and re-arms |
| A3 | An active loop and any other stop hook in the session share one eight-block budget | Med | only affects the supervised in-session shape, which `--yolo` does not use |
| A4 | Scoping the gate to touched files is enough while the full suite is red at base (I-001) | Med | a regression outside the touched files reaches the pull request; the reviewer's independent check catches it |
| A5 | Auto-resolving planning decisions on the stated recommendation produces work worth reviewing | Med | the reviewer rejects the pull request wholesale; four hours are spent |
| A6 | A single-file revert is a safe way to undo the induced break in every supported repo | Med | a dirty tree after an interrupted control; FR-05's checksum test is the guard |

## 8. Open questions

None. Both questions raised during drafting were resolved before freeze:

- Which file the negative control breaks — the first file named by the first task; a first task naming no tracked file is refused (exit 3). Recorded in §4.1 FR-04 and `design.md` §7.
- Whether a capped run opens the pull request — it does, naming what remains. Recorded in §4.1 FR-10 and Journey 3's edge path.

## Appendix A — Glossary

| Term | Means |
|------|-------|
| Verifier | the single command whose exit status is the loop's only exit condition |
| Negative control | deliberately breaking the code under test to prove the verifier can report failure |
| Tamper finding | evidence that the test layer was weakened since the run began |
| Fail-closed | a finding stops the run, rather than labelling it and continuing |
| Scoped test command | the project's test runner narrowed to the files this feature touches |
| Draft pull request | a pull request explicitly not ready to merge, awaiting the reviewer |

## Amendment 2026-09-22
What changed: one task added (T009). `test_loop_docs.sh` asserts `### Execution — Fallback Path` in `plugins/flow/skills/fix/SKILL.md`; commit 14f8844 removed that heading when direct execution became the default and the loop became opt-in (`--loop`). The check has been red since, which holds every task verified by `test_loop_docs.sh` (T006, T007) at exit 1.
Why: the check's intent — `/flow:fix` works without the fresh loop — still holds, but under a different name. T009 re-points the assertion at the current direct-execution text rather than restoring a heading for a path that no longer exists. T006 now runs after T009.
Not this: no change to `plugins/flow/skills/fix/SKILL.md` itself.
