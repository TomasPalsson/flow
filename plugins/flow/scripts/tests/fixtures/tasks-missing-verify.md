# Tasks — No verify
Spec: spec.md · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 | given / when / then | T001 | t1 |

## Phase 1 — Sloppy
Goal: a task with no verify.
Independent test: `pytest -q`
- [ ] T001 Do the thing — files: src/a.py

## Gates
- [ ] G001 clean — verify: `flow check`
