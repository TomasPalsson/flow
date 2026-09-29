#!/usr/bin/env bash
# What a perfect drafting turn leaves on disk: a lint-clean, UNAPPROVED
# TASKS.md that covers every acceptance criterion; no source edit.
set -euo pipefail
DIR=.specs/001-low-stock-report
BASE=$(git rev-parse --short HEAD)
cat >"$DIR/TASKS.md" <<MD
# Tasks — Low-stock report
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given items with qty 9, 2, 4 and threshold 5, when low_stock runs, then it returns the qty 2 and 4 items, lowest first (AC-1) | T001 | test_low_stock_sorted |
| B2 (P0) | Given no override, when the threshold is read, then it is 5; given STOCKROOM_LOW_STOCK=abc, then ConfigError names the variable (AC-2) | T002 | test_threshold_default_and_override |
| B3 (P0) | Given an item with qty 0, when the report rows are built, then its status is OUT and the others are LOW (AC-3) | T003 | test_status_out_and_low |
| B4 (P0) | Given a data file, when I run low-stock --threshold 3, then the table lists only items below 3 (AC-4) | T004 | test_low_stock_command |
| B5 (P1) | Given the longest product name in the data, when the table prints in 80 columns, then the columns line up without wrapping (AC-5) | CHK001 | human: columns line up |

## Phase 1 — Report logic
Goal: the stock logic can say which items are low, how low, and at what threshold.
Independent test: \`python3 -m unittest tests.test_reports tests.test_config\` — green with the CLI untouched.
- [ ] T001 [P] low_stock returns items under the threshold, sorted (AC-1) — files: src/reports.py, tests/test_reports.py — verify: \`python3 -m unittest tests.test_reports\`
- [ ] T002 [P] threshold default and STOCKROOM_LOW_STOCK override (AC-2) — files: src/config.py, tests/test_config.py — verify: \`python3 -m unittest tests.test_config\`
- [ ] T003 OUT/LOW status per row (AC-3) — files: src/reports.py, tests/test_reports.py — verify: \`python3 -m unittest tests.test_reports\` — after: T001

## Phase 2 — The command
Goal: a warehouse lead can run one command and read the short items.
Independent test: \`python3 -m unittest tests.test_cli\` — green.
- [ ] T004 low-stock subcommand with --threshold (AC-4) — files: src/cli.py, tests/test_cli.py — verify: \`python3 -m unittest tests.test_cli\` — after: T002, T003
- [ ] CHK001 human-verify the table lines up in an 80-column terminal with the longest product name (AC-5) — files: src/cli.py — verify: human: the columns line up without wrapping at 80 columns

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
- [ ] G003 verification evidence exists — files: . — verify: \`test -s verify/\`
MD
