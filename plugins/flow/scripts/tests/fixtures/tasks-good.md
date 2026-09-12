# Tasks — Entry tagging
Spec: spec.md · Design: none · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`
Approved: 2026-09-08 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given an entry, when I POST a tag, then it persists | T002 | test_tag_persists |

## Phase 1 — Tag persistence
Goal: an entry can carry tags and survive a restart.
Independent test: `pytest tests/test_tags.py` — green with the UI untouched.
- [ ] T001 Migration + Tag model — files: db/schema.sql, src/models/tag.py — verify: `pytest tests/test_schema.py`
- [ ] T002 [P] POST tags persists (B1) — files: src/api/tags.py, tests/test_tags.py — verify: `pytest tests/test_tags.py` — after: T001
- [ ] T003 [P] Duplicate tag returns 409 (B2) — files: src/api/dedupe.py, tests/test_dedupe.py — verify: `pytest tests/test_dedupe.py` — after: T001

## Phase 2 — Tag filter UI
Goal: the filter chip works on mobile.
Independent test: `pytest tests/test_ui.py`
- [ ] CHK011 human-verify filter chip at 375px — files: src/ui/chip.tsx — verify: human: user says the chip wraps

## Gates
- [ ] G001 flow check clean — verify: `flow check --fix`
