# conductor-and-kiro

## What it is

Conductor (`gemini-cli-extensions/conductor`) is a Claude Code / Antigravity plugin — six markdown "skills" (system prompts, no code) that turn an agent into a spec-driven project manager: setup → new-track (spec+plan) → implement → status/revert/review, all state persisted as files inside a `conductor/` directory in the target repo. 3.7k stars, 293 forks (GitHub page). Latest commit in the shallow clone: `6e8f9a8` on 2026-09-01. Kiro is AWS's closed-source agentic IDE; its "Spec-Driven Development" feature generates `requirements.md` (EARS syntax) → `design.md` → `tasks.md` under `.kiro/specs/<feature>/`, backed by always-on `steering/` context files and JSON-defined `hooks/` that fire on file/tool/task events — read via kiro.dev docs and a leaked system-prompt gist since the source is not public.

Repo: `/tmp/claude-1000/-home-tomas--dotfiles/65f7117c-29cb-4945-b826-0a4f06e8ef17/scratchpad/repos/conductor`

## Workflow it implements (as coded, not as advertised)

Conductor's sequence is entirely prose-driven — there is no orchestrator script; each "command" is a slash-command that loads one `SKILL.md` file wholesale:

1. **`conductor-setup`** (`skills/conductor-setup/SKILL.md`) — runs `python3 scripts/resume.py` to detect partial state (see Deterministic table), classifies the repo Greenfield/Brownfield, then interviews the user through Product → Product Guidelines → Tech Stack → Code Style Guides (copied verbatim from `assets/code_styleguides/*.md`, never generated) → Workflow (copies `assets/workflow.md`) → optional skill install, then writes `conductor/index.md` as "the Handshake."
2. **`conductor-new-track`** — reads `conductor/index.md`, interviews for `spec.md` (Overview/Functional Requirements/Acceptance Criteria/Out of Scope), then reads the confirmed spec + `workflow.md` to draft `plan.md` as nested `- [ ]` phases/tasks, appends a `Phase Verification & Checkpoint` meta-task per phase, creates `conductor/tracks/<id>/{spec.md,plan.md,metadata.json,index.md}`, appends a registry line to `conductor/tracks.md`, commits `chore(conductor): initialize track '<id>'`.
3. **`conductor-implement`** — resolves the next `[ ]`/named track, flips it to `[~]` and commits, then **loops task-by-task deferring entirely to `workflow.md`** as "the single source of truth for implementation, testing, and committing" (SKILL.md §3.4) — i.e. the actual Red/Green/Refactor loop lives in the *asset template*, not the skill. On completion it flips `[x]`, commits, then runs a "Synchronize Project Documentation" pass that may edit `product.md`/`tech-stack.md`/`product-guidelines.md` with per-file diff-approval gates, then optionally hands off to `conductor-review`.
4. **`conductor-review`** — git-diffs the track's commit range (chunked per-file above 300 lines), checks intent/style/correctness/tests, runs the test suite, emits a fixed-format Review Report, offers Apply Fixes/Manual/Complete, and — if fixes are applied — appends a `## Phase: Review Fixes` phase to `plan.md` and records the fix commit SHA back into it.
5. **`conductor-revert`** / **`conductor-status`** — read-only or git-history-driven; revert reconstructs the SHA list for a track/phase/task from `plan.md` + registry, offers `git revert` vs `git reset --hard`.

Kiro's workflow (per docs + gist), no source to inspect:

1. **Steering** is loaded first, automatically, on every interaction (`inclusion: always` files) or on-demand (`fileMatch`/`manual`/`auto` front-matter) — this is the standing project context, analogous to Conductor's `conductor/index.md` bundle but resolved by the IDE, not re-read by prose instruction each command.
2. **Spec creation**, Requirements-First variant: user describes a feature → agent writes `requirements.md` (EARS) → **hard stop**, must call a `userInput` tool with reason `'spec-requirements-review'` and literally ask *"Do the requirements look good? If so, we can move on to the design."* → only on explicit approval does it write `design.md` → stop, ask *"Does the design look good? If so, we can move on to the implementation plan."* → only then `tasks.md` → stop, ask *"Do the tasks look good?"*. Design-First variant reorders design before requirements. "Quick Spec" mode explicitly skips all three gates and free-runs.
3. **Task execution**: the IDE parses `tasks.md`'s two-level checkbox hierarchy (`1`, `1.1`), builds a dependency graph, groups independent tasks into concurrent "waves," and executes **one task per interaction, never auto-advancing to the next** (per the leaked prompt: "stop upon completion without auto-advancing").
4. **Hooks** run independently of specs, on IDE/agent lifecycle events (`PostFileSave`, `PreToolUse`, `PostTaskExecution`, etc.), each a standalone `.kiro/hooks/<id>.json`.

## Artifacts it produces

Conductor (schema quoted from the skill files themselves):

| File | Written by | Template heading source |
|---|---|---|
| `conductor/index.md` | conductor-setup §3 | literal block: `# Project Context` / `## Definition` / `## Workflow` / `## Capabilities` |
| `conductor/product.md`, `product-guidelines.md`, `tech-stack.md` | conductor-setup §2.1-2.3 | free-form, interview-drafted, no fixed template in repo |
| `conductor/code_styleguides/*.md` | conductor-setup §2.4 | copied verbatim from `skills/conductor-setup/assets/code_styleguides/{cpp,csharp,dart,general,go,html-css,javascript,python,ruby,typescript}.md` |
| `conductor/workflow.md` | conductor-setup §2.5 | copied verbatim from `skills/conductor-setup/assets/workflow.md` (442 lines) — headings `## Guiding Principles`, `## Task Workflow` → `### Standard Task Workflow` (11 numbered steps), `### Phase Completion Verification and Checkpointing Protocol`, `### Quality Gates`, `## Commit Guidelines`, `## Definition of Done` |
| `conductor/tracks.md` | conductor-new-track §2.5 | line format: `` - [ ] **Track: <Description>** *Link: [...](...)`` |
| `conductor/tracks/<id>/{spec.md,plan.md,metadata.json,index.md}` | conductor-new-track §2.5 | `spec.md`: Overview / Functional Requirements / Non-Functional Requirements / Acceptance Criteria / Out of Scope; `plan.md`: nested `- [ ] Task: ...` / `- [ ] ...` per phase, `[checkpoint: <sha>]` appended to phase headings |

Kiro (schema quoted from docs/gist):

| File | Trigger | Template heading source |
|---|---|---|
| `.kiro/specs/<feature>/requirements.md` | Requirements phase | "Introduction section", numbered requirements = user story + EARS acceptance criteria: `WHEN [event] THEN [system] SHALL [response]` (also IF/WHILE/WHERE variants per the community `jasonkneen/kiro` template) |
| `.kiro/specs/<feature>/design.md` | Design phase | technical architecture, sequence diagrams, data models/interfaces |
| `.kiro/specs/<feature>/tasks.md` | Tasks phase | two-level numbered checkbox list (`1`, `1.1`, max two levels), each task = objective + sub-bullets + requirement refs; explicitly **excludes** testing/deployment/perf/e2e/training/doc tasks |
| `.kiro/steering/{product,tech,structure}.md` | steering, always-on by default | front-matter `inclusion: always \| fileMatch \| manual \| auto`, `fileMatchPattern`, referenced inline via `#[[file:<path>]]` |
| `.kiro/hooks/<id>.json` | any lifecycle event | `{"version":"v1","hooks":[{"name","trigger","matcher","action":{"type":"command"\|"agent",...}}]}` |

## Deterministic vs prompt

| Mechanism | Enforced by script/hook/CLI | Asked of the model in prose |
|---|---|---|
| Detecting partial setup / resume point | **Deterministic** — `skills/conductor-setup/scripts/resume.py`, a real Python script checking `os.path.exists` for 5 files and returning JSON (`setup_complete`, `checklist`, `next_step`) | — |
| Everything else in setup (interview content, mode choice, greenfield/brownfield classification) | — | Prose only — "Detect Project Maturity" is a paragraph of heuristics the model applies itself, not code |
| TDD Red/Green/Refactor loop | — | Prose only — `workflow.md` §Standard Task Workflow, steps are narrative instructions ("Run the tests and confirm that they fail") with no script wired to actually verify red-before-green |
| Commit / plan-status bookkeeping (`[ ]`→`[~]`→`[x]`, SHA recording) | — | Prose only — the model is trusted to edit `plan.md` and run `git commit`/`git notes` itself; nothing checks the SHA it wrote matches a real commit |
| Coverage/lint "Quality Gates" | — | Prose checklist only (`- [ ] Code coverage meets requirements (>80%)`) — no CI hook enforces it |
| Revert target → commit-SHA resolution | — | Prose ("Git Reconciliation") — model greps `git log`, handles "ghost commits" via its own judgment, no script |
| Kiro: EARS format compliance | — | Prose (system-prompt instruction + template), no linter |
| Kiro: phase gating (requirements→design→tasks) | **Deterministic** — the leaked prompt requires calling a `userInput` tool with a fixed `reason` enum (`spec-requirements-review`, etc.); the IDE tool call itself is the enforcement point, not just an instruction to "ask nicely" | wording of the question is prose-fixed but literal |
| Kiro: one-task-per-turn execution | Partially deterministic — IDE task-execution UI drives which task runs; "don't auto-advance" is still a prose rule the model must obey | — |
| Kiro: hooks (lint-on-save, tests-on-save, etc.) | **Deterministic** — real JSON-declared triggers (`PostFileSave`, `PreToolUse`) wired into the IDE event loop, independent of any model choice | — |
| Kiro: steering inclusion (always/fileMatch/manual) | **Deterministic** — YAML front-matter parsed by the IDE to decide what's injected into context, not a model decision | — |

Net: Conductor is almost 100% prose — the only executable artifact in the whole repo is a 54-line existence-check script. Kiro, despite being closed-source, exposes at least three real deterministic seams (tool-call-gated approvals, JSON hooks, front-matter-gated context loading) that don't depend on the model choosing to comply.

## Mechanisms worth stealing

1. **Resumable-state script instead of prose state-detection** — `skills/conductor-setup/scripts/resume.py`. Problem solved: agents re-derive "what's done" from vibes/directory listings every time, burning tokens and occasionally hallucinating completeness. Snippet:
   ```python
   for filename, step_name in chain:
     if not checklist[filename]:
       next_step = {"step": step_name, "file": filename}
       break
   ```
   For a solo-dev dotfiles harness: any multi-step skill (e.g. a `/new-project` scaffold) gets a tiny Python/bash existence-check script that's the single source of truth for "what step am I on," so a killed/resumed session never re-asks answered questions.

2. **Tool-call-gated approval, not prose-gated approval** — Kiro's `userInput(reason='spec-requirements-review')` pattern. Problem solved: "ask the user and wait" is exactly the instruction Conductor's skills give too (`Ask ... using a Yes/No question`), but nothing stops a model from asking-then-immediately-proceeding in the same turn under pressure; a dedicated blocking tool call is a harder wall. For Claude Code skills: model a real approval step as a tool invocation (e.g. `AskUserQuestion`) with a fixed enum reason string per gate, rather than relying on the skill's prose "you MUST ask."

3. **Frozen third-party skill installs with disclosed trust tier** — `skills/conductor-setup/SKILL.md` §2.6 / `conductor-new-track/SKILL.md` §2.4. Snippet:
   > *"Attention: This is a third-party skill. It will be installed as a frozen version (commit <sha>) for your safety."*
   ```bash
   mkdir -p .agents/skills/<skill_name>
   curl -sSL <URL>SKILL.md -o .agents/skills/<skill_name>/SKILL.md
   ```
   For dotfiles: any auto-install-a-skill-from-the-internet flow (e.g. this repo's own `find-skills`/`skill-forge`) should pin to a commit SHA and label 1p/3p rather than always tracking `main`.

4. **Checkpoint-per-phase with git notes, not just commits** — `assets/workflow.md` §"Phase Completion Verification and Checkpointing Protocol", steps 6-9: identify last functional commit (no empty checkpoint commits), attach a full verification report via `git notes add -m "<report>" <sha>`, then record `[checkpoint: <sha>]` in `plan.md`. Problem solved: audit trail of *why* a phase was accepted lives with the code forever (`git log --show-notes`) instead of only in chat scrollback that vanishes. Fits a global harness directly — any long TDD-style skill can attach its manual-verification transcript as a git note on the last real commit instead of a synthetic empty commit.

5. **Explicit destructive-vs-safe revert choice with a pre-declared execution plan** — `skills/conductor-revert/SKILL.md` §4. It never runs `git revert`/`git reset` until it has printed the exact SHA list and commit subjects and gotten a **single-choice** Safe-vs-Hard-Reset answer. Snippet:
   > *"Safe (Recommended): Use `git revert` ... Hard Reset (Destructive): ... This is destructive and should be used with caution."*
   Worth stealing verbatim for any dotfiles/agent skill that touches git history — print the plan, name the destructive option explicitly, default-recommend the safe one.

6. **Two-level task hierarchy with excluded categories, enforced by prompt** — Kiro's `tasks.md` rule to exclude testing/deployment/perf/docs tasks and cap nesting at `N`/`N.M`. Problem solved: plan.md/tasks.md files in agentic frameworks tend toward infinite nesting and scope bloat; a hard cap plus an explicit exclusion list keeps a task list skimmable and keeps "write the task" from becoming "write the whole SDLC." Directly reusable as a rule inside any spec/plan-writing skill.

7. **Steering front-matter to control context cost, not just content** — Kiro's `inclusion: always | fileMatch | manual | auto` + `fileMatchPattern`. Problem solved: Conductor's `workflow.md` (442 lines) and every project doc get re-read in full on every single skill invocation (setup, new-track, implement, review, status, revert all independently re-open `conductor/index.md`'s linked files) — there's no equivalent of "only load this when touching `*.tsx`." For a global dotfiles CLAUDE.md/skills setup: split large standing-context files by inclusion mode (always-small vs. glob-triggered vs. explicit-mention) instead of one monolithic always-loaded file.

8. **Named git-notes-linked audit trail for review fixes** — `conductor-review/SKILL.md` §3.2: fix commits get their SHA appended into `plan.md` (`- [x] Task: Apply review suggestions <sha>`), separate from the commit that made the fix. This closes the loop between "the plan says this is done" and "here is the exact diff that did it," useful for any skill that both edits code and edits its own tracking file — always record the SHA *in* the tracking artifact right after commit, not just in prose.

## Weaknesses / ceremony cost

- **Lines loaded per invocation:** `conductor-implement` alone pulls in its own `SKILL.md` (139 lines) + `conductor/workflow.md` (442 lines, copied wholesale from the 442-line asset) + `product.md`/`tech-stack.md` (variable, user-authored) + the track's `spec.md`/`plan.md` (variable) — a **minimum ~580 lines of pure protocol prose** before any project-specific content is even considered, every single time implementation resumes on a task. `conductor-review` similarly loads `product-guidelines.md` + `tech-stack.md` + every file under `conductor/code_styleguides/` + `plan.md`, uncapped.
- **Gate count:** conductor-setup alone has ~6 sequential approve/revise/refine loops (product, guidelines, tech-stack, style guides, workflow, skills) each individually re-askable; conductor-new-track adds 2 more (spec approval, plan approval); conductor-implement's `workflow.md` template adds a phase-checkpoint manual-verification gate per phase plus a per-task "await confirmation" wherever the workflow defines a human-in-the-loop step. This is heavier than Kiro's fixed 3-gate spec flow (requirements/design/tasks) — Conductor has no "Quick Spec" equivalent to skip ceremony for small changes.
- **Nothing enforces the model actually followed the gate.** Every "MUST ask", "MUST HALT", "CRITICAL" in these skills is prose the model can silently skip under context pressure — e.g. "Run the tests and confirm that they fail as expected... Do not proceed until you have failing tests" (`workflow.md` step 3) has no tool-level check that a red run actually happened; the model self-reports. Same for coverage (>80%) — quality gates are a checklist, not a script that blocks completion. Compare to Kiro's `userInput` tool-call requirement, which is at least a harder API-level checkpoint (assuming the IDE enforces the tool must be called and its response awaited — unverifiable without source).
- **State integrity is entirely file-convention-based**: track status lives as a bracket character (`[ ]`/`[~]`/`[x]`) inside a markdown line that multiple skills parse independently with slightly different "legacy format" fallbacks (`## [ ] Track:` vs `- [ ] **Track:`) — no schema validation, so a manually-edited or partially-committed `tracks.md` can desync from `plan.md` with nothing catching it until `conductor-status`/`conductor-revert` fails to parse.
- **Third-party skill installs use bare `curl | -o` with no checksum**, only a SHA-pin promise stated in prose — the "frozen version (commit <sha>)" claim is not verified by any script; a malicious catalog entry could point anywhere.
- **Kiro side, from what's visible**: hooks only fire on *agent-made* file changes, not manual edits (a documented gap), and the whole spec/steering/hooks system is IDE-proprietary — nothing here is portable outside Kiro itself, unlike Conductor's plain-markdown-plugin approach.

## Plugin/packaging structure

Conductor installs as a **Claude Code / Antigravity plugin**, no build step, no dependencies beyond the two files at repo root:
- `plugin.json` (4 lines): `{"name": "conductor", "description": "Conductor Agent Skills"}` — no entrypoints, no hooks array, no permissions block; the entire "plugin" is just a directory of `skills/*/SKILL.md` files Claude Code auto-discovers by convention.
- `.claude-plugin/marketplace.json`: registers itself as a marketplace with one plugin, `source: "./"`.
- Claude Code install: `/plugin marketplace add gemini-cli-extensions/conductor` then `/plugin install conductor` (README §2).
- Antigravity install: either `agy plugins install <github-url>`, or a **symlink** into `~/.gemini/config/plugins/conductor` / `.agents/plugins/conductor` for live-dev-mode (edits apply without reinstall) — same trick this dotfiles repo uses via `stow`.
- `rules/conductor_antigravity.md` is a platform-specific adapter file (front-matter `trigger: model_decision`) that only Antigravity's rule-loading mechanism picks up, instructing the agent to prefer a native `ask_question` modal tool over text prompts when available, falling back to text otherwise — the one place in the repo that branches behavior by host environment.
- No hooks are registered anywhere in the repo — all automation is slash-command/skill-invocation-driven, not event-driven. [CORRECTED: the original claim that `grep -r hook` "finds only prose references to the review skill being 'hooked' into the plan" is wrong — `grep -rni hook` across every file in the repo (all `.md`/`.json`, non-`.git`) returns **zero matches**, not even a prose reference. The word "hook"/"hooked" does not appear anywhere in the conductor-review or workflow.md text; the closest actual language is workflow.md's "The review agent will automatically append a `Review Fixes` phase to `plan.md`," which never uses the word "hook." The underlying conclusion (no real hook mechanism exists) still holds, just not for the reason originally stated.]

Kiro packaging (per docs, not inspectable): built into the IDE itself — `.kiro/` directory convention (`specs/`, `steering/`, `hooks/`), hooks are plain JSON files auto-registered by the IDE's file watcher, no plugin marketplace since it's not an extension model but core product surface. Community reproductions (e.g. `jasonkneen/kiro` "spec-process-guide") exist as documentation/templates only, not installable packages, since the enforcement (tool-gating, hook execution) requires the closed IDE.

## Second-reader additions

1. **`CI=true` non-interactive test-runner convention** — `skills/conductor-setup/assets/workflow.md`, Guiding Principle 6:
   > *"**Non-Interactive & CI-Aware:** Prefer non-interactive commands. Use `CI=true` for watch-mode tools (tests, linters) to ensure single execution."*
   Problem solved: an agent that runs `npm test`/`jest`/etc. without this hangs forever in watch mode waiting for a TTY that never comes, burning the whole turn (or the session) on a stuck process — a common, concrete agent-loop failure the first pass's "worth stealing" list didn't call out despite quoting the surrounding workflow.md extensively. Directly portable as a one-line standing rule in any TDD-flavored skill in this dotfiles repo (`flow`, `feature`, `fix`): always prefix/env-wrap test and lint invocations to force single-shot, non-interactive execution.

2. **Host-conditional UI escalation via front-matter trigger** — `rules/conductor_antigravity.md` (17 lines, front-matter `trigger: model_decision`). The first-reader report only cited this file once, in passing, under "Plugin/packaging structure," to note it's "the one place in the repo that branches behavior by host environment" — it was never listed as a mechanism worth stealing in its own right. The actual pattern is reusable on its own: *check whether a richer native tool (`ask_question`) is present in the current tool declarations, and only if so, upgrade every yes/no and multiple-choice prompt in the skill from raw chat text to a native modal; fall back to plain text otherwise.* Snippet:
   > *"Modal Tool Check: ... the agent MUST proactively check if the native GUI modal tool `ask_question` is available in its allowed tool declarations ... Text Fallback: If `ask_question` is NOT present ... fall back to standard formatted text-based choices."*
   For this dotfiles repo: any skill that asks the user structured questions (e.g. via `AskUserQuestion`) could adopt the same "detect-then-upgrade" rule explicitly instead of assuming one fixed I/O surface, so the same skill degrades gracefully across Claude Code's terminal UI vs. any richer host.

3. **The "frozen third-party skill" mechanism (report's own mechanism #3) is untested in this snapshot and the freeze promise is unenforceable as written** — `skills/conductor-setup/assets/catalog.md` and `skills/conductor-new-track/assets/catalog.md`. Both catalogs are exhaustively Firebase-only and **100% `Party: 1p`** (`grep -c "Party.*1p"` = 11/11 and 11/11; zero `3p` entries in either file), so the whole 3p-disclosure/frozen-commit warning path the first reader praised has no real example anywhere in the repo to check the model's behavior against. Worse, every catalog URL is a `main`-branch raw GitHub URL (e.g. `https://raw.githubusercontent.com/firebase/agent-skills/main/skills/firebase-auth-basics/SKILL.md`), not a commit-pinned one — nothing in the skill or the catalog schema tells the model *how* to resolve the `<sha>` it's supposed to freeze to, so "installed as a frozen version (commit `<sha>`)" is a promise the prose makes with no data source to fulfill it from. Worth folding into the original mechanism write-up as a caveat: pin the catalog's URLs themselves (or record a resolved SHA at install time via an actual `git ls-remote`/API call), not just the warning text, or the "frozen version" claim is decorative.

## Verdict

**Borrow parts.** Conductor's actual code footprint is nearly zero (one 54-line Python script; everything else is instructional markdown), so "adopt the plugin" would mean adopting ~580 lines of always-reloaded prose per implement-cycle for a solo dev who doesn't need a Product Manager persona, brand-voice files, or third-party skill marketplace ceremony. The state-detection script, the git-notes-checkpoint pattern, the safe/hard-reset revert-plan pattern, and the frozen-commit third-party-install discipline are each small, self-contained, and directly draftable into this dotfiles repo's existing `flow`/`feature`/`fix` skills without importing Conductor's six-skill apparatus wholesale. Kiro cannot be adopted at all (closed-source, IDE-bound) but its two sharpest ideas — gate approval via an actual blocking tool call rather than a prose "MUST ask," and context-inclusion front-matter to stop re-loading the same 400+ lines of standing context on every invocation — are worth reproducing inside Claude Code's own skill/hook system, where `AskUserQuestion` and settings.json hooks already provide the primitives Kiro fakes with IDE-proprietary plumbing.
