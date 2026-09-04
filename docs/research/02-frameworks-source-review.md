# Frameworks Synthesis — What to Steal for flow v2

Builds on `SYNTHESIS.md` §§3–6 (gap analysis, recommended workflow, hooks, cut list). That document established *what is broken* (zero hooks wired, CLAUDE.md not stowed, 66 skills over the listing budget, 1,787 lines loaded per Medium `/flow` run, every invariant prose-only). This document establishes *what thirteen shipped frameworks do about the same problems*, and which of their mechanisms are worth copying by path.

Reading order: §2 tells you what the field agrees on. §3 is the actionable list. §5 is the target layout.

---

## 1. Comparison matrix

### 1a — Shape, artifacts, granularity, fresh context

| Framework | Workflow shape | Artifacts | Spec granularity | Fresh-context strategy |
|---|---|---|---|---|
| **spec-kit** (`github/spec-kit`) | 9 slash commands, linear: constitution → specify → clarify → plan → tasks → analyze → implement | `specs/<NNN-slug>/{spec,plan,tasks,research,data-model}.md`, `contracts/`, `checklists/*.md`, `.specify/memory/constitution.md`, `.specify/feature.json` | Task line forced to `- [ ] [TaskID] [P?] [Story?] Description with file path`, grouped **by user story not by layer** (`templates/tasks-template.md`) | None. Only a cross-session pointer: `.specify/feature.json` written by `common.sh:_persist_feature_json`, read `env > file > error` |
| **openspec** (`Fission-AI/OpenSpec`) | CLI engine + chat steering wheel: `new change` → artifact loop → `validate` → implement → `archive` | `openspec/changes/<name>/{proposal,design,tasks}.md` + delta `specs/<cap>/spec.md`; merged into `openspec/specs/**` on archive | Delta grammar: `## ADDED/MODIFIED/REMOVED/RENAMED Requirements`, `### Requirement: <n>`, `#### Scenario: <n>` (exactly 4 hashes or "fails silently") | Per-artifact reload: `openspec instructions <artifact-id> --json` returns `context/rules/template/instruction` for one artifact at a time |
| **bmad** (`bmad-code-org/BMAD-METHOD` v6.12.0) | Agent activation → `bmad-build` dispatch → 5 step files → oneshot fast path | `spec-{slug}.md` (frozen Intent), `epics.md`, `epic-N-context.md`, `sprint-status.yaml`, `deferred-work.md` | Spec targeted at **900–1600 tokens**; `## I/O & Edge-Case Matrix` + `## Tasks & Acceptance` (`ship/bmad-build/spec-template.md`) | Two mechanisms: step files (`workflow.md`: "NEVER load multiple step files simultaneously") + a context-free implementation subagent handed only the spec (`step-03-implement.md`) |
| **superpowers** (`obra/superpowers` 6.3.0) | brainstorm → spec → writing-plans → subagent-driven-development → finish-branch | `docs/superpowers/specs/YYYY-MM-DD-*.md`, `plans/YYYY-MM-DD-*.md`, `.superpowers/sdd/<plan>/{progress.md,task-N-brief.md,review-*.diff}` | Per task: `**Files:**` + `**Interfaces:** Consumes/Produces` + 5 fixed checkbox steps (failing test → verify fail → minimal impl → verify pass → commit) | **Best in class.** `scripts/task-brief` awk-extracts one `### Task N` section; "Never make a subagent read the whole plan file" (`SKILL.md` ~262) |
| **get-shit-done** (`gsd-build/get-shit-done` v1.50) | new-project → discuss → plan → execute (waves) → verify → debug → complete-milestone | `.planning/{PROJECT,ROADMAP,STATE}.md`, `phases/{N}/{N}-{CONTEXT,PLAN-NN,SUMMARY,VERIFICATION,HUMAN-UAT}.md`, `debug/{slug}.md` | Plan frontmatter carries `wave`, `depends_on`, `files_modified`, `autonomous`, `requirements` | Fresh `gsd-executor` subagent per plan in a disposable worktree; documented budget "~15% orchestrator, 100% fresh per subagent"; `references/context-budget.md` rule 2: "Never inline large files into subagent prompts" |
| **ccpm** (`automazeio/ccpm`) | PRD → epic → numbered tasks → GitHub issues → worktree agents per stream | `.claude/prds/*.md`, `epics/<n>/{epic.md,NNN.md,github-mapping.md,execution-status.md,updates/<issue>/stream-A.md}` | Task frontmatter `depends_on`/`parallel`/`conflicts_with`; hard cap "Aim for ≤10 tasks total" (`references/plan.md:96`) | One `Task` subagent per parallel work stream, each writing its own `stream-<X>.md` |
| **agent-os** (`buildermethods/agent-os` v3.0) | Standards track (discover → index → inject) + thin product track (plan-product, shape-spec) | `agent-os/standards/index.yml` + `standards/**.md`, `product/{mission,roadmap,tech-stack}.md`, `specs/<ts-slug>/{plan,shape,standards,references}.md` | Standards: one concept per file, "lead with the rule." Spec/task breakdown **deliberately deleted in v3** — delegated to host plan mode | None |
| **conductor** (`gemini-cli-extensions/conductor`) | setup → new-track → implement → review → revert/status | `conductor/{index,product,tech-stack,workflow}.md`, `tracks.md`, `tracks/<id>/{spec,plan,metadata.json,index}.md` | Nested `- [ ]` phases/tasks + an appended `Phase Verification & Checkpoint` meta-task per phase | None — re-reads `workflow.md` (442 lines) in full every implement cycle |
| **kiro** (AWS, closed) | requirements(EARS) → design → tasks, each gated; steering always-on; JSON hooks | `.kiro/specs/<f>/{requirements,design,tasks}.md`, `.kiro/steering/*.md`, `.kiro/hooks/<id>.json` | EARS: `WHEN [event] THEN [system] SHALL [response]`; tasks capped at two levels (`1`, `1.1`), testing/deploy/docs tasks explicitly excluded | One task per interaction, "stop upon completion without auto-advancing" |
| **humanlayer-ace** (`humanlayer/humanlayer` `.claude/`) | research → plan → implement → validate → commit/PR; `ralph_*` variant drives it off Linear status | `thoughts/shared/research/YYYY-MM-DD-ENG-XXXX-*.md`, plan doc, handoff doc | Per phase: `#### Automated Verification:` as **literal shell commands** vs `#### Manual Verification:` (`create_plan.md:225-238`) | **Best in class.** Literally a new OS process per phase: `humanlayer-nightly launch --model opus … "/implement_plan …"` (`ralph_impl.md:31`) |
| **anthropic official** (`anthropics/claude-plugins-official`) | Independent single-purpose plugins; no cross-plugin orchestrator | feature-dev: none (chat only). ralph-loop: `.claude/ralph-loop.local.md`. hookify: `.claude/hookify.{rule}.local.md`. claude-security: SARIF | feature-dev is 7 phases in one 125-line prompt; code-review is a 8-step agent pipeline | Parallel lens subagents per phase; explorers must return "5-10 key files" that the **parent then reads itself** (`feature-dev/agents/code-explorer.md`) |
| **hooks-mastery** (`disler/…`, 3.9k★) | Not a pipeline — 13 lifecycle hooks + one `plan_w_team` multi-agent demo | `logs/*.json` per event, `.claude/data/sessions/<id>.json`, `specs/<name>.md` | The spec's 7 required headings are enforced by a Stop hook, not prose | Agent-scoped hooks in `agents/team/builder.md` frontmatter |
| **tdd-guard / checkwash** | Not a pipeline — a `PreToolUse` gate (tdd-guard) and a `Stop` gate (checkwash) | `.claude/tdd-guard/data/{test,todos,lint,config}.json`; `.greenwash/allow.toml` | n/a | n/a |

### 1b — Determinism, review, weight, packaging, verdict

| Framework | What is actually deterministic | Review mechanism | Prompt lines per main command | Packaging | Verdict |
|---|---|---|---|---|---|
| **spec-kit** | `scripts/bash/create-new-feature.sh` (numbering, `LC_ALL=C` slug, 244-byte GitHub truncation), `common.sh` (`get_feature_paths`, `resolve_template_content` 4-layer priority), `check-prerequisites.sh` (`--require-tasks`). Cross-language parity is **tested**: `tests/test_*_python_parity.py` | `/speckit.analyze` — **strictly read-only**, severity CRITICAL/HIGH/MED/LOW, 50-finding cap, must ask before fixing. Spec checklist is self-graded (no independent checker) | 2,437 across 10 command templates; **specify ~346, checklist ~379, tasks ~219**, each repeating ~35–40 lines of identical hook boilerplate (`specify.md:21-54` ≈ `clarify.md:21-54`) | PyPI `specify-cli`; renders into `.claude/skills/speckit-*/SKILL.md`; `extensions.yml` hooks; preset marketplace `presets/catalog.json` | **Borrow scripts + analyze + checklist framing.** 131 py files / 56k LOC / 41 agent integrations is the wrong shape |
| **openspec** | `validator.ts` (939 lines of cross-section conflict checks), `specs-apply.ts:buildUpdatedSpec` (fixed RENAMED→REMOVED→MODIFIED→ADDED order), `status --json` graph walk, `archive.ts:claimArchiveDestination` (`wx` lock + ownership nonce), `restoreSpecSnapshots` (byte-compare before rollback) | `openspec validate` only — structural, ERROR/WARNING/INFO tiers, strict mode toggles whether warnings fail. `findArchiveBlockers` calls the real merge in `{silent:true}` so preview can't drift from commit. **No LLM review anywhere** | propose skill 1,817 words + per-artifact schema instructions 1,547 + 4 templates 332 ≈ **3,700 words ≈ 5k tokens** for one propose→tasks pass | npm `@fission-ai/openspec`; 30 tool adapters; **no plugin.json** | **Borrow delta grammar + `schema.yaml` (graph + prose in one file) + dry-run-reuses-commit.** Ignore stores/initiatives/adapters |
| **bmad** | `render_skill.py` (401 lines, SHA-256 verified snapshot), `resolve_customization.py`, `sprint_plan.py` (697 lines + 524-line pytest, atomic temp+fsync+replace) | **Best in class.** `step-04-review.md`: N context-free lenses in parallel (Blind Hunter / Edge Case / Verification Gap) → triage re-verifies every claim → `high/med/low/false/maybe-false` → routes `patch/defer/intent_gap/bad_spec`; cap 5 loops; "Disregard any severity a reviewing subagent assigned" | `workflow.md` 84 + **one step file at a time (43–107)** ≈ 130–190 in context | Claude Code plugin, `.claude-plugin/plugin.json`, ~27 skills; `tools/installer/` ~16k lines JS; needs `uv`+Python 3.11 in the *target* repo | **Borrow step-files, frozen-intent, review lenses, script-for-state.** Skip TOML 3-layer merge, installer, v6-shims |
| **superpowers** | `hooks/session-start` (SessionStart injection), `scripts/{sdd-workspace,task-brief,review-package}` — that is all. Everything else is prose. Plus `scripts/lint-shell.sh` (shellcheck) + `tests/**` on its own bash | Fresh `task-reviewer` per task on a diff file; fix loop rounds 1–3 same implementer, 4–5 **fresh implementer on a stronger model**, then a "breaker" forcing fix-or-park-with-written-ruling; final whole-branch review. Template: Critical/Important/Minor + `Ready to merge? Yes\|No\|With fixes` | 63 injected per session; then **568 (subagent-driven-development) + 250 (brainstorming) + 320 (TDD)** — "1,000+ lines of skill prose" for one architectural task | `.claude-plugin/{plugin.json,marketplace.json}` + 8 other per-harness manifests | **Borrow the three scripts, the ledger, brief isolation, the fix ladder.** Skip the gate stack |
| **get-shit-done** | `hooks/gsd-read-injection-scanner.js` (PostToolUse, regex + invisible-Unicode), `gsd-workflow-guard.js` (soft), `gsd-validate-commit.sh` (**the only `decision:"block"`/exit 2 in the repo**), `gsd-sdk validate context`, `scripts/lint-command-contract.cjs` (CI: every `@`-ref resolves across 65 command files), `verify-tarball-sdk-dist.sh` | `gsd-plan-checker` check-revise-escalate, **cap 3 with stall detection** ("If the count does not decrease between consecutive iterations… break early"); fresh `gsd-verifier` checks the phase GOAL against ROADMAP success criteria, not task completion | `commands/gsd/execute-phase.md` 64 + `@`-included `workflows/execute-phase.md` **1,802** + 4 references ≈ **2,036+** | npm `get-shit-done-cc`; `bin/install.js` **11,376 lines**; 65 commands + 31 agents + ~9 hooks | **Borrow the two portable hooks, gate taxonomy, stall detection, `files_modified` overlap, STATE.md cap.** Ignore the product |
| **ccpm** | 12 working bash scripts in `references/scripts/` (status, next, blocked, epic-status…) answering every read-only query with grep+sed, zero LLM | **None.** No review phase exists | SKILL.md **82** + conventions 165 + one phase doc = **353–543** | No plugin.json, no npm. `ln -s .../skill/ccpm .claude/skills/ccpm` | **Borrow the thin router, the Script-First Rule table, frontmatter-as-dep-graph.** Ignore GitHub-issues-as-truth |
| **agent-os** | `project-install.sh`, `common-functions.sh:get_profile_inheritance_chain` (cycle detection), `sync-to-profile.sh:backup_files` (timestamped, before overwrite), `validate_not_in_base` | **None** | 1,147 across 5 commands; `shape-spec` 267 **plus every matched standard pasted in full — unbounded** | Shell installer only, no manifest | **Borrow index.yml indirection, profile inheritance, backup-before-overwrite, "Needs description" stubs.** Ignore the spec track (v3 deleted it itself) |
| **conductor** | `scripts/resume.py` — 54 lines of `os.path.exists`. That is the entire executable footprint | `conductor-review` diffs the track's commit range (chunked per file >300 lines), fixed report format, appends a `## Phase: Review Fixes` to plan.md with the fix SHA | `conductor-implement` SKILL 139 + `workflow.md` **442** + product/tech-stack + spec/plan ≈ **580 minimum protocol lines every resume** | `plugin.json` (4 lines) + `.claude-plugin/marketplace.json` | **Borrow resume.py, git-notes checkpoints, safe/hard revert plan, `CI=true`.** Ignore the rest |
| **kiro** | Approval is a **tool call** — `userInput(reason='spec-requirements-review')`; `.kiro/hooks/*.json` fire on IDE events; steering `inclusion: always\|fileMatch\|manual` parsed by the IDE | n/a | n/a | Closed IDE, not installable | **Reproduce two ideas only**: tool-call-gated approval, inclusion-mode-gated context |
| **humanlayer-ace** | `hack/create_worktree.sh` (fail-closed: tears the worktree down if `make setup` fails), `hack/spec_metadata.sh`, `hlyr thoughts` git hooks, `humanlayer launch` (new process per phase) | `/validate_plan` runs from git history + `make check test` + parallel verification subagents, **in a session that did not implement**; `describe_pr.md:41-48` only checks a PR checkbox after running the command | research 213 + create_plan **449** + implement 84 + validate 166 = **912**, + CLAUDE.md 88 ≈ 1,000 | Not a plugin — project-local `.claude/` checked into the monorepo | **Borrow split criteria, fresh-session-per-phase, handoff doc, no-open-questions rule.** Skip Linear/`--dangerously-skip-permissions` |
| **anthropic official** | `ralph-loop/hooks/stop-hook.sh` (session-id guard, numeric self-heal, literal `<promise>` compare, max-iter arithmetic); `security-guidance/hooks/hooks.json` `asyncRewake` on `Bash(git commit:*)`; `git stash create` diff baseline; `hookify/core/rule_engine.py`; `claude-security/scripts/lib/secret.py` (CWE-798 snippet redaction in code); `plugin-dev/skills/hook-development/scripts/validate-hook-schema.sh` | `code-review`: 5 parallel Sonnet lens agents → **a separate Haiku agent re-scores every issue 0–100 against a fixed 0/25/50/75/100 anchor rubric** → keep only ≥80 → abort silently if none survive → re-check eligibility → one `gh pr comment` | feature-dev **125**; code-review **92**; both single-file, no includes | `.claude-plugin/plugin.json` (only `name` is required — `manifest-reference.md:15`) + root `marketplace.json`; 291 entries: 53 local paths, 85 `git-subdir`, 153 `url` | **Steal the stop-hook loop, asyncRewake, the confidence filter, the stash baseline, the validators.** Ignore feature-dev (flow covers it) and security-guidance (7.7k lines, needs an API key) |
| **hooks-mastery** | `pre_tool_use.py` (rm -rf / `.env` regex → `sys.exit(2)`), `validators/{validate_new_file,validate_file_contains,ruff_validator,ty_validator}.py`, `tts_queue.py` lock, `pre_compact.py` backup, `session_start.py` `additionalContext` | `validator` agent is only denied `Write/Edit`; its verdict is free text — **not machine-checked** | n/a (hooks, not prompts) | Copy `.claude/` into your repo. No manifest | **Steal the blocklist, `validate_file_contains`, the agent-scoped lint gate, PEP-723 `uv run --script`, PreCompact backup.** Ignore TTS/narration/13-event logging |
| **tdd-guard / checkwash** | tdd-guard: `testCounter.ts` (ast-grep, 6 languages), `isAllowedTestAddition` short-circuit, `validator.ts` multi-strategy JSON extraction, JSON-stdout-with-exit-0 protocol. **checkwash: 100% deterministic, zero LLM** — 12 AST detectors + `gating.py:_repair_evidence` (a weakened assertion is only a violation if no prod change explains it) | tdd-guard's verdict is an LLM judge (in-process Agent SDK, `maxTurns:1`). checkwash's is a gating table (D1–D3/E1–E2 escalators) | tdd-guard: **~190–210 lines of fixed prompt on every Edit/Write** that misses the short-circuit | tdd-guard: npm + `plugin/.claude-plugin/plugin.json` + marketplace. checkwash: PyPI + `checkwash hook install --agent claude-code --local` | **Install checkwash as a Stop hook.** Steal tdd-guard's *plumbing* (short-circuit ordering, JSON protocol, tolerant parser); skip its LLM gate |

---

## 2. Patterns that recur across 3+ frameworks

These are the de-facto standards. "flow has it?" is judged against `flow/SKILL.md`, `flow/planning.md`, `feature/execution-prompt.md`.

| # | Pattern | Frameworks | Best implementation | flow has it? |
|---|---|---|---|---|
| 1 | **The plan file is the progress tracker** — checkboxes edited in place, trusted over conversation on resume | superpowers, humanlayer, conductor, gsd, ccpm, kiro, bmad, openspec | `humanlayer/.claude/commands/implement_plan.md:12,49,79-82` — "check for any existing checkmarks… Trust that completed work is done, pick up from the first unchecked item" | **Yes.** `flow/SKILL.md:54` (Phase 0.1 resume) + `planning.md:120-122` Progress section |
| 2 | **Fresh context per task; the subagent gets a brief, never the plan** | superpowers, bmad, gsd, humanlayer, ccpm, anthropic feature-dev | `superpowers/skills/subagent-driven-development/scripts/task-brief` (awk, fence-aware, extracts one `### Task N`) | **Intent only.** `flow/SKILL.md:169` states it; `orchestration.md` pastes a contract block by prose. No script cuts the brief |
| 3 | **The reviewer never shares context with the writer; multiple biased lenses beat one generalist** | bmad, superpowers, anthropic code-review + feature-dev, gsd, humanlayer | `bmad/src/bmm-skills/ship/bmad-build/step-04-review.md` — parallel context-free lenses, then a triage pass that must re-locate every claim in the code before accepting it | **Partial.** 4-dim swarm exists (`SKILL.md:190`); "scanner ≠ fixer ≠ verifier" is prose with nothing behind it (SKILL.md:24 admits this) |
| 4 | **Bounded fix loop with an escalation trigger and a terminal recorded decision** | superpowers (5 rounds, escalate at 4, "breaker"), bmad (cap 5 + carried verdicts), gsd (cap 3 + stall detection), anthropic ralph (max-iterations) | `gsd/get-shit-done/references/revision-loop.md` — "If the count does not decrease between consecutive iterations, the producing agent is stuck… Break early and escalate" | **Weak.** Flat "2 fix attempts per finding, then requires human review" (`SKILL.md:190`); "3 attempts" in `execution-prompt.md:30`. No stall detection, no escalation to a stronger model, no ruling record |
| 5 | **Numbering, paths, state and ordering belong to a script, never to the model** | spec-kit, ccpm, bmad, gsd, conductor, agent-os, openspec, superpowers | `spec-kit/scripts/bash/create-new-feature.sh` + `common.sh:get_feature_paths/_persist_feature_json` — collision-safe numbering, `LC_ALL=C` slug, 244-byte truncation, pointer file | **No.** `flow/SKILL.md:101` asks the model to compute `<NNN> = max existing + 1`. `shared/scripts/{check-all,detect-project,test-changed}` exist but nothing owns paths/numbering |
| 6 | **Progressive disclosure: a thin router + step/reference files, one at a time** | ccpm (82-line router), bmad ("NEVER load multiple step files simultaneously"), spec-kit, gsd, superpowers, agent-os | `ccpm/skill/ccpm/SKILL.md` (82 lines) — `**When**:` / `**Read**: \`references/structure.md\`` per phase | **No.** 266-line SKILL.md with ~9 "MANDATORY — READ ENTIRE FILE" directives; 1,787 lines on a Medium run |
| 7 | **Success criteria split into automated (literal shell commands) vs manual, per phase** | humanlayer, gsd (VERIFICATION/HUMAN-UAT), conductor, kiro, superpowers | `humanlayer/.claude/commands/create_plan.md:225-238` — `- [ ] Migration applies cleanly: \`make migrate\`` vs `- [ ] Feature works as expected when tested via UI` | **Partial.** Browser + User Verification Steps exist, but only once at the end (`planning.md:89-94`), not per slice |
| 8 | **A hard human approval gate before implementation** | superpowers `<HARD-GATE>`, bmad CHECKPOINT 1, anthropic feature-dev Phase 5, kiro, conductor, agent-os | **kiro only makes it real**: a `userInput` tool call with a fixed `reason` enum. Everyone else's is prose the model can walk past | **Yes, twice** (`SKILL.md:157,192`) — and, like everyone but kiro, unenforced |
| 9 | **A structured artifact grammar validated by code, not by the author re-reading it** | openspec (`validator.ts`), hooks-mastery (`validate_file_contains.py`), gsd (`lint-command-contract.cjs`), spec-kit (format rule — *stated but never parsed*) | `hooks-mastery/.claude/commands/plan_w_team.md` frontmatter — a **command-scoped `Stop` hook chain** that re-runs the command until `specs/*.md` exists containing all 7 required headings | **No.** `planning.md:104-114` is a 10-item checklist the model self-grades |
| 10 | **Severity buckets + an explicit verdict enum, fixed in the template** | superpowers (Critical/Important/Minor + `Ready to merge?`), bmad (high/med/low/false/maybe-false), spec-kit (CRITICAL→LOW, 50 cap), openspec (ERROR/WARNING/INFO), anthropic (0–100 → ≥80) | `anthropic/plugins/code-review/commands/code-review.md` — a **separate** agent re-scores each finding against 0/25/50/75/100 anchors; "Filter out any issues with a score less than 80" | **Partial.** `.claude/quality/*.md` schema has verdict + severity + confidence as separate fields (`SKILL.md:190`) but no threshold and no independent re-scorer |
| 11 | **An explicit, auditable opt-out marker instead of a gate the model games** | openspec (`skip_specs: true` + "Do not invent a requirement just to satisfy validation"), checkwash (`allow.toml` with `reason`/`author`/`expires`), gsd (`.planning/config.json`), agent-os ("Needs description" stub) | `checkwash/.greenwash/allow.toml` — fingerprint-scoped, time-boxed, **self-expiring**; plus `EXEMPTION_ADDED` fires when one diff both trips a rule and adds its own exemption | **No.** flow's "say you skipped it" (`SKILL.md:27`) is prose with no artifact |
| 12 | **Read-time / write-time hooks are the only thing that actually stops anything** | gsd (1 of ~9 hooks blocks), anthropic (ralph Stop, security asyncRewake), hooks-mastery (pre_tool_use exit 2), tdd-guard, checkwash, kiro | `hooks-mastery/.claude/hooks/pre_tool_use.py` — regex → `sys.exit(2)`, "exit code 2 blocks the tool call and shows Claude the error" | **No.** Zero hooks wired (SYNTHESIS §3 row 1) |

**The through-line:** every framework here converges on 1, 2, 3, 5, 6 and diverges only on ceremony. flow already has 1 and 8; its gaps are exactly 2 (no brief script), 3 (isolation unenforced), 5 (model does arithmetic), 6 (no progressive disclosure), 9 (self-graded plan), 12 (no hooks).

---

## 3. Steal list

Ordered by value ÷ effort. "Adds/replaces" is against `~/.claude/skills/flow/`, `~/.claude/skills/feature/`, or `~/.dotfiles/claude/.claude/hooks/`.

---

**S1 — `slice-brief` + `review-package` scripts (S)**
Source: `superpowers/skills/subagent-driven-development/scripts/task-brief`, `scripts/review-package`, `scripts/sdd-workspace`.
Copy: `task-brief` is an awk fence-aware scan for a `# Task N` heading; `review-package` is three lines —
```bash
git log --oneline "${base}..${head}" > "$out"
git diff --stat "${base}..${head}" >> "$out"
git diff -U10 "${base}..${head}" >> "$out"   # "The output never enters your own context."
```
Adapt to cut slice N + its `## Contract for this slice` block out of `.claude/feature-plan.local.md` into `.claude/slices/<n>-brief.md`, and to build a base..head diff file for a reviewer.
Replaces: `flow/SKILL.md:169` ("each slice executes in its own fresh context") and `orchestration.md`'s prose instruction to paste a contract block — the highest-value prose→script conversion available. Also fixes the `HEAD~1` class of bug superpowers calls out (`scripts` require an explicit BASE + `git rev-parse --verify`).

**S2 — `skills-lint`: every path reference in every SKILL.md must resolve (S)**
Source: `get-shit-done/scripts/lint-command-contract.cjs` — "every `@`-reference resolves to an existing file on disk… Exit 0 = clean. Exit 1 = violations," across all 65 command files.
Adapt: a ~40-line script walking `~/.claude/skills/*/**.md` for `.claude/skills/...` and `~/.claude/skills/...` paths and `command -v` claims, failing on the first miss.
Adds: catches exactly the dead-reference class SYNTHESIS §3 row 9 found (`better-plan` at `flow/SKILL.md:159`, `rtk`, the `.claude/skills/shared/scripts/*` chain). Run it from `run-maintenance` or a pre-commit in the dotfiles repo.

**S3 — Artifact-shape Stop gate on the plan and spec files (S)**
Source: `hooks-mastery/.claude/hooks/validators/{validate_new_file.py,validate_file_contains.py}` wired as **command-frontmatter Stop hooks** in `.claude/commands/plan_w_team.md`:
```yaml
hooks:
  Stop:
    - hooks:
        - type: command
          command: >-
            uv run $CLAUDE_PROJECT_DIR/.claude/hooks/validators/validate_file_contains.py
            --directory specs --extension .md
            --contains '## Task Description' --contains '## Acceptance Criteria' ...
```
Adapt: one generic `hooks/artifact-gate.sh --file .claude/feature-plan.local.md --contains '## Behavior Inventory' --contains '### Slice 1 — RED' …`, registered in **skill frontmatter** so it only arms during a flow run and self-removes.
Replaces: `flow/planning.md:104-114`'s self-graded 10-item validation checklist — pattern 9. Cap the retry (hooks-mastery has none; Claude Code force-overrides at 8 blocks anyway).

**S4 — checkwash as a Stop hook (M — install, not build)**
Source: `checkwash` (PyPI), `checkwash hook install --agent claude-code --local` writes `{"type":"command","command":"checkwash check --format hook-json"}` into `.claude/settings.local.json`'s `hooks.Stop`.
Why this one and not tdd-guard: zero LLM, zero prompt cost, and `gating.py:_repair_evidence` gates every "assertion weakened" finding on whether prod code actually changed — so honest refactors don't trip it. Detectors that matter here: `EXPECTATION_DEFINITION_CHANGED`, `TEST_DISABLED`, `GUARDRAIL_TOUCHED` (severity `critical` only when an *existing* guardrail is relaxed, per `gating.py:502-507`), `IMPORT_UNRESOLVED` ("hallucination fingerprint", `detectors/globals_rules.py`).
Enforces: `flow/SKILL.md:24` "never edit a test to go green" and `execution-prompt.md:77` — currently the single most load-bearing prose invariant in the whole harness. Pair with `.greenwash/allow.toml`'s expiring, fingerprinted exemptions (pattern 11).

**S5 — `new-spec`: deterministic numbering, slug, branch, pointer file (S)**
Source: `spec-kit/scripts/bash/create-new-feature.sh` (`clean_branch_name()` uses `LC_ALL=C` "so a name of `-n`/`-e`/`-E` is text, not options"; `fit_branch_name()` truncates to 244 bytes) + `common.sh:_persist_feature_json` writing `.specify/feature.json`, read priority `env > file > error`.
Replaces: `flow/SKILL.md:101` ("`<NNN>` = max existing + 1, or `001`") and `SKILL.md:78`'s hand-built worktree command. Emits `.claude/flow.json` = `{"spec_dir": ".specs/003-user-auth", "branch": "flow/user-auth", "worktree": "…"}` for Phase 0.1 resume to read instead of re-deriving from git.
Portability note: keep the `$(git rev-parse --show-toplevel)` anchoring flow already got right, avoid BSD-only `stat` flags.

**S6 — Fix loop: escalation ladder + stall detection + carried verdicts (S)**
Source, three parts:
- `superpowers/skills/subagent-driven-development/SKILL.md` §"The fix loop": rounds 1–3 resume the same implementer, **4–5 dispatch a fresh implementer on a more capable model**, then a "breaker" forces fix-or-park-with-a-written-ruling — "a silent discard is forbidden."
- `gsd/get-shit-done/references/revision-loop.md`: break early when the finding count stops decreasing.
- `bmad/.../step-04-review.md:33`: a persisted `## Review Triage Log`; an unchanged finding gets its verdict re-written with `carried` and is never re-litigated.
Replaces: `flow/SKILL.md:190` "2 fix attempts per finding, then requires human review" and `execution-prompt.md:30-31`. Costs three sentences of prose in `flow/review.md` and one table in the plan file.

**S7 — Independent confidence re-score with anchored rubric before a finding counts (S)**
Source: `anthropic/plugins/code-review/commands/code-review.md` steps 4–6: 5 lens agents produce `(issue, reason-flagged)`, then **one separate agent per issue** re-scores 0–100 against a fixed 0/25/50/75/100 anchor table; "Filter out any issues with a score less than 80. If there are no issues that meet this criteria, do not proceed."
Adds to: flow Phase 5.3. Directly addresses the 78%-false-positive number flow already cites at `SKILL.md:190` — and enforces "scanner ≠ verifier" structurally (a different agent scores) rather than by prose. Give the anchor definitions verbatim; a bare "rate your confidence" clusters at the top.

**S8 — Per-slice automated vs manual criteria, as literal commands (S)**
Source: `humanlayer/.claude/commands/create_plan.md:225-238`. Plus `describe_pr.md:41-48` — a checklist box is checked **only after running the command**, manual-only items stay unchecked.
Changes: `flow/planning.md:60-98` — move `#### Automated Verification:` (real `$TEST_CMD`/`$E2E_CMD` invocations) and `#### Manual Verification:` into each slice's block, not just the terminal gate list. Makes a slice resumable by a session that never saw the conversation, and makes `S3`'s artifact gate able to check for them.

**S9 — Ledger with ruling lines and a hard size cap (S)**
Source: `superpowers/skills/subagent-driven-development` ledger format —
```
Ruling: <what you decided> — <why> — <what it costs if wrong>
Task <N>: complete (commits <a7>..<b7>, review clean)
Task <N>: parked — <finding> — Ruling: <why the code stands>
```
"after compaction, trust the ledger and `git log` over your own recollection" — plus `gsd/get-shit-done/templates/state.md`: "Keep STATE.md under 100 lines… a DIGEST, not an archive."
Upgrades: `.claude/workflow-state.local.md`'s Progress section (`planning.md:120-122`) — it already tracks checkboxes+SHAs; add ruling lines for every parked finding and a 100-line cap.

**S10 — Agent-scoped `PostToolUse` lint gate via frontmatter (S)**
Source: `hooks-mastery/.claude/agents/team/builder.md` frontmatter —
```yaml
hooks:
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: uv run $CLAUDE_PROJECT_DIR/.claude/hooks/validators/ruff_validator.py
```
with the validator emitting `{"decision":"block","reason":"Lint check failed:\n…"}`.
Adds: scope SYNTHESIS §5's `format-lint.sh` to the *build subagent* rather than every tool call in every session. Cheaper, and it puts the gate exactly where unattended writing happens.

**S11 — `files_modified` overlap pre-flight before any parallel wave (S)**
Source: `gsd/get-shit-done/workflows/execute-phase.md` step `execute_waves`: `seen_files = {}; for each plan in wave_plans: for each file in plan.files_modified: if file in seen_files: overlapping_plans.add(...)` → forces that wave sequential.
Adds: a `scripts/slice-overlap` called before flow Phase 4's "subagent waves ≤4" (`SKILL.md:180`) and before any `ultracode` fan-out. This is the mechanism behind SYNTHESIS §1.8's "failures cluster at unowned interfaces" — turned into a check.

**S12 — Frozen-after-approval intent block (S)**
Source: `bmad/src/bmm-skills/ship/bmad-build/spec-template.md` — `<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">` wrapping `## Intent`; every later step re-states "Content inside `<frozen-after-approval>`… is read-only."
Adds to: the spec's problem statement and the plan's Behavior Inventory. Unlike bmad's version this one is **greppable**, so `S3`'s artifact gate can hash the block at approval time and block a Stop if it changed — turning flow's "NEVER add scope beyond the approved plan" (`SKILL.md:242`) into a check.

**S13 — Background commit review via `asyncRewake` + `git stash create` baseline (M)**
Source: `anthropic/plugins/security-guidance/hooks/hooks.json` —
```json
{ "if": "Bash(git commit:*)", "asyncRewake": true,
  "rewakeMessage": "Background security review of commit — address or acknowledge the findings below…",
  "rewakeSummary": "Commit security review found issues" }
```
and `hooks/security_reminder_hook.py`'s baseline trick: `git stash create` yields a commit-object SHA for the working tree **without stashing anything**, captured at `UserPromptSubmit` and diffed at `Stop`, so an expensive check only ever sees this session's delta.
Adds: an out-of-band reviewer that never blocks a commit but can wake the session with findings — the cheapest way to get pattern 3's independent reviewer without adding a gate.

**S14 — `CI=true` / non-interactive rule for every test and lint invocation (XS)**
Source: `conductor/skills/conductor-setup/assets/workflow.md`, Guiding Principle 6 — "Prefer non-interactive commands. Use `CI=true` for watch-mode tools (tests, linters) to ensure single execution."
Adds: one line to `shared/scripts/check-all` and `test-changed`. An agent that runs a watch-mode `npm test` hangs until the turn dies — a real failure mode with a one-word fix.

**S15 — PreCompact transcript backup (S)**
Source: `hooks-mastery/.claude/hooks/pre_compact.py:backup_transcript` — `shutil.copy2(transcript_path, backup_dir / f"{session}_pre_compact_{trigger}_{ts}.jsonl")`.
Adds: `~/.claude/hooks/pre-compact-backup.sh` writing to `~/.claude/transcript-backups/`. Zero model involvement, costs nothing, and gives a recovery path for exactly the long `/flow` and `/ultracode` runs where compaction bites.

---

## 4. What NOT to copy

Each with the code that shows why.

**Prose-as-hook.** spec-kit's entire extension mechanism asks the model to emit `EXECUTE_COMMAND:` and then actually run it — its own instruction says *"Emitting the block alone does not run the hook,"* a tell that this has failed before. Only the separate `workflow.yml` path (`type: gate`, `on_reject: abort`) enforces anything. If flow wants hooks, they go in `settings.json`.

**The `<promise>` honor system — and flow already has it.** `anthropic/plugins/ralph-loop/hooks/stop-hook.sh:174` literally reads *"ONLY when statement is TRUE - do not lie to exit!"*; the script does a literal string compare and nothing verifies truth. `feature/execution-prompt.md:271` currently ends with `Output <promise>FEATURE COMPLETE</promise>` — a completion signal with zero evidence behind it. Replace it with the Stop gate re-running `check-all` (SYNTHESIS §5) — a real check, not an assertion.

**LLM-judging every edit.** tdd-guard assembles `SYSTEM_PROMPT` + `RULES` (59) + `FILE_TYPES` (50) + operation prompt + `RESPONSE` (35) ≈ **190–210 lines of fixed prompt before any diff** on every Edit/Write that misses its AST short-circuit, and a malformed response makes `validator.ts` throw and block spuriously. checkwash gets the same invariant for zero prompt tokens.

**Duplicated command bodies.** spec-kit repeats ~35–40 lines of hook boilerplate verbatim across 10 command files (`specify.md:21-54` ≈ `clarify.md:21-54`); humanlayer ships `create_plan.md` / `_nt.md` / `_generic.md` at 449/442/439 lines; bmad ships three independently-drifted copies of "edge case hunter" (`bmad-build/review-prompts/`, `bmad-code-review/review-prompts/`, `core-skills/bmad-review/references/`) that `diff` already shows diverging. flow's `NEVER duplicate the referenced files into this skill` rule (`SKILL.md:240`) is correct — keep it.

**Always-reloaded standing context.** conductor's `conductor-implement` pulls SKILL 139 + `workflow.md` **442** + product docs + spec + plan ≈ **580 lines of pure protocol every time implementation resumes**. gsd's `/gsd:execute-phase` loads **2,036+**. This is the failure flow v2 must not repeat.

**Gate density for a solo dev.** bmad's dispatch route has six blocking human decisions minimum (VCS dirty HALT, multi-goal split, token count, open questions, CHECKPOINT 1's 3-way choice, loop cap). agent-os's `/discover-standards` explicitly forbids batching — N standards = N sequential Q&A loops, no unattended mode. anthropic's feature-dev mandates 7 phases and ≥8 subagent launches with no scale-down path for a one-line feature. flow's two gates plus its "Run components by value" doctrine (`SKILL.md:20-27`) is already better calibrated than all three.

**Three-layer config merges.** bmad's `customize.toml` → `_bmad/custom/*.toml` → `*.user.toml` with a documented merge algebra ("arrays of tables keyed by `code` or `id` replace matching entries and append new entries") serves teams. One user, two machines, one stow tree: two of the three layers are dead weight.

**Runtime dependencies pushed into every target repo.** bmad needs `uv` + Python 3.11 (`tomllib`) present in the *consumer* project just to run its own bookkeeping. Any hook flow adds must degrade with `command -v` guards, not require a toolchain a Rust or Go repo doesn't have.

**Generated installers, and what they rot into.** gsd's `bin/install.js` is **11,376 lines** and the installed copy here is v1.5.15 against upstream v1.50.0 — 45 minors of upgrade friction, already realized. ccpm's own `init.sh`, `help.sh`, and `validate.sh` still scaffold `.claude/rules` and print `/pm:prd-new`/`/pm:clean` — commands that no longer exist in that repo — so a fresh run prints a spurious warning and points at nothing. Generated setup code rots faster than the prompts it installs.

**Model-redone deterministic work.** openspec has a 1,108-line `specs-apply.ts` doing the delta merge, and then an "experimental" skill (`skills/openspec-archive-change/SKILL.md`) that re-does the same merge via "agent-driven intelligent merge." Two implementations of one operation, one deterministic and one prompted, that must stay behaviorally equivalent forever.

**Curated fan-out without ownership.** ccpm's parallel `Task:` blocks are illustrative YAML in a prompt, not a scheduler; conflict resolution is "agents report and pause" with no lock (`execute.md:209`), and its own `structure.md:105` asserts "Circular dependencies are an error — check before finalizing" while no script ever walks the graph (a cycle passes `validate.sh` and silently deadlocks `next.sh`). If flow fans out, S11's overlap check is the minimum bar.

**kiro entirely.** Closed IDE; its hooks fire only on agent-made file changes, not manual edits. Only the two ideas in §1b are portable.

---

## 5. Proposed flow v2 skeleton

Layout under `~/.dotfiles/claude/.claude/` (all of it stowed into `~/.claude/`, which today only `skills/`, `agents/`, `commands/`, `settings.json` are).

```
claude/.claude/
├── settings.json                     hooks key from SYNTHESIS §5 + skillListingBudgetFraction
├── CLAUDE.md                         ~25 lines (SYNTHESIS §6), STOWED — currently is not
├── hooks/
│   ├── lib/hookout.sh                JSON-stdout helpers; always exit 0 unless deliberately blocking
│   │                                   ← anthropic examples/hooks/bash_command_validator_example.py + tdd-guard cli/tdd-guard.ts
│   ├── session-context.sh            SessionStart: branch, dirty count, PROGRESS.md head  ← hooks-mastery session_start.py
│   ├── git-guard.sh                  PreToolUse/Bash: destructive-command deny            ← hooks-mastery pre_tool_use.py + gsd gsd-validate-commit.sh
│   ├── format-lint.sh                PostToolUse/Edit|Write: format then lint, exit 2 with remediation text  ← hooks-mastery ruff_validator.py
│   ├── size-guard.sh + size_guard.py PostToolUse: file/function length teaching signal    ← SYNTHESIS §5
│   ├── stop-gate.sh                  Stop: re-run check-all; stop_hook_active + 8-block aware  ← anthropic ralph-loop/hooks/stop-hook.sh
│   ├── stop-tamper.sh                Stop: checkwash check --format hook-json             ← checkwash (S4)
│   ├── artifact-gate.sh              Stop (skill-scoped): required headings + frozen-block hash  ← hooks-mastery validate_file_contains.py (S3, S12)
│   └── pre-compact-backup.sh         PreCompact: copy transcript out                      ← hooks-mastery pre_compact.py (S15)
├── scripts/                          invoked by skills; stdout only, source never enters context
│   ├── new-spec                      numbering + slug + branch + worktree + .claude/flow.json  ← spec-kit create-new-feature.sh + common.sh (S5)
│   ├── slice-brief                   cut slice N + its contract block → .claude/slices/<n>-brief.md  ← superpowers task-brief (S1)
│   ├── review-package                base..head log+stat+diff -U10 → a file path          ← superpowers review-package (S1)
│   ├── slice-overlap                 files_modified collision check before a wave         ← gsd execute-phase execute_waves (S11)
│   ├── plan-lint                     structural validation of feature-plan.local.md       ← openspec validator.ts + flow planning.md:104-114 (S3)
│   └── skills-lint                   every path/@ref under skills/ resolves               ← gsd lint-command-contract.cjs (S2)
└── skills/flow/
    ├── SKILL.md                      router: invariants, size table, gate manifest, step index  ← ccpm SKILL.md (82-line router)
    ├── steps/00-setup.md             resume via flow.json, detect, classify, mode, branch   ← conductor resume.py + bmad step-01
    ├── steps/01-spec.md              adaptive discovery, question caps, spec write         ← spec-kit clarify.md bounded loop
    ├── steps/02-judge.md             single harsh pass, opt-in per SYNTHESIS §6            ← spec-kit analyze.md (read-only, capped, severity-tagged)
    ├── steps/03-plan.md              slices + Behavior Inventory + per-slice criteria + approval  ← humanlayer create_plan.md
    ├── steps/04-build.md             per-slice: slice-brief → subagent → review-package    ← superpowers subagent-driven-development
    ├── steps/05-verify.md            inline gates, browser, user gate                      ← flow today, minus what hooks now own
    ├── steps/06-pr.md                draft → re-verify → ready                             ← humanlayer describe_pr.md (only check a box you ran)
    ├── planning.md                   slice rules + inventory + per-slice automated/manual  ← humanlayer create_plan.md:225-238 (S8)
    ├── review.md                     lens registry, triage log, carried verdicts, fix ladder  ← bmad step-04 + superpowers fix loop + anthropic ≥80 (S6, S7)
    └── orchestration.md              mode sections only, unchanged
```

`flow-deepen` stays a separate skill invoked after merge (SYNTHESIS §6). `feature/execution-prompt.md` shrinks to ~80 lines: the Red/Green exit-code gates and the "no test edits in Green" rule are now enforced by `stop-gate.sh` + `stop-tamper.sh`, so the prompt keeps only the state-restoration contract and the phase dispatch.

### Keeping a Medium run under ~900 lines

| Loaded on a Medium run | Lines | Was |
|---|---|---|
| `flow/SKILL.md` (router) | 180 | 266 |
| `steps/00` + `01` + `02` + `03` + `04` + `05` + `06` | 7 × ~70 = 490 | — |
| `planning.md` | 110 | 122 |
| `review.md` (Phase 5 only) | 90 | quality-gates.md, external |
| `orchestration.md` — **one mode section only** | 60 | 213 |
| `feature/execution-prompt.md` | 80 | 271 |
| **Total** | **~1,010** → **~860 with §6's cuts** | 1,787 |

Five levers, in order of size:
1. **Router + step files, one at a time** (pattern 6, bmad's "NEVER load multiple step files simultaneously"). A Small run reads 00, 01, 03, 04, 05 — never 02 or 06's PR machinery until it gets there.
2. **Hooks absorb four invariant blocks.** The Red/Green exit-code paragraphs, "never edit a test to go green," the size discipline, and the artifact checklist all become one referring sentence each because a hook enforces them. That is ~150 lines of prose deleted, not moved.
3. **Nine `MANDATORY — READ ENTIRE FILE` directives → three.** Each one today is a line the model can silently not act on and no output reveals it (SYNTHESIS §3 row 5).
4. **`orchestration.md` already says to read only the chosen mode's section** (`SKILL.md:47`) — make that structural by splitting it into three files so the other 130 lines cannot leak in.
5. **Delete the dead branches**: the `better-plan` block (`SKILL.md:159`, CLI not installed), the routing matrix (duplicates orchestration.md), and the unattended table's restatements of rules stated elsewhere.

---

## 6. Plugin packaging

**Recommendation: split. Keep the core harness stowed. Package the domain skills as a private local marketplace.**

### What the code shows a plugin buys

- **Near-zero manifest cost.** Only `name` is required (`plugins/plugin-dev/skills/plugin-structure/references/manifest-reference.md:15`; "Relies entirely on default directory discovery"). conductor's entire `plugin.json` is 4 lines. Components are found by convention — `commands/*.md`, `agents/*.md`, `skills/<n>/SKILL.md`, `hooks/hooks.json`.
- **`${CLAUDE_PLUGIN_ROOT}`** — the path-substitution variable every marketplace hook uses to locate its own scripts regardless of install location. This is the mechanism that makes a plugin's hooks portable in a way `$HOME/.claude/hooks/...` is not.
- **Per-project enablement.** A marketplace lets you enable `tomas-finance` only inside the repo that needs it. This is the *only* mechanism that delivers SYNTHESIS §6's biggest win — moving ~20 domain skills out of the global listing that currently costs 12,493 tokens every session and overflows the 1%-of-context budget.
- **Local sources work.** `claude-plugins-official/.claude-plugin/marketplace.json` uses relative `"./plugins/agent-sdk-dev"` paths for 53 of its 291 entries; a git-subdir or url pin is only needed for third-party code.

### What it costs, from the same code

- **Path references break.** `flow/SKILL.md` hard-codes `.claude/skills/flow-spec/references/question-bank.md`, `.claude/skills/feature/execution-prompt.md`, `.claude/skills/shared/scripts/check-all` and six more (lines 57, 89, 101, 146, 171, 189, 190, 218). Moving flow into a plugin means rewriting every one to `${CLAUDE_PLUGIN_ROOT}/…` and re-verifying them — for zero functional gain, since these skills should load in every repo anyway.
- **Distribution is already solved.** stow gives live-edit across both machines with no install step. conductor documents the same symlink trick as its own live-dev mode (`~/.gemini/config/plugins/conductor`). A plugin adds `/plugin install` friction to reach parity.
- **Installers rot.** bmad's `tools/installer/` is ~16k lines; gsd's `bin/install.js` is 11,376; ccpm's three install/validate scripts still reference a retired command surface. None of that is *required* by the plugin format — but it is what every framework here ended up writing once it shipped one.

### Recommended structure (domain skills only)

```
~/.dotfiles/claude-plugins/                       # its own git repo, NOT stowed
├── .claude-plugin/marketplace.json               # {name, owner, plugins:[{name, source:"./plugins/<n>"}]}
│                                                 #   ← anthropics/claude-plugins-official marketplace.json, local-source form
└── plugins/
    ├── tomas-finance/.claude-plugin/plugin.json  # skills/{alpha-hunt,portfolio,investment,etoro}
    ├── tomas-aws/.claude-plugin/plugin.json      # skills/{aws-explore,aws-lambda-microvms,strands-agentcore,
    │                                             #          strands-steering-hooks,agui-strands,sst}
    ├── tomas-web/.claude-plugin/plugin.json      # skills/{seo-audit,google-ads,figma-to-strapi,website-cloner}
    └── tomas-lang/.claude-plugin/plugin.json     # skills/{icelandic-professor,worklog,rag-guide,cocoindex}
```

Install once per machine: `/plugin marketplace add ~/.dotfiles/claude-plugins`, then enable a bundle only in the projects that need it. Each `plugin.json` needs `{"name": "tomas-finance"}` and nothing else.

**Do not** package `flow`, `flow-spec`, `feature`, `shared`, `qa`, `audit`, `ultracode`, or `hooks/` — they must be present in every repo, their cross-references are absolute paths today, and stow already delivers them to both machines. Revisit only if a second person ever needs this harness.

---

## Executive summary

1. Thirteen frameworks converge on six mechanisms; flow has two of them (durable plan-as-tracker, human approval gates) and states four more as prose it cannot enforce.
2. The gap is never design — flow's doctrine is better calibrated than bmad's six gates, agent-os's no-batch interview, or feature-dev's fixed 7 phases. The gap is that nothing executes it.
3. Highest-value steal is the smallest: `superpowers/scripts/{task-brief,review-package}` — ~40 lines of awk/git that turn flow's "each slice runs in its own fresh context" from an intention into a file path.
4. Install `checkwash` as a Stop hook: zero LLM, zero prompt cost, and it deterministically enforces "never edit a test to go green" — the single most load-bearing prose rule in the harness.
5. Delete `Output <promise>FEATURE COMPLETE</promise>` from `feature/execution-prompt.md:271` — that is ralph-loop's honor system ("do not lie to exit", `stop-hook.sh:174`), an assertion with no evidence behind it.
6. Move numbering, slugs, branches and resume state into one `new-spec` script (spec-kit's `create-new-feature.sh` + `feature.json` pointer); the model should never compute `<NNN> = max existing + 1`.
7. Upgrade the fix loop with superpowers' escalation ladder, gsd's stall detection and bmad's carried triage verdicts — three sentences replacing "2 attempts then human review."
8. Adopt ccpm's thin-router + bmad's one-step-file-at-a-time structure: 266-line SKILL.md → a 180-line router plus seven ~70-line steps, and a Medium run drops 1,787 → ~860 loaded lines.
9. Copy nothing that asks the model to run its own hook, re-do a deterministic merge, or re-load 400+ lines of standing protocol per cycle — spec-kit, openspec and conductor each demonstrate that failure in their own code.
10. Package only the ~20 domain skills as a private local marketplace (`{"name": "..."}` is the whole manifest); leave the core harness stowed, because its absolute `.claude/skills/...` references would all have to become `${CLAUDE_PLUGIN_ROOT}` for no gain.
