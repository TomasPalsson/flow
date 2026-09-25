---
name: skill-judge
description: Evaluate Agent Skill design quality against official specifications and best practices. Use when asked to evaluate a skill, review a SKILL.md file, audit a skill, score a skill, or judge whether a skill is well-designed. Not for editing an existing skill (use skill-improver) or creating a new one (use skill-forge).
---

# Skill Judge

Evaluate Agent Skills against the Agent Skills specification and Anthropic's skill-authoring guidance.

---

## Core Philosophy

### The Core Formula

> **Good Skill = Expert-only Knowledge − What Claude Already Knows**

A Skill's value is measured by its **knowledge delta** — the gap between what it provides and what the model already knows.

- **Expert-only knowledge**: Decision trees, trade-offs, edge cases, anti-patterns, domain-specific procedures — things that take years of experience to accumulate
- **What Claude already knows**: Basic concepts, standard library usage, common programming patterns, general best practices

### Three Types of Knowledge in Skills

When evaluating, categorize each section:

| Type | Definition | Treatment |
|------|------------|-----------|
| **Expert** | Claude genuinely doesn't know this | Must keep — this is the Skill's value |
| **Activation** | Claude knows but may not think of | Keep if brief — serves as reminder |
| **Redundant** | Claude definitely knows this | Should delete — wastes tokens |

To tell Redundant from Activation, ask: what would the agent do wrong without this line? If nothing, it is Redundant.

---

## Evaluation Dimensions (120 points total)

### D1: Knowledge Delta (20 points) — THE CORE DIMENSION

The most important dimension. Does the Skill add genuine expert knowledge?

| Score | Criteria |
|-------|----------|
| 0-5 | Explains basics Claude knows (what is X, how to write code, standard library tutorials) |
| 6-10 | Mixed: some expert knowledge diluted by obvious content |
| 11-15 | Mostly expert knowledge with minimal redundancy |
| 16-20 | Pure knowledge delta — every paragraph earns its tokens |

**Red flags** (instant score ≤5):
- "What is [basic concept]" sections
- Step-by-step tutorials for standard operations
- Explaining how to use common libraries
- Generic best practices ("write clean code", "handle errors")
- Definitions of industry-standard terms

**Green flags** must be specific to the skill's domain — "edge cases from real-world experience" and "NEVER X because Y" only earn credit for the knowledge inside them, not for matching this shape:
- Decision trees for non-obvious choices ("when X fails, try Y because Z")
- Trade-offs only an expert would know ("A is faster but B handles edge case C")
- A specific edge case, named, with what goes wrong
- A specific NEVER with a non-obvious reason
- A domain-specific procedure Claude wouldn't otherwise know

**The main test**: for each section, ask "what would the agent do wrong without this line?" A cold read asking "does Claude already know this?" is a guess — a model's own sense of what it knows is only partly calibrated, so treat that question as a starting point, not the verdict.

**Spot-check**: pick 2-3 factual claims that can be checked (a command's behavior, a library's default, a format rule) and verify them. A claim confirmed false caps D1 at 10, regardless of the rest of the score.

---

### D2: Mindset + Appropriate Procedures (15 points)

Does the Skill transfer expert **thinking patterns** along with **necessary domain-specific procedures**?

The difference between experts and novices isn't "knowing how to operate" — it's "how to think about the problem." But thinking patterns alone aren't enough when Claude lacks domain-specific procedural knowledge.

**Key distinction**:
| Type | Example | Value |
|------|---------|-------|
| **Thinking patterns** | "Front-load the riskiest unknown, not the easiest task" | High — shapes decision-making |
| **Domain-specific procedures** | "OOXML workflow: unpack → edit XML → validate → pack" | High — Claude may not know this |
| **Generic procedures** | "Step 1: Open file, Step 2: Edit, Step 3: Save" | Low — Claude already knows |

| Score | Criteria |
|-------|----------|
| 0-3 | Only generic procedures Claude already knows |
| 4-7 | Domain procedures present, but ordering or reasons unexplained |
| 8-11 | Good balance: thinking patterns + domain-specific workflows |
| 12-15 | Expert-level: shapes thinking AND provides procedures Claude wouldn't know |

A correct low-freedom checklist (see D6) can earn full marks on its own — it doesn't also need mindset prose. Generic "ask yourself" questions earn nothing; they're the kind of content D1 already red-flags.

**What counts as valuable procedures**:
- Workflows Claude hasn't been trained on (new tools, proprietary systems)
- Correct ordering that's non-obvious (e.g., "validate BEFORE packing, not after")
- Critical steps that are easy to miss (e.g., "MUST recalculate formulas after editing")
- Domain-specific sequences (e.g., MCP server's 4-phase development process)

**What counts as redundant procedures**:
- Generic file operations (open, read, write, save)
- Standard programming patterns (loops, conditionals, error handling)
- Common library usage that's well-documented

**A domain decision with its consequence looks like**:
```markdown
If the test passes before the fix, the test is wrong: rewrite it before touching the implementation. A green test on broken code proves nothing.
```

**Valuable domain procedures look like**:
```markdown
### Redlining Workflow (Claude wouldn't know this sequence)
1. Convert to markdown: `pandoc --track-changes=all`
2. Map text to XML: grep for text in document.xml
3. Implement changes in batches of 3-10
4. Pack and verify: check ALL changes were applied
```

**The test**: does it explain the decision behind non-obvious steps, and does it give Claude domain know-how it wouldn't otherwise have? A good Skill provides both when needed.

---

### D3: Anti-Pattern Quality (15 points)

Does the Skill name specific failure modes and how to avoid them?

**Why this matters**: Half of expert knowledge is knowing what NOT to do. A senior designer sees a purple gradient on a white background and instinctively cringes — "too AI-generated." This intuition comes from stepping on countless landmines, and Claude hasn't stepped on them, so a good Skill states them explicitly.

This dimension is format-neutral: a NEVER list, a table of failure modes, or inline "if X, do Y instead, because Z" all count the same. What matters is the content, not the shape.

| Score | Criteria |
|-------|----------|
| 0-3 | No failure modes named |
| 4-7 | Generic warnings ("avoid errors", "be careful", "consider edge cases") |
| 8-11 | Specific failure modes with some reasoning |
| 12-15 | Expert-grade anti-patterns with WHY — things only experience teaches |

Each entry needs a specific trigger and a real mechanism (what actually breaks, and why), plus what to do instead when that isn't obvious. Circular reasons ("because X is bad") and restatements of a rule the skill already states elsewhere earn nothing — they add words, not knowledge.

More than about 3 lines of all-caps emphasis (MANDATORY, MUST, CRITICAL) costs 2 points. Emphasis on many lines dilutes all of it and can over-trigger on current Claude models — reserve it for the one rule that testing shows actually gets skipped.

**Expert anti-patterns** (specific trigger + real mechanism):
```markdown
NEVER use generic AI-generated aesthetics like:
- Overused font families (Inter, Roboto, Arial) — reads as "unstyled default," not a choice
- Purple gradients on white backgrounds — the single most common AI-generated tell, because generation models converge on it as a safe default
- Default border-radius on everything — reads as templated rather than designed
```

**Weak anti-patterns** (vague, no reasoning): "Avoid making mistakes. Be careful with edge cases. Don't write bad code."

**The test**: would an expert read the entry and say "yes, I learned this the hard way"? Or would they say "this is obvious to everyone" or "this just restates the rule above"?

---

### D4: Specification Compliance — Especially Description (15 points)

Does the Skill follow official format requirements? **Special focus on description quality.**

| Score | Criteria |
|-------|----------|
| 0-5 | Missing frontmatter or invalid format |
| 6-10 | Has frontmatter but description is vague or incomplete |
| 11-13 | Valid frontmatter, description has WHAT but weak on WHEN |
| 14-15 | Perfect: WHAT and WHEN in plain wording, using the terms users actually say, and neighbouring skills named where they exist |

**Frontmatter requirements**:
- `name`: lowercase, alphanumeric + hyphens only, ≤64 characters
- `description`: **THE MOST CRITICAL FIELD** — determines if skill gets used at all

---

A poor description costs the most: a Skill with perfect content but a poor description is never activated, so this field gets special weight in the score.

**Description must answer WHAT and WHEN**, and may naturally include searchable keywords (file extensions, domain terms):

**Good**: "Create, edit, and analyze .docx files. Use when working with Word documents, tracked changes, or professional document formatting."

**Poor**: "A helpful skill for various tasks" — no WHAT, no WHEN; the Agent has no idea when to activate it.

---

**Description quality checklist**:
- [ ] Lists specific capabilities (not just "helps with X")
- [ ] Includes explicit trigger scenarios ("Use when...", "When user asks for...")
- [ ] Contains searchable keywords (file extensions, domain terms, action verbs)
- [ ] Specific enough that Agent knows EXACTLY when to use it
- [ ] Says when it applies, and names a neighbouring skill for nearby requests when one exists (Not for X, use Y)
- [ ] Meets the hard limits, checked in Step 0: 1-1024 characters, third person, no `<` or `>`

Keyword stuffing and "MUST be used whenever" phrasing add no points on their own — what counts is whether the description actually distinguishes this skill's territory. When a trigger-eval result is available (a measured trigger rate), it is the strongest evidence for this dimension; use it over a cold read.

---

### D5: Progressive Disclosure (15 points)

Does the Skill implement proper content layering?

Skill loading has three layers:
```
Layer 1: Metadata (always in memory)
         Only name + description
         ~100 tokens per skill

Layer 2: SKILL.md Body (loaded after triggering)
         Detailed guidelines, code examples, decision trees
         Ideal: < 500 lines

Layer 3: Resources (loaded on demand)
         scripts/, references/, assets/
         No limit
```

| Score | Criteria |
|-------|----------|
| 0-5 | Everything dumped in SKILL.md (>500 lines, no structure) |
| 6-10 | Has references but unclear when to load them |
| 11-13 | Load triggers sit at the step that needs them |
| 14-15 | Load triggers sit at the step that needs them, plus when-not-to-load guidance (no literal "Do NOT Load" string required) |

**For Skills WITH references directory**, check Loading Trigger Quality:

| Trigger Quality | Characteristics |
|-----------------|-----------------|
| Poor | References listed at end, no loading guidance |
| Mediocre | Some triggers but not embedded in workflow |
| Good | Load triggers embedded in workflow steps |
| Excellent | Scenario detection + conditional triggers + when-not-to-load guidance |

Also check, using Step 0's results: references stay one level deep (a reference file doesn't itself link to further references), reference files over 300 lines have a table of contents, and every referenced file actually exists.

**Good loading trigger** (a calm conditional, embedded in workflow):
```markdown
### Editing Tracked Changes

Before editing tracked changes, read [`redlining.md`](references/redlining.md)
in full; the ordering rules are at the end. Skip it for new documents.
```

**Bad loading trigger** (just listed):
```markdown
## References
- docx-js.md - for creating documents
- ooxml.md - for editing
- redlining.md - for tracking changes
```

**For simple Skills** (no references, <100 lines): Score based on conciseness and self-containment.

---

### D6: Freedom Calibration (15 points)

Is the level of specificity appropriate for the task?

Match specificity to how fragile the task is and how much it varies. Judge this per step, not once for the whole skill — a single skill can mix a high-freedom design step with a low-freedom file-write step, and each should be scored on its own terms.

| Score | Criteria |
|-------|----------|
| 0-5 | Severely mismatched (rigid scripts for creative tasks, vague for fragile ops) |
| 6-10 | Partially appropriate, some mismatches |
| 11-13 | Good calibration for most steps |
| 14-15 | Perfect freedom calibration across every step |

**The freedom spectrum**:

| Task Type | Should Have | Why | Example Skill |
|-----------|-------------|-----|---------------|
| Creative/Design | High freedom | Multiple valid approaches, differentiation is value | frontend-design |
| Code review | Medium freedom | Principles exist but judgment required | code-review |
| File format operations | Low freedom | One wrong byte corrupts file, consistency critical | docx, xlsx, pdf |

**High freedom** (text-based instructions):
```markdown
Commit to a BOLD aesthetic direction. Pick an extreme: brutally minimal, maximalist chaos, retro-futuristic, organic natural...
```

**Medium freedom** (pseudocode or parameterized):
```markdown
Review priority:
1. Security vulnerabilities (must fix)
2. Logic errors (must fix)
3. Performance issues (should fix)
4. Maintainability (optional)
```

**Low freedom** (an exact command, script, or validator, not prose):
```markdown
Run `scripts/create-doc.py --title "X" --author "Y"`. The script validates its own output; a non-zero exit means the document is malformed.
```

**The test**: Ask "if Agent makes a mistake at this step, what's the consequence, and how much does the right approach vary run to run?"
- High consequence, low variability → low freedom, backed by a command or script
- Low consequence, high variability → high freedom

---

### D7: Pattern Recognition (10 points)

Does the Skill's structure fit the shape of its task?

Five recurring shapes show up across skills:

| Pattern | Key Characteristics | Example | When to Use |
|---------|---------------------|---------|-------------|
| **Mindset** | Thinking > technique, strong NEVER list, high freedom | frontend-design | Creative tasks requiring taste |
| **Navigation** | Minimal SKILL.md, routes to sub-files | internal-comms | Multiple distinct scenarios |
| **Philosophy** | Two-step: Philosophy → Express, emphasizes craft | canvas-design | Art/creation requiring originality |
| **Process** | Phased workflow, checkpoints, medium freedom | mcp-builder | Complex multi-step projects |
| **Tool** | Decision trees, code examples, low freedom | docx, pdf, xlsx | Precise operations on specific formats |

| Score | Criteria |
|-------|----------|
| 0-3 | No recognizable pattern, chaotic structure |
| 4-6 | Partially follows a pattern with significant deviations |
| 7-8 | Clear pattern with minor deviations |
| 9-10 | Masterful application of appropriate pattern |

Judge the structure itself — ignore any label the skill applies to itself; a self-declared "Pattern: Process" heading proves nothing on its own.

**Pattern selection guide**:

| Your Task Characteristics | Recommended Pattern |
|---------------------------|---------------------|
| Needs taste and creativity | Mindset |
| Needs originality and craft quality | Philosophy |
| Has multiple distinct sub-scenarios | Navigation |
| Complex multi-step project | Process |
| Precise operations on specific format | Tool |

---

### D8: Practical Usability (15 points)

Can an Agent actually use this Skill effectively?

| Score | Criteria |
|-------|----------|
| 0-5 | Confusing, incomplete, contradictory, or untested guidance |
| 6-10 | Usable but with noticeable gaps |
| 11-13 | Clear guidance for common cases |
| 14-15 | Clear guidance for the cases the skill will realistically meet, plus a way to check the result (a test, validator, or done-check) |

**Check for**:
- **Decision trees**: For multi-path scenarios, is there clear guidance on which path to take?
- **Code examples**: Do they actually work? Or are they pseudocode that breaks?
- **Fallbacks**: Do they name a realistic failure, or are they speculative "just in case" coverage? Only the named-failure kind counts.
- **A done-check**: Can the agent tell, mechanically, whether it finished — a test, a validator, an exit code?
- **Actionability**: Can Agent immediately act, or needs to figure things out?

Dead references or broken code that Step 0 found cost D8 points on top of the pre-check cap — a skill pointing at a file that doesn't exist isn't usable, whatever else it gets right.

**Good usability** (decision tree + fallback):
```markdown
| Task | Primary Tool | Fallback | When to Use Fallback |
|------|-------------|----------|----------------------|
| Read text | pdftotext | PyMuPDF | Need layout info |
| Extract tables | camelot-py | tabula-py | camelot fails |

**Common issues**:
- Scanned PDF: pdftotext returns blank → Use OCR first
- Encrypted PDF: Permission error → Use PyMuPDF with password
```

**Poor usability** (vague): "Use appropriate tools for PDF processing. Handle errors properly. Consider edge cases."

---

## NEVER Do When Evaluating

- **NEVER** give high scores just because it "looks professional" or is well-formatted — formatting isn't knowledge
- **NEVER** ignore token waste — every redundant paragraph costs context budget the skill could spend on real knowledge
- **NEVER** let length impress you — a 43-line Skill can outperform a 500-line Skill
- **NEVER** skip mentally testing the decision trees — trace them and see if they actually lead to correct choices
- **NEVER** forgive explaining basics with "but it provides helpful context" — if Claude already knows it, the context doesn't help
- **NEVER** overlook missing failure modes — if nothing tells Claude what not to do, that's a significant gap, whatever form the warning takes
- **NEVER** assume all procedures are valuable — distinguish domain-specific from generic
- **NEVER** undervalue the description field — a skill with a poor description never gets used, however good its body is
- **NEVER** put "when to use" info only in the body — the Agent only sees the description before loading
- Don't count NEVER entries or ask-yourself blocks; count the knowledge in them

---

## Evaluation Protocol

### Step 0: Deterministic Pre-Checks

Run these checks before scoring. They are pass/fail, not judgment calls.

(a) Reference resolution: run `flow skills-lint <skill-dir>`. Any `MISSING` line is a failure. If the `flow` CLI is not installed, check every path the skill references with `ls` instead.

(b) Frontmatter: `name` matches `^[a-z0-9]+(-[a-z0-9]+)*$` and is 64 characters or fewer. `description` is 1-1024 characters, written in the third person, and contains no `<` or `>`.

A failed pre-check is a Critical Issue and caps the total at 95 — one below skill-forge's 96 stop line. The report shows both the raw total and the capped total.

### Step 1: First Pass — Knowledge Delta Scan

Read SKILL.md completely and mark each section [E] Expert, [A] Activation, or [R] Redundant (see Core Philosophy's Three Types table). Use D1's main test — what would the agent do wrong without this line — not a cold "does Claude already know this?" read.

Calculate rough ratio: E:A:R
- Good Skill: >70% Expert, <20% Activation, <10% Redundant
- Mediocre Skill: 40-70% Expert, high Activation
- Bad Skill: <40% Expert, high Redundant

### Step 2: Structure Analysis

```
[ ] Count total lines in SKILL.md
[ ] List all reference files and their sizes
[ ] Identify which pattern the Skill follows
[ ] Check for loading triggers (if references exist)
```

### Step 3: Score Each Dimension

For each of the 8 dimensions:
1. Find specific evidence (quote relevant lines)
2. Assign score with one-line justification
3. Note specific improvements if score < max

### Step 4: Calculate Total & Grade

```
Total = D1 + D2 + D3 + D4 + D5 + D6 + D7 + D8
Max = 120 points
```

**Grade Scale** (percentage-based):
| Grade | Percentage | Meaning |
|-------|------------|---------|
| A | 90%+ (108+) | Excellent — production-ready expert Skill |
| B | 80-89% (96-107) | Good — minor improvements needed |
| C | 70-79% (84-95) | Adequate — clear improvement path |
| D | 60-69% (72-83) | Below Average — significant issues |
| F | <60% (<72) | Poor — needs fundamental redesign |

A single judge run varies by up to about ±5 points on a padded skill; treat a total within 5 points of a gate (such as skill-forge's 96) as borderline, not a clean pass or fail.

### Step 5: Generate Report

When the Critical Issues section names a failure pattern, read `references/failure-patterns.md` first to cite it accurately.

```markdown
# Skill Evaluation Report: [Skill Name]

## Summary
- **Pre-checks**: PASS | FAIL — <details>
- **Raw Total**: X/120 (X%)
- **Capped Total**: X/120 (X%) — equals Raw Total unless pre-checks failed
- **Grade**: [A/B/C/D/F]
- **Pattern**: [Mindset/Navigation/Philosophy/Process/Tool]
- **Knowledge Ratio**: E:A:R = X:Y:Z
- **Behavioral evidence**: <prompts + outcome> | NONE
- **Verdict**: [One sentence assessment]

## Dimension Scores

| Dimension | Score | Max | Notes |
|-----------|-------|-----|-------|
| D1: Knowledge Delta | X | 20 | |
| D2: Mindset + Appropriate Procedures | X | 15 | |
| D3: Anti-Pattern Quality | X | 15 | |
| D4: Specification Compliance | X | 15 | |
| D5: Progressive Disclosure | X | 15 | |
| D6: Freedom Calibration | X | 15 | |
| D7: Pattern Recognition | X | 10 | |
| D8: Practical Usability | X | 15 | |

## Critical Issues
[List must-fix problems that significantly impact the Skill's effectiveness]

## Top 3 Improvements
1. [Highest impact improvement with specific guidance]
2. [Second priority improvement]
3. [Third priority improvement]

## Detailed Analysis
[For each dimension scoring below 80%, provide:
- What's missing or problematic
- Specific examples from the Skill
- Concrete suggestions for improvement]
```

---

## The Meta-Question

When evaluating any Skill, always return to this fundamental question:

> **"Would an expert in this domain, looking at this Skill, say:**
> **'Yes, this captures knowledge that took me years to learn'?"**

If the answer is yes → the Skill has genuine value.
If the answer is no → it's compressing what Claude already knows.

The best Skills are **compressed expert brains** — they take a designer's 10 years of aesthetic accumulation and compress it into 43 lines, or a document expert's operational experience into a 200-line decision tree.

What gets compressed must be things Claude doesn't have. Otherwise, it's garbage compression.
