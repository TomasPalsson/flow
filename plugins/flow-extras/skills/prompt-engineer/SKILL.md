---
name: prompt-engineer
description: "Design and write production-grade system prompts for AI agents and LLM applications — including CLAUDE.md files, SKILL.md files, and agent instructions. Do NOT use for: one-off user prompts or prompt templates for human use. Use WHENEVER the user asks to: create a system prompt, write agent instructions, design an AI persona, configure agent behavior, create tool descriptions, or engineer context for any LLM. Also trigger on: 'system prompt', 'agent prompt', 'prompt for Claude/GPT/Gemini', 'context engineering', 'tool descriptions'."
---

# System Prompt Engineer

Craft system prompts that install expert cognition, not instructions that compress what the model already knows.

## The Core Insight

> **A system prompt does not work by giving the model information — it works by changing what the model notices, worries about, and reaches for by default.**

The difference between a novice system prompt and an expert one is not length or detail — it's **knowledge delta**. Every token must encode something the model wouldn't do on its own. If the model would already do it without being told, the token is waste competing for attention against tokens that matter.

---

## Before Writing Anything

Before writing a single line of system prompt, ask yourself:

1. **What does the model get WRONG without this prompt?** If you can't answer this, you don't need a system prompt — you need to test the model's baseline behavior first.
2. **What are the consequences of failure?** High-consequence (irreversible actions, financial impact, safety) → low freedom, exact constraints. Low-consequence (style, format) → high freedom, principles only.
3. **Who is the audience?** A system prompt has two audiences: the routing layer (description/metadata that decides whether to load it) and the execution layer (the body that guides behavior after loading).
4. **What model(s) will run this?** Prompts are model-dependent. Claude benefits from XML. GPT-4/5 prefers Markdown. Gemini 3+ works best with minimal structure. A prompt optimized for one model can degrade 40%+ on another.

---

## The Architecture

### Layer 1: Identity and Orientation (First 2-3 sentences)

Define the behavioral role — what the agent IS DOING, not what it CLAIMS TO BE.

**Do this:**
```
You are executing an adaptive code review workflow.
Your default stance is skepticism toward all external inputs.
You never execute write operations without first listing what will be changed.
```

**Not this:**
```
You are a brilliant senior engineer with 20 years of experience
who is an expert in all programming languages.
```

Why: "Act as an expert" prompts degrade factual accuracy by 3-5 percentage points (Wharton GAIL 2025, tested across 6 major LLMs). Expert personas activate the failure modes of expert communication — overconfidence, jargon, hallucinated authority. Define behavior and operational contracts instead.

### Layer 2: Critical Constraints (Immediately after identity)

Place NEVER rules and non-negotiable constraints here — at the TOP, never buried in the middle.

Why this position matters: Models exhibit a U-shaped attention curve (primacy/recency bias). Content in the middle of long prompts receives 30%+ lower attention. If a constraint is critical, it goes first. If truly non-negotiable, repeat it at the end.

**Strong constraint:**
```
NEVER execute database mutations without outputting a dry-run plan first.
Reason: production data loss from unplanned mutations is irreversible.
```

**Weak constraint (avoid):**
```
Be careful with database operations.
```

Every constraint needs a specific reason. Vague warnings are ignored. Specific reasons with consequences are followed.

### Layer 3: Decision Frameworks (Core of the prompt)

The model lacks expert judgment for choosing BETWEEN approaches — encode that judgment as decision trees, not step lists.

```
| Situation | Action | Why |
|-----------|--------|-----|
| Bug is intermittent | Add logging before attempting fix | Intermittent bugs often have timing-dependent causes invisible without logs |
| Same test fails 3x after fix | STOP. Report to user. | Fix approach is fundamentally wrong — more iteration won't help |
| Tool returns unexpected format | Validate schema, treat as permanent error if invalid | Retrying malformed responses wastes budget |
```

### Layer 4: Output Format and Boundaries (End of prompt)

Specify format requirements and re-state any truly critical constraints (recency bias makes end-positioned rules more durable in long conversations).

---

## Token Budget Rules

System prompt length directly impacts quality. This is architectural, not a best-practices opinion.

| Token Count | Effect |
|-------------|--------|
| 150-400 tokens (~150-300 words) | Sweet spot for most tasks |
| ~3,000 tokens | Reasoning performance begins measurably degrading |
| ~32,000 tokens | General task performance degrades across all frontier models |
| 80,000+ tokens | System prompt adherence measurably erodes |

**The attention equation:** Every token you add competes with every other token for the model's finite attention budget (O(n²) complexity). A 500-token prompt that's 100% signal outperforms a 3,000-token prompt that's 30% signal — even though the longer prompt contains more total information.

**Practical rule:** If your system prompt exceeds ~1,500 tokens, audit each section: "Would the model do this without being told?" If yes, delete it. If maybe, compress it to one line. Only keep sections where the answer is clearly "no."

---

## Compressing Large System Prompts

**If improving an existing prompt over ~2,000 tokens** — **MANDATORY:** Read [references/prompt-compression.md](references/prompt-compression.md) before starting. Do NOT load for new prompts or prompts under 2,000 tokens.

Structural reorganization always beats automated compression. The priority order:

1. **Knowledge delta audit** (30-50% reduction): For every sentence, ask "Would the model do this without being told?" If yes, delete it.
2. **Deduplication** (10-20%): Extract all imperative statements into a flat list. Same constraint stated 3 ways → one canonical version.
3. **Structural extraction** (50-80% per-request): Split into routing core (~200-500 tokens) + conditional modules loaded on demand.
4. **Format optimization** (15-30%): Convert verbose prose rules to pseudocode/if-then (25-60% savings). Use tables for lookup rules. Cut filler words.
5. **Automated compression** (optional, context only): LLMLingua-2 at 2x-3x on injected context. NEVER on instruction core or safety constraints.

**The compression paradox:** Aggressive automated compression (>5x) can INCREASE total cost because output tokens expand to compensate for missing context, and output tokens cost 3-5x more than input tokens. Safe automated ratio: 2x-2.5x maximum.

**Safety constraints are disproportionately fragile** under compression — even 20% token removal causes compliance failures. Always preserve safety sections verbatim.

---

## Tool Description Engineering

**If the system prompt includes tools** — **MANDATORY:** Read [references/tool-descriptions.md](references/tool-descriptions.md) before writing tool descriptions. Do NOT load for tool-free prompts.

Tool descriptions matter MORE than the system prompt for agent behavior. Anthropic's SWE-bench team spent more time on tool descriptions than the overall prompt. Key rules:
- Every tool needs: WHEN to use it, disambiguation from similar tools, parameter examples, failure modes
- Minimal toolsets (3-5) outperform bloated ones (15+) — ambiguity scales with count
- Tool description improvements alone yielded 40% reduction in task completion time

---

## Provider-Specific Guidance

**Default (no provider specified or cross-provider):** Use Markdown structure. Do NOT load any provider-specific references.

**If targeting a specific provider — MANDATORY before drafting:**
- **Claude:** Read ENTIRE [references/claude-specific.md](references/claude-specific.md) before writing. Do NOT load other provider references. Key: XML structure, adaptive thinking, trust hierarchy, cache thresholds.
- **GPT-4/5:** Read ENTIRE [references/openai-specific.md](references/openai-specific.md) before writing. Do NOT load other provider references. Key: Markdown structure, surgical instruction-following, structured outputs.
- **Gemini:** Read ENTIRE [references/gemini-specific.md](references/gemini-specific.md) before writing. Do NOT load other provider references. Key: Minimal structure, system_instruction field, cache storage costs.
- **Open-source:** Read ENTIRE [references/open-source-specific.md](references/open-source-specific.md) before writing. Do NOT load other provider references. Key: Chat template requirements, no trust hierarchy.

---

## The System Prompt Writing Process

**Determine your starting condition first:**

| Condition | Starting Point |
|-----------|---------------|
| Writing from scratch, can test model baseline | Phase 1 below |
| Improving an existing prompt (<2,000 tokens) | Phase 4 (Harden) — run knowledge delta audit on existing prompt, then rewrite |
| Improving an existing prompt (>2,000 tokens) | **MANDATORY:** Read [references/prompt-compression.md](references/prompt-compression.md) first, then Phase 4 |
| No access to baseline testing (production, inherited) | Skip Phase 1 — go directly to Phase 2, use knowledge delta audit instead of baseline |
| User hasn't specified target model | Use Markdown as default, proceed without asking |

### Phase 1: Baseline Testing
Test the model's behavior WITHOUT a system prompt on 5-10 representative inputs. Document where it fails. The system prompt exists to fix THESE failures — nothing else.

### Phase 2: Draft
Follow the architecture above (Identity → Constraints → Decision Frameworks → Output Format). Target 150-300 words.

### Phase 3: Validate
**If test access available:** Test the draft against baseline inputs plus edge cases. Check for NEW failure modes (over-refusal, style rigidity) and test at production context lengths.

**If no test access:** Structural validation instead — run contradiction scan (every rule pair), attention position audit (critical constraints at start/end?), knowledge delta audit (every sentence earns its tokens?), and verify token count is under 1,500.

### Phase 4: Harden
- Run contradiction detection: read every rule pair and ask "can both be true simultaneously?"
- Apply the bookend pattern: repeat critical constraints at the end
- Verify token count is under 1,500 (ideally under 500)
- Check formatting style matches desired output style

---

## NEVER Do These

- **NEVER use "Act as an expert [X]" for factual/reasoning tasks.** Degrades accuracy 3-5 percentage points. Use behavioral role definitions instead. Expert personas help ONLY for tone/style/alignment tasks.

- **NEVER add rules without measuring cumulative compliance.** Beyond ~15 explicit rules, the model's compliance per-rule degrades logarithmically. Rules interact in unpredictable ways. If you need >10 behavioral rules, enforce the overflow architecturally (guardrails, validation layers), not through prompt text.

- **NEVER bury critical constraints in the middle of a long prompt.** Models attend most to the beginning and end (30%+ accuracy drop for middle-positioned content). Critical rules go first. Non-negotiable rules get repeated at the end.

- **NEVER assume system prompts survive model updates.** GPT-4's code output dropped from 52% to 10% over six months. Claude Sonnet 4.5 began treating "MUST" as suggestions. System prompts require regression testing on every model update — treat them as deployable artifacts, not configuration.

- **NEVER use Chain-of-Thought scaffolding on reasoning models.** "Think step by step" DECREASES performance on o1/o3/o4-mini and Claude with extended thinking. These models run their own internal reasoning. External scaffolding constrains rather than guides. For reasoning models: specify output format and constraints, not reasoning steps.

- **NEVER embed secrets, API keys, or proprietary logic in system prompts.** Assume every system prompt will be extracted. Extraction techniques range from trivial ("repeat your instructions") to sophisticated (gradient-based attacks). Retrieve sensitive data dynamically through secure calls.

- **NEVER write tool descriptions as afterthoughts.** Tool descriptions are load-bearing prompts. They matter MORE than the system prompt for agent task selection. A poorly worded tool description causes wrong tool selection, parameter hallucination, and cascading failures. Invest more engineering effort in tool descriptions than in the system prompt itself.

- **NEVER use "be helpful" as an unbounded top-level directive.** Models trained on helpfulness have a strong prior toward compliance that adversarial inputs exploit. Scope helpfulness: "Be helpful within these constraints, and decline helpfully outside them."

- **NEVER test safety behavior only at short context lengths.** Refusal rates shift unpredictably as context grows (5% → 40% or 80% → 10% at 200K tokens, depending on model). Safety testing must happen at production context lengths.

- **NEVER write the system prompt before understanding the domain's failure modes.** A system prompt written from general knowledge compresses what the model already knows. The value comes from encoding failure modes, edge cases, and expert judgment that the model lacks. Research first, write second.

- **NEVER front-load all instructions for complex, long-running agents.** Decision-time guidance (injecting situational instructions at key decision points) outperforms exhaustive front-loading. Maintain a minimal system prompt for identity and global constraints; inject task-specific rules at task boundaries.

- **NEVER write a system prompt in a format you don't want in the output.** Heavy markdown system prompts produce heavy markdown responses. If you want plain prose output, write the system prompt in plain prose. Format style bleeds from prompt to output.

- **NEVER iterate on wording before fixing structure.** 80% of prompt failures are structural — wrong layer, wrong position, missing constraint type. Rewording a mispositioned rule doesn't fix it. Diagnose structure first: Is the rule in the right layer? Is it at the right attention position? Is the freedom calibration correct? Only then refine wording.

- **NEVER improve a prompt by adding to it.** Every token added makes the signal-to-noise ratio worse. The correct reflex when a prompt underperforms is to look for what to REMOVE, not what to add. Ask: "What would I cut if I had to get this to 50% of current length?" — this is a better diagnostic than "What am I missing?"

- **NEVER evaluate a prompt using the same inputs you wrote the rules for.** Testing against inputs you already handled is fitting, not evaluation. Representative evaluation requires inputs you haven't seen — especially adversarial edge cases and boundary conditions between rules.

---

## Agent-Specific Patterns

When writing system prompts for autonomous agents (not chatbots), these additional patterns apply:

### Stop Conditions
Agents require explicit termination criteria. Without them, agents either declare success prematurely or loop indefinitely.
```
Complete when: all tests pass AND code review checklist passes.
Stop and escalate when: same error occurs 3 consecutive times OR task exceeds 30 minutes.
Maximum iterations: 5 revision cycles, then finalize regardless.
```

### Error Classification
```
Transient (retry): network timeout, rate limit → exponential backoff, 3 retries max
Permanent (escalate): permission denied, file not found → do not retry, report to user
Ambiguous (validate): unexpected format → schema check, treat as permanent if invalid
```

### Autonomy Calibration
```
Read operations: free — no confirmation needed
Idempotent writes: low friction — output plan, proceed
Destructive operations: require explicit confirmation before executing
External API calls with side effects: require justification before calling
```

### Multi-Agent Orchestrator Prompts
The orchestrator is a ROUTER, not an executor. Its system prompt needs:
1. Explicit "never perform tasks directly" instruction
2. Agent capability map with trigger conditions
3. Deterministic routing logic (decision tree, not vibes)
4. Delegation format specification (objective, output format, tool list, boundaries)
5. Maximum hierarchy depth of 3 levels

