# Tasks — Too big for oneshot
Spec: spec.md · Base: 4f2a91c · Route: oneshot · Test: `pytest -q`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 | given / when / then | T001 | t1 |

## Phase 1 — Six
Goal: six tasks on a oneshot route.
Independent test: `pytest -q`
- [ ] T001 a — files: a.py — verify: `pytest -q`
- [ ] T002 b — files: b.py — verify: `pytest -q`
- [ ] T003 c — files: c.py — verify: `pytest -q`
- [ ] T004 d — files: d.py — verify: `pytest -q`
- [ ] T005 e — files: e.py — verify: `pytest -q`
- [ ] T006 f — files: f.py — verify: `pytest -q`

## Gates
- [ ] G001 clean — verify: `flow check`
