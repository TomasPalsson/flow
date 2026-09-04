# Step 0 — Resume, detect, classify, mode, branch

## 0.1 Resume check

Read `.claude/flow.json` (spec number, slug, spec dir, branch, worktree — written by `${CLAUDE_PLUGIN_ROOT}/scripts/new-spec`) and `.claude/workflow-state.local.md` (mode, size, detected commands, unattended flag, code-design path, Progress).

- Both present with `type: flow` → restore, read `.claude/feature-plan.local.md`, and **jump to the first unchecked phase — do NOT re-run discovery or re-plan.**
- **Stored `unattended` wins over the resume invocation.** A `--unattended` flag passed on resume does not convert a run authorized as attended — its pending gates were promised to a human. Converting takes an explicit ask, and then you MUST re-state the 0.6 gate manifest, because a resume skips this step and the stop count would otherwise change with nothing announcing it.
- Current branch ≠ stored branch → check `git worktree list`; if the worktree exists, tell the user where it is and stop.
- `type` is another workflow → stop and say so. Neither file → fresh start below.

## 0.2 Detect the project

Detect `TEST_CMD`, `LINT_CMD`, `FORMAT_CMD`, `TYPECHECK_CMD`, `DEV_CMD`, `E2E_CMD` with `${CLAUDE_PLUGIN_ROOT}/skills/shared/scripts/detect-project`; `${CLAUDE_PLUGIN_ROOT}/skills/shared/project-detection.md` covers the fallbacks. **Never hardcode tool commands** — detected commands encode the real toolchain (monorepo, container, CI).

## 0.3 Speccability guard, then size

**Guard first.** If the request is empty (`/flow` alone) or unspeccable (no problem, no users, no domain signal — "make it better"), do NOT classify. Ask the three grounding questions — (1) what problem this solves, (2) for whom, (3) what they do today instead — and resume only after they are answered. **This guard blocks even under `--unattended`**: an unattended run on an unspeccable request refuses to start rather than inventing a problem statement, because every later phase inherits that invention.

Then classify Small / Medium / Large against the size table in `SKILL.md`. This one classification drives discovery depth, slice count and pipeline depth for the whole run. Show it; accept a one-word override and recalculate the discovery budget to the new tier.

## 0.4 Pick the orchestration mode

Read [`../orchestration.md`](../orchestration.md) — the one rule plus mode detection — then read **only** the chosen mode's file. State the choice in one line: *"Orchestration: **Workflow mode** (ultracode on) — build slices pipeline through the saved `build-slices` workflow; the user-approval gate stays with me."*

## 0.5 Spec dir + branch

Run `${CLAUDE_PLUGIN_ROOT}/scripts/new-spec "<feature title>" --prefix flow/` (add `--worktree` unless `--no-worktree` was requested; add `--no-branch` when the user wants to stay on the current branch). It computes the next `NNN`, creates `.specs/NNN-slug/`, creates and checks out `flow/<slug>`, writes `.claude/flow.json`, and prints that JSON. Read the JSON back — `spec_dir` is where step 1 writes, `branch` is the PR head, and `git rev-parse HEAD` right after is the review **base** steps 4–5 diff against.

Write `.claude/workflow-state.local.md` with `type: flow`, the mode, size, `unattended` flag, detected commands, the base sha, the code-design path (once step 3 writes it), and an empty `## Progress` section.

## 0.6 Gate manifest

State in one line how many times this run stops for the user and where.

- Attended: *"This run will stop for you twice: plan approval (step 3) and verification (step 5)."*
- Unattended: *"Unattended: no stops. Plan auto-approved; verification deferred to PR review; PR stays draft."*

Then read [`01-spec.md`](01-spec.md).

End the step with the line `Next: …` from `harness next`.
