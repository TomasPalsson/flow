# Beads vs. the harness — fit analysis and recommendation

Sources: `research4/beads-source.md` (repo clone at `c0d8da4`, 2026-09-02; 6/6
load-bearing claims re-verified) and `research4/beads-field.md` (author posts,
issue-tracker evidence, HN; 5/6 verified, one header stat corrected).
Harness contracts: `ultracode/harness/SPEC.md` §C7, C8, C11, C13, C14.
Flow v2: `claude/.claude/skills/flow/{SKILL.md,planning.md,steps/03-plan.md,steps/04-build.md}`.

---

## 1. What Beads is

Beads (`bd`) is a single-binary CLI issue tracker built for coding agents rather
than humans: issues ("beads") carry hash-based IDs (`bd-a1b2`) so concurrent
agents on different branches never collide, a **typed dependency graph** (4
blocking types — `blocks`, `parent-child`, `conditional-blocks`, `waits-for` —
plus 6 annotation types including `discovered-from`, `caused-by`, `supersedes`),
a deterministic **`bd ready` queue** that computes unblocked claimable work by
transitive closure, atomic claim (`bd update <id> --claim`), and **semantic
decay** (`bd admin compact` summarises issues closed >30 days ago at ~70%
reduction, with the summary text written by the calling agent and applied
transactionally by `bd`). Storage is **Dolt** — a version-controlled SQL database,
embedded by default since v1.0.0 (2026-04-03) — not the SQLite+JSONL+daemon
architecture nearly every blog post still describes; `.beads/issues.jsonl` is now
an opt-in export/interchange format, not the source of truth, and cross-machine
sync is `bd dolt push` / `bd dolt pull` over `refs/dolt/data`. Claude Code
integration is a first-class plugin wiring `SessionStart` and `PreCompact` hooks
to `bd prime`, which injects ready work plus persistent memories into context —
aimed squarely at surviving `/clear` and auto-compaction.
[beads-source.md §"What it is", §"Data model", §"Storage moved onto Dolt",
§"Claude Code integration surface"]

**Confidence: high on what it is and how it works** — the source research cloned
the repo, quoted the architecture docs verbatim, and re-verified six load-bearing
claims at the same commit. **Confidence: medium-high on its stability** — the
project is ~11 months old, went through a storage-engine rewrite mid-flight, and
the field report documents recurring data-loss and silent-write-loss bugs through
at least mid-2026, most now closed but concentrated in exactly the paths this
harness would depend on. **Confidence: low on the specific numbers that would
apply to a solo two-machine setup** — the most-cited context-cost figure (2.79 MB
per `bd prime`) was measured on a 50-clone shared store and was filed by an agent
dogfooding the project's own infrastructure, not by an independent solo user
[beads-field.md §"Source check" item 3].

---

## 2. What it would replace or duplicate in this harness

| Harness piece | What it does today | Beads equivalent | Verdict |
|---|---|---|---|
| **Plan file** `.claude/feature-plan.local.md` (C7) | Behavior Inventory table, `## Slice N — title` sections carrying `Files`, `Depends-on`, RED/GREEN/REFACTOR sub-headings, per-slice `#### Automated verification` with literal commands, Gate Phases block. It is a **build input**, not a status record: `slice-brief` extracts a section verbatim and hands the prose to an implementer agent. | `bd create` per slice, prose in the description/notes fields | **Poor replacement.** A bd issue has no place for RED/GREEN/REFACTOR structure or per-slice verification commands except as an opaque description blob — and `bd show --json` omits comment bodies entirely, so a machine consumer reading a slice back can silently miss content [beads-field.md §5, #5078]. Keeping both stores means the plan file stays the real source and bd is a shadow copy. |
| **`- **Depends-on**: Slice M`** (C7) | One line per slice, authored by the orchestrator in the same turn as the plan, parsed by `plan-lint` and by `build-slices` stage 0 | `bd dep add A B --type blocks`, 10 typed relations, transitive closure | **Genuine superset**, unused. Flow's graph is small (3–12 slices), acyclic, flat by rule, authored in one turn. `conditional-blocks`/`waits-for` have no consumer. The only type with a real gap behind it is `discovered-from` (see §3B). |
| **`slice-overlap`** (C8) | Fails a plan when two slices list the same file — the thing that actually prevents parallel agents colliding | **Nothing.** Beads models dependencies, never file ownership. | **No overlap at all.** `slice-overlap` survives every option. This alone means `bd ready` cannot be dropped in as the wave scheduler. |
| **Waves** (C13, `build-slices.js`) | `ready = pending.filter(s => deps satisfied && no file overlap with running)`, `parallel(...)`, `log()` each wave | `bd ready [--claim] [--json]` | **Half a replacement.** `bd ready` covers the deps half and adds atomic claim; it does not know about files, so the overlap filter stays. The wave loop is ~10 lines of JS over data the plan already carries. Swapping it for a subprocess adds a store without removing the code. |
| **`PROGRESS.md`** (C9 template, ≤60 lines, Now/Next/Done/Rulings/Blocked) | The cross-session ledger the SessionStart hook prints and CLAUDE.md says to read first | `bd prime` + `bd remember` + `bd list` — beads' README explicitly says *"do not create MEMORY.md files"* [beads-source.md §CLI surface] | **Direct competition, and the most honest overlap.** This is beads' actual niche (`adamgordonbell`: beads "doesn't compete with gh issues as much as it competes with markdown specs"). Trade: a 60-line human-readable digest under git, versus a queryable graph injected automatically at SessionStart and PreCompact. |
| **`/wrap`** (C14 W2) | Rewrites PROGRESS.md from `git status` + `git log`, prints the resume command | `bd sync` / `bd dolt push` + `bd close --reason` | **Different jobs wearing the same name.** `/wrap` *summarises*; `bd sync` *persists*. `/wrap` would still need to exist to write the digest a human reads. |
| **Auto-memory** (`~/.claude/projects/*/memory/MEMORY.md`, `/memory-audit`, explorer agent's write-back per C15 W5) | Durable cross-session hints, explicitly treated as HINTS re-verified each run | `bd remember` + `bd prime` injection | **Direct competition.** Beads' version is better plumbed (injected at PreCompact too) and worse audited (no `/memory-audit` equivalent; the explorer's "never write anything one Grep answers cheaply" discipline has no counterpart). |
| **TaskCreate / TodoWrite lists** | In-session checklist | Beads' own skill ships the rule: *"Will I need this context in 2 weeks? YES = bd, NO = TodoWrite"* | **No conflict** — beads concedes this layer. Several practitioners found the built-in task tool sufficient on its own [beads-field.md, `andai`]. |

**The structural finding:** beads overlaps the harness's *memory* layer
(PROGRESS.md, auto-memory) much more than its *build* layer (plan file, waves).
The plan file is not a tracker that happens to be markdown — it is a contract
whose prose is fed verbatim to implementer agents by `slice-brief`. Replacing it
with issue rows means either losing that structure or keeping both stores.

---

## 3. Three integration options

### Option A — Adopt Beads as the work graph

**Shape:** flow writes each slice as a bd issue with `blocks` deps; `build-slices`
asks `bd ready` for each wave; `/wrap` becomes `bd sync` plus a PROGRESS digest.

**Exact changes**

1. Per-project bootstrap: `bd init` in every repo flow runs in (writes/updates
   `AGENTS.md`, installs git hooks and Claude Code hooks unless `--skip-agents`
   / `--stealth`), plus a Dolt remote or pushed `refs/dolt/data` for the second
   machine.
2. New script `claude/.claude/scripts/plan-to-beads <plan-file>` — parses C7,
   emits `bd create` per slice with the section body as description, `bd dep add`
   per `Depends-on`, and stores the slice↔bd-id map (a new file, because the plan
   file has no field for it — so C7 gains a `- **Issue**: bd-xxxx` bullet, and
   `plan-lint` a rule for it).
3. `C11 build-slices.js` stage 0 rewritten: instead of a haiku agent deriving
   `{deps, files}` from the plan, shell out to `bd ready --json` per wave — **but
   still** intersect with `slice-overlap`'s file map, because `bd ready` has no
   file model. Net: one more subprocess, same amount of code.
4. Slice completion becomes `bd close <id> --reason` inside the implementer
   agent, or in the orchestrator after it re-runs `TEST_CMD`.
5. `steps/03-plan.md` gains a "publish the plan to bd" step after `plan-lint`;
   `steps/04-build.md` subagent mode's wave rule changes from "read the plan" to
   "ask `bd ready`"; `/wrap` gains `bd sync`.
6. `harness doctor` gains checks: `bd` on PATH, Dolt version pinned to 2.2.0,
   `.beads/.gitignore` present, no orphaned `dolt sql-server` processes.
7. CLAUDE.md and the C5 settings.json hooks block absorb beads' `SessionStart`
   and `PreCompact` hooks alongside `session-context.sh`, `codebase-map.sh` and
   `pre-compact-backup.sh` — two SessionStart producers writing into every
   session's context.

**Effort:** roughly 2–3 fleet-days of build (one new script + a `build-slices`
rewrite + four skill-file edits + doctor checks + tests for all of it), then a
standing operational tax: per-project `bd init`, Dolt remote setup, and version
pinning across two machines.

**Downside register**
- *Second state store.* The plan file cannot go away (`slice-brief` needs the
  prose; `slice-overlap` needs `Files`), so bd is additive. Every plan edit must
  now be mirrored, and drift between the two is undetectable by `plan-lint`.
- *Merge on two machines.* Better than the task brief assumed — conflicts are
  Dolt's cell-level merge, not JSONL line-merge — but the documented recovery for
  a failed `bd dolt pull` is `cp -r .beads .beads.backup` → `bd doctor` →
  `bd doctor --fix` [beads-source.md §"Git integration"], and cross-clone data
  loss via committed `metadata.json` has its own closed issue (#2251). The
  harness's current two-machine story is `git pull` on a tracked PROGRESS.md.
- *Daemon.* The docs say embedded mode needs "no server, no ports, no PID files";
  the field report has #4282 — seven orphaned embedded Dolt servers, several at
  ~38% CPU / ~2 GB RSS, ~67 W battery drain — and #3415, `bd list --watch`
  holding the embedded lock against every other `bd` command. Treat "no daemon"
  as the doc's claim, not the observed behavior.
- *Context cost.* `bd prime` at SessionStart and PreCompact adds a payload the
  harness currently spends on a ≤20-line `session-context.sh` plus ≤20 lines of
  PROGRESS.md. The 2.79 MB figure is a shared-fleet worst case and would not
  apply here, but the direction is wrong for a harness whose C9 doctor already
  WARNs above a 10,000-token skill index.
- *Agent closing issues early / wrongly.* This is the sharpest risk given C13.
  `build-slices` runs slices **in parallel waves**, and the field report has
  `bd close` returning "✓ Closed" (exit 0) while the status silently reverts when
  closes are chained in one shell invocation (#4135), fails to persist under
  concurrent agentic load (#4767), and falsely reports success on an
  already-closed issue while dropping `--reason` (#4816). The harness's whole
  design premise — SPEC.md C12, `04-build.md` line 11 — is that an agent's report
  is a claim and the orchestrator re-runs `TEST_CMD`. Adopting bd would import a
  status store whose writes can silently fail, into the exact concurrent shape
  that triggers it.
- *Lock-in.* `bd init` on a fork-less clone silently adopts the git origin's
  entire Dolt history with no row count and no consent prompt — one reporter got
  4,559 upstream issues (#6099). `bd init` also writes `AGENTS.md` and installs
  hooks by default. Getting back out means the plan file is still there, but a
  week of rulings and discovered work lives in Dolt.

### Option B — Borrow the ideas, keep the files

**Shape:** take the four ideas that pay (hash ids, `discovered-from`,
ready-queue framing, decay) into the existing grammar and scripts. No new binary,
no new store.

**Exact changes**

1. **Discovered-from** — the real gap. `flow/SKILL.md` says *"NEVER add scope
   beyond the approved plan … log additions as follow-ups instead"* but names no
   destination. Add a `## Discovered` section to the C7 plan grammar
   (`- <what> — discovered in Slice <N> — <defer|fold into Slice M>`), have
   `plan-lint` accept it, and have `/wrap` drain it into PROGRESS.md's `## Next`.
   Cost: ~20 lines across three files.
2. **Ready-queue as an explicit artifact** — `build-slices` already computes
   waves and `log()`s them; make the same computation available to subagent mode
   as `slice-overlap --waves` (or a `plan-waves` mode), so `steps/04-build.md`'s
   wave rule stops being a prose instruction the model re-derives by hand every
   run. Cost: ~30 lines in one script + tests.
3. **Decay** — PROGRESS.md's ≤60-line cap *is* a decay policy, currently enforced
   only by prose in `/wrap`. Make it measurable: `harness doctor` WARNs when
   PROGRESS.md exceeds 60 lines or its `## Done` section has entries older than
   30 days, and `/wrap` gains a summarise-and-drop rule for `## Done` (beads' Tier
   1 semantics, applied to a file). Cost: ~15 lines.
4. **Hash ids** — **skip.** They solve concurrent creation across branches; flow
   numbers slices 1..N in one file authored by one orchestrator in one turn.
   Adopting them would make `## Slice 3 — title` unreadable for zero collision
   benefit.

**Effort:** roughly half a fleet-day. Three small script edits, one grammar
addition, one command edit, tests in the existing harnesses.

**Downside register**
- No cross-project view: work discovered in repo A is invisible from repo B.
  (Beads has no cross-project view either without federation setup.)
- Discovered items live in a `.local.md` plan file that is untracked and dies with
  the feature — mitigated only by `/wrap` draining them into the tracked
  PROGRESS.md, which becomes a load-bearing manual step.
- No automatic context injection at PreCompact beyond what
  `postcompact-context.sh` already prints.
- Zero of beads' typed-graph power: no `waits-for` fan-in, no transitive query.
  Correct for a 3–12 node acyclic graph; wrong the day the harness manages work
  across repos.

### Option C — Skip

**Exact changes:** none. Record the decision and a re-evaluation trigger.

**Effort:** zero.

**Downside register**
- The genuine gap in §3B item 1 (discovered work has no home) stays open, and it
  is the one thing the harness actually lacks.
- If the harness later grows to many concurrent agents across several repos with
  work outliving a feature branch, this analysis has to be redone — and by then
  beads will have moved again (releases every 1–3 weeks; the public mental model
  already lags the code by 6–9 months).

---

## 4. Recommendation

**Option B, and specifically only items 1–3 of it.**

The reasoning is not "beads is bad" — it is unusually well-engineered for eleven
months old (2,840 Go source files, 1,597 test files, a 514 KB maintained
changelog, measured dependency-version pinning) [beads-source.md §"Verdict on
maturity"]. It is that **the overlap is in the wrong place.** Beads' strength is a
typed dependency graph over work that outlives a session; this harness's
dependency graph is 3–12 nodes, acyclic by rule, authored in one turn, and
already parsed by two scripts — while its actual coordination constraint,
**file ownership**, is something beads does not model at all, so `slice-overlap`
survives every option and `bd ready` can never be the whole scheduler. Adopting
it therefore adds a store without removing a script.

Two harness-specific risks make A worse than a general "second store" objection.
First, C13 mandates parallel waves, and beads' documented silent-write-loss bugs
cluster on exactly concurrent and chained `bd close` (#4135, #4767, #4816) — a
tracker whose writes can succeed-but-not-persist is the opposite of the harness's
founding premise that an agent's report is a claim and the orchestrator re-runs
the gate. Second, the harness's whole value is *determinism the developer can
read*: hooks that fail loudly, scripts with fixed exit codes, a 60-line file under
git. Dolt is a version-controlled SQL database whose recovery runbook is
`bd doctor --fix`.

The one real gap beads exposes — discovered work with nowhere to go — is fixed by
twenty lines of grammar, not a database.

**The measurement that decides it after one week.** Run B items 1–3 (or just start
counting, if even that is too much to commit to). Over one week of normal use,
count:

| Metric | How to count | Threshold that flips the decision to A |
|---|---|---|
| **Dropped discovered work** | Items appearing in `## Discovered` (or, without B, in a build turn's output) that are absent from PROGRESS.md `## Next` at the next `/wrap` | ≥3 in the week |
| **Cross-session re-derivation** | Sessions where the first 10 minutes are spent reconstructing state PROGRESS.md should have carried — count them at each SessionStart | ≥2 in the week |
| **Cross-machine staleness** | Times PROGRESS.md on machine B was behind machine A's actual state by more than one commit | ≥2 in the week |
| **Wrong waves** | `build-slices` wave logs where a slice ran in the wrong wave, or two slices collided on a file | ≥1 (this is a `slice-overlap`/C7 bug, not a beads argument — it flips the decision toward fixing the script) |
| **Work outliving its branch** | Distinct items still open after the feature branch merged | ≥5 — this is the only metric that genuinely argues for a graph store |

If the last row stays under 5 and the first three stay under threshold, the plan
file plus PROGRESS.md is doing the job and Option A is buying a Dolt dependency
for nothing. If "work outliving its branch" runs high **and** the first row is
also high, re-open Option A — but scope it to replacing **PROGRESS.md and
auto-memory only**, never the plan file, because the plan file's prose is a build
input `slice-brief` feeds to agents verbatim and no issue row reproduces that.

---

## 5. Spec deltas for Option B (numbered edits)

**C7 — Plan file grammar**

1. After the sentence listing required top-level headings, add: an **optional**
   `## Discovered` section, permitted only after the last `## Slice <N>` section
   and before `## Gate Phases`. Its body is zero or more bullets of the form
   `- <what> — discovered in Slice <N> — <defer|fold into Slice M>`. Fence-aware
   like every other heading in this grammar.
2. Add to the slice-section list: the `## Discovered` heading terminates the
   preceding slice's section exactly as a `## Slice` heading does — so
   `slice-brief` must not leak Discovered bullets into the last slice's brief.
   U3's fence test gains a case asserting this.

**C8 — Script CLIs**

3. `plan-lint` gains two checks: (a) if a `## Discovered` section exists it is
   positioned per C7 delta 1, and every bullet matches the shape above with an
   `<N>` that names an existing slice; (b) `## Discovered` is never required —
   its absence is not a `MISSING`. New failure lines: `INVALID: Discovered bullet
   <n> does not name an existing slice` and `INVALID: Discovered section is
   misplaced`.
4. `slice-overlap` gains `--waves` (mutually exclusive with `--json`): parse each
   slice's `Files` and `Depends-on`, compute waves with the C13 rule (a slice is
   ready when every `Depends-on` slice is in an earlier wave and its files
   overlap no slice in the same wave), print one line per wave as
   `wave <k>: Slice A, Slice B`; exit 1 on a file overlap (unchanged) or a
   dependency cycle (new: `INVALID: dependency cycle among Slice A, Slice B`).
   `--json` output shape unchanged; `--waves --json` prints
   `{"waves":[[1],[2,3]]}`.
5. U3's `scripts/tests/test_flow.sh` gains: a three-slice fixture where slices 2
   and 3 both depend on 1 and share no files → two waves; the same fixture with
   slices 2 and 3 sharing a file → exit 1; a cyclic fixture → exit 1 with the
   cycle line. U4's `test_lint.sh` gains a good and a bad `## Discovered` fixture.

**C11 — Saved workflows**

6. `build-slices.js` stage 0's fallback agent schema becomes
   `{ deps, files, discovered? }` — unchanged in behavior, but the workflow's
   return value gains `discovered: []`, populated from any slice result whose
   `notes` field flags out-of-plan work the implementer hit. `04-build.md` already
   says to record `parked` rulings; this gives discovered scope the same
   treatment. No change to the phase list or to `workflow-lint`.
7. `workflow-lint` rule (9) is unchanged; no new rule needed.

**C13 — Parallelism**

8. The `04-build.md` binding wording changes from "run `slice-overlap` first" to
   "run `~/.claude/scripts/slice-overlap --waves` first and launch the waves it
   prints" — the wave computation stops being something the model re-derives from
   prose each run, and subagent mode and `build-slices` now compute waves from
   one implementation instead of two. `build-slices.js`'s internal wave loop is
   unchanged (it cannot shell out to a script; it receives `deps`/`files`), but
   its `log()` line format is fixed to match `slice-overlap --waves` output so the
   two are comparable in a transcript.

**C14 — Commands**

9. `/wrap` step 3 gains, between `## Next` and `## Done`: read
   `.claude/feature-plan.local.md`'s `## Discovered` section if the file exists,
   fold every `defer` bullet into `## Next` (deduplicated against what is already
   there), and drop the section from the plan file so an item is drained exactly
   once. Body cap rises from ≤30 to ≤35 lines.
10. `/wrap` step 3 gains a decay rule on `## Done`: entries older than 30 days
    are collapsed into a single dated summary bullet rather than deleted — beads'
    Tier 1 semantics (`bd admin compact --apply`), applied to a markdown file by
    the same agent that would have written the summary for `bd`.
11. `harness doctor` (C9) gains one check: PROGRESS.md exists (WARN if absent in a
    git repo), is ≤60 lines (WARN above), and its `## Done` section has no bullet
    dated more than 30 days back (WARN, naming the oldest) — making the decay
    policy enforced rather than exhorted.

**Not changed:** C5 (no new hooks — beads' `SessionStart`/`PreCompact` injection
is not adopted), C9's tool list (no `bd`), C12 (flow's step files change only via
delta 8's one sentence and delta 9's `/wrap` behavior), C15.

### Spec deltas for Option A, if the week-one measurement flips the decision

A1. **C7** — every `## Slice <N>` section gains a required `- **Issue**: bd-xxxx`
bullet once the plan is published; `plan-lint` accepts it as optional on first
write and required after publication (a `--published` flag, since the bullet
cannot exist before `bd create` runs).
A2. **C8** — new script `plan-to-beads <plan-file> [--dry-run]`: creates one bd
issue per slice, adds `blocks` deps from `Depends-on`, writes the ids back into
the plan, prints the map; idempotent (re-running updates rather than duplicates).
Plus `slice-overlap` unchanged and still mandatory — beads models no file
ownership.
A3. **C11** — `build-slices.js` stage 0 gains an alternate path: when args carry
`beads: true`, each wave is `bd ready --json` intersected with the file-overlap
filter; slice completion calls `bd close <id> --reason`, **one close per shell
invocation with a `bd show` verification between each** (#4135's documented
workaround), and the orchestrator's own `TEST_CMD` re-run remains the gate.
A4. **C13** — the wave rule is restated as "`bd ready` gives dependency
readiness; `slice-overlap` gives file readiness; a slice runs only when both
agree" so no future reader assumes `bd ready` alone is sufficient.
A5. **C14** — `/wrap` gains `bd sync` before writing PROGRESS.md, and PROGRESS.md
becomes a rendering of `bd list` rather than a hand-written digest; `harness
doctor` gains the beads probes listed in Option A change 6.
