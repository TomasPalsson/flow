# OpenSpec / BMAD / superpowers — what happens *after* the spec

Scope: the developer wants `/flow:spec` to stay and everything after it to get simpler, with no GitHub dependency. This file
answers five questions per framework — (a) how post-spec work is broken into units, (b) where state lives, (c) how "what next"
is answered, (d) how done is verified, (e) how a small change avoids ceremony — then names best / clunky / steal.

Prior work, not repeated: `docs/research/02-frameworks-source-review.md` §1 matrix (13-framework shape/determinism table),
§3 steal list S1–S15, §5 flow v2 skeleton; `docs/research/10-idiot-proof-harness-2026.md` §3 (mechanism-by-mechanism
idiot-proofing table); `docs/research/raw/frameworks/{openspec,bmad,superpowers,get-shit-done,spec-kit}.md`.
This pass re-fetched all three repos and quotes source, and it supersedes the raw notes where the layout has moved.

**Provenance — all PRIMARY (shallow clones read on disk, 2026-09-07):**

| Repo | Clone commit / date | Version | `gh api` pushed_at |
|---|---|---|---|
| `Fission-AI/OpenSpec` | `e062b95` — Thu Sep 3 2026 "Version Packages (#1766)" | `package.json` 1.12.0 | 2026-09-07T01:46Z |
| `bmad-code-org/BMAD-METHOD` | `abe4eb1` — Sat Sep 5 2026 | see `skills/*/module-manifest.toml`; root `pyproject.toml` pins `version = "0"` with the note *"The release version lives in skills/\*/module-manifest.toml, not here."* | 2026-09-07T08:21Z |
| `obra/superpowers` | `b36e082` — Wed Aug 12 2026 "Release v6.3.0" | `.claude-plugin/plugin.json` 6.3.0 | 2026-09-04T23:04Z |

**Layout drift since the raw notes (BMAD): `src/bmm-skills/**` is now `skills/**`; new skills the earlier review never saw — `bmad-spec` (memlog-derived spec + `stories.yaml`), `bmad-build-auto` (unattended one-iteration build), `bmad-forge-idea`, `bmad-walkthrough`, `bmad-deep-recon`; `v6-shims/` is gone.** Paths below are current. Star counts from `gh api` looked implausible (superpowers 282k) — UNVERIFIED, unused.

---

## 1. OpenSpec — the unit is a *change folder*; the CLI owns the graph

**(a) Units.** After `openspec new change "<name>"` the work is one directory, `openspec/changes/<name>/`, holding `proposal.md`, `specs/<capability-path>/spec.md` (delta), `design.md` (conditional), `tasks.md`, `.openspec.yaml`. The unit of *execution* inside it is a checkbox line in `tasks.md`; the unit of *durable meaning* is a requirement delta. Both grammars are parsed, not trusted: `schemas/spec-driven/schema.yaml` tells the model **"Scenarios MUST use exactly 4 hashtags (`####`). Using 3 hashtags or bullets will fail silently"** and **"The apply phase parses checkbox format to track progress. Tasks not using `- [ ]` won't be tracked."** Every task carries its own check: *"Each task MUST state how to verify completion (a test, command, observable behavior, or delivered artifact). Put the verification in that task's checkbox description."*

**(b) State = the filesystem, and nothing else.** There is no status field anywhere. `src/core/artifact-graph/state.ts`:

```ts
/** Detects which artifacts are completed by checking file existence in the change directory. */
export function detectCompleted(graph: ArtifactGraph, changeDir: string): CompletedSet {
```

Implementation progress is likewise derived — `src/commands/workflow/instructions.ts:430` counts `parsedTasks.filter(t => t.done)`
off the checkboxes. Archival state is a directory move to `openspec/changes/archive/YYYY-MM-DD-<name>/`, and the durable spec is
whatever `src/core/specs-apply.ts` merged into `openspec/specs/**` (`:386` — `// Apply operations in order: RENAMED → REMOVED →
MODIFIED → ADDED`). Nothing has to be reconciled after a crash because nothing was written twice.

**(c) "What next" is a data structure.** `formatChangeStatus` (`src/core/artifact-graph/instruction-loader.ts:456`) labels each
artifact `done | skipped | ready | blocked` from the graph's `requires` edges, sorts by `graph.getBuildOrder()`, and attaches a
literal command in `nextSteps` (`src/core/change-status-policy.ts:65`):

```ts
if (readyArtifact) {
  steps.push(`Run openspec instructions ${readyArtifact.id} --change "${input.changeName}" --json before writing that artifact.`);
}
```

The `/openspec-continue-change` skill is then five lines of policy over that JSON: *"Pick the FIRST artifact with
`status: "ready"` … **STOP after creating ONE artifact**."* The apply side has its own tiny state machine —
`instructions.ts:436-462` emits `blocked` (missing artifacts / missing or empty tracking file), `ready`, or `all_done`
with the exact remedial sentence attached to each.

**(d) Done.** Three tiers, only the first two mechanical: `openspec validate` (ERROR/WARNING/INFO; `--strict` decides whether warnings fail) parses the delta grammar and cross-checks sections; archive refuses what validate warned about *by calling the same function* (`findArchiveBlockers` → `buildUpdatedSpec(..., {silent:true})`); and `openspec-verify-change/SKILL.md` is an LLM pass over Completeness / Correctness / Coherence that greps the codebase per requirement. Only tiers 1–2 can stop you.

**(e) Small changes.** One real hatch: `skip_specs: true` in `.openspec.yaml`, paired in the prompt with *"Do not invent a requirement just to satisfy validation."* It validates itself — `src/core/validation/constants.ts:38-43` distinguishes `CHANGE_SKIP_SPECS_CONFLICT` (marker set but delta files exist), `CHANGE_SKIP_SPECS_ACCEPTED` (INFO), and `CHANGE_SKIP_SPECS_INVALID_METADATA` ("the marker is not honored. Fix the metadata"). Beyond that ceremony does **not** scale down: `openspec-ff-change` merely *batches* the same four artifacts into one turn. A typo fix still gets a proposal.

---

## 2. BMAD — the unit is a *story spec file*; the file's frontmatter is the state machine

**(a) Units.** Two layers, and the top one is new since the last review. `skills/bmad-spec/` produces a **spec folder** —
`SPEC.md` (a five-field kernel: Why, Capabilities, Constraints, Non-goals, Success signal), optional companions, and optionally
`stories.yaml`: *"a top-level YAML list, one entry per story, in execution order — stories run top to bottom"*
(`assets/stories-schema.md`). Each story then becomes exactly one spec file under `stories/<id>-*.md`, matched by id prefix, and
that file is what `bmad-build` / `bmad-build-auto` implements. A story is sized by the SCOPE STANDARD in
`skills/bmad-build/workflow.md`: *"a **single user-facing goal** within **900–1600 tokens** … Multi-goal means >=2 top-level
independent shippable deliverables — each could be reviewed, tested, and merged as a separate PR without breaking the others.
Never count surface verbs, 'and' conjunctions, or noun phrases."* And: *"Neither limit is a gate. Both are proposals with user
override."*

**(b) State.** Deliberately single-homed. `stories.yaml` validity rule 3 is literally **"No `status` field, ever."** Status lives in the story spec's frontmatter (`skills/bmad-build/spec-template.md`): `status: draft | ready-for-dev | in-progress | in-review | done`, plus `route: oneshot | dispatch`, `review_loop_iteration`, and a `baseline_commit` captured before the first edit (step-03: *"If the frontmatter already contains `baseline_commit` (resumed run), preserve the existing value — never overwrite it."*). Three append-only logs live in the same file: `## Implementation Notes`, `## Spec Change Log`, `## Review Triage Log`. Cross-story rollup is a *separate*, script-owned file, `sprint-status.yaml`, mutated only by `skills/bmad-sprint-planning/scripts/sprint_plan.py` (746 lines + test suite) or the five-line `sync-sprint-status.md` micro-instruction. Upstream, `bmad-spec` keeps `.memlog.md` — *"append-only, chronological … never edited or reordered"* — and **`SPEC.md` is re-derived from it every run**: *"a hand-edit to `SPEC.md` from outside is unsupported and is overwritten on the next derive."*

**(c) "What next"** is a `status` read plus a jump table. `bmad-build-auto/step-01-clarify-and-route.md` routes on the story file's frontmatter alone: `draft → step-02`, `ready-for-dev | in-progress → step-03`, `in-review → step-04`, `blocked → HALT`, `done → reset review_loop_iteration, set followup_pass, → step-04` (a fresh review pass, "not a resumption"). Dispatch is `(spec_folder, story_id)`; the runner reads only that entry's `title`/`description` and is forbidden the orchestration fields: *"never read the checkpoint fields or `invoke_dev_with` … One `stories.yaml` entry per invocation: never read another entry, and never advance to a different story id regardless of outcome."*

**(d) Done.** Judged against a diff the orchestrator produced itself, never the worker's report (`skills/bmad-build/step-03-implement.md`): *"write a unified diff of all changes since `{baseline_commit}` — untracked files included — to a uniquely-named file … **Judge against the diff, not against the implementation subagent's report.**"* Then the Matrix Test Audit: *"A covering test that exists but did not run — unregistered, filtered out, skipped, or disabled — counts as missing. If a test disagrees with the matrix, never edit the expectation to match the code: fix the code."* Then step-04's context-free lenses → triage: *"Disregard any severity a reviewing subagent assigned — they lack the context to grade"*, verdicts `high/medium/low/false/maybe-false`, routes `patch/defer/intent_gap/bad_spec`, and the carried-verdict rule that stops re-litigation across loops (*"write the row again with `carried` in front of the evidence, skip verification"*).

**(e) Small changes — the best ceremony router in the field.** `skills/bmad-build/step-02-plan.md` step 3 makes the model write
down three facts *about the plan it already has*: **intent gaps** ("things the request does not say, the code cannot settle,
and the user would notice in the result"), **irreversibles** ("migrations, data deletion or mutation, external side effects,
deploy or config triggers"), **footprint**. Then:

> If there are no intent gaps, nothing irreversible, and the change is small: … write `{spec_file}` with only the frontmatter,
> `## Intent` (inside its `<frozen-after-approval>` block), and `## Implementation Notes`. Delete every other section; the
> template says you may. Set `route: 'oneshot'` … **EARLY EXIT** → `step-oneshot.md`.

The oneshot path keeps the review classification but drops the checkpoint, the Code Map, the I/O matrix and the task list — and
it is *reversible mid-flight*: *"Stop coding if you learn something step 2 did not account for … set `route: 'dispatch'` and
`status: 'draft'`. Go back to step-02 step 6."* The heavy path's one human gate (CHECKPOINT 1) also re-reads before acting:
*"Before acting on approval, re-read `{spec_file}` from disk. If it is missing, HALT without recreating it."*

---

## 3. superpowers — the unit is a *task in one plan file*; the ledger is the state

**(a) Units.** `skills/writing-plans/SKILL.md` states the size rule directly: *"A task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate … fold setup, configuration, scaffolding, and documentation steps into the task whose deliverable needs them; split only where a reviewer could meaningfully reject one task while approving its neighbor."* Every task carries `**Files:**` (Create/Modify with line ranges/Test) and `**Interfaces:** Consumes / Produces` — *"A task's implementer sees only their own task; this block is how they learn the names and types neighboring tasks use."* Steps are 2–5 minutes and fixed: failing test → verify it fails → minimal impl → verify pass → commit. Placeholders are banned by name ("TBD", "add appropriate error handling", "Similar to Task N" — *"repeat the code — the engineer may be reading tasks out of order"*).

**(b) State = a plan-scoped git-ignored workspace.** `scripts/sdd-workspace PLAN_FILE` prints `<repo-root>/.superpowers/sdd/<plan-basename>/` and drops a self-ignoring `printf '*\n' > "$base/.gitignore"`. Its header states the failure it removes: *"A stale ledger misread as current progress makes controllers skip whole task sequences — plan-scoping removes that failure structurally."* The ledger `progress.md` names its own plan on line 1 (`# SDD ledger — plan: <plan file path>`), and *"A ledger whose first line names a different plan file … is another plan's progress: leave it in place and start your own, fresh."* Line grammar: `Task <N>: complete (commits <a7>..<b7>, review clean)`, `Task <N>: fix round <R>/5 (…)`, `Ruling: <what you decided> — <why> — <what it costs if wrong>`.

**(c) "What next"** is a ledger scan — prose, but precise: *"tasks with a `Task <N>: complete` line are DONE — do not re-dispatch them; resume at the first task without one. A task whose last line is a fix round is mid-loop: resume the loop at the next round."* Plus the rule that makes it load-bearing: *"After compaction, trust the ledger and `git log` over your own recollection."* Context is never inherited: `scripts/task-brief PLAN_FILE N` awk-extracts one `### Task N` section (fence-aware: `/^```/ { infence = !infence }`) to a file — *"Never make a subagent read the whole plan file"* — and *"Everything you paste into a dispatch prompt … stays resident in your context for the rest of the session. Hand artifacts over as files."*

**(d) Done.** `scripts/review-package PLAN_FILE BASE HEAD` writes `log --oneline` + `diff --stat` + `git diff -U10` for the recorded BASE, with the trap in its header: *"Using the recorded per-task BASE (not `HEAD~1`) keeps multi-commit tasks intact."* Then a bounded ladder: rounds 1–3 resume the same implementer, rounds 4–5 *"fresh implementer, more capable model"*, breaker at 5 → adjudicate each open finding, *"Adjudicate only at the cap. Adjudicating earlier to end a loop is pre-judging with a different name … a silent discard is forbidden."* The final whole-branch review gets **one** fix dispatch: *"Per-finding fixers each rebuild context and re-run suites; a real session's final-review fix wave cost more than all its tasks combined."* At the end every `Ruling:` line is collected into the last message — *"A ruling that dies with the workspace was a decision made in secret."*

**(e) Small changes.** `skills/brainstorming/SKILL.md` classifies before the first question into **spike / bounded / architectural** and says the label out loud so the human can override. Bounded = *"a well-scoped change to code that already exists in this repo … Understanding the kind of app is not enough — bounded means the flow you are changing is already here to read"* → questions one at a time, a short design **in chat**, then implement. **No spec file, no plan document.** The ratchet is one-way (*"hidden complexity discovered mid-task upgrades the path … Nothing downgrades mid-task"*) and the approval gate never scales: *"What scales with simplicity is the artifact, never the approval."* A second scale-down sits inside execution: *"Batch small same-shape work … Compose ONE dispatch brief listing every file and its change, send the whole batch to a single subagent."*

---

## 4. Side-by-side

| | OpenSpec 1.12.0 | BMAD (Sep 2026) | superpowers 6.3.0 |
|---|---|---|---|
| Unit after the spec | change folder → `tasks.md` checkbox | `stories.yaml` entry → one `stories/<id>-*.md` spec file | `### Task N` block in one plan file |
| Unit sizing rule | "small enough to complete in one session" + a stated verification | single user-facing goal, 900–1600 tokens, PR-independence test | "worth a fresh reviewer's gate"; split only where a reviewer could reject one and approve its neighbor |
| State lives in | file existence + `- [x]` (zero status fields) | story-file frontmatter `status`/`route`/`baseline_commit`; rollup in script-owned `sprint-status.yaml`; `.memlog.md` upstream | git-ignored `.superpowers/sdd/<plan>/progress.md` ledger + `git log` |
| "What next" | `openspec status --json` graph walk → first `ready` + literal command | frontmatter `status` → step-file jump table | first task with no `complete` line |
| Done verified by | `validate` (parser, ERROR/WARNING/INFO) + archive reusing the same merge fn; LLM verify optional | orchestrator-rebuilt diff from `baseline_commit`, matrix test audit, context-free lenses + triage log | review package diff, 5-round ladder w/ model escalation, breaker + rulings |
| Small-change path | `skip_specs: true` only; artifacts still all required | `route: 'oneshot'` computed from intent gaps × irreversibles × footprint; reversible mid-flight | `spike` / `bounded` paths produce **no files at all** |
| Human gates | none enforced; planning-boundary is prose | CHECKPOINT 1 (+ re-read from disk before acting), `spec_checkpoint`/`done_checkpoint` per story | one HARD-GATE approval before any implementation; then "rulings, not stalls" |
| Cost per unit | ~3.7k words of skill+schema prose for one propose→tasks pass | one step file at a time (26–115 lines) | 568-line SKILL for the controller; workers see one brief |
| GitHub needed | no | no | no |

## 5. Best / clunky, each

- **OpenSpec best:** state that cannot lie (existence + checkbox), a machine-walkable artifact graph that turns "what next" into
  JSON with the command attached, delta grammar merged by code in a fixed order, and a self-validating escape hatch.
  **Clunky:** flat ceremony — four artifacts for a rename; heavy prose (`skills/` totals 2,586 lines, `openspec-onboard`
  alone 560); the planning-boundary and "material ambiguity" gates are prose with nothing behind them; `openspec-archive-change`
  re-does in prompt the merge `specs-apply.ts` already does deterministically; stores/initiatives/worksets are product surface a
  solo dev will never touch.
- **BMAD best:** the route gate (ceremony keyed to intent gaps × irreversibles × footprint, reversible mid-flight), one file =
  one unit = its own state machine with `stories.yaml` forbidden to carry status, judging done from a rebuilt diff, the
  carried-verdict triage log, and `.memlog.md` as append-only truth with the contract re-derived.
  **Clunky:** every mechanism shells out to `uv run … _bmad/scripts/*.py` in the *target* repo; `render_skill.py` snapshotting
  before any run; `bmad-build` vs `bmad-build-auto` are two near-duplicate step trees already diverging (`<frozen-after-approval>`
  vs `<intent-contract>`); `step-oneshot.md` re-states step-04's rubric verbatim; ~29 skills and a customize.toml layer per skill.
- **superpowers best:** the three scripts (`sdd-workspace` / `task-brief` / `review-package`) — ~127 lines of bash that make
  fresh-context-per-task, plan-scoped state and multi-commit-safe review packages *structural*; the ledger identity line; the
  bounded fix ladder with model escalation and mandatory rulings; and spike/bounded/architectural, the only router that lets a
  small task produce **no artifact at all**.
  **Clunky:** the controller carries 568 lines (+250 brainstorming, +320 TDD) of prose; the entire process — resume rules, cap,
  breaker, "no parallel implementers" — is unenforced instruction; `executing-plans` is a stub duplicate of the same loop; and
  plan quality rests on a self-review the same session performs.

## 6. Steal list for flow (calibrated to what flow already has)

flow already ships `scripts/{new-spec,slice-brief,review-package,plan-lint,slice-overlap,skills-lint}`, `hooks/{spec-gate,stop-gate,
git-guard,size-guard,…}` and a `flow next` that reads PROGRESS.md + git. So the gap is not scripts; it is the **unit model** and
the **ceremony router**. In value ÷ effort order:

1. **Kill `/flow-to-issues`; make the unit a directory of slice files.** `.flow/<NNN>-<slug>/{SPEC.md, slices/<id>-<slug>.md}`
   + a `slices.yaml` that is *ordered and status-free* (BMAD's rule 3). Local markdown, no `gh`, no issue numbers. `slices.yaml`
   holds only `id/title/description/checkpoint/notes` — exactly BMAD's `spec_checkpoint`/`done_checkpoint`/`invoke_dev_with`
   split, where checkpoint fields are read by the dispatcher and **never** by the builder.
2. **One status field, in the slice file's frontmatter, and route on it.** `draft | ready | building | review | done | blocked`
   + `baseline_commit` + `review_round`. Resume = read frontmatter, jump. This replaces flow's Phase 0.1 prose resume and gives
   `flow next` a real input: today it infers from PROGRESS.md prose; tomorrow it globs `.flow/*/slices/*.md`, reads frontmatter,
   and prints the first non-`done` slice with a literal command — OpenSpec's `nextSteps` pattern, which flow's `--json` mode
   already has the shape for.
3. **Steal BMAD's route gate verbatim as flow's size classifier.** Replace "Small/Medium/Large" with the three computed facts —
   intent gaps, irreversibles, footprint — and two routes: `oneshot` (spec file = frontmatter + Intent + notes; build, review,
   done) and `dispatch` (full slice set). Make it reversible mid-flight the way step-oneshot is. This is the single change that
   makes a typo fix cost one file instead of a pipeline.
4. **Add superpowers' third route below oneshot: `bounded` produces no file at all.** Short design in chat → approve →
   TDD → commit. The approval gate stays; only the artifact scales. Guard it with the same anti-pattern table ("Reaching for a
   label to skip work IS the doubt — take the heavier path").
5. **Judge done from a diff flow rebuilds itself.** flow has `review-package`; add BMAD's `baseline_commit`-in-frontmatter and
   the rule *"judge against the diff, not the subagent's report"*, plus the matrix audit line ("a covering test that exists but
   did not run counts as missing") — that one is a `stop-gate.sh` check, not prose.
6. **Ledger discipline where flow keeps PROGRESS.md.** Adopt the identity-first-line rule and the `Ruling:` grammar, plus
   the terminal "Rulings I made" dump. flow's `/lesson` + PROGRESS.md already occupy this slot; what is missing is the
   *exhaustive* end-of-run ruling list.
7. **A `flow validate` that parses the slice grammar** (frontmatter keys, required headings, ids prefix-free, every slice has an
   automated check line) with OpenSpec's ERROR/WARNING/INFO tiers and one JSON envelope carrying a `fix` string. flow's
   `plan-lint` is the seed; give it the severity tiers and make `flow next` refuse to advance past an ERROR.
8. **A self-validating skip marker**, OpenSpec-style: `skip_spec: <reason>` in slice frontmatter, with a distinct error when the
   marker is present but malformed, and the prompt line *"Do not invent a requirement just to satisfy validation."*
9. **Don't copy:** OpenSpec's four-artifact floor and its store/initiative layer; BMAD's `uv`+Python-in-target-repo dependency,
   snapshot rendering, and duplicated auto/interactive step trees; superpowers' 568-line controller prose. And do not re-derive
   deterministically-mergeable state in a prompt (OpenSpec's own archive skill is the cautionary example).

## 7. Target shape

`/flow:spec` (unchanged) → writes `.flow/<NNN>-<slug>/SPEC.md` + `slices.yaml` in the same pass → `/flow:build` loops:
`flow next` reads frontmatter → route gate (`bounded` | `oneshot` | `dispatch`) → `slice-brief` → fresh implementer →
`review-package` → bounded ladder → frontmatter `done` + ledger line. Three commands, one directory, no GitHub, and the only
things that block are `flow validate`, the stop-gate, and the one human approval.

---

## BLUF

1. OpenSpec's best idea is that **state is the filesystem** — `done` means the file exists and the checkbox is `[x]`; no status field can drift.
2. Its second-best is **"what next" as data**: `status --json` walks `requires` edges and returns the first `ready` artifact *with the command to run attached*.
3. BMAD's best idea is the **route gate** — intent gaps × irreversibles × footprint decides `oneshot` vs `dispatch`, and the route can be revised mid-build.
4. BMAD's second-best is **one file = one unit = its own state machine**: `stories.yaml` is ordered and forbidden to carry status ("No `status` field, ever").
5. superpowers' best is **~127 lines of bash** (`sdd-workspace`, `task-brief`, `review-package`) that make fresh context, plan-scoped state and multi-commit-safe review structural rather than intended.
6. superpowers' second-best is **spike/bounded/architectural**: the only router in the field where a small task produces no artifact at all, while the approval gate never scales down.
7. Improve in OpenSpec: flat ceremony (four artifacts for a rename), 2.6k lines of skill prose, and a prompt that re-does the deterministic merge the CLI already owns.
8. Improve in BMAD: `uv`+Python required inside every target repo, snapshot rendering before each run, and two diverging copies of the same build step tree.
9. Improve in superpowers: a 568-line controller whose caps, resume rules and no-parallel-implementer rule are all unenforced prose.
10. Steal for flow: delete `/flow-to-issues`; the unit becomes `.flow/<NNN>-<slug>/slices/<id>-*.md` with one frontmatter `status` + `baseline_commit`, and a status-free ordered `slices.yaml`.
11. Steal next: BMAD's route gate as flow's size classifier plus superpowers' `bounded` no-file path; judge done from a diff flow rebuilds from `baseline_commit`, never from the worker's report.
12. Steal last: make `flow next` read slice frontmatter instead of PROGRESS.md prose, and give `plan-lint` ERROR/WARNING/INFO tiers + a self-validating `skip_spec: <reason>` hatch.
