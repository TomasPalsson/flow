# Design — 009 ECC borrows

Only what two tasks must agree on. Everything else is in each task's brief.

## 1. Contract file

`plugins/flow/bin/lib/doctor-hygiene.js` — written by the orchestrator before the build, already wired into `buildDoctorChecks` in `plugins/flow/bin/flow`. It exports exactly three functions; each task fills the body of its own function only. The export list, names and signatures are fixed.

| canonical | identifier | defined in | banned synonyms |
|---|---|---|---|
| worktree check | `worktreeHygieneCheck(push, cwd)` | doctor-hygiene.js | staleWorktrees, wtCheck |
| personal-path check | `personalPathsCheck(push, repoRoot)` | doctor-hygiene.js | pathLeakCheck, homePaths |
| reference-doc check | `referenceDocsCheck(push, repoRoot)` | doctor-hygiene.js | docsDrift, refDocs |
| doctor row id | `'worktree-hygiene'`, `'personal-paths'`, `'reference-docs'` | push() first arg | any other spelling |

- `push(id, status, detail)` is doctor's own callback: `status` is `'PASS'` or `'WARN'` — these checks never push `'FAIL'`. One PASS row when nothing is wrong; one WARN row per finding otherwise.
- `cwd` is `process.cwd()`. `repoRoot` is the marketplace repo root (`path.resolve(__dirname, '..', '..', '..', '..')` from `bin/lib/`); a check whose inputs do not exist under it returns without pushing anything.
- Synchronous, `node:` built-ins only, `spawnSync('git', …)` for git — the same style as the rest of `bin/flow`.

## 5. Shared resources

| resource | owned by | others |
|---|---|---|
| `docs/reference/hooks.md`, `docs/reference/scripts.md` | T008 | T003 and T005 never edit them; T008 documents `context-pressure.sh` and the widened tamper-notice scope |
| `plugins/flow/scripts/tests/test_doctor_hygiene.sh` | created by T006 | T007, T008 append their own `t_doctor_*` functions |
| `plugins/flow/hooks/hooks.json` | T003 | — |

## 6. Deliberately duplicated

- The `hookSpecificOutput.additionalContext` printf in `context-pressure.sh` copies `search-first.sh:62` inline — two call sites; a shared helper waits for the third (Ruling: new abstraction waits for the third instance).

## 7. Decisions

- In the context of the loop child timeout, facing tests that cannot wait minutes, we chose an env override `FLOW_LOOP_CHILD_TIMEOUT_SEC` (seconds) read in `driver.js` and rejected a new CLI flag, to keep §2.2's no-new-flag rule, accepting one undocumented-to-users test knob. Makes hard: `driver.js`.
- In the context of build-slices re-look rounds, facing lenses that return null, we chose "a failed re-look keeps the previous round's blocking findings" and rejected "treat null as zero findings", to fail closed, accepting that a flaky lens can park a finding a human then clears. Makes hard: `build-slices.js`.

## Complexity Tracking

| Violation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| new module `doctor-hygiene.js` | `bin/flow` is 3,219 lines and size-guard flags growth | three more functions inline would push it further past the size budget |

## Contract for T003 — Context-pressure hook
MODULE     plugins/flow/hooks/context-pressure.sh · sources hooks/lib/hookout.sh · exports: nothing
CALLS      hook_field, hook_skip_if_off, _hook_tmp, _hook_sid, _json_str, hook_ok (all in hooks/lib/hookout.sh)
DUPLICATE  the additionalContext printf from search-first.sh:62 — copy it, do not add a helper to hookout.sh
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for T005 — Tamper-notice hidden-unicode scan
MODULE     plugins/flow/hooks/tamper-notice.sh · docs/reference/hooks.md is T008's — do not edit it
THE FIVE   (1)–(5) as in T003's block.

## Contract for T006 — Doctor worktree-hygiene check
CONTRACT   plugins/flow/bin/lib/doctor-hygiene.js — fill the body of worktreeHygieneCheck(push, cwd) only
NAMES      worktreeHygieneCheck · row id 'worktree-hygiene' · statuses PASS | WARN only
CALLS      push(id, status, detail) · spawnSync('git', [...], { encoding: 'utf8' })
THE FIVE   (1)–(5) as in T003's block.

## Contract for T007 — Doctor personal-paths check
CONTRACT   plugins/flow/bin/lib/doctor-hygiene.js — fill the body of personalPathsCheck(push, repoRoot) only
NAMES      personalPathsCheck · row id 'personal-paths' · statuses PASS | WARN only
CALLS      push(id, status, detail) · fs.readdirSync / fs.readFileSync
THE FIVE   (1)–(5) as in T003's block.

## Contract for T008 — Doctor reference-docs check + doc drift fix
CONTRACT   plugins/flow/bin/lib/doctor-hygiene.js — fill the body of referenceDocsCheck(push, repoRoot) only
NAMES      referenceDocsCheck · row id 'reference-docs' · statuses PASS | WARN only
CALLS      push(id, status, detail) · fs.readdirSync / fs.statSync / fs.readFileSync
THE FIVE   (1)–(5) as in T003's block.
