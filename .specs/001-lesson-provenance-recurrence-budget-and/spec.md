# Spec: Lesson provenance, recurrence, budget and deny rung

> **One-sentence summary**: Every `/lesson` guardrail carries its reason inline, the repo can tell whether a lesson held, and the ladder gains a settings-deny rung.

**Status**: Draft
**Size**: Medium
**Author**: Mr Claude (orchestrator), for the harness maintainer
**Created**: 2026-09-05
**Last updated**: 2026-09-05
**Version**: 1.0

---

## TL;DR

**Problem**: A `/lesson` ruling lives only in PROGRESS.md, so the hook, test or CLAUDE.md line it produced becomes undeletable once the ruling scrolls away (instruction files grow 226% over their life; deletion likelihood falls with age, arXiv:2608.11095). Nothing records whether a lesson ever fired again, nothing stops a duplicate CLAUDE.md line, and the ladder has no rung for the "agent routed around the hook" class that a settings-level deny fixes.

**Solution**: (1) a fixed provenance marker written next to every rung; (2) silent per-lesson fire counting inside hooks that already run, read back on demand by `lesson-stats`; (3) a `lesson-claude-md` writer that refuses duplicates and enforces the line budget; (4) a **Deny** rung in the skill and in `lesson-sites`.

**Who it's for**: The harness maintainer running `/lesson`; the model executing the skill; a future reader pruning CLAUDE.md.

**Non-goals (v1)**:
- No new hook output, nudge, gate or question in the normal turn loop. **This feature adds zero lines of hook stdout per turn.**
- No staleness pass (rules revisited when code changes) and no reproducibility gate at capture — follow-up spec.
- No automatic rule writing, promotion or deletion; every write stays behind the user's yes.
- No cross-project or cross-machine sync of rulings.
- No change to the correction phrase list in `lesson-nudge.sh`, and no new git-guard patterns (`git stash` is a separate lesson).

**MVP cut line**: all `MUST` rows in Section 4 ship; `SHOULD` rows are v1.1.

**Key decision**: recurrence is measured by *guardrail fires*, counted silently in `hookout.sh` where every deny/block/feedback already passes, keyed by the same marker text the ruling carries. Tests and settings-deny rules cannot fire through a hook, so they are reported as *unmeasured*, never as zero.

---

## 1. Context

### 1.1 Problem Statement

The maintainer runs `/lesson` after a mistake and gets a hook, a test or a CLAUDE.md line plus a one-line ruling in PROGRESS.md. Six months later the CLAUDE.md line has no visible reason, the hook branch has no comment saying which incident it answers, and nobody knows whether the guardrail ever caught anything again. Keeping everything is the rational choice, so the files only grow.

**Current workaround**: read `git log -S` and PROGRESS.md by hand. Nobody does.

**Business rationale**: The research sweep (docs/research/raw/lesson-guardrails-2026.md §7) ranks these four gaps as the only ones with grade-A evidence; the maintainer chose to build exactly these four.

### 1.2 User Roles

| Role | Description | Volume (approx.) | Key characteristic |
|------|-------------|------------------|--------------------|
| Maintainer | The one developer who owns this harness and runs `/lesson` | 1 | Knows bash; wants to get work done, not be nagged |
| Model | Claude executing `SKILL.md` steps inside a session | every `/lesson` run | Follows the skill literally; needs exact commands |
| Pruner | Whoever trims CLAUDE.md or a hook later (same person, months on) | rare | Has no memory of the incident |

**Primary actor**: Maintainer.
**Hidden stakeholders**: every project that installs the plugin (hooks are shared); the `/wrap` skill (may read stats later).

### 1.3 Prior Art & Alternatives Considered

| Option | Status | Why rejected / why not this |
|--------|--------|-----------------------------|
| Cursor Bugbot learned rules (auto-promote, auto-disable) | Rejected | Automated promotion is the documented anti-pattern (ICLR 2026, ETH: LLM-generated context files add cost, no success gain) |
| Rationale only in PROGRESS.md (today) | Rejected | Rationale must sit next to the rule to keep it deletable (arXiv:2608.11095: 99.3% less excess growth) |
| Separate `lessons.md` ledger | Rejected | Second memory file to grow unbounded; PROGRESS.md already has `## Rulings` |
| Count fires in `$TMPDIR` like gate timing | Rejected | Reboot wipes it; a 30-day window needs project-local state |
| Inline marker + silent counter + on-demand stats | **Selected** | Zero turn-loop noise, one grammar, state the harness already owns (`.claude/`) |

---

## 2. Scope

### 2.1 In Scope

- Marker grammar `lesson(YYYY-MM-DD): <what>` and where each rung writes it.
- `lesson-record` gains a date on the ruling line and prints the marker to use.
- `hookout.sh`: when a deny/block/feedback reason contains a marker, append one fire line to `.claude/lesson-fires.log` and **suppress** the second-identical-block nudge for that reason.
- New script `lesson-stats`: joins rulings and fires; text and `--json`.
- New script `lesson-claude-md`: budgeted, dedup-checked append with marker.
- `lesson-sites` gains a `deny` rung; `SKILL.md` ladder gains **Deny** between Test and Hook/lint.
- Tests in both suites for every new behaviour; README, `docs/reference/scripts.md`, `docs/reference/hooks.md` and `docs/decisions.md` rows.

### 2.2 Out of Scope (Non-Goals)

- **Staleness pass / reproducibility gate**: follow-up spec (research gaps 5 and 6).
- **Automatic writes of any rung**: the skill proposes, the user decides (unchanged).
- **`git stash` / quiet-flag coverage in git-guard**: a separate lesson, not this feature.
- **A `/wrap` summary line**: allowed later; not built here.
- **Counting test or deny-rule fires**: no hook runs; reported as unmeasured.

### 2.3 Adjacent Systems

| System | Relationship | Constraint |
|--------|-------------|------------|
| `hookout.sh` (`hook_deny/block/feedback`, `_lesson_nudge`) | Writes fires | Existing nudge behaviour for non-marker reasons is byte-identical |
| PROGRESS.md `## Rulings` | Read/written by `lesson-record`, read by `lesson-stats` | Existing rulings without a date still parse; `grep '^- Ruling: '` prefix unchanged |
| `.claude/` runtime state | New file `lesson-fires.log` | Must be treated as ignorable runtime state by `post-bash-write` and `stop-gate` (same class as `flow.json`) |
| `skills-lint`, `test_lesson_skill_frontmatter_and_references` | Validates `SKILL.md` | Every path the skill names must exist |
| `flow doctor` | Verifies deployment | New scripts must be executable and pass the portability grep |

---

## 3. User Journeys

### Journey 1 — Record a lesson with provenance (Priority: P1)

**Actor**: Model, on the Maintainer's yes.
**Starting condition**: Steps 1–3 of `/lesson` done; a rung chosen.
**Goal**: The rung is written with its reason attached, and the ruling is dated.

**Happy path**:
1. Model runs `lesson-record --what "…" --mechanism "…" --cost "…"`.
2. Script appends `- Ruling: <what> — <mechanism> — <cost> (2026-09-05)` and prints two lines: the ruling and `marker: lesson(2026-09-05): <what>`.
3. Model writes the marker in the host file's comment syntax on the rung it just wrote (`# …` in bash, `<!-- … -->` in markdown, the deny reason string in a hook).
4. For a hook rung, the hook's deny/block reason text ends with the bracketed marker `[lesson(2026-09-05): <what>]`.

**Error path — `--what` already recorded**:
1. Same `--what` with a new mechanism or cost.
2. Script writes the line and prints the superseding note to stderr (unchanged), still exit 0.
3. `lesson-stats` later shows `escaped: 1` for that lesson.

**Edge cases**:
- `--what` contains `(` or `)`: marker still printed verbatim; date parsing keys on the trailing `(YYYY-MM-DD)` only.
- Existing undated rulings: never rewritten.

**Acceptance criteria**:

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-001 | a PROGRESS.md with `## Rulings` | `lesson-record` runs with the three args | the appended line ends with ` (YYYY-MM-DD)` for today and stdout's second line is `marker: lesson(YYYY-MM-DD): <what>` | MUST |
| AC-002 | an existing undated ruling | `lesson-record` runs | the undated line is unchanged byte for byte | MUST |
| AC-003 | `--date 2026-01-02` passed | `lesson-record` runs | that date is used instead of today (tests need determinism) | MUST |
| AC-004 | `--date 20260102` passed | `lesson-record` runs | exit 2, nothing written | MUST |

---

### Journey 2 — A lesson-marked guardrail fires again (Priority: P1)

**Actor**: Model (the hook fires on its action); Maintainer reads stats later.
**Starting condition**: A hook branch whose reason contains `[lesson(DATE): what]` exists.
**Goal**: The fire is counted silently; the model is not nudged toward `/lesson` again.

**Happy path**:
1. Hook calls `hook_deny "…[lesson(2026-09-05): push --force in heredoc]"`.
2. `hookout.sh` appends `2026-09-05\tpush --force in heredoc\t<ISO-8601 UTC>\t<hook basename>` to `<project>/.claude/lesson-fires.log`.
3. Deny JSON/stderr output is identical to today. **No extra stdout line.** The `_lesson_nudge` "second identical block" line is **not** emitted for marker reasons.

**Error path — `.claude/` missing or unwritable**:
1. `mkdir -p .claude` fails or the file is not writable.
2. Hook continues; the fire is dropped; exit code and output unchanged (advisory bookkeeping never breaks a deny).

**Edge cases**:
- Reason with two markers: first one counts.
- `flow off` active: judging hooks already exit early; nothing is written.
- No git project dir: falls back to `$PWD/.claude` exactly as `hook_project_dir` does.

**Acceptance criteria**:

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-010 | a temp project | a test hook denies twice with the same marker reason | `.claude/lesson-fires.log` has two lines with that date and what, and stderr/stdout contain no `/lesson` nudge | MUST |
| AC-011 | same setup, reason without a marker | denies twice | behaviour identical to today: nudge on second, no log file | MUST |
| AC-012 | `.claude` unwritable | deny with marker | exit code and JSON identical; no crash; no log | MUST |

---

### Journey 3 — Read whether lessons held (Priority: P1)

**Actor**: Maintainer.
**Starting condition**: PROGRESS.md has rulings; some fires logged.
**Goal**: One command answers "did each lesson do anything?" without touching the turn loop.

**Happy path**:
1. Maintainer runs `lesson-stats` (or `lesson-stats --json`).
2. Output: one row per ruling: date, what, rung (first word of mechanism), caught count, days since last fire, escaped count, verdict.
3. Verdict rules, first match wins: `unmeasured` for undated rulings and for rungs other than `hook` and `lint` (only those fire through a hook); `escaped` when escaped > 0; `held` when caught > 0; `prune?` when caught = 0 and ruling age ≥ 30 days; otherwise `young`. Fires matching no ruling are listed last with verdict `orphan`.

**Error path — no PROGRESS.md**: prints `lesson-stats: no PROGRESS.md in <dir>` to stderr, exit 2.

**Edge cases**:
- Fires whose what matches no ruling: listed at the end under `orphan fires` (the ruling was edited or deleted).
- Log line malformed: skipped, counted in a stderr warning.

**Acceptance criteria**:

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-020 | 3 rulings (hook 40 days old with 0 fires, hook 2 days old with 2 fires, CLAUDE.md line) | `lesson-stats` | verdicts are `prune?`, `held`, `unmeasured` respectively | MUST |
| AC-021 | same data | `lesson-stats --json` | valid JSON array parsed by `python3 -c json.load`, same fields | MUST |
| AC-022 | a duplicate-what ruling | `lesson-stats` | that what shows `escaped: 1` and verdict `escaped` | MUST |
| AC-023 | `--now 2026-10-15` passed | `lesson-stats` | age computed against that date (determinism) | MUST |

---

### Journey 4 — Add a CLAUDE.md line within budget (Priority: P1)

**Actor**: Model, on the Maintainer's yes.
**Starting condition**: Ladder stopped at the CLAUDE.md rung.
**Goal**: The line lands with its marker, never as a duplicate, never over budget.

**Happy path**:
1. Model runs `lesson-claude-md --file CLAUDE.md --line "- Never edit a test to go green." --what "…" --date 2026-09-05`.
2. Script appends `- Never edit a test to go green. <!-- lesson(2026-09-05): … -->`, prints the written line and `lines: 87/100`.

**Error path — duplicate**:
1. An existing line equals the new one after normalisation (lowercase, whitespace collapsed, punctuation and any marker stripped).
2. Exit 3, nothing written, stderr names the existing line and its number.

**Error path — at budget**:
1. File has ≥ 100 lines (project) or ≥ 40 (`~/.claude/CLAUDE.md`; `--budget N` overrides).
2. Exit 5, nothing written, stderr: `at budget (100/100): pass --cut "<exact existing line>" to swap`.
3. With `--cut`, the named line is removed and the new one appended in the same locked write.

**Edge cases**:
- Similar lines (≥ 50% of the new line's words of 4+ letters appear in one existing line): written, but stdout lists `similar: <line no>: <text>` so the skill can ask the user; exit 0.
- `--cut` names a line that does not exist: exit 3, nothing written.
- File missing: created with the single line (project file only; never creates `~/.claude/CLAUDE.md`).

**Acceptance criteria**:

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-030 | 10-line CLAUDE.md | append a new line with `--what` | last line is the text plus ` <!-- lesson(DATE): what -->`; stdout has `lines: 11/100` | MUST |
| AC-031 | file already has the line in different case/punctuation | append | exit 3, file unchanged, stderr names line number | MUST |
| AC-032 | 100-line file | append without `--cut` | exit 5, file unchanged | MUST |
| AC-033 | 100-line file | append with `--cut` of an existing line | file still 100 lines, old line gone, new line last | MUST |
| AC-034 | file with a line sharing most words | append | exit 0, stdout contains `similar:` | SHOULD |

---

### Journey 5 — The ladder offers a Deny rung (Priority: P2)

**Actor**: Model, reading `SKILL.md` and `lesson-sites`.
**Goal**: For "the agent routed around the hook", the skill points at `permissions.deny` before a hook.

**Happy path**:
1. `lesson-sites` prints a `deny` line: `present <path>` only when `.claude/settings.json` exists **and** contains `"deny"`; `absent` otherwise, naming that file as the place to add a `permissions.deny` block (or to create, when missing); the global `~/.claude/settings.json` is named in the detail either way.
2. `SKILL.md` Step 3 table reads Test → **Deny** → Hook / lint → Script → Skill → CLAUDE.md, with the question "Must the tool call never be allowed at all, even if a hook is bypassed or disabled? (e.g. `Bash(git commit --no-verify*)`)".
3. Step 4 says a deny rung's provenance is the ruling only (JSON has no comments) and the mechanism text must quote the rule.

**Acceptance criteria**:

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-040 | temp project without settings.json | `lesson-sites` | a `deny absent …` line and `--json` has a `deny` key | MUST |
| AC-041 | temp project with `.claude/settings.json` containing `"deny"` | `lesson-sites` | `deny present <path>` | MUST |
| AC-042 | `SKILL.md` | the existing `test_lesson_skill_frontmatter_and_references` and a new test in `test_lesson_ladder.sh` run | both pass; the new one finds `Deny` between Test and Hook in the rung table and `lesson-stats`, `lesson-claude-md` referenced by `${CLAUDE_PLUGIN_ROOT}/scripts/` path and present on disk | MUST |
| AC-043 | `.claude/settings.json` exists without a deny block | `lesson-sites` | `deny absent` names that file as the place to add `permissions.deny` | MUST |

---

## 4. Functional Requirements

### 4.1 Core Requirements

| ID | Actor | Requirement | Priority | Acceptance Link |
|----|-------|-------------|----------|-----------------|
| FR-001 | Model | `lesson-record` MUST date every new ruling and print the marker text | MUST | AC-001..004 |
| FR-002 | System (hooks) | A deny/block/feedback reason containing `lesson(YYYY-MM-DD): …` MUST be appended to `.claude/lesson-fires.log` with no change to the hook's stdout, stderr wording, or exit code, and MUST NOT trigger the second-identical-block nudge | MUST | AC-010..012 |
| FR-003 | Maintainer | `lesson-stats` MUST list every ruling with caught, escaped, age and verdict, text and `--json` | MUST | AC-020..023 |
| FR-004 | Model | `lesson-claude-md` MUST refuse normalised duplicates (exit 3) and at-budget writes without `--cut` (exit 5), and MUST append the marker | MUST | AC-030..033 |
| FR-005 | Model | `lesson-sites` MUST report a `deny` rung; `SKILL.md` MUST list Deny between Test and Hook/lint | MUST | AC-040..043 |
| FR-006 | Model | `SKILL.md` Step 4 MUST state the marker rule per rung and Step 6 MUST name `lesson-stats` as the way to check later, without adding any per-turn instruction | MUST | AC-042 |
| FR-007 | Maintainer | `flow lessons` SHOULD run `lesson-stats` in the current project | SHOULD | — |
| FR-008 | Model | `lesson-claude-md` SHOULD list similar existing lines | SHOULD | AC-034 |

### 4.2 Data Requirements

| Entity | Description | Key attributes (logical) | Relationships |
|--------|-------------|--------------------------|---------------|
| Ruling | One lesson, in PROGRESS.md | what, mechanism, cost, date (optional for legacy) | 1..n Fires by (date, what) |
| Marker | Provenance text next to a rung | date, what | equals the Ruling key |
| Fire | One guardrail activation | date, what, timestamp (UTC), hook basename | belongs to a Ruling or is orphan |

**Data retention**: `.claude/lesson-fires.log` grows one line per fire; `lesson-stats --prune-log` is out of scope; the file is gitignored runtime state and may be deleted freely.
**Data sensitivity**: none; contains reason text the hook already printed.

---

## 5. Non-Functional Requirements

### 5.1 Performance

| Metric | Target | Condition | Measurement method |
|--------|--------|-----------|-------------------|
| Added latency in `hook_deny/block/feedback` | ≤ 20 ms | reason with marker, warm disk | `time` in test on a 1,000-line log |
| `lesson-stats` runtime | ≤ 1 s | 200 rulings, 10,000 fires | test with generated data |

**Performance budget decision**: a hook that exceeds its `hooks.json` timeout is a defect; everything else is a known limitation.

### 5.2 Security

**Authentication / Authorization**: local files only; no roles beyond the file system.
**Data protection**: none needed.
**Threat surface**: a marker string crafted in a reason could inject tab/newline into the log; the writer MUST strip `\t` and `\n` from what before writing.

### 5.3 Reliability & Availability

**Graceful degradation**: any failure to write a fire or read the log leaves hook behaviour untouched (fail open for bookkeeping; deny decisions unaffected).
**Recovery behavior**: deleting the log resets counts; rulings remain.

### 5.4 Error Handling

| Error condition | Actor-visible behavior | System behavior | Recovery path |
|----------------|----------------------|-----------------|---------------|
| duplicate CLAUDE.md line | stderr `lesson-claude-md: duplicate of line N: …`, exit 3 | nothing written | rephrase or skip |
| at budget | stderr `at budget (N/N): pass --cut …`, exit 5 | nothing written | pick a line to cut |
| PROGRESS.md missing (stats) | stderr, exit 2 | nothing | run `lesson-record` first |
| log unwritable (hook) | nothing | fire dropped | none needed |

### 5.5 Scalability

Single developer, single machine; re-evaluate if the log passes 100k lines.

### 5.6 Observability

`lesson-stats` is the only surface. No logging beyond the fire lines. No alerting.

### 5.7 Accessibility / 5.8 Platform

CLI text; bash 3.2 and BSD tools (macOS default) and Linux; the suites' portability grep is the gate.

---

## 6. Success Criteria

### 6.1 Launch Criteria (go/no-go)

- [ ] All MUST ACs pass in both suites (`hooks/tests/run.sh`, `scripts/tests/run.sh`), zero failures.
- [ ] Portability grep and shellcheck clean.
- [ ] `flow doctor` green with the new scripts installed.
- [ ] A hook run with and without a marker reason produces byte-identical stdout (test asserts it).
- [ ] `skills-lint` passes on `SKILL.md`.

### 6.2 Post-Launch Health Metrics

| Metric | Target | Measurement | Review trigger |
|--------|--------|-------------|----------------|
| Nudge lines per session | unchanged from before | grep session transcripts for `/lesson` nudges | any increase |
| Rulings with a marker in their rung | 100% of new rulings | `lesson-stats` orphan count = 0 | any orphan |

### 6.3 What "Failure" Looks Like

Everything passes, but the maintainer never runs `lesson-stats`, so counts accrue unread. Mitigation later: one line in `/wrap`, deliberately out of scope now.

---

## 7. Constraints & Assumptions

### 7.1 Technical Constraints

| Constraint | Rationale | Impact on design |
|-----------|-----------|-----------------|
| bash 3.2 / BSD tools | macOS default shell; suites enforce a banned list | no `date -d`, no `date -v`, no `declare -A`; age math is an inline awk Julian-day function in `lesson-stats`, with `--now` / `--date` overrides for tests |
| Zero per-turn noise | maintainer's stated constraint | counting silent; nudge suppressed for marker reasons |
| PROGRESS.md ≤ 60 lines | existing rule | dated rulings add ~13 chars, no lines |

### 7.2 Assumptions

| ID | Assumption | Confidence | Owner | How to validate |
|----|-----------|------------|-------|-----------------|
| A-001 | Marker grammar `lesson(YYYY-MM-DD): <what>` is acceptable; comment syntax varies by host file | High | Maintainer | plan approval |
| A-002 | Duplicate = equal after lowercasing, whitespace collapse, punctuation and marker strip; "similar" = ≥ 50% of content words shared | Medium | Maintainer | plan approval; AC-031/034 |
| A-003 | Fire log lives at `<project>/.claude/lesson-fires.log`, treated like `flow.json` | High | Maintainer | `post-bash-write` ignores it (test) |
| A-004 | Prune hint threshold is 30 days with zero fires, only for hook/lint/script rungs | Medium | Maintainer | `--prune-days N` override exists |
| A-005 | Maintainer is the sole user; no migration of old undated rulings | High | Maintainer | — |

### 7.3 Dependencies

| Dependency | Type | Owner | Status | Risk if delayed |
|-----------|------|-------|--------|-----------------|
| `hookout.sh` `_lesson_nudge` signature logic | Blocking | this repo | available | none |
| `python3` for JSON parsing in tests | Informational | system | present | tests skip JSON parse if absent |

---

## 8. Open Questions

| ID | Question | Impact if unresolved | Owner | Deadline |
|----|---------|----------------------|-------|----------|
| Q-001 | Should `flow lessons` (FR-007) ship in v1 or wait? | UX only; script works standalone | Maintainer | plan approval |

---

## 9. Revision History

| Version | Date | Author | Changes | Reason |
|---------|------|--------|---------|--------|
| 1.0 | 2026-09-05 | Mr Claude | Initial draft | research sweep gaps 1–4 |

## Appendix

### A. Glossary

| Term | Definition in this spec |
|------|-------------------------|
| Rung | One level of the `/lesson` ladder: test, deny, hook/lint, script, skill, CLAUDE.md |
| Marker | `lesson(YYYY-MM-DD): <what>`, written in the host file's comment syntax |
| Fire | A hook deny/block/feedback whose reason carries a marker |
| Caught | Count of fires for one ruling |
| Escaped | Count of later rulings with the same what |

### B. Mockups

No mockups — behaviour is fully specified by the acceptance criteria.

### C. Reference Documents

| Document | What it answers | Link |
|----------|----------------|------|
| Research sweep | Evidence and ranking for the four gaps | docs/research/raw/lesson-guardrails-2026.md |
| Lesson skill | Current ladder | plugins/flow/skills/lesson/SKILL.md |
| Hook output lib | Where fires are counted | plugins/flow/hooks/lib/hookout.sh |
