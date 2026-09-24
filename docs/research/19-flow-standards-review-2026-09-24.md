# Flow standards review — 2026-09-24

Code-only review. README, docs/ and PROGRESS.md were treated as wrong and not
used as evidence. SKILL.md files count as product (they are the prompts that run).

Compared against: GitHub spec-kit, obra/superpowers, BMAD-METHOD, AWS Kiro,
OpenSpec, Tessl, Agent OS, GSD, claude-task-master, Anthropic's
"explore-plan-code-commit" and "effective harnesses for long-running agents".

## Part 1 — The standards

Each standard names where it comes from and how to check it.

### A. Size the process to the change
- **S1 Ceremony scales.** A one-sentence change needs no spec file and at most
  one human stop. Source: Anthropic best practices, BMAD "right-size", the
  top complaint about spec-kit (9x overhead) and Kiro (bug -> 16 criteria).
  Check: walk a tiny change and a big one; count files, stops, subagents.
- **S2 Artifacts a human can read.** A small feature's spec + tasks read in
  under 5 minutes; no line is only parseable by a machine.
  Source: Böckeler "I'd rather review code than these markdown files".
- **S3 Route is visible and checkable.** How much process a change gets is
  decided from evidence, shown, and overridable.

### B. The spec itself
- **S4 WHAT/WHY apart from HOW.** Source: spec-kit specify template.
- **S5 Testable acceptance criteria with IDs** (EARS or Given/When/Then).
  Source: Kiro EARS, spec-kit FR-#/SC-#.
- **S6 Ambiguity marked, capped, resolved before planning.**
  Source: spec-kit `[NEEDS CLARIFICATION]` (max 3) + `/clarify`.
- **S7 Traceability check.** Every requirement maps to a task and a test; every
  task maps back. Checked by a tool, read-only. Source: spec-kit `/analyze`.
- **S8 Project principles are written once and checked.** Source: spec-kit
  constitution gate, Kiro steering, Agent OS standards.

### C. Humans in the loop
- **S9 Human approval cannot be faked by the model.** Source: Plan Mode is a
  mechanical write-block; Tessl structural approval pause.
- **S10 Plans are easy to review and edit** (short, diffable, cheap to change).
- **S11 Stop only for real reasons** (irreversible, security, outside side
  effect, plan broken). Source: superpowers executing-plans.

### D. Building
- **S12 Test-first is observed, not claimed.** Red run seen before green, by
  something other than the worker. Source: superpowers TDD iron law.
- **S13 Fresh, minimal context per task.** Source: superpowers SDD, GSD, BMAD.
- **S14 Worker scope is enforced** (files it may touch).
- **S15 Independent review per task and per branch, with a fix loop.**
- **S16 No "done" without fresh evidence.** Source: superpowers
  verification-before-completion.
- **S17 Parallel work is safe** (disjoint files, capped concurrency).

### E. State over time
- **S18 State on disk; any fresh session resumes.** Source: Anthropic long-running harness, ralph.
- **S19 One source of truth per rule** (no logic duplicated across languages).
- **S20 Specs stay true after ship** (spec-anchored, not spec-first).
  Source: OpenSpec specs/ vs changes/ + archive merge; Böckeler taxonomy.
- **S21 Mid-build change is safe** (amend without losing history or approval meaning).

### F. Enforcement and safety
- **S22 Rules that matter are code; prose-only rules are few and named.**
- **S23 Fail closed and loud** when a tool (git, jq, node) is missing.
- **S24 Cheap per turn** (hooks add little latency and no noise).
- **S25 Destructive actions guarded.**

### G. The product
- **S26 Small, learnable surface.** Core flow separate from extras.
- **S27 One "what now?" answer** at any moment.
- **S28 Portable** (OS; ideally more than one agent harness).
- **S29 Evidence it helps.** Behaviour evals with a baseline (with vs without plugin).
- **S30 Works on big existing codebases** (brownfield).
- **S31 Light bug-fix path.**
- **S32 Kill bad ideas before speccing** (idea assessment).

## Part 2 — Results

Graded by 7 code readers (one per group) and 1 hands-on run on a throwaway
repo. Headline claims were re-checked by hand (marked ✔).

**Score: 9 PASS · 15 PARTIAL · 8 FAIL.**

| Std | Grade | One-line reason |
|---|---|---|
| S1 | PARTIAL | 3 routes exist, but the route is the model's self-report; a 1-task wave still runs brief + subagent + 3-lens review. This repo's own history has 0 `bounded` runs. |
| S2 | PARTIAL | Oneshot TASKS.md (26-line template) is great. Real task lines reach 2,070 chars (`.specs/009`); dispatch feature 010 is ~34 KB of markdown. |
| S3 | PARTIAL | Route is shown and overridable; `flow-lint:794` only checks it is one of 3 words. Downgrade `--force` rule has no code. |
| S4 | PARTIAL | Template separates WHAT/HOW; only spec-judge (advisory, once) checks it. |
| S5 | PARTIAL | Behaviors table has B-IDs + Given/When/Then; nothing parses it. |
| S6 | PARTIAL | Cap of 3 open questions is enforced by `prep-lint` on PREP.md, not on spec.md. |
| S7 | **FAIL** | No requirement → task → test trace check. spec-kit `/analyze` has one. |
| S8 | **FAIL** | No project principles file or gate. spec-kit constitution, Kiro steering. |
| S9 | **FAIL** ✔ | Any `^Approved: YYYY-MM-DD` line opens the gate (`router.js:254`, `specgate.sh:258`). The model can write it. Same for `Verified:` and `--by user`. |
| S10 | PASS | Plans are short, plain, diffable; `flow lint` is fast. |
| S11 | PASS | Stops only at approval, verify, blocked, looping, disagreement. |
| S12 | PARTIAL | RED is the worker's own claim. Nothing outside it saw a failing run. |
| S13 | PASS | `task-brief` gives each worker one task slice. Best in field. |
| S14 | **FAIL** | `files:` is not enforced; a worker can edit anything. |
| S15 | PARTIAL | Per-task fix ladder is real (`build-slices.js`); whole-branch `review-diff.js` has no fix step. |
| S16 | PASS | `PASS-<sha>.md` self-invalidates. (But see bug 2 below.) |
| S17 | PARTIAL ✔ | "At most 4 in parallel" is prose; `build-slices.js` runs the whole wave. |
| S18 | PASS | State recomputed from disk every call. |
| S19 | **FAIL** | Feature resolution exists 3 times (router.js, flow-lint, specgate.sh); approval parsing twice. |
| S20 | **FAIL** | Specs are archived, never merged into a current-truth spec. Spec-first, not spec-anchored. OpenSpec does this. |
| S21 | PARTIAL | `--amend` clearing `Approved:` is prose; nothing clears or checks it. |
| S22 | PARTIAL | Big rules (tick, waves, PASS) are code; many MUST/NEVER lines are prose. |
| S23 | **FAIL** | With no jq and no python3, git-guard judges nothing and says nothing. `flow next` without git says "not a git repo". |
| S24 | PASS | Hooks are fast and quiet. |
| S25 | PARTIAL | git-guard is good, but a regex, and fails open (S23). |
| S26 | **FAIL** | 29 skills, ~6,300 SKILL.md lines + ~7,900 reference lines. About 10 are the product. |
| S27 | PASS | `flow next` always gives one answer. Best in field. |
| S28 | PARTIAL | Only the hooks travel to opencode, not the skills. superpowers ships 6+ harnesses. |
| S29 | PASS | Real eval suite with ledger. Ahead of spec-kit and superpowers. |
| S30 | PARTIAL | Codebase map exists; no test on a big repo. |
| S31 | PASS | `/flow:fix` is light for small bugs. Best in field. |
| S32 | PARTIAL | scrutinize-idea exists but its verdict doesn't gate `/flow:spec`. |

### Bugs found on the way
1. ✔ `flow tick` falls back to HEAD when no commit touched the task's files
   (`bin/lib/tick.js:96-100`), so it writes a false `done:`. `flow lint`
   catches it afterwards (`done-touches-nothing`). tick should refuse instead.
2. ✔ PASS file paradox: the router needs `PASS-<HEAD>.md` exactly
   (`router.js:511`). Committing that file moves HEAD, so it is stale at once.
   It only works if left uncommitted, yet the archived feature 010 has it committed.
3. ✔ `flow-lint:494` folds any unknown `key:` segment into the description.
   A typo like `afetr:` silently drops the dependency.
4. Nothing warns when a feature is built on `main` (`new-spec --no-branch`).
5. `requireSpec: true` makes the `bounded` route impossible (no TASKS.md to approve).

### What others do better
- **spec-kit**: `/analyze` traceability check; constitution gate; `[NEEDS CLARIFICATION]` blocks the spec; core vs extensions split at install.
- **superpowers**: one small coherent pipeline; worktree per unit of work; tests its skills by pressure scenarios; ships to 6+ harnesses.
- **OpenSpec**: current-truth `specs/` + change deltas merged on archive (no drift).
- **Kiro**: EARS criteria; steering files loaded only when relevant.
- **Anthropic Plan Mode**: approval is a real write-block, not a text line.

### What flow does better than all of them
- A deterministic "what now?" router over disk state (`flow next`).
- Mechanical tick/lint joins to git (lies about done get caught).
- Self-invalidating PASS file; stop-gate; tamper notice; git-guard.
- Light `/flow:fix`; one-task briefs; a real eval suite.

### Top 5 changes, in order
1. **Make approval real (S9).** A `flow approve` / `flow verify` CLI that asks
   the human on the terminal (or an `AskUserQuestion` answer), and a PreToolUse
   deny on any Edit/Write that adds `Approved:`/`Verified:` to `.specs/`.
2. **Split core from extras (S26).** Ship `flow` = spec, next, fix, loop, issue,
   no-slop. Move the other ~19 skills to a separate plugin.
3. **Add `flow analyze` (S7, S5, S6).** Read-only: every B-ID has a task and a
   `Proven-by`; every task has a B-ID; ≤3 open questions in spec.md.
4. **Fix the 3 bugs** (tick fallback, PASS paradox, unknown-field fallback), and
   make hooks say "not judging" when jq/python3 are missing (S23).
5. **Living spec (S20).** On archive, fold each feature's behaviours into one
   `.specs/SPEC.md` (current truth), OpenSpec-style.
