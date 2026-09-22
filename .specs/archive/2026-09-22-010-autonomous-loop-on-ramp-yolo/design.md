# design — Autonomous loop on-ramp (`--yolo`)

Seam: five tasks write or read the same loop contract front-matter and share one
"refuse to arm" exit-code contract. Everything below exists so two agents do not
build two incompatible halves of that. Spec §5's caps are cited, never hosted here.

## 1. Contract file and names

**Contract file**: `plugins/flow/bin/lib/loop/contract.js` — already the sole owner of the
front-matter. Import from it; do not declare a second one. A field you need that is not
there is an escalation to the orchestrator, never a local literal.

Front-matter invariant, read from the existing code: **every value is a string**, and
booleans are the strings `'1'` and `'0'` (see `finish_reported: '0'`, `unchanged: '0'`).
Keys are `snake_case`. New fields follow both rules without exception.

| canonical | identifier | plural | defined in | banned synonyms |
|---|---|---|---|---|
| negative control | `negControl` / `neg_control_*` | — | `negcontrol.js` | sanity check, smoke test, canary, mutation |
| induced break | `inducedBreak` | — | `negcontrol.js` | mutation, fault, sabotage, poison |
| verdict | `verdict` | verdicts | `negcontrol.js` | result, outcome, status |
| yolo run | `yolo` / `front.yolo` | — | `contract.js` | unattended, auto, headless, autonomous |
| fail-closed | `failClosed` / `front.fail_closed` | — | `contract.js` | strict, hard-fail, fatal |
| refusal | `refuse*` | refusals | `init.js` | abort, bail, reject |

New front-matter fields, exact spelling, all strings, all written in `buildInitFront`:

```
yolo             '1' | '0'     this run was armed by the --yolo bootstrap
fail_closed      '1' | '0'     a tamper finding stops the run instead of labelling it
neg_control_file <repo-relative path> | ''   the file the induced break edited
neg_control_at   <ISO-8601 UTC> | ''         when the control last passed
```

`--yolo` implies `fail_closed: '1'`. No other field changes meaning.

## 2. Trust boundaries

| boundary | untrusted input shape | parse fn | failure granularity |
|---|---|---|---|
| the operator's idea string | free text, any length | the skill, before any file is written | refuse to arm, exit 3 |
| the composed verifier string | free text becoming `sh -c` | `runVerify` (existing) | refuse to arm, exit 3 |
| the repo working tree at arm time | may be dirty, may be mid-rebase | `negcontrol.js` preflight | refuse to arm, exit 3 |
| the tree after an induced break | may be partially restored | checksum compare in `negcontrol.js` | exit 5, the loudest case |

The tree is untrusted input. `negcontrol.js` treats "clean before" as a precondition it
verifies, never as something it assumes.

## 3. Error taxonomy — `cmdInit` exit codes

One closed set. `cmdInit` returns these numbers and nothing else; every one writes a
one-line reason to stderr naming the field or file responsible.

```
0  armed
1  usage or an existing active loop          (unchanged, existing behaviour)
3  an input could not be composed            (no goal, no verifier, no task list, dirty tree)
4  the verifier survived the induced break   — refuse to arm
5  the tree could not be restored            — refuse to arm, and say a human must look
6  the negative control exceeded its bound   — refuse to arm
```

Exit 5 is the only one that may leave the tree modified, and it must say so explicitly.
Adding a code is an escalation.

## 4. Module boundaries

```
contract.js   layer 0 · may import: node builtins · exports: readContract, writeContract,
                                    corruptReason, contractPath, serializeContract
negcontrol.js layer 1 · may import: contract.js, verify.js, node builtins
                      · exports: runNegControl(toplevel, opts) -> {verdict, file, restored, ms}
init.js       layer 2 · may import: contract.js, verify.js, negcontrol.js, tamper.js
tick.js       layer 2 · may import: contract.js, verify.js, tamper.js
driver.js     layer 2 · may import: contract.js, tick.js
```

Anything not listed is a bug. `negcontrol.js` never writes the contract; `init.js` owns
that, and writes it only after the control returns a passing verdict. Nothing half-armed
is the whole point of that ordering.

## 5. Shared resources

| resource | constructed by | passed how | received by |
|---|---|---|---|
| `toplevel` (repo root) | `cli.js` | first positional argument | every layer-1 and layer-2 function |
| the contract file | `init.js` only | never passed; read via `readContract` | tick, driver, status, router |
| `env` for verifier runs | `cli.js` | explicit parameter | `runVerify`, `runNegControl` |
| git | the shell | `spawnSync('git', ['-C', toplevel, …])` | negcontrol, init |

`runNegControl` constructs nothing it was not handed. An agent told nothing constructs its
own git invocation with the wrong working directory; the `-C toplevel` form is mandatory.

## 6. Deliberately duplicated

- **Do not consolidate `runVerify` and `runNegControl`.** The control calls the verifier
  twice with an edit in between; folding that into the verifier would make the verifier
  stateful, which is the one property it must never have.
- **Do not consolidate the four refusal paths into one helper.** Each carries a different
  exit code and a different remedy sentence; a shared helper reliably collapses them to one.
- **Do not reuse the tamper checksum machinery for the tree-restore check.** Tamper answers
  "did the test layer get weaker since base"; restore answers "are these bytes identical to
  ninety seconds ago". Same tool, different question, different failure meaning.

## 7. Decisions

- In the context of the negative control, facing the fact that an interrupted run must never
  leave a wrecked tree, we chose a **single-file edit reverted by `git checkout -- <file>`**
  and rejected `git stash` and multi-file mutation, to achieve a recovery that is one command
  and cannot partially apply, accepting that a verifier blind to that one file passes a control
  it should fail (spec §7 A1). *Makes hard:* verifying features whose first task touches no
  tracked file — that case must exit 3 rather than silently skip. Touches `negcontrol.js`.
- In the context of arming, facing the requirement that nothing be half-armed, we chose to run
  the control **before `writeContract`** and rejected writing a contract in a `pending` status,
  to achieve "no contract file means no run", accepting one extra verifier run before anything
  is persisted. *Makes hard:* resuming a failed bootstrap. Touches `init.js`.
- In the context of tamper handling, facing an operator who is not present, we chose a
  **contract field read at tick time** and rejected a command-line flag on `run`, to achieve a
  setting that survives a crash and a resume, accepting a new front-matter field.
  *Makes hard:* changing the policy mid-run. Touches `contract.js`, `tick.js`.

## Complexity Tracking

| Violation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| a new module (`negcontrol.js`) rather than a function in `init.js` | `init.js` is already the largest file in the directory and the control is independently testable | inlining it makes the control unreachable from a test without arming a real loop |

---

## Contract for T001 — reject an unreadable start time as corrupt
CONTRACT   `plugins/flow/bin/lib/loop/contract.js` — extend `corruptReason(front)`. Import nothing new.
NAMES      `started_at` (existing key, ISO-8601 UTC string). Not `startedAt`, not `start_time`.
MODULE     `contract.js` · layer 0 · may import: node builtins · exports: unchanged plus no new names
CALLS      `corruptReason(front) -> string | null`. Return the reason string in the existing
           shape: `` `started_at is not a parseable timestamp: '${front.started_at}'` ``
DUPLICATE  §6 bullet 3 — do not route this through the tamper checksum machinery.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for T002 — the router explains an active loop
CONTRACT   `plugins/flow/bin/lib/loop/contract.js` — read the contract with `readContract`; do not parse the file.
NAMES      `goal`, `iteration`, `max_iterations`, `slug` (existing keys, all strings).
MODULE     `plugins/flow/bin/flow` · the `loop-active` branch only · exports: unchanged
CALLS      the branch's returned object must carry a non-empty `why`. Keep `state` and `command` as they are.
DUPLICATE  §6 bullet 2 — this is not a refusal path; do not reuse a refusal helper.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for T003 — the negative control
CONTRACT   `plugins/flow/bin/lib/loop/contract.js` for field names; `verify.js` for `runVerify`.
NAMES      `negControl`, `inducedBreak`, `verdict`, `restored`. Banned: sanity check, canary, mutation, sabotage.
MODULE     `negcontrol.js` · layer 1 · may import: contract.js, verify.js, node builtins
           · exports: `runNegControl(toplevel, opts) -> { verdict, file, restored, ms }`
CALLS      `opts = { verify, verifyTimeout, file, env }`. `verdict` is one of the literals
           `'red-then-restored'`, `'survived'`, `'not-restored'`, `'timeout'`.
           Map to exit codes per §3: survived → 4, not-restored → 5, timeout → 6.
           Time bound: `2 * verifyTimeout` seconds (spec §5), measured across the whole call.
DUPLICATE  §6 bullets 1 and 3 — never fold this into `runVerify`, never reuse the tamper checksums.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for T004 — `--yolo` caps and child arguments
CONTRACT   `plugins/flow/bin/lib/loop/contract.js` — the caps are existing keys.
NAMES      `max_minutes`, `max_usd`, `max_iterations`, `stall_after`, `yolo` — all strings.
MODULE     `init.js` (defaults) and `driver.js` (child argv) · layer 2
CALLS      `--yolo` sets the spec §5 defaults only when the operator passed no explicit cap.
           The child argv must contain `--permission-prompts none`; `--max-budget-usd` only when --max-usd is set.
DUPLICATE  §6 bullet 2 — the cap-refusal path keeps its own message.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for T005 — fail-closed tamper
CONTRACT   `plugins/flow/bin/lib/loop/contract.js` — read `fail_closed` via `readContract`.
NAMES      `fail_closed` (string `'1'` | `'0'`), `failClosed` for the local. Banned: strict, fatal, hard-fail.
MODULE     `tick.js` · layer 2 · may import: contract.js, verify.js, tamper.js
CALLS      when `front.fail_closed === '1'` and `tamper` returns any finding, stop the run with the
           existing stop machinery and the tamper reason. Do not invent a new stop reason string.
DUPLICATE  §6 bullet 3 — the tamper checksums answer their own question; do not extend them here.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.
