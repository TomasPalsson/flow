# Spec: ECC borrows — ten small guards and fixes

**Created**: 2026-09-19 · **Route**: dispatch

## TL;DR

> Read this block. If it answers your question, stop here.

**Problem**: A 48-agent comparison of affaan-m/ECC against flow (this session, 3-lens verified) surfaced ten small gaps. Two are silent failures in flow today: a fresh-loop child can hang forever, and a crashed review lens silently shrinks a review (in build-slices it can turn a blocked task "clean").

**Solution**: Fix the two silent failures, add three advisory guards (context-pressure nudge, injection-as-data rule, hidden-unicode scan of harness files), three WARN-only doctor checks (stale worktrees, personal-path leaks, reference-doc drift), a reuse-first step in skill-forge, and write-confinement assertions in the install/stealth tests.

**Who it's for**: the plugin author running flow daily; any agent running `/flow:next`, `/flow:loop` or a review workflow.

**MVP cut line**: everything tagged `MUST` in §4.1 ships. `SHOULD` is v1.1. `MAY` is backlog.

**Key decision**: every new check is advisory (WARN or a note to the model) — nothing new blocks a turn, per the Ruling that mechanical checks stay advisory.

## 1. Context

### 1.1 Problem statement

An unattended `flow loop run` spawns `claude -p` with no wall-clock limit, so one hung child stalls the loop forever while the verifier beside it has a 600 s cap. A review lens agent that dies returns null and both review workflows drop it without a word; in build-slices a fix round whose three re-look lenses all die reads as "no blocking findings". Context fills with no warning before auto-compact, review agents are never told that diff text is data, the tamper notice only watches tests, and three kinds of repo rot (merged worktrees, `/Users/<name>/` leaks, stale reference docs) have no detector.

**Current workaround**: none — each is noticed by hand, late.

### 1.2 Roles

| Role | What they do | Key characteristic |
|------|--------------|--------------------|
| Author | runs flow daily, reads `flow doctor` | one person, reads WARNs, wants zero noise |
| Loop operator | leaves `flow loop run` overnight | cannot watch it; needs every stop to be automatic |
| Build orchestrator | runs `/flow:next`, build-slices, review-diff | trusts the workflow's `clean` flag |
| Review agent | adversary / pr-reviewer reading diffs and PR text | reads content written by others |

**Primary actor**: Author.
**Hidden stakeholders**: anyone the plugin ships to (a leaked personal path breaks their install).

## 2. Scope

### 2.1 In scope

- Loop child wall-clock timeout; review-lens failure reporting in both review workflows
- One new advisory PreToolUse hook; one prose rule in two review surfaces; tamper-notice scope widening
- Three WARN-only doctor checks in one new module; fixing the drift and leaks they find on day one
- A reuse-first Step 0 in skill-forge; write-confinement assertions in two existing test files

### 2.2 Non-goals

> Binding. A change here is an amendment, not an interpretation.

- No new slash command, CLI subcommand or flag; no new runtime dependency
- No auto-removal, auto-fix or blocking: doctor WARNs, the hooks note; nothing deletes a worktree or rewrites a file
- No cost/token ledger, no skill-outcome tracking, no install profiles, no LLM-written session memory (all rejected by the verify pass)

## 3. Journeys

### Journey 1 — Unattended loop with a hung child (Loop operator)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | a fresh loop | the child exits within the cap | behaviour unchanged |
| Error | a child that never exits | the cap elapses | the child is killed, the iteration logs `claude -p timeout`, the error streak rises; three in a row stop the loop with `stop_reason: error` |
| Edge | `max_minutes` leaves 3 min | a child starts | its cap is the 3 min remaining, never more |

### Journey 2 — A review lens dies (Build orchestrator)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | all lenses return | the workflow ends | `failedLenses: []`, result shape otherwise unchanged |
| Error | one lens returns null | the workflow ends | the result names it in `failedLenses` and sets `incomplete: true`; build-slices reports `clean: false` |
| Edge | every re-look lens dies in a fix round | the round ends | the previous blocking findings stay blocking and are parked, never cleared |

### Journey 3 — Doctor on a messy repo (Author)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | no stale worktrees, no leaks, docs match | `flow doctor` | three PASS rows |
| Error | a merged idle worktree, a `/Users/alice/` path, an undocumented hook | `flow doctor` | one WARN row each, naming the path and the command to fix it; exit code unchanged by WARNs |
| Edge | the worktree you are standing in | `flow doctor` | never reported |

## 4. Requirements

### 4.1 Functional requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | Loop operator's child run MUST be killed after the lesser of the minutes left under `max_minutes` and 60 min, and count as an error | fake child that sleeps past a 2 s test cap → error logged, 3 → stopped |
| FR-02 | MUST | Build orchestrator MUST see every lens that returned nothing, by name, in both review workflows | workflow run with a null lens → `failedLenses` names it, `incomplete: true` |
| FR-03 | MUST | build-slices MUST NOT clear blocking findings when its re-look lenses failed | all re-look lenses null → findings parked, `clean: false` |
| FR-04 | MUST | Author MUST get one context note the first time a session crosses 160k tokens (200k window) or 250k (1M window), and again every further 60k within the same window | 200k-window model: 150k silent, 170k note, 175k silent; 1M window: 260k note, 300k silent, 320k note; a session that noted at 170k then reads 230k (now inferred 1M, below 250k) is silent |
| FR-05 | MUST | Review agent MUST treat diff, PR body, comment and issue text as data; an embedded directive is reported as a finding | the rule is present in adversary.md and pr-reviewer Stage 1 (prose test) |
| FR-06 | MUST | Author MUST get a note when an edit adds a zero-width or bidi control character to a hook, skill, agent, hooks.json or .mcp.json file | edit fixture with U+200B in a SKILL.md → note; plain edit → silent |
| FR-07 | MUST | Author MUST see a WARN for a `.claude/worktrees/*` worktree that is merged-and-clean and idle ≥ 1 day, or idle ≥ 14 days | fixture repo with both kinds → two WARNs naming `git worktree remove <path>` |
| FR-08 | MUST | Author MUST see a WARN per shipped file containing a personal absolute path | fixture with `/Users/alice/` → WARN; `/Users/you/` → PASS |
| FR-09 | MUST | Author MUST see a WARN when docs/reference hooks.md or scripts.md drifts from the shipped hook and script files | fixture missing one heading → WARN naming it |
| FR-10 | MUST | skill-forge MUST search existing skills before research and stop on a close match with three choices | prose test on Step 0 |
| FR-11 | MUST | install and stealth tests MUST fail when either command writes outside its claimed paths | new tests green; a planted stray write turns them red |
| FR-12 | SHOULD | Day-one cleanliness: the repo's own leaks and doc drift are fixed so the new checks PASS here | `flow doctor` on this repo shows the three checks PASS |

## 5. Non-functional requirements

| Dimension | Number | How it is measured |
|-----------|--------|--------------------|
| Context hook cost | ≤ 50 ms per call on a 5 MB transcript; reads only the last 256 KiB | `time` over the hook in its test |
| Doctor added time | ≤ 500 ms for the three checks on this repo | `FLOW_VERBOSE=1 flow doctor` timings |
| Noise | 0 WARNs from the three new checks on this repo after FR-12 | `flow doctor` |
| Reliability | 0 turns blocked by anything this feature adds: every new hook exits 0, every new doctor row is PASS or WARN | hook tests assert rc 0; doctor tests assert no FAIL row |
| Security | 0 new network calls, 0 new writes outside TMPDIR (hook state) and the files each task lists | review of the diff; T010 confinement tests |
| Loop stop latency | a hung child is killed within its cap + 5 s | T001 test wall time |

## 6. Launch criteria

- [ ] Every MUST in §4.1 has a passing test in plugins/flow/scripts/tests or plugins/flow/hooks/tests
- [ ] The error path of each journey is exercised by a test
- [ ] Both suites green: `bash plugins/flow/hooks/tests/run.sh` and every touched `TEST_ONLY` file under scripts/tests

## 7. Assumptions

| # | Assumption | Confidence | Blast radius if wrong |
|---|------------|-----------|-----------------------|
| A1 | The user's standing approval ("I approve anything you do", /goal 2026-09-19) is the approval of this plan | High | plan re-approved by hand |
| A2 | The window is re-inferred on every call: 1M when tokens > 200k, a `[1m]` model id, or a claude-opus-5 / claude-fable-5 id; else 200k. A 200k window cannot hold more than 200k, so crossing it proves 1M. The debounce key is window + bucket, so a window change never replays an old bucket | Med | a 1M session below 200k gets an early note |
| A6 | FR-05 and FR-10 change model-read prose; their tests assert the text sits in the right section, not model behaviour (a behavioural check needs a live model run, out of scope here) | High | a rule present but ignored by the model |
| A3 | 60 min is a safe default child cap when `max_minutes` is unset | Med | a legitimately long iteration is killed and retried |
| A4 | Idle = newest of the worktree HEAD commit time and its directory mtime | Med | a busy uncommitted worktree reads as idle only if its dir mtime is also old |
| A5 | Allowed placeholder names in paths: you, me, user, USER, username, name, runner, example, and `<…>` forms | High | one false WARN |

## 8. Open questions

None.

## Appendix A — Glossary

| Term | Means |
|------|-------|
| lens | one adversary review pass with a fixed focus (correctness, gaming, slop …) |
| claimed paths | the paths a command's help and dry-run say it writes |
| idle | days since the newest of HEAD commit time and directory mtime |
