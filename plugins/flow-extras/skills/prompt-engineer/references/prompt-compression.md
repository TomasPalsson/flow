# Compressing Large System Prompts

## The Compression Paradox

Aggressive automated compression (retaining <40% of tokens) can INCREASE total cost because:
- Compressed inputs cause models to generate longer, more exploratory outputs
- Output tokens are priced 3-5x higher than input tokens
- At 80% compression (r=0.2), one production RCT showed mean cost INCREASED by 1.8%
- Safe zone for automated compression: 40-60% retention (2x-2.5x ratio maximum)

**Rule: Structural reorganization always beats automated compression for system prompts.**

---

## The 6-Phase Compression Workflow

### Phase 1: Knowledge Delta Audit (biggest win — 30-50% reduction)

For every sentence, ask: "Would the model do this without being told?"

**Cut immediately:**
- Generic politeness ("be kind," "be professional")
- Technical facts the model knows ("Python uses indentation," "JSON must be valid")
- Redundant restatements of the same rule across sections
- Instructions implied by more specific ones already present
- "Just in case" edge cases that rarely trigger (move to on-demand reference)

**Extract all imperative statements into a flat list.** This makes duplication visible. An 11K-line prompt commonly has the same constraint stated 3-5 different ways.

### Phase 2: Deduplication (10-20% additional reduction)

1. Group semantically similar instructions (embedding similarity or manual)
2. For each group: one canonical version, delete the rest
3. Check for contradictions between surviving instructions
4. If an explicit rule exists AND an example demonstrates it, the example may be cuttable

### Phase 3: Structural Extraction (50-80% per-request reduction)

Split the monolith into a routing core + conditional modules:

```
Core (always loaded, ~200-500 tokens):
  - Agent identity (who, what, for whom)
  - Hard safety constraints (verbatim, never compressed)
  - Universal output format
  - Routing logic: classify request → load relevant module
  - Fallback behavior

Modules (loaded on demand, ~500-2000 tokens each):
  - Domain-specific knowledge per vertical
  - Extended examples per task type
  - Edge case handling per domain
  - Persona voice/style per context
  - Regulatory/compliance per jurisdiction
```

**What to move to tool descriptions (zero cost when tool not called):**
- When to use tool X vs tool Y
- Parameter formats and validation
- Tool-specific error handling
- Output post-processing rules

**What to move to dynamic few-shot (2-3 per request instead of 10):**
- Static examples currently in system prompt
- Retrieve by semantic similarity at inference time
- Or inject single most relevant example in user turn

### Phase 4: Format Optimization (15-30% additional reduction)

| Content Type | Most Efficient Format | Savings vs Prose |
|---|---|---|
| Conditional logic | Pseudocode / if-then | 25-40% |
| Definitions | key: value (no prose) | 30-50% |
| Lookup rules | Markdown table | 20-35% |
| Sequential steps | Numbered list | 10-20% |
| Independent constraints | Bullet list | 10-15% |
| Examples | Labeled input/output pair | 15-25% |

**Pseudocode for rules (25-60% savings on rule-heavy sections):**
```
Natural language (42 tokens):
"If the user asks about billing, check whether they are a premium
subscriber first. If premium, provide detailed account info.
If not, redirect to the help center."

Pseudocode (18 tokens):
if query.topic == billing:
  if user.tier == premium: provide_account_detail()
  else: redirect(help_center)
```

LLMs trained on code understand and follow pseudocode instructions reliably.

**Prose tightening patterns:**
- "In order to" → "To" (saves 2 tokens each)
- "You should try to" → just state the rule
- "It is important that you" → cut entirely
- Passive → active: "Responses should be formatted as" → "Format responses as"
- Establish referent once, then use pronouns

**Markup overhead reduction:**
- XML tags: highest overhead (use only for top-level structure)
- Markdown headers: medium (good default)
- Plain separators (`---`): low
- Consistent indentation only: lowest, but risks ambiguity

### Phase 5: Automated Compression (optional, context sections only)

Apply to per-request injected context (RAG docs, conversation history). NEVER to instruction core.

| Tool | Best Ratio | Use Case |
|---|---|---|
| LLMLingua-2 | 2x-3x | General context, task-agnostic |
| LongLLMLingua | 2x-5x | Long contexts (10K+ tokens) |
| Selective Context | 2x | Simple, low-risk content |
| PCRL | ~1.3x | Conservative instruction compression |

**Critical: Never apply automated compression uniformly.** Safety constraints are disproportionately fragile — even 20% removal causes compliance failures.

### Phase 6: Validation

1. Run full test suite: baseline vs optimized
2. Special attention to safety constraints and edge cases  
3. Monitor output length — increase = confused model (compression paradox)
4. A/B test at low traffic before full rollout
5. Check prompt caching hit rate (should be >70%)

---

## Prompt Caching Architecture

**Structure for maximum cache efficiency:**
```
[STATIC PREFIX — place cache_control breakpoint here]
  Core identity + safety rules
  Tool descriptions
  Universal formatting rules
  Static few-shot examples

[DYNAMIC SUFFIX — no cache_control]
  User context / session state
  Retrieved documents
  Request-specific instructions
```

**Silent failure modes:**
- Dynamic content before static → every request misses cache (observed: 10% hit rate vs expected 80%+)
- Timestamp or user ID in the middle of the static block → invalidates everything after it
- Below minimum token threshold → caching silently does nothing (Claude: 2048-4096 tokens)

**Cost math (Anthropic):**
- Cache read: 10% of base input price (90% discount)
- 5-min cache write: 1.25x base price, refreshes on hit
- 1-hour cache write: 2x base price
- Break-even: 1 read for 5-min, 2 reads for 1-hour
- Most interactive workloads should use 5-min (auto-refreshes)

---

## Common Compression Mistakes

1. **Compressing instructions, leaving context bloat.** The instruction core is the WRONG place to compress. Per-request context (retrieved docs, history) is where compression tools shine.

2. **Trusting compression ratios across models.** Quality at 5x compression on GPT-4o ≠ quality at 5x on DeepSeek (observed: 50x output expansion on DeepSeek at aggressive ratios).

3. **Removing all examples.** Few-shot examples are disproportionately effective per token. Make them dynamic (retrieve when needed) rather than cutting them.

4. **Adding to a monolith instead of modularizing.** Once a prompt exceeds ~2,000 tokens of instructions, progressive disclosure is the right architecture. Every new capability should be a module, not an append.

5. **Optimizing without a baseline.** Tokenize the full prompt, run representative tests, log input/output tokens and success rate BEFORE optimizing. Otherwise you can't tell if changes helped.
