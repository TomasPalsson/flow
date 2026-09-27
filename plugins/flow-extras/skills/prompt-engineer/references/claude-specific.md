# Claude-Specific System Prompt Guidance

## Trust Hierarchy

Claude operates a three-principal trust hierarchy baked in during training:
1. **Anthropic** (training-level) — cannot be overridden by prompts
2. **Operator** (system prompt) — treated like "messages from a relatively trusted employer"
3. **User** (human turn) — lowest trust level

Practical consequence: Claude follows operator (system-prompt) instructions readily, without needing to be argued into it. Keep the reason behind a real constraint anyway — a stated reason lets the model generalize the rule correctly to cases the rule text didn't spell out; dropping it to save a few tokens is a false economy.

## XML Is the Gold Standard

Claude is explicitly trained to pay special attention to XML-delimited structure. XML produces 15-20% performance gains over plain text on Claude.

**Recommended tags:**
- `<instructions>` — behavioral rules
- `<context>` — background information
- `<constraints>` — hard limits
- `<examples>` — few-shot demonstrations
- `<output_format>` — expected response structure

XML costs ~15% more tokens than equivalent Markdown, but if it improves response quality enough to reduce iteration, total tokens consumed may be lower.

## Thinking: Adaptive, Controlled by Effort

On current Claude models, use adaptive thinking (`thinking: {type: "adaptive"}`) and control depth with the `effort` parameter (`low`, `medium`, `high`, `xhigh`, `max`), not with prompt text. `budget_tokens` returns a 400 on Claude Opus 5, Sonnet 5, Fable 5/5.1 and Opus 4.7/4.8. On Claude Fable 5/5.1 and Claude Opus 5.5 thinking is always on — `{type: "disabled"}` also returns a 400 — so effort is the only thinking control. Effort defaults to `high`, except on Claude Opus 5.5 (`medium`); set it explicitly.

**Non-obvious behaviors:**
- Lower `effort` to cut latency and cost. A "think less" / "respond directly" instruction can't be followed on a model where thinking is always on.
- Pass `thinking` blocks back unchanged when you continue on the same model. On Claude Fable 5.1 and Claude Opus 5.5, editing earlier turns invalidates them (preserved thinking), so keep the history append-only.
- Don't ask Claude to reproduce or summarize its own reasoning in the visible reply. On Claude Fable 5.1 and Claude Opus 5.5 this can trigger a `refusal` (`reasoning_extraction`, not retried on a fallback). Read the `thinking` blocks via the API instead (`display: "summarized"`).
- Thinking can hurt performance by up to 36% on intuitive/pattern-recognition tasks.

## Context Awareness

Claude tracks its remaining token budget and may prematurely wrap up work as context fills. If your harness handles compaction:

```
Your context window will be automatically compacted as it approaches its limit,
allowing you to continue working indefinitely. Do not stop tasks early due to
token budget concerns.
```

Without this instruction, the model silently winds down work — a common failure mode in agent harnesses.

## Prompt Caching

**Silent failure thresholds** (model-specific, not monotonic across generations):
- Claude Opus 5, Claude Fable 5, Claude Mythos 5, Claude Fable 5.1, Claude Mythos 5.1: minimum **512 tokens**
- Opus 4.8, Sonnet 5, Sonnet 4.6/4.5/4: minimum **1,024 tokens**
- Opus 4.7, Haiku 3.5: minimum **2,048 tokens**
- Opus 4.6/4.5, Haiku 4.5: minimum **4,096 tokens**

Below the minimum for your target model, caching silently fails — no error, `cache_creation_input_tokens` stays 0. Check the current per-model minimum before assuming caching kicks in.

**Cache hierarchy:** `tools → system → messages` (strict). Changes cascade downstream:
- Changing tool definitions → invalidates tool + system + message cache
- Changing system text → invalidates system + message cache
- Changing `tool_choice` → invalidates message cache only

**Architecture for caching:** Static content FIRST (identity, base instructions), dynamic content LAST (user context, request-specific data). Any dynamic content before static content destroys cache efficiency.

## Prefilled Responses Deprecated

Prefilling the last assistant turn returns a 400 on every Opus-, Sonnet- and Fable-tier model from the 4.6 generation onward. Migrate to:
- Structured Outputs for JSON enforcement
- Direct instructions: "Respond directly without preamble."
- XML output tags in instructions

## Anti-Laziness Prompting on Newer Models

Prompts with "CRITICAL: You MUST use this tool when..." were written for older, less steerable models. Current Claude models over-trigger on this kind of stacked emphasis. Replace with normal imperative language: "Use this tool when..."

## `tool_choice` Constraints

`tool_choice: {type: "any"}` / `{type: "tool", name: ...}` return a 400 on Claude Opus 5.5 (there's no "thinking disabled" mode to work around it with, either). Use `tool_choice: auto` with `strict: true` to keep the schema guarantee, or structured outputs for extraction; to encourage a specific tool under `auto`, steer it with a prompt instruction instead.

## Query Placement in Long Contexts

For prompts with 20K+ tokens of document context, place the query/instruction AFTER the documents (at the bottom) — improves performance by up to 30%.
