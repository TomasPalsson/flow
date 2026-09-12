# Generation Quality Bar

Load this reference during Phase 4 (Generation) to produce artifacts that aren't slop.

---

## The Core Formula

**Good Skill = Expert Knowledge − What Claude Already Knows**

An artifact with zero knowledge delta is worse than no artifact — it occupies tokens without changing behavior. Every paragraph must earn its tokens.

**The test:** Would Claude do this correctly without being told? If yes, don't write it.

---

## The Description Field — Highest-Leverage Component

The description is the ONLY field Claude reads before deciding whether to load the artifact. A weak description = the artifact never activates, silently.

### Required description structure

A description must answer 3 questions:
1. **WHAT** does this artifact do? (one sentence)
2. **WHEN** should it trigger? (3-5 explicit scenarios)
3. **KEYWORDS** that activate it? (the specific vocabulary the user uses)

### Trigger word patterns

**Pattern 1 — Scenario list:**
```yaml
description: "... Use when: (1) user asks to add new component, (2) user says /flow:next, (3) user wants to implement new behavior, (4) user mentions TDD, (5) resuming feature branch."
```

**Pattern 2 — Keyword cluster:**
```yaml
description: "... Trigger words: deploy, ship, release, staging, production, rollout, rollback."
```

**Pattern 3 — Anti-trigger scoping:**
```yaml
description: "... Do NOT use for: bug fixes (use /fix), doc updates, config-only changes, or refactoring without new behavior."
```

**Pattern 4 — WHENEVER escalation (for must-not-miss triggers):**
```yaml
description: "... Use WHENEVER the user asks to implement, build, or create new functionality."
```

### The trigger word problem

Generic descriptions are semantically accurate but keyword-sparse. "Helps with feature development" will NOT fire when user says "let's add a new endpoint." The description must include the specific vocabulary users actually use, not a semantic summary.

**Rule:** The description should read slightly like SEO text — include the keywords, not just an accurate summary.

---

## Minimum Quality Bar Per Type

### Skill
- **Knowledge delta > 0**: at least one non-obvious anti-pattern, trade-off, or decision framework. E:A:R ratio > 70% Expert.
- **Description triggers correctly**: WHAT + WHEN (scenarios) + KEYWORDS.
- **No filler**: no "Getting Started", no "What is X", no "Best Practices" sections.
- **Correct size for pattern**: Mindset ~50, Navigation ~30, Philosophy ~150, Process ~200, Tool ~300. Over 500 = progressive disclosure failure.

### Slash Command / Skill-Command
- Clear argument spec (what it takes, not just what it does)
- Bounded scope (one verb — no "and")
- Actionable output format (user knows what to expect)
- Non-ambiguous trigger (name unambiguously maps to the one thing)

### Subagent
- Explicit behavioral role ("executing a code review workflow" not "you are a senior engineer")
- Allowed tools enumerated with **only tools that actually exist** (Read, Write, Edit, Bash, Glob, Grep, Agent, Task, WebSearch, WebFetch)
- Output format specified (artifact + location)
- Scope boundary (what it does NOT do)
- Stop condition (when is the agent done?)

### Hook
- Clear trigger (which event, which matcher regex)
- Exit code discipline (0 + JSON for decisions; 2 + stderr for blocking)
- No relative paths (use `"$CLAUDE_PROJECT_DIR"`)
- Check `stop_hook_active` if it's a Stop hook

---

## 9 Slop Patterns — Reject These

### Slop 1: Vague descriptor
```yaml
# BAD
description: "Helps with coding tasks and provides guidance"
description: "Use when working with databases"
```
Matches too broadly, either over-triggers or never triggers.

### Slop 2: Tutorial body
```markdown
## What is React?
React is a JavaScript library for building UIs...

## Getting Started
To install React, run: npm install react
```
Zero knowledge delta. Claude knows all of this.

### Slop 3: Kitchen-sink scope
```markdown
This skill helps you: review code, suggest improvements, check security,
optimize performance, add documentation, refactor, write tests, set up CI/CD.
```
If you'd need "and" to describe it, it's multiple skills.

### Slop 4: Redundant preamble
```markdown
You are Claude, an AI assistant made by Anthropic. This skill helps you...
```
Claude knows. Every word wastes context.

### Slop 5: Generic best practices section
```markdown
## Best Practices
- Write clean code
- Handle errors appropriately
- Use meaningful variable names
- Write tests
```
Not domain-specific. Not expert. Not earning tokens.

### Slop 6: Vague warning
```markdown
## Caution
- Be careful with database operations
- Handle edge cases properly
```
vs. expert:
```markdown
NEVER run migrations before `pg_dump` completes — incomplete backups
corrupt rollback paths. Check `pg_dump` exit code first.
```
Specificity + WHY = expert content.

### Slop 7: Missing concrete examples
Prose descriptions of "good error handling" vs. showing the exact diff between bad and good code.

### Slop 8: Trigger info in the body, not description
```markdown
---
description: "Performs code review"
---
## When to Use This Skill
Use when you want to review PRs, check quality, identify bugs...
```
The "When to Use" belongs in the DESCRIPTION. Claude never sees body content at the decision point.

### Slop 9: Hallucinated tool names
```yaml
tools: ["analyze_code", "run_linter", "check_security", "format_output"]
```
These don't exist. Only use: Read, Write, Edit, Bash, Glob, Grep, Agent, Task, WebSearch, WebFetch, TodoWrite, NotebookEdit.

---

## Scope Discipline Rules

1. **One primary verb.** If you need more than one, split the artifact.
2. **The "and" test.** If the name needs "and", it's multiple artifacts.
3. **Expertise boundary.** Different scopes = different expertise required. Combining = shallower treatment everywhere.
4. **Depth beats breadth.** "React Suspense boundary placement" > "React development."
5. **Cut when scope wants to expand.** Model bias is toward comprehensiveness — resist.

---

## Tailoring to the User's Repo

Generic skills have near-zero delta. Tailored skills (referencing user's actual stack) have high delta.

### The Tailoring Delta Rule

**A generated artifact must reference the user's actual stack at least 3 times** to justify existing over a generic template.

Include:
- Specific file paths from the repo (`see src/auth/session.ts:42`)
- Specific tool names actually in use (`we use pnpm, not npm`)
- Specific conventions that differ from ecosystem default
- Specific anti-patterns extracted from the user's own git history

### Context gathering required before generation

1. **Stack detection**: languages, frameworks, tools actually in codebase
2. **Convention extraction**: what does linter/tsconfig/pyproject actually say?
3. **Gotcha discovery**: comments, TODO/HACK/FIXME, git blame annotations
4. **Existing artifact audit**: what's already installed that might conflict?

---

## How to Pass skill-judge (if the generated artifact is a skill)

Target: ≥96/120 (80%) for production-ready.

### D1 Knowledge Delta (20 pts) — MAKE OR BREAK

To score 16-20: every paragraph encodes info Claude doesn't already have.
- Research the specific domain BEFORE writing
- Explicitly generate anti-patterns
- Generate decision trees for non-obvious choices

Automatic ≤5 (red flags): "What is X" sections, generic best practices, tutorials for standard operations.

### D2 Mindset + Procedures (15 pts)

Include BOTH "Before doing X, ask yourself..." frameworks AND domain-specific procedures.

### D3 Anti-Pattern Quality (15 pts)

Specific NEVER list with reasons. Every NEVER includes WHY. Vague warnings score 4-7 max.

### D4 Specification Compliance (15 pts)

Perfect frontmatter: `name` lowercase ≤64 chars, `description` ≥3 sentences with WHAT/WHEN/KEYWORDS. NO trigger info in body.

### D5 Progressive Disclosure (15 pts)

SKILL.md body < 500 lines (< 300 ideal). Heavy content → `references/`. Include "Do NOT Load" guidance.

### D6 Freedom Calibration (15 pts)

Creative tasks → high freedom (principles). Fragile operations (file formats, deployments, DB) → low freedom (exact commands). Test: "If the model makes a mistake, what's the consequence?"

### D7 Pattern Recognition (10 pts)

Classify the domain first: creative (Mindset), multi-scenario (Navigation), craft (Philosophy), complex process (Process), or precise operations (Tool). Target the right line count.

### D8 Practical Usability (15 pts)

Include decision trees, working examples (not pseudocode), "if X fails, do Y" fallbacks, realistic edge cases.

---

## Generation Anti-Patterns (AI-specific)

1. **Generating before researching** — produces training-distribution content (zero delta). Research MUST come first.
2. **Same template regardless of domain** — React/Rust/SQL get identical structure. Classify domain FIRST.
3. **Optimizing for length** — 500 lines ≠ thorough; skill-judge explicitly penalizes length without delta.
4. **Copying structure without quality** — producing correct sections with generic content.
5. **Scope inflation** — "Git workflows" balloons to include branches, merge, rebase, tags, CI. Cut instead of extending.
6. **Not testing description against scenarios** — run mental test: does this description match the 10 user requests where the skill should activate?
7. **Fabricating domain expertise** — plausible-sounding "NEVER" items from training data, not from real failure modes.

**The test:** Can every NEVER item in the generated artifact be explained with a specific failure scenario? If not, it's fabricated.

---

## Verification Checklist Before Writing Any Generated Artifact

- [ ] Description includes WHAT + WHEN (3-5 scenarios) + KEYWORDS
- [ ] Description has no trigger info missing that's in the body
- [ ] One primary verb (no "and" in name/description)
- [ ] References user's actual stack ≥3 times (file paths, tool names, conventions)
- [ ] No hallucinated tools (only real Claude Code tools)
- [ ] No "Best Practices" / "Getting Started" / "What is X" sections
- [ ] Every NEVER item has a specific WHY
- [ ] Size matches pattern (Process ~200, Tool ~300, etc.)
- [ ] Concrete examples, not prose descriptions
- [ ] Grounded in actual repo evidence (cited file:line)
