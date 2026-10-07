# aihero.dev/skills (mattpocock/skills) borrow review — 2026-10-07

Source: https://www.aihero.dev/skills → github.com/mattpocock/skills at f3fc563 (MIT). All 38 SKILL.md files read in full, plus the reference files that the candidate borrows depend on.

## Borrowed

| Upstream | Landed in | Why |
|---|---|---|
| diagnosing-bugs | `flow/skills/fix/feedback-loops.md` + `scripts/hitl-loop.template.sh`; fix §1/§2/§3/§5 | Fix used to stop as soon as a plain unit test could not be written. Now it walks a 10-rung ladder of red-capable loops first (curl, CLI snapshot, headless browser, replayed trace, harness, fuzz, bisect, differential, HITL). It also borrows minimise, 3–5 falsifiable hypotheses (reported in the one §3 gate, never an extra stop), `[DEBUG-xxxx]` tagged logs, and the "no correct seam is a finding" route to /flow:issue. |
| retro | `flow/skills/lesson` `--retro` | Lesson builds one guardrail per mistake; retro finds the candidates across a whole session. Each candidate the user picks goes through the existing ladder. |
| pr | `flow/skills/shared/pr-body.md`, used by next §Ship and fix §5 | Smallest-visual summary, before/after evidence, and a one-way/two-way door plus blast radius. Rulings and revert proofs are still appended. |
| to-tickets (wide refactors) | next TASKS.md drafting | Expand → migrate → contract, so a column rename still lands green task by task. |
| tdd tests.md / mocking.md | no-slop developer block | Test through the public interface, mock only at system boundaries, never verify via a side channel. NS-26/NS-28 already covered tautological and never-red tests. |
| grilling | flow-extras `grill-with-docs` | Replaces the stale one-at-a-time copy with rounds over the frontier, one recommendation per question, and non-blocking fact lookups. |
| writing-for-agents | `skill-improver/references/writing-for-agents.md`; pointers from skill-improver, skill-forge, claude-md | Context pointers, leading words, negation, no-ops and completion criteria. No local skill covered these. |
| wizard | tooling `wizard` + `template.sh` | Generates an interactive bash script for steps only a human can do (dashboards, secrets, cutovers). There was no local equivalent. |

## Skipped, and why

- grill-me: the local copy was changed on purpose (open questions, recommendation only after the user answers, to avoid anchoring). Upstream's batched rounds could still come here later if the user wants fewer turns.
- code-review (Standards + Spec axes): flow already runs 5 adversary lenses, and acceptance.md proves every criterion with an exit code. The Fowler smells mostly overlap NS-01/21/24.
- tdd, to-spec, to-tickets, implement, implement-spec: flow:spec, TASKS.md `after:` waves, build-slices and the developer block already cover them. implement-spec's frontier scheduling is close to waves already.
- triage, wayfinder, setup-matt-pocock-skills: these are built around an issue tracker and a team. flow:issue and develop-idea → prep → spec cover solo work. Revisit wayfinder for a foggy greenfield effort.
- codebase-design, improve-codebase-architecture, domain-modeling: flow-deepen, audit, and grill-with-docs's domain section.
- git-guardrails: hooks/git-guard.sh already blocks more patterns. setup-pre-commit: `harness init`.
- research, teach, handoff, claude-handoff, wait-what, ask-matt: research-sweep, teacher, PROGRESS.md plus on-disk flow state, the ELI5 output style, and the `flow next` router.
- prototype: design:showcase covers UI variants. The logic-prototype branch is a possible later add.
- to-questionnaire, chief-of-staff, loop-me, writing-*, shoehorn, scaffold-exercises, setup-ts-deep-modules: niche or personal to the author.
- PHASE-BOUNDARIES ("continue before /clear"): flow ends turns with /clear on purpose, because state and Rulings live on disk.

## Verification

Before and after the change, these 7 touched test files passed with 0 failures: test_fix_prose (21), test_lesson (87), test_no_slop (54), test_no_slop_seams (22), test_marketplace (155), test_agents (47), test_lint (70). One adversary found that test_plugin_refs broke on a `~/.claude/` string; it is fixed and that file now passes 26/26. In the full scripts suite, no test fails only on this branch: 11 fail here, and all 11 also fail on a clean copy of main.

Open: shellcheck is not installed on this machine, so neither copied template was shellchecked. wizard/template.sh lines ~96 and ~139 use quote-in-replacement forms that are worth a round trip under macOS /bin/bash 3.2.
