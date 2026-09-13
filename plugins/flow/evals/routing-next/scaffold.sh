#!/usr/bin/env bash
set -euo pipefail
mkdir -p src .specs/001-csv-export
cat >package.json <<'JSON'
{
  "name": "orders-app",
  "private": true,
  "version": "0.0.0"
}
JSON
cat >src/server.js <<'JS'
const express = require("express");
const app = express();

app.get("/orders", (req, res) => {
  res.json([]);
});

module.exports = app;
JS
cat >.specs/001-csv-export/spec.md <<'MD'
# Spec — CSV export

Requirement: `/orders` also exposes a CSV export so ops can pull orders into a
spreadsheet.
MD
cat >.specs/001-csv-export/TASKS.md <<'MD'
# Tasks — CSV export
Spec: spec.md · Design: none · Base: 4f2a91c · Route: bounded · Test: `npm test`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given orders, when GET /orders.csv, then a CSV downloads | T001 | test_csv_export |

## Phase 1 — CSV export
Goal: orders can be exported as CSV.
Independent test: `npm test` — green.
- [x] T001 CSV export endpoint — files: src/server.js — verify: `npm test`
- [ ] T002 Content-Disposition header names the file orders.csv — files: src/server.js — verify: `npm test`

## Gates
- [ ] G001 project gates clean — files: . — verify: `flow check --fix`
MD
printf '001-csv-export\n' >.specs/.current
