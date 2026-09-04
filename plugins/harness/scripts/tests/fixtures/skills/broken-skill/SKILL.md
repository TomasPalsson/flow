---
name: broken-skill
description: fixture skill with a dead reference and a tool mention, for skills-lint tests.
---

# broken-skill

This skill references a file that does not exist:
`references/does-not-exist.md`

It also checks for a tool before using it:

```bash
if command -v better-plan >/dev/null 2>&1; then
  better-plan --help
fi
```
