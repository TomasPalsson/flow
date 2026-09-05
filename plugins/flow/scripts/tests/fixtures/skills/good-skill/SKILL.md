---
name: good-skill
description: fixture skill with only resolvable references, for skills-lint tests.
---

# good-skill

A tiny fixture skill whose references all resolve.

- Bare relative form: `references/a.md`
- Dotted skills-dir form: `.claude/skills/good-skill/references/a.md`
- Home-tilde form: `~/.claude/skills/good-skill/SKILL.md`

These placeholder forms must be ignored by skills-lint, not treated as
dead references: `.claude/skills/<name>/references/NNN.md` and
`references/<some-var>.md`.
