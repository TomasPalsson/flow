# gsd (get-shit-done) at source — for the flow pipeline redesign

## 0. Sources, provenance, canonicity

| Source | What was read | Rev / date | Class |
|---|---|---|---|
| `open-gsd/gsd-core` @ `0a09057`, v1.13.0 | full clone: `commands/gsd/*`, `gsd-core/{workflows,references,templates}`, `hooks/`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`, `.out-of-scope/` | 2026-09-07 | PRIMARY (this pass) |
| `gh api repos/open-gsd/gsd-core` | 9,180★, pushed 2026-09-07 | 2026-09-07 | PRIMARY |
| `gh api repos/gsd-build/get-shit-done` | 64,583★, **`archived: true`**, last push 2026-05-31 | 2026-09-07 | PRIMARY |
| `docs/research/raw/frameworks/get-shit-done.md` | §matrix, §mechanisms, §weaknesses | 2026-09-07 | prior work — cited, not repeated |
| `docs/research/raw/idiot-proof/superpowers-gsd-ace-ccpm.md` §3 | 19 guard hooks, `hook-exit.js`, graduation | 2026-09-07 | prior work — cited, not repeated |
| `docs/research/02-frameworks-source-review.md` §1/§3/§5, `10-idiot-proof-harness-2026.md` §3 | matrix, steal list, flow v2 skeleton | 2026-09-07 | prior work |

**Canonicity ruling (new this pass):** `glittercowboy/get-shit-done` now 301-redirects to `gsd-build/get-shit-done`, which is **archived**. The living project is `open-gsd/gsd-core`, npm `@opengsd/gsd-core`. Everything below is quoted from the v1.13.0 tree unless marked otherwise. The archived 64.5k★ repo is the one most blog posts describe; do not design against it.

---

## 1. The `.planning/` directory model — the whole idea in one tree

`docs/ARCHITECTURE.md:87`: *"All state lives in `.planning/` as human-readable Markdown and JSON. No database, no server, no external dependencies."* This is the anti-GitHub-issues answer the flow redesign is looking for, and it is load-bearing, not cosmetic — every routing decision in §3 is a filesystem predicate over this tree.

```
.planning/
├── PROJECT.md          # vision, constraints, decisions, evolution rules
├── REQUIREMENTS.md     # scoped: v1 / v2 / out-of-scope
├── ROADMAP.md          # phase breakdown + status + ## Backlog (999.x numbering)
├── STATE.md            # living memory: position, decisions, blockers, metrics
├── config.json         # workflow config (live-reloaded by a FileChanged hook)
├── MILESTONES.md
├── phases/XX-name/
│   ├── XX-CONTEXT.md       # decisions locked during /gsd:discuss-phase
│   ├── XX-RESEARCH.md      # ecosystem research (plan-phase)
│   ├── XX-YY-PLAN.md       # one per parallelizable unit of work
│   ├── XX-YY-SUMMARY.md    # executor → verifier handoff, one per PLAN
│   ├── XX-VERIFICATION.md  # goal-level verdict: passed / human_needed / gaps_found
│   └── XX-UAT.md, XX-VALIDATION.md, XX-UI-SPEC.md, XX-UI-REVIEW.md
├── quick/YYMMDD-xxx-slug/{PLAN,SUMMARY}.md
├── todos/{pending,completed}/   ├── threads/   ├── seeds/
├── debug/{*.md, resolved/, knowledge-base.md}
└── .continue-here.md + HANDOFF.json     # pause/resume handoff
```

**PLAN ↔ SUMMARY pairing is the schema's one real invariant.** "Work is unfinished" is defined nowhere as a status field — it is `plans.length > summaries.length` for a phase (`workflows/next.md`, Route 0 and Route 4). A file's *existence* is the state machine. Nothing can lie about it, no field can drift.

**STATE.md is capped, and the cap is argued** (`templates/state.md`, `<size_constraint>`):
> "Keep STATE.md under 100 lines. It's a DIGEST, not an archive. … The goal is 'read once, know where we are' — if it's too long, that fails."

Sections: Project Reference / Current Position (`Phase X of Y`, `Plan A of B`, status, progress bar) / Performance Metrics (velocity, avg min per plan, trend) / Accumulated Context (Decisions, Pending Todos, Blockers) / Deferred Items / Session Continuity (`Resume file:` path or `None`). Frontmatter (`status`, `progress.{total,completed}_{phases,plans}`, `percent`) is **generated from a schema** — `src/state-md-schema.cts` via `scripts/gen-state-md-docs.cjs --write`, with a `<!-- STATE-MD-SCHEMA:START -->` do-not-hand-edit region. The prose body is hand-authored; the machine-read fields are not. That split is the reason `/gsd:next` can trust the file.

---

## 2. Command set — 72 commands, of which ~6 are the loop

`ls commands/gsd/*.md` → **72**; `agents/*.md` → **35**; `skills/` → **72**; `gsd-core/references/*.md` → **112**; `gsd-core/**/*.md` → **64,508 lines**; `agents/*.md` → **15,771 lines**; `docs/**/*.md` → 610 files incl. **91 ADRs**; `tests/` → 1,133 files; `src/` → 234 TS files.

README's own pitch is a **five-step loop**, not 72 commands: *"1. Discuss … 2. Plan … 3. Execute … 4. Verify … 5. Ship."* The daily set is `new-project | onboard → discuss-phase → plan-phase → execute-phase → verify-work → ship`, with `next`, `progress`, `quick`, `debug`, `capture`, `pause-work`/`resume-work` as connective tissue. The other ~60 (`graphify`, `mempalace-capture`, `ns-ideate`, `nyquist` validation, `forensics`, `ultraplan-phase`, `eval-review`, `profile-user`, `workstreams`…) are optional lanes. **The five-step README and the 72-command tree are two different products**; the redesign should copy the README.

Note `/gsd:next` is now a thin router onto `smart-entry.md`, and the routing logic quoted in §3 has migrated to `/gsd:progress --next`. Same algorithm, two front doors — itself a symptom of the surface sprawl.

---

## 3. `/gsd:next` — the single best mechanism in the system

`gsd-core/workflows/next.md` (364 lines). Reads `gsd_run query state.json`, STATE.md, ROADMAP.md, then routes. Verbatim decision table (`<step name="determine_next_action">`):

```
Route 1: ROADMAP has phases, no phase dirs on disk        → /gsd:discuss-phase <first>
Route 2: phase dir exists, no CONTEXT.md and no RESEARCH.md → /gsd:discuss-phase <current>
Route 3: has CONTEXT.md (or RESEARCH.md), no PLAN.md files → /gsd:plan-phase <current>
Route 4: plans exist, not all have matching summaries      → /gsd:execute-phase <current>
Route 5: all plans have summaries                          → /gsd:verify-work
Route 6: current phase complete, next phase in ROADMAP     → /gsd:discuss-phase <next>
Route 7: all phases complete                               → /gsd:complete-milestone
Route 8: STATE.md shows paused_at                          → /gsd:resume-work
```

Three properties make this worth stealing wholesale:

1. **Every predicate is a file test.** No `status: in_progress` string is trusted for routing. A crashed session, a `git checkout`, a manual file deletion — all self-heal, because the answer is recomputed from disk each time.
2. **Three hard-stop gates run before routing**, each naming its own bypass in the deny text: Gate 1 `.planning/.continue-here.md` exists ("*⛔ Hard stop: Unresolved checkpoint … Use `--force` to bypass this check.*"); Gate 2 STATE.md `status: error|failed`; Gate 3 VERIFICATION.md with un-overridden `FAIL` items.
3. **Route 0 (`resume_incomplete_phase`) is a hard invariant that ignores `current_phase`.** It scans *all* phases lowest-first for `plans.length > summaries.length` and resumes the first hit. The comment says why: *"This catches the common failure mode where a session died mid-execution (hang, token exhaustion, API connection drop) and STATE.md's `current_phase` got advanced past the phase that actually has unfinished work."* And critically, a `roadmap.analyze` whose `scope != "complete"` is treated as **scan-failed, not clean** (#3184/#3165): *"a NON-answer rather than a real empty. Looping it would run the invariant over a phase list the scan could not populate and report 'clean' — the silent disarm."* A derived-state router must distinguish "I looked and found nothing" from "I could not look."

`--auto` re-invokes `/gsd:next --auto` after each dispatched command, chaining until a milestone completes, a gate fires, or a human decision is needed. That is the unattended mode, and it costs ~20 lines because the router is already total.

Zero-friction is explicit: *"Then immediately invoke the determined command via SlashCommand. Do not ask for confirmation — the whole point of `/gsd:progress --next` is zero-friction advancement."*

---

## 4. PLAN.md — the XML task format and wave execution

`gsd-core/templates/phase-prompt.md` defines `.planning/phases/XX-name/{phase}-{plan}-PLAN.md`. Frontmatter is the scheduler's input:

```yaml
phase: XX-name        plan: NN        type: execute
wave: N               # execution wave, PRE-COMPUTED AT PLAN TIME
depends_on: []        # plan ids, e.g. ["01-01"]
files_modified: []    # ← the parallel-safety declaration
files_deleted: []     # exact paths, not globs — undeclared deletion blocks worktree merge
coupling_justified: []# "plan-id: reason" — exempts a deliberate same-wave pair from the checker
autonomous: true      # false ⇒ plan contains blocking checkpoints
requirements: []      # REQUIRED, MUST NOT be empty — ids from ROADMAP
must_haves:           # goal-backward verification, derived at PLAN time, checked after
  truths: []          #   observable behaviours that must be true
  artifacts: []       #   files that must exist with real implementation
  key_links: []       #   critical connections between artifacts
```

Body: `<objective>`, `<execution_context>` (@-refs to the executor's own workflow), `<context>` (@-refs to PROJECT/ROADMAP/STATE + source files — with the anti-pattern called out inline: *"Do NOT reflexively chain: Plan 02 refs 01, Plan 03 refs 02…"*), then `<tasks>` of three types:

```xml
<task type="auto">
  <name>…</name> <files>…</files> <read_first>…</read_first>
  <action>… Include CONCRETE values: exact identifiers, parameters, expected outputs,
          file paths, command arguments. Never say "align X with Y" without specifying
          the exact target state.</action>
  <verify>[command or check to prove it worked]</verify>
  <acceptance_criteria>- [Grep-verifiable: "file.ext contains 'exact string'"]</acceptance_criteria>
</task>
<task type="checkpoint:decision"     gate="blocking"> <options><option id=…>…  <resume-signal>
<task type="checkpoint:human-verify" gate="blocking"> <what-built> <how-to-verify> <resume-signal>
```

Two things flow's slice format does not have: **`acceptance_criteria` demanded grep-verifiable**, and **human gates as a task type inside the plan** rather than as skill prose — so a plan is `autonomous: false` mechanically, and the unattended chain knows to stop.

**Waves** (`workflows/execute-phase.md`, `<step name="execute_waves">`, 1,547 lines total): plans are grouped by the pre-computed `wave`, run in parallel within a wave (each in a disposable git worktree), sequential across waves. Before spawning, the **intra-wave `files_modified` overlap check** compares every pair; on overlap it *"Override `PARALLELIZATION` to `false` for this wave only … This is a safety net for plans that were incorrectly assigned to the same wave."* `--wave N` exists for pacing/quota, with a monotonicity guard: *"If `WAVE_FILTER` is set and there are still incomplete plans in any lower wave … STOP."* Plans with a non-empty `blocked_by` are skipped **by name with a reason** — *"Never silently drop a blocked plan from the report."* `execute-phase/steps/` names 16 discrete gates (codebase-drift, per-plan-worktree, post-merge, regression, protected-branch, worktree-recovery…). flow already has `scripts/slice-overlap`; the missing half is that gsd's check is *derived from a declared field in the plan*, not re-inferred at run time.

---

## 5. Fresh-context discipline — the actual budget numbers

`commands/gsd/execute-phase.md`: *"Context budget: ~15% orchestrator, 100% fresh per subagent."* `references/context-budget.md` makes it operational:

- Rule 1: *"**Never** read agent definition files (`agents/*.md`) — `subagent_type` auto-loads them."*
- Rule 2: *"**Never** inline large files into subagent prompts — tell agents to read files from disk instead."*
- Rule 3, read depth scales with the window: at <500k, *"read only frontmatter, status fields, or summaries. Never read full SUMMARY.md, VERIFICATION.md, or RESEARCH.md bodies."* At ≥500k, full bodies permitted.
- Tiers PEAK 0–30 / GOOD 30–50 / DEGRADING 50–70 / POOR 70%+, wired to `workflow.context_guard_mode` (`auto|warn|off`, default `warn`); `auto` invokes `/gsd:pause-work` before the next wave.
- Named early-warning signals, not just thresholds: *"Silent partial completion … Increasing vagueness — agent starts using phrases like 'appropriate handling' or 'standard patterns' instead of specific code … Skipped steps — if an agent's success criteria has 8 items but it only reports 5, suspect context pressure."*
- And the honest admission: *"the orchestrator cannot verify semantic correctness of agent output — only structural completeness. This is a fundamental limitation. Mitigate with `must_haves.truths` and spot-check verification."*
- Off-topic but the sharpest line in the file: *"Every enabled MCP server injects its tool schema into **every turn** … often dwarfing whatever GSD itself can save through `model_profile` tuning."*

**Handoff is measured, not narrated.** `/gsd:pause-work` writes `.planning/HANDOFF.json` (machine) + `.continue-here.md` (human), scoped to the active context (phase / spike / sketch / deliberation / root). The JSON carries `completed_tasks[]` with commit hashes, `remaining_tasks[]`, `blockers[]`, `async_jobs[]`, `human_actions_pending[]`, `next_action`, `context_notes`, and `uncommitted_files` — which is *"MEASURED, never asserted (#3968). Populate it from an actual call, not from memory — a narrated `[]` over a dirty tree is how 14 plans' worth of uncommitted code went invisible in the wild."* Truncate at 50 entries, *"but NEVER round it to empty."*

---

## 6. The one-off lane: `/gsd:quick`, `/gsd:debug`, `/gsd:capture`

`/gsd:quick` (`workflows/quick.md`, **748 lines**) is gsd's answer to "small change, don't build a phase for it": *"Execute small, ad-hoc tasks with GSD guarantees (atomic commits, STATE.md tracking). Quick mode spawns gsd-planner (quick mode) + gsd-executor(s), tracks tasks in `.planning/quick/`, and updates STATE.md's 'Quick Tasks Completed' table."* Composable escalation flags — `--discuss`, `--research`, `--validate`, and `--full` as their union, normalized so `--discuss --research --validate ≡ --full`. **The escalation ladder is the right idea; the 748 lines and eight hard-coded banner variants are not.** Even bare `/gsd:quick` still spawns two subagents and writes two files — there is no "just edit it" rung.

`/gsd:debug` — resumable scientific-method sessions at `.planning/debug/{slug}.md`, `/gsd:debug continue <slug>`, resolved sessions archived to `debug/resolved/`, plus a persistent `debug/knowledge-base.md`. Slug is sanitized in prose: `^[a-z0-9][a-z0-9-]*$`, max 30 chars, reject `..`, `/`, `\`. **Still prose, still a path-traversal control the model executes** — unchanged from the prior pass's finding. `/gsd:capture` routes `--note | --backlog | --seed` into `todos/pending/`, ROADMAP `## Backlog`, or `seeds/`; `check-todos` surfaces pending todos into STATE.md as one bounded bullet each (240-char cap, repo-relative link, and *"No collapse-by-count fallback — every pending todo gets its own line, always"*).

---

## 7. Hooks — what is actually code

`hooks/hooks.json` registers: SessionStart ×2 (canonical-path, update check); PreToolUse on `Write|Edit` (prompt-guard, read-guard), `Write|Edit|MultiEdit` (worktree-path-guard), `Write` (write-guard), `Read|Grep|Bash` (secret-read-guard), `Agent|Task` (agent-isolation-guard); PostToolUse on `Bash|Edit|Write|MultiEdit|Agent|Task` (context-monitor) and `Read|WebFetch|WebSearch` (injection-scanner); SubagentStop / Stop / PreCompact (context-monitor); **FileChanged on `config.json`** for live config reload. 28 hook scripts total.

The single most portable file in the repo is `hooks/lib/hook-exit.js` — 81 lines, `{HOOK_ON_CRASH, allow, deny, crash}`, where `onCrash` is a **required argument with no default**: *"a shared helper that silently defaulted to either would let a future hook inherit the wrong policy by omission … Requiring the caller to name its policy at every call site — not just once at module load — makes 'I forgot to decide' a load-time/call-time crash instead of a silent behavior."* An unrecognised policy terminates via `terminateNow('INTERNAL', …)` *"because throwing would unwind into the CALLER's own outer catch — the exact fail-open-by-accident hazard this module removes."* (Full 19-guard treatment — write-guard's 40% shrink floor, the single-use `.gsd-allow-shrink` sentinel, the `git add -f` hard block — is in `raw/idiot-proof/superpowers-gsd-ace-ccpm.md` §3; not repeated.)

Correction to the earlier pass: `gsd-validate-commit.sh` is no longer the *only* denying hook in v1.13.0 — `agent-isolation-guard`, `worktree-path-guard`, `write-guard`, `secret-read-guard` and `workflow-guard` (one leg) all emit deny. The posture claim that survives is narrower and still true: **the workflow gates are prose; only the tool-boundary invariants are code.**

---

## 8. What gsd does BEST

1. **Derived resume, not stored resume.** `/gsd:next`'s 8 routes + Route 0 recompute position from `plans.length > summaries.length`. No status field to desync. This is the answer to "the flow after /flow:spec gets murky" — you never *choose* the next command, you ask.
2. **`.planning/` as the issue tracker.** Markdown + JSON on disk, in the repo, in the diff, reviewable in a PR, greppable, zero network. Everything GitHub issues give (ordering, dependencies, state) minus the API, the auth, the offline gap, and the `gh` dependency.
3. **Parallel safety declared at plan time.** `wave` + `depends_on` + `files_modified` + `files_deleted` in frontmatter turns "can these run together" from a runtime guess into a static check the plan-checker can also lint.
4. **`must_haves.{truths,artifacts,key_links}` derived during planning, verified after execution.** Goal-backward, not task-forward — the verifier checks the phase's actual goal, not that tasks were ticked.
5. **Handoff facts are measured.** `uncommitted_files` from `git status --porcelain`, never from memory; `[]` may not be narrated.
6. **Bounded human interruption.** graduation promotes a learning to a rule only after **≥3 distinct phases** (Jaccard ≥0.25 clustering), with dismissed/deferred `cluster_id`s recorded in STATE.md so a declined suggestion never returns.
7. **A deletion register.** `.out-of-scope/` — 16 files, one per rejected proposal, each with `**Decision:** wontfix`, a date, an issue link, and a "why GSD does not own this" argument.
8. **Escalation by flag, not by separate command.** `quick` → `--validate` → `--discuss` → `--research` → `--full` is one command with rungs.

## 9. What is bloated

- **Surface:** 72 commands / 35 agents / 72 skills / 112 references / 64.5k lines of markdown to express a **five-step loop**. Two front doors (`/gsd:next` and `/gsd:progress --next`) for one router.
- **Prompt load per invocation:** `/gsd:execute-phase` = 65-line wrapper → `workflows/execute-phase.md` (1,547) + `ui-brand` + `agent-contracts` + `context-budget` + `gates` + 6 more @-refs + `transition.md` (720) ≈ **3,005 lines before a single project file is read** — inside a workflow whose stated budget is "~15% orchestrator."
- **The `gsd_run` resolver.** A ~2,300-character single-line bash preamble probing 18 runtime config dirs, pasted **verbatim into every workflow that shells out** (next.md, quick.md, pause-work.md, …). Pure cross-runtime portability tax; a solo Claude-Code-only harness pays none of it.
- **`/gsd:quick` at 748 lines** with eight banner variants, and no rung below "spawn a planner and an executor."
- **Gate semantics are prose.** `references/gates.md` (pre-flight / revision / escalation / abort) and `revision-loop.md` (cap 3 + stall detection) are documentation; nothing enforces that a gate ran. Same for the debug slug regex.

**CORRECTION — "it deleted 3,065 lines for unclear value" is not a real event.** No such phrasing exists anywhere in `open-gsd/gsd-core` or the archived `gsd-build/get-shit-done` (grepped CHANGELOG, docs/, `.out-of-scope/`). `3065` is an **issue number**: CHANGELOG:729 — *"The composer's load-bearing-fragment guarantee is now enforced, not just documented … (#3065) (#3068)"*, a context-composer gate, an *addition*. The premise appears to be a misread issue ref (this repeats the prior pass's finding at `superpowers-gsd-ace-ccpm.md:337`). The real, dated deletions are better evidence anyway:
- **#1891/#3422** — *"Removed the orphaned `verify-phase` workflow (~40 KB shipped to every runtime, never loaded) — its still-live verification gates … moved to a reference the verifier agent actually loads, so they run again instead of shipping as dead prose."* A 40 KB per-install prompt file that no code path loaded, discovered only when someone measured.
- **#3271/#3285** — ~5,800 duplicated test lines deleted; *"Every duplicated block registered and passed twice, so nothing reported it"* — plus a new `local/no-duplicate-fold-marker` ESLint rule so it cannot recur.
- **#2020/#2027** — dead `sdk/` refs in runtime markdown caused runtimes resolving doc references by filesystem search to run `find / -iname …`; on Git Bash for Windows that traversed the whole disk (14h+, 4M+ open handles, unkillable).

The pattern across all three: **dead prose in a prompt tree is not free, and it is invisible until something measures it.** That is the transferable lesson, not a line count.

## 10. What a solo dev drops

Drop outright: the multi-runtime installer and the `gsd_run` resolver preamble (Claude Code only); `workstreams`, `ns-*`, `mempalace-*`, `graphify`, `forensics`, `profile-user`, `eval-review`, `ultraplan-phase`, `nyquist`/VALIDATION, UI-SPEC/UI-REVIEW/UAT artifacts; `complete-milestone` + MILESTONES.md + retrospectives (a solo dev's milestone is a merged PR); PROJECT.md **and** REQUIREMENTS.md **and** ROADMAP.md as three files — collapse to spec + roadmap; per-phase RESEARCH.md as a mandatory step; `discuss-phase` as a separate command (fold into plan); the 35-agent roster (flow needs ~4: planner, executor, reviewer, verifier); STATE.md's Performance Metrics table (velocity trends are a team artifact).

Keep, ported: the `.planning/`-shaped dir (flow's `.specs/<NNN>/`), the PLAN↔SUMMARY existence invariant, the `next` router, PLAN frontmatter (`wave`/`depends_on`/`files_modified`/`must_haves`), the checkpoint task types, the 100-line STATE cap, measured `uncommitted_files`, `.out-of-scope/`, `hook-exit.js`'s required crash policy, and the `--full` escalation ladder — with a true zero-ceremony rung at the bottom.

---

## 11. BLUF (12 lines)

1. **BEST — derived resume.** `/gsd:next` recomputes position from disk (`plans > summaries`, 8 routes, 3 hard-stop gates, Route 0 scans *all* phases). Nothing to desync; a crashed session self-heals. This is the fix for "after /flow:spec it gets murky."
2. **BEST — `.planning/` beats GitHub issues.** Markdown + JSON in the repo, in the diff, greppable, offline, no `gh`. *"No database, no server, no external dependencies."*
3. **BEST — parallel safety is declared, not guessed.** `wave` + `depends_on` + `files_modified` + `files_deleted` in PLAN frontmatter; an intra-wave overlap forces that wave sequential.
4. **BEST — measured over narrated.** `uncommitted_files` from `git status --porcelain`; `[]` may not be asserted from memory (#3968).
5. **BEST — bounded nagging + a deletion register.** graduation promotes at ≥3 distinct phases with a dismissed backlog; `.out-of-scope/` records 16 wontfixes with dates and arguments.
6. **IMPROVE — 72 commands for a 5-step loop.** Two routers for one decision; the README's own five steps are the honest product.
7. **IMPROVE — 3,005 prompt lines to run one `/gsd:execute-phase`** inside a workflow budgeted at "~15% orchestrator."
8. **IMPROVE — no zero-ceremony rung.** Bare `/gsd:quick` (748 lines) still spawns a planner + an executor and writes two files.
9. **IMPROVE — gate semantics are prose.** `gates.md`, `revision-loop.md` and the debug slug regex are documentation; only tool-boundary invariants are code.
10. **CORRECTION — the "3,065 lines for unclear value" deletion never happened**; `3065` is an issue number for an *added* context gate. The real lesson is #1891: a 40 KB workflow shipped to every install that **no code path loaded**, found only by measuring.
11. **STEAL 1 — `/flow:next`.** Port the 8-route table + Route 0 over `.specs/<NNN>/`, predicates = file existence only, `--auto` to chain, three hard-stop gates each naming its own bypass.
12. **STEAL 2 — slice frontmatter + escalation ladder.** `wave/depends_on/files_modified/must_haves{truths,artifacts,key_links}` + `checkpoint:decision|human-verify` as task types (so `autonomous:false` is mechanical), and one `/flow:do` with `--validate/--discuss/--research/--full` rungs — bottom rung being "just edit it."
