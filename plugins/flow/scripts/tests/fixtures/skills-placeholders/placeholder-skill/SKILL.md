---
name: placeholder-skill
description: fixture skill demonstrating skills-lint's C16 placeholder skip and fenced-reference skip, alongside one genuine dead reference that must still be reported.
---

# placeholder-skill

These references are single-character or X/Y/foo/bar stems and must never
be reported as MISSING, even though none of these files exist:

- `references/a.md`
- `references/X.md`
- `references/foo.md`
- `references/bar.md`

This reference lives inside a fenced code block and must never be
reported as MISSING, even though the file does not exist:

```text
references/fenced-ghost.md
```

This reference is a genuine dead reference and must still be reported:
`scripts/deploy-staging.sh`
