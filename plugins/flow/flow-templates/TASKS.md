# Tasks — Entry tagging
Spec: spec.md · Design: none · Base: 4f2a91c · Route: dispatch · Test: `pytest -q`
<!-- Optional task field: " — follow: <repo path>" names an existing production file whose pattern the task copies (lint errors when the path is missing; task-brief prints it as "Follow: <path>"). A task that changes a repeated pattern says "every <X> in files:" in its description. -->
<!-- Optional task field: " — no_claim: <what green does not prove>" after verify:, only when the test mocks an external seam (a model call, a cloud service, a database stand-in). The developer copies it into the report's Evidence section. -->
<!-- Optional header field, only when spec.md says **Behaviour-preserving**: yes — "· Parity: <cmd>". Plan T000 runs it at Base into verify/baseline.txt; a G### gate runs "<cmd> | diff verify/baseline.txt -". T000 also writes verify/parity-redcheck.txt (one raw character changed before any filter in <cmd>, the diff must exit non-zero) and its verify: names that file. -->

## Behaviors
| ID | Given / When / Then | Task | Proven by | Key |
|----|---------------------|------|-----------|-----|
| FR-01 (P0) | Given an entry, when I add a tag, then it persists and its chip shows | T002, T003 | test_tag_persists, test_chip_renders | tags/add-persists |
| FR-02 (P1) | Given a duplicate tag, when I add it, then the API returns 409 and the form says so | T004, T005 | test_duplicate_409, test_duplicate_message | tags/duplicate-refused |
| FR-03 (P2) | Given a duplicate-tag message, when it shows at 375px in dark mode, then it wraps and stays legible | CHK011 | human-verify | tags/duplicate-message-narrow |

<!-- Optional Key column: a stable key (<area>/<slug>) per behaviour. At archive, ${CLAUDE_PLUGIN_ROOT}/scripts/spec-merge folds the keyed rows into the living .specs/SPEC.md. "<key>, Replaces: <old-key>" replaces an earlier row (kept as "Previously"); "Retire: <old-key>" removes one; any other key already in SPEC.md is a collision and the merge refuses. A header field "· Spec-base: <hash>" (the hash spec-merge printed last) makes it refuse when SPEC.md has moved on. Rows with no Key are ignored. -->
<!-- Each Behaviors row opens with the spec's own FR-NN id. flow lint checks, when the Spec: file numbers FR-NN rows, that every FR has a row, every row cites a spec FR, and every row's Task cell names a task. -->

## Review focus
<!-- Optional, at most 5 lines: "<input class> — T###[, T###]". Lint errors on an unknown id; task-brief adds the line to each named task's brief and the Gates reviewer reads the whole section. -->
Tag names in Icelandic (þ, ð, æ) and 200-character names — T002, T003

## Phase 1 — A tag can be added and seen
Goal: a user adds a tag to an entry and sees its chip, with the database, API and UI all in play.
Independent test: `pytest tests/test_tags.py tests/test_ui.py` — a tag is added through the API and its chip renders from what was stored.
- [ ] T001 Migration and Tag model — files: db/schema.sql, src/models/tag.py — verify: `pytest tests/test_schema.py`
- [ ] T002 [P] POST tags persists (FR-01) — files: src/api/tags.py, tests/test_tags.py — verify: `pytest tests/test_tags.py::test_tag_persists` — no_claim: DB is sqlite in-memory; live Postgres not exercised — after: T001
- [ ] T003 [P] Tag chip renders stored tags (FR-01) — files: src/ui/chip.tsx, tests/test_ui.py — verify: `pytest tests/test_ui.py::test_chip_renders` — after: T001

## Phase 2 — Duplicates are rejected and shown
Goal: adding a tag that already exists is refused by the API and the form tells the user why.
Independent test: `pytest tests/test_dedupe.py tests/test_form.py` — a duplicate POST returns 409 and the form shows the message.
- [ ] T004 [P] Duplicate tag returns 409 (FR-02) — files: src/api/dedupe.py, tests/test_dedupe.py — verify: `pytest tests/test_dedupe.py` — after: T002
- [ ] T005 [P] Form shows the duplicate message (FR-02) — files: src/ui/form.tsx, tests/test_form.py — verify: `pytest tests/test_form.py::test_duplicate_message` — after: T004
- [ ] CHK011 human-verify the duplicate message at 375px in dark mode — files: src/ui/form.tsx — verify: human: user says the message wraps and stays legible — after: T004, T005

## Gates
- [ ] G001 project gates clean — files: . — verify: `flow check --fix --since 4f2a91c`
- [ ] G002 branch review clean — files: . — verify: `flow pass`
- [ ] G003 verification evidence exists — files: . — verify: `test -s verify/`
