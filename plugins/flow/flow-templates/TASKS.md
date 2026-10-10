# Tasks — Entry tagging
Spec: spec.md · Design: none · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`
<!-- Optional header field, only when spec.md says **Behaviour-preserving**: yes — "· Parity: <cmd>". Plan T000 runs it at Base into verify/baseline.txt; a G### gate runs "<cmd> | diff verify/baseline.txt -". -->

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given an entry, when I add a tag, then it persists and its chip shows | T002, T003 | test_tag_persists, test_chip_renders |
| B2 (P1) | Given a duplicate tag, when I add it, then the API returns 409 and the form says so | T004, T005 | test_duplicate_409, test_duplicate_message |

## Phase 1 — A tag can be added and seen
Goal: a user adds a tag to an entry and sees its chip, with the database, API and UI all in play.
Independent test: `pytest tests/test_tags.py tests/test_ui.py` — a tag is added through the API and its chip renders from what was stored.
- [ ] T001 Migration and Tag model — files: db/schema.sql, src/models/tag.py — verify: `pytest tests/test_schema.py`
- [ ] T002 [P] POST tags persists (B1) — files: src/api/tags.py, tests/test_tags.py — verify: `pytest tests/test_tags.py::test_tag_persists` — after: T001
- [ ] T003 [P] Tag chip renders stored tags (B1) — files: src/ui/chip.tsx, tests/test_ui.py — verify: `pytest tests/test_ui.py::test_chip_renders` — after: T001

## Phase 2 — Duplicates are rejected and shown
Goal: adding a tag that already exists is refused by the API and the form tells the user why.
Independent test: `pytest tests/test_dedupe.py tests/test_form.py` — a duplicate POST returns 409 and the form shows the message.
- [ ] T004 [P] Duplicate tag returns 409 (B2) — files: src/api/dedupe.py, tests/test_dedupe.py — verify: `pytest tests/test_dedupe.py` — after: T002
- [ ] T005 [P] Form shows the duplicate message (B2) — files: src/ui/form.tsx, tests/test_form.py — verify: `pytest tests/test_form.py::test_duplicate_message` — after: T004
- [ ] CHK011 human-verify the duplicate message at 375px in dark mode — files: src/ui/form.tsx — verify: human: user says the message wraps and stays legible — after: T004, T005

## Gates
- [ ] G001 project gates clean — files: . — verify: `flow check --fix --since 4f2a91c`
- [ ] G002 branch review clean — files: . — verify: `flow pass`
- [ ] G003 verification evidence exists — files: . — verify: `test -s verify/`
