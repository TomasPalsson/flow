# Claude-Specific System Prompt Guidance

## Trust Hierarchy

Claude operates a three-principal trust hierarchy baked in during training:
1. **Anthropic** (training-level) — cannot be overridden by prompts
2. **Operator** (system prompt) — treated like "messages from a relatively trusted employer"
3. **User** (human turn) — lowest trust level

Practical consequence: System prompts don't need to justify rules. Claude follows operator instructions without requiring reasoning unless they cross ethical lines. This saves tokens — skip the "because..." justification for operational rules.

## XML Is the Gold Standard

Claude is explicitly trained to pay special attention to XML-delimited structure. XML produces 15-20% performance gains over plain text on Claude.

**Recommended tags:**
- `<instructions>` — behavioral rules
- `<context>` — background information
- `<constraints>` — hard limits
- `<examples>` — few-shot demonstrations
- `<output_format>` — expected response structure

XML costs ~15% more tokens than equivalent Markdown, but if it improves response quality enough to reduce iteration, total tokens consumed may be lower.

## Adaptive Thinking

Claude 4.6 uses adaptive thinking (`thinking: {type: "adaptive"}`), controlled by the `effort` parameter (`low`, `medium`, `high`, `max`), not by prompt text.

**Non-obvious behaviors:**
- Complex system prompts trigger adaptive thinking MORE FREQUENTLY, increasing latency and cost
- If you want to suppress unnecessary thinking: "Extended thinking adds latency and should only be used for problems requiring multi-step reasoning. When in doubt, respond directly."
- NEVER feed Claude's `<thinking>` block content back as input — Anthropic explicitly states this degrades performance
- Extended thinking can HURT performance by up to 36% on intuitive/pattern-recognition tasks
- `budget_tokens` is deprecated for 4.x models; use `effort` parameter instead
- Minimum thinking budget is 1,024 tokens

## Context Awareness

Claude 4.6 tracks its remaining token budget and may prematurely wrap up work as context fills. If your harness handles compaction:

```
Your context window will be automatically compacted as it approaches its limit,
allowing you to continue working indefinitely. Do not stop tasks early due to
token budget concerns.
```

Without this instruction, the model silently winds down work — a common failure mode in agent harnesses.

## Prompt Caching

**Silent failure thresholds:**
- Opus 4.6/4.5, Haiku 4.5: minimum **4,096 tokens** to cache
- Sonnet 4.6/4.5/4, Haiku 3.5/3: minimum **2,048 tokens**

Below these thresholds, caching silently fails — no error, `cache_creation_input_tokens` stays 0.

**Cache hierarchy:** `tools → system → messages` (strict). Changes cascade downstream:
- Changing tool definitions → invalidates tool + system + message cache
- Changing system text → invalidates system + message cache
- Changing `tool_choice` → invalidates message cache only

**Architecture for caching:** Static content FIRST (identity, base instructions), dynamic content LAST (user context, request-specific data). Any dynamic content before static content destroys cache efficiency.

## Claude Opus 4.5 Word Sensitivity

When extended thinking is disabled, Claude Opus 4.5 is triggered by the word "think" and its variants. Use "consider," "evaluate," or "reason through" to avoid unintentional thinking activation.

## Prefilled Responses Deprecated

Prefilling the last assistant turn is no longer supported in Claude 4.6. Migrate to:
- Structured Outputs for JSON enforcement
- Direct instructions: "Respond directly without preamble."
- XML output tags in instructions

## Anti-Laziness Prompting on Newer Models

Prompts with "CRITICAL: You MUST use this tool when..." were written for older models. Claude Opus 4.5+ over-triggers on these. Replace with normal imperative language: "Use this tool when..."

## `tool_choice` Constraints with Thinking

`tool_choice: any` raises a hard API error when thinking is enabled. Use `tool_choice: auto` with explicit instruction in the user message if you want to encourage a specific tool while thinking is enabled.

## Query Placement in Long Contexts

For prompts with 20K+ tokens of document context, place the query/instruction AFTER the documents (at the bottom) — improves performance by up to 30%.
