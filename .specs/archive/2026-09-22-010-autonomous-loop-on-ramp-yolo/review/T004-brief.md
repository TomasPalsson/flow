# Brief — T004
Base: 49caae4
Feature: /Users/tomas/Desktop/Projects/flow/.specs/010-autonomous-loop-on-ramp-yolo
Approved: 2026-09-22 by user
Spec: spec.md
Design: design.md
Route: dispatch
Test: `TEST_ONLY=test_loop.sh bash plugins/flow/scripts/tests/run.sh`

## Phase 3 — The unattended child
Goal: a yolo run is bounded by time, money and iterations, and its children can never sit waiting for an answer nobody will give.
Independent test: `TEST_ONLY=test_loop_yolo.sh bash plugins/flow/scripts/tests/run.sh` — green with the negative control untouched.

## Your task
- [ ] T004 --yolo defaults and child arguments (B5, B6, FR-09, FR-12) — files: plugins/flow/bin/lib/loop/init.js, plugins/flow/bin/lib/loop/driver.js, plugins/flow/scripts/tests/test_loop_yolo.sh — verify: `TEST_ONLY=test_loop_yolo.sh bash plugins/flow/scripts/tests/run.sh` — after: T003


## Before you write
```
Avoid over-engineering. Only make changes that are directly requested or clearly
necessary. Keep solutions simple and focused:

- Scope: Don't add features, refactor code, or make "improvements" beyond what was
  asked. A bug fix doesn't need surrounding code cleaned up. A simple feature doesn't
  need extra configurability.
- Documentation: Don't add docstrings, comments, or type annotations to code you
  didn't change. Only add comments where the logic isn't self-evident.
- Defensive coding: Don't add error handling, fallbacks, or validation for scenarios
  that can't happen. Trust internal code and framework guarantees. Only validate at
  system boundaries (user input, external APIs).
- Abstractions: Don't create helpers, utilities, or abstractions for one-time
  operations. Don't design for hypothetical future requirements. The right amount of
  complexity is the minimum needed for the current task.

Before writing any new function, class, or helper: search the whole repository for an
existing implementation of the same behaviour. A name search is not enough — the helper
you need is usually named differently. Do all three: (1) list the helper packages
(`**/{utils,support,helpers,lib,common,shared,core}/**`) and open every small module
there; (2) grep the exact idiom you are about to write — the regex (`[^a-z0-9]+`), the
join, the format string, the arithmetic — an existing helper contains it; (3) grep the
verb and two synonyms (slug: kebab, dash, hyphen; format: render, label; validate:
check, verify; parse: load, decode; retry: backoff) plus the library you would import.
When an LSP tool is available, query workspace symbols for each term too. Reuse what
exists. State in one line what you searched and what you found before your first edit,
in the form: `searched: <terms and dirs>; found: <path:line | nothing>`.

Two rules that are not the same rule:
- An existing helper is reused, always. Re-implementing one is a defect.
- A new helper is extracted at the third similar block, or in a measured hot path,
  never at the second. Three similar lines beat a premature abstraction.

Comments: default to none. Add one short line only when the WHY is non-obvious — a
hidden constraint, an invariant, a workaround for a specific bug, behaviour that would
surprise a reader. Never explain WHAT the code does, and never reference the current
task, fix, ticket, or callers; those belong in the report and rot in the code.
No docstring on a function shorter than five lines unless the file already documents
every sibling.

Match the surrounding file exactly: quote style, naming case, indent, import style,
error types. Read the three functions above and below your insertion point first.

Tests: the new test must fail against the unchanged code before you make it pass, and
you report that exit code. Expected values come from the spec or hand computation,
never from running the implementation. No `assert True`, no `toBeDefined()` alone, no
asserting a mock was called with the input you just passed, no `raises(Exception)`,
no sleeps, no snapshot as the only assertion. Never skip, weaken, or delete a test.

Write a high-quality, general-purpose solution. Do not hard-code values or special-case
the test inputs. If the task is unreasonable or a test is wrong, say so in the report
instead of working around it.

Before reporting done, run `scripts/slop-check --base <base>` and either fix each
finding or justify it in one line in the report.
```

## Contract for T004 — `--yolo` caps and child arguments
CONTRACT   `plugins/flow/bin/lib/loop/contract.js` — the caps are existing keys.
NAMES      `max_minutes`, `max_usd`, `max_iterations`, `stall_after`, `yolo` — all strings.
MODULE     `init.js` (defaults) and `driver.js` (child argv) · layer 2
CALLS      `--yolo` sets the spec §5 defaults only when the operator passed no explicit cap.
           The child argv must contain `--max-budget-usd <max_usd>` and `--permission-prompts none`.
DUPLICATE  §6 bullet 2 — the cap-refusal path keeps its own message.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.

## Rules
Touch only the paths in files:. Failing test first, verify it fails, minimal
implementation, verify it passes, commit. Do not tick the box — the
orchestrator re-runs verify: and runs flow tick T004.

## Clarifications (orchestrator)
- `flow loop init --yolo` (init.js `parseInitArgs` + `buildInitFront`): writes `yolo: '1'` and `fail_closed: '1'` into the front matter; without `--yolo` both are `'0'`. tick.js already reads `front.fail_closed === '1'` — do not touch tick.js.
- Defaults under `--yolo`, applied PER CAP, only to a cap the operator did not pass: `max_minutes '240'`, `max_usd '50'`, `max_iterations '40'`, `stall_after '3'`. An explicit `--max-usd 10 --yolo` keeps `10` and still gets 240/40/3. Without `--yolo`, every existing default is unchanged byte for byte.
- driver.js `buildClaudeArgs`: when `front.yolo === '1'`, append `--permission-prompts none` (a real `claude` flag: anything that would prompt is denied automatically). `--max-budget-usd` is already emitted when `max_usd > 0`; with the 50 default it must show up. Without yolo, argv is unchanged.
- Prove it in the NEW file `plugins/flow/scripts/tests/test_loop_yolo.sh`, self-contained like `test_loop_failclosed.sh` (copy its CLI-locating header and `fc_cli_in` pattern under a `yo_` prefix). Tests named `t_yolo_default_caps` (B5: init --yolo --shape fresh with no caps → contract front has 240/50/40/3, yolo 1, fail_closed 1), `t_yolo_explicit_cap_kept` (explicit --max-usd kept, others defaulted), `t_yolo_child_argv` (B6: `flow loop run --dry-run` after a yolo init prints an `argv:` line containing both `--max-budget-usd 50` and `--permission-prompts none`), and `t_no_yolo_argv_unchanged` (non-yolo dry run has no `--permission-prompts`). Use `flow loop init` with a verifier that starts red (e.g. `--verify false`) or `--allow-green`, whichever init needs — read init.js.
- Must stay green: `TEST_ONLY=test_loop.sh bash plugins/flow/scripts/tests/run.sh` and `TEST_ONLY=test_loop_negcontrol.sh bash plugins/flow/scripts/tests/run.sh`.
- Commit message describes the change, e.g. `feat(loop): --yolo arms with 240 min / $50 / 40 iterations and children that deny prompts instead of waiting`.
