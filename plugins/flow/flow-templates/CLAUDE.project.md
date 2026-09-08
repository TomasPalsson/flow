# {{PROJECT_NAME}}

## Commands
- Test: `{{TEST_CMD}}`
- Lint: `{{LINT_CMD}}`
- Typecheck: `{{TYPECHECK_CMD}}`
- Dev: `{{DEV_CMD}}`

## Behavioural rules
- Surface assumptions; when several readings exist, ask rather than pick silently.
- Minimum code that solves the problem; no speculative abstractions or flags.
- Surgical changes only; every edited line traces to the request.
- Define verifiable success criteria first; for bugs, write the reproducing test first.
- When the user corrects a mistake, run `/lesson` before resuming the work.

## Verify before done
Run the test command above before calling anything done. For UI work, load
the page and look at it — a passing test suite is not the same as a working
page.

## Conventions
- Keep changes scoped to what was asked; no drive-by refactors.
- Match the existing style of the file you are editing.
- Prefer the smallest diff that solves the problem.

## Never
- Edit a test to make it go green — fix the code or say the test is wrong.
- Commit secrets, tokens, or credentials.
- Touch {{PROTECTED_PATHS}} without being asked.

See REVIEW.md for review standards and PROGRESS.md for current state.
