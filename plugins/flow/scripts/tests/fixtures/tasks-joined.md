# Tasks — Joined actions
Spec: spec.md · Design: none · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a user, when they log in, then a session exists | T001 | test_login |

## Phase 1 — Login and cache
Goal: a user can log in and the cache is usable.
Independent test: `pytest tests/test_login.py`
- [ ] T001 Add login and export CSV — files: src/login.py, src/export.py — verify: `pytest tests/test_login.py`
- [ ] T002 Read and write cache — files: src/cache.py — verify: `pytest tests/test_cache.py`

## Gates
- [ ] G001 project gates clean — files: . — verify: `flow check`
