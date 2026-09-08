# flow redesign — two commands, one folder, one list (2026-09-07)

Synthesis of three designs, three adversarial judgements, and the raw source reads in
`docs/research/raw/flow-redesign/`. Every mechanism below was re-fetched from upstream this session
unless marked otherwise. **PRIMARY** = read from source (in this tree or fetched 2026-09-07);
**SECONDARY** = prior research in `docs/research/`; **UNVERIFIED** = asserted, not fetched.
Not repeated, cited instead: `02-frameworks-source-review.md` §1/§3/§5 · `10-idiot-proof-harness-2026.md`
§2 (P1–P5) and §3 (mechanism table) · `raw/flow-redesign/{current-flow,spec-kit,gsd,openspec-bmad}.md`.

## 1. BLUF

1. **Ship v2's shape on v3-A's ground.** Two slash commands — `/flow:spec` to open, `/flow:next` run
   until it says idle — over `.specs/NNN-slug/`, not a new `.flow/`. Aggregate judge score: v2 148,
   v3-folder 145, v3-router 135; v2 won 2 of 3 ballots.
2. **`.specs/` is not cosmetic, it is the migration.** `_sg20_is_source` exempts `.specs/*`,
   `.claude/*`, `docs/*` and `*.md` (PRIMARY, `hooks/spec-gate.sh:31-35`, `hooks/stop-gate.sh:34-38`).
   An extensionless `.flow/current` matches none of them, so v2 and v3-B both deny their own first
   write on a `flow/*` branch. `scripts/new-spec` already takes `--dir` (default `.specs`, line 126).
3. **The pointer question is settled by source, and both sides were wrong.** gsd has no "Route 0"
   (PRIMARY: `get-shit-done/workflows/next.md`, routes 1–8 at lines 163-191, all reading STATE.md's
   `current_phase`). It has a *prior-phase completeness scan* at lines 85-120 that **reports and asks**
   — `[C] Continue / [S] Stop (recommended) / [F] Force`, default S. Keep the pointer; add the scan as
   report-and-halt. A pointer can go stale; a silent scan-override can be wrong *confidently*.
4. **`bounded` is superpowers', and two judges were wrong to call it a flow invention.** PRIMARY,
   `skills/brainstorming/SKILL.md:29-52`: spike / bounded / architectural, bounded = *"No spec file, no
   implementation plan document"* (:44), one-way ratchet (:51), and the rule that decides the small-change
   fight: *"a bounded task's approval is as hard a gate as an architectural one"* (:43), *"What scales
   with simplicity is the artifact, never the approval"* (:60). So `bounded` keeps exactly one decision.
5. **Take the write away from the model.** `flow tick <ID>` is the only writer of `[x]`, appending a
   *measured* `git rev-parse --short HEAD`; the Stop hook blocks a sha-less `[x]` in the same turn.
   This closes spec-kit's weakest link verbatim (PRIMARY, `templates/commands/implement.md:169`:
   *"**IMPORTANT** For completed tasks, make sure to mark the task off as [X]"* — honour system, nothing behind it).
6. **Done is a file named after the tree it verified.** `PASS-<sha>.md` (machine) + a dated `Verified:`
   line (human). A later commit invalidates the machine half for free, with zero invalidation logic.
7. **Cannot-judge is not pass.** Row 0 of the router: an unreadable `.specs/`, a git failure or a
   permission error prints `scan-failed`, never `idle`. `10-idiot-proof-harness-2026.md` §2 P2 names
   this as the single change with the largest return; all three designs but one omitted it.
8. **Delete the GitHub middle, keep `gh`.** `issues/` was never the dependency — the dependency was a
   third artifact shape fed by a manual `/flow-handoff` × N loop. `flow publish` survives as an
   off-pipeline leaf, exactly as spec-kit ships `taskstoissues` beside `tasks.md`.
9. **Numbers.** Pipeline skill text 3,564 → ~600 (measured today: flow-spec 1221, flow 708, feature 1298,
   flow-to-issues 242, flow-handoff 95). Mandatory reads on a Medium run ~1,400 → ~470. State files 22 → 6.
   Plan grammars 2 → 1. Progress representations 6 → 1. User decisions 10–12 → 4, honestly declared.
10. **Biggest residual risk is the one nobody scored: `bin/flow:2025-2033`.** `computeNext` returns on
    PROGRESS.md's `## Now` bullet *before* it reads any flow state (PRIMARY). Ship the new router on top
    of that and a stale bullet silently outranks the whole redesign.

## 2. What each framework does best — and what to improve

| Mechanism (source) | Why it works | Its cost | Verdict for flow |
|---|---|---|---|
| **spec-kit** — one `tasks.md` per feature, strict line grammar, `[ ]→[x]` in place (PRIMARY `templates/commands/tasks.md`) | Plan, progress and resume are the same bytes; nothing can desync | ~30 lines of grammar taught in prose and parsed by **nothing** | **Steal + fix.** Same file, but `flow lint` is the parser spec-kit never wrote |
| spec-kit — `get_feature_paths`: env → `.specify/feature.json` → error naming its own fix (PRIMARY `scripts/bash/common.sh:180-207`) | Survives worktrees, detached HEAD, renames; the error is the remedy | A stored pointer can outlive the thing it points at | **Steal**, and pair with gsd's scan (row 0/1) |
| spec-kit — `/converge` append-only, **byte-for-byte unchanged when clean** (PRIMARY `converge.md:73-83`) | Re-planning cannot quietly rewrite history; a no-op is provably a no-op | Needs a second pass to be worth running | **Steal wholesale** as `/flow:next`'s amend path |
| spec-kit — `implement.md:169` "mark the task off as [X]" (PRIMARY) | — | **Pure honour system**; no verification anywhere behind it | **Improve:** `flow tick` measures the sha; the model may not type one |
| **gsd** — `next.md` routes 1–8, every predicate a file test, three hard stops each naming `--force` (PRIMARY lines 38-81, 163-191) | Crash, `/clear`, `git checkout` all self-heal; a stop always publishes its own exit | 220 lines of workflow prose on top of a 345-line TS router | **Steal the table, not the surface.** 11 rows, in `bin/flow` |
| gsd — prior-phase completeness scan → structured report + `[C]/[S]/[F]`, default **Stop** (PRIMARY `next.md:85-120`) | Catches "a session died and `current_phase` advanced past unfinished work" *without* guessing for you | Costs one interactive question | **Steal.** This is the correct fix for both v2's stale pointer and v3-A's silent scan |
| gsd — `.next-call-count` consecutive-invocation gate, `--force` bypass (PRIMARY `sdk/src/query/route-next-action.ts:17-23`) | A router meant to be run in a loop cannot loop forever on one mis-encoded state | One more file | **Steal.** All three designs shipped an unbounded `--unattended` loop |
| gsd — `routeNextAction` returns `{command, args, reason, current_phase, gates, context}` (PRIMARY, same file) | Gates travel as **data**; the caller halts, so hooks and status lines can query without tripping a stop | Callers must remember to read them | **Steal** the JSON shape verbatim |
| gsd — `files_modified` declared at plan time, waves pre-computed (SECONDARY `raw/.../gsd.md` §4) | Parallel safety is proved before dispatch, not guessed at run time | Plan-time cost | flow already has `slice-overlap`; **make it mandatory, not advisory** |
| **OpenSpec** — state is file existence + `- [x]`, zero status fields; `status --json` in dependency order | Nothing to desync; "what next" is data with a command attached | Flat ceremony — four artifacts for a rename | **Steal the principle**, reject the ceremony |
| OpenSpec — `ValidationIssue {level, path, message, line?, column?}` (PRIMARY `src/core/validation/types.ts:3-9`) | ERROR/WARNING/INFO tiers a caller can filter | **There is no `fix` field** — the three designs all mis-cited this | **Own it:** flow's `fix:` string is flow's, informed by `nextSteps` |
| **BMAD** — route gate: intent gaps × irreversibles × footprint → `oneshot` EARLY EXIT \| `dispatch`, reversible mid-flight (SECONDARY §2e) | Ceremony keyed to what ceremony protects against, computed not argued | Two routes only; still writes a spec file on the light one | **Steal the gate, add a third rung** (`bounded` below it) |
| BMAD — judge the orchestrator-rebuilt diff from `baseline_commit`, never the worker's report; matrix audit: *a covering test that did not run counts as missing* | Removes self-report from the verdict entirely | Needs a recorded baseline | **Steal both**; enforce the matrix rule in `stop-gate.sh`, not in prose |
| **superpowers** — spike/bounded/architectural; bounded ships **no spec file, no plan doc**; approval never scales down (PRIMARY `brainstorming/SKILL.md:29-60`) | The only escape from ceremony that is a *route*, not a missing feature | Classification is prose the model must honour | **Steal, correctly attributed**, incl. the "reaching for a lighter label IS the doubt" ratchet |
| superpowers — `review-package PLAN BASE HEAD`, BASE recorded before dispatch, *"never `HEAD~1`, which silently drops all but the last commit"* (PRIMARY `subagent-driven-development/SKILL.md:290`) | A multi-commit task is reviewed whole | — | flow ships the script; **add the rule** |
| superpowers — `task-brief`: fence-aware awk of one task; *"Never make a subagent read the whole plan file"* | Worker context is a file, not a paste | — | **Keep**, rename `slice-brief` → `task-brief` |
| superpowers — one fix dispatch for the whole final review; `Ruling:` lines collected at the end (*"a ruling that dies with the workspace was a decision made in secret"*) | Per-finding fixers cost more than the build | — | **Steal**, and dump rulings into the PR body |
| **flow today** — `new-spec`, `plan-lint`, `slice-overlap`, `slice-brief`, `review-package`, `build-slices.js`, `stop-gate.sh` | The only parts no model can fudge | Wired to a hardcoded `.claude/feature-plan.local.md` | **Keep verbatim; retarget the paths** |

## 3. The design

### 3.1 Command surface — 2 slash, 5 CLI

| Command | Semantics |
|---|---|
| `/flow:spec <idea>` | Route gate (`bounded｜oneshot｜dispatch`) → one batched discovery turn → write only what the route needs → `flow use`. **The only door.** Flags: `--amend "<change>"`, `--interview`, `--unattended`. |
| `/flow:next` | Do the one thing `flow next --json` names. **The only build verb**; run it until it says idle. Flags: `--force`, `--escalate`, `--qa`, `--unattended`. |
| `flow next [--json] [--force]` | Router. Pure query of disk → `{state, command, why, gates:{blocked, lint_error, unreachable_done, scan_failed, consecutive_calls}}`. |
| `flow lint [--waves] [--json]` | Parse `TASKS.md`; ERROR/WARN/INFO, each with a `fix:` string; prove `[P]` disjointness; join `[x]`→sha→`files:`; detect vanished IDs; compute waves. |
| `flow tick <ID>` | **The only writer of `[x]`.** Appends `— done: <measured git rev-parse --short HEAD>`. |
| `flow use <NNN-slug>` | Write `.specs/.current`. Only needed with two features open. |
| `flow publish` | Optional leaf: mirror unchecked tasks to GitHub issues. **Never called by the pipeline.** |

Both slash commands ship as `commands/flow/{spec,next}.md`. VERIFIED in this tree: `.claude-plugin/plugin.json`
declares `"skills"` only and there is no `commands/` dir — adding one is two files, versus renaming 10 skill
directories and every cross-reference. Skill dirs stay where they are.

### 3.2 Layout

```
.specs/
  .current                     one line: 003-entry-tagging      (matches .specs/* → hook-exempt)
  .next-call-count             consecutive `flow next` invocations; reset by any state change
  LEDGER.md                    append-only: one line per shipped feature + every Ruling:
  003-entry-tagging/
    spec.md                    ~110-line template (§3.3)
    design.md                  only when 2+ tasks share a name / id type / error shape / resource
    TASKS.md                   plan + progress + resume + commit ledger.  THE state
    NOTES.md                   append-only: Discovered:, Ruling:, Amendment refs
    PASS-<sha>.md              tracked. The machine half of "done"; a later commit invalidates it
    verify/                    tracked evidence. A verification claim with no artifact here does not count
    review/                    GITIGNORED. Diffs only. NEVER a routing predicate
  archive/2026-09-08-002-price-rules/
```

Deleted: `.claude/flow.json`, `workflow-state.local.md`, `feature-plan.local.md`, `.claude/slices/`,
`.claude/quality/`, `.claude/verification/`, `issues/`, `/tmp/flow-handoff-*`, `plan.mdx`, `.qa-report/`.
**22 state files → 6.** Generated artifacts are never predicates: `review/` is gitignored and unreadable
by the router; `verify/` and `PASS-<sha>.md` are tracked *because* they are predicates.

Resolution, anchored at `git rev-parse --show-toplevel` (kills FU-09/L2):
`$FLOW_SPEC` → `.specs/.current` → branch `flow/<slug>` exact match → error naming its own fix. Then,
**before routing**, the completeness scan: any other `.specs/NNN-*/TASKS.md` with an `Approved:` line and an
unchecked `- [ ]` is reported, not switched to (§3.4 row 1b).

### 3.3 `spec.md` — what survives flow-spec's 1,487 lines

Template **401 → ~110**. Keep: TL;DR + MVP cut line · 1.1 Problem · 1.2 Roles · 2.1 In scope / 2.2 Non-goals ·
3 Journeys (happy + error + edge, Given/When/Then) · 4.1 FRs with MoSCoW · 5 NFRs **only where a number
exists** · 6.1 Launch criteria · 7.2 Assumptions · 8 Open questions (cap 3) · Appendix A Glossary.
Cut: 1.3 Prior Art, 2.3 Adjacent Systems, 4.2/4.3, 5.5–5.9 without numbers, 6.2/6.3, 7.1/7.3,
9 Revision History (git has it), Appendix B/C, the Size Variant table (the route gate replaces it), and the
Anti-Pattern Defense Map (a doc about the doc). `question-bank.md` **278 → ~65**, asked as one numbered list
of *pre-answered assumptions* in a single turn — silence is acceptance of a stated position, not a skipped
question; the negative-scope probe and "quantify every adjective" stay as items in the list.
`code-design-doctrine.md` (200) + `pattern-forces.md` (76) → one conditional `design.md` reference (~90),
plus spec-kit's Complexity Tracking table `| Violation | Why needed | Simpler alternative rejected because |`
so over-engineering costs a written justification. `spec-judge` stays, capped at **1** iteration, `dispatch` only.

### 3.4 State machine — every predicate is a file test

| # | State | Encoded by | `flow next` prints | Transition |
|---|---|---|---|---|
| 0 | **scan-failed** | `.specs/` unreadable, git unavailable, or lint crashed | `STOP: cannot read .specs/ — refusing to report clean. <errno>` | fix the environment |
| 1a | Blocked | `.specs/BLOCKED.md` exists | `STOP: read it, fix it, delete it. Bypass: /flow:next --force` | human deletes the file |
| 1b | Disagreement | another approved feature has unchecked `- [ ]` | structured report + `[C] defer / [S] stop (default) / [F] force` | user answers |
| 1c | Looping | `.next-call-count` ≥ 5 with no state change | `STOP: 5 consecutive calls, no progress. --force to continue` | `--force` |
| 1d | Invalid | `flow lint` ERROR | the first ERROR verbatim + its `fix:` | edit `TASKS.md` |
| 1e | Lying | `[x]` whose `done:` sha is not in `Base..HEAD`, or touches none of its `files:` | `STOP: TASKS.md claims T004 done at 8b1d0e3 — not on this branch` | `flow tick` or hand-fix |
| 2 | No project | no `.specs/*/TASKS.md` | `Next: /flow:spec <idea>` · *nothing in flight* | `/flow:spec` |
| 3 | Ambiguous | features on disk, no `.current`, no branch match | `Next: flow use <NNN-slug>` · **never guesses** | `flow use` |
| 4 | Drafting | `.current` set, `spec.md` ∧ no `TASKS.md` | `Next: /flow:next` · *resuming 003; discovery 4 of 6 answered (NOTES.md:12)* | writes `TASKS.md` |
| 5 | Unapproved | `TASKS.md` ∧ no `Approved:` line | `Next: read TASKS.md, reply "approved"` · **HARD GATE** | prepends `Approved: <date> by user` + `Base: <sha>` |
| 6 | Building | ≥1 unchecked `T###` | `Next: /flow:next` · *wave 2 — T002, T003 — verify: pytest tests/test_tags.py (5 of 9 done)* | builds a wave, `flow tick` each |
| 7 | Checkpoint | first unchecked is `CHK###` | that line's own text, verbatim | user answers → `flow tick` |
| 8 | Gating | all `T###` done, `G###` unchecked | `Next: /flow:next` · *9 of 9 tasks done, G001-G003 open* | runs gates, writes `PASS-<sha>.md` |
| 9 | Unverified | `PASS-<HEAD>.md` exists, no `Verified:` | `Next: verify using verify/, reply "approved"` · **HARD GATE** | writes `Verified: <date> by user` |
| 10 | Stale pass | `Verified:` present but newest `PASS-*` ≠ HEAD | `Next: /flow:next` · *3 commits since PASS-a91f0cc* | back to 8 |
| 11 | Shippable | verified ∧ no PR | `Next: /flow:next` · *opening the PR* | `gh pr create --draft` → gates → `gh pr ready` |
| 12 | Shipped | PR exists | `Next: gh pr view --web` · *PR #41; merge, then /flow:next archives* | `git mv` → `.specs/archive/<date>-<NNN>-<slug>` |
| 13 | Idle | nothing unchecked anywhere | `Next: /flow:spec <idea>, or just ask` | — |

Three properties, all from gsd source: one runnable token on `Next:` with prose confined to `Why:`;
every hard stop naming its own bypass inside the deny text; and **the only two stored facts are the two
human events** (`Approved:`, `Verified:`) because nothing on disk implies them. Archiving is a `git mv` —
an atomic directory move with no field to desync — so "shipped" cannot be faked or forgotten.

### 3.5 `TASKS.md` — the whole build state

```markdown
# Tasks — Entry tagging
Spec: spec.md · Design: none · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`
Approved: 2026-09-08 by user
Verified: 2026-09-08 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given an entry, when I POST a tag, then it persists | T002 | test_tag_persists |

## Phase 1 — Tag persistence
Goal: an entry can carry tags and survive a restart.
Independent test: `pytest tests/test_tags.py` — green with the UI untouched.
- [x] T001 Migration + Tag model — files: db/schema.sql, src/models/tag.py — verify: `pytest tests/test_schema.py` — done: 8b1d0e3
- [ ] T002 [P] POST /entries/{id}/tags persists (B1) — files: src/api/tags.py, tests/test_tags.py — verify: `pytest tests/test_tags.py::test_tag_persists`
- [ ] T003 [P] Duplicate tag returns 409 (B2) — files: src/api/dedupe.py, tests/test_dedupe.py — verify: `pytest tests/test_dedupe.py` — after: T001
- [~] T007 Server-side tag search — dropped: B5 moved to spec Amendment 2026-09-09

## Phase 2 — Tag filter UI
- [ ] CHK011 human-verify — filter chip at 375px, dark mode — verify: human: user says yes

## Gates
- [ ] G001 `flow check --fix` exits 0 — verify: `flow check --fix`
- [ ] G002 branch review clean — verify: `PASS-<HEAD>.md` exists
- [ ] G003 browser evidence — verify: `test -s verify/`
```

**Line grammar, parsed by `flow lint`, never remembered by the model:**

```
- [ |x|~] <ID> [P]? <description> — files: <path,path,…> — verify: <`cmd` | human: <observable>>
                                    [— after: <IDs>] [— dropped: <reason>] [— done: <sha>]
```

`files:` is a **comma-separated list, no globs** — one owned path per task is v3-B's fatal flaw: its own
example declares `src/auth/google.ts` and writes `src/auth/google.test.ts`, so two `[P]` tasks sharing a
test file pass validation and then race.

Lint rules (each replaces a rule the model used to carry):

- `[P]` is an **ERROR** unless the task's `files:` intersect no other `[P]` task **in the same wave**.
  Waves are computed from `after:` — this is `slice-overlap` folded in, at task granularity, mandatory.
  (`after:` may name a same-phase task; that just puts them in different waves. v2's own flagship example
  violated its "every `after:` sits in an earlier phase" rule — the rule was wrong, not the example.)
- Missing `verify:` → **ERROR** (OpenSpec: every task states how to verify completion).
- `[x]` whose `done:` sha is unreachable in `Base..HEAD`, **or whose commit touched none of that task's
  `files:`** → **ERROR**. The second half catches "committed something else, ticked the box".
- An ID present in `git show HEAD:.specs/NNN-*/TASKS.md` and absent from the working copy → **ERROR**.
  This is what actually enforces append-only; prose does not.
- `[~]` without `dropped:` → ERROR. Phase without `Goal:`/`Independent test:` → WARN.
  `Route: oneshot` with >5 tasks → INFO (suggest `--escalate`).
- Every ERROR carries a `fix:` string, and `spec-gate.sh` prints it (§5).

### 3.6 Execution model

The route is decided once, by the gate, and written into the TASKS header — so the model never negotiates it.

| Route | Predicate (BMAD's three facts) | Artifacts | Execution |
|---|---|---|---|
| `bounded` | 0 intent gaps, 0 irreversibles, ≤2 files, the flow already exists in this repo | **none under `.specs/NNN/`** — short design in chat, one `LEDGER.md` line | inline, main session |
| `oneshot` | 0 gaps, 0 irreversibles, ≤5 tasks | `TASKS.md` only | inline per task |
| `dispatch` | anything else | `spec.md` + `TASKS.md` (+ `design.md` on the seam trigger) | one fresh subagent per task |

The ratchet is one-way: `--escalate` upgrades; a downgrade needs `--force` and writes a `Ruling:` line.
Reaching for a lighter label because you are unsure *is* the doubt. **The approval gate never scales down** —
`bounded` still costs one "go?" (PRIMARY, superpowers `brainstorming/SKILL.md:43`); only the artifact scales.

Per task on `dispatch`: `scripts/task-brief TASKS.md T003` (renamed `slice-brief`, fence-aware awk) cuts that
task's lines plus its phase header and any matching `## Contract` block into `review/T003-brief.md`. One fresh
`developer` subagent reads **only the brief**. Ready `[P]` tasks in the same wave dispatch in one message,
≤4 parallel; wave N+1 never starts before wave N reports. The `build-slices` Workflow (327 lines, exists) runs
only when a wave has ≥3 ready `[P]` tasks — a 2-task workflow costs more than it schedules.

Per-task loop, `feature/execution-prompt.md` (71 lines, kept verbatim): failing test → verify it fails →
minimal implementation → verify it passes → commit → `flow tick T003` **in the same turn**, which is what
makes the `[x]`→sha→`files:` join meaningful.

### 3.7 Verification and done

1. **Per turn — `hooks/stop-gate.sh`.** The turn cannot end while the tests touching what changed are red.
   Two additions: an `[x]` with no `done:` sha blocks; and a `verify:` command whose test the runner never
   reported as *executed* — unregistered, filtered, skipped — counts as **missing, not passing** (BMAD's
   matrix rule, enforced at the hook rather than stated in a skill). This is the load-bearing test-running
   mechanism precisely because it is not a step in any skill; the model cannot route around it.
2. **Per task.** The orchestrator re-runs the task's own `verify:`; the agent's report is never the gate.
   Then `review-package <task-base>..HEAD` — BASE recorded **before dispatch**, never `HEAD~1` — → two fresh
   adversary lenses (correctness, gaming) → fix ladder ≤3 rounds → a `Ruling:` line in `NOTES.md` at the cap.
3. **Per phase.** The phase's `Independent test:` line is **executed** at the boundary, not just written.
   This catches the class where every task passes its own `verify:` and the slice still does not work.
4. **Per feature — the gates.** `flow check --fix`; one whole-branch fresh-context reviewer over
   `review-package <Base>..HEAD` with the anchored 0/25/50/75/100 blind re-score and ≥80 keep rule, and
   **one** fix dispatch for everything it finds; a converge pass that appends unmet work as new tasks,
   append-only, byte-for-byte no-op when clean. Clean → write `PASS-<HEAD-sha>.md`.
5. **Two halves of done, deliberately kept apart.** `PASS-<sha>.md` = *the gates were green for this tree*
   (self-invalidating: any later commit drops the router back to state 8). The `Verified:` line = *a human
   looked*. UI work requires an artifact in `verify/`; a verification claim with no file there does not count.
   Merging these two is v3-B's fatal flaw — 39% of *plans* get rejected by humans versus 97% of permission
   prompts approved (`10-idiot-proof-harness-2026.md` §2 P4), so the human gate belongs where humans engage.

### 3.8 Resume, and change of mind

**Resume is not a feature.** Position is recomputed from disk on every call, so `/clear`, a crash, a
compaction or a `git checkout` self-heals. `/flow:next` after a dead session prints the same thing it would
have printed before the session died — plus, if the pointer disagrees with the disk, the completeness report.
The `drafting` state (4) resumes a half-finished interview by writing each answer into `NOTES.md` as it is
answered, so dying at question 5 of 8 does not restart discovery from zero.

- **Spec was wrong / scope grew** — `/flow:spec --amend "<what changed>"` appends `## Amendment <date>` to
  `spec.md` (never a silent rewrite), then re-plans **append-only**: new IDs appended, `[x]` tasks never
  renumbered/reordered/deleted, obsoleted unchecked tasks become `- [~] … — dropped: <reason>`, and
  `Approved:` is **cleared** so a scope change cannot ride on a stale approval. Byte-for-byte no-op when nothing changed.
- **Route was wrong** — `/flow:next --escalate`. One-way; downgrade needs `--force` + a `Ruling:`.
- **Something must stop the run** — write `.specs/BLOCKED.md`. A `[ -f ]` presence test cannot be faked by a
  fenced example, a quoted `Ruling:` or a historical line; "delete the file" is also the only instruction
  compatible with an append-only ledger. This is why the sentinel is a file and not a `blocked:` line.

## 4. Worked examples

### 4.1 Medium — entry tagging (route: dispatch)

```
> /flow:spec entry tagging with autocomplete filter
  route facts: intent gaps 2 · irreversibles 0 · footprint ~6 files, 3 behaviors → dispatch
  "Reply 'oneshot' to downgrade."                                            [not a decision — a statement]
  [1] one turn, 5 pre-answered assumptions: "reply with the numbers to change, or 'all good'"
  new-spec "Entry tagging" --dir .specs --prefix flow/   → .specs/003-entry-tagging/, branch flow/entry-tagging
  writes spec.md (108) · spec-judge 1 pass, 101/120 · writes TASKS.md (9 tasks, 2 phases, 3 waves)
  writes .specs/.current · flow lint → OK
  prints: "This run will stop for you 4 times."
  Next: read .specs/003-entry-tagging/TASKS.md, reply "approved"
> approved                              [2] HARD GATE — prepends Approved: + Base: 4f2a91c
> /flow:next   wave 1: T001 → 1 developer subagent → verify → review-package → 2 lenses → flow tick T001
> /flow:next   wave 2: T002 [P] T003 [P] → 2 subagents in one message → 2 ticks
               Phase 1 boundary: `pytest tests/test_tags.py` runs. Green.
> /flow:next   wave 3: T004..T009 → 3 + 3 subagents. stop-gate blocks the turn once on a red test; fixed.
> flow next    Next: /flow:next  Why: CHK011 human-verify — filter chip at 375px, dark mode
> /flow:next   opens the browser, writes verify/{filter.png,console.txt}
> approved                              [3] flow tick CHK011
> /flow:next   G001 flow check --fix ✓ · G002 branch reviewer, 2 findings ≥80, one fix wave, converge no-op
               → PASS-a91f0cc.md ✓ · G003 verify/ non-empty ✓
  Next: verify using .specs/003-entry-tagging/verify/, reply "approved"
> approved                              [4] HARD GATE — writes Verified: 2026-09-08 by user
> /flow:next   gh pr create --draft → re-runs G001-G003 → gh pr ready → rulings from NOTES.md into the body
  Next: gh pr view --web   Why: PR #41 open; merge, then /flow:next archives
```

**4 user decisions**, all four declared up front. Commands typed: 2 distinct tokens. `--interview` restores
serial discovery (4 → 10, opt-in). `--unattended` → 1: user verification defers to PR review, the PR stays
draft, and the `.next-call-count` gate bounds the loop.

### 4.2 Small — /health returns the git sha (route: bounded)

```
> /flow:spec /health should return the git sha
  route facts: gaps 0 · irreversibles 0 · footprint 2 files → bounded
  "Plan: read GIT_SHA at build time, return it in the health payload, test asserts 40-char hex. Go?"
> go                                    [1] the one decision — approval never scales down
  failing test → impl → green (stop-gate confirms) → 1 commit
  appends .specs/LEDGER.md:  2026-09-08 bounded — /health returns git sha — 9c02f1a
> flow next    Next: /flow:spec <idea>, or just ask   Why: nothing in flight
```

**Zero files under `.specs/003-*/`. Zero spec. One decision. Two typed lines.** The escape from ceremony is
a route, not a missing feature — and `--escalate` promotes to `oneshot` the moment it turns out bigger.

## 5. Migration

Line counts measured in this tree, 2026-09-07 (`find <skill> -name '*.md' | xargs cat | wc -l`).

| Skill today | Lines | Fate |
|---|---|---|
| `flow-spec` (5 files) | 1,221 | **KEEP → ~320.** Cuts in §3.3. Delete SKILL.md:232's `/flow-to-issues` hand-off — the literal cause of L7 |
| `flow` (SKILL + steps/00-06 + planning + review + orchestration) | 708 | **MERGE → ~200.** `steps/00-06` (251) deleted: routing moves into `bin/flow`. `review.md` (56) kept |
| `feature/execution-prompt.md` | 71 | **KEEP verbatim** — the per-task TDD machine |
| `feature` (rest: SKILL 449, planning 438, quality-gates 340) | 1,227 | **DELETE.** Third build path. `quality-gates.md` → the `## Gates` block + two review lenses |
| `flow-to-issues` (+ template) | 242 | **DELETE.** Survives as `flow publish`, ~15 lines, off the pipeline |
| `flow-handoff` | 95 | **DELETE.** `.specs/NNN/` + `flow next` **is** the handoff |
| `shared/review.md` | 242 | **DELETE** — duplicate of the live `flow/review.md` (56) |
| `spec-judge` | 707 | Keep; capped at 1 iteration, `dispatch` only |
| `qa` | 1,265 | Keep, demoted to `/flow:next --qa`; off the default path |
| `flow-deepen` | 275 | Keep standalone; **removed from the router's output** (kills today's decision #12) |
| `fix` | 339 | Keep as an independent lane. Bugs are not features |

Pipeline text **3,564 → ~600**. Mandatory Medium reads **~1,400 → ~470** (spec 320 turn-1; build turns:
router 60 + grammar 70 + execution-prompt 71 + review 56 ≈ 257).

**Scripts.** `new-spec` verbatim (its `LC_ALL=C` slug and 3-digit max over worktrees *and* branches is the
best code in the repo) + ~20 lines to write `.specs/.current`. `review-package` verbatim + the BASE rule.
`slice-brief` → `task-brief` (162 → ~90). `plan-lint` (309) + `slice-overlap` (319) → `flow lint`.
**Do not promise 380 lines**: the merge gains severity tiers, wave computation, git-range joins and the
ID-vanish diff; budget ~500 and land it as three PRs (§7 items 3, 5, 6).

**`bin/flow next` (2,234 lines total) must change:**

| Change | Site | Why |
|---|---|---|
| Delete the PROGRESS.md early return | `bin/flow:2025-2033` | It returns *before* any flow state is read; a stale `## Now` bullet silently outranks the entire router (L5) |
| Anchor at `gitToplevel`, not `process.cwd()` | `cmdNext:2182` | FU-09/L2: the router gives different answers at repo root and in `src/lib/api` |
| Replace `readFlowJson` + `feature-plan.local.md` with `.specs` resolution | `computeNext:2035-2036` | env → `.current` → branch → error; then the completeness scan |
| Emit gates as data | `cmdNext:2180-2191` | `{state, command, why, gates:{...}}` so hooks, `flow doctor` and the status line can query without tripping a stop (gsd `routeNextAction`) |
| Add `.next-call-count` | new | `--unattended` is meant to be looped; today nothing bounds it |
| Never print a command the plugin does not ship | `2047, 2063, 2081` | `agents <path>`, `/wrap then /ship`, prose-not-commands (L4). Enforce with a test over the state table's literal output column |
| Row 0: scan-failed ≠ clean | new | `terraform` today reports `clean-no-flow` while `spec-gate.sh` denies every edit on that branch |

**Hooks.** Retarget `spec-gate.sh:118` and `stop-gate.sh:179,225,247` from `.claude/feature-plan.local.md` to
`.specs/.current → TASKS.md` (fixes FU-18/L3's permanent-porcelain block). **No exemption-list change is
needed** — `_sg20_is_source` already exempts `.specs/*` (`spec-gate.sh:33`, `stop-gate.sh:36`), which is a
real and previously unclaimed part of why this migration is the cheapest of the three.
And make the deny text print the objection: `spec-gate.sh` captures `PL_OUT` at line ~74 and never uses it,
so line 170 tells the user a plan is invalid without saying which rule failed. Cheapest fix in the whole set.

## 6. Risks, and the judges' fatal flaws

| Risk / fatal flaw | Whose | Mitigation in this design |
|---|---|---|
| Stale `.current` after a crash or a forgotten `flow done` → the router confidently builds the wrong feature | v2 | State 1b: the completeness scan runs **before** routing and **reports** with `[C]/[S]/[F]`, default Stop. Plus `git mv` archiving replaces the manual `flow done` |
| Silent scan-override with two features open; no `flow use` | v3-A | The pointer is authoritative; the scan can only *report*. `flow use` exists. `$FLOW_SPEC` stays a read-only hatch |
| Verification collapses into shipping; no human-verify artifact | v3-B | `PASS-<sha>.md` and `Verified:` are separate; `CHK###` is a task line the router prints verbatim; `verify/` is a tracked predicate |
| One owned path per task → `[P]` disjointness cannot see the test file | v3-B | `files:` is a list; lint intersects lists per wave |
| `blocked:` as a grep-able line inside an append-only `notes.md` | v3-B | `.specs/BLOCKED.md` presence sentinel |
| Migration cost: skill renames + a 628→380-line script rewrite | v2 | `commands/` files instead of skill renames; `.specs/` instead of `.flow/`; lint budgeted at ~500 and split across three PRs |
| Unbounded `--unattended` loop on one mis-encoded state | all three | `.next-call-count`, `--force` bypass |
| `flow next` prints a command the plugin does not ship | today | A test asserts every literal in the state table's output column resolves to a shipped command |
| PROGRESS.md outranks the new router | today, unmentioned by v3-A | Deleted at `bin/flow:2025-2033` in the first PR |
| **Provenance repairs required before this ships** | — | (a) There is no gsd "Route 0" — routes are 1–8 over `current_phase`; the scan is a prior-phase completeness report (PRIMARY, `workflows/next.md:85-120,163-191`). (b) gsd issue #3968 (cited for "done measured, never narrated") returns 404 — the mechanism is real in `pause-work`'s `uncommitted_files`; cite the file. (c) gsd #3184, cited for "the silent disarm", is titled *"SDK-level phase-complete predicate"* — wrong topic; cite `gsd-verifier.md`'s UNCERTAIN tier instead. (d) OpenSpec's `ValidationIssue` has **no `fix` field** (PRIMARY `types.ts:3-9`); `fix:` is flow's own. (e) **`bounded` IS superpowers'** — two judges searched skill *names* and missed `brainstorming/SKILL.md:29-60`; the attribution stands and its "approval never scales" clause is binding |

## 7. Implementation backlog, ranked

| # | Item | Size | Files |
|---|---|---|---|
| 1 | Delete the PROGRESS.md early return; anchor `computeNext` at `gitToplevel` | **S** | `bin/flow:2016-2033, 2182` |
| 2 | Print `PL_OUT` in the spec-gate deny text | **S** | `hooks/spec-gate.sh:74,170` |
| 3 | `flow lint` v1: parse the grammar, ERROR/WARN/INFO + `fix:` strings (fold `plan-lint`) | **M** | `scripts/flow-lint` (from `scripts/plan-lint` 309) |
| 4 | `flow tick <ID>` + the stop-gate rule that a sha-less `[x]` blocks the turn | **S** | `bin/flow`, `hooks/stop-gate.sh` |
| 5 | `flow lint` v2: `[P]` disjointness per wave + wave computation (fold `slice-overlap`) | **M** | `scripts/flow-lint`, delete `scripts/slice-overlap` (319) |
| 6 | `flow lint` v3: `[x]`→sha→`files:` join + ID-vanish diff vs `git show HEAD:` | **M** | `scripts/flow-lint` |
| 7 | The router: 14 states, gates-as-data JSON, `.next-call-count`, scan-failed row, completeness report | **L** | `bin/flow` (`computeNext`, `cmdNext`) |
| 8 | Output-table test: every literal `Next:` token resolves to a shipped command | **S** | `tests/` |
| 9 | `commands/flow/{spec,next}.md` + `.claude-plugin/plugin.json` gains `"commands"` | **S** | 3 files |
| 10 | Retarget `spec-gate.sh` / `stop-gate.sh` to `.specs/.current → TASKS.md` | **M** | `hooks/spec-gate.sh:118`, `hooks/stop-gate.sh:179,225,247` |
| 11 | `skills/flow` → the `/flow:next` skill (~200): grammar, execution model, gates | **M** | delete `flow/steps/00-06` (251) |
| 12 | `flow-spec` cuts: template 401→110, question-bank 278→65, doctrine+forces→`design.md` | **L** | `skills/flow-spec/**` |
| 13 | Route gate (`bounded｜oneshot｜dispatch`) + the truthful gate manifest | **M** | `skills/flow-spec/SKILL.md` |
| 14 | `slice-brief` → `task-brief` at task granularity; add the BASE-never-`HEAD~1` rule | **S** | `scripts/task-brief` (from 162) |
| 15 | Matrix rule in `stop-gate.sh`: a covering test that did not run counts as missing | **M** | `hooks/stop-gate.sh` |
| 16 | `PASS-<sha>.md` + `Verified:` split; `verify/` as a tracked predicate; `review/` gitignored | **S** | router + `/flow:next` skill |
| 17 | Delete `feature` (1,227), `flow-to-issues` (242), `flow-handoff` (95), `shared/review.md` (242) | **M** | keep `feature/execution-prompt.md` |
| 18 | `flow publish` as an off-pipeline leaf | **S** | `bin/flow` |
| 19 | `--amend` append-only re-plan with `Approved:` cleared; converge no-op check | **M** | `/flow:spec` skill |
| 20 | `LEDGER.md` + rulings dumped into the PR body on ship | **S** | `/flow:next` skill |

Items 1–2 are the two highest-return single lines in the repo and depend on nothing. Items 3–8 make the
router trustworthy before any skill text moves. Items 9–20 are the surface change, and none of them is
safe to start until 7 is green.
