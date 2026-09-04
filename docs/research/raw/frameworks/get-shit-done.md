# get-shit-done

## What it is

`get-shit-done-cc` (GSD) is a meta-prompting / context-engineering / spec-driven development system for Claude Code (and OpenCode/Gemini/Codex), by TÂCHES. It replaces "chat with the model and hope it remembers" with a file-based state machine: `.planning/` artifacts (PROJECT.md, ROADMAP.md, STATE.md, per-phase PLAN/SUMMARY/VERIFICATION.md) plus ~65 slash commands, 31 subagent types, and Node.js hooks/CLI tooling that enforce structure the prompts alone can't guarantee.

- Repo: `https://github.com/glittercowboy/get-shit-done` (clone redirects to canonical `gsd-build/get-shit-done`)
- Stars: not shown in a `--depth 1` clone (no GitHub API call made)
- Last commit (this clone): `Sun May 31 08:34:35 2026 -0500`
- Installed version in this user's dotfiles: **v1.5.15** (`~/.dotfiles/claude/.claude/get-shit-done/VERSION`, symlinked into `~/.claude/get-shit-done`) vs. upstream HEAD **v1.50.0-canary.0** (`package.json`) — the user is ~45 minor versions behind. Upstream has grown from ~20 workflow files to 190+ workflow/reference files, added a TypeScript SDK (`sdk/`), a golden-test harness, mutation testing (Stryker), CI release automation, and a `bin/install.js` installer that is now **11,376 lines**.

## Workflow it implements

Core loop (matches the user's older installed command set, still present upstream under renamed/expanded commands):

1. `new-project` → creates `.planning/PROJECT.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`
2. `discuss-phase {N}` → orchestrator reads STATE.md/ROADMAP.md, scouts codebase, surfaces "gray areas" via `AskUserQuestion`, writes a `{N}-CONTEXT.md` discussion log, commits it, updates STATE.md, optionally auto-advances (`get-shit-done/workflows/discuss-phase.md`, steps: `initialize → check_blocking_antipatterns → check_spec → check_existing → load_prior_context → cross_reference_todos → scout_codebase → analyze_phase → present_gray_areas → discuss_areas → write_context → confirm_creation → git_commit → update_state → auto_advance`)
3. `plan-phase {N}` → spawns `gsd-planner` (and optionally `gsd-phase-researcher`) to produce `{N}-PLAN-{NN}.md` files; a `gsd-plan-checker` reviews plan quality in a **check-revise-escalate loop capped at 3 iterations** with stall detection
4. `execute-phase {N}` → orchestrator discovers plans, groups into dependency-ordered waves, spawns one **fresh `gsd-executor` subagent per plan** (in a disposable git worktree when possible), aggregates SUMMARY.md results, runs an advisory code-review gate, a regression gate against prior-phase tests, a schema-drift gate, then spawns a **fresh `gsd-verifier` subagent** to check the phase's actual GOAL (not just task completion) against ROADMAP.md success criteria, producing `{N}-VERIFICATION.md`
5. Verification outcomes route: `passed` → `update_roadmap`; `human_needed` → persists a `{N}-HUMAN-UAT.md` and waits for manual sign-off; `gaps_found` → offers `/gsd:plan-phase {N} --gaps` (gap-closure loop)
6. `debug` / `diagnose-issues` → scientific-method debugging in a **resumable session file** (`.planning/debug/{slug}.md`) delegated to `gsd-debug-session-manager`, which loops `gsd-debugger` through checkpoints until root cause is found or the session is abandoned; `diagnose-issues` fans this out **in parallel, one debug agent per UAT gap**, feeding diagnosed root causes back into `plan-phase --gaps`
7. `complete-milestone` → readiness gate, stats gathering, PROJECT.md "full review" rewrite (Validated/Active/Out-of-Scope requirement buckets), ROADMAP.md reorganization into `## Milestones`, archival of phase directories, and a written retrospective (`## What Was Built / What Worked / What Was Inefficient / Patterns Established / Key Lessons`)

**Fresh-context-per-phase mechanism:** every planning/execution/verification/debug step is dispatched via `Agent(subagent_type="gsd-...", isolation="worktree", ...)` from `get-shit-done/workflows/execute-phase.md` step `execute_waves` — the orchestrator "stays lean" (documented budget: "~15% orchestrator, 100% fresh per subagent," `commands/gsd/execute-phase.md`) and subagents load their own context by reading files from disk rather than receiving inlined content (`get-shit-done/references/context-budget.md`, rule 2: "Never inline large files into subagent prompts").

## Artifacts it produces

| File | Location | Purpose | Schema (quoted headings) |
|---|---|---|---|
| `PROJECT.md` | `.planning/` | Long-term requirements/decisions memory | `## What This Is / ## Core Value / ## Requirements / ### Validated / ### Active / ### Out of Scope / ## Context` |
| `ROADMAP.md` | `.planning/` | Phase list + success criteria + progress table | `## Overview / ## Phases / ## Phase Details / ### Phase N: [Name]` with `**Goal**`, `**Depends on**`, `**Requirements**`, `**Success Criteria** (what must be TRUE)`, `**Plans**`; later `## Milestones / ## Progress` |
| `STATE.md` | `.planning/` | Session-to-session short-term memory, **hard-capped at 100 lines** ("a DIGEST, not an archive") | `## Project Reference / ## Current Position / ## Performance Metrics / ## Accumulated Context / ### Decisions / ### Pending Todos / ### Blockers/Concerns / ## Deferred Items / ## Session Continuity` |
| `{N}-CONTEXT.md` | `.planning/phases/{N}/` | Discuss-phase output | `## Decisions Captured / ### [Category] / ## Noted for Later` |
| `{N}-PLAN-{NN}.md` | phase dir | Planner→executor handoff | frontmatter (`phase, plan, type, wave, depends_on, files_modified, autonomous, requirements`), `<objective>`, `<tasks>`, `<verification>`, `<success_criteria>` |
| `{N}-SUMMARY.md` | phase dir | Executor→verifier handoff | frontmatter (`phase, plan, subsystem, tags, key-files, metrics`), commits table, "Deviations" section, "Self-Check: PASSED/FAILED" |
| `{N}-VERIFICATION.md` | phase dir | Verifier output | `status:` frontmatter (`passed`/`human_needed`/`gaps_found`), must-haves checklist |
| `{N}-HUMAN-UAT.md` | phase dir | Manual test tracker when automation can't verify | `## Current Test / ## Tests / ### {N}. {item} / ## Summary / ## Gaps` |
| `.planning/debug/{slug}.md` | debug dir | Resumable debug session | frontmatter `status/trigger/updated`; body `Current Focus` (`hypothesis`, `next_action`), `Evidence`, `Eliminated`, `Resolution` |
| `{version}-RETROSPECTIVE.md` | milestone archive | End-of-milestone learning capture | `## Milestone: v{version} — {name} / ### What Was Built / ### What Worked / ### What Was Inefficient / ### Patterns Established / ### Key Lessons` |

## Deterministic vs prompt

| Mechanism | Enforced by script/hook/CLI | Asked of the model in prose |
|---|---|---|
| Prompt-injection scanning of every file the model Reads | `hooks/gsd-read-injection-scanner.js` — PostToolUse hook, regex + invisible-Unicode detection, runs outside the model entirely | — (advisory `additionalContext` warning is text, but the *detection* is code) |
| Nudging Claude back into the framework when it edits files without an active GSD workflow | `hooks/gsd-workflow-guard.js` — PreToolUse hook on Write/Edit, checks for `.planning/` path or subagent context | — |
| Slug sanitization for debug session filenames (path-traversal defense) | Documented in `workflows/debug.md` as a regex (`^[a-z0-9][a-z0-9-]*$`, max 30 chars) but **executed by the model following prose instructions**, not a hook | Yes — this one is prose-only despite looking like a security control |
| Revision loop iteration cap + stall detection (max 3 iterations) | Not a script — `references/revision-loop.md` is pure prose the orchestrating model must follow each time | Yes |
| Wave dependency / parallel-write conflict detection (`files_modified` overlap) | Prose algorithm in `workflows/execute-phase.md` step `execute_waves` ("Detection algorithm (pseudocode)") — model executes it via Bash/reasoning, not a real static check | Yes |
| Git worktree HEAD-branch safety assertion before `git reset --hard` | Bash snippet embedded in the workflow prompt (`worktree-agent-*` namespace check) — real bash, but only runs because the model is told to run it | Half — deterministic *if* the model actually executes the bash block |
| Config reads (`workflow.tdd_mode`, `workflow.code_review`, context-window tier) | `gsd-sdk query config-get ...` — real Node CLI (`get-shit-done/bin/gsd-tools.cjs`, `sdk/`) | — |
| Context-window quality guard (60%/70% thresholds) | `gsd-sdk validate context` (`sdk/src/query/validate.ts`, `validateContext`: `ratio < 0.60` healthy, `< 0.70` warning, else critical — thresholds documented as "#2792 fracture point") [CORRECTED: the 60%/70% figures belong only to `gsd-sdk validate context`. The other cited file, `hooks/gsd-context-monitor.js`, uses different, unrelated thresholds — `WARNING_THRESHOLD = 35` and `CRITICAL_THRESHOLD = 25`, both measured as *remaining* percentage (i.e. it fires at 65%/75% *used*), not 60%/70%. The original row implied one shared threshold pair across both mechanisms; they are two separate guards with two separate threshold sets.] | — |
| Agent completion detection | Regex match on `## MARKER` headings, documented centrally in `references/agent-contracts.md`, but matching itself happens as model reasoning over subagent return text, not a hook | Mostly prose (the marker taxonomy is a *convention*, not parsed by code except spot-checks) |
| Install/upgrade, hook version stamping, atomic file writes | `bin/install.js` (11k lines), `scripts/build-hooks.js` (uses `fs.renameSync` for atomicity per CHANGELOG 1.41.0) | — |
| Gate taxonomy (pre-flight / revision / escalation / abort) | Pure documentation (`references/gates.md`) — no code enforces which gate type a given check "is"; it's a naming discipline for prompt authors | Yes, entirely |

**Overall read:** the newest, highest-value additions (injection scanning, workflow-guard, context monitor, atomic writes, config CLI) are real scripts. Everything about *plan quality, revision loops, worktree safety, and gate semantics* is still prose the orchestrating LLM must faithfully execute — nothing stops a degraded-context model from skipping a documented gate.

## Mechanisms worth stealing

1. **Read-time prompt-injection scanner as a PostToolUse hook**
   Problem: long agent sessions read untrusted files (docs, scraped content, other repos); injected instructions can survive context compression and become indistinguishable from real instructions.
   Path: `hooks/gsd-read-injection-scanner.js`
   Snippet: `/ignore\s+(all\s+)?previous\s+instructions/i`, `/[​-‏ - ﻿­⁠-⁩]/` (invisible Unicode), severity `HIGH` at 3+ pattern hits, injects `hookSpecificOutput.additionalContext` as a warning rather than blocking.
   Fit for dotfiles: drop-in as a global Claude Code `PostToolUse` hook in `~/.claude/hooks/` — completely project-agnostic, no GSD dependency, protects every session including ad hoc ones, not just GSD-managed ones.

2. **Soft workflow-guard hook (advise, don't block)**
   Problem: agents drift from a structured workflow into unmanaged direct edits, losing state tracking, without the user noticing until later.
   Path: `hooks/gsd-workflow-guard.js`
   Snippet: `"This is a SOFT guard — it advises, not blocks. The edit still proceeds."`
   Fit: generalizable pattern for any personal harness — e.g. warn when editing dotfiles directly outside a tracked change/commit flow, without ever blocking legitimate one-off fixes.

3. **Gate taxonomy (pre-flight / revision / escalation / abort)**
   Problem: ad hoc "checkpoint" prose in agent workflows becomes inconsistent — some checks silently pass, some loop forever, some should just stop everything.
   Path: `get-shit-done/references/gates.md`
   Snippet: `"Selection heuristic: Start with pre-flight. If the check happens after work is produced, it is a revision gate. If the revision loop cannot resolve the issue, escalate. If continuing is dangerous, abort."`
   Fit: a one-page taxonomy to paste into any CLAUDE.md or skill authoring guide for this dotfiles repo — cheap to adopt, immediately improves any multi-step Claude workflow (e.g. the `feature`/`fix`/`flow` skills already in this user's setup).

4. **Revision loop with stall detection, not just an iteration cap**
   Problem: naive "retry up to N times" loops keep re-spawning an agent that's stuck, wasting the same budget 3x without diagnosing why.
   Path: `get-shit-done/references/revision-loop.md`
   Snippet: `"If the count does not decrease between consecutive iterations, the producing agent is stuck and further iterations will not help. Break early and escalate to the user."`
   Fit: directly reusable in any Claude Code subagent-review loop (code-review fix loops, skill-judge convergence loops already present in this user's `.claude/skills/skill-forge`).

5. **`files_modified` overlap detection before parallel dispatch**
   Problem: parallelizing subagents across git worktrees is unsafe if two agents' target files overlap — silent merge conflicts or lost writes.
   Path: `get-shit-done/workflows/execute-phase.md` step `execute_waves`, part 1
   Snippet: pseudocode `seen_files = {}; for each plan in wave_plans: for each file in plan.files_modified: if file in seen_files: overlapping_plans.add(...)` — falls back to forced sequential execution for the affected wave.
   Fit: directly applicable to any multi-agent fan-out this dotfiles setup does (e.g. `ultracode` skill's Sonnet fleet) — a cheap pre-flight check before parallel `Agent()` dispatch.

6. **Stream-idle-timeout heartbeats at wave/plan boundaries**
   Problem: `Stream idle timeout - partial response received` errors on Claude Code when a long tool_result precedes a long silent reasoning gap.
   Path: `get-shit-done/workflows/execute-phase.md` lines ~418–435
   Snippet: `"emit short assistant-text heartbeats — no tool call, just a literal line — at every wave and plan boundary. Each heartbeat MUST start with [checkpoint]"`
   Fit: a documented, battle-tested workaround for a real Claude Code infra failure mode — worth copying verbatim into any long multi-agent orchestration prompt in this repo.

7. **STATE.md as a hard-capped digest, not an archive**
   Problem: agent "memory" files grow unboundedly and stop being useful because nobody wants to read 1000 lines at session start.
   Path: `get-shit-done/templates/state.md`
   Snippet: `"Keep STATE.md under 100 lines. ... The goal is 'read once, know where we are' — if it's too long, that fails."`
   Fit: a concrete size discipline (not just "keep it short") to apply to any persistent-memory file this user's skills maintain (e.g. session logs, `MEMORY.md`-style files).

8. **Resumable, slugged debug sessions with a scientific-method state file**
   Problem: debugging sessions get lost when context resets; re-explaining symptoms every time is expensive and error-prone.
   Path: `get-shit-done/workflows/debug.md`, `.planning/debug/{slug}.md` schema
   Snippet: `Current Focus` block with `hypothesis`, `next_action`; `/gsd:debug continue <slug>` resumes by reading the file back rather than replaying conversation.
   Fit: a lightweight pattern for a personal `/debug` command that persists hypothesis/evidence/eliminated state to a file under version control, independent of chat history.

## Second-reader additions

Mechanisms the first pass missed, verified directly against the clone at `/tmp/claude-1000/-home-tomas--dotfiles/65f7117c-29cb-4945-b826-0a4f06e8ef17/scratchpad/repos/get-shit-done`:

1. **The one hook in the whole system that actually blocks (`decision: "block"`, exit 2) — everything else in the report is advisory-only**
   Problem: the report's own "Overall read" says GSD's newest hooks are "real scripts" but stops short of noting that of the ~9 hooks in `hooks/`, exactly one enforces a hard block; the rest (injection scanner, workflow-guard, read-guard, phase-boundary) all inject `additionalContext` and let the tool call proceed regardless.
   Path: `hooks/gsd-validate-commit.sh`
   Snippet: PreToolUse hook on `git commit`; delegates subcommand classification to `hooks/lib/git-cmd.js` `isGitSubcommand()` ("A naive `^git\s+commit` regex misses [env-prefix, -C path, full-path invocations]; this guard fixes that (#3129)"), then on a non-conforming subject line emits `echo '{"decision": "block", "code": "CONVENTIONAL_COMMITS_VIOLATION", ...}'` and `exit 2` — a real, hard-blocking enforcement point, not advisory text. Opt-in only: no-op unless `.planning/config.json` sets `hooks.community: true`.
   Fit for dotfiles: the actually-portable pattern here isn't "scan and warn" (already covered by mechanism 1) but "pick exactly one high-value invariant (commit message format, or e.g. 'never commit to main') and make it a real PreToolUse exit-2 block" — cheap, and it's the only mechanism in the whole repo proven to stop a bad action rather than just narrate around it.

2. **CI-time structural contract lint across all 65 command files, not just prose convention**
   Problem: the report's Weaknesses section says "almost every gate is prose the orchestrating model must remember to execute" — true at *runtime*, but GSD separately catches doc/command drift at *CI time*, which the first pass didn't mention at all.
   Path: `scripts/lint-command-contract.cjs` (+ `scripts/command-contract-helpers.cjs`)
   Snippet: "Enforces the commands/gsd/*.md contract across all 65 command files: 1. name ... 2. description ... 3. allowed-tools ... 4. execution_context @-refs: every @-reference resolves to an existing file on disk 5. ... each appears on its own line ... Exit 0 = clean. Exit 1 = violations."
   Fit: a cheap, generalizable idea for this dotfiles repo's own skills — a small script that walks `.claude/skills/*/SKILL.md` (or command files) and fails CI if a referenced file path doesn't exist, closing exactly the "silently stale doc reference" failure mode without needing any of GSD's runtime machinery.

3. **Release-time tarball smoke test — verifies what actually ships, not what built locally**
   Problem: a build can succeed locally while the *published* npm package is missing files (wrong `files` whitelist, broken `prepublishOnly` chain) — a class of bug that unit tests never catch because they run against the source tree, not the packed artifact.
   Path: `scripts/verify-tarball-sdk-dist.sh`
   Snippet: "Guards regression of bug #2647: v1.38.3 shipped without `sdk/dist/` because the outer `files` whitelist and `prepublishOnly` chain drifted out of alignment." — runs `npm pack --ignore-scripts`, extracts the real tarball to a temp dir, asserts `sdk/dist/cli.js` exists, then installs deps inside the extracted package and invokes `gsd-sdk query --help` against it before allowing `npm publish`.
   Fit: directly reusable for any of this user's `bin/.local/bin/` Node.js CLI tools distributed via a packaging step — pack, extract, and execute the actual artifact in CI before calling a release "done," instead of trusting that source-tree tests generalize to the shipped tarball.

## Weaknesses / ceremony cost

- **Lines loaded per single command invocation:** `commands/gsd/execute-phase.md` (64 lines) `@`-includes `workflows/execute-phase.md` (1,802 lines) + `references/agent-contracts.md` (79) + `references/context-budget.md` (85) + `references/gates.md` (70) + `references/ui-brand.md` (not measured) ≈ **2,036+ lines of prompt text** loaded into the orchestrator's context for one `/gsd:execute-phase` call, before any subagent spawns or project files are read. `plan-phase` (1,789-line workflow) and `new-project` (1,476-line workflow) are comparably heavy.
- **Number of gates in execute-phase alone:** ~14 named `<step>` blocks including 5 explicit gates (`code_review_gate`, `regression_gate`, `schema_drift_gate`, `codebase_drift_gate`, TDD `tdd_review_checkpoint`), most advisory-only ("Advisory only — never blocks execution flow").
- **Things the model can silently skip:** almost every gate is prose the orchestrating model must remember to execute each turn — `references/gates.md` and `references/revision-loop.md` are pure documentation with no code enforcing they actually ran. A degraded-context or distracted model can skip a "REQUIRED" step (several are literally annotated `required="true"` in the XML, which is itself just a hint, not an enforced constraint) with no downstream failure until much later (e.g. missing a `files_modified` overlap check just corrupts a worktree silently).
- **Installer complexity:** `bin/install.js` is 11,376 lines — a large surface area (migrations, hook version stamping, node-path resolution across Homebrew/Cellar variants, minimal-vs-full install modes) that a solo dev adopting only *parts* of GSD would need to either accept wholesale or hand-extract.
- **Version churn:** CHANGELOG shows near-daily releases with mutation-testing gates, skill-surface reorganizations (86→59 commands), and stryker/coderabbit CI — this is closer to a maintained SaaS product's release cadence than a stable prompt library; adopting it means signing up for frequent breaking changes (the user's installed 1.5.15 vs upstream 1.50.0-canary gap already spans dozens of such reorganizations).

## Plugin/packaging structure

- Distributed as an **npm package** `get-shit-done-cc` (not a Claude Code "plugin.json"/marketplace entry) — `package.json` declares `bin: {"get-shit-done-cc": "bin/install.js", "gsd-sdk": "bin/gsd-sdk.js", "gsd-tools": "bin/gsd-sdk.js"}`.
- Install copies `bin/`, `commands/`, `get-shit-done/`, `agents/`, `hooks/`, `scripts/`, and a bundled `sdk/` (dist + prompts) into the target `.claude/` tree (per `package.json` `"files"` list).
- Registers Claude Code hooks (PreToolUse/PostToolUse/etc.) via `hooks/*.js` + `hooks/*.sh`, each self-versioned with a `// gsd-hook-version: {{GSD_VERSION}}` comment for update detection.
- 31 subagents under `agents/gsd-*.md` (largest: `gsd-debugger.md` 1,452 lines, `gsd-planner.md` 1,278 lines, `gsd-verifier.md` 917 lines, `gsd-executor.md` 774 lines) — these are Claude Code's native subagent-definition files, auto-loaded by `subagent_type=`.
- 65 slash commands under `commands/gsd/*.md`, each a thin (~50–150 line) wrapper that sets `allowed-tools`, parses `$ARGUMENTS`, and `@`-includes the real logic from `get-shit-done/workflows/*.md`.
- Also has README translations (ja-JP, ko-KR, pt-BR, zh-CN), a `CONTRIBUTING.md` (44KB) and `VERSIONING.md`, `.changeset/` (changesets-based release flow), `.github/workflows/` for canary/release/hotfix automation, and an optional TypeScript SDK (`sdk/`) with its own `package.json`/`tsconfig.json`/golden-fixture tests.

## Verdict: adopt / borrow parts / ignore

**Borrow parts — do not adopt wholesale.** The full GSD system is now a large, fast-moving software product (11k-line installer, near-daily releases, 190+ workflow/reference files, a TS SDK) built for teams/heavy users managing many concurrent projects with milestone-based roadmaps — that ceremony cost is disproportionate for a solo dev's dotfiles harness, and the user is already 45 releases behind on their existing install, suggesting upgrade friction is real. The parts worth lifting into this dotfiles repo are the small, self-contained, code-enforced mechanisms that don't require the rest of the system: the read-injection-scanner hook and workflow-guard hook (portable as-is, no GSD dependency), the gate taxonomy and revision-loop-with-stall-detection as documentation to paste into existing skills (`flow`, `fix`, `feature`, `ultracode`), the STATE.md size discipline, the `files_modified` overlap check for parallel agent dispatch, and the resumable slugged-session pattern for a lightweight personal `/debug` command. These are each under ~150 lines, address concrete failure modes already relevant to this user's existing Claude Code skill set, and don't require running GSD's installer or committing to its `.planning/` directory convention.
