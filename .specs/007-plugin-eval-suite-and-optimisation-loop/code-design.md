# Code design — 007 plugin eval suite and optimisation loop

Not a spec. Fixes names, locations and signatures shared across slices; behaviour and acceptance criteria stay in `spec.md`.

## 1. Contract file + ubiquitous language

Contract file: `plugins/flow/bin/lib/eval/contract.js` (CommonJS, `require`d by `eval.js`, the doctor check and `scripts/tests/test_evals.sh` via `node -e`). Owner: orchestrator; slices import, never edit.
```js
'use strict';
const TAGS = ['quality', 'routing', 'invariant', 'pipeline', 'needs-bash'];  // every case tag ⊂ TAGS
const EVALS_ROOT = 'plugins/flow/evals';                                   // relative to repo toplevel
const LEDGER_PATH = 'plugins/flow/evals/ledger.jsonl';
const CONFIG_KEYS = { model: 'evalModel', judgeModel: 'evalJudgeModel' };  // .claude/flow.config.json
const DEFAULT_MODELS = { model: 'claude-sonnet-5', judgeModel: 'claude-haiku-4-5' };
const MIN_CLAUDE_VERSION = '2.1.269';
function ledgerLine(fields) { /* {ts, sha, model, judgeModel, tags:{<tag>:{score, delta, cases}}, meanDelta, costUsd, partial, reason} */ }
module.exports = { TAGS, EVALS_ROOT, LEDGER_PATH, CONFIG_KEYS, DEFAULT_MODELS, MIN_CLAUDE_VERSION, ledgerLine };
```
| Canonical | identifier | collection | defined in | banned synonyms |
|---|---|---|---|---|
| rubric row id | `NS-01`…`NS-29` | rows | `skills/no-slop/references/rubric.md` | `SLOP-1`, `rule 1`, `R-01` |
| lens | `slop` | lenses | `skills/flow/review.md` table, `agents/adversary.md` | `no-slop`, `quality`, `reuse` |
| eval tag | `quality` / `routing` / `invariant` / `needs-bash` | `TAGS` | contract.js | `code-quality`, `trigger`, `bash` |
| developer block | `skills/no-slop/references/developer-block.md` | — | slice 1 | `pre-write checklist`, `slop rules` |
| checker | `skills/no-slop/scripts/slop-check` | — | slice 1 | `slop-lint`, `slopcheck`, `slop_check` |
| ledger | `evals/ledger.jsonl`, one JSON object per line | lines | contract.js | `history`, `results.json` |
| subcommand | `flow eval` | — | `bin/flow` dispatch → `bin/lib/eval.js` `run(argv, cwd, env)` | `flow evals`, `flow test-plugin` |
| case dir | `evals/<tier>-<slug>/` with `case.yaml`, `scaffold.sh`, `graders/` | cases | slice 4 | `scenarios/` |

`node -e "require('./plugins/flow/bin/lib/eval/contract.js')"` exits 0 before handoff; every shared function is synchronous.

## 2. Type contracts & trust boundaries
| Boundary | untrusted input shape | parse fn | failure granularity |
|---|---|---|---|
| `claude plugin eval --json` output | `string` (stdout or file) | `parseAggregate(text): {ok, data\|error}` in `eval.js` | whole run: exit 1 "unparsable result" |
| `.claude/flow.config.json` | `unknown` | existing `hook_config`-equivalent reader in `eval.js`: `readConfigKey(toplevel, key): string\|''` | key absent → default, never throw |
| `case.yaml` tags | list of strings | `test_evals.sh` asserts ⊂ `TAGS` | per case, test failure |
| scaffold scripts | executable bash, run as the user | `flow eval` refuses paths outside `plugins/*/evals/` | whole run: exit 1 |

## 3. Error taxonomy

`EXIT = { ok: 0, fail: 1, partial: 2 }` declared once in `eval.js`; adding a variant is a design change.
| CLI exit | `flow eval` exit | meaning |
|---|---|---|
| 0 | 0 ok | every case ≥ threshold |
| 1 | 1 fail | a case below threshold, a load error, no `claude`, or an unparsable result |
| 2 | 2 partial | cost ceiling or auth rejected; ledger line has `partial: true` |
| other | 1 fail | raw code in the message |

## 4. Module boundaries
- `plugins/flow/bin/lib/eval/` · layer 1 · may import: `node:*`, `./contract.js`, `../loop/util.js` (`headSha`, `resolveOnPath`) · exports: `run` · seam: **eval runner**. Anything not listed is a bug.
- `plugins/flow/skills/no-slop/` · layer 0 · imports nothing from the repo · exports: `scripts/slop-check`, `references/*.md` · seam: **slop rubric**.
- `plugins/flow/evals/` · data · may reference rubric row ids in case names · seam: **eval cases**. `.gitignore` · data · owned by slice 4.
- `plugins/flow/workflows/*.js`, `scripts/slice-brief`, `skills/flow/review.md`, `skills/feature/execution-prompt.md` · consumers · may reference the developer block and the lens by the literal paths and names above · seam: **pipeline seams**.
- `plugins/flow/bin/flow`, `plugins/flow/bin/lib/loop/init.js` · layer 2 CLI shell · may import: `./lib/eval.js`, existing loop modules · exports: dispatch, help, doctor rows · seam: **cli shell**.
- `plugins/flow/scripts/tests/` (`test_<slice>.sh`, `fixtures/<name>/`) · test harness · may import: `lib.sh` · exports: `t_*` functions · seam: **test harness**.

## 5. Shared resources & construction
| resource | constructed-by | passed-how | received-by |
|---|---|---|---|
| `claude` binary path | `resolveOnPath('claude', env)` from `loop/util.js` | argument | `eval.js` runner, doctor check |
| repo toplevel | `git rev-parse --show-toplevel` in `eval.js` | argument | ledger writer, scaffold guard |
| results dir | the CLI (`<eval dir>/results/<ts>/`) | read from `--json` file | ledger writer |
| config keys `evalModel`, `evalJudgeModel` (camelCase like `sizeGuard`) | `readConfigKey` | value | model selection; timestamps are `new Date().toISOString()` |

## 6. Deliberately duplicated — do NOT consolidate
- Hedge-phrase, generic-name and test-weakening regexes live in `slop-check` only; eval graders restate the few they need as YAML `pattern:` literals. No YAML generator.
- Each `case.yaml` carries its own `scaffold.sh`; no shared fixture library.
- `flow eval` re-implements nothing of `claude plugin eval`; it shells out and parses. No embedded grader logic.
- The developer block is pasted whole by `slice-brief`; `execution-prompt.md` references the receipt format by name, never copies the block.

## 7. Decisions
1. In the context of `flow eval`, facing a CLI whose JSON is the only stable surface (schemaVersion 1), we chose a thin runner (`spawnSync claude plugin eval … --json <file>`, parse, ledger) and rejected re-implementing grading in Node, to achieve zero drift from the CLI, accepting that every CLI flag change is a `flow eval` change. `Makes hard:` swapping the eval engine — touches `bin/lib/eval.js` and `evals/README.md`.
2. In the context of case tags, facing YAML that cannot import a contract, we chose a `TAGS` constant plus a test that reads every `case.yaml`, and rejected a case generator, to achieve one source of truth with plain files, accepting a test-time rather than compile-time check. `Makes hard:` adding a tier — touches `contract.js`, `test_evals.sh`, `README.md`.
3. In the context of the `slop` lens, facing per-slice cost, we chose per-slice plus branch placement and rejected branch-only, to achieve catching a clone before slice 2 builds on it, accepting one extra adversary call per slice. `Makes hard:` cheaper slices — touches `build-slices.js`, `review.md`.
4. In the context of the mechanical checker, facing a closest-tool false-positive rate of 36.7% (a blocking hook would stop a legitimate edit about one time in three), we chose advisory exit 0 and rejected a blocking hook, to achieve a check developers act on instead of route around, accepting that a missed advisory ships until the lens catches it. `Makes hard:` a hard gate later — touches `slop-check`, `hooks.json`.
5. In the context of code-editing evals, facing no `socat`, we chose Write/Edit-only cases tagged plain and Bash cases tagged `needs-bash` (skipped with a notice), and rejected blocking on socat, to achieve a runnable suite today, accepting no mutation-testing oracle in v1. `Makes hard:` mutation cases — touches `eval.js` skip logic, case tags.

## Contract for this slice — Slice 1: no-slop skill and slop-check
CONTRACT   none imported; this slice DEFINES `references/rubric.md` row ids NS-01…NS-29 and `scripts/slop-check` ids ⊂ those rows.
NAMES      `NS-xx` · `slop-check` · `developer-block.md` · receipt line format (banned: `SLOP-1`, `slopcheck`, `reuse ledger`)
MODULE     `plugins/flow/skills/no-slop/` · layer 0 · may import: nothing · exports: scripts/slop-check, references/* · seam: slop rubric
CALLS      `slop-check [--base <ref>] [--head <ref>] [--json] [--strict] [--no-tools] [--files <path>...]` → exit 0 (1 only with --strict)
DUPLICATE  regexes: `scripts/slop-check` only. Fixture builder: `scripts/tests/fixtures/no-slop/make-fixture.sh`, separate from `evals/`.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for this slice — Slice 2: developer briefs carry the block and the slop lens runs per slice
CONTRACT   `plugins/flow/skills/no-slop/references/developer-block.md` fenced block, verbatim; `references/adversary-lens.md` path in the adversary prompt.
NAMES      lens `slop` · receipt line `searched: …; found: …` · `slop-check` (banned: `no-slop` as a lens name, `search log`)
MODULE     `plugins/flow/scripts/slice-brief`, `plugins/flow/workflows/build-slices.js`, `plugins/flow/skills/feature/execution-prompt.md` · consumers · seam: pipeline seams
CALLS      `slice-brief <plan> <N> [--design …] [--out …]` unchanged signature; appends the block after the slice section; `adversaryPrompt('slop', briefPath, diffPath)` added to both `parallel([...])` arrays.
DUPLICATE  execution-prompt.md carries the receipt format string only, not the block.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for this slice — Slice 3: branch review runs the slop lens
CONTRACT   `references/adversary-lens.md` path; lens name `slop`.
NAMES      `slop` · lens table row order: correctness, gaming, slop, security, cross-file
MODULE     `plugins/flow/skills/flow/review.md`, `plugins/flow/workflows/review-diff.js` · consumers · seam: pipeline seams
CALLS      `const lenses = args.lenses || ['correctness', 'security', 'gaming', 'cross-file', 'slop']`
DUPLICATE  lens contract: `skills/no-slop/references/adversary-lens.md`; review.md row: one sentence with that path.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for this slice — Slice 4: the eval suite
CONTRACT   `TAGS` from `plugins/flow/bin/lib/eval/contract.js` (read via `node -e` in the test); rubric row ids from `skills/no-slop/references/rubric.md`.
NAMES      case dir `evals/<tier>-<slug>/` · tags ⊂ TAGS · grader names `ns-20-uses-existing-helper` style · scaffold file `scaffold.sh`
MODULE     `plugins/flow/evals/` · data · seam: eval cases
CALLS      none; cases are declarative. `claude plugin eval plugins/flow --case <glob> --trust-plugin --no-publish --scaffold --allow-tools Write Edit` must load every case with zero load errors.
DUPLICATE  one `scaffold.sh` per case, no shared fixture library; grader patterns as YAML literals.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for this slice — Slice 5: `flow eval` and the loop contract
CONTRACT   `plugins/flow/bin/lib/eval/contract.js` — this slice CREATES it exactly as section 1 declares, then imports it.
NAMES      `flow eval` · `evalModel` / `evalJudgeModel` · `ledger.jsonl` · `EXIT = {ok:0, fail:1, partial:2}` · doctor check id `eval-ready`
MODULE     `plugins/flow/bin/lib/eval.js`, `plugins/flow/bin/lib/eval/contract.js`, `plugins/flow/bin/flow` (dispatch + help + doctor row), `plugins/flow/bin/lib/loop/init.js` (`--test-files` accepted) · layer 1 · may import: node:*, ./eval/contract.js, ./loop/util.js · seam: eval runner
CALLS      `run(argv, cwd, env) -> number` · `parseAggregate(text) -> {ok, data|error}` · `readConfigKey(toplevel, key) -> string` · `ledgerLine(fields)`
DUPLICATE  grading: none in Node. `resolveOnPath`, `headSha`: imported from `loop/util.js`.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.
