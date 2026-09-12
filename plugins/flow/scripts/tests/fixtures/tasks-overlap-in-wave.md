# Tasks — Overlap
Spec: spec.md · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 | given / when / then | T001 | t1 |

## Phase 1 — Race
Goal: two tasks share a test file.
Independent test: `pytest -q`
- [ ] T001 [P] Google auth — files: src/auth/google.ts, src/auth/google.test.ts — verify: `pytest -q`
- [ ] T002 [P] Github auth — files: src/auth/github.ts, src/auth/google.test.ts — verify: `pytest -q`

## Gates
- [ ] G001 clean — verify: `flow check`
