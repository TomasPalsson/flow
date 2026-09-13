---
name: no-slop-rubric
description: The PASS/FAIL rubric for AI-slop in a diff. Every row names its detector (mechanical via scripts/slop-check, or the adversary `slop` lens) and the false-positive guard. Load when scoring a diff or writing an eval grader for one.
---

# no-slop rubric

Scope is always **the added lines of one diff** against a base ref. A row PASSES when the condition holds for every added line or new symbol; it FAILS on the first counter-example, and the finding must carry `path:line`.

Severity is one of `block` (an adversary reports it as a finding that must be fixed before the slice is clean) or `advise` (reported, fixed if cheap, never blocks). The mechanical script is always `advise`; only the lens can `block`, and only with a receipt.

## A. Reuse and abstraction

| ID | PASS condition | Detector | Severity | False-positive guard |
|---|---|---|---|---|
| NS-01 | No added block of ≥ 3 lines / 15 tokens duplicates code that exists at base, in any file, after renaming identifiers | `slop-check` via jscpd `--ignore-identifiers --baseline-from-ref` | advise | Excludes tests, generated code, lock files. A same-shape block that two independently deployed services must own separately needs a comment saying so. |
| NS-20 | No new function or block re-implements behaviour an existing repo helper, stdlib call, or already-imported library provides | lens (checks the search receipt, then runs the search itself) | block | A wrapper that changes the contract (different input type, added caching) is not a re-implementation; it must call the existing helper inside. |
| NS-21 | No new helper, interface, base class, parameter, flag or config key has fewer than three real call sites or users in the diff plus base | lens | block | A second implementation that the spec names, or a hot path measured in the brief, earns the abstraction at two. |
| NS-27 | The developer's report contains one search receipt line before the first edit: what was searched (names, verbs, imports, error strings) and what was found | lens (reads the developer report) | block | A slice that only edits existing bodies with no new symbol needs no receipt. |

## B. Defensive padding and error masking

| ID | PASS condition | Detector | Severity | False-positive guard |
|---|---|---|---|---|
| NS-03 | No added `except:` / `except Exception:` / empty `catch` whose body only passes, continues, returns a default, or logs without re-raising | `slop-check` (stdlib; ruff BLE001/E722 when present) | advise | A top-level entry point, request handler, or worker loop that must not die is a boundary; it keeps the broad catch but logs with context. |
| NS-22 | No added guard (`is not None`, `hasattr`, `isinstance`, `if not x`, `?.`, `\|\| {}`) on a value the type signature, constructor, prior validation, or non-null schema already guarantees | lens | block | Values from user input, external APIs, files, environment, or optional fields are boundaries; guard them. |
| NS-09 | No added `as any`, `as unknown as`, `@ts-ignore`, `# type: ignore`, `cast(Any, …)` | `slop-check` | advise | An escape hatch with a same-line reason naming the upstream type bug is allowed. |

## C. Comments and documentation

| ID | PASS condition | Detector | Severity | False-positive guard |
|---|---|---|---|---|
| NS-23 | No added comment restates the adjacent code, and no added docstring only repeats the signature; every kept comment states a WHY (constraint, invariant, workaround, surprise) in one short line | lens | block | Public API or library entry points may carry full docstrings when the file already does. |
| NS-05 | No added function with a body of ≤ 3 lines carries a docstring of ≥ 3 lines | `slop-check` | advise | Exported API in a file where every sibling has one. |
| NS-15 | No added comment references the current task, fix, caller, or ticket ("used by X", "added for the Y flow", "see issue #123") | `slop-check` | advise | A comment linking a permanent external spec (RFC, vendor doc) is fine. |
| NS-07 | No emoji in added comments | `slop-check` | advise | String literals that the product renders are not comments. |

## D. Scope and style

| ID | PASS condition | Detector | Severity | False-positive guard |
|---|---|---|---|---|
| NS-24 | Every added file, symbol, option and behaviour traces to a sentence in the brief; no cleanup, rename, reformat, or feature outside it | lens | block | Out-of-brief work belongs in the report's `## Discovered` list, not the diff. |
| NS-10 | No added compat shim, deprecated wrapper, `_legacy`/`_old` symbol, or dual code path for a symbol with zero external callers | `slop-check` (marker) + lens (callers) | advise / block | A public package API with downstream consumers keeps its shim. |
| NS-25 | Added code matches the surrounding file: quote style, naming case, indent, import style, error type | lens | block | A file with no consistent style takes the project formatter's output. |
| NS-06 | No new function, class or long-lived variable is named from the generic pool (`data`, `result`, `temp`, `item`, `handle`, `manager`, `helper`, `util`, `process`, `info`, `value`, `obj`, `thing`) | `slop-check` (function and class defs, plain `x = …` / `const x = …` assignments) | advise | Loop variables inside a ≤ 3-line comprehension, tuple-unpacking targets, and plain assignments inside test files (the act-phase `result = fn()`) are not scanned; the script does not judge lifetime, the lens does. |
| NS-04 | No added hedge phrase (`TODO`, `FIXME`, `in a real implementation`, `for now`, `placeholder`, `not implemented yet`) on the code that was the task | `slop-check` | advise | A TODO with a ticket reference for work the brief defers. |
| NS-08 | No added `print(` / `console.log(` outside CLI output paths and logging modules | `slop-check` | advise | Files under `cli/`, `scripts/`, `__main__`. |
| NS-14 | Diff shape is reported: files added vs modified, lines added. Not a verdict | `slop-check` summary | info | The brief's size tier sets the expectation; the lens judges, the script counts. |

## E. Tests

| ID | PASS condition | Detector | Severity | False-positive guard |
|---|---|---|---|---|
| NS-13 | No added skip/xfail/`xit`/`describe.skip`, no removed assertion without an equal or stronger one in the same hunk, no widened tolerance, no `raises(Exception)` / bare `.toThrow()`, no commented-out assert | `slop-check` (test files only) | advise → lens confirms → block | A skip with a ticket and a reason string that names the blocker. |
| NS-26 | Every new test can fail: no `assert True`, no `toBeDefined()` as the only check, no assertion that the mock was called with the input just passed, no expected value computed by re-running the implementation's logic, no snapshot as the only assertion on business logic | lens | block | Snapshot of stable serialised output with a named matcher beside it. |
| NS-28 | Red was real: the new test failed against the pre-change code (exit non-zero) before Green | pipeline (`TEST_CMD` exit code recorded in the developer report) | block | none |
| NS-29 | Test names describe behaviour, not implementation (`test_calculates_total`, not `test_uses_for_loop`) | lens | advise | none |

## F. What is not slop (do not flag)

- A guard at a real boundary (user input, network, file, env, optional schema field).
- A broad catch in an entry point that logs and keeps the process alive.
- A full docstring on a public API in a file that already documents siblings.
- Three similar lines that have not yet earned a helper.
- Duplication justified in a comment or ADR (independent deployables, hot loop).
- A TODO with a ticket for work the brief explicitly defers.
- Pre-existing issues on lines the diff did not add.
- Anything a configured linter or formatter already reports.

## Grader mapping for evals

| Rubric row | Grader type | Target |
|---|---|---|
| NS-01, NS-03 to NS-10, NS-13, NS-15, NS-16 | `regex` `match: not_contains` on `{source: file, path}` or the script's `--json` output | file |
| NS-20 | `regex` `contains` the existing helper's name in the edited file, plus `not_contains` the re-implementation's tell (`re.sub`, `new RegExp`, hand-rolled loop) | file |
| NS-27 | `regex` on `last_message` for `searched .* found` | last_message |
| NS-21 to NS-26, NS-29 | `llm` with the row's PASS condition as the criteria, `focus: {source: file, path}` | file |
| NS-28 | `tool_order`: `Bash` running the test before `Edit` of the implementation; or `regex` on trace for a non-zero exit | trace |
