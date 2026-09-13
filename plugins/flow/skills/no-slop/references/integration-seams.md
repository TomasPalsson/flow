---
name: no-slop-integration-seams
description: Where the no-slop skill plugs into the flow plugin's pipeline — the exact files for the developer block, the slop lens, the optional hook, and the eval suite. Load only when wiring the skill into a pipeline stage; never for a developer, adversary or grader invocation.
---

# Integration seams (flow plugin)

| Seam | File(s) | Change |
|---|---|---|
| Developer brief | `plugins/flow/scripts/task-brief`, `plugins/flow/workflows/build-slices.js` (`implementPrompt`) | append the fenced block from `references/developer-block.md` verbatim after the task section; name the receipt line and `slop-check` in the implement prompt |
| TDD state machine | `plugins/flow/skills/next/execution-prompt.md` GREEN and REFACTOR | receipt line before the first edit; `slop-check --base <base>` before reporting |
| Per-slice review | `plugins/flow/workflows/build-slices.js` both `parallel([...])` review arrays | `adversaryPrompt('slop', briefPath, diffPath)` with label `adv:slop:<id>` |
| Branch review | `plugins/flow/workflows/review-diff.js` default lens list; `plugins/flow/skills/next/review.md` lens table | append `slop`; one table row pointing at `references/adversary-lens.md` |
| Adversary agent definition | the user's own Claude Code agent definitions (outside this plugin): `agents/adversary.md` under their Claude config dir | add a `slop` lens bullet that points at `references/adversary-lens.md` |
| Optional hook | `plugins/flow/hooks/hooks.json` PostToolUse | `slop-guard.sh` calling `slop-check --files <edited>` through `hook_note`, never `hook_deny`; toggle `slopGuard` in `.claude/flow.config.json` |
| Optional hook | `plugins/flow/hooks/hooks.json` UserPromptSubmit | `search-first.sh` fires on an add/implement/create/introduce + new-symbol prompt, emits one `additionalContext` receipt-line nudge; toggle `searchFirst` in `.claude/flow.config.json` |
| Eval suite | `plugins/flow/evals/quality-*` | one case per rubric row with a fixture that plants the reuse target; graders from `references/rubric.md`'s mapping table |

## v2 notes

- `flow/SKILL.md` invariants clause dropped at the v2 merge; v2's `/flow:spec` route decides artifacts.
