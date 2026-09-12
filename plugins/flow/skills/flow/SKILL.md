---
name: flow
description: "End-to-end build pipeline merging flow-spec + flow-feature + flow-deepen into one pass: idea → spec → harsh judge (once, no loop) → internal vertical-slice build plan (code design when slices share a seam) → TDD Red/Green/Refactor per slice → inline gates → quality swarm → browser verification → user approval (hard gate) → verified PR → optional architecture deepen. No GitHub issues, no AFK/HITL tags — spec decomposes into an internal build plan and builds straight through. Mode-aware: picks subagents, agent team, or deterministic Workflow in Phase 0; human gates never delegate. Pass `--unattended` to walk away — decision gates auto-resolve on flow's own recommendations, user verification defers to PR review, and the PR stays draft. Use when the user says /flow, \"build this end to end\", \"spec and build it\", \"idea to PR\", \"full pipeline\", \"spec then ship\", \"run it unattended\", \"build this without stopping me\", \"don't stop for me\", \"walk away\", or describes something to build and wants it carried all the way through in one go. Do NOT use for a spec with no intent to build (use /flow-spec), a bug fix (/fix), a whole-repo audit (/audit), or when the user explicitly wants tracked GitHub issues or an AFK-HITL plan (use /flow-to-issues)."
---

# Flow — Idea to Verified PR in One Pass

`flow` fuses the `flow-*` skills into one linear pipeline you run once and walk away from. The seam the user never wanted is gone: **flow never creates GitHub issues**, no AFK/HITL tags, no per-issue handoff. The spec decomposes into an internal vertical-slice build plan and builds straight through.

```
[0 Setup] → [1 Spec] → [2 Judge] → [3 Plan] → [4 Build] → [5 Verify] → [6 PR]
                       opt-in      HARD GATE   TDD/slice   HARD GATE     ready
```

Architecture deepening is no longer a phase here — after the PR, point the user at `/flow-deepen`.

**This file is a router.** Read the next step file only when you reach that step; never load them all up front. Every fan-out phase runs through one orchestration mode — subagents, an agent team, or a deterministic Workflow — chosen once in step 0.

## Run components by value, not by checklist

Two kinds of step answer to different rules. This pipeline is the full menu, not a checklist to complete on every run.

- **Invariants** hold the moment their phase runs, at every size, no exceptions. The spec always lands at `<spec_dir>/spec.md` and verification always lands in `.claude/verification/` — even a two-property, single-file change gets both files; size scales discovery depth and verification breadth, never whether the artifacts exist. Both human approval gates (plan approval, user verification) stay **in the main loop**; Red exits non-zero and Green exits zero, verified by *you* and not an agent's word; scanner ≠ fixer ≠ verifier; never edit a test to go green; any feature with UI gets browser-verified; any build whose slices share a seam gets a `code-design.md` — **two or more slices sharing a name, id type, error shape, module boundary, or shared resource** is the trigger, never file count and never the size tier, and the doc is skipped otherwise, including on every one-slice build; and flow never creates GitHub issues. Size and time pressure never excuse them.
- **Scalable components** are selected by value and scaled to the size tier: the harsh judge, `showcase`, E2E tests, review breadth, the QA pass, `better-plan` rendering, code-design depth, and how heavy the orchestration mode is. Litmus per component: *"Would running this change what ships or catch a real defect here?"* If no, skip it — **and say you skipped it.** Running everything every time is the same bug as skipping an invariant: one weight applied to every step.

**Hooks own the mechanics.** The harness hooks format every edit, flag oversized files/functions, blocks destructive git, records test-weakening, and refuses to end a turn while gates are red. Treat their feedback as a check to satisfy, never noise to suppress. They do **not** enforce the invariants above — those are yours.

## Size

| | Small | Medium | Large |
|---|---|---|---|
| Files / scope | 1–3, single concern | 4–15, 1–2 areas | 15+, cross-cutting |
| Spec discovery | 2–4 questions | 5–7 questions | full discovery (cap 10) |
| Build slices | 1–3 | 3–6 | 6–12 |
| Code design depth (when triggered) | sections 1–7 | sections 1–7 | sections 1–11 |
| Example | config, copy, small refactor | component, endpoint | full-stack, subsystem |

Show the classification; let the user override with one word. **On override, recalculate the discovery budget to the new tier before step 1** — a Small→Large override that keeps the Small budget produces a Large spec no later phase can fix.

**Gate manifest rule**: before any work, state in one line how many times this run stops for the user and where. The user decides whether to stay before their attention is spent, not after.

## Unattended mode (`--unattended`)

`--unattended` auto-resolves human DECISION gates using recommendations flow already makes; every verification invariant still runs and evidence is still gathered for real. **It resolves decisions, not evidence.**

| Gate | Attended | `--unattended` |
|---|---|---|
| 0 speccability guard | asks 3 grounding questions | **still blocks; run refuses to start** (cannot invent a problem statement) |
| 1 discovery | serial interview | consolidate-mode, one batched offer, then proceed on recommendations recorded as Assumptions |
| 2 judge decision | user picks fixes | auto-applies flow's own recommendation (ship-blockers only, rest carried as Assumptions) |
| 3 plan approval | HARD GATE | auto-approved after the batched offer |
| 3 showcase UI direction | user picks | takes recommended direction, records as Assumption |
| 5 user verification | HARD GATE | **deferred, not skipped** — PR stays draft, evidence attached, user verifies at PR review |
| 6 deepen offer | offered (`/flow-deepen`) | skipped, and the PR body says so |

**Batched-offer protocol**: ask ONE question early — *"Answer a few questions now, or Mr Claude proceeds on its recommendations?"* — then run `sleep 90` as a BACKGROUND Bash call (`run_in_background: true`) so the wait does not block the turn. The offer fires **once per run**, at the first gate needing input. Unanswered when it returns → the user has left: proceed on recommendations at this and every later gate, without re-offering. Answered → they are present: offer again at the next decision gate. Never a blocking `AskUserQuestion` in unattended mode except the speccability guard.

Every auto-resolved decision is recorded as `Assumption (confidence: <level>)` in the spec (steps 1–2) or plan (step 3), and surfaced again in the PR body.

## Step index — read ONE file when you reach it

| Step | File | Read it when |
|---|---|---|
| 0 Setup | [steps/00-setup.md](steps/00-setup.md) | at the start of every run, including a resume |
| 1 Spec | [steps/01-spec.md](steps/01-spec.md) | after setup states the mode and gate manifest |
| 2 Judge | [steps/02-judge.md](steps/02-judge.md) | only when the run carries `--judge` |
| 3 Plan | [steps/03-plan.md](steps/03-plan.md) | once a spec file exists |
| 4 Build | [steps/04-build.md](steps/04-build.md) | after the plan is explicitly approved |
| 5 Verify | [steps/05-verify.md](steps/05-verify.md) | after every slice's triplet lands |
| 6 PR | [steps/06-pr.md](steps/06-pr.md) | after user verification clears (or is deferred) |

Supporting files, loaded only where a step tells you to: [planning.md](planning.md) (step 3), [review.md](review.md) (steps 4–5), [orchestration.md](orchestration.md) (step 0, then one mode file).

## Routing matrix

| Work | Mode default | Model | Note |
|---|---|---|---|
| Codebase / spec research | parallel readers | `haiku` | read-only |
| Spec discovery dialogue | main loop (interactive) | orchestrator | never delegated |
| Harsh judge (×1, opt-in) | single agent / one stage | `sonnet` | follows a rubric |
| Code design (step 3) | main loop | orchestrator | architecture and interface decisions are orchestrator-tier |
| Design adversary lens | single agent / one stage | `sonnet` | different agent than the design's author |
| Build plan decomposition | main loop | orchestrator | has full context |
| Red / Green / Refactor per slice | subagent / team task / `build-slices` | `sonnet` (`agentType: developer`) | one slice per context; ready slices launch together, ≤ 4 per wave |
| Slice review lenses | two adversaries / `review-diff` | `sonnet` (`agentType: adversary`) | both launched in one message; scanner ≠ fixer ≠ verifier |
| Inline gates / browser / PR | main loop (CLI) | orchestrator | no LLM cost |
| User verification | **main loop only** | — | HARD GATE, never delegated |

In Workflow mode the build and review fan-outs become the saved `build-slices` and `review-diff` workflows and the model column is the per-`agent()` model; the **main loop only** rows still run outside the workflow.

## NEVER do

- **NEVER create GitHub issues, AFK/HITL tags, or a tracked issue set.** A user who wanted issues asked for the wrong skill — point them to `/flow-to-issues`.
- **NEVER run the harsh judge more than once, or loop on it.** Residual gaps after one pass trace to discovery, not drafting; a second run cannot fix them.
- **NEVER soften the harsh judge to look clean.** Harsh means over-report — false positives are acceptable, silence is not.
- **NEVER move a human gate into a subagent, agent team, or workflow.** Plan approval and user verification always run in the main loop; inferring approval from silence ships the agent's interpretation of "correct", not the user's.
- **NEVER skip the orchestration-mode decision.** Large work as serial subagents wastes hours; a tiny change through a full Workflow wastes tokens.
- **NEVER write implementation in a Red phase or a test in a Green phase**, and never accept an agent's "tests fail" without running `TEST_CMD` yourself. The exit code is the only ground truth.
- **NEVER skip Browser Verification or the Refactor phase for any size.** Unit tests miss CSS, asset, runtime and a11y failures; "tests pass, ship it" is Test-First, not TDD.
- **NEVER let a reviewer verify or fix its own findings.** Scanner ≠ fixer ≠ verifier: an agent that saw its own finding rationalizes it, and a self-confirmed auto-fix ships a real defect behind a false-clean gate.
- **NEVER emit a deepening slice that changes an interface, external contract, or caller-visible symbol without the user's explicit decision.** That is a feature choice wearing a refactor's clothes.
- **NEVER duplicate the referenced files into this skill.** `flow` references the kept originals (`flow-spec/`, `feature/`, `shared/`) as the single source of truth; copies rot the moment an original changes.
- **NEVER start a build phase with a load-bearing assumption ungathered.** Guessed scope, users or criteria target the wrong feature; re-planning mid-build costs more than asking.
- **NEVER add scope beyond the approved plan.** Agent scope-creep is invisible until PR review — log additions as follow-ups instead.
- **NEVER treat the scalable components as a checklist to complete.** Select each by value and scale to size; the flip side is equally banned — the invariants are never skipped to save time.
- **NEVER let `--unattended` weaken a verification invariant.** Exit codes, scanner ≠ fixer ≠ verifier, and browser verification are identical in both modes.
- **NEVER promote an unattended run's PR to ready, or delete its verification evidence.** "User approved" is a precondition `gh pr ready` has not met; a ready PR with no human verification looks reviewed and is not.
- **NEVER chain shell commands in a pipeline step** (`;`, `&&`, `||`, `|`). A chained command matches no pre-approval and parks the run on a permission prompt. Two facts are two calls.
