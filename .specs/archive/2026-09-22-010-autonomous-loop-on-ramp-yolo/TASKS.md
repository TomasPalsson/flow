# Tasks — Autonomous loop on-ramp (--yolo)
Approved: 2026-09-22 by user
Verified: 2026-09-22 by user
Spec: spec.md · Design: design.md · Base: 418f2d2 · Route: dispatch · Test: `TEST_ONLY=test_loop.sh bash plugins/flow/scripts/tests/run.sh`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a contract whose started_at is blank, when the loop ticks, then it is corrupt rather than uncapped | T001 | t_loop_started_at_corrupt |
| B2 (P1) | Given an armed loop, when the router is asked what is next, then it names the goal and the status command | T002 | t_next_loop_active_why |
| B3 (P0) | Given a verifier that cannot fail, when the bootstrap runs its negative control, then arming is refused | T003 | t_negcontrol_survives_refuses |
| B4 (P0) | Given a negative control that is interrupted, when it returns, then the tree is byte-identical | T003 | t_negcontrol_restores_tree |
| B5 (P1) | Given --yolo with no explicit caps, when the loop is armed, then the contract carries 240 minutes and 40 iterations and no money cap | T004 | t_yolo_default_caps |
| B6 (P0) | Given a yolo run, when a child is spawned, then its arguments carry the no-prompt setting | T004 | t_yolo_child_argv |
| B7 (P0) | Given a yolo run, when a test file disappears, then the run stops rather than continuing as suspect | T005 | t_failclosed_tamper_stops |
| B8 (P1) | Given an idea and --yolo, when the operator reads the skill, then Step 0 tells them exactly what is bootstrapped and what is refused | T006, T007 | t_loop_docs_yolo |

## Phase 1 — Prerequisites
Goal: an unattended run can no longer lose its wall-clock cap in silence, and coming back to an armed loop explains itself.
Independent test: `TEST_ONLY=test_loop.sh bash plugins/flow/scripts/tests/run.sh` — green with nothing else touched.
- [x] T001 [P] An unreadable started_at is corrupt (B1, FR-01) — files: plugins/flow/bin/lib/loop/contract.js, plugins/flow/scripts/tests/test_loop.sh — verify: `TEST_ONLY=test_loop.sh bash plugins/flow/scripts/tests/run.sh` — done: 7c2c820
- [x] T002 [P] loop-active states which loop and how to inspect it (B2, FR-02) — files: plugins/flow/bin/flow, plugins/flow/scripts/tests/test_next.sh — verify: `TEST_ONLY=test_next.sh bash plugins/flow/scripts/tests/run.sh` — done: 7c2c820

## Phase 2 — The arming safety net
Goal: no loop can be armed on a verifier that has not been shown to fail, and no failed bootstrap leaves anything behind.
Independent test: `TEST_ONLY=test_loop_negcontrol.sh bash plugins/flow/scripts/tests/run.sh` — green with the driver untouched.
- [x] T003 The negative control, and init refuses to arm without it (B3, B4, FR-04, FR-05, FR-11) — files: plugins/flow/bin/lib/loop/negcontrol.js, plugins/flow/bin/lib/loop/init.js, plugins/flow/scripts/tests/test_loop_negcontrol.sh — verify: `TEST_ONLY=test_loop_negcontrol.sh bash plugins/flow/scripts/tests/run.sh` — after: T001 — done: 49caae4
- [x] T005 A tamper finding stops a yolo run (B7, FR-07) — files: plugins/flow/bin/lib/loop/tick.js, plugins/flow/scripts/tests/test_loop_failclosed.sh — verify: `TEST_ONLY=test_loop_failclosed.sh bash plugins/flow/scripts/tests/run.sh` — after: T001 — done: 16e5966

## Phase 3 — The unattended child
Goal: a yolo run is bounded by time and iterations, and its children can never sit waiting for an answer nobody will give.
Independent test: `TEST_ONLY=test_loop_yolo.sh bash plugins/flow/scripts/tests/run.sh` — green with the negative control untouched.
- [x] T004 --yolo defaults and child arguments (B5, B6, FR-09, FR-12) — files: plugins/flow/bin/lib/loop/init.js, plugins/flow/bin/lib/loop/driver.js, plugins/flow/scripts/tests/test_loop_yolo.sh — verify: `TEST_ONLY=test_loop_yolo.sh bash plugins/flow/scripts/tests/run.sh` — after: T003 — done: 2acd7ba

## Phase 4 — The on-ramp
Goal: an operator can type one command with an idea and understand, before they leave, exactly what will happen and what would stop it.
Independent test: `TEST_ONLY=test_loop_docs.sh bash plugins/flow/scripts/tests/run.sh` — green with no code touched.
- [x] T006 Step 0 in the loop skill: bootstrap, refuse, arm (B8, FR-03, FR-06, FR-08, FR-10, FR-13) — files: plugins/flow/skills/loop/SKILL.md, plugins/flow/scripts/tests/test_loop_docs.sh — verify: `TEST_ONLY=test_loop_docs.sh bash plugins/flow/scripts/tests/run.sh` — after: T004, T009 — done: dcf2f25
- [x] T007 The yolo-bootstrap reference: spec routing, task derivation, verifier composition, shared-repo rules (B8) — files: plugins/flow/skills/loop/references/yolo-bootstrap.md — verify: `TEST_ONLY=test_loop_docs.sh bash plugins/flow/scripts/tests/run.sh` — after: T006 — done: 6df8760
- [x] T009 The fix-skill docs check asserts the direct (no-loop) execution path instead of the heading removed in 14f8844 — files: plugins/flow/scripts/tests/test_loop_docs.sh — verify: `TEST_ONLY=test_loop_docs.sh bash plugins/flow/scripts/tests/run.sh` — after: T004 — done: f6e3488

## Phase 5 — Proof
Goal: the thing actually works once, unattended, on a repo that is not this one.
Independent test: human.
- [x] CHK008 human-verify one real unattended run on a throwaway repo reaches a draft PR with zero prompts — files: . — verify: human: operator confirms a draft PR exists, no question was asked, and the report names the cap that ended it — after: T007 — done: 6df8760 by user

## Gates
- [x] G001 project gates clean — files: . — verify: `flow check --fix` — done: 0ec2d57
- [x] G002 branch review clean — files: . — verify: `test -f PASS-$(git rev-parse --short HEAD).md` — done: 0ec2d57
- [x] G003 verification evidence exists — files: . — verify: `test -s verify/` — done: 0ec2d57
