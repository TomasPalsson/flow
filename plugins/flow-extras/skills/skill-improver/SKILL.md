---
name: skill-improver
description: "Use WHENEVER the user asks to improve, refine, polish, fix, audit, optimize, or suggest improvements for an existing Agent Skill / SKILL.md file. Key scenarios: (1) skill exists but never triggers → activation failure, fix description first; (2) skill fires but output is weak → content failure, fix body; (3) user names a specific change → DIRECTED mode; (4) user asks what could be better → CREATIVE mode. Trigger phrases: 'improve this skill', 'polish SKILL.md', 'fix skill', 'this skill never fires', 'audit skill', 'suggest skill improvements'. Do NOT use skill-judge when the goal is to produce edits — skill-judge evaluates only; this skill evaluates AND edits. Do NOT use for: creating new skills from scratch (use skill-forge), general prose editing, non-skill markdown files."
---

# Skill Improver

Improve an existing SKILL.md with surgical precision, not wholesale rewrites. This skill does two things: applies user-directed improvements correctly, or generates novel improvement ideas — never both in one pass.

## Core Principles

**Surgical edits beat rewrites. Every time.** The #1 failure mode when improving skills is regenerating the whole file. That erases deliberate author choices, voice, and system-level decisions you can't see. Define a change budget BEFORE opening the file — list the exact sections you'll touch — and don't exceed it.

**Diagnose before editing.** Skill failures split into two mutually-exclusive classes: activation failures (skill is invisible because the description doesn't trigger) or content failures (fires but produces weak output). Fixing content on an invisible skill is wasted work.

**Addition bias is structural.** LLMs systematically propose additions (more examples, more NEVER, more edge cases) and systematically miss subtractions. For every proposed addition, force the question: "Would removing weak content serve the same goal?"

**Voice is functional, but calibrated.** Reserve terse imperative wording ("NEVER X. It will break.") for the one or two rules a test actually showed get rationalized away under conversational pushback — that phrasing is harder to talk a model out of. Everywhere else, a calm rule that states its reason works better on current Claude models: stacking emphasis onto many lines dilutes all of it and can cause over-triggering. Don't polish away a blunt rule that already carries a reason, and don't add new shouting to rules nobody has tested under pushback.

**Skill-judge's 8 dimensions interfere.** Fixing D3 often bloats past length and degrades D5. Adding examples dilutes D1. Pushy descriptions degrade D4 clarity. Think systemically — check regression across dimensions, not just the targeted one.

---

## Phase 0: Select Mode (MANDATORY)

Before anything else, determine which mode applies:

| If the user says... | Mode |
|---|---|
| "add X", "fix Y", "improve description", "make shorter", "reorganize", "I don't like section Z" | **DIRECTED** |
| "suggest improvements", "what could be better", "review this skill", "brainstorm ideas for", "audit this" | **CREATIVE** |
| "make it better" (no specifics) | Ask ONE question: "What fails when you use it?" Then route. |

**Never mix modes.** Directed mode that generates creative ideas produces score-chasing noise. Creative mode that executes random improvements damages skills. Pick one. Commit.

---

## Phase 1: Diagnose (both modes)

**Before improving, ask yourself:**
- What does this skill WANT to be? (What's its pattern, voice, intended audience?)
- What would be lost if I blindly applied best practices?
- What's the ONE thing most broken, vs the 3-4 things I could polish?

Read the full SKILL.md first. Then answer these three diagnostic questions before touching anything:

**Q1: Activation or content failure?**
- Read the description aloud. Ask: "If I were an agent seeing 40 descriptions, would this one stand out for the user's scenarios?" If no → activation failure. Fix the description first.
- Identify 3 sentences in the body that would change model behavior. If you can't find them → content failure. (Tiebreaker for ambiguous sections: "If I replaced this with 'use your judgment', would the output change?" No → Activation. Yes → Expert.)
- Both broken = mixed failure. Fix activation first; content work is wasted on invisible skills.

**Q2: Does the skill use the right pattern?**
Apply this diagnostic: "If I removed all step-by-step procedures, would anything valuable remain?" If yes → it's really a Mindset/Philosophy skill being run as Process. If no → Process may be correct.

Quick pattern first-cut (detect without loading the reference): Mindset ≈ 50 lines, no steps, high freedom. Navigation ≈ 30 lines, routes to sub-files. Philosophy ≈ 150 lines, "why hard" + craft framework. Process ≈ 200 lines, numbered phases + gates. Tool ≈ 300 lines, decision trees + exact code.

**If pattern mismatch is detected — MANDATORY**: Read `references/pattern-switching.md` completely before proceeding. Do NOT load it if the current pattern is correct — it is only needed for conversions.

**Q3: Is the skill smooth or rough?**
A skill that reads cleanly end-to-end is SUSPICIOUS. Genuine expert knowledge is hedged, conditional, rough ("except when X, in which case Y"). Smooth = training-distribution reformatting. Find the most specific sentence. If it sounds like a top-3 Stack Overflow answer, knowledge delta is low.

Also identify the skill's VOICE (imperative? hedged? terse? formal?) and document it. Improvements must preserve the voice unless the voice itself is the problem.

---

## Phase 2 (Directed Mode): Interpret → Apply → Validate

### Step 2a: Interpret the request

Surface requests encode dimension problems. Translate:

| User says... | Underlying dimension problem | Technique |
|---|---|---|
| "Make shorter" | Redundant content; ceremony before substance (D1/D5) | E/A/R audit; cut R, compress A |
| "Make longer" / "feels thin" | Missing anti-patterns, decision trees, or edge cases (D3/D8) | Identify specific gap; add substance, not filler |
| "Improve description" | D4 — WHAT/WHEN/KEYWORDS missing or passive | Rewrite with concrete "Use when..." scenarios + near-miss exclusions |
| "Add examples" | D8 — gap at point of maximum uncertainty | One concrete working example > 3 generic |
| "Add anti-patterns" | D3 vague or missing | Action + consequence + non-obvious reason |
| "Reorganize" / "confusing" | Wrong pattern (D7) OR wrong layer (D5) | Diagnose which; pattern fix before shuffling |
| "It's too rigid" | D6 — freedom miscalibrated | Match freedom to task fragility |
| "I don't like section X" | Usually D1 (redundant content) in that section | Audit E/A/R in that section only |

**MANDATORY for Directed mode**: Read the relevant recipe section in `references/directed-recipes.md` before applying any improvement. Do NOT load `references/pattern-switching.md` unless Q2 in Phase 1 detected a pattern mismatch.

### Step 2b: Define a change budget

Before editing, write down:
- Exact sections to modify
- Exact lines (approximate ranges)
- Expected length delta

Any change beyond this budget is scope creep. If you notice adjacent issues, FLAG them for the user as separate improvement opportunities. Don't silently "fix" them.

### Step 2c: Push back when warranted

Push back — don't comply — when:
1. The literal request would HARM a higher-value dimension (e.g., "add more examples" when the skill is already bloated with redundant content)
2. The request assumes a false diagnosis (e.g., "make it longer" for a correctly-concise Mindset skill)
3. Information would move to the wrong layer (e.g., "put trigger info in body" — agents never read body before routing)
4. The request contradicts the skill's pattern (e.g., "add procedures" to a Mindset skill)

Pushback always names the concrete reason AND offers an alternative. Never refuse without redirecting.

### Step 2d: Apply the minimal change

Edit surgically. Preserve voice. Touch only budgeted sections.

### Step 2e: Validate

After the edit, run through this checklist:
- [ ] Targeted dimension actually improved? (Concrete evidence, not vibes.)
- [ ] Every OTHER dimension unchanged or improved? (Regression check — see Interference Matrix below.)
- [ ] Description-body coupling intact? (Body content still matches description scope?)
- [ ] Voice preserved?
- [ ] Body length within 300 soft / 500 hard limit?

If any box is unchecked, revert and re-plan.

---

## Phase 2 (Creative Mode): Explore → Diverge → Converge → Present

Keep these three phases strictly separated. Collapsing them produces premature convergence on safe ideas.

### Step 2a: Explore (no ideas yet)

**Do NOT load** `references/directed-recipes.md` — it contains directed-improvement techniques that are irrelevant in Creative mode.

Read the SKILL.md once. Classify each section E/A/R, identify the VOICE, spot pattern fit, flag dimensional weaknesses.

**Ambiguous E vs A heuristic** (use in any mode): When unsure if content is Expert or Activation, ask: "If I removed this section and replaced it with 'use your judgment', would the model's output change?" No → it's Activation. Yes → keep as Expert. This is the only tiebreaker needed.

Note: pattern type, E:A:R ratio, weakest dimensions, VOICE (imperative/hedged/terse), top-3 characteristics to preserve.

### Step 2b: Diverge (no evaluation yet)

Generate ideas across ALL SIX categories. Do not let any category be empty — each surfaces ideas the others miss:

1. **Structural Transformation** — Would a pattern-switch help? (Process → Philosophy? Tool → Navigation?) Would section-order inversion surface critical info earlier? Would NEVER entries become positive affordances?

2. **Perspective Shifts** — Rewrite from the user's POV, from anti-pattern-first organization, from a skeptical critic's POV. What does an expert in an unrelated domain (teacher, surgeon, editor, game designer) notice?

3. **Compression & Subtraction** (MANDATORY — do not skip) — What's the 20% that carries 80% of value? Which instructions would the model follow without being told? What can be deleted entirely? What could move to references/ instead of the body?

4. **Decision-Tree Extraction** — Where are implicit "if/when/unless" branches in the prose? What decisions is the skill leaving to tacit knowledge? What are the five most different inputs and where does guidance diverge?

5. **Trigger/Description Optimization** — Does the description cover the real user vocabulary? What requests would trigger false positives? What adjacent skills need disambiguation?

6. **References Architecture** — What's in body that should be in references? What's in references that's needed every run and should be inlined?

**Anti-generic techniques** (apply after first pass):

- **Exclusion constraint**: Name the 3 most obvious ideas you just generated. Now generate 3 more with NOTHING in common with those.
- **Inversion**: "What would make this skill fail catastrophically?" Generate 5 failure modes. Invert each to an improvement.
- **Cross-domain analogy**: What would a surgical checklist, a recipe, a Socratic dialogue, or a legal brief add to this skill's structure?

### Step 2c: Converge (evaluate now)

**Top 3-5 ideas get full Passports** (all 7 fields below). The rest get one-line summaries with effort + confidence only. Filling 12 Passports is overengineering.

| Field | Content |
|---|---|
| Improvement | One-line description |
| Category | Structural / Perspective / Compression / Decision-tree / Trigger / References |
| Quoted source | Specific lines from SKILL.md motivating this, or "MISSING" |
| Failure mode addressed | Concrete bad-output scenario this prevents |
| Trade-off | What this costs (length, flexibility, risk of over-prescription) |
| Effort | XS (one sentence) / S (one section) / M (new section) / L (restructure) / XL (pattern change) |
| Confidence | High (structural flaw visible) / Medium (plausible hypothesis) / Low (experimental) |

**Trade-off is mandatory.** Every skill improvement has a cost. An improvement without a stated trade-off has not been thought through.

**Example completed Passport:**

| Field | Content |
|---|---|
| Improvement | Upgrade NEVER entries with production-concrete consequences |
| Category | Compression (anti-patterns exist but behavioral weight is low) |
| Quoted source | "A rewrite silently erases calibrated author choices" — consequence is abstract |
| Failure mode addressed | Agent reads the NEVER, doesn't see a specific failure, rationalizes past it and produces a de facto rewrite |
| Trade-off | Longer entries (+1-2 sentences each); total +8-10 lines on body length |
| Effort | M |
| Confidence | High — structural flaw visible in 8 of 12 entries |

Group ideas into tiers:
- **Foundation** (contradictions, broken triggers, wrong outputs — fix regardless of effort)
- **Growth** (consistently better across invocations)
- **Delight** (unexpected value — only surface if Foundation is clean)

### Step 2d: Present

- Lead with the insight that reframes how the user thinks about their skill
- Foundation → Growth → Delight ordering
- 6-12 total ideas (not a laundry list)
- Top 3-5 get full Passports; rest get 1-2 sentence summaries
- AT LEAST 1 compression/subtraction idea (forced — do not skip)
- End with: "If you did ONE thing, this is the highest-leverage improvement because [specific reason]"

---

## The Dimension Interference Matrix

Before any improvement, check what it might break:

| Improving... | Risks degrading... | Mechanism |
|---|---|---|
| D3 anti-pattern coverage | D5 progressive disclosure | Added NEVER entries bloat past pattern's line budget |
| D8 via examples | D1 knowledge delta | Examples often explain context Claude knows |
| D4 via expanding description | D4 clarity itself | Packing keywords reduces routing precision |
| D6 via explicit scripts | D8 usability | Rigid scripts break adaptation to variants |
| D2 via "ask yourself" framing | D1 knowledge delta | Generic "ask yourself" questions are content Claude already acts on; the judge no longer credits them |
| D1 via cutting | D3 / D8 | Expert content and WHYs can be removed accidentally |
| D5 via new references/ dir | D5 itself | Orphan references without loading triggers |

---

## NEVER Do These

**NEVER rewrite when a surgical edit suffices.** The rewrite fallacy is the #1 improvement failure. Production failure: agents using the rewritten skill produce homogenized output indistinguishable from zero-skill mode — the calibrated choices (line budget, voice, scope) that made the original work are gone, replaced by your defaults. If 60% of the file is changing for a "targeted" fix, stop — you're writing a new skill, not improving one.

**NEVER propose additions before evaluating subtractions.** Training data skews toward building, not removing. Production failure: the skill grows past its pattern's line budget, pushing knowledge delta below 70%, and the agent's attention spreads across bloat instead of hitting the high-value content. For every proposed addition, ask: "Would removing weak existing content serve the same goal?" A 320 → 200 line skill by subtraction outperforms a 320 → 360 line skill by addition.

**NEVER remove content you can't articulate a reason for.** Chesterton's fence. Production failure: you delete a "redundant-looking" section, and the next week the user reports the skill now misfires in the specific edge case that section was handling. Burden of proof is on the change. If you can imagine a plausible reason it was written that way, preserve it or make the narrowest possible edit.

**NEVER improve the body without auditing the description.** Description-body coupling failures are silent. Production failure (Mode A): you add a new capability to the body that isn't reflected in the description — the skill never activates for that capability's use case, so your improvement is invisible. Production failure (Mode B): you expand the description's WHEN clauses without covering them in the body — the skill activates on new scenarios and produces generic output because the body can't deliver.

**NEVER use judge score as the sole success criterion.** Goodhart's Law. Production failure: D3 gets gamed by manufacturing 5 new NEVER entries that read as specific but aren't real failure modes. Score rises; an expert reading the skill says "these aren't things I've actually seen" and dismisses the whole NEVER list. The real test: would a domain expert read each change and say "yes, I learned this the hard way"? If no, the score improvement is cosmetic. A score gain only counts if a with/without run on 2-3 prompts (or the skill's own eval) shows no new regression — without that check, a higher score is unverified.

**NEVER smooth away a blunt rule that a test showed resists pushback.** Production failure: a polished skill saying "it is recommended to avoid X as it can sometimes cause issues" gets overridden by in-context persuasion — users pushing back in conversation get compliance. Where testing showed "NEVER X. It will break." held up and a calm rewrite didn't, keep the blunt version. Elsewhere, polishing toward a calm rule that states its reason is fine — it works better on current models than blanket shouting.

**NEVER exceed the change budget.** Production failure: what started as "fix the description" becomes a 6-section rewrite; you silently touch sections the user didn't ask about, and when something breaks the user has no map of what changed. Define the exact sections you'll touch BEFORE opening the file. Flag out-of-scope observations separately; don't silently "fix" them.

**NEVER comply with a user request that damages the skill.** Sycophancy in skill improvement is high-cost because regressions are invisible until the agent fails in production on a real task. Production failure: user asks for "more examples", you add 4 generic ones, skill now scores 13/20 on knowledge delta (was 17/20), and a week later the user notices the skill's output got vaguer but can't say why. Push back with an alternative.

**NEVER iterate past convergence.** Production failure: you chase 96/120 from a stable 91/120, and end up at 87/120 after breaking something that was working. Past convergence, improvements and regressions occur at equal rates. Ship the 91 rather than risk an 87 while chasing 96.

**NEVER mistake reformatting for improvement.** Production failure: you convert bullets to a table and add 3 headers. The skill LOOKS more organized. The agent's behavior does not change — same output, same decisions. You've spent effort for zero behavioral delta. If no sentence was added, removed, or substantively rewritten, nothing improved.

**NEVER jump to edits before diagnosis.** Production failure: the skill's real problem is that its description is broken (activation failure), but you spend an hour polishing the body. After your edits the skill still never fires, so none of your improvements have any effect. Phase 1 is mandatory — a skill scoring badly on multiple dimensions often has ONE root cause.

**NEVER apply feedback that contradicts a prior round without flagging the conflict.** Production failure: round 1 said "be more specific" so you added detail. Round 3 says "be more concise" so you cut detail. Now the skill has lost what made round 1's feedback useful and is back to the pre-round-1 state, having burned two iterations. Resolution rule: specificity wins INSIDE NEVER entries; conciseness wins in procedures. Name the conflict; pick a side with reasoning.

---

## Minimum Viable Output

Before reporting complete, verify: mode was explicit, failure class was diagnosed, voice was preserved, all changes were in-budget, regression check ran on all 8 dimensions, body ≤ 500 lines, behavioural evidence for content changes (with/without on 2-3 prompts), or "Behavioral evidence: NONE" stated. Creative mode also needs: Trade-off field on every idea, ≥1 compression/subtraction idea, all ideas grounded in quoted SKILL.md sources (not generic advice). Any scope creep → flagged as separate opportunity, not silently applied.
