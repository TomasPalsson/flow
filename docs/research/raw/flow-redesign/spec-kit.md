# spec-kit at source — what happens after the spec

**Scope**: `github/spec-kit`, everything downstream of `/speckit.specify`. Focus: artifact production, tasks.md grammar, `/implement`'s walk, feature-dir + prerequisite mechanics, where state lives, small-change handling, 2026 drift.

**Source (PRIMARY, fetched)**: `git clone --depth 1 https://github.com/github/spec-kit` on 2026-09-07 → HEAD `4a7341a9` dated **2026-09-04**; released version **1.0.4 (2026-09-02)** per `CHANGELOG.md:5`. All file:line refs below are to that tree unless marked otherwise. Nothing here is from the README.
**Prior flow research (do not repeat)**: `docs/research/02-frameworks-source-review.md` §1 (matrix row `spec-kit`), §3 steal-list items S5/S6/S9/S10, §5 skeleton lines 235–245, and the anti-pattern call-outs at :189 and :195. `docs/research/10-idiot-proof-harness-2026.md` §3. Raw: `docs/research/raw/frameworks/spec-kit.md`, `raw/idiot-proof/spec-kit-openspec-kiro.md`. **This file supersedes two claims in 02**: (a) core `create-new-feature.sh` no longer creates git branches, (b) `/speckit.specify` no longer calls that script at all.

---

## 1. The pipeline as it actually ships (PRIMARY)

`docs/reference/agentic-sdd.md:11` states the canonical chain verbatim:

```text
/speckit.constitution -> /speckit.specify -> /speckit.clarify -> /speckit.plan -> /speckit.checklist -> /speckit.tasks -> /speckit.analyze -> /speckit.implement -> /speckit.converge
```

Ten command templates, **2,437 lines total** (`templates/commands/*.md`): analyze 255, checklist 379, clarify 291, constitution 177, converge 273, implement 222, plan 170, specify 345, tasks 219, taskstoissues 106. Two of those (`converge`, `taskstoissues`) are new since the 02 review. `docs/reference/agentic-sdd.md:6`: "only `/speckit.specify` is strictly required before `/speckit.plan`. The clarify, checklist, and analyze commands are quality gates you add for anything with meaningful ambiguity." So the ceremony is *documented as optional* even though the command surface implies a 9-step march.

## 2. Where state lives — one pointer file, no DB (PRIMARY)

Everything downstream resolves through **`.specify/feature.json`**, a single-key JSON file:

```json
{ "feature_directory": "specs/003-user-auth" }
```

`scripts/bash/common.sh:163-208` `get_feature_paths()` resolution order is exactly three rungs, then a hard error:
1. `SPECIFY_FEATURE_DIRECTORY` env var (and, unless `--no-persist`, it *writes back* to feature.json);
2. `.specify/feature.json` → `feature_directory`;
3. `ERROR: Feature directory not found. Set SPECIFY_FEATURE_DIRECTORY or run the specify command to create .specify/feature.json.`

It then emits, via `printf '%q'` (the comment at :218 says: "safely quote values, preventing shell injection via crafted branch names"), a shell-evalable block: `REPO_ROOT`, `CURRENT_BRANCH`, `FEATURE_DIR`, `FEATURE_SPEC`, `IMPL_PLAN`, `TASKS`, `RESEARCH`, `DATA_MODEL`, `QUICKSTART`, `CONTRACTS_DIR`. Every downstream script is `eval "$(get_feature_paths)"` and then pure path work. `CURRENT_BRANCH` degrades gracefully: if no `SPECIFY_FEATURE` env is set it falls back to the feature-dir basename (`common.sh:210-217`, "issue #3026") — i.e. **git is no longer load-bearing for identity**.
Two real bugs are pinned in comments here and worth stealing as tests: `--no-persist` exists because pure path resolution used to dirty the working tree / clobber a pinned value (`common.sh:164-166`, issue #3025); the fallback parser chain is `jq → python3 → grep/sed` with a note that a broken `python3` stub must not swallow the file (`common.sh:95-105`, CHANGELOG #3312).

**Session state beyond that: none.** No run log, no task DB, no resume record. `/implement`'s only memory is the `[X]` markers inside `tasks.md`.

## 3. Feature dir + branch — the 2026 decoupling (PRIMARY, supersedes 02)

`scripts/bash/create-new-feature.sh` (420 lines) still does the deterministic work and is still excellent:
- `get_highest_from_specs()` (:110-134) scans `specs/*`, matches `^[0-9]{3,}-` while explicitly *skipping* timestamp dirs `^[0-9]{8}-[0-9]{6}-`, takes max, `+1`, `printf "%03d"`.
- `clean_branch_name()` (:157-161) carries a 3-line comment justifying each character of the implementation: `LC_ALL=C` because "in a UTF-8 locale glibc resolves the a-z *range* through collation, so `[^a-z0-9]` keeps accented lowercase letters"; `--*` instead of GNU `\+` because "POSIX/BSD sed reads as a literal '+'"; `printf` instead of `echo` "so a name of `-n`/`-e`/`-E` is text, not options".
- `fit_branch_name()` (:163-176) truncates to `MAX_BRANCH_LENGTH=244` ("GitHub enforces a 244-byte limit") and re-strips a trailing `-`.
- `--number N` is a *preference*, not a command: on collision it walks forward from the current max and warns `--number N conflicts with an existing spec directory; using NNN instead` (:303-327).
- Flags: `--dry-run`, `--allow-existing-branch`, `--short-name`, `--number`, `--timestamp`.
- It ends by calling `_persist_feature_json` and printing to stderr: `# To persist: export SPECIFY_FEATURE=…` / `SPECIFY_FEATURE_DIRECTORY=…`.

**What changed**: this script no longer touches git, and `templates/commands/specify.md` has **no `scripts:` frontmatter at all** — it does not call it. Instead `specify.md:39-90` instructs *the model* to pick the number ("next available 3-digit number after scanning existing directories in `specs/`"), `mkdir -p`, copy the template, and hand-write `.specify/feature.json`. Branch creation is an opt-in extension hook: `extensions/git/extension.yml:41-45` registers `before_specify → speckit.git.feature`, and `CHANGELOG.md:1116` records `feat: make git extension opt-in and remove --no-git at v0.10.0 (#2873)` — **0.10.0, 2026-06-09**. `specify.md:56` spells out the new stance: "The spec directory name and the git branch name are independent."
This is a **regression against 02 §3 steal-item S5** ("numbering, paths and ordering belong to a script, never to the model"). spec-kit still ships the good script; the default path just stopped using it. Take the script, not the 2026 decision.

## 4. `/speckit.plan` → research.md, data-model.md, contracts/, quickstart.md (PRIMARY)

`templates/commands/plan.md` is 170 lines, of which **71 are extension-hook boilerplate**. The actual instruction is 6 lines (`plan.md:57-70`):

1. Run `scripts/bash/setup-plan.sh --json`, parse `FEATURE_SPEC, IMPL_PLAN, FEATURE_DIR, BRANCH`.
2. Read spec + `/memory/constitution.md`; the plan template is *already copied* by the script.
3. Fill Technical Context (unknowns → `NEEDS CLARIFICATION`), fill Constitution Check, "Evaluate gates (ERROR if violations unjustified)", Phase 0 → `research.md`, Phase 1 → `data-model.md` + `contracts/` + `quickstart.md`, then **re-evaluate Constitution Check post-design**.

`setup-plan.sh` (85 lines) is deliberately tiny and idempotent: `mkdir -p "$FEATURE_DIR"`; if `plan.md` exists → "skipping template copy" (there is a dedicated test, `tests/test_setup_plan_no_overwrite.py`); else `resolve_template_content plan-template > "$IMPL_PLAN"`; emit JSON via `jq` with a hand-rolled `printf` fallback when `jq` is absent. It rejects unknown args (`ERROR: Unknown option`, CHANGELOG #4371).

Artifact semantics, from `plan.md:112-152`:
- **research.md** — Phase 0. One entry per unknown, fixed 3-field shape: `Decision / Rationale / Alternatives considered`. Generated by fanning out research tasks ("For each unknown in Technical Context: Task: 'Research {unknown} for {feature context}'"). Exit condition is literal: "research.md with all NEEDS CLARIFICATION resolved".
- **data-model.md** — entities, fields, relationships, validation rules pulled from requirements, state transitions.
- **contracts/** — explicitly *not* OpenAPI-only: "Identify what interfaces the project exposes… public APIs for libraries, command schemas for CLI tools, endpoints for web services, grammars for parsers, UI contracts for applications. **Skip if project is purely internal** (build scripts, one-off tools, etc.)".
- **quickstart.md** — a *validation* guide, and the template fights bloat directly: "Do not include full implementation code, model/service/controller bodies, migrations, or complete test suites… implementation details belong in `tasks.md`".

`templates/plan-template.md` (113 lines) is a fill-in form: Summary, Technical Context (9 named slots — Language/Version, Primary Dependencies, Storage, Testing, Target Platform, Project Type, Performance Goals, Constraints, Scale/Scope, each defaulting to `NEEDS CLARIFICATION`), Constitution Check ("*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*"), Project Structure (three canned trees — single project / web / mobile — with `[REMOVE IF UNUSED]` markers and "The delivered plan must not include Option labels"), and a **Complexity Tracking** table with columns `Violation | Why Needed | Simpler Alternative Rejected Because`, filled *only* when a constitution gate is violated. That last table is the best small idea in the whole template: it makes over-engineering cost a written justification.

## 5. `/speckit.tasks` → tasks.md (PRIMARY)

`setup-tasks.sh` (94 lines) hard-fails if `plan.md` or `spec.md` is missing (naming the command to run), builds `AVAILABLE_DOCS` by existence-checking `research.md`, `data-model.md`, `contracts/` (only if non-empty: `ls -A`), `quickstart.md`, and returns `FEATURE_DIR`, `AVAILABLE_DOCS`, `TASKS_TEMPLATE`, **`TASKS_TEMPLATE_CONTENT`** — the template body inlined into the JSON, so the model never has to find or read the template file (fallback path for old scripts is documented at `tasks.md:79`).

**The task grammar** (`templates/commands/tasks.md:170-197`) — a strict single line format:

```text
- [ ] [TaskID] [P?] [Story?] Description with file path
```

- Checkbox always `- [ ]`; ID is `T001, T002…` sequential *in execution order*; `[P]` only when parallelizable ("different files, no dependencies on incomplete tasks"); `[US1]/[US2]` story label **required in user-story phases, forbidden in Setup / Foundational / Polish**; description must carry an exact file path.
- It teaches by counter-example — four ❌ rows: missing ID, missing checkbox, missing ID, and `- [ ] T001 [US1] Create model` marked wrong purely for *missing a file path*.
- Dependency notes are inline prose in the description: `T014 [US1] Implement [Service] in src/services/[service].py (depends on T012, T013)` (`templates/tasks-template.md:110`).

**Phase grouping is by user story, not by layer** (`tasks.md:227-234`): Phase 1 Setup → Phase 2 Foundational ("Blocking Prerequisites… ⚠️ CRITICAL: No user story work can begin until this phase is complete") → Phase 3+ one phase per user story in P1/P2/P3 order → final Polish. Each story phase carries a **Goal**, an **Independent Test** line, and ends with a `**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently`. The template also emits a Dependencies & Execution Order section, Parallel Opportunities, and an Implementation Strategy with "MVP First (User Story 1 Only) → **STOP and VALIDATE**". Tests are opt-in, stated three times: "Tests are OPTIONAL - only include them if explicitly requested."

**Nothing parses this format.** `grep -rln "tasks.md" src/specify_cli/` returns exactly one file, and only in help strings (`__init__.py:374-379`). No test in `tests/` mentions `T001` or `[P]`. The grammar is enforced only by the model re-reading its own output ("Format validation: Confirm ALL tasks follow the checklist format", `tasks.md:151`). This confirms 02 §3 item S9 — the format rule is *stated but never parsed*.

## 6. `/speckit.implement` — how the walk works (PRIMARY)

`templates/commands/implement.md`, 222 lines, prerequisite `check-prerequisites.sh --json --require-tasks --include-tasks`. The loop (:97-160):
- **Checklist gate first**: scan `FEATURE_DIR/checklists/*.md`, count `- [ ]` vs `- [X]/[x]`, print a `| Checklist | Total | Checked | Unchecked | Status |` table, and if anything is unchecked, "**STOP** and ask: 'Some checklists have unchecked items. Do you want to proceed with implementation anyway? (yes/no)'". Read-only: "do NOT modify checklist files or markers".
- Load `tasks.md` + `plan.md`, then optionally `data-model.md`, `contracts/`, `research.md`, `quickstart.md`, constitution.
- Then ~40 lines of **ignore-file generation** — per-language `.gitignore`/`.dockerignore`/`.eslintignore`/`.terraformignore` pattern tables for 14 languages. This is dead weight bolted onto the executor.
- Parse phases, dependencies, `[P]` markers, file paths. Execute **phase by phase**, "Complete each phase before moving to the next", sequential tasks in order, `[P]` together, "Tasks affecting the same files must run sequentially".
- Failure policy is explicit and asymmetric: "**Halt execution if any non-parallel task fails**. For parallel tasks [P], continue with successful tasks, report failed ones."
- Progress: "**IMPORTANT** For completed tasks, make sure to mark the task off as `[X]` in the tasks file." That single instruction is the entire resume mechanism — the model rewrites `- [ ]` to `- [X]` in place, and a later `/implement` run reads the file and skips what is marked.

`check-prerequisites.sh` (243 lines) is the one prerequisite gate for `implement`, `analyze`, `converge`, `checklist`, `clarify` and `taskstoissues`, switched by flags: `--require-spec`, `--require-tasks`, `--include-tasks`, `--paths-only`, `--template NAME`, `--json`. Every failure names its fix: `ERROR: tasks.md not found in $FEATURE_DIR` + `Run <cmd> first to create the task list.` — rendered through `format_speckit_command`, so the message uses the invocation form of the agent actually installed (`/speckit.tasks` vs `$speckit-tasks`). `--template NAME` returns the composed template body inline as `TEMPLATE_CONTENT`, so one script call replaces "run script, then go read a file".

## 7. `/analyze`, `/checklist`, `/converge` (PRIMARY)

- **analyze** (255 lines): "**STRICTLY READ-ONLY**: Do not modify any files… Offer an optional remediation plan (user must explicitly approve)." Six detection passes (Duplication, Ambiguity, Underspecification, Constitution Alignment, Coverage Gaps, Inconsistency), severity enum CRITICAL/HIGH/MEDIUM/LOW with a written heuristic per level, "Limit to 50 findings total; aggregate remainder in overflow summary", output is a findings table plus a **Coverage Summary** table (`Requirement Key | Has Task? | Task IDs | Notes`) that mechanically joins FR-###/SC-### to task IDs. It also excludes un-buildable criteria from coverage: "exclude post-launch outcome metrics and business KPIs (e.g., 'Reduce support tickets by 50%')". CHANGELOG #2511 runs it in a forked subagent on Claude.
- **checklist** (379 lines, the longest): framed as "**Unit Tests for English**" — the checklist tests the *spec*, not the code. Items are `CHK001…`, and the template states the marker semantics twice: "`[x]` means the criterion has been reviewed and satisfied for requirements quality. It does not mean implementation work is complete." It asks up to 3 clarifying questions (escalating to 5) before generating.
- **converge** (273 lines, added 2026-07 per CHANGELOG #3001/#3181): the honest answer to "the agent said it was done". Reads spec/plan/tasks as "the **sole source of intent**", assesses the *current code*, and appends unmet work as a new `## Phase N: Convergence` block. Constraints are unusually tight: "**APPEND-ONLY, NEVER REWRITE**" — must not rewrite/renumber/reorder/delete existing tasks, must not touch spec.md or plan.md, must not touch code; and "When the codebase already satisfies everything, the command MUST leave `tasks.md` **byte-for-byte unchanged** (no empty Convergence header)". Explicitly not a diff tool: "no git, no branch comparison, no history."
- **taskstoissues** (106 lines): GitHub issues are an *optional leaf*, not the spine — it aborts unless `git config --get remote.origin.url` is a GitHub URL, dedupes by matching `\bT\d{3,}\b` in existing issue titles, and creates one issue per task titled `T001: <description>`. Notably it needs a 400-word paragraph to explain its own regex edge cases (four-digit IDs, `ST001` false matches, `T100` inside `T1000`) — a sign the ID scheme is doing work the tool should own.

## 8. Small changes, and how they degrade (PRIMARY)

There is no "small change" path in the command surface. `docs/guides/evolving-specs.md` instead names three **persistence models** the user chooses once: *Flow-Forward* (every change is a new numbered `specs/NNN-*` dir, prior dirs kept as history), *Living Spec* (`spec.md` is the contract; re-run plan → tasks → analyze → implement → converge on every change), *Flow-Back* (edit wherever the insight lands, then reconcile). All three still cost the full chain. The only real relief valves are documented in `docs/concepts/complex-features.md`, and both are *prompt arguments*, not features: `/speckit.implement only execute tasks T001-T010, then stop and report progress` (works because `[X]` marks survive), and `/speckit.implement delegate each parallel [P] task to a sub-agent`. The doc is candid about why: "In the middle of a long `/speckit.implement` run, agents can start to lose track of the plan, ignore tasks, or hallucinate — usually right before or after context compaction… The underlying cause is context window exhaustion."

`extensions/bug/` (`speckit.bug.assess` → `.test` → `.fix`) is the closest thing to a light lane, and it is an opt-in extension.

## 9. The `lean` preset — spec-kit's own answer to "too much ceremony" (PRIMARY)

`presets/lean/` is the most useful artifact in the repo for flow. Five commands replacing the core five, **116 lines total** vs 2,437 — a **21× reduction** — described as "Minimal core workflow commands - just the prompt, just the artifact" and "without the ceremony of the full templates. Each command produces a single focused Markdown file with no boilerplate sections to fill in." The entire lean `/plan` is:

```markdown
1. Read `.specify/feature.json` to get the feature directory path.
2. **Load context**: `.specify/memory/constitution.md` and `<feature_directory>/spec.md`.
3. Create an implementation plan and store it in `<feature_directory>/plan.md`.
   - Technical context: tech stack, dependencies, project structure
   - Design decisions, architecture, file structure
```

Lean drops research.md, data-model.md, contracts/, quickstart.md, clarify, checklist, analyze and converge entirely. It keeps exactly three things: the `feature.json` pointer, the constitution load, and the task checklist grammar (`speckit.tasks.md:16-18` keeps `- [ ] [TaskID] Description with file path` and phase-by-user-story, but drops `[P]` and `[US#]`). Lean's `/implement` is 22 lines and keeps only the `[ ]→[x]` marking and "Halt on failure". **That is very close to the shape the developer is asking for**, arrived at by spec-kit's own maintainers.

`workflows/speckit/workflow.yml` (74 lines) is the other lean-ward move: a declarative `specify → gate(review-spec) → plan → gate(review-plan) → tasks → implement` run with `type: gate`, `options: [approve, reject]`, `on_reject: abort`. Real gates, engine-enforced — unlike the prose hooks.

## 10. What spec-kit does BEST (specific)

1. **`tasks.md` as the single executable artifact.** One file is simultaneously the plan, the progress log and the resume token. `[ ]→[X]` in place means an interrupted run resumes with zero extra state, and "run only T001-T010" is a free feature. No issue tracker, no DB, no lock file.
2. **Grouping tasks by user story, not by layer.** Phase 3 = US1 end-to-end, with a `**Goal**`, an `**Independent Test**`, and a `**Checkpoint**` proving the story stands alone. This is vertical slicing baked into a template rather than argued for in prose — and it makes "MVP = stop after Phase 3" mechanical.
3. **One pointer file (`feature.json`) as the whole cross-session state**, with a 3-rung resolution order and a `--no-persist` read-only mode. Small, auditable, git-diffable, and it survived decoupling from git branches.
4. **Deterministic scripts with justified implementations.** `create-new-feature.sh`'s `LC_ALL=C` / `--*` / `printf` comments, the 244-byte fit, `--number` as a preference not a command, `--dry-run`, and cross-language parity that is *tested* (`tests/test_create_new_feature_python_parity.py`, `test_check_prerequisites_python_parity.py`, `test_setup_plan_python_parity.py`).
5. **Prerequisite checking as one flag-switched script that names its own fix.** `--require-spec/--require-tasks/--paths-only/--template` + `format_speckit_command` so the error says the right invocation for the installed agent. `--template NAME` inlining template *content* into the JSON kills a whole class of "the model went looking for the file" failures.
6. **`/analyze` as a read-only, capped, severity-tagged consistency pass** with a requirement→task coverage join, and an explicit exclusion of unbuildable business KPIs from coverage math.
7. **`/converge` as an anti-"it's done" gate**, append-only, byte-for-byte no-op when clean.
8. **The Complexity Tracking table** — over-engineering must be written down as `Violation | Why Needed | Simpler Alternative Rejected Because`.
9. **Anti-bloat instructions inside the templates themselves** — quickstart's "Do not include full implementation code…", tasks' four ❌ counter-examples, contracts' "Skip if project is purely internal".
10. **`update-agent-context` now writes a pointer, not a copy** (`extensions/agent-context/scripts/python/update_agent_context.py:205-213`): a marker-delimited 3-line block saying "read the current plan at `<path>`", resolved from feature.json with a most-recent-mtime `rglob('plan.md')` fallback. Persistent-memory-by-reference instead of duplication.

## 11. Clunky / over-ceremonial

1. **31% of the core command text is extension-hook boilerplate** — 761 of 2,437 lines, repeated near-verbatim in all ten files (66–116 lines each; `plan.md` spends 71 of its 170 lines on it, leaving 6 lines of actual planning instruction). And it is **prose-as-hook**: the model is told to print `EXECUTE_COMMAND: {command}` and then "you MUST actually invoke the hook… Emitting the block alone does not run the hook" — an admission it has failed. (02 §189 flagged this; it has since spread to 10 files.)
2. **Four artifacts before a line of code.** research.md + data-model.md + contracts/ + quickstart.md are generated for *every* feature, gated only by soft prose ("Skip if project is purely internal"). For a solo dev on a known stack, research.md is a transcript of things already decided and quickstart.md restates the test command.
3. **Numbering handed back to the model.** `specify.md:39-52` asks the LLM to scan `specs/`, pick "the next available 3-digit number", `mkdir`, and hand-write JSON — while a hardened script that does exactly this sits unused two directories away.
4. **A grammar nothing validates.** `T001 [P] [US1] … path` is specified across ~30 lines with counter-examples, then checked only by the model re-reading its own file. Add a 20-line parser and the whole section collapses to a schema.
5. **Two checklist systems with different semantics.** `checklists/requirements.md` is agent-owned and auto-maintained; `checklists/*.md` from `/checklist` are reviewer-owned; `implement.md` needs a paragraph to explain that `[x]` here means "reviewed", not "built", and `checklist-template.md` repeats the disclaimer three times. Any concept needing that much disambiguation is two concepts.
6. **`/implement` carries 40 lines of `.gitignore`/`.dockerignore` pattern tables for 14 languages** — unrelated to executing a task list, and stale by construction.
7. **The constitution is a fill-in-the-blanks form** (`[PRINCIPLE_1_NAME]` … `[SECTION_3_CONTENT]`, `**Version**: [CONSTITUTION_VERSION] | **Ratified**: …`) with amendment governance. For one person this is bureaucracy cosplay; the useful 10% is "Test-First (NON-NEGOTIABLE)"-style non-negotiables the plan gate can actually check.
8. **Interrogation caps that are only prose.** clarify ≤5 questions asked one at a time; specify ≤3 `[NEEDS CLARIFICATION]` markers; checklist 3→5 questions; analyze ≤50 findings. Good instincts, zero enforcement.
9. **131 Python files supporting a markdown pipeline** — bundler, presets, workflows engine (12 step types incl. `fan_out`/`do_while`/`switch`), overlays with a merge/composer/schema layer, 41 agent integrations, auth for GitHub *and* Azure DevOps. `docs/` alone has 5 subtrees. The `tasks.md` grammar this all exists to produce is validated by nothing.
10. **`taskstoissues`' regex archaeology** — a 400-word paragraph on `\bT\d{3,}\b` boundary cases is the tell that IDs-in-issue-titles is the wrong join key.

## 12. What a solo dev should drop

Drop: the constitution ceremony (keep 5 non-negotiable lines, drop version/ratification/amendment); `/clarify` as a separate command (fold the ≤3-question cap into spec, as `specify.md:200-221` already does with its A/B/C/Custom option table); `/checklist` entirely (it's a second spec-quality system on top of `requirements.md`); research.md and quickstart.md by default; contracts/ unless the feature is an actual interface boundary; data-model.md unless there is a schema change; the whole `EXECUTE_COMMAND` hook layer; the ignore-file generator; GitHub issues (`taskstoissues` proves they're an optional leaf, and the developer explicitly doesn't want them); the numbered `specs/NNN-*` dir *as a branch name* (spec-kit itself decoupled these).

Keep: `.specify/feature.json`-equivalent pointer; `create-new-feature.sh`'s numbering/slug/244-byte logic **in a script**; `tasks.md` with `[ ]→[x]` as the only progress state; phases grouped by vertical slice with Goal + Independent Test + Checkpoint; `check-prerequisites`-style one-script gate whose errors name the fix; `/analyze`'s read-only + capped + severity + coverage-join shape; `/converge`'s append-only "what's actually unbuilt" pass; the Complexity Tracking justification table; anti-bloat lines inside templates.

---

## BLUF (12 lines)

1. **BEST — one executable artifact.** `tasks.md` is plan + progress + resume in one file; `[ ] → [X]` marked in place is the entire resume mechanism, and it makes "just do T001–T010" free.
2. **BEST — slices, not layers.** Phases are user stories (P1/P2/P3), each with `**Goal**`, `**Independent Test**` and a `**Checkpoint**`; `Foundational` is the only shared blocking phase. MVP = stop after Phase 3.
3. **BEST — one pointer file.** `.specify/feature.json` (`{"feature_directory": …}`) + `get_feature_paths()`'s env → file → error order is all the cross-session state there is; `--no-persist` keeps read-only callers from dirtying the tree.
4. **BEST — scripts that own numbering, slugs and truncation**, with parity-tested twins and comments justifying `LC_ALL=C`, `printf` vs `echo`, and the 244-byte GitHub cap.
5. **BEST — prerequisite gate that names its own fix**, flag-switched (`--require-spec/--require-tasks/--paths-only/--template`) and able to inline template *content* into its JSON so the model never hunts for a file.
6. **BEST — `/analyze` + `/converge`**: read-only, 50-cap, CRITICAL→LOW, requirement→task coverage table; then an append-only pass that finds what was claimed done but isn't, and is a byte-for-byte no-op when clean.
7. **IMPROVE — 31% of command text (761/2,437 lines) is extension-hook boilerplate**, and it's prose-as-hook: "Emitting the block alone does not run the hook." Delete the layer; real gates belong in `workflow.yml` (`type: gate`, `on_reject: abort`) or `settings.json`.
8. **IMPROVE — four artifacts before any code.** research/data-model/contracts/quickstart are unconditional in practice; spec-kit's own `lean` preset drops all four and runs the same pipeline in **116 lines instead of 2,437**.
9. **IMPROVE — the model was handed back the numbering.** Since 0.10.0 (2026-06-09) git went opt-in and `/specify` stopped calling `create-new-feature.sh`; the model now scans `specs/` and writes `feature.json` by hand. Keep the script; reject that decision.
10. **IMPROVE — the `T001 [P] [US1] path` grammar is validated by nothing** (no parser in `src/`, no test mentions `T001`). ~30 lines of prose + ❌ counter-examples that a 20-line parser would replace.
11. **STEAL for flow**: `feature.json` pointer + a `new-spec` script; `tasks.md` as the sole build state with `[x]` resume; slice-phases with Independent Test + Checkpoint; one prerequisite script with fix-naming errors; `/converge` as the "is it actually built" gate; the Complexity Tracking justification table; `update-agent-context`'s marker-delimited *pointer* to plan.md instead of copying context.
12. **DON'T steal**: constitution ceremony, `/clarify` + `/checklist` as separate commands, unconditional research/quickstart/contracts, `EXECUTE_COMMAND` hooks, ignore-file generation inside `/implement`, GitHub issues as a pipeline stage, and 131 Python files of preset/bundler/workflow machinery around a markdown grammar nothing parses.
