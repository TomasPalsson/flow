# Tasks — Entry tagging
Spec: spec.md · Design: none · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given an entry, when I POST a tag, then it persists | T002 | test_tag_persists |
| B2 (P1) | Given a duplicate tag, when I POST it, then the API returns 409 | T003 | test_duplicate_409 |

## Phase 1 — Tag persistence
Goal: an entry can carry tags and survive a restart.
Independent test: `pytest tests/test_tags.py` — green with the UI untouched.
- [ ] T001 Migration and Tag model — files: db/schema.sql, src/models/tag.py — verify: `pytest tests/test_schema.py`
- [ ] T002 [P] POST tags persists (B1) — files: src/api/tags.py, tests/test_tags.py — verify: `pytest tests/test_tags.py::test_tag_persists` — after: T001
- [ ] T003 [P] Duplicate tag returns 409 (B2) — files: src/api/dedupe.py, tests/test_dedupe.py — verify: `pytest tests/test_dedupe.py` — after: T001

## Phase 2 — Tag filter UI
Goal: the filter chip reads correctly on a phone.
Independent test: `pytest tests/test_ui.py` — green with the API untouched.
- [ ] T004 Filter chip component — files: src/ui/chip.tsx, tests/test_ui.py — verify: `pytest tests/test_ui.py`
- [ ] CHK011 human-verify the filter chip at 375px in dark mode — files: src/ui/chip.tsx — verify: human: user says the chip wraps and stays legible

## Gates
- [ ] G001 project gates clean — files: . — verify: `flow check --fix`
- [ ] G002 branch review clean — files: . — verify: `test -f PASS-$(git rev-parse --short HEAD).md`
- [ ] G003 verification evidence exists — files: . — verify: `test -s verify/`
