# Panel adjudication — harness SPEC

Adjudicator pass over seven lens reports. Lenses over-report by design; what follows is the
binding disposition. Lens keys: **DU** daily-usefulness, **MP** missing-pieces, **VG**
vendor-guidance, **MC** model-compliance, **PT** portability, **SP** spec, **FC** friction-and-cost.

Rules applied: only fatal/significant findings may force a CHANGE; improvable findings become a
CHANGE only when the fix is ≤3 lines of spec; cosmetic findings are logged and left alone.
Contested severities are decided, not averaged — the reasoning is in the row.

---

## 1. Findings register

| # | Finding | Lenses | Severity | Decision | Exact change |
|---|---|---|---|---|---|
| 1 | `rtk-rewrite.sh` is wired first in every `PreToolUse`/Bash call although `rtk` is absent on both machines; the SPEC's own cited research says delete it three times | VG#1, FC-I2 | **significant** | **CHANGE** | Spec edit 1 (C5 PreToolUse), edit 2 (repo facts line 12) |
| 2 | C10 orders `rtk-fast.sh` to be made portable with `stat -c %Y` / `stat -f %m`, but the Oracle's banned-token grep forbids both literals — U1 cannot satisfy both; the only escapes are BLOCKED or token obfuscation that defeats the grep | PT-F1 | **fatal** | **CHANGE** | Spec edit 3 (C10 rtk bullet) + edit 4 (U1 ownership). Resolved by removing the file from scope entirely rather than by adding a `# portable-ok` carve-out — a `stat` helper nothing else needs is not worth an exemption in the one grep that protects every other file |
| 3 | `rtk-fast.sh` keeps hardcoded `/Users/tomas/...` cache path; "keep behavior otherwise" forbids fixing it | PT-S1 | significant | **CHANGE** | Subsumed by edit 3 — the file is no longer edited, wired, or tested by this work |
| 4 | `stop-gate.sh` runs the **full** `check-all` (typecheck→lint→format→test) on every Stop with any changed file; on the harness's own primary workflow (iterative multi-turn slices) this adds the full suite's runtime to every turn, and the only escape is disabling the gate entirely | FC-F1 (fatal), DU-F2 | **significant** | **CHANGE** | Spec edit 7. Downgraded from FC's "fatal": the gate is not *wrong*, it is *unscoped*, and the fix is a scoping change inside the mechanism the SPEC already has. But FC is right that the shipped default decides whether this harness survives week one, so the default flips to scoped |
| 5 | `check-all --continue` worst case (4 gates × 120s spawn timeout = 480s) exceeds `stop-gate.sh`'s 300s hook timeout — the gate can be killed mid-run with no defined outcome | FC-F2 | **significant** | **CHANGE** | Spec edit 5 (timeout 300→600) + edit 7 (drop `--continue`, fail-fast) |
| 6 | Repo with one pre-existing red test wedges every Stop forever; no baseline, and the two escapes the gate names are the two things it forbids | FC-S1 | significant | **CHANGE** | Spec edit 7 — same-signature block cap (3), then advisory. Rejected FC's checkwash-style fingerprinted-exemption proposal: it needs a package install, banned by SPEC line 27 |
| 7 | Turn stamp is forgeable (documented path, `touch` it and every edited file is "older"); and a delete-only turn produces no newer file, so the gate silently never runs | MC#2, SP#5 | **significant** | **CHANGE** | Spec edit 6 (C3) — union the mtime scan with `git status --porcelain` always, not only when the stamp is missing. One line, closes both |
| 8 | `size_guard.py`'s signature heuristic misreads a multi-line JSX `return (` as a 74-line function named `'return'`, and the 400-line file cap fires on flat data tables — both **executed**, not theorised | FC-S2, FC-S3, DU-F4, MC#6 | **significant** (strongest receipt in the panel) | **CHANGE** | Spec edit 9 — exclude control-flow keywords from the signature regex, require a declared name, and ship `harness init` with data-shaped `ignore` defaults; both false positives become required U2 tests |
| 9 | The harness's highest-value invariant ("do not delete, skip, xfail, or weaken a test, do not lower a threshold") is a printed sentence with zero deterministic detector | MP#1 (significant), MC#8 (cosmetic, "accepted ceiling") | **significant** | **CHANGE** | Spec edit 11 — new `tamper-notice.sh`. MP wins the contest: MC's "accepted ceiling" reasoning is that checkwash needs a PyPI install, which is true of *checkwash*, not of the mechanism. A `git diff` grep for newly-added skip markers is zero-dependency, fits U2's existing ownership, and uses machinery the SPEC already has. MC's own finding #4 (silent `harness.json` loosening) is the same hole from the other side and is closed by the same hook |
| 10 | `.claude/harness.json` is freely and silently editable by the agent it constrains; nothing logs or surfaces a loosened threshold | MC#4 | significant | **CHANGE** | Spec edit 11 (config half of `tamper-notice.sh`) + edit 12 (`session-context.sh` prints active overrides) + edit 15 (doctor WARN). Visibility, not prohibition — the escape hatch is legitimate |
| 11 | `sizeGuard` config key is declared in C4 and wired to nothing; writing `"sizeGuard": false` has no effect | SP#2 | **significant** (confirmed) | **CHANGE** | Spec edit 8 |
| 12 | PreCompact backup retention is broken by its own filename order: `<session_id>_<trigger>_<epoch>` name-sorts by opaque session id, so "delete oldest by name sort" deletes an arbitrary file | SP#3 | **significant** (confirmed by execution) | **CHANGE** | Spec edit 13 — reorder to `<epoch>_<session_id>_<trigger>.jsonl` |
| 13 | Unit map's Depends-on omits U4→U3 (fixture) and U5→U4 (`skills-lint`, already a live symlink target) — the exact unowned-interface failure the parallel fan-out is built to avoid | SP#4 | **significant** | **CHANGE** | Spec edit 14 |
| 14 | Banned-token list has real holes: `mktemp -p`/`--tmpdir`, `sed -r`, `xargs -r` are all GNU-only, all natural first choices on the only box that is ever executed against | PT-S2 | **significant** | **CHANGE** | Spec edit 16 |
| 15 | `format-lint.sh` chains `eslint --fix` synchronously after prettier on every single Edit/Write: multi-second on type-aware TS configs, and it flags legitimately-incomplete intermediate states (unused export in file A before file B wires it) | DU-F3 (significant), FC-I1 (improvable) | **significant** | **CHANGE** | Spec edit 10 — formatters stay on the per-edit path (measured 70–230ms), `eslint --fix` moves to the once-per-turn stop-gate lint step. DU's severity wins: FC graded it improvable only because it could not build a type-aware project in-sandbox, not because the effect is small |
| 16 | DONE criteria (line 22) still lists "shellcheck is clean" unconditionally although line 20 now correctly states shellcheck is **not** installed on this box | SP#1, PT-C1 | improvable (SP's "significant" was against a stale SPEC revision — line 20 already carries the correction) | **CHANGE** (2 lines) | Spec edit 17 |
| 17 | `harness doctor` verifies hook files are present+executable, never that content matches the git-tracked source | MC#7 | improvable | **CHANGE** (1 line) — cheap because stow symlinks make this `git diff --quiet -- claude/.claude/hooks` | Spec edit 15 |
| 18 | Complexity backstop (`.harness/*.thresholds.*`) is written but never spliced into the real lint config, so nothing in the harness ever measures complexity — only gameable line counts | MC#6 (second half) | improvable | **CHANGE** (1 line) | Spec edit 15 — doctor WARNs when a thresholds file exists but the real config does not reference it. Rejected the auto-merge variant: editing a user's eslint config is exactly what C9 forbids, and for good reason |
| 19 | git-guard's "not a security boundary" caveat present in the research did not survive into the frozen C10 text | MC#5 (improvable), DU-F8 (cosmetic, explicitly not raised as a defect) | improvable | **CHANGE** (1 line) | Spec edit 18 |
| 20 | `--force-with-lease` is correctly *allowed* in C10 prose but *denied* by the reference regex a builder will copy from SYNTHESIS §5; nothing in the Oracle forces a test on this string | FC-S4 | significant | **CHANGE** | Spec edit 18 — named required test cases in U1 |
| 21 | Stray `?` inside a frozen security-relevant pattern list: "`git restore --staged .`**?** (only `git restore .`)" | SP#10 | cosmetic | **CHANGE** (folded into edit 18, free) | — |
| 22 | Fence-awareness is required of `slice-brief` but not of `plan-lint`/`slice-overlap`, which parse the same grammar | SP#7 | improvable | **CHANGE** (1 line) | Spec edit 19 |
| 23 | C7 never defines the Behavior Inventory's internal structure, yet `plan-lint` must check "at least one table row" | SP#8 | improvable | **CHANGE** (2 lines) | Spec edit 19 |
| 24 | `harness init --stack auto` has no specified behavior and no test when `detect-project` finds no ecosystem | SP#9 | improvable | **CHANGE** (1 line) | Spec edit 15 |
| 25 | U5's four template files' content is deferred to an unseen "unit packet", and `CLAUDE.project.md` is not bound to the vendor's own CLAUDE.md size guidance | SP#6, VG#3 | improvable | **CHANGE** (2 lines) | Spec edit 15 — bind the constraints inline so U5 is buildable from the SPEC alone |
| 26 | `skills-lint` silently loses detection power on macOS's case-insensitive APFS — wrong-case references resolve and are never reported, on the machine where doctor matters most | PT-I1 | improvable | **CHANGE** (1 line) | Spec edit 19 |
| 27 | "no ecosystem detected → stop-gate exit 0" is a documented pass; deleting the manifest converts a red turn into a silent green one | MC#3 | improvable (MC graded significant; the exploit is adversarial and the honest non-adversarial case — a genuinely manifest-less repo — is the common one) | **CHANGE** (2 lines) | Spec edit 7 — block when a manifest file is deleted or renamed in this turn's `git status` |
| 28 | `format-lint`/`size-guard` never fire on files written through Bash heredocs (`cat > f <<EOF`), and nothing downstream re-checks them | MC#1 | improvable | **CHANGE** (1 line documenting the limit) + **DEFER-TO-WAVE-2** for closure | Spec edit 18. Closing it properly means re-running size-guard at Stop over the changed set — which, given finding 8's confirmed false positives, would turn advisory noise into turn-blocking noise. Fix the heuristic first (edit 9), close the bypass in wave 2 |
| 29 | U3/U4's five scripts have no caller: the SPEC forbids editing `skills/flow/*`, so `/flow` still computes its own numbering and pastes contracts by prose. Day-one usage is zero | DU-F1 (significant, "largest theatre cluster", proposes DROP), MP#4 (cosmetic, "correctly-drawn phase boundary"), MP#2 (plan-lint uninvoked) | **significant as an honesty defect in the Objective; improvable as a code decision** | **CHANGE the Objective wording; KEEP the units; DEFER the wiring** | Spec edit 20. DU is right that the Objective's "a `scripts/` toolbox that owns numbering, slice briefs, review packages" reads as though the toolbox becomes load-bearing on merge, and it does not. DU is wrong to propose dropping the scripts: U7 (flow-v2) is already in the wave-2 table and cannot be built without them, and `skills-lint` has standalone value today. The correct fix is truth in the Objective plus a named wave-2 owner, not deletion |
| 30 | The single highest-leverage item in the whole research corpus (skill index ≈44,250 description chars over the listing budget) is out of scope for every unit | DU-F6, VG#2 | improvable | **KEEP-AS-IS** (already assigned to U8) + 1-line qualification | Spec edit 21. VG's premise check missed that U8 already names `skillListingBudgetFraction`; the qualification makes explicit that raising the fraction is not a substitute for cutting the index — VG's substantive point, and correct |
| 31 | Frozen-intent hash (S12) has no home and is not named as a follow-up | MP#3 | improvable | **DEFER-TO-WAVE-2** | Spec edit 21 (wave-2 table row) |
| 32 | Hook subprocess PATH under a macOS GUI launch can silently hide every formatter; doctor checks its own PATH, not the hook's, so "doctor all PASS / hooks all no-op" has no diagnostic surface | PT-I3 | improvable (fix needs a real probe mechanism, >3 lines) | **DEFER-TO-WAVE-2** | — |
| 33 | `plan-lint` exists but nothing invokes it automatically; the plan stays self-graded in wave 1 | MP#2 | improvable | **DEFER-TO-WAVE-2** (belongs with U7's flow wiring; wiring it into stop-gate now would gate every turn on a file only a future flow produces) | — |
| 34 | `${TMPDIR:-/tmp}/...` yields a double slash on macOS (TMPDIR always ends in `/`) | PT-I2 | cosmetic | **KEEP-AS-IS** — functionally inert for `touch`/`find -newer`/`mktemp`; logged | — |
| 35 | `harness init` collides conceptually with the existing `new-project` scaffolder | DU-F7 | cosmetic | **KEEP-AS-IS** — different jobs (scaffold a repo vs. add governance to one); logged | — |
| 36 | `harness check` / `harness skills-lint` are thin pass-throughs; DU proposes dropping them | DU (drop-list #4) | cosmetic | **KEEP-AS-IS** — ~5 lines of exec passthrough each, and a single `harness` entry point is worth more than the surface it costs. Proposal declined | — |
| 37 | Inline lint-suppression (`// eslint-disable-next-line`, `# noqa`) is discouraged in prose with no detector | MC#8 | cosmetic | **KEEP-AS-IS** — logged as the honest ceiling of a deterministic, zero-install harness. Partially mitigated by finding 9's hook, which sees the same class of diff | — |
| 38 | C1/C5/C10 hook-protocol semantics (exit codes per event, matcher support per event, `stop_hook_active` + 8-block cap, SessionStart-with-no-matcher, PreToolUse deny JSON) verified line-by-line against the PRIMARY vendor-doc cache | VG (§1, no defect) | — | **KEEP-AS-IS** — credited, not changed. Notably C5's single-entry SessionStart is *leaner* than SYNTHESIS's own two-entry proposal and equally correct | — |

Nothing in the register is dispositioned DROP as a deliverable. The two things that get dropped are
*work items*: the `rtk-fast.sh` port (findings 2, 3) and the `rtk-rewrite.sh` wiring (finding 1).

---

## 2. Spec edits

Apply in order. SPEC structure (Objective / Repository facts / Oracle / Out of scope / C1–C10 /
Unit map / Rules / Wave 2) is preserved throughout.

### Edit 1 — C5, drop `rtk-rewrite.sh` from the PreToolUse chain
**Old** (SPEC.md:74–75):
```
  "PreToolUse":       [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/rtk-rewrite.sh", "timeout": 10 },
                                                          { "type": "command", "command": "$HOME/.claude/hooks/git-guard.sh", "timeout": 10 } ] } ],
```
**New:**
```
  "PreToolUse":       [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/git-guard.sh", "timeout": 10 } ] } ],
```

### Edit 2 — Repository facts, state the rtk files' status plainly
**Old** (SPEC.md:12):
> - Existing hooks dir `claude/.claude/hooks/` contains `rtk-fast.sh` and `rtk-rewrite.sh` (RTK token-saving proxy; installed on the Mac only). Keep both files; do not delete.

**New:**
> - Existing hooks dir `claude/.claude/hooks/` contains `rtk-fast.sh` and `rtk-rewrite.sh` (RTK token-saving proxy; `rtk` is not installed on either machine today — verified `command -v rtk` → exit 1 on this box). Keep both files on disk; do **not** delete them, do **not** edit them, do **not** wire them into `settings.json`, and do **not** write tests for them. They are outside every unit's ownership. If RTK is ever installed on the Mac, wiring it back is a one-line settings change made by hand.

### Edit 3 — C10, remove the self-contradicting rtk-fast.sh port
**Old** (SPEC.md:121):
> - `rtk-fast.sh`: make portable — replace `stat -f %m` with a function that tries `stat -c %Y` then `stat -f %m`; keep behavior otherwise. `rtk-rewrite.sh`: already guarded; only change if shellcheck demands.

**New:**
> - `rtk-fast.sh` / `rtk-rewrite.sh`: **not in scope.** No unit edits, wires, or tests them (see Repository facts). Note for the Oracle: the portability grep in `hooks/tests/run.sh` must therefore exclude `rtk-*.sh` from the banned-token scan — those two files already contain `stat -f` and are exempt as unowned legacy, not as `# portable-ok` lines.

### Edit 4 — Unit map, U1 loses rtk-fast.sh
**Old** (SPEC.md:127, "Owns" cell of U1):
> `hooks/session-context.sh`, `hooks/turn-stamp.sh`, `hooks/git-guard.sh`, `hooks/pre-compact-backup.sh`, `hooks/rtk-fast.sh` (edit), `hooks/tests/test_core.sh`

**New:**
> `hooks/session-context.sh`, `hooks/turn-stamp.sh`, `hooks/git-guard.sh`, `hooks/pre-compact-backup.sh`, `hooks/tests/test_core.sh`

And U2's "Owns" cell (SPEC.md:128) gains `hooks/tamper-notice.sh`:
> `hooks/format-lint.sh`, `hooks/size-guard.sh`, `hooks/size_guard.py`, `hooks/stop-gate.sh`, `hooks/tamper-notice.sh`, `hooks/tests/test_quality.sh`

### Edit 5 — C5, stop-gate timeout and the new PostToolUse hook
**Old** (SPEC.md:76–78):
```
  "PostToolUse":      [ { "matcher": "Edit|Write|NotebookEdit", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/format-lint.sh", "timeout": 60 },
                                                                            { "type": "command", "command": "$HOME/.claude/hooks/size-guard.sh", "timeout": 20 } ] } ],
  "Stop":             [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/stop-gate.sh", "timeout": 300 } ] } ],
```
**New:**
```
  "PostToolUse":      [ { "matcher": "Edit|Write|NotebookEdit", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/format-lint.sh", "timeout": 60 },
                                                                            { "type": "command", "command": "$HOME/.claude/hooks/size-guard.sh", "timeout": 20 },
                                                                            { "type": "command", "command": "$HOME/.claude/hooks/tamper-notice.sh", "timeout": 10 } ] } ],
  "Stop":             [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/stop-gate.sh", "timeout": 600 } ] } ],
```
(600 > `check-all`'s own worst case of 4 gates × 120s, so the gate can always deliver a verdict.)

### Edit 6 — C3, the changed-set is a union, never the stamp alone
**Old** (SPEC.md:60):
> `hooks/turn-stamp.sh` (UserPromptSubmit) touches `$(hook_stamp_path)` and exits 0 with no stdout. `hooks/stop-gate.sh` treats files under the project dir newer than the stamp (excluding `.git/`, `node_modules/`, `.venv/`, `target/`, `dist/`) as "changed this turn"; if none, exit 0 without running gates. If the stamp is absent, fall back to `git status --porcelain` non-empty.

**New:**
> `hooks/turn-stamp.sh` (UserPromptSubmit) touches `$(hook_stamp_path)` and exits 0 with no stdout. `hooks/stop-gate.sh`'s "changed this turn" set is the **union** of (a) files under the project dir newer than the stamp (excluding `.git/`, `node_modules/`, `.venv/`, `target/`, `dist/`) and (b) every path reported by `git status --porcelain`. It exits 0 without running gates only when **both** are empty. The stamp is an optimisation, never the sole authority: (b) covers deletions, files written through Bash heredocs, and a stamp that has been re-touched later than the edits it was meant to precede.

### Edit 7 — C10, rewrite the `stop-gate.sh` bullet
**Old** (SPEC.md:119):
> - `stop-gate.sh` (Stop): exit 0 immediately if `stop_hook_active` is true, or `CC_NO_STOP_GATE=1`, or `.claude/harness.json` has `stopGate:false`, or not a git repo, or no files changed this turn (C3), or `check-all` is absent. Run `CI=true check-all --continue --json`; on exit ≠ 0 print Stop block JSON (C1) whose reason contains the failed gate names, up to 40 lines of their output, and the fixed sentence: "Do not delete, skip, xfail, or weaken a test to make this pass, and do not lower a threshold in config. If a check is genuinely inapplicable here, say so explicitly and stop." When check-all reports no ecosystem, exit 0.

**New:**
> - `stop-gate.sh` (Stop): exit 0 immediately if `stop_hook_active` is true, or `CC_NO_STOP_GATE=1`, or `.claude/harness.json` has `stopGate:false`, or not a git repo, or nothing changed this turn (C3), or both `check-all` and `test-changed` are absent.
>   **Scope.** `stopGate` (C4) takes `"scoped"` (default when the key is absent), `true`, or `false`.
>   - `"scoped"`: run `CI=true test-changed --json` and block when it reports `passed:false`. Additionally run the full sweep (below) when the scoped run is green **and** `date +%s` minus the epoch in `${TMPDIR:-/tmp}/claude-gates-<repo-basename>-<8-char-toplevel-hash>` exceeds `stopGateFullEverySec` (C4 default 900); rewrite that stamp with the current epoch after every full sweep. Fall through to the full sweep when `test-changed` is absent or reports no test command.
>   - `true`: full sweep every turn. `false`: off.
>   **Full sweep.** `CI=true check-all --json` — **without** `--continue`, so it stops at the first red gate (that is all the agent needs, and it bounds the worst case well inside the 600s hook timeout).
>   **Blocking.** On failure print Stop block JSON (C1) whose reason contains the failed gate names, up to 40 lines of their output, and the fixed sentence: "Do not delete, skip, xfail, or weaken a test to make this pass, and do not lower a threshold in config. If a check is genuinely inapplicable here, say so explicitly and stop."
>   **Wedge valve.** Append the failed-gate-name signature to `${TMPDIR:-/tmp}/claude-gatesig-<session_id>`. When that identical signature has already blocked 3 times in this session, do not block a fourth time: exit 2 instead, with the same text plus "these gates were already failing before this turn's edits; fix them or say why they are out of scope." A repo carrying one known-red test degrades to loud advisory rather than deadlocking every turn until the 8-block cap fires.
>   **No-ecosystem.** When `check-all` reports no ecosystem, exit 0 — **unless** this turn's `git status --porcelain` shows a deleted or renamed `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or `deno.json`, in which case block with "the project manifest disappeared this turn; a gate cannot be passed by removing the thing that defines it."

### Edit 8 — C4, wire `sizeGuard`, add the new keys, document the values
**Old** (SPEC.md:63–67):
```json
{ "maxFileLines": 400, "maxFuncLines": 60, "stopGate": true, "sizeGuard": true, "formatOnEdit": true,
  "ignore": ["migrations/", "generated/"] }
```
> `stopGate: false` disables stop-gate.sh for that repo. `ignore` entries are path substrings skipped by size-guard and format-lint. Environment overrides for one session: `CC_MAX_FILE_LINES`, `CC_MAX_FUNC_LINES`, `CC_NO_STOP_GATE=1`.

**New:**
```json
{ "maxFileLines": 400, "maxFuncLines": 60, "stopGate": "scoped", "stopGateFullEverySec": 900,
  "sizeGuard": true, "formatOnEdit": true,
  "ignore": ["migrations/", "generated/", "locales/", "i18n/", "**/*.generated.*"] }
```
> `stopGate` is `"scoped"` (default when absent), `true` (full sweep every turn), or `false` (off) — see C10. `stopGateFullEverySec` is the minimum gap between full sweeps in scoped mode. `sizeGuard: false` makes `size-guard.sh` exit 0 without running, exactly as `formatOnEdit: false` does for `format-lint.sh`. `ignore` entries are path substrings skipped by size-guard and format-lint. Environment overrides for one session: `CC_MAX_FILE_LINES`, `CC_MAX_FUNC_LINES`, `CC_NO_STOP_GATE=1`, `CC_NO_SIZE_GUARD=1`.

### Edit 9 — C10, fix `size_guard.py`'s two confirmed false positives
**Old** (SPEC.md:118, from "`size_guard.py <file> <maxFile> <maxFunc>` counts"):
> `size_guard.py <file> <maxFile> <maxFunc>` counts lines and function spans (heuristic: a signature regex for `def|fn|func|function|method-like`, closed at the next line with indentation ≤ the signature's that is not blank/comment)

**New:**
> `size_guard.py <file> <maxFile> <maxFunc>` counts lines and function spans (heuristic: a signature regex for `def|fn|func|function|method-like`, closed at the next line with indentation ≤ the signature's that is not blank/comment). The signature regex **must not** match a line whose first token is a control-flow keyword (`return`, `if`, `else`, `for`, `while`, `switch`, `case`, `catch`, `try`, `with`, `match`) and **must** capture a declared identifier — a bare `return (` opening a multi-line JSX block is not a function. Two cases are required tests in U2, both confirmed false positives of the naive heuristic: (1) an idiomatic ~110-line React component with a multi-line `return (` JSX block reports **no** function-span problem; (2) a >400-line flat data table (e.g. a `Record<string,string>` of country codes) under a path matched by the C4 `ignore` defaults reports nothing.

### Edit 10 — C10, take type-aware eslint off the per-edit path
**Old** (SPEC.md:117, mid-bullet):
> else prettier (`.prettierrc*`/`prettier.config.*` present or `prettier` in package.json) `prettier --write <file>`, then eslint if an eslint config exists `eslint --fix <file>`;

**New:**
> else prettier (`.prettierrc*`/`prettier.config.*` present or `prettier` in package.json) `prettier --write <file>`. **Do not run `eslint --fix` on the per-edit path** — it costs seconds per invocation on type-aware configs (`parserOptions.project`/`projectService` rebuild the TS program per process) and it flags legitimately-incomplete intermediate states, e.g. an export added in file A before file B consumes it. Lint runs once per turn as part of stop-gate's `check-all` lint gate instead. `format-lint.sh` runs formatters only;

### Edit 11 — C10, add `tamper-notice.sh` (new bullet, after `size-guard.sh`)
**New bullet:**
> - `tamper-notice.sh` (PostToolUse/Edit|Write|NotebookEdit): read `tool_input.file_path`; exit 0 unless it is a test file (`*_test.*`, `*.test.*`, `*.spec.*`, or under `tests/`/`__tests__/`) or a gate-config file (`.claude/harness.json`, `eslint.config.*`, `.eslintrc*`, `pyproject.toml`, `ruff.toml`, `clippy.toml`, `.golangci.yml`). Exit 0 if not a git repo or `git` is missing. Run `git diff HEAD -- <file>`; examine added lines only (`^+`, excluding `^+++`). For a test file, match `\.skip\(|\.only\(|it\.todo\(|xfail|@pytest\.mark\.skip|#\[ignore\]|t\.Skip\(`. For a gate-config file, match `stopGate\s*[":]\s*false` or an added line changing a numeric value of a key matching `max[-_A-Za-z]*|complexity|threshold` whose counterpart appears in a removed line. On a match, print to stderr the file, the matching added lines, and: "You just disabled or weakened a check. If that is intentional and correct, state which check and why in your reply; otherwise revert it." and exit 2 (PostToolUse exit 2 is feedback shown to Claude, not a block — the write already happened, which is the point: the loosening is now on the record). No match → exit 0. This is the deterministic half of the invariant whose other half is stop-gate's printed sentence; it is a detector, not a prohibition.

### Edit 12 — C10, surface active config overrides at session start
**Old** (SPEC.md:114, end of the `session-context.sh` bullet):
> then `note: REVIEW.md present` if it exists. Exit 0.

**New:**
> then `note: REVIEW.md present` if it exists, then one line per `.claude/harness.json` field whose value differs from the C4 default, as `note: harness override: <key>=<value>`. Exit 0.

### Edit 13 — C10, fix PreCompact retention ordering
**Old** (SPEC.md:120):
> - `pre-compact-backup.sh` (PreCompact): copy `transcript_path` to `$HOME/.claude/transcript-backups/<session_id>_<trigger>_<epoch>.jsonl` (mkdir -p; epoch via `date +%s`); keep at most 50 files (delete oldest by name sort); exit 0 always.

**New:**
> - `pre-compact-backup.sh` (PreCompact): copy `transcript_path` to `$HOME/.claude/transcript-backups/<epoch>_<session_id>_<trigger>.jsonl` (mkdir -p; epoch via `date +%s`, zero-padded to 10 digits). Epoch **leads** the filename so that a lexical name sort is a chronological sort — this is what makes "keep at most 50 files, delete oldest by name sort" correct without `stat -c`/`stat -f`, both of which are banned by the Oracle. Exit 0 always.

### Edit 14 — Unit map, declare the real cross-unit dependencies
**Old** (SPEC.md:130–131, "Depends on" cells):
> | U4 scripts-lint | … | U0 | may reuse U3's `fixtures/plan.md` read-only |
> | U5 harness-cli | … | U0 | … |

**New:**
> | U4 scripts-lint | … | U0, U3 | U3 owns `fixtures/plan.md`; U4 reads it but must not write it. If it is absent when U4 runs, U4 vendors its own minimal C7-conformant fixture under `fixtures/plan-good.md` rather than blocking |
> | U5 harness-cli | … | U0, U4 | `harness skills-lint` and `harness doctor` item (5) exec `~/.claude/scripts/skills-lint`, owned by U4 and already a live symlink target. U5's tests must assert the JSON, and skip (not fail) the skills-lint line when that script is absent |

### Edit 15 — C9, close the `harness doctor` / `harness init` gaps
**Old** (SPEC.md:107, doctor check (2)):
> (2) `settings.json` contains a `hooks` key with every hook file in C5 present and executable;

**New:**
> (2) `settings.json` contains a `hooks` key with every hook file in C5 present and executable, and — because stow makes the deployed hooks symlinks to the git-tracked source — WARN when `git -C ~/.dotfiles diff --quiet -- claude/.claude/hooks` reports drift, so a neutered hook cannot report PASS; also WARN once per repo when `.claude/harness.json` sets any field away from its C4 default (naming the field), and WARN when a `.harness/*.thresholds.*` file exists but the project's real lint config contains no reference to it (the complexity backstop is written but unwired);

**Old** (SPEC.md:108, end of the `harness init` bullet):
> Prints a summary table of created/skipped files. `--dry-run` prints what it would write.

**New:**
> When `detect-project` reports no recognised ecosystem, `harness init` still writes `REVIEW.md`, `PROGRESS.md` and `.claude/harness.json`, skips the CI workflow and the threshold file, and prints `no stack detected — governance files written, gates skipped`; U5's tests cover this case alongside the per-stack ones. Prints a summary table of created/skipped files. `--dry-run` prints what it would write.

**Old** (SPEC.md:111, last sentence):
> Template content is specified in the unit packet for U5.

**New:**
> Template content is specified in the unit packet for U5; if that packet is unavailable, U5 reports BLOCKED rather than inventing it. Binding constraints regardless of the packet: `CLAUDE.project.md` ≤ 40 lines (vendor guidance: a bloated CLAUDE.md causes Claude to ignore the instructions in it), `REVIEW.md` and `PROGRESS.md` ≤ 60 lines each, and `gates.yml.tmpl` must leave every command as a `{{PLACEHOLDER}}` rather than hardcoding a tool.

### Edit 16 — Oracle, close the banned-token holes
**Old** (SPEC.md:21, the token list):
> contains none of: `mapfile`, `readarray`, `declare -A`, `${var,,}`, `${var^^}`, `readlink -f`, `stat -c`, `stat -f`, `sed -i ` (without a temp-file pattern), `grep -P`, `date -d`, `date -v`, `timeout ` (GNU-only), `realpath`.

**New:**
> contains none of: `mapfile`, `readarray`, `declare -A`, `${var,,}`, `${var^^}`, `readlink -f`, `stat -c`, `stat -f`, `sed -i ` (without a temp-file pattern), `sed -r`, `grep -P`, `date -d`, `date -v`, `timeout ` (GNU-only), `realpath`, `xargs -r`, `mktemp -p`, `mktemp --tmpdir`.

### Edit 17 — Oracle, make the shellcheck DONE criterion conditional
**Old** (SPEC.md:22):
> - A unit is DONE when: its tests pass with real output shown, shellcheck is clean, the portability grep is clean, and both adversaries return no Fatal/Significant findings.

**New:**
> - A unit is DONE when: its tests pass with real output shown, the portability grep is clean, both adversaries return no Fatal/Significant findings, and shellcheck is clean **if it is installed** — it is not installed on this box, so a unit that cannot run it must say so explicitly in its report rather than claiming a clean run it never performed.

### Edit 18 — C10, git-guard: caveat, stray `?`, and required test strings
**Old** (SPEC.md:116, from "`git checkout -- .`"):
> `git checkout -- .`; `git restore .` or `git restore --staged .`? (only `git restore .`); `git branch -D`; … Deny reasons name the pattern and the safe alternative.

**New:**
> `git checkout -- .`; `git restore .` (bare only — `git restore --staged .` is not denied); `git branch -D`; … Deny reasons name the pattern and the safe alternative. **Required test cases in U1's `test_core.sh`, each named:** `git push --force origin main` → denied; `git push --force-with-lease origin main` → **allowed** (the naive regex `--force(-with-lease)?` denies it, which is the fastest way to teach a developer to disable this hook); `git push -f` → denied; `git commit -m "add force flag"` → allowed. **Required header comment in the shipped script:** "This is a regex blocklist over a command string. It raises the bar against an ordinary mistake; it is not a security boundary — `bash -c`, `eval`, variable construction, and a helper script written via Edit all evade it. CI is the real backstop." The same limit applies to `format-lint.sh`/`size-guard.sh`/`tamper-notice.sh`, which only see `Edit|Write|NotebookEdit`: a file written through a Bash heredoc is never checked by them. Closing that is a wave-2 item.

### Edit 19 — C7/C8, grammar definition, fence-awareness, case-sensitivity
**Old** (SPEC.md:94, C7 first bullet, end):
> Required top-level headings in order: `## Behavior Inventory`, one or more `## Slice <N> — <title>`, `## Gate Phases`.

**New:**
> Required top-level headings in order: `## Behavior Inventory`, one or more `## Slice <N> — <title>`, `## Gate Phases`. The Behavior Inventory section contains a GitHub-flavoured markdown table whose header row is `| Behavior | Slice | Verified by |` followed by a `|---|` separator and at least one data row; `plan-lint`'s "at least one Behavior Inventory table row" check means at least one line after the separator that starts and ends with `|`.

**Old** (SPEC.md:100, `slice-brief`, last sentence):
> Must be fence-aware: a `## Slice` line inside a ``` fence is not a heading.

**New:**
> Must be fence-aware: a `## Slice` line inside a ``` fence is not a heading. **Fence-awareness is a property of the C7 grammar, not of this one script — `slice-overlap` and `plan-lint` parse the same file and must segment it identically. U3 and U4 each carry a test asserting that a plan whose slice body contains a fenced block with a literal `## Slice 9 — decoy` line yields the same slice boundaries from all three tools.**

**Old** (SPEC.md:104, `skills-lint`, after "resolves each"):
> resolves each (relative ones against the containing skill's dir; `.claude/skills/...` against `$HOME` and against the skills dir's parent);

**New:**
> resolves each (relative ones against the containing skill's dir; `.claude/skills/...` against `$HOME` and against the skills dir's parent), and after a successful resolve also verifies the basename appears **verbatim** in a listing of its parent directory — macOS's default case-insensitive APFS otherwise resolves a wrong-case reference silently, making this linter weaker on the machine where `harness doctor` matters most;

### Edit 20 — Objective, tell the truth about what ships
**Old** (SPEC.md:4, second clause):
> a `scripts/` toolbox that owns numbering, slice briefs, review packages, overlap checks and plan/skill linting, and a `harness` CLI

**New:**
> a `scripts/` toolbox that owns numbering, slice briefs, review packages, overlap checks and plan/skill linting, and a `harness` CLI

…with this sentence appended to the paragraph:

> **What this wave does not change:** `skills/flow/*` is out of scope, so `/flow` still computes its own spec numbering and pastes contract blocks by prose. The `scripts/` toolbox is a prerequisite for U7 (flow-v2), not a change to today's `/flow` run — apart from `skills-lint`, which is useful standing alone. Honest framing of wave 1: a deterministic safety net (hooks) plus a diagnostic (`harness doctor`), with the `/flow` experience unchanged until U7 lands.

### Edit 21 — Wave 2, add the deferred items
**Old** (SPEC.md:148, U8 row "Owns" cell):
> `settings.json` hooks block + `skillListingBudgetFraction`, `CLAUDE.md` trim, stow deployment on this machine, description trims, duplicate-skill removals

**New:**
> `settings.json` hooks block, `CLAUDE.md` trim, stow deployment on this machine, description trims, duplicate-skill removals. Note: raising `skillListingBudgetFraction` is **not** a substitute for cutting the index — the ~44,250 chars of skill descriptions are paid every session before any skill is invoked; raising the cap removes the truncation symptom and keeps the whole cost.

**New row appended to the Wave 2 table:**
> | U9 harness-v2 | `hooks/stop-gate.sh` (extend), `scripts/plan-lint` wiring, `harness doctor` (extend) | Close what wave 1 documented as a limit: re-run `size_guard.py` over the C3 changed set at Stop so Bash-heredoc writes are covered (only after wave 1's false-positive fixes are proven); run `plan-lint` automatically when `.claude/feature-plan.local.md` changed this turn; a frozen-intent hash over the approved Behavior Inventory (S12) once flow emits the block; a `harness doctor` probe that reports the PATH a hook subprocess actually sees, so a macOS GUI-launched session cannot show "doctor all PASS / hooks all silently no-op" |

---

## 3. Wave 2 backlog (priority order)

1. **Wire `skills/flow/*` to the U3/U4 scripts (U7).** Until this happens, five of the twelve
   wave-1 deliverables have no caller. This is the difference between "the harness changed my
   week" and "the harness added a safety net". Highest priority by a wide margin.
2. **Cut the skill index (U8).** ~44,250 description chars measured live, paid every session
   before any skill fires. Wave 1 builds the instrument that reports it (`harness doctor` item 4)
   and is forbidden from acting on it. The ROI story of the whole harness rests here.
3. **Close the Bash-heredoc write bypass** (register #28) — re-run `size_guard.py` over the C3
   changed set at Stop. Gated on wave 1's size-guard false-positive fixes actually holding in
   daily use; shipping it before that converts advisory noise into turn-blocking noise.
4. **Auto-invoke `plan-lint`** when the plan file changed this turn (register #33). Cheap, but
   pointless before item 1 makes something produce a C7-shaped plan file.
5. **Frozen-intent hash over the approved Behavior Inventory** (register #31). Blocked on flow
   emitting a frozen block to hash; nothing in-scope to build until then.
6. **`harness doctor` hook-PATH probe** (register #32). Guards a real macOS failure mode
   (GUI-launched session, launchd PATH, every formatter invisible to hooks while doctor reports
   all PASS) but needs a genuine probe mechanism, not a one-liner.
7. **Baseline-aware gating** — replace the wave-1 wedge valve (3 identical blocks then advisory)
   with a real per-repo record of pre-existing failures, so a known-red repo blocks on regressions
   only. The checkwash-style fingerprinted exemption stays out until the no-install constraint is
   revisited.
8. **Re-verify findings 4, 7, 9, 10 by execution once U1/U2 land.** Every model-compliance finding
   is PLAUSIBLE, not CONFIRMED, because no code existed to run against. Adversarial test cases for
   stamp forgery, manifest deletion, and skip-marker insertion belong in U2's suite.

---

## 4. Verdict

Yes — build it, after the edits. The strongest thing about this package is that its riskiest layer
is also its best-sourced one: the vendor lens checked C1/C5/C10's hook semantics line-by-line
against a primary doc cache and found nothing wrong, which means the deterministic spine
(session-context, git-guard, stop-gate, format-lint, size-guard, pre-compact-backup) will behave as
written rather than fighting the platform. What the panel actually caught is a different class of
problem, and a cheap one: a frozen contract that contradicts its own Oracle (the `rtk-fast.sh` port),
a gate whose default setting would have got the whole harness disabled inside a week (unscoped
`check-all` on every turn), a heuristic with two *executed* false positives on ordinary React and
data files, a retention algorithm that deletes the wrong file, a dead config key, and a per-edit
eslint chain that punishes exactly the intermediate states a coding agent must pass through. None of
those needed a redesign; all of them are line edits to contracts the orchestrator controls right
now, and every one of them would otherwise have been discovered by a blocked or quietly-cheating
implementation agent later. That is the review paying for itself. The honest caveat is scope: after
these edits, wave 1 delivers a safety net and a diagnostic, not a changed workflow — five of its
scripts have no caller until U7 wires flow, and the largest single win in the entire research corpus
(the skill index) is assigned to a wave-2 unit that has not been specified yet. For one solo
developer on two machines, a deterministic net that catches `git reset --hard`, keeps a turn from
ending red, formats every edit, and tells him exactly what is unstowed is worth the build on its own
merits — but the package is only worth what it promises if wave 2 actually happens, and the Objective
edit above is there so nobody mistakes the one for the other.
