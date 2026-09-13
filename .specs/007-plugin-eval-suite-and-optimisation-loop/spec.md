# Spec: Plugin eval suite and optimisation loop

> **One-sentence summary**: Measure the code Claude writes under the flow plugin with `claude plugin eval`, then tune the plugin until that code is clean.

**Status**: Draft (unattended run; assumptions recorded)
**Size**: Medium
**Author**: Mr Claude, for Tomas
**Created**: 2026-09-12
**Last updated**: 2026-09-12
**Version**: 1.0

---

## TL;DR

**Problem**: The flow plugin promises high-quality code, but nothing measures whether the code Claude writes under it is any better than without it. A spike today showed Claude, with the plugin loaded, re-implementing an existing `slugify` helper instead of reusing it. There is no number for "how sloppy is flow's output", so there is nothing to optimise against.

**Solution**: A `claude plugin eval` suite under `plugins/flow/evals/` that grades code output against the forged `no-slop` rubric (duplication, over-engineering, comment noise, test slop, scope creep), plus routing and invariant cases, and a `flow eval` wrapper that runs it, records scores per plugin version, and feeds an optimisation loop (`flow loop run` with the eval as verifier) that edits skills, briefs and lenses until the suite passes at threshold.

**Who it's for**: Tomas (plugin author) running the loop; the Sonnet `developer` and `adversary` agents whose prompts the loop tunes.

**Non-goals (v1)**:
- Not a replacement for `scripts/tests` (structure and prose stay deterministic there).
- Pipeline cases run once per suite run (no 3-run averaging, no baseline arm): cost, and `/flow:*` has no meaning without the plugin.
- No CI job on a personal API key in v1 (Assumption A-003); local runs and a results ledger.
- No evals for the other five plugins in v1; the harness must make adding them a copy of one directory.
- No eval of routing for skills that need a long interview (grill-me, prep) beyond "fires or not".

**MVP cut line**: Section 4 `MUST` rows ship; `SHOULD` are v1.1; `MAY` backlog.

**Key decision**: The pipeline the user runs (`/flow:prep` → `/flow:flow-spec` → `/flow:flow` → `flow next`) is what gets evaluated, end to end, and its output code is graded for slop; the `no-slop` skill is the rubric and the brief text, not the subject. Routing and invariants are secondary gates. (Corrected 2026-09-12 after the user's clarification.) Every rubric item is a PASS/FAIL grader (regex over files, tool_used/tool_order, or a 3-vote llm grader), never a prose opinion.

---

## 1. Context

### 1.1 Problem Statement
Tomas built a 29-skill plugin with hooks and workflows so that Claude writes better code. Every claim of "better" is prompt-only; the only mechanical checks are file size, formatting and test weakening. The spike (`plugins/flow/evals/probe-write`, 2026-09-12) scored 0/1: Claude read only the target file, never searched for an existing helper, and duplicated it. The user wants zero duplicated code and none of the classic AI-slop signs from `/flow`, and a loop that keeps measuring and adjusting until that holds.

**Current workaround**: Manual review of PRs; `/audit` sweeps after the fact; global CLAUDE.md rules.

**Business rationale**: GitClear's 211M-line study shows AI-era code duplicating 4x more and refactoring 60% less. A plugin that does not measure this is part of the problem.

### 1.2 User Roles

| Role | Description | Volume | Key characteristic |
|------|-------------|--------|--------------------|
| Plugin author (Tomas) | Runs `flow eval`, reads reports, approves or vetoes loop edits | 1 | Wants numbers, not opinions; runs overnight loops |
| Optimisation loop (`flow loop run`) | Fresh `claude -p` sessions that edit skills/briefs/lenses and re-run the eval | 1 at a time | Cannot ask questions; needs a verifier exit code |
| Eval child session | The `claude` run the harness spawns per case with only the flow plugin loaded | 3 per case per arm | Empty workspace; hooks fire; no other plugins |

**Primary actor**: Plugin author.
**Hidden stakeholders**: Anyone installing `flow@flow` (they inherit whatever the loop tunes); the eval results ledger reader in 6 months.

### 1.3 Prior Art & Alternatives Considered

| Option | Status | Why rejected / why not this |
|--------|--------|-----------------------------|
| skill-creator `evals.json` + `run_loop.py` | Rejected | Tests description triggering only; no code-output graders, no ablation arm |
| Hand-run headless probes (`claude -p`) with ad-hoc greps | Rejected | No scoring, no baseline, not repeatable; the two loop probes in PROGRESS.md cost $0.80 each and produced no number |
| `claude plugin eval` with graders + with/without ablation | Selected | Shipped in the CLI, scores a no-plugin baseline, JSON schema v1, cost caps, runs hooks |
| Mutation testing as the only quality oracle | Deferred (SHOULD) | Ground truth for test quality but needs Bash in the sandbox (socat missing on this machine) |

---

## 2. Scope

### 2.1 In Scope
- Eval suite `plugins/flow/evals/` with four tiers, each a tag: `pipeline` (run `/flow:flow --unattended`, `/flow:fix`, `/flow:flow-spec`, `/flow:prep` on a fixture and grade the artifacts and code), `quality` (single-slice code output), `routing` (right skill fires), `invariant` (skill promises hold).
- Fixture scaffolds (`scaffold.sh` per case) that build small Python and TypeScript repos with planted reuse targets.
- Graders derived one-to-one from the `no-slop` rubric items (regex/file, tool_order, llm 3-vote).
- `flow eval` subcommand: runs the suite with pinned models and cost cap, writes `evals/ledger.jsonl` (date, git sha, model, per-tag score, delta, cost), prints a one-screen summary, exit code from `--threshold`.
- Optimisation loop: a `.claude/loop/loop.md` contract whose verifier is `flow eval --tag quality --threshold 0.9 --json`, driven by `flow loop run`, editing only `plugins/flow/skills/no-slop/`, `agents` briefs, `workflows/build-slices.js` prompt strings and `skills/flow/review.md` lens table.
- Mutation check in `scripts/tests`: gutting one skill description makes its routing case fail (proves the suite can fail).
- Docs: `plugins/flow/evals/README.md` (how to add a case, how to read the ledger).

### 2.2 Out of Scope (Non-Goals)
- **CI on a personal key**: cost and secret handling undecided (A-003).
- **Whole `/flow` pipeline evals**: human gates and $10+ per run.
- **Other plugins' suites**: v1.1, once the flow suite is stable.
- **Semantic clone detection via embeddings**: research shows 9 to 43% F1 collapse under rewrites; not a gate.

### 2.3 Adjacent Systems

| System | Relationship | Constraint |
|--------|-------------|------------|
| `claude plugin eval` (CLI ≥ 2.1.269) | Runs the suite | JSON schema v1; `scaffold_script` is a path; `arm: with-only` for plugin-fired graders |
| `flow loop` (`bin/lib/loop/`) | Drives the optimisation loop | Verifier is any `sh -c` command, exit 0/1/2; caps 30 iterations / 480 min / stall 3 |
| `no-slop` skill (spec by skill-forge, same day) | Source of rubric items and the checker script | Every rubric item must be phrased PASS/FAIL |
| `scripts/tests/run.sh` | Hosts the mutation check and `flow eval` unit tests | Bash 3.2 portability list; no test shells out to `claude` today |
| Hooks (`session-context.sh`) | Fire inside eval children | Prints `Next: /flow` when `.git` exists; fixtures must not create `.git` unless the case wants that steer |

---

## 3. User Journeys

### Journey 1 — Measure code quality (P1)
**Actor**: Plugin author
**Starting condition**: Clean checkout, `claude` logged in, no socat (Write/Edit cases only)
**Goal**: A per-tag score and delta for the current plugin version in under 15 minutes and under $25.

**Happy path**:
1. Run `flow eval` (defaults: all tags, `--runs 3`, pinned `--model` and `--judge-model`, `--max-cost-usd 25`, `-j 4`).
2. Suite runs; ledger line appended; summary prints tags, scores, deltas, cost.
3. Exit 0 when every case ≥ threshold, else 1.

**Error path — cost ceiling hit**:
1. `claude plugin eval` exits 2 with `partial: true`.
2. `flow eval` prints the partial reason, still appends a ledger line marked `partial`, exits 2.
3. Author lowers scope with `--tag` or raises the cap.

**Edge cases**:
- socat missing: cases tagged `needs-bash` are skipped with a one-line notice, not failed.
- `claude` not on PATH: exit 1 with the install hint from `flow doctor`.

**Acceptance criteria**:

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-001 | the suite exists | `flow eval --tag quality` runs | every `quality` case runs with the plugin and without, and the summary shows score, delta and cost per case | MUST |
| AC-002 | a run completes | the ledger is read | one JSON line per run with sha, model, per-tag score, meanDelta, cost, partial flag | MUST |
| AC-003 | `--max-cost-usd` is breached | the run ends | exit 2, ledger line has `partial: true` | MUST |
| AC-004 | socat is absent | a `needs-bash` case is selected | it is skipped with a notice, exit code unaffected | MUST |
| AC-030 | the pipeline fixture | `flow eval --tag pipeline` runs | every pipeline case loads, runs to completion inside its turn and time caps, and produces a per-grader verdict | MUST |

### Journey 2 — Optimise until green (P1)
**Actor**: Optimisation loop
**Starting condition**: `flow eval --tag quality` fails at threshold 0.9
**Goal**: Edit the plugin (skill text, briefs, lenses, checker) until the quality tag passes, without touching the eval cases.

**Happy path**:
1. `flow loop init --fresh --verify "flow eval --tag quality --threshold 0.9 --runs 2"` with the goal text and an allowlist of editable paths.
2. Each iteration: read the last report's failed graders, edit the allowed files, commit, verifier runs.
3. Verifier exit 0 → loop stops, PROGRESS.md gets a line with before/after scores.

**Error path — the loop edits an eval case**:
1. `flow loop check` tamper veto sees a diff under `plugins/flow/evals/` (added to `test_files`).
2. Verdict `suspect`, exit 2; iteration rejected; BLOCKED.md written.

**Edge cases**:
- Stall (3 iterations, no score change): loop stops with the plateau in the log.
- Score regresses: loop keeps the higher-scoring commit as the base for the next iteration (git reset to it is banned; it reverts by a new commit).

**Acceptance criteria**:

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-010 | a loop contract with the eval verifier | an iteration edits only allowed paths | the verifier runs `flow eval` and the loop continues or stops on its exit code | MUST |
| AC-011 | an iteration edits a file under `evals/` | `flow loop check` runs | verdict `suspect`, exit 2 | MUST |
| AC-012 | the suite passes at threshold | the loop stops | PROGRESS.md carries before/after per-tag scores and the winning sha | MUST |

### Journey 3 — Prove the suite can fail (P2)
**Actor**: Plugin author
**Starting condition**: Suite green
**Goal**: Confidence the graders are not tautological.

**Happy path**: `scripts/tests/test_evals.sh` holds `t_eval_mutation_*` tests that (a) blank the `fix` skill description in a temp copy and assert the routing case's grader spec would fail (static check against the grader, no `claude` call), and (b) run the `no-slop` checker script on a planted-slop fixture and assert it reports every planted item.

**Acceptance criteria**:

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-020 | the planted-slop fixture | the checker runs | every planted signal is reported and the clean fixture reports none | MUST |
| AC-021 | a copy of the plugin with one description blanked | routing graders are evaluated against a recorded trace without the skill call | the case scores 0 | SHOULD |

---

## 4. Functional Requirements

### 4.1 Core Requirements

| ID | Actor | Requirement | Priority | Acceptance Link |
|----|-------|-------------|----------|-----------------|
| FR-001 | Eval child | MUST be given a fixture with a reuse target for every `quality` case (scaffold script), never an empty workspace | MUST | AC-001 |
| FR-002 | Suite | MUST grade each `no-slop` rubric item with at least one case, each grader PASS/FAIL | MUST | AC-001 |
| FR-003 | Suite | MUST include a `routing` case per hub skill (fix, flow, flow-spec, loop, prep, scrutinize-idea, qa, audit) and two negative cases that must fire no skill | MUST | AC-001 |
| FR-004 | Suite | MUST include `invariant` cases for: reproduce-before-fix (tool_order), never weaken a test (regex not_contains on test files), verifier decides completion (llm) | MUST | AC-001 |
| FR-012 | Suite | MUST include `pipeline` cases: `/flow:flow --unattended` on a fixture with existing helpers (graders: spec.md and plan exist, existing helpers reused, no NS-03/04/05/06/08/09 signals in added code, a search tool call precedes the first Write/Edit), `/flow:fix` on a planted bug (test run before edit, regression test added, no test weakened), `/flow:flow-spec` alone (spec has no implementation leak, no invented requirement), `/flow:prep` first turn (one question, stated hypothesis with confidence, no silent pick). Each runs once, `--ablation none`, `max_turns 150`, `timeout_seconds 2400` | MUST | AC-030 |
| FR-013 | Loop | MUST edit only pipeline skill files (`skills/prep`, `skills/flow-spec`, `skills/flow`, `skills/fix`, `skills/feature/execution-prompt.md`, `scripts/slice-brief`, `workflows/*.js`) and `skills/no-slop/references/developer-block.md`, with `flow eval --tag pipeline --tag quality` as verifier | MUST | AC-010 |
| FR-005 | `flow eval` | MUST pin `--model` and `--judge-model` from `.claude/flow.config.json` (`evalModel`, `evalJudgeModel`) with defaults `claude-sonnet-5` / `claude-haiku-4-5` | MUST | AC-002 |
| FR-006 | `flow eval` | MUST append a ledger line per run and print a per-tag summary with deltas | MUST | AC-002 |
| FR-007 | `flow eval` | MUST skip `needs-bash` cases when `socat` is absent and say so | MUST | AC-004 |
| FR-008 | Loop | MUST treat `plugins/flow/evals/**` as tamper-protected `test_files` | MUST | AC-011 |
| FR-009 | `flow doctor` | SHOULD report eval readiness (claude version ≥ 2.1.269, bwrap, socat, ledger age) | SHOULD | — |
| FR-010 | `flow next` | SHOULD recommend `flow eval` when skills changed since the last ledger line | SHOULD | — |
| FR-011 | Suite | MAY run mutation testing (mutmut) in `needs-bash` cases as the test-quality oracle | MAY | — |

### 4.2 Data Requirements

| Entity | Description | Key attributes (logical) | Relationships |
|--------|-------------|--------------------------|---------------|
| Case | One eval scenario | name, tags, fixture, graders, runs | belongs to a tier |
| Ledger line | One suite run | timestamp, sha, model, judge model, per-tag score, meanDelta, cost, partial | references cases by name |
| Loop contract | One optimisation run | goal, verify command, allowed paths, caps | produces ledger lines |

**Data retention**: `evals/results/` is gitignored and pruned by the author; `evals/ledger.jsonl` is committed.
**Data sensitivity**: Traces may contain repo code; results stay local, `--no-publish` is the default.

---

## 5. Non-Functional Requirements

### 5.1 Performance

| Metric | Target | Condition | Measurement method |
|--------|--------|-----------|-------------------|
| Full suite wall time | ≤ 15 min | `-j 4`, 3 runs, ~30 cases | `durationSeconds` in JSON |
| Full suite cost | ≤ $25 | with-without ablation | `costUsd` in JSON |
| Quality-tag-only loop verifier | ≤ 6 min, ≤ $8 | `--runs 2`, `--ablation none` | same |

**Performance budget decision**: above $40 per full run the loop is uneconomic; drop `runs` to 2 before dropping cases.

### 5.2 Security
**Authentication**: the user's own `claude` login; no keys in the repo.
**Authorization**: `--scaffold` and `--allow-tools Write Edit` only on cases in this repo (`--trust-plugin` asserted by `flow eval`).
**Threat surface**: a scaffold script runs as the user outside the sandbox. `flow eval` refuses scaffold scripts outside `plugins/*/evals/`.

### 5.3 Reliability & Availability
**Graceful degradation**: missing `claude`, `bwrap` or `socat` produce a skip or a clear exit 1, never a hang.
**Recovery behavior**: partial runs still write a ledger line; re-running is idempotent.

### 5.4 Error Handling

| Error condition | Actor-visible behavior | System behavior | Recovery path |
|----------------|----------------------|-----------------|---------------|
| Case file invalid | eval CLI exit 1 with the file name | `flow eval` echoes it, exit 1 | fix the case |
| Cost ceiling | "partial: cost_ceiling" line | ledger marked partial, exit 2 | narrow with `--tag` |
| Auth rejected | "partial: auth_failed" | exit 2 | `claude login` |
| Loop tamper | BLOCKED.md written | iteration rejected | author reviews |

### 5.5 Scalability
30 cases in v1; adding another plugin's suite is one directory and one `flow eval --plugin` flag. Bottleneck: rate limit shared by `-j` children.

### 5.6 Observability
Ledger is the metric store; `flow eval --history` prints the last 10 lines as a table. The HTML report path is printed per run.

### 5.7 Accessibility / 5.8 Platform
CLI only. Linux and macOS; Windows needs WSL2 for Bash-granting cases (documented).

---

## 6. Success Criteria

### 6.1 Launch Criteria
- [ ] AC-001 to AC-004, AC-010 to AC-012, AC-020 pass.
- [ ] `flow eval --tag quality` shows a positive meanDelta after the loop, and the S1 reuse case (existing `slugify`) passes 3/3 with the plugin.
- [ ] `bash plugins/flow/scripts/tests/run.sh` green including the new tests; shellcheck clean.
- [ ] The mutation check proves at least one case can fail.

### 6.2 Post-Launch Health Metrics

| Metric | Target | Measurement | Review trigger |
|--------|--------|-------------|----------------|
| Quality tag score | ≥ 0.9 with plugin | ledger | drops below 0.85 on two consecutive runs |
| meanDelta | > 0.2 | ledger | ≤ 0 (plugin not helping) |
| Cost per full run | ≤ $25 | ledger | > $40 |

### 6.3 What "Failure" Looks Like
The suite goes green because the graders are lenient (llm graders passing everything) while real PRs still duplicate helpers. Defence: regex-over-file graders for every mechanical signal, llm graders only where research says no mechanical check exists, and the mutation check.

---

## 7. Constraints & Assumptions

### 7.1 Technical Constraints

| Constraint | Rationale | Impact on design |
|-----------|-----------|-----------------|
| No socat on this machine | sudo needs a password | v1 quality cases use Write/Edit only; Bash-tier tagged `needs-bash` |
| Eval children see an empty workspace | harness design | every quality case ships a scaffold |
| Hooks fire in children | harness design | fixtures avoid `.git` unless the case tests a hook |
| Bash 3.2 portability, shellcheck | `scripts/tests/run.sh` | `flow eval` lives in `bin/lib/eval.js` (Node), tests in bash |

### 7.2 Assumptions

| ID | Assumption | Confidence | Owner | How to validate |
|----|-----------|------------|-------|-----------------|
| A-001 | Code quality of flow's output is the optimisation target (user said so 2026-09-12) | High | Tomas | — |
| A-002 | Iterate on `claude-sonnet-5`, certify on the session model | Medium | Tomas | compare ledger lines across models |
| A-003 | No CI job in v1; local runs only | Medium | Tomas | user decision at PR review |
| A-004 | The optimisation loop is `flow loop run` with `flow eval` as verifier | High | Mr Claude | AC-010 |
| A-005 | $25 per full run is acceptable | Low | Tomas | user decision at PR review |
| A-006 | Rubric items come from the `no-slop` skill forged today | High | Mr Claude | skill exists before slice 2 |

### 7.3 Dependencies

| Dependency | Type | Owner | Status | Risk if delayed |
|-----------|------|-------|--------|-----------------|
| `no-slop` skill (rubric + checker) | Blocking for quality tier | skill-forge run | In progress | quality graders cannot be written |
| `claude` ≥ 2.1.269 | Blocking | local | Available (2.1.269) | — |
| socat | Informational | Tomas (`sudo pacman -S socat`) | Missing | Bash-tier cases skipped |

---

## 8. Open Questions

| ID | Question | Impact if unresolved | Owner | Deadline |
|----|---------|----------------------|-------|----------|
| Q-001 | Per-slice or branch-level placement of the slop lens in `flow/review.md`? | affects invariant cases | Mr Claude (synthesis) | before slice 2 |
| Q-002 | Is $25/run and ~$100/loop acceptable? | loop may be uneconomic | Tomas | PR review |
| Q-003 | CI on a key later? | none for v1 | Tomas | PR review |

---

## 9. Revision History

| Version | Date | Author | Changes | Reason |
|---------|------|--------|---------|--------|
| 1.0 | 2026-09-12 | Mr Claude | Initial draft, consolidate mode | unattended run after discovery 1 |

## Appendix

### A. Glossary

| Term | Definition in this spec |
|------|-------------------------|
| Arm | One of two eval runs per case: with the plugin, or without (baseline) |
| Delta | with-arm score minus without-arm score |
| Tier / tag | `quality`, `routing`, `invariant`, plus `needs-bash` |
| Ledger | `plugins/flow/evals/ledger.jsonl`, one line per suite run |

### C. Reference Documents

| Document | What it answers | Link |
|----------|----------------|------|
| research-notes.md | spike facts, hooks, loop verifier API, CLI seams, skill inventory | `.specs/007-plugin-eval-suite-and-optimisation-loop/research-notes.md` |
| plugin-evals docs | case schema, graders, sandbox, JSON | https://code.claude.com/docs/en/plugin-evals.md |
| skill-forge workspace | slop research and the forged skill | `.skill-forge/no-slop/` |

## Amendment 2026-09-13 — v1.1: code quality is the target

User priority restated: the code the pipeline writes must be of the highest quality. The v1 quality tier saturated (five of six cases pass without the plugin) and the score never saw the mechanical tells. Scope added, same ACs style:

| ID | Actor | Requirement | Priority |
|----|-------|-------------|----------|
| FR-020 | Suite | MUST add six `quality-hard-*` cases whose traps are realistic: a reusable helper two directories away under another name, a guard on a typed value, a mode flag temptation on a shared function, a test that must bite, style drift against a neighbouring file, cleanup temptation on a one-line fix | MUST |
| FR-021 | `flow eval` | MUST run a case's `postcheck.sh` in the kept workspace after each run (contract: cwd = workspace, `EVAL_CASE`/`EVAL_RUN`/`EVAL_TRACE`/`EVAL_PLUGIN_ROOT`, 120 s, exit 0 = pass), record `post: {pass, total}` per tag in the ledger, and count a case as passed only if graders ≥ threshold and every post-check passed | MUST |
| FR-022 | `slop-check` | MUST offer `--all-lines --files <paths>` for workspaces without git | MUST |
| FR-023 | Suite | MUST post-check every quality case with `slop-check --all-lines --strict` and the fix case with a mutation check (revert the fix; the new test must go red) | MUST |
| FR-024 | Loop | SHOULD run with the verifier restricted to `--tag quality --runs 3` once FR-020..023 land | SHOULD |

Assumption A-007: the mechanical tells found by `slop-check` are a fair proxy for "highest quality" when combined with the LLM rubric graders; mutation testing beyond the fix case is v1.2.
