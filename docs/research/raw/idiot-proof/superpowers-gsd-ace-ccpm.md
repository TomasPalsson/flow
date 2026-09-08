# Idiot-proofing the workflow frameworks, read at source — 2026-09-07

Delta pass. Everything below was fetched from the vendor/author repo on **2026-09-07** and read as
code/prose, not as a README claim. Existing flow research (`01`, `02`, `07`, `08`, `09`) is not
repeated.

## 0. Provenance

| Source | What I read | Commit / version | Source date | Class |
|---|---|---|---|---|
| `obra/superpowers` | 14 `skills/*/SKILL.md`, `hooks/hooks.json`, `hooks/session-start`, SDD's 3 scripts, `CLAUDE.md` | `b36e082`, v6.3.0 | 2026-08-12 | PRIMARY |
| `open-gsd/gsd-core` | `hooks/hooks.json`, 6 guards, `hooks/lib/hook-exit.js`, `workflows/{extract-learnings,graduation}.md`, `docs/features/community-hooks-opt-in.md`, `.out-of-scope/` | `6ebe637`, v1.13.0 | 2026-09-07 | PRIMARY |
| `gsd-build/get-shit-done` | tree only | `bdcaab2` | 2026-05-31 | PRIMARY (superseded lineage) |
| `automazeio/ccpm` | `skill/ccpm/SKILL.md`, `references/{conventions,execute}.md`, `scripts/{validate,next}.sh` | `7d7e462` | 2026-03-18 | PRIMARY |
| `buildermethods/agent-os` | full tree (24 files), `shape-spec.md`, `CHANGELOG.md` | `475b0ca`, v3.0 | 2026-08-29 (v3: 2026-01-20) | PRIMARY |
| `humanlayer/humanlayer` | `.claude/` — 27 commands, 6 agents, `settings.json` | `99abe67` | 2026-06-18 | PRIMARY |
| `humanlayer/advanced-context-engineering-for-coding-agents` | `ace-fca.md` (408 lines), 2607★ | main | 2026-08-04 | PRIMARY (Dex Horthy) |
| `anthropics/claude-plugins-official` | `plugins/ralph-loop/*` (all 9 files), `plugins/hookify/*` | `85cce03` | 2026-09-04 | PRIMARY (vendor) |

---

## 1. BLUF

1. The 2026 delta is **enforcement leaving prose for code**: gsd-core ships 19 enforcement hooks whose stated justification is "a prose backstop cannot fix a prose defect."
2. gsd's `hooks/lib/hook-exit.js` makes **fail-open vs fail-closed a required argument with no default** — "I forgot to decide" becomes a call-time crash. Single most adoptable idea in the sweep.
3. Every hard block in gsd **names its escape hatch inside the block message**, because "a guard whose bypass is undocumented gets bypassed with the blunt instrument instead" (all guards off).
4. Its best hatch shape: a **path-bound, single-use, 15-minute, self-consuming sentinel file** — not an env var, because a PreToolUse hook inherits the runtime's env and a per-step prefix can never reach it.
5. Superpowers has exactly **one hook** (SessionStart) whose whole job is inlining `using-superpowers/SKILL.md` verbatim inside `<EXTREMELY_IMPORTANT>`. Everything else is skill prose + rationalization tables.
6. Superpowers' SDD replaced "stop and ask" with **"Rulings, not stalls"**: four named stop conditions; everything else is decided, ledgered as `Ruling: <what> — <why> — <cost if wrong>`, and read back to the human at the end.
7. Its **ledger** (`.superpowers/sdd/<plan-slug>/progress.md`, first line = plan path) exists because post-compaction controllers re-dispatched entire completed task sequences.
8. Artifacts move as **files, never pasted text**: `sdd-workspace`, `task-brief`, `review-package` are three small shell scripts whose only job is keeping the orchestrator's context clean.
9. Its fix loop is a **bounded 5-round breaker with model escalation at round 4**; adjudicate only at the cap, and "a silent discard is forbidden."
10. ACE-FCA's target is numeric — **keep context at 40–60%** — and human review goes on research and plans, not diffs: "a bad line of research could land you thousands of bad lines of code."
11. HumanLayer's `create_plan.md` bans **open questions in a finished plan** and splits success criteria into *Automated Verification* (agent-runnable commands) vs *Manual Verification* (human).
12. Anthropic's `ralph-loop` is tiny-surface idiot-proofing done right: session-id isolation, corrupt-state self-delete with remediation text, iteration cap, exact-literal `<promise>` exit, and `hide-from-slash-command-tool` so the model cannot arm it.
13. Anthropic's `hookify` is the vendor's own mistake→rule flow: scan the conversation for corrections, `AskUserQuestion` for warn-vs-block, write `.claude/hookify.<name>.local.md`, active with no restart.
14. gsd's `graduation.md` is the best **anti-nag** design seen: promote a learning to a rule only after it recurs in **≥3 distinct phases**, and record dismissed/deferred cluster ids so a declined suggestion never returns.
15. agent-os v3 **deleted its whole implementation/orchestration layer** (24 files remain) because plan mode, todo lists and frontier models already do it — the clearest value-driven deletion in the set.

---

## 2. obra/superpowers — discipline by prose, one hook

**The one hook.** A single `SessionStart` (`startup|clear|compact`). `hooks/session-start` reads
`using-superpowers/SKILL.md`, JSON-escapes it, emits it inside `<EXTREMELY_IMPORTANT>`, and branches on
`CURSOR_PLUGIN_ROOT`/`CLAUDE_PLUGIN_ROOT`/`COPILOT_CLI` because "Claude Code reads BOTH
`additional_context` and `hookSpecificOutput` without deduplication." Cost: the full skill body every
session — the opposite of flow's 20-line cap.

**Mandatory read.** "If you think there is even a 1% chance a skill might apply … you ABSOLUTELY MUST
invoke the skill … You cannot rationalize your way out of this," then a 12-row **Red Flags table**
("I remember this skill" → "Skills evolve. Read current version."). A `<SUBAGENT-STOP>` block exempts
dispatched subagents so the bootstrap does not recurse into workers.

**Plan-approval gate.** `brainstorming/SKILL.md` opens with a `<HARD-GATE>` forbidding any
implementation action before the human approves intent — on all three paths (spike / bounded /
architectural). The classification is **announced out loud** so the user can override, and "the
ratchet is one-way: hidden complexity … upgrades the path. Nothing downgrades mid-task." An explicit
anti-pattern kills "too simple to need approval": "What scales with simplicity is the artifact, never
the approval."

**Checklists + prerequisite refusal.** "If it has a checklist, create a todo per item."
`writing-plans` enumerates banned placeholders ("TBD", "Add appropriate error handling", "Similar to
Task N") as **plan failures**, then self-reviews for spec coverage, placeholders and cross-task type
consistency. Every plan header must carry `REQUIRED SUB-SKILL: Use
superpowers:subagent-driven-development …` plus a `**Spec:**` path — "the plan argues from the spec, so
the spec travels with it" — and Global Constraints copied **verbatim** from the spec.

**Fresh-context handoff as files** (`skills/subagent-driven-development/scripts/`):
- `sdd-workspace PLAN_FILE` → `<repo>/.superpowers/sdd/<plan-basename>/`, writing `printf '*\n' >
  $base/.gitignore` so the scratch dir self-ignores. "A stale ledger misread as current progress makes
  controllers skip whole task sequences — plan-scoping removes that failure structurally." Not under
  `.git/` because "Claude Code treats .git/ as a protected path and denies agent writes there."
- `task-brief PLAN_FILE N` → fence-aware awk extraction of one task to a file. "Never make a subagent
  read the whole plan file."
- `review-package PLAN_FILE BASE HEAD` → commits + `--stat` + `git diff -U10` to one file. "Never
  dispatch a task reviewer without a diff file," and never `HEAD~1` ("silently drops all but the last
  commit of a multi-commit task").

**Ledger + anti-stall.** Ledger first line is `# SDD ledger — plan: <path>`; one naming another plan
"is another plan's progress: leave it in place and start your own, fresh," and "After compaction,
trust the ledger and `git log` over your own recollection." Only four things stop a run: "an
irreversible or destructive operation; a security-sensitive action; a side effect outside this worktree
that norms say you ask about first (a merge, a push to a shared branch, a publish); and a plan so broken
that every path forward is a guess."

**Bounded loop.** Five fix rounds; 1–3 resume the same implementer, 4–5 dispatch a fresh one on a more
capable model. At the cap: park with a ruling, or rule on load-bearing findings. "Adjudicate only at
the cap. Adjudicating earlier to end a loop is pre-judging with a different name."

**Reviewer hygiene, cost, destruction.** Never pre-judge findings — "If the prompt you are writing
contains 'do not flag,' … 'at most Minor,' or 'the plan chose' — stop." Implementers never spawn
reviewers; the controller never fixes findings itself. "**Always specify the model explicitly when
dispatching a subagent.** An omitted model inherits your session's model — often the most capable and
most expensive — which silently defeats this section." `finishing-a-development-branch` requires the
literal string "Type 'discard' to confirm" before `git branch -D`.

**Mistake → rule.** `writing-skills` (679 lines) is TDD-for-prose: "NO SKILL WITHOUT A FAILING TEST
FIRST … This applies to NEW skills AND EDITS." The 2026 addition is **Match the Form to the Failure**:
prohibitions work only for *discipline* failures; wrong-shaped output needs a positive recipe, omitted
elements a REQUIRED template slot, conditional behaviour an observable predicate — with evidence ("the
prohibition arm produced clearly more of the unwanted content than the recipe arm … and trended worse
than even the no-guidance control") and "**No nuance clauses.** 'Don't X unless it matters' reopens the
negotiation."

**Contributor-side.** `CLAUDE.md`: "This repo has a 94% PR rejection rate," six mandatory pre-PR
checks for agents, and one acceptance test for a new harness integration — send exactly "Let's make a
react todo list"; a working integration auto-triggers `brainstorming`.

---

## 3. gsd-core — enforcement in code, 19 guard hooks

**Registered** (`hooks/hooks.json`): SessionStart ×2; PreToolUse on `Write|Edit`, `Write|Edit|MultiEdit`,
`Write`, `Read|Grep|Bash`, `Agent|Task`; PostToolUse ×2; SubagentStop/Stop/PreCompact; and
**FileChanged on `config.json`** for live config reload — a hook event flow does not use.

**Crash-policy contract** (`hooks/lib/hook-exit.js`), quoted because it *is* the finding:
> "WHY onCrash is a REQUIRED argument, with no default (this is the entire point of this module) … a
> shared helper that silently defaulted to either would let a future hook inherit the wrong policy by
> omission … Requiring the caller to name its policy at every call site — not just once at module load
> — makes 'I forgot to decide' a load-time/call-time crash instead of a silent behavior."

`crash()` is total: an unrecognised policy terminates via `terminateNow('INTERNAL', …)` naming the
offending value, "because throwing would unwind into the CALLER's own outer catch — the exact
fail-open-by-accident hazard this module removes." Each hook declares `const ON_CRASH =
HOOK_ON_CRASH.ALLOW|DENY` once, with a comment justifying the choice.

**Mixed-posture guard.** `gsd-workflow-guard.js` is advisory for edits but has "ONE hard block …
`git add -f` on an agent/worktree-agent branch … that block leg fails CLOSED on internal error …
The advisory legs keep the fail-open posture — a broken advisory must never wedge every tool call."
Default `hooks.workflow_guard: false`.

**Clobber guard** (`gsd-write-guard.js`, 369 lines, one incident). Blocks a whole-file `Write` that
shrinks a curated `.planning/` artifact below **40%** of its on-disk lines (40-line floor). Header:
"instructions to a model … lower the probability of a clobber but cannot prevent one … #973 records an
agent reading the advisory, classifying it as non-binding, and reasoning past it." Deliberately narrow
— not arbitrary markdown, because "a guard that fires on those trains override-fatigue until nobody
reads it" — and it discloses its own bound ("stops accidental and single-shot collapse, not a
determined agent") and two known gaps (stateless per-write, so 292→120→50 erodes invisibly;
case-insensitive matching).

**Hatches named in the deny message.** `GSD_ALLOW_PLANNING_SHRINK=1` for a human at a terminal, and
`.planning/.gsd-allow-shrink` — a **single-use sentinel** — for workflow steps, "because a PreToolUse
hook inherits the RUNTIME's environment, so a per-step env prefix can never reach it." Fresh (15 min),
must name the pending target, **consumed** on use: "Path-bound + single-use + freshness is what keeps
it from becoming a standing unlock left on disk."

**Prerequisite enforcement at the tooling layer.** `gsd-agent-isolation-guard.js` hard-blocks an
`Agent(subagent_type="gsd-executor")` dispatch when the project resolved to `harness-worktree` but the
model did not copy the flag into the call — "nothing verifies the model actually copied it … the
executor runs and commits directly in the user's PRIMARY checkout … with no consent and no warning" —
and fails **closed** on unresolvable config: "a guard that cannot verify must not answer 'safe'."
`gsd-worktree-path-guard.js` blocks absolute Edit/Write paths outside the worktree root: "The prose
guard in `agents/gsd-executor.md` step 0b is never enforced because the model under load skips it."

**Context budget for the agent, not the user.** `gsd-context-monitor.js` reads the statusline's bridge
file and injects `additionalContext` at ≤35% remaining (wrap up) and ≤25% (stop and save state), with a
**5-tool-use debounce** that severity escalation bypasses, a 60s staleness cut-off, and a PreCompact
watermark window during which readings are dropped as untrustworthy.

**Opt-in gates + zero noise.** `hooks.community: true` in `.planning/config.json` gates three hooks
(Conventional-Commits validation, session state, phase boundary); each script **re-checks the flag
itself** and exits 0 silently, so the gate lives in the hook, not only in the installer.
`hooks.commit_types` extends the built-in 10 types and never replaces them, each entry sanitized to
`^[a-z][a-z0-9-]*$` so "a configured value can never alter the compiled pattern's structure."
`gsd-update-banner.js` is registered by the installer **only** when the user declined the statusline —
"The presence of the SessionStart entry IS the opt-in" — and both update hooks degrade to silence when
a build artifact is missing rather than crashing SessionStart.

**Wave scheduling.** `/gsd:execute-phase` groups plans into dependency waves; `--wave N` exists "for
pacing, quota management, or staged rollout," and "If `WAVE_FILTER` is set and there are still
incomplete plans in any lower wave … STOP and tell the user to finish earlier waves first."
`execute-phase/steps/` names 16 discrete gates (codebase-drift, per-plan-worktree, post-merge,
regression, protected-branch, worktree-recovery…); under `TDD_MODE` the normally advisory
`tdd.review-checkpoint` escalates to **blocking** and refuses to mark the phase complete.

**Mistake → rule, two stages.** `extract-learnings.md` mines a finished phase into `LEARNINGS.md`
under decisions/lessons/patterns/surprises, **each with source attribution**, under the rules "Do not
fabricate learnings" and "re-running must overwrite, not append"; it also rebuilds estimate-vs-actual
calibration and refuses to guess ("a fabricated sample would steer every future estimate").
`graduation.md` then clusters recurring items by Jaccard ≥0.25, surfaces a cluster only at **≥3
distinct phases**, and asks Promote / Defer / Dismiss / Defer-all. Promotion appends to the target
rules file, stamps each source item `**Graduated:** {target}:{date}`, and commits atomically;
dismissed/deferred `cluster_id`s (sha256 of title) live in STATE.md's `graduation_backlog` — **the nag
is structurally bounded**. "No item is promoted without explicit developer approval."

**Deletion register.** `.out-of-scope/` holds 16 files, one per rejected proposal, each with
`**Decision:** wontfix — closed on the technical merits`, a date, an issue link, and a "Why GSD does not
own this" argument (#2758: "A theoretical failure surface should not be traded for a real, high-risk
patch-migration surface").

---

## 4. HumanLayer / ACE-FCA — human leverage at the top of the funnel

`ace-fca.md` is PRIMARY for the method, SECONDARY as evidence (single-team anecdote, no controls).
- **Numeric target:** "keeping utilization in the 40%-60% range." **Failure ordering:** "1. Incorrect
  Information 2. Missing Information 3. Too much Noise."
- **Leverage:** "A bad line of code is… a bad line of code. But a bad line of a **plan** could lead to
  hundreds of bad lines of code. And a bad line of **research** … thousands." So humans review research
  and plans, not diffs. "Subagents are not about playing house and anthropomorphizing roles."
- Honesty: "This is not Magic … You have to engage with your task … or it WILL NOT WORK," with a named
  failure (parquet-java, 7 hours, research not deep enough). Only *implement* needs a worktree.

Command-level (`humanlayer/.claude/`):
- `create_plan.md`: "Use the Read tool WITHOUT limit/offset parameters"; "DO NOT spawn sub-tasks before
  reading these files yourself in the main context"; "**NEVER** read files partially." Completeness
  gate: "**No Open Questions in Final Plan** — If you encounter open questions during planning, STOP …
  Every decision must be made before finalizing the plan."
- Success criteria are **structurally split** into `#### Automated Verification:` (commands an execution
  agent can run) and `#### Manual Verification:` (human) — "done" becomes un-fakeable by an agent.
- `implement_plan.md`: a fixed pause template after each phase, and "do not check off items in the
  manual testing steps until confirmed by the user." Mismatch protocol is a 4-field form
  (Expected / Found / Why this matters / How should I proceed?).
- `create_handoff.md`: fixed path `thoughts/shared/handoffs/ENG-XXXX/YYYY-MM-DD_HH-MM-SS_…md`, YAML
  frontmatter (git_commit, branch, repo, researcher), 7 required sections, "prefer
  `/path/to/file.ext:line` references," and a fixed reply template handing the user the exact
  `/resume_handoff` command. `resume_handoff.md` takes a bare ticket id, lists the dir and handles
  zero / one / many deterministically (most recent by filename timestamp); "do NOT use a sub-agent to
  read these critical files."
- `validate_plan.md`: a separate command re-deriving evidence from `git log`/`git diff` +
  `make check test`, checking the plan's checkmarks against reality.
- Ralph as HumanLayer runs it: "if no plan exists, move the ticket back to 'ready for spec' and EXIT
  with an explanation"; "if no SMALL or XS issues exist, EXIT IMMEDIATELY." The loop refuses to run
  without its prerequisite rather than improvising one.
- `settings.json` is 12 lines: three allow-listed Bash calls, `enableAllProjectMcpServers: false`,
  `MAX_THINKING_TOKENS: 32000`. **No hooks at all.**

---

## 5. automazeio/ccpm — files over heads, scripts over reasoning

Now one skill + 6 reference docs + 14 bash scripts (27 files total).
- **Script-First Rule**: "For deterministic operations — anything that reads and reports without needing
  reasoning — always run the bash script directly." 12 mapped commands. `next.sh` walks task frontmatter
  and prints only tasks whose `depends_on` is empty/closed; `validate.sh` prints errors/warnings/invalid
  and ends with a remediation pointer.
- **Preflight refusals worded as remediation**: "❌ No local task for issue #<N>. Run a sync first."; "❌
  No worktree. Sync the epic first."; starting an issue requires an existing `<N>-analysis.md`.
- **Template-repo safety check** before any GitHub write: if `origin` matches `automazeio/ccpm`, refuse
  with the exact `git remote set-url` fix. **"Don't pre-check authentication. Run the `gh` command and
  handle failure"** — no speculative preflight, just a good error.
- **Frontmatter as the state machine**: `status`, `depends_on`, `parallel`, `conflicts_with`; epic
  `progress:` recomputed by a 3-line shell formula on every close. **"Never use `--force` in any git
  operation"** sits in the conventions file every phase must read first.

---

## 6. buildermethods/agent-os v3 — the deletion case study

CHANGELOG v3.0 (2026-01-20): "Spec writing — Now best handled using Plan mode. Task breakdown — Tools
like Claude Code automatically create and track todo lists … **Implementation/orchestration phases
retired**." v2.1.0 had already "Retired the short-lived 'roles' system. Too complex" and "Removed
documentation & verification bloat." What survives: standards discovery/indexing/injection +
`shape-spec`.

Surviving idiot-proofing, all in `shape-spec.md`:
- **A prerequisite it refuses to run without**: "This command **must be run in plan mode** … If NOT in
  plan mode, **stop immediately**", with the exact remediation sentence to print. (Prose-only.)
- **"Always use AskUserQuestion tool when asking the user anything"** — the interaction primitive is
  mandated, not left to model discretion.
- **Task 1 is always "Save spec documentation"** — plan, shaping notes, applied standards, references
  and visuals hit disk *before* implementation, so a run that dies mid-build still leaves the artifact.
- Standards are surfaced from `index.yml` and **confirmed by the user** before injection.

---

## 7. Anthropic ralph-loop + hookify (vendor)

**ralph-loop** (v1.0.0, 9 files, one 191-line `Stop` hook) — every line is a guardrail:
- **Session isolation**: the hook compares `session_id` in `.claude/ralph-loop.local.md` against the
  payload's and exits 0 if they differ — "If another session started the loop, this session must not
  block (or touch the state file)."
- **Corrupt state is fatal-but-friendly**: non-numeric `iteration`/`max_iterations`, missing transcript,
  no assistant messages, jq failure or empty prompt each print a diagnosed multi-line message *and
  delete the state file* — "Run /ralph-loop again to start fresh."
- **Exit contract is an exact literal**: `<promise>TEXT</promise>` compared with `[[ … = … ]]` (not
  `==`, which glob-matches), plus prose closing the loophole: "you may ONLY output it when the statement
  is completely and unequivocally TRUE. Do not output false promises to escape the loop."
- **Bounded** by `--max-iterations` (counter written via temp file + `mv`). **The model cannot arm
  it**: both commands carry `hide-from-slash-command-tool: "true"` and narrow `allowed-tools`. A bad
  `--max-iterations` prints valid examples, invalid examples, and "You provided: …".

**hookify** — the vendor's mistake→rule loop:
- `/hookify` launches a `conversation-analyzer` over the last 20–30 messages looking for "explicit
  requests to avoid something", "corrections or reversions", "frustrated reactions", "repeated issues",
  returning `{category, tool, pattern, context, severity}`.
- Then `AskUserQuestion`: which behaviours (multiSelect, max 4), **warn vs block** per rule, pattern
  refinement. Rules are `.claude/hookify.<name>.local.md` (`name/enabled/event/pattern/action` or a
  `conditions:` list; events `bash|file|stop|prompt|all`), **active with no restart** — dispatchers
  re-read them every event.
- **Fail-open by construction**: every dispatcher wraps everything in try/except, emits
  `{"systemMessage": "Hookify error: …"}` and `sys.exit(0)` in a `finally`. The shipped
  `require-tests-stop` example ships `enabled: false` with a note saying why.

---

## 8. Where flow already wins, and where it doesn't

| Property | flow today | Best-in-set | Gap |
|---|---|---|---|
| Session-start state | `hooks/session-context.sh`, hard 20-line cap, PROGRESS.md head, worktree/branch mismatch note, `flow next` | ccpm `status.sh`/`next.sh`; gsd STATE.md | flow ahead; nobody else caps the budget |
| Mandatory-read bootstrap | none | superpowers inlines a whole SKILL.md each session | deliberate divergence (see `07` on per-turn cost) |
| Plan-approval gate | `/flow` HARD GATE prose + `spec-gate.sh` (PreToolUse deny, `requireSpec: flow-branches`) | superpowers `<HARD-GATE>`; agent-os plan-mode refusal | flow is the only one enforcing it **in code** |
| Fail-open/closed posture | per-hook convention, unenforced | gsd `hook-exit.js` requires a declared policy | **adopt** |
| Escape-hatch discoverability | `flow off`, `CC_NO_*`, config keys | gsd names the hatch in every block message; single-use sentinel | **adopt** |
| Fresh-context handoff | `flow-handoff` (refs not copies, temp path, redaction, "skill to run") | superpowers `task-brief`/`review-package`; HumanLayer `create_handoff`+`resume_handoff` | no `/flow-resume` counterpart; no generator script |
| Ledger surviving compaction | PROGRESS.md (60-line digest) + `postcompact-context.sh` | superpowers plan-scoped ledger with identity first line | **adopt** identity line + per-spec scoping |
| Bounded fix loop | `build-slices` fix ladder | SDD 5 rounds + escalation + breaker | near parity; flow lacks "adjudicate only at the cap" |
| Mistake → rule | `/lesson` (5-rung ladder, red-then-green, adversary bypass, `lesson-record` → PROGRESS.md Rulings) + `lesson-nudge.sh` | hookify (vendor); gsd graduation (recurrence-gated) | flow is most rigorous; missing **recurrence threshold + dismissed backlog** |
| Deletion discipline | none recorded | gsd `.out-of-scope/`; agent-os v3 | **adopt** a wontfix lane in `docs/decisions.md` |
| Context-budget awareness | none | gsd context-monitor (35/25%, debounced); ACE 40–60% | **adopt**, budget-capped |

---

## 9. The 10 most adoptable mechanisms

1. **Required crash policy per hook** (gsd `hooks/lib/hook-exit.js`) → `plugins/flow/hooks/lib/hookout.sh` + a `hooks/tests` assertion → prevents a newly added guard silently inheriting the wrong fail-open/fail-closed behaviour.
2. **Escape hatch named inside the deny message** (gsd `gsd-write-guard.js` block payload) → `plugins/flow/hooks/{git-guard,spec-gate,stop-gate}.sh` → prevents reaching for `flow off` (disabling *all* guards) because the one-shot override is unmemorable.
3. **Single-use, path-bound, time-boxed sentinel override** (`.planning/.gsd-allow-shrink`) → new `.claude/flow-allow-<guard>` consumed by `plugins/flow/hooks/lib/hookout.sh` → prevents a standing `CC_NO_*` unlock left in a shell profile forever.
4. **Ledger with an identity first line, scoped per plan** (superpowers `sdd-workspace`) → `plugins/flow/skills/flow/steps/04-build.md` + `flow-templates/PROGRESS.md` → prevents a post-compaction resume re-running landed slices, or reading another spec's progress as this one's.
5. **Artifact-as-file handoff rules** (`task-brief`, `review-package`) → flow's `scripts/slice-brief` and `scripts/review-package` already exist; add "never dispatch a reviewer without a diff file" and the `HEAD~1` ban → prevents a multi-commit slice being reviewed as only its last commit.
6. **Automated vs Manual verification split in the plan** (HumanLayer `create_plan.md`) → `plugins/flow/skills/flow/planning.md` + `scripts/plan-lint` → prevents an agent calling a UI slice done on unit tests, and makes the user-verification gate mechanically checkable.
7. **"No open questions" + placeholder ban with self-review** (HumanLayer + superpowers `writing-plans`) → `plugins/flow/scripts/plan-lint` as a hard lint → prevents a slice brief whose ambiguity gets resolved by a cheap worker guessing.
8. **Recurrence-gated promotion with a dismissed backlog** (gsd `graduation.md`) → `plugins/flow/skills/lesson/SKILL.md` + `scripts/lesson-record` → prevents `/lesson` nagging on a one-off, and prevents re-offering a lesson the user already declined.
9. **Agent-visible context budget with debounce** (gsd `gsd-context-monitor.js`; ACE's 40–60%) → a PostToolUse hook in `plugins/flow/hooks/` gated by `.claude/flow.config.json` → prevents a run degrading past the smart zone with no handoff written; the debounce keeps per-turn output at zero until it matters.
10. **Loop/state hygiene from ralph-loop** — session-id isolation, corrupt-state self-delete with remediation text, exact-literal exit token, `hide-from-slash-command-tool` → `plugins/flow/skills/flow` `--unattended` and `.claude/flow.json` → prevents a second session clobbering another's flow state, and prevents the model arming an unattended run itself.

Runner-up: **a wontfix register** (gsd `.out-of-scope/`, agent-os v3) → `docs/decisions.md` → prevents
a rejected feature being re-proposed by a future session with no memory of why it was declined.

---

## 10. UNVERIFIED / not established

- **"gsd's 'unclear value' deletions"** — no such phrasing exists in `open-gsd/gsd-core` (CHANGELOG,
  CONTRIBUTING, docs) or `gsd-build/get-shit-done`. The nearest real artifact is `.out-of-scope/`
  (16 dated "wontfix — closed on the technical merits" memos), described in §3. Original
  characterisation: UNVERIFIED.
- **Which GSD is canonical.** `gsd-build/get-shit-done` (64.5k★, last push 2026-05-31),
  `open-gsd/gsd-core` (9.2k★, pushed 2026-09-07, v1.13.0) and `gsd-build/gsd-2` all exist. I read
  `open-gsd/gsd-core` as the engineering source because it is the one still shipping; the relationship
  between the three is UNVERIFIED.
- **gsd hook effectiveness.** All quotes come from source comments citing issues (#973, #2255, #3045,
  #3504, #3911). I did not read the issues — the incident narratives are the authors' self-report.
- **ACE-FCA outcomes** (35k LOC in 7h; intern shipping 10 PRs on day 8; $12k/mo on Opus) are
  uncontrolled single-team anecdotes. SECONDARY as evidence.
- **superpowers eval claims** ("fully separated distributions") point at
  `prime-radiant-inc/superpowers-evals`, not fetched. UNVERIFIED.
- **agent-os v3 outcomes** — the CHANGELOG gives the rationale for the deletions; no in-repo evidence
  they improved results. UNVERIFIED.
- **`hide-from-slash-command-tool`** is PRIMARY-by-usage in shipped Anthropic plugin frontmatter; its
  documented semantics were not confirmed against the hooks/slash-command reference. UNVERIFIED.
- Not read this pass (named for follow-up): gsd `src/` TypeScript (plan-dependency-graph,
  broken-windows, state-transition), superpowers `implementer-prompt.md` / `task-reviewer-prompt.md` /
  `re-review-prompt.md`, ccpm `sync.md`/`track.md`, HumanLayer's 6 subagent definitions.
