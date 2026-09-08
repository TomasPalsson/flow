# Tasks — Sequenced overlap
Spec: spec.md · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 | given / when / then | T001 | t1 |

## Phase 1 — Sequenced
Goal: the same file is touched in two different waves.
Independent test: `pytest -q`
- [ ] T001 [P] Google auth — files: src/auth/google.ts, src/auth/shared.test.ts — verify: `pytest -q`
- [ ] T002 [P] Github auth — files: src/auth/github.ts, src/auth/shared.test.ts — verify: `pytest -q` — after: T001

## Gates
- [ ] G001 clean — verify: `flow check`
