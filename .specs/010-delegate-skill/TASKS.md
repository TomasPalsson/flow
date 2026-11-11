# Tasks — Delegate skill
Approved: 2026-11-11 by user
Verified: 2026-11-11 by user (pre-approved: /flow:next --finish)
Spec: none · Design: none · Base: 2b9be80 · Route: oneshot · Test: `bash plugins/flow/scripts/tests/run.sh`

## Behaviors
| ID | Given / When / Then | Task | Proven by | Key |
|----|---------------------|------|-----------|-----|
| FR-01 (P0) | Given a step whose spec would be longer than the edit, an iterative or context-sharing task, or no nameable acceptance command, when the session reads `delegate`, then it is told to stay in the main session | T001, T002 | t_delegate_stay_inline_cases | delegate/stay-inline |
| FR-02 (P0) | Given a worker is about to be spawned, when the session reads `delegate`, then it is told to pin `model` on every spawn, never Fable and never a fork | T001, T002 | t_delegate_pins_model | delegate/pin-model |
| FR-03 (P1) | Given a step a command or a quote can check, when the session picks a model, then it picks Haiku with a short single-purpose brief, Sonnet for writing code and judging diffs, Opus only after Sonnet failed with a good spec or for subtle concurrency or security review, and re-runs a failed Haiku check on Sonnet | T001, T002 | t_delegate_model_ladder | delegate/model-ladder |
| FR-04 (P1) | Given a worker brief, when it is written from the template, then it carries objective, exact owned paths, signatures and edge cases, acceptance command, return format and tools allowed | T001, T002 | t_delegate_brief_template | delegate/brief-template |
| FR-05 (P1) | Given a worker reports back, when it follows the skill, then the report is a verdict, files changed and failing output only, about 15 lines, and the session verifies by re-running the acceptance command | T001, T002 | t_delegate_report_format | delegate/report-format |
| FR-06 (P1) | Given several pieces of work, when the session plans a wave, then it uses 2 to 4 workers, sends same-mental-model or overlapping-file work to one worker, and does not poll | T001, T002 | t_delegate_wave_cap | delegate/wave-cap |
| FR-07 (P1) | Given the new skill file, when the skill lints run, then frontmatter is valid, no collision pair names `delegate`, and SKILL.md is 80 lines or fewer | T001, T002 | t_delegate_short_and_lints | delegate/lints-clean |
| FR-08 (P2) | Given the flow plugin docs, when a reader looks for the skill list, then `delegate` is listed and the count reads 14 | T003 | t_delegate_listed_in_docs | delegate/listed |
| FR-09 (P1) | Given the rule that every flow skill has an eval case or a waiver, when the eval coverage test runs, then `delegate` has a waiver line that says what is not measured | T004 | t_evals_every_skill_has_disposition | delegate/eval-waiver |

## Assumptions
<!-- Recorded under --unattended: each is a position stated in the discovery turn and not yet corrected. -->
- A1 (high) Users: the main Claude Code session, at the moment it is about to call the Agent tool or a Workflow agent. Today those rules live only in a personal global CLAUDE.md, so every worker pays to read them.
- A2 (high) Success: the five rule groups are present in one SKILL.md of 80 lines or fewer that passes `skills-lint`.
- A3 (high) Not in this feature: the PreToolUse model-pinning hook; moving `claim-check` or the `research-sweep` check stage to Haiku; editing `docs/reference/CLAUDE.md.example`; an eval case that measures whether sessions actually delegate less.
- A4 (medium) Acceptance is a prose test in the existing `test_*_prose.sh` pattern (observed: plugins/flow/scripts/tests/test_issue_prose.sh:1). It proves the words are in the file, not that a session obeys them.
- A5 (medium) Adding a skill bumps the flow plugin from 0.10.0 to 0.11.0 (observed: plugins/flow/.claude-plugin/plugin.json:3; assumed: a new skill is a minor bump, as the moonshot skill shipped with a version change per PROGRESS.md:4).
- A6 (medium) The description must not steal triggers from `flow-extras:ultracode` (fleet scale) — `delegate` is for a single spawn decision and says so with a "Do NOT use for" clause.
- A7 (low) Specs stay in-tree: `.specs/` already exists and is tracked here, so the stealth offer does not apply even though the repo is public.

## Review focus
Description wording against `flow-extras:ultracode` and `tooling:agent-architecture` triggers — T002
Rules stated once, plainly, with no stacked emphasis (IMPORTANT / NEVER walls) — T002

## Phase 1 — The delegate skill can be loaded and tells a session how to spawn a worker
Goal: a session about to spawn a worker loads `delegate` and reads whether to delegate at all, which model to pin, the brief to write, the report to ask for and how many workers to run; the skill lints clean and is listed in the plugin docs.
Independent test: `TEST_ONLY=test_delegate_prose.sh bash plugins/flow/scripts/tests/run.sh > .specs/010-delegate-skill/verify/prose-phase1.log 2>&1; grep -q '^t_delegate_' .specs/010-delegate-skill/verify/prose-phase1.log && ! grep '^  FAIL ' .specs/010-delegate-skill/verify/prose-phase1.log | grep -qvxFf .specs/010-delegate-skill/verify/baseline-tests.txt && plugins/flow/scripts/skills-lint --frontmatter plugins/flow/skills && ! plugins/flow/scripts/skills-lint --collisions plugins/flow/skills | grep -q 'delegate/SKILL.md'` — the prose test reads the real SKILL.md and the real docs, and both lints run over the real skills tree.
- [x] T000 Record the test suite at Base, before any other task commits: run the `Test:` command and write its exit code plus the failing test names — files: .specs/010-delegate-skill/verify/baseline-tests.txt — verify: `test -s .specs/010-delegate-skill/verify/baseline-tests.txt` — done: cb21034
- [x] T001 Prose test for the delegate rules, written first and red (FR-01 to FR-08): one `t_delegate_*` function per Behaviors row, named as in the Proven by column — files: plugins/flow/scripts/tests/test_delegate_prose.sh — verify: `bash -n plugins/flow/scripts/tests/test_delegate_prose.sh` — follow: plugins/flow/scripts/tests/test_issue_prose.sh — after: T000 — done: 8c00265
- [x] T002 Write the `delegate` skill (FR-01 to FR-07): frontmatter `name: delegate` plus a description with trigger phrases and a "Do NOT use for" clause naming fleet-scale work; body in five short sections (when delegating pays and when to stay inline, model pick, brief template, report format, wave size), 80 lines or fewer — files: plugins/flow/skills/delegate/SKILL.md — verify: `TEST_ONLY=test_delegate_prose.sh bash plugins/flow/scripts/tests/run.sh > .specs/010-delegate-skill/verify/prose-T002.log 2>&1; grep -q '^t_delegate_' .specs/010-delegate-skill/verify/prose-T002.log && ! grep '^  FAIL ' .specs/010-delegate-skill/verify/prose-T002.log | grep -v 'delegate docs:' | grep -qvxFf .specs/010-delegate-skill/verify/baseline-tests.txt` — no_claim: a prose test proves the rules are written down, not that a session follows them — follow: plugins/flow/skills/no-slop/SKILL.md — after: T001 — done: 985bb06
- [x] T003 List `delegate` in the plugin docs and bump the flow version to 0.11.0 (FR-08): README skill list, `## flow (14 skills + shared)` with a `- delegate` row in alphabetical order, plugin.json version — files: plugins/flow/README.md, docs/reference/plugins.md, plugins/flow/.claude-plugin/plugin.json, .claude-plugin/marketplace.json — verify: `TEST_ONLY=test_delegate_prose.sh bash plugins/flow/scripts/tests/run.sh > .specs/010-delegate-skill/verify/prose-T003.log 2>&1; grep -q '^t_delegate_' .specs/010-delegate-skill/verify/prose-T003.log && ! grep '^  FAIL ' .specs/010-delegate-skill/verify/prose-T003.log | grep -qvxFf .specs/010-delegate-skill/verify/baseline-tests.txt` — after: T002 — done: f9db01d
- [x] T004 Waive the eval case for `delegate` with a reason line (FR-09), found by the full-suite run at f040ffc — files: plugins/flow/evals/NO-EVAL.txt — verify: `TEST_ONLY=test_evals.sh bash plugins/flow/scripts/tests/run.sh > .specs/010-delegate-skill/verify/evals-T004.log 2>&1; grep -q '^  ok   every flow skill has a case or a NO-EVAL.txt waiver' .specs/010-delegate-skill/verify/evals-T004.log` — after: T003 — done: 9db80a3

## Gates
- [x] G001 project gates clean — files: . — verify: `flow check --fix --since 2b9be80` — done: d17e12c
- [x] G002 branch review clean — files: . — verify: `flow pass` — done: d17e12c
- [x] G003 verification evidence exists — files: . — verify: `test -s verify/` — done: d17e12c
