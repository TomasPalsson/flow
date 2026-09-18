# PREP.md template

No YAML frontmatter — metadata is the second line. A seed from
`/flow:develop-idea` adds a third, `Seed: "<the user's own first words>" —
user, via /flow:develop-idea`; keep it on every rewrite. Each section's job:

- **Decisions** — locked; the spec copies these verbatim, never re-asks.
- **Not this** — becomes the spec's §2.2 Non-goals verbatim; build must not
  touch it.
- **Discretion** — the spec or the build decides alone here; never asks.
- **Assumptions** — stated by prep from exploring the tree; the user only
  confirms or corrects them.
- **Verify** — the one end-to-end check the user accepts as proof this
  shipped.
- **Open** — ≤3 lines; more than that is the split signal, not a bigger spec.

## Empty template

```markdown
# Prep — <title>
Gathered: YYYY-MM-DD · Questions: N of 12 · Route: spike|bounded|oneshot|dispatch · Status: interviewing|ready for spec|done in chat

## Decisions
- D-01 <text> — user, Q<n>
## Not this
- <text>
## Discretion
- <text>
## Assumptions
- A-01 <text> — evidence: <path:line or none> — confidence: high|medium|low — confirmed Q<n>|corrected Q<n>|unconfirmed
## Verify
- <text>
## Open
- Q: <question> → deferred to spec
```

## Filled example (entry tagging, 7 of 12 questions, dispatch route)

```markdown
# Prep — Entry tagging
Gathered: 2026-09-07 · Questions: 7 of 12 · Route: dispatch · Status: ready for spec

## Decisions
- D-01 Tags are per-entry, free text, max 5. — user, Q2
- D-02 Duplicate tag on an entry returns 409, not a silent dedupe. — user, Q4
- D-03 Tag length capped at 24 characters. — user, Q5
## Not this
- No tag hierarchy. No server-side tag search. No admin UI for tag management.
## Discretion
- Empty-state copy when an entry has no tags.
- Chip ordering within the tag list.
- Layout below a 375px viewport width.
## Assumptions
- A-01 Postgres already hosts entries — evidence: db/schema.sql:12 — confidence: high — confirmed Q1
- A-02 ~1k tags per user is the realistic ceiling — evidence: none — confidence: low — corrected Q3 (user: "no idea, assume 10k")
## Verify
- Tag an entry at a 375px viewport, reload the page, the chip is still there; `pytest tests/test_tags.py` is green.
## Open
- Q: rename vs delete-and-recreate for an edited tag? → deferred to spec
```
