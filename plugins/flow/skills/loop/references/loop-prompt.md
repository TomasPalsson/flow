---
name: loop-prompt
description: The per-iteration prompt anatomy, the task-list (tasks.json) template, the learnings-file format, and the initializer prompt for greenfield loops. Load before writing --prompt-file.
---

# Loop prompt and task list

Four independent implementations converged on the same four roles: a spec ("done when"), a task list, execution rules, and a learnings log (Huntley: `specs/` `fix_plan.md` `PROMPT.md` `AGENT.md`; snarktank: `prd.json` acceptance criteria and stories, `prompt.md`, `progress.txt`; Anthropic's harness: feature JSON, coding-agent prompt, `claude-progress.txt`; Codex: `Prompt.md` `Plan.md` `Implement.md` `Documentation.md`). In `flow loop` the contract carries the spec (`goal` + `verify`), the body carries the rules, `LEARNINGS.md` is the log, and the task list is yours to choose.

## 1. What every iteration receives (supplied by `flow loop`, do not repeat it in the body)

```
[flow loop] iteration <n> of <max> — goal: <goal>
verifier `<cmd>` exited <rc>; last lines:
<verifier tail, ≤ 40 lines>
<stall warning when nothing changed last iteration>
Read .claude/loop/LEARNINGS.md, then make the ONE smallest change that moves the verifier. Do not claim completion; the loop checks.
<your body>
```

The body is what you write. Its job is to name the task list, the selection rule, and the project's own conventions. Keep it under 60 lines; every line is re-read on every iteration by a fresh context.

## 2. Body template

```markdown
Task list: .claude/loop/tasks.json — pick the highest-priority item with "passes": false.
Before changing anything, search the codebase; do not assume something is missing.
Do exactly that one item. If it will not fit in one iteration, split it: add the remainder
as new items (passes:false) and do the first part.

Build/run: <one line>. Tests: <one line>. Lint: <one line>.
Conventions: <three lines at most; link to CLAUDE.md for the rest>.

When the verifier for the item is green: commit `feat(<scope>): <item id> — <title>`, set
"passes": true for that item only, append to LEARNINGS.md (what, learned, next).
Bugs you notice outside the item: add them to tasks.json as items; do not fix them now.
Out of scope: <the fence — what this loop must not touch>.
```

Guardrail lines borrowed from the field, with their reason:

- "Before making changes search the codebase (don't assume not implemented)" — Huntley's most-cited sign; a nondeterministic search once made the loop re-implement existing code.
- "Implement functionality completely. Placeholders and stubs waste effort redoing the same work" — the reward function is compiling code; say it.
- "When authoring tests, capture the why" — future iterations "will not have the reasoning in their context window".
- "Use many subagents for searches and reads and exactly one for build/tests" — fan-out is safe for reading; the validation step must be a single, unambiguous run.
- Escalating emphasis: the ralph-playbook numbers its invariants 99999, 999999, … — the more 9s, the more load-bearing. A cheap way to mark the two lines the model must not lose.

## 3. `tasks.json` template (JSON on purpose: the model is "less likely to inappropriately change or overwrite JSON files compared to Markdown files" — Anthropic)

```json
{
  "goal": "<the loop's goal, verbatim>",
  "verify": "<the verifier, verbatim>",
  "items": [
    {
      "id": "T001",
      "title": "User can open a new chat and see a reply",
      "priority": 1,
      "passes": false,
      "steps": ["click New chat", "type a message", "press Enter", "reply appears in the thread"],
      "verify": "bunx playwright test tests/e2e/new-chat.spec.ts",
      "notes": ""
    }
  ]
}
```

Rules: every item fits one context window (if not, it is two items); every item has a runnable `verify` (never "code is clean"); items start `passes: false`; the model changes only `passes` and `notes`, and appends new items — "It is unacceptable to remove or edit" items (Anthropic's wording for its feature list). The loop's global verifier should include a check that every item passes AND the suite is green, so the JSON alone cannot end the loop.

## 4. `LEARNINGS.md` format (append-only)

```markdown
## Codebase patterns
- <general, reusable; promoted from entries below>

## 2026-09-07T22:10Z — iteration 3 — T002
- did: <one line>
- learned: <gotcha, convention, where things live>
- next: <the smallest next step>
```

Patterns at the top are what a fresh iteration reads first. Entries are never edited. At `/wrap`, promote durable patterns to PROGRESS.md rulings or CLAUDE.md and leave the file to the run.

## 5. Initializer prompt for a greenfield loop (one-off, before the first `flow loop init`)

Anthropic's harness uses "a different prompt for the very first context window". Run this once, interactively, then arm the loop:

```
Read the spec at <path>. Produce .claude/loop/tasks.json: every end-to-end behaviour the spec
implies as an item with runnable acceptance (browser or CLI), priority-ordered, all passes:false,
each small enough for one context window. Write an init script at the project root (for example `init.sh`) that installs, starts the dev
server and runs one smoke check. Make an initial commit. Do not implement any item.
```

Then: `flow loop init "<spec goal>" --verify "./init.sh && node -e '<all items pass>' && <suite>" --shape fresh --prompt-file .claude/loop/prompt.md --max-iterations 40 --max-usd 25 --worktree`.

## 6. Regenerate, do not patch

When the task list stops matching reality (duplicate work, items done but unmarked, clutter), run one planning iteration whose body is "compare the spec to the code with subagents and rewrite tasks.json from scratch; implement nothing", then resume. Huntley: "I have deleted the TODO list multiple times."
