#!/usr/bin/env bash
# What a perfect first turn leaves on disk: a PREP.md that records the
# contradiction with path:line evidence, no decision about cancellation, and
# nothing else.
set -euo pipefail
mkdir -p .specs/001-partial-cancel-refund-email
cat >.specs/001-partial-cancel-refund-email/PREP.md <<'MD'
# Prep — Refund email on partial cancellation
Gathered: 2026-09-29 · Questions: 0 of 12 · Route: dispatch · Status: interviewing
Seed: "Send a refund email when a customer cancels part of an order" — user, via /flow:prep

## Decisions
## Not this
## Discretion
## Assumptions
- A-01 cancel_order cancels the whole order only; there is no per-line cancellation — evidence: src/orders.py:15 — confidence: high — unconfirmed
- A-02 The user said partial cancellation already exists; the code contradicts that — evidence: src/orders.py:16 — confidence: high — unconfirmed
## Verify
## Open
- Q: Is partial cancellation to be built as part of this, or did you mean something else? → asked
MD
