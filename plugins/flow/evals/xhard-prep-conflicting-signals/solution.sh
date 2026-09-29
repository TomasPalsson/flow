#!/usr/bin/env bash
# What a perfect first turn leaves on disk: a PREP.md with findings from the
# tree, still interviewing, and nothing else.
set -euo pipefail
mkdir -p .specs/001-order-exports
cat >.specs/001-order-exports/PREP.md <<'MD'
# Prep — Order exports
Gathered: 2026-09-29 · Questions: 0 of 12 · Route: dispatch · Status: interviewing
Seed: "people keep asking for exports, do something about it" — user, via /flow:prep

## Decisions
## Not this
## Discretion
## Assumptions
- A-01 A CSV exporter is half-built and not wired into the CLI — evidence: src/export/csv_export.py:1 — confidence: high — unconfirmed
- A-02 An xlsx exporter is parked because it needs openpyxl — evidence: src/export/xlsx_export.py:5 — confidence: high — unconfirmed
- A-03 New dependencies are off the table — evidence: README.md:9 — confidence: high — unconfirmed
- A-04 "Exports" most likely means the order list as CSV for the support team — evidence: none — confidence: medium — unconfirmed
## Verify
## Open
MD
