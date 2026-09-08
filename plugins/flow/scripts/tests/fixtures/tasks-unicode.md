# Tasks — Ísland
Spec: spec.md · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 | Þegar notandi — smellir | T001 | t1 |

## Phase 1 — Þýðingar
Goal: descriptions may hold an em dash — like this — and stay one task.
Independent test: `pytest -q`
- [ ] T001 Bæta við þýðingum — með striki — files: src/þýð.py — verify: `pytest -q`

## Gates
- [ ] G001 clean — verify: `flow check`
