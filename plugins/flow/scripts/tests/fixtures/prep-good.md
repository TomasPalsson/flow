# Prep — Widget dispatch

Gathered: 2026-09-01 · Questions: 3 of 12 · Route: dispatch · Status: ready for spec

## Decisions
- D-01 Use SQLite for local cache — user, Q1
- D-02 Ship behind a feature flag — user, Q2

## Not this
- Does not support multi-tenant mode yet

## Discretion
- Log level defaults to info

## Assumptions
- A-01 The cache is single-writer — evidence: src/cache.ts:42 — confidence: high — confirmed Q3
- A-02 No external dependency needed — evidence: none — confidence: medium — unconfirmed

## Verify
- `npm test` passes with the new cache path exercised

Decoy fenced block a naive line-scanner would misparse as a real Open section:

```text
## Open
- Q: one? → deferred to spec
- Q: two? → deferred to spec
- Q: three? → deferred to spec
- Q: four? → deferred to spec
```

## Open
- Q: Should we cap cache size? → deferred to spec
