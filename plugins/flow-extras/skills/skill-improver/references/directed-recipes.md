# Directed Improvement Recipes

Canonical techniques for each type of user-requested improvement. Load this when the user makes a directed improvement request and you need the specific expert technique for that type.

---

## Recipe: "Make It Shorter" / "Reduce" / "Cut"

**Naive mistake**: Delete sentences arbitrarily from the longest sections.

**Expert technique**:
1. Knowledge-delta audit first — tag every section as Expert (E) / Activation (A) / Redundant (R)
2. Cut all R sections entirely
3. Compress A sections to one-line bullets
4. If still over budget, move long Expert content to `references/` rather than deleting
5. Target: SKILL.md body < 300 lines, knowledge ratio > 70% Expert

**Specific cuts that are almost always safe**:
- Opening paragraphs that re-explain the domain ("PDF is a format...") — always Redundant
- "Best practices" sections with generic advice — always Redundant
- Tutorial-style step-by-step for standard operations Claude already knows

**Preservation rules**:
- The WHY in anti-patterns is sacrosanct. Never cut WHY to save length.
- If uncertain whether content is Expert or Redundant, bias toward keeping it.

**Regression risk**: Removing Expert content (D1 drop), removing NEVER entries silently (D3 drop).

---

## Recipe: "Make It Longer" / "Add More" / "Feels Thin"

**Naive mistake**: Add filler — restating existing content, generic examples, importing tutorials.

**Expert technique**:
Diagnose which dimension is thin. "Longer" is a proxy for a specific gap:
1. No named failure modes? → Add real ones with mechanism and what to do instead (D3)
2. No decision trees? → Add them (D8)
3. No edge cases? → Add them (D8)
4. Description lacks scenarios? → Expand description (D4)
5. No domain decision with its consequence? → Add one (D2)

**The addition test**: "Would Claude do this correctly WITHOUT being told?" If yes, don't add. Only add content where the answer is no.

**Regression risk**: Pushing past body length budget (D5 drop), adding Redundant content (D1 drop).

---

## Recipe: "Improve the Description"

**Naive mistake**: Make description longer without adding precision. "Helps with X" → "Helps Claude to perform X tasks more effectively..." (same vagueness, more tokens).

**Expert technique**: WHAT / WHEN / KEYWORDS structure

Canonical pattern:
```
[Concise WHAT]. Use when: (1) [scenario 1], (2) [scenario 2], (3) [scenario 3].
Trigger phrases: [term1], [term2], [term3].
Do NOT use for: [adjacent intent 1], [adjacent intent 2].
```

**The pushy principle**: Claude under-triggers skills by default, so name concrete scenarios in plain "Use when: X, Y, Z" wording rather than a vague "Can be used for X". Avoid "Use WHENEVER" / "MUST activate" and keyword dumps — they cause false triggers against neighbouring skills. Let a trigger eval (10 requests that should trigger, 5 near-misses that should not) decide how broad to go, not the wording. Write in the third person, and keep the description to 1024 characters or fewer.

**Anti-trigger inclusion**: "Do NOT use for: [X]" prevents false activations on adjacent intents.

**Validation**:
- Mentally test 10 requests that SHOULD trigger this skill — do all 10 match the new description?
- Mentally test 5 requests that should NOT trigger — none should match?

**Regression risk**: Over-narrowing trigger scope (missed activations), over-pushing (competes with adjacent skills).

---

## Recipe: "Add Anti-Patterns" / "Add NEVER Items"

**Naive mistake**: Generic warnings. "Be careful with X", "avoid mistakes", "don't introduce bugs".

**Expert technique**: Every NEVER needs three components:
1. **Specific action** (not a category): "NEVER do Y" where Y is concrete
2. **Specific consequence**: not "because it causes problems" but "because [specific failure mode]"
3. **Non-obvious reason**: something experience teaches, not first-principles obvious

Canonical structure:
```
NEVER [specific action] because [specific failure that non-experts wouldn't predict].
Example: [concrete scenario where this goes wrong, or version/library specifics].
```

**The expert reader test**: Would a domain expert nod and say "yes, I learned this the hard way"? If a junior developer would know the warning, it's not expert-grade.

**The specificity test**: Can you name a concrete failure scenario? If not, the anti-pattern is too vague.

**Placement**: NEVER sections belong near the top or bottom (primacy/recency), NOT buried mid-body.

**Regression risk**: Over-constraining a high-freedom creative skill (D6 drop), bloating past length (D5 drop).

---

## Recipe: "Reorganize" / "Structure Is Confusing"

**Naive mistake**: Reshuffle sections or add more headers for visual structure.

**Expert technique**: Structure complaints mean ONE of:
1. **Wrong pattern** — skill uses Process conventions for a Mindset domain (or vice versa)
2. **Wrong layer** — content in body that belongs in `references/`, or trigger info in body that belongs in description

**Pattern diagnostic**: "If I removed all step-by-step procedures, would anything valuable remain?" If yes → really a Mindset/Philosophy skill. If no → Process may be correct.

**Layer diagnostic**: For each section, ask: "Is this needed on EVERY activation of this skill?"
- Yes → body
- No (only for specific sub-tasks) → `references/` with loading trigger

**Structural moves (Fowler refactoring applied to prose)**:
- Extract to references/ — self-contained section → own file
- Inline from references/ — small file always needed → body
- Move to description — trigger info in body → description field
- Reorder for attention — critical constraints → top or bottom
- Split section — section mixing concerns → two focused sections
- Merge sections — duplicate coverage → one coherent section

**Regression risk**: Highest regression class. Always diff after reorganization to verify nothing was lost.

---

## Recipe: "Add Examples"

**Naive mistake**: Generic placeholders (`[some code here]`) or examples that could apply to any skill in the domain.

**Expert technique**:
1. **What KIND?** Decision-tree, code, before/after contrast, or scenario examples?
2. **Where?** At the point of MAXIMUM uncertainty — where the skill gives a principle and the reader needs to see it applied.
3. **How many?** One excellent working example beats three generic ones.

**Type by pattern**:
- Mindset → before/after contrast pairs
- Tool → working code with real tool names, actual parameters
- Process → checkpoint examples showing completion state per phase
- Navigation → decision-tree examples per branch

**Concreteness test**: Replace any placeholder with real content. If the example still makes sense abstractly, it's too generic.

**Generic test**: Would this exact example appear in 10 other skills in the domain? If yes, too generic.

**Regression risk**: Pushing past length budget (D5), biasing model toward imitation instead of principle application (D6).

---

## Recipe: "Add a references/ Directory"

**Decision rule**: Content belongs in references/ if it's needed only for specific sub-scenarios, not every activation. Content belongs in body if it shapes every interaction.

**In references/**:
- Detailed lookup tables (>50 lines)
- Specialized procedural knowledge for one of several tasks
- Domain specifications (format details)
- Long code examples used verbatim

**In body**:
- Decision trees loaded every activation
- Anti-patterns (always needed — never orphan them)
- Core framework
- Loading triggers for references/

**Loading trigger requirement** (D5): Every reference file needs an explicit trigger embedded in workflow:
```
MANDATORY — Read `references/X.md` before proceeding with task Y.
```

**Do NOT Load anti-trigger**: For skills with multiple references, specify which NOT to load per task:
```
For task A: load references/a.md. Do NOT load references/b.md.
```

**Regression risk**: Creating references without loading triggers is an instant D5 regression (orphan references pattern).

---

## Recipe: "It's Too Rigid" / "Too Prescriptive"

**Naive mistake**: Remove procedural steps wholesale, leaving ambiguity.

**Expert technique**: Match freedom to task fragility.
- **Low freedom appropriate**: fragile operations (file format ops, API calls, exact commands). Consequence of a mistake: corrupted output.
- **High freedom appropriate**: creative tasks (design, writing, analysis). Consequence: bland output.

**The fragility test**: "If the agent makes a mistake here, what's the consequence?"
- Corrupted/irreversible → Low freedom (exact steps OK)
- Ugly/ineffective → High freedom (principles, not steps)

**Conversion techniques**:
- Prescriptive → Principled: "Step 1: Open file. Step 2: Edit..." → state the domain decision at that step and its consequence: "Edit only the smallest region the fragility test flags; editing more risks the exact corruption this step guards against."
- Rules → Reasoning: "NEVER use X" → "X typically fails because [reason]; prefer Y unless [condition]"

**Regression risk**: If the task is actually fragile (e.g., OOXML editing), increasing freedom breaks correctness.

---

## Recipe: "I Don't Like Section X"

**Step 1: Intent archaeology**. Work backwards to why the user dislikes it:
1. Is the section explaining something Claude already knows? → D1 problem (redundant)
2. Is it too generic? Could apply to any domain? → D1 problem (lacks delta)
3. Is it in the wrong place? → D5 problem (wrong layer)
4. Is it too long for its value? → D1 + D5 problem
5. Does it contradict guidance elsewhere? → D8 problem (internal contradiction)

**Step 2**: Apply the matching fix:
1 → cut or compress
2 → replace with expert content specific to this domain
3 → move to references/ or description
4 → compress aggressively
5 → resolve contradiction (pick the correct guidance)

**Never** just rewrite the section stylistically without identifying which failure mode applies.

---

## Recipe: "Make It Better" (Pure Vague)

**The one-question rule**: Ask ONE targeted question, not a list:

> "When you imagine using this skill and it works perfectly, what's different about what it does compared to now?"

This surfaces the functional gap without requiring the user to understand the 8-dimension rubric.

If the user can't articulate a gap, offer to run Creative mode instead: generate improvement ideas, let the user pick.

---

## Anti-Patterns Across All Recipes

These are naive implementations that appear across multiple request types:

- **"Make shorter" → random deletion** (should: E/A/R audit first)
- **"Add examples" → generic placeholders** (should: specific + working)
- **"Improve description" → longer but same vagueness** (should: WHAT/WHEN/KEYWORDS)
- **"Add anti-patterns" → generic warnings** (should: specific + consequence + WHY)
- **"Reorganize" → reshuffle without pattern diagnosis** (should: pattern check first)
- **"Add references/" → create files without loading triggers** (should: trigger embedded in workflow)
- **"Make concise" → remove the WHY from anti-patterns** (should: WHY is sacrosanct)
- **"Clarify" → more headers** (should: fix information architecture)
