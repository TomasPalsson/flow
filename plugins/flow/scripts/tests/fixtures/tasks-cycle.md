# Tasks — Cycle
Spec: spec.md · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 | given / when / then | T001 | t1 |

## Phase 1 — Loop
Goal: two tasks depend on each other.
Independent test: `pytest -q`
- [ ] T001 a — files: a.py — verify: `pytest -q` — after: T002
- [ ] T002 b — files: b.py — verify: `pytest -q` — after: T001

## Gates
- [ ] G001 clean — verify: `flow check`
