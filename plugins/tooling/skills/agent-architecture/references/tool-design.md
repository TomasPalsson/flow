---
name: tool-design
description: Designing tools and MCP for agents — consolidation, namespacing, response_format, dynamic tool loading (Tool Search Tool), programmatic tool calling, count thresholds, and error design. Load when building/auditing tools or hitting tool-selection errors.
---

# Tool Design for Agents

Tools are contracts between a deterministic system and a non-deterministic reasoner — **not human APIs**. Anthropic's five principles: choose the right tools (workflows, not endpoints), namespace them, return meaningful context, optimize token efficiency, prompt-engineer the descriptions. Tool-description refinement *alone* drove Sonnet 3.5 to SWE-bench SOTA and cut task time ≈40% in the multi-agent research system — descriptions are prompt real estate, not docs.

## Consolidate around intents, not endpoints

Build tools for what the agent is trying to *do*. `schedule_event` (looks up availability + books in one call) beats `list_users`+`list_events`+`create_event` (three selection decisions, three result blobs). `get_customer_context` replaces `get_customer_by_id`+`list_transactions`+`list_notes`. **Five sharp tools beat twenty overlapping ones** — overlapping tools make the model debate which to use and pick wrong. Rule: *if a human engineer can't say which tool applies in a situation, the agent can't either.* Find consolidation targets by logging tool-call sequences in evals — a repeated A→B→C is one tool.

## Tool count is an architecture signal

- **≤~20 loaded at once:** fine.
- **~20:** reconsider — consolidate or switch to dynamic loading. (Vercel removed 80% of tools and completion rates rose.)
- **30–50 (all loaded):** selection-accuracy cliff; wrong-tool selection becomes the dominant failure, and schemas alone can burn 50K+ tokens before the first user message (a 5-server MCP setup ≈ 55,000 tokens of definitions).
- **1,000s (MCP hubs):** dynamic loading mandatory.

Decision: `<10 always-used` → static; `10–30` → keep 3–5 core static, defer the rest; `30+ or >10K schema tokens` → Tool Search Tool / Gateway SEMANTIC.

## Return meaningful context

Resolve **UUIDs → semantic names** ("significantly improves Claude's precision in retrieval" — Anthropic). Return the human-readable name *and* the ID only when a downstream call needs the ID. **Prefix-namespace** (`asana_projects_search` > `search_asana` > `search`) — prefix-vs-suffix has non-trivial eval impact; one-line change. Pagination state in words ("page 3 of 7"), not opaque cursors.

## response_format enum (build into every variable-size tool)

```json
{"response_format": {"type": "string", "enum": ["concise", "detailed"], "default": "concise"}}
```
Slack-thread example: concise **72** vs detailed **206** tokens (≈65% off). Concise keeps semantic fields (`name`, `file_type`); excludes opaque ones (`uuid`, `mime_type`) — but **still return any ID a downstream call requires**, even in concise mode, or you break multi-step workflows.

## Error messages as steering prompts

The last defense against retry loops. ❌ `ERROR 429` / raw traceback → the model retries identically. ✅ `Found 847 expenses. Narrow the date range or add a category filter.` Include the correct input-format example. Also return explicit **terminal states** — `SUCCESS: booking HT79265 confirmed`, `FAILED: fully booked — no retry will succeed`, `PARTIAL: 3 of 10 found, rest don't exist`. Clear terminal states cut one task from 14 tool calls to 2 in AWS's experiment.

## Dynamic tool loading — Tool Search Tool

`betas=["advanced-tool-use-2025-11-20"]`. Mark catalog tools `defer_loading:true`; **never** defer the search tool itself (all-deferred → 400). Keep 3–5 most-used tools non-deferred. Returns 3–5 relevant tools/search; max catalog 10,000. Deferred tools live in the system-prefix and **don't consume context until discovered — caching is preserved**.
- Variants: `tool_search_tool_regex_20251119` (Python `re.search`, ≤200 chars, `(?i)` for case-insensitive) vs `tool_search_tool_bm25_20251119` (natural language). Regex for consistent namespaced catalogs; BM25 for varied naming.
- Accuracy: Opus 4 49→74%, Opus 4.5 79.5→88.1%; >85% context reduction (≈191K vs 122K tokens preserved in one benchmark — *reported*).
- **Incompatible with `tool_use_examples`** (server-side variant) — inline examples into descriptions instead, or use a client-side search returning `tool_reference` blocks. On Bedrock: **InvokeModel only, not Converse**.

## Programmatic Tool Calling (code execution)

`"allowed_callers": ["code_execution_20250825"]` per tool. Claude writes Python that calls tools as functions in a sandbox; only the script's **output** enters context — 20 sequential calls become 1 inference pass. Reported: complex research 43,588→27,297 tokens (37%); Drive→Salesforce 150,000→2,000 (98.7%). Cost: sandbox infra + security surface. Best for data processing, multi-step dependent calls, filtering before context entry; worse for interactive branching logic.

## tool_use_examples (few-shot)

1–5 `input_examples` per tool → ≈72%→90% accuracy on complex params. Use realistic domain data (ISO dates, currency codes). Incompatible with server-side Tool Search (see above).

## Let Claude optimize your tools

Paste eval transcripts into Claude Code, ask it to find failure patterns and refactor all tool definitions at once, re-run evals. Works because Claude has seen vast API docs and can spot idiomatic, selection-friendly descriptions.

## AgentCore Gateway specifics (when tools live behind Gateway)

- Tool name is `${target}___${tool}` (**three underscores**) — never hardcode; construct from the listed names. Lambda handlers must strip the prefix before routing.
- Schemas must be **self-contained**: no `$ref`/`$defs`/`$anchor`/`$dynamicRef`/`$dynamicAnchor`, or the target silently sticks in `SYNCHRONIZE_UNSUCCESSFUL`. Inline/bundle refs first.
- `searchType: SEMANTIC` is the managed Tool Search equivalent — give the agent only `x_amz_bedrock_agentcore_search`, never the full catalog. **searchType is permanent** (recreate gateway to change). Break-even ≈30 tools.
- `UpdateGateway` is NOT a PATCH — pass all original fields (always `gateway_get` first) or they're silently cleared.
- Auth is per-target Gateway config — tool params stay task-focused, never carry `api_key`. See [`agentcore-mapping.md`](agentcore-mapping.md).
