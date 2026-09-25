# Pattern-Switching Recipes

Load this when you need to CONVERT a skill from one pattern to another. The 5 official patterns have different structural signatures; switching between them is a surgical rewrite, not reformatting.

---

## The 5 Patterns (Quick Reference)

| Pattern | Lines | Signal | Failure when misused |
|---|---|---|---|
| **Mindset** | ~50 | Pure thinking injection, high freedom, taste tasks | Catastrophic for fragile ops |
| **Navigation** | ~30 | Routes to sub-files, minimal body | Wasteful when scenarios aren't orthogonal |
| **Philosophy** | ~150 | "Why hard" + craft framework, some decision logic | Drifts to Tutorial when steps replace judgment |
| **Process** | ~200 | Phases + stage gates, medium freedom | Becomes Checkbox Procedure with generic steps |
| **Tool** | ~300 | Decision trees + exact code, low freedom | Explodes into Dump without references/ |

---

## Mismatch Detection

Diagnostic questions to surface the wrong pattern:

**"If the agent makes a mistake, what's the consequence?"**
- Corrupted/irreversible → Tool (low freedom)
- Wrong procedural outcome → Process
- Ugly/ineffective/bland → Mindset or Philosophy (high freedom)

**"If I removed all step-by-step procedures, would anything valuable remain?"**
- Yes (frameworks, anti-patterns, principles remain) → Mindset or Philosophy being run as Process
- No (nothing left) → Process may be correct

**"Are the multiple sub-scenarios actually orthogonal, or just variants?"**
- Orthogonal (truly different approaches) → Navigation appropriate
- Variants (same approach, different inputs) → Process or Tool is better

**"Does this skill need judgment or compliance?"**
- Compliance (match exact format/API) → Tool
- Judgment (creative decisions within constraints) → Philosophy
- Taste (no objectively correct output) → Mindset

---

## Conversion Recipes

### Process → Philosophy

**When**: The skill has phases but the phases are generic or the real value is WHY each phase matters, not HOW to execute it.

**Moves**:
1. Keep the strongest anti-patterns and thinking frameworks
2. Replace generic phase steps with the domain's decision at each phase and why it matters
3. Remove checkpoint/gate logic that was there for pure orchestration
4. Lead with "what makes this domain hard" / "what the model gets wrong by default"
5. Keep 1-2 reference files if deep sub-topics need them

**Example**: A skill with "Phase 1: Read the code. Phase 2: Identify patterns. Phase 3: Write the summary" is Process-patterned but adds nothing Claude doesn't already do. The Philosophy version leads with "What distinguishes a useful code summary from a checklist of what's present" and provides principles, not steps.

---

### Process → Navigation

**When**: The skill covers 3+ genuinely distinct scenarios that share only a name.

**Moves**:
1. Create a routing table at the top (scenario detection → sub-file)
2. Extract each phase/scenario to its own references/ file
3. Shrink SKILL.md to ~30 lines (routing table + critical shared anti-patterns)
4. Add MANDATORY loading triggers: "For scenario A, read references/a.md"
5. Add "Do NOT Load" anti-triggers per path

**Example**: A 500-line skill covering "creating X, editing X, converting X, validating X" is better as Navigation + four reference files. The routing SKILL.md becomes 30 lines.

---

### Tool → Navigation

**When**: A massive Tool-pattern skill has become a Dump (>500 lines).

**Moves**:
1. Identify natural sub-domains (grouping of related operations)
2. Extract each sub-domain to its own references/ file
3. Create scenario-detection routing in SKILL.md
4. SKILL.md becomes: routing table + the MOST critical shared decision trees
5. MANDATORY load triggers for each sub-domain

**Example**: `gh-cli` (2187 lines) covering repos, issues, PRs, actions, releases, projects. Each could be its own references/ file; SKILL.md becomes routing. Token cost drops ~85% per activation.

---

### Philosophy → Process

**When**: The skill tries to convey principles but the domain has hard sequential dependencies the model keeps missing.

**Moves**:
1. Identify the sequence-dependent phases (where skipping breaks correctness)
2. Add phase gates / checkpoint logic
3. Move the "why this domain is hard" content to an opening summary
4. Keep anti-patterns as a concluding section
5. Expected length increase: 150 → 200 lines

**Warning**: If the content is genuinely about taste/craft, this conversion BREAKS the skill. Philosophy → Process is the right call only when hard ordering actually exists.

---

### Tool → Philosophy

**When**: A Tool-pattern skill handling a creative domain has over-specified itself into brittleness.

**Moves**:
1. Identify the prescriptive scripts — are they actually fragile, or did the author over-constrain?
2. Replace exact commands with principles + "if X fails, consider Y"
3. Move remaining genuinely fragile scripts to scripts/ directory
4. Dramatically increase freedom calibration
5. Expected length decrease: 300 → 150 lines

**Warning**: If the domain IS fragile (docx/pdf/xlsx operations), do NOT do this conversion.

---

### Mindset → Philosophy

**When**: A Mindset skill needs more concrete execution guidance but shouldn't lose its thinking framework.

**Moves**:
1. Keep the Mindset's core philosophical inversion at the top
2. Add a second section: craft framework with concrete decision principles
3. Anti-patterns become more specific (still about thinking, now with examples)
4. Expected length increase: 50 → 150 lines

---

### Philosophy → Mindset

**When**: A Philosophy skill has drifted into Tutorial territory, adding step-by-step content that waters down its principled stance.

**Moves**:
1. Delete all Tutorial-style procedural content
2. Keep the philosophical inversion
3. Tighten anti-patterns to 3-8 bullets
4. Expected length decrease: 150 → 50 lines

**The test**: Does the remaining content require judgment, not compliance? If it still reads like instructions, cut more.

---

## What to Preserve When Switching Patterns

Regardless of the direction, preserve:
- **Voice** — document it before switching; match in the new structure
- **Expert-grade anti-patterns** — they survive pattern changes
- **Knowledge delta content** — the genuinely expert-only insights
- **Description field** — unless the new pattern changes what the skill DOES

---

## What Gets Restructured

- **Section ordering** — each pattern has different attention priorities
- **Section naming** — pattern conventions differ (Phases vs Principles vs Scenarios)
- **Example density** — Tool needs working code, Mindset needs contrast pairs
- **Freedom calibration** — each pattern has a different freedom default
- **references/ structure** — Tool/Navigation need it, Mindset shouldn't have it

---

## Red Flags: Pattern Change Is NOT the Fix

Sometimes structural dissatisfaction isn't a pattern mismatch:

- If D1 is low AND pattern is correct → fix knowledge delta, not pattern
- If D4 (description) is bad AND pattern is correct → fix description, not pattern
- If anti-patterns are vague AND pattern is correct → sharpen anti-patterns, not pattern
- If the skill feels "off" but you can't name a specific dimension → probably voice problem, not pattern

**Pattern switching is the highest-regression improvement class.** Only do it when pattern mismatch is the genuine root cause.

---

## Post-Switch Validation

After any pattern switch, re-check ALL 8 skill-judge dimensions against the ORIGINAL, not just the targeted improvement:
- D1: Did knowledge delta survive?
- D2: Is mindset/procedures balance appropriate for new pattern?
- D3: Are anti-patterns still specific enough?
- D4: Does description still match what the new structure does?
- D5: Is progressive disclosure set up correctly for new pattern?
- D6: Is freedom calibrated to new pattern's defaults?
- D7: Does the new structure cleanly match pattern conventions?
- D8: Can an agent actually use the new structure?

If any dimension regressed by >2 points, the pattern switch may have been wrong.
