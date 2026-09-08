# Current flow pipeline — exact map (2026-09-07)

Scope: what the `flow` plugin actually does today, artifact by artifact, read by read, stop by stop. Paths are
repo-relative. **PRIMARY** = read from source in this tree or fetched upstream this session; **SECONDARY** =
prior research in `docs/research/`. Not repeated, cited instead: `02-frameworks-source-review.md` §1 (matrix),
§3 (steal list S1–S8), §5 (v2 skeleton + the ~860-line Medium budget); `10-idiot-proof-harness-2026.md` §3
(per-framework mechanism table); `raw/frameworks/{spec-kit,get-shit-done,ccpm,openspec}.md`.

## 1. Boxes and arrows — what exists today

There are **three** build paths out of a spec, not one. Nothing at the top of any skill tells you which to pick.

```
                      ┌─────────────────────────────────────────────────────────────┐
   idea ──► /flow-spec │ 6 phases. Writes .specs/NNN-slug/spec.md (NNN = model scans │
                      │ .specs/ for max+1, SKILL.md:90 — NOT scripts/new-spec).      │
                      │ + code-design.md (Ph3.5, conditional) + spec-judge-iteration-│
                      │ N.md (Ph4, loop ≤2). No branch. No .claude/flow.json.        │
                      └──────────────┬──────────────────────────────────────────────┘
                                     │ SKILL.md:232 closing line: "Run /flow-to-issues"
                                     ▼
   PATH A — /flow-to-issues (197 lines)
     Ph1 resolve spec (highest-numbered .specs/NNN-*) · Ph2 slice vertically + tag AFK/HITL
     Ph2b revalidate code-design.md counts, re-cut contract blocks
     Ph4 .specs/NNN/plan.md ─► spec-judge issue-breakdown ≤2 iters ─► issue-plan-judge-iteration-N.md
     Ph5 HARD GATE "local, github, or edits?"
     Ph6 ALWAYS issues/NN-slug.md · OPTIONALLY `gh issue create --label afk|hitl` (topo) ─► issues.md
     Ph7 per issue: /flow-handoff ─► /tmp/flow-handoff-<slug>-<n>.md ─► /flow-feature

   PATH B — /feature (449 lines, Stages -1..8, own resume, own quality swarm writing
     .claude/quality/{security,performance,accessibility,type-safety}.md)

   PATH C — /flow (router SKILL.md 108 + steps/00..06)   ← the one the dev wants
     [0 setup]  scripts/new-spec "<title>" --prefix flow/ [--worktree] ─► creates .specs/NNN-slug/,
                branch flow/<slug>, writes+prints .claude/flow.json {number,slug,spec_dir,branch,
                worktree}; base sha = git rev-parse HEAD; writes .claude/workflow-state.local.md
                {type:flow, mode, size, unattended, detected cmds, base sha, empty ## Progress}
     [1 spec]   ─► <spec_dir>/spec.md   (≤3 haiku codebase readers fan out in one message)
     [2 judge]  opt-in --judge only ─► <spec_dir>/spec-judge-harsh.md
     [3 plan]   conditional design pass ─► <spec_dir>/code-design.md + per-slice "## Contract for
                this slice — Slice N" blocks; ─► .claude/feature-plan.local.md (C7) [+ plan.mdx]
                gates: plan-lint must print OK · slice-overlap must exit 0
                HARD GATE approval ─► prepends "Approved: YYYY-MM-DD by user"
     [4 build]  slice-overlap --waves ─► waves; per slice: slice-brief ─► .claude/slices/<N>-brief.md
                ─► 1 developer subagent (reads ONLY the brief) ─► review-package ─►
                .claude/review/slice-<N>.diff ─► 2 adversaries (correctness, gaming) ─► fix ladder.
                Workflow mode: Workflow({name:'flow:build-slices', args:{plan,design,base,slices,
                testCmd}}) — build-slices.js 327 lines; stage-0 haiku agent recomputes {deps,files}
     [5 verify] 5.1 `flow check --fix` ‖ 5.2 E2E (Large UI) ‖ 5.3 review-diff — one message;
                5.4 browser ─► .claude/verification/* ; 5.5 HARD GATE user verification;
                5.6 /qa ─► .qa-report/QA-REPORT.md
     [6 PR]     .claude/pr-description.md ─► gh pr create --draft ─► re-run gates ─► gh pr ready
                ─► DELETE flow.json, *.local.md, slices/, review/, verification/, .qa-report/
                ─► offer /flow-deepen

   out-of-band: `flow next` (bin/flow computeNext, :2016-2147) reads PROGRESS.md FIRST, then
   .claude/flow.json, then .claude/feature-plan.local.md. Knows nothing about PATH A.
```

## 2. State files — 22 distinct, across 3 namespaces, 2 plan grammars, 6 progress representations

| # | File | Written by | Read by | Lifetime |
|---|---|---|---|---|
| 1 | `.claude/flow.json` | `scripts/new-spec` (step 0.5) | step 0.1 resume, step 1 (`spec_dir`), `computeNext:2035` | deleted step 6 |
| 2 | `.claude/workflow-state.local.md` | step 0.5, updated every sub-phase | step 0.1, `computeSliceProgress` (`workflow-state-checkboxes`), `feature` Stage -1 | deleted step 6 |
| 3 | `.claude/feature-plan.local.md` | step 3 | plan-lint, slice-overlap, slice-brief, `spec-gate.sh:118`, `stop-gate.sh:179`, `computeNext:2036`, steps 4–6 | deleted step 6 |
| 4 | `.claude/plan.mdx` | step 3, only if `command -v better-plan` | better-plan UI (`GET /__bp/status`) | never cleaned |
| 5 | `.claude/slices/<N>-brief.md` | `scripts/slice-brief` | the one slice subagent | deleted step 6 |
| 6 | `.claude/review/slice-<N>.diff` | `scripts/review-package` | adversary lenses | deleted step 6 (kept if unattended) |
| 7 | `.claude/review/<base>..<head>.diff` | `review-package` default `--out` | step 5.3 lenses | same |
| 8 | `.claude/verification/*` | step 5.4 | step 5.5, PR body | deleted step 6 (kept if unattended) |
| 9 | `.claude/pr-description.md` | step 6 | `gh pr create --body-file` | deleted step 6 |
| 10 | `.claude/quality/{security,performance,accessibility,type-safety}.md` | **`/feature` Stage 4.1 only** | Stage 4.2 aggregate | `/flow` never writes these |
| 11 | `.qa-report/QA-REPORT.md` | `/qa` (step 5.6) | step 5.6 verdict | deleted step 6 |
| 12 | `.claude/flow.config.json` | hand-written (C4) | `spec-gate.sh:135` `requireSpec` | permanent |
| 13 | `.claude/flow.off` | `flow off` | every judging hook | permanent until `flow on` |
| 14 | `PROGRESS.md` | `flow init` template; humans | **`computeNext:2026` FIRST, before flow.json** | tracked |
| 15 | `REVIEW.md` | `flow init` (`flow-templates/REVIEW.md`) | humans | tracked |
| 16 | `.specs/NNN-slug/spec.md` | step 1 **or** flow-spec Ph3 (two different numberers) | everything downstream | tracked |
| 17 | `.specs/NNN-slug/code-design.md` | step 3 (conditional) **or** flow-spec Ph3.5 (provisional) | `slice-brief --design`, flow-to-issues Ph2b | tracked |
| 18 | `.specs/NNN-slug/spec-judge-harsh.md` | step 2 (`--judge`) | step 2 decision | tracked |
| 19 | `.specs/NNN-slug/spec-judge-iteration-N.md` | flow-spec Ph4 | flow-spec Ph5 loop | tracked |
| 20 | `.specs/NNN-slug/plan.md` | **flow-to-issues Ph4 only** — a *second, incompatible* plan grammar | spec-judge issue-breakdown; nothing else | tracked |
| 21 | `.specs/NNN-slug/issues/NN-slug.md` + `issues.md` | flow-to-issues Ph6 | `/flow-handoff`, `/flow-feature`, humans | tracked |
| 22 | `${TMPDIR:-/tmp}/flow-handoff-<slug>-<n>.md` | flow-handoff Ph4 | the next session, by hand-pasted sentence | orphan on disk |

**Two plan grammars.** `.claude/feature-plan.local.md` is C7 (`docs/SPEC.md:99-104`): ordered
`## Behavior Inventory` (literal header `| Behavior | Slice | Verified by |`) → `## Slice N — <title>` with
`- **Files**:`, `- **Depends-on**:`, `### Slice N — RED|GREEN|REFACTOR` → optional `## Discovered` →
`## Gate Phases`, fence-aware; `plan-lint:253-296` emits `MISSING:`/`INVALID:` against exactly that.
`.specs/NNN/plan.md` is `### 01 — <title>` with `- **Tag**: AFK|HITL`, `- **depends-on**:`,
`- **Acceptance criteria**` (flow-to-issues SKILL.md:168-186). **No script parses grammar 2** — PATH A ships a
plan `plan-lint`, `slice-overlap`, `slice-brief`, `spec-gate.sh` and `flow next` are all blind to.

**Six progress representations, no single writer:** (a) `workflow-state.local.md` `## Progress` checkboxes
(canonical per `planning.md`, hand-mirrored by the model "marking each `[x]` with its commit hash");
(b) plan-file checkboxes (`computeNext` fallback `plan-checkboxes`); (c) slice-heading done markers
(`slice-heading-marker`, `bin/flow:1956`); (d) the `PROGRESS.md` resume bullet, which *outranks* all of the
above; (e) git log Red/Green/Refactor commits; (f) on PATH A, GitHub issue state — or nothing at all when the
user answered "local".

## 3. Where GitHub is touched

Only five call sites in the whole plugin, and issue creation is already fully optional:

- `flow-to-issues` Ph5 asks *"local, github, or edits?"*; Ph6 runs `gh issue create --title … --body-file …
  --label afk` in topological order and writes URLs back to `issues.md`; missing/unauthed `gh` falls back to
  local-only (SKILL.md:148-152). Local markdown is **always** written first (SKILL.md:146).
- `/flow` step 6 and `/feature` Stage 8: `gh pr create --draft` → `gh pr ready` (+ `gh pr view --json number`).
  `/flow` bans issues outright ("NEVER create GitHub issues, AFK/HITL tags, or a tracked issue set").
- `computeNext` emits `gh pr view --web` for a shipped-and-pushed `flow/*` branch (`bin/flow:2115`).

**So the GitHub dependency is not `gh`.** It is that `issues/` is a third artifact shape whose only consumer is
a human running `/flow-handoff` N times by hand, while `/flow` step 3's first line says *"this REPLACES issue
slicing"*. Two mutually exclusive middles ship in one plugin, and `/flow-spec`'s closing paragraph routes the
user into the one the developer says he does not want.

## 4. A Medium run, counted

**Mandatory reads** (`MANDATORY — READ ENTIRE FILE`), attended, UI feature, no `--judge`, design pass firing:

seven files, **959 lines**: `flow-spec/references/spec-template.md` 401 (step 1) · `flow/planning.md` 110 and
`flow-spec/references/{code-design-doctrine.md 200, pattern-forces.md 76}` (step 3, the latter two conditional
on the shared-seam trigger) · `feature/execution-prompt.md` 71 (step 4) · `flow/review.md` 56 (step 5) ·
`shared/claude-in-chrome-reference.md` 45 or `shared/verification.md` 77 (step 5.4). 683 if the design pass skips.

Plus unavoidable router text: `flow/SKILL.md` 108 + `steps/00..06` 251 + `orchestration.md` 22 +
`orchestration/subagents.md` 62 = **443**. **Medium total ≈ 1,400 lines of skill text**, vs the ~860 target in
`02-frameworks-source-review.md` §5. Not counted: `shared/review.md` (242 lines) which duplicates
`flow/review.md` (56) — two review doctrines with the same filename in two directories.

**User decisions on the same run** — the gate manifest (step 0.6) is instructed to say *"this run will stop for
you twice"*. Actual turns that wait on the user:

(1) size-classification override offer (0.3) · (2–8) discovery, **serial, one question per turn, Medium cap 7**
(01-spec.md:7,18) · (9) `showcase` UI direction, explicit STOP (03-plan.md:25) · (10) plan approval HARD GATE ·
(11) user verification HARD GATE (5.5) · (12) `/flow-deepen` offer (06-pr.md:37); plus the 3-question
speccability guard when the request is thin. **≈ 10–12 stops promised as 2.** PATH A adds Ph5 local-vs-github,
Ph7 go-ahead, and one pause per HITL issue.

## 5. Every place the pipeline loses "what's next"

**L1 — the two middles have no shared state.** `flow-to-issues` writes `.specs/NNN/plan.md`; `computeNext`
reads only `.claude/feature-plan.local.md` (`bin/flow:2036`). After a full PATH A run, `flow next` reports
`source:'flow-no-plan'`, *"spec exists …, plan not written"*, `next:'/flow'` — sending the user to start the
*other* middle on top of the finished one (**PRIMARY**, `bin/flow:2052-2058`).

**L2 — FU-09** (`/tmp/probe-results.json`, `synthesis.fix_units`, `significant`, 8/10 repos):
`computeNext(process.cwd())` resolves from cwd, not `gitToplevel`. In `finance` the repo root says
`/wrap then /ship` and `src/lib/api` says `/flow <describe the feature>` with `why: 'spec gate is active on
this branch'` — *"it has lost a 320-commit flow entirely and instructs the model to start a SECOND spec on top
of the existing one, and CLAUDE.md tells the model to trust exactly this output."* The whole plan branch is
gated on `flow.json` existing, so `terraform` (live plan, unchecked `[ ] Phase 5 gates`, three `flow/*`
branches) reports `clean-no-flow` **while `spec-gate.sh` denies every edit on that branch**.
`findSpecDirForBranch` (`bin/flow:1988-1999`) only looks in `.specs/`, so the `specs/` convention flow-spec
SKILL.md:91 explicitly permits is unreachable. `branch` comes back `""` in JSON in five repos.

**L3 — FU-18** (same source, `significant`): one hardcoded plan path. A stale untracked
`feature-plan.local.md` sits permanently in porcelain, so `stop-gate.sh:225` marks it changed every turn and
blocks 100% of turns including read-only ones; `finance` carries `feature-plan-2..9` that **no consumer reads
and nothing in the plugin ever creates**, so pass 1's `Approved:` line grants edit permission forever for work
no plan describes. The deny text never prints plan-lint's actual objection, so a human-approved plan failing on
a missing `## Gate Phases` heading has no exit but turning the gate off.

**L4 — `flow next` returns prose, not commands, and names commands the plugin does not ship.**
`'review and approve the plan (then /flow continues)'`, `'/wrap then /ship'`, `'agents <path>'`
(`bin/flow:2047,2063,2081`). `/wrap` and `/ship` exist only in `~/.claude/commands/` (user dotfiles) —
**PRIMARY**: `plugins/flow/` ships no `commands/` dir at all (`plugin.json` declares `skills` only), so a
clean install's next-step points at nothing.
**L5 — `PROGRESS.md` outranks live run state.** `computeNext:2026-2033` returns on the PROGRESS.md resume
bullet before it ever reads `flow.json`; a stale "Now: …" line silently overrides an in-flight flow.
**L6 — position is never data.** `flow.json` has no `phase` and no `plan` field; step 0.1 reconstructs where
the run is from markdown checkboxes the model was told to hand-mirror ("Mirror each slice's sub-phases into
`## Progress`", `planning.md` last line). Nothing verifies the mirror.

**L7 — `/flow-spec` → `/flow` allocates a second spec.** flow-spec computes `NNN` itself by scanning `.specs/`
(SKILL.md:90) and writes no `flow.json` and no branch; `/flow` step 0.1 resumes only on `flow.json`, and 0.5
unconditionally runs `new-spec`, which allocates a *new* number and a *new* branch. No `/flow --spec <path>`
is documented. The developer's stated ideal — `/flow:spec` then build — therefore yields `.specs/001-x/` and
`.specs/002-x/` for one feature. The numberers also differ in strength: `new-spec` maxes over the cwd, every
worktree and every local/remote branch's committed dir (`docs/SPEC.md:106`); flow-spec's scan sees only cwd.

**L8 — step 6 erases the trail.** Cleanup deletes `flow.json`, both `*.local.md`, `slices/`, `review/`,
`verification/`; post-PR `flow next` drops to `findSpecDirForBranch` + `gitPushed` heuristics (L2's blind spot).
**L9 — handoffs are orphans.** `/tmp/flow-handoff-<slug>-<n>.md` is referenced by nothing on disk; the only
pointer is a chat sentence the next session cannot see (flow-handoff SKILL.md:50-54).
**L10 — three build entry points, no selector.** `/flow` steps 4–6, `/feature` Stages 2–8 and `/flow-feature`
(referenced 6× by flow-to-issues and flow-handoff) all implement TDD → gates → browser → user gate → PR, in
three different state layouts (`.claude/quality/` exists only in `/feature`).

## 6. What a solo dev calls murky (the developer's own words, grounded)

- *"/flow:spec then it gets murky"* → L7 is literal: the two skills cannot hand off, and flow-spec's closing
  line (SKILL.md:232) routes to `/flow-to-issues` — the GitHub-shaped path — while `/flow` step 3 line 1 says
  issue slicing is replaced. The plugin contradicts itself across two files.
- *"I don't want to rely on GitHub"* → he already doesn't; `gh` is opt-in behind Ph5. The real cost is the
  `issues/` artifact shape and the manual `/flow-handoff` × N loop that exists only to feed it.
- *"as simple as possible"* → 1,400 lines read on a Medium run; 22 state files; 2 plan grammars; 6 progress
  representations; a gate manifest that says 2 and delivers 10–12.
- The genuinely load-bearing determinism is small and already correct: `new-spec`, `plan-lint`, `slice-brief`,
  `slice-overlap`, `review-package` (frozen in `docs/SPEC.md` C7/C8) and `build-slices.js`'s wave scheduler
  (C13; stage-0 haiku agent recovers `{deps,files}` from the plan, `build-slices.js:170-195`).

## 7. Upstream mechanisms fetched this session (PRIMARY)

- **spec-kit** `templates/commands/tasks.md` (`gh api repos/github/spec-kit`, 2026-09-07): one `tasks.md` per
  feature under a strict line grammar — *"- [ ] [TaskID] [P?] [Story?] Description with file path"* — taught
  with four `❌ WRONG` examples naming the exact omission (missing checkbox / ID / story / file path). Phases:
  Setup → Foundational → one per user story in priority order → Polish. `taskstoissues.md` is a *separate,
  optional* command: issues are a publish step, never the plan.
- **spec-kit** `implement.md`: *"**IMPORTANT** For completed tasks, make sure to mark the task off as `[X]` in
  the tasks file"* vs *"Treat checklist markers as a **read-only** gate: scan checkbox state, report status,
  and ask before proceeding when needed; do NOT modify checklist files or markers"* — two checkbox files with
  opposite write permissions, plus a rendered per-checklist PASS/FAIL table.
- **gsd** `commands/gsd/progress.md` + `workflows/next.md` (`gh api repos/gsd-build/get-shit-done`,
  2026-09-07): one situational command, three modes — default (report + route), `--next` (auto-advance),
  `--do "<intent>"` (*"Never does the work itself — matches intent, confirms, hands off"*). State is queried
  as **data**: `gsd-sdk query state.json` plus `.planning/{STATE,ROADMAP}.md`, extracting `current_phase`,
  `plan_of`/`plans_total`, `progress`, `status`. Then three named hard stops, each with its own exit text and
  a `--force` bypass: unresolved checkpoint (`.planning/.continue-here.md` exists → *"Read the file, resolve
  the issue, then delete it to continue"*), `status: error|failed`, and unresolved `FAIL` items in the phase's
  `VERIFICATION.md`. No `.planning/` → *"No GSD project detected. Run `/gsd:new-project`"* and exit.
  Scale caution from the same fetch: gsd ships **66** files under `commands/gsd/` — steal the mechanism, not
  the surface.

## BLUF (12 lines)

1. **Best today — the deterministic spine.** `new-spec` / `plan-lint` / `slice-brief` / `slice-overlap` /
   `review-package` + C7 grammar + `build-slices.js` waves are the only parts no model can fudge. Keep verbatim.
2. **Best today — scanner ≠ fixer ≠ verifier** with the anchored 0/25/50/75/100 re-score and ≥80 keep rule
   (`flow/review.md`). Cheap, structural, already implemented in `workflows/review-diff.js`. Keep.
3. **Best today — two real human gates** (plan approval, user verification) that never delegate into a
   workflow, and evidence-as-deliverable in `.claude/verification/`. Keep.
4. **Improve #1 — one middle, not three.** Delete `/flow-to-issues`' `plan.md` grammar and the `issues/`
   directory; keep `gh issue create` as an optional *publish* verb over the C7 plan, spec-kit style.
5. **Improve #2 — make `/flow-spec` → `/flow` a real handoff.** flow-spec must call `scripts/new-spec` and
   write `.claude/flow.json`; `/flow` must accept an existing `spec_dir` instead of allocating a second one (L7).
6. **Improve #3 — position becomes data.** Add `phase` and `plan` to `flow.json`; make `flow next` read
   git-toplevel-anchored state and emit one runnable token, prose in `why` (FU-09, FU-18).
7. **Improve #4 — collapse the progress representations from six to one.** The plan file's checkboxes are the
   only ones three scripts already parse; delete the workflow-state mirror and the PROGRESS.md override.
8. **Improve #5 — the gate manifest must be true.** Either batch discovery into one turn or say "10 stops".
   A manifest that says 2 and delivers 12 trains the user to stop reading it.
9. **Improve #6 — 1,400 → ~600 lines.** `shared/review.md` (242) duplicates `flow/review.md` (56);
   `spec-template.md` (401) is the single largest mandatory read on every run at every size tier.
10. **Steal from spec-kit** — the one-file task list with a strict, example-driven line grammar and a
    *read-only* checklist gate rendered as a PASS/FAIL table; issues as a separate optional publish command.
11. **Steal from gsd** — `--next` as state-queried data with three named hard stops, each carrying its own
    exit text and a `--force` bypass, and a `.continue-here` sentinel that must be deleted by hand to advance.
12. **Do not steal gsd's surface** (66 commands) or its advisory-only hooks; and do not steal spec-kit's
    `constitution`/`converge` layer — the developer's constraint is fewer nouns, not more.
