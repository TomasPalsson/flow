#!/usr/bin/env bash
# What a perfect /flow:spec --unattended leaves on disk: spec.md beside the
# PREP.md carrying every decision (streaming only as a non-goal), and a
# lint-clean, unapproved TASKS.md with a real Base.
set -euo pipefail
DIR=.specs/001-order-csv-export
BASE=$(git rev-parse --short HEAD)
cat >"$DIR/spec.md" <<'MD'
# Spec: Order CSV export

**Created**: 2026-09-29 · **Route**: dispatch

## TL;DR

**Problem**: Support staff cannot get orders out of ordersbook and into a spreadsheet.

**Solution**: `ordersbook export <orders.json> --out <file.csv>` writes the orders as RFC 4180 CSV.

**Who it's for**: Support staff.

**MVP cut line**: everything tagged `MUST` in §4.1 ships.

**Key decision**: D-03: an export holds at most 10,000 rows; a larger one is refused and writes nothing.

## 2. Scope

### 2.1 In scope

- D-01 The export is RFC 4180 CSV: comma delimiter, CRLF line endings, a field containing a comma, a double quote or a newline is quoted, and an embedded double quote is doubled.
- D-02 No new dependencies; the standard library only.
- D-03 An export holds at most 10,000 rows. A larger export is refused with a clear error and writes nothing.
- D-04 Columns are id, customer, total, status, in that order, with a header row; total is dollars with two decimals (12.50), not cents.
- D-05 The entry point is `ordersbook export <orders.json> --out <file.csv>`, with an optional `--status <s>` filter.

### 2.2 Non-goals

- No streaming or chunked export for more than 10,000 rows: out of scope, the refusal in D-03 is the whole answer.
- No XLSX, JSON or PDF output.
- No scheduled or emailed exports.

## 4. Requirements

### 4.1 Functional

| ID | Level | Requirement |
|----|-------|-------------|
| FR-001 | MUST | The file is RFC 4180 CSV with CRLF line endings (D-01). |
| FR-002 | MUST | The total column reuses the existing `cents_to_decimal` helper (D-04). |
| FR-003 | MUST | More than 10,000 orders is refused and no file is written (D-03). |
| FR-004 | MUST | `ordersbook export <orders.json> --out <file.csv> [--status <s>]` (D-05). |

## 6. Verify

- `ordersbook export sample.json --out out.csv` on a customer named `Smith, "Bob"`: one row, one cell for the name; the unit suite is green.

## 7. Assumptions

- Support staff open the file in Excel or Numbers. Confidence: medium.
- Real order files stay well under 2,000 rows today. Confidence: low.
- An empty result writes a header-only file. Confidence: medium.
MD
cat >"$DIR/TASKS.md" <<MD
# Tasks — Order CSV export
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a customer named Smith, "Bob", when exported, then the row has one quoted cell | T001 | test_quotes_comma_and_quote |
| B2 (P0) | Given 10,001 orders, when exported, then it is refused and nothing is written | T002 | test_refuses_over_cap |
| B3 (P0) | Given orders.json, when I run export --out, then the CSV file exists | T003 | test_export_command |

## Phase 1 — The file format
Goal: orders can be written as RFC 4180 CSV and an oversized export is refused.
Independent test: \`python3 -m unittest tests.test_export\` — green with the CLI untouched.
- [ ] T001 RFC 4180 writer — files: src/export.py, tests/test_export.py — verify: \`python3 -m unittest tests.test_export\`
- [ ] T002 Refuse more than 10,000 rows — files: src/export.py, tests/test_export.py — verify: \`python3 -m unittest tests.test_export\` — after: T001

## Phase 2 — The command
Goal: the support team can run the export from the command line.
Independent test: \`python3 -m unittest tests.test_cli_export\` — green.
- [ ] T003 export subcommand — files: src/cli.py, tests/test_cli_export.py — verify: \`python3 -m unittest tests.test_cli_export\` — after: T002

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
- [ ] G003 verification evidence exists — files: . — verify: \`test -s verify/\`
MD
