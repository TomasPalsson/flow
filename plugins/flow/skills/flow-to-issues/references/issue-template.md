# Issue file template

One file per issue at `<SPEC-DIR>/issues/<NN>-<slug>.md`. This is also the `--body-file` for `gh issue create`. Keep it self-contained: an agent picking up this issue should need nothing but this file + the linked spec.

```markdown
# <NN> — <user-capability title, phrased as observable behavior>

> Slice of [spec](../spec.md) · **Tag**: `AFK` | `HITL`

## What ships
<One sentence: the observable, demoable behavior the user gets when this merges. If you can't state it as user-visible behavior, this is a horizontal slice — re-slice it.>

## Tag rationale
- **AFK** → "No human decision required; spec fully specifies this."
- **HITL** → "Needs a human for: <the specific unmade decision — visual design / architecture fork / external credential / destructive action / unresolved [NEEDS CLARIFICATION]>."

## Depends on
- #<NN> — <title>   (omit / "none" for the walking skeleton)

## Spec trace
- Journey: <which journey + path: happy / error / edge>
- Requirements: FR-<n>, NFR-<n>  (the IDs this issue satisfies)

## Design trace  (omit this entire section if code-design.md does not exist for this spec)
- <the slice's `## Contract for this slice` block from code-design.md, or at minimum the code-design.md sections and contract types this issue implements>

## Acceptance criteria  (verbatim from the spec — do not invent)
- [ ] Given <context> When <action> Then <observable outcome>
- [ ] Given <invalid input> When <action> Then <error behavior>

## Out of scope
- <what a later slice handles — keeps this issue thin>
```

## Labels
- `afk` — agent can implement unattended
- `hitl` — needs a human checkpoint first

## index file (`<SPEC-DIR>/issues.md`)

| # | Title | Tag | depends-on | GitHub |
|---|---|---|---|---|
| 01 | User can create a draft entry end-to-end | AFK | — | <url or "local"> |
| 02 | User can add a title and see it persist | AFK | 01 | … |
```
