---
name: token-economics
description: Exact token-cost mechanics for Claude agents — prompt caching, model routing, batch API, structured outputs, extended thinking billing, and per-request tool overhead. Load when cutting cost, debugging caching, or budgeting.
---

# Token Economics — Exact Mechanics

Mid-2026 figures. **Verify live pricing before budgeting.** Three independent dials: **what model** (routing), **what you reuse** (caching), **what you skip** (batch / structured outputs / pruning). They compound multiplicatively.

## Prompt caching — the foundational 90% reducer

The cache stores the KV state of a **prefix**, keyed by a cumulative prefix hash up to each `cache_control` breakpoint. A hit needs an identical hash.

**Pricing multipliers (vs base input):** read **0.1×** · 5-min write **1.25×** · 1-hour write **2.0×**.
Break-even: 5-min pays off after **1** read; 1-hour after **2** reads.

| Model | base in | 5m write | 1h write | read |
|---|---|---|---|---|
| Opus 4.5–4.8 | $5.00 | $6.25 | $10.00 | $0.50 |
| Sonnet 4.5/4.6 | $3.00 | $3.75 | $6.00 | $0.30 |
| Haiku 4.5 | $1.00 | $1.25 | $2.00 | $0.10 |

**Rules that silently cost you money if violated:**
- **Order is enforced: `tools → system → messages`.** A change in an earlier section invalidates that section *and everything after it*. Modifying one tool definition = full miss. Changing `tool_choice` (auto↔any↔named) invalidates system+messages. Adding/removing images invalidates messages.
- **Max 4 explicit breakpoints.** Automatic caching (Anthropic API only) consumes one slot.
- **20-block lookback.** From a breakpoint the system scans back ≤20 content blocks for a match. A turn-1 breakpoint becomes a miss by ~turn 21 — add a second breakpoint at a later stable position.
- **Minimum tokens to cache (cumulative across tools+system+messages, NOT per section):** 1,024 (Sonnet 4.x, Opus 4.8/4.1/4) · 4,096 (Opus 4.5/4.6/4.7, Haiku 4.5) · 2,048 (Haiku 3.5). Below the min, `cache_creation_input_tokens` returns **0 with no error** — the #1 silent failure. Counter-intuitive: **Haiku 4.5 needs MORE tokens (4,096) than Sonnet (1,024)** — small Haiku prompts may not cache at all.
- **Place static first, volatile (latest user turn, timestamps) LAST and uncached.**
- **1-hour entries must appear before 5-minute entries** in the prompt.
- **Verify:** `cache_creation_input_tokens > 0` on call 1, `cache_read_input_tokens > 0` after. `input_tokens` ≠ total — total = `input + cache_read + cache_creation`; budgeting off `input_tokens` alone undercounts and breaks context-window math.
- **Cache reads are excluded from ITPM rate limits** (Sonnet 4.x+) — enables high-throughput shared-context agents.
- **Pre-warm** with `max_tokens: 0` (NOT with streaming, extended thinking, structured outputs, `tool_choice:any|tool`, or batch).
- **Workspace isolation since Feb 5 2026** on direct API / Claude-on-AWS / MS Foundry; Bedrock & Vertex are org-level only.
- **JSON key-order non-determinism (Go/Swift maps) breaks the hash** — serialize tool schemas with sorted keys.

**Bedrock differences:** NO automatic caching (explicit `cache_control` / `cachePoint` only); 1-hour TTL only on Opus 4.5 / Sonnet 4.5 / Haiku 4.5 (not 3.7 Sonnet, 3.5 Sonnet v2, Opus 4, Sonnet 4.6); **CRIS scatters cache across regions** (pin a region for cache-critical work); **Nova auto-caching = latency only, no cost discount** unless you add explicit `cachePoint` markers; batch inference does NOT cache (markers silently ignored).

## Model routing — the 3–5× tier dial

| Model | input $/MTok | output $/MTok | vs Haiku in |
|---|---|---|---|
| Haiku 4.5 | $1 | $5 | 1× |
| Sonnet 4.5/4.6 | $3 | $15 | 3× |
| Opus 4.5–4.8 | $5 | $25 | 5× |

Output ≈ 5× input everywhere. **Route:** Haiku = search/grep, extraction from known schemas, classification, routing, simple summary. Sonnet = code review, security scan, plan/test generation, multi-step reasoning. Opus = novel architecture, hard cross-file debugging, multi-domain synthesis, or where Sonnet already failed. **Escalate conditionally** (run cheap, escalate only when output is flagged wrong) — retry-at-same-tier never helps, just doubles cost. Note: Opus often solves in *fewer* tokens, so for deep reasoning it can be net-cheaper per *solved task* despite higher per-token price.

## Batch API — flat 50% off

All tokens, all models. ≤100,000 requests / 256 MB; results within 24h (usually <1h), retained 29 days. **Stacks with 1-hour caching → ≈95% off real-time Opus.** No streaming, no `max_tokens:0`, no fast mode. Same output quality as real-time. Use for evals, doc pipelines, bulk generation — never interactive loops.

## Structured outputs

Schema compiled to a generation grammar (model literally cannot violate it). First use ≈100–300 ms compile, then cached server-side 24h. Saves ≈20–40% output tokens vs prompted-JSON and removes ≈1–5% parse-retry failures. Worth it for any extraction/classification running >100 calls. Incompatible with `max_tokens:0`.

## Extended thinking — billing discipline

You are billed for **full thinking tokens generated**, not the summarized display — `display:"summarized"` shows hundreds but bills thousands; `display:"omitted"` shows nothing but still bills. Streaming required when `max_tokens > 21,333`. `budget_tokens` is deprecated on Opus 4.6+/Sonnet 4.6+; use `thinking:{type:"adaptive"}` + `effort: low|medium|high|xhigh` (default `medium`). **Disable thinking entirely on routine/Haiku paths** — 10K thinking tokens on Opus ≈ $0.25/call = $25K/day at 100K calls. On Haiku/pre-4.5 Sonnet, thinking blocks are stripped in multi-turn and **silently invalidate the messages cache every turn**.

## Per-request overhead you forget to count

Tool system-prompt overhead is added on **every** request with tools: Opus 4.8 auto 290 / any 410; Opus 4.7 auto 675; Sonnet 4.5/4.6 auto ≈497 / any ≈589; Haiku 4.5 auto 496. Plus text-editor +700, bash +245, computer-use +735/definition. A Sonnet agent at 1,000 calls/day with `tool_choice:auto` ≈ +497K input tokens/day just in overhead — drop unused tools to reclaim it. **Opus 4.7+ uses a new tokenizer: up to +35% tokens for the same text** — recompute min-cache-threshold checks when migrating.

## Tool-result verbosity

Claude Code caps tool responses at **25,000 tokens** by default (≈ an explicit architecture decision, not a perf limit). Add `response_format: concise|detailed` (≈72 vs 206 tokens). A 10K-token result re-enters context every subsequent turn — 20 turns = 200K billed tokens. Cap at ≈5K, return summaries + IDs, paginate, and make truncation messages *steer* ("exceeded 5K tokens; add a date filter").
