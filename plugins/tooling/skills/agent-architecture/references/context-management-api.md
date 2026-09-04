---
name: context-management-api
description: The exact API primitives for managing agent context — compaction, tool-result clearing, thinking-block clearing, and the memory tool — with parameters, silent-failure modes, and a combined config. Load for long-running agents or context-limit blowups.
---

# Context Management API — Compaction, Clearing, Memory

These are **new server-side primitives**, not prompt tricks. Getting a parameter wrong causes *silent* failures (null summaries, wrong billing, erased memory). Copy strings verbatim. Three tools, used together as a run grows: **clear tool results** (continuous, cheap) → **compact** (full reset) → **memory tool** (durable cross-session).

## Why you need them: the math

Naive loops re-bill the whole accumulated history every turn — a 10-step loop ≈ **43× a single-pass call** (quadratic rebilling); a constrained 2-step window ≈ 29×. Context rot also degrades quality before the 200K wall (often 50K–150K). So you must actively *remove* and *externalize* context, not just let it grow.

## 1. Tool-result clearing (lowest-risk, do this first)

Removes raw tool *results* once processed; keeps the `tool_use` record so the model knows the call happened. Applied **server-side** before the prompt reaches the model — the client keeps full history and does not resync.

```python
{
  "type": "clear_tool_uses_20250919",          # header: anthropic-beta: context-management-2025-06-27
  "trigger": {"type": "input_tokens", "value": 100_000},  # default 100K
  "keep":    {"type": "tool_uses", "value": 3},            # most-recent results to retain (default 3)
  "clear_at_least": {"type": "input_tokens", "value": 15_000},  # min to clear per firing
  "exclude_tools": ["memory"],                  # MANDATORY — never clear memory's paper trail
  "clear_tool_inputs": False                    # also clear tool_use.input if True
}
```
Cleared results become `[cleared to save context]`. **`clear_at_least`** exists because each clear invalidates the cache prefix at the clear point (you pay a cache write next request) — set it high enough that the savings exceed that write cost, else you pay the write for nothing.

**Thinking-block clearing** (`clear_thinking_20251015`) has **tier-dependent defaults**: Opus 4.5+/Sonnet 4.6+ keep ALL prior thinking; Sonnet 4.5-and-earlier and all Haiku keep only the last turn's. Migrating Sonnet 4.5→4.6 silently grows context from accumulated thinking — set `keep` explicitly when spanning tiers.

## 2. Compaction (the full reset)

When clearing isn't enough, summarize the whole transcript and continue from the summary.

```python
{
  "type": "compact_20260112",                   # header: anthropic-beta: compact-2026-01-12
  "trigger": {"type": "input_tokens", "value": 150_000},  # default 150K; min allowed 50K
  "instructions": "<full custom prompt>",       # REPLACES the default — does not append
  "pause_after_compaction": True                # returns stop_reason:"compaction" for inspection (dev)
}
```
Supported: Sonnet 4.6, Opus 4.6/4.7/4.8, Mythos Preview.

**Three traps:**
- **`instructions` REPLACES the default prompt.** If you customize, you must re-include the structural directives — the default wraps the summary in `<summary></summary>` and you'll lose that if you omit it.
- **Tool-call-during-compaction bug:** when `tools` are defined the model may call a tool on the compaction turn instead of summarizing → `compaction.content` is **null**. Fix: add **"Do not call tools; respond with text only"** to `instructions`.
- **Billing:** top-level `input_tokens`/`output_tokens` reflect only the *non-compaction* iteration. **Sum `usage.iterations[*]`** for true cost or you'll massively undercount.

**Preserve in the summary:** architectural decisions + rationale, unresolved bugs/blockers, confirmed quantitative findings, task state + next steps. **Discard:** processed raw tool outputs, concluded intermediate reasoning, repetitive search results. Strategy: *maximize recall first, then tighten for precision.* Cache survival: put `cache_control` on the **system block separate from** the compaction block so the system-prompt cache survives compaction events.

**Compaction alone is insufficient for multi-session continuity** (Anthropic, explicit) — pair it with the memory tool / external files.

## 3. Memory tool (durable, cross-context)

```python
tools = [{"type": "memory_20250818", "name": "memory"}]   # you implement the storage backend
```
Six ops: `view`, `create`, `str_replace`, `insert`, `delete`, `rename`. Model-driven (it decides when to call). The **NOTES.md pattern**: the agent maintains `/memories/NOTES.md` (or `FINDINGS.md`), updating with `str_replace` as facts firm up — this is how Claude-plays-Pokémon tracked state across thousands of steps. **`str_replace` errors if `old_str` matches more than once** (intentional, prevents wrong edits) — agents can loop retrying; write unique anchors or use `insert`+`delete` for big edits. Always `exclude_tools:["memory"]` in clearing config.

## Combined config (clearing fires first, compaction as fallback)

```python
context_management={"edits": [
  {"type": "clear_tool_uses_20250919",
   "trigger": {"type": "input_tokens", "value": 100_000},
   "keep": {"type": "tool_uses", "value": 6},
   "exclude_tools": ["memory"],
   "clear_at_least": {"type": "input_tokens", "value": 15_000}},
  {"type": "compact_20260112",
   "trigger": {"type": "input_tokens", "value": 150_000},
   "instructions": "Preserve decisions, bugs, facts, next steps. Do not call tools; respond with text only."}
]}
```
Lower threshold fires first: continuous clearing delays the heavier compaction reset.

## Choosing the strategy

| Scenario | Use |
|---|---|
| Moderate tool use, single session | Tool-result clearing only |
| Long research run, many iterations | Clearing (100K) + compaction (150K) |
| Multi-session continuity needed | Compaction + memory tool / external files |
| Debugging summary quality | `pause_after_compaction:true` + probe the summary, then re-enable auto |

**Sub-agent discipline (the multi-agent analogue):** a sub-agent that burned tens of thousands of tokens returns a **1,000–2,000 token** distilled summary to the parent; detail goes to files/Memory. Apply tool-result clearing at the *orchestrator* level too (excluding memory) so accumulating sub-agent summaries don't rot the orchestrator's own context.

**On AgentCore:** memory-record injections and retrieved facts are per-turn dynamic — place them **after** the cache breakpoint, never before, or every turn cache-misses. See [`agentcore-mapping.md`](agentcore-mapping.md) for the managed Memory equivalents of these primitives.
