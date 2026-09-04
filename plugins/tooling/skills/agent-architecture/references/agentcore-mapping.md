---
name: agentcore-mapping
description: How each agent-architecture pattern maps onto Amazon Bedrock AgentCore primitives — Runtime, Memory, Gateway, Identity, Code Interpreter, Browser, Observability, Policy — with the token/cost implication of each. Load when implementing on AgentCore. Deployment mechanics live in the strands-agentcore skill.
---

# AgentCore Mapping (Architecture Layer)

Each pattern from this skill has a native AgentCore primitive. This file is the *architecture + token-economics* view. **Deployment mechanics — ARM64, port 8080, Dockerfile, IAM trust, `@requires_access_token`, session backends — are in `strands-agentcore`.** Don't duplicate them.

| Architecture need | Primitive | Token/cost effect |
|---|---|---|
| Sub-agent context isolation | Runtime (microVM/session) | clean window per worker |
| Compaction + cross-session memory | Memory | k=3 STM + topK=5 LTM stays flat vs unbounded history |
| Just-in-time tool loading | Gateway `searchType:SEMANTIC` | ≈95% tool-schema token cut at scale |
| Computation offload | Code Interpreter | compute instead of reasoning tokens |
| Web interaction | Browser | extract structured data, not raw HTML |
| Auth without leakage | Identity | secrets never in LLM context |
| Tool authorization | Policy (Cedar) | zero-token guardrail |
| Cost/quality feedback | Observability | per-call token attribution |

## Runtime → sub-agent isolation (orchestrator-workers)

Each microVM (`runtimeSessionId`) is a hardware-isolated CPU/mem/filesystem → clean context per worker, so workers spend tokens only on their task. Spawn N workers = N `invoke_agent_runtime` with distinct session IDs. Limits: **max lifetime 28,800s (8h); idle timeout 900s (15 min)** — call `stop_runtime_session` the moment work finishes to stop idle compute charges. **Reusing a terminated `runtimeSessionId` creates a new empty microVM** — no state carries over; persist anything durable to Memory before the session ends. Use A2A (port 9000) for delegation; see [`multi-agent.md`](multi-agent.md).

## Memory → compaction + long-term extraction

Two **structurally different** stores, not retention tiers:
- **STM** = raw `Event`s scoped to `sessionId`; `get_last_k_turns(k)`; ms latency. k=3 ≈450 tokens, k=20 ≈3,000.
- **LTM** = extracted `MemoryRecord`s scoped to `namespace`; `retrieve_memory_records(searchQuery, topK)`; semantic, survives sessions. topK=3 ≈90 tokens, topK=5 ≈150. **Created asynchronously — 5–10s lag** after `create_event`; do NOT expect LTM current within the same request.

The win: instead of injecting 50 raw turns, inject **k=3 STM + topK=5 LTM ≈ flat regardless of session length** (≈95% vs unbounded history).

**Four built-in strategies:** SEMANTIC (vector facts — replaces a personal-fact vector DB), SUMMARIZATION (rolling conversation summary — the managed compaction equivalent; can itself grow large), USER_PREFERENCE (durable prefs, avoids re-asking), EPISODIC (episodes + `reflectionConfiguration` for higher-order learning). Custom: `semanticOverride` etc. with `appendToPrompt` + separate `modelId` per phase (**use Haiku for extraction *and* consolidation** — write-then-review applied to memory), or `selfManagedConfiguration` (SNS→your Lambda→S3→`batch_create_memory_records`) for regulated data you can't send to a managed extractor.

**Silent failure modes:**
- **Wildcard namespaces return `[]`** (no error). Provide the exact resolved namespace — `actorId` must be a first-class request param. (`search_long_term_memories` takes a `namespace_prefix`; low-level `retrieve_memory_records` needs exact.)
- **Consolidation is a hidden 2nd stage** (extract → dedup/merge). Default consolidation misses domain contradictions ("prefers Go" vs "prefers Python") — supply a domain consolidation prompt.
- `MemorySessionManager` is **not thread-safe** — one instance per thread/request.
- Provisioning takes 2–3 min — use `create_or_get_memory()` (idempotent) / `create_memory_and_wait()` (polls ≤300s).
- **Not available in `agentcore dev`** — mock locally, test against deployed.
- Expiry `eventExpiryDuration` 7–365 days: **SDK default 90, CLI `--expiry` default 30**. Batch ops ≤100 records/call. Tune `relevance_score` (e.g. 0.3) to drop 40–60% low-relevance records and curb context bloat.

The **orchestrator plan-persistence pattern**: lead saves its plan to Memory at session start, retrieves it after compaction near 200K — needs `actorId`/`sessionId` injected at startup. Strands integration: `MemoryHook` (STM, framework-managed) vs `MemorySessionManager.process_turn_with_llm` (atomic retrieve→LLM→store, includes LTM) vs low-level `MemoryClient` (batch/control-plane).

## Gateway → just-in-time tool loading + federation

Managed MCP server turning Lambda / OpenAPI / Smithy / API Gateway / upstream MCP into one endpoint (solves the N×M integration problem; handles per-target outbound auth). **`searchType:SEMANTIC`** indexes tool metadata as vectors; the agent calls one tool `x_amz_bedrock_agentcore_search(query)`, gets back 3–15 relevant tools, calls those. Give the agent ONLY the search tool — exposing the full catalog defeats it.
- **Token economics:** 268-tool catalog @ ~500 tokens each = 134K loaded vs ≈6K via search → ≈95% cut (sample-repo benchmark; *reported*). Smaller 26-tool benchmark ≈70% (6,010→1,814; single-author). Conservative general range ≈40–60%. **Break-even ≈30 tools** — below that, the extra search round-trip costs more than it saves.
- **`searchType` is PERMANENT** — set at creation; to change, delete and recreate the gateway *and all targets*. Decide upfront.
- Tool name `${target}___${tool}` (three underscores); schemas self-contained (no `$ref`/`$defs`); upstream MCP must support protocol `2025-06-18` or `2025-03-26`; sync is not live — call `synchronize_gateway_targets` after upstream changes (build it into CI/CD); `UpdateGateway` needs all original fields. Target outbound auth matrix: Lambda = IAM only; mcpServer = OAuth-CC/None; openApi/Smithy = OAuth-CC/AC + API key/IAM. Credentials stored in Identity, referenced by ARN — inline secrets are rejected by the API. Interceptors (request/response Lambdas) for JWT-scope filtering / PII redaction / tenant injection — keep them fast, they run on every call.

## Identity → auth without context pollution

`@requires_access_token` / `@requires_api_key` / `@requires_iam_access_token` inject credentials *inside* the agent function at call time from the Token Vault — never into tool results, system prompt, or conversation history. M2M (client-credentials, 2LO) for server-to-server; User-Federation (auth-code, 3LO) for acting on a user's behalf (needs `allowedResourceOauth2ReturnUrls`). Resource-based policies on Runtime/Endpoint/Gateway ARNs enable cross-account / multi-tenant invocation without sharing IAM roles. (Decorator mechanics + the programmatic OAuth-URL workload pattern: `strands-agentcore`.)

## Code Interpreter → computation offload

`start_code_interpreter_session` + `invoke_code_interpreter(executeCode, python)`; numpy/pandas/matplotlib preinstalled; 900s default / 28,800s max. A calc that costs 500–2,000 reasoning tokens returns in tens of tokens — and **deterministic output eliminates numeric hallucination**. Offload: arithmetic, stats, sorting/filtering, regex, JSON transforms, answer self-verification. Call `stop_code_interpreter_session` when done.

## Browser → web-interaction offload

`start_browser_session` → CDP WebSocket (Playwright / Nova Act). Extract structured data via `page.evaluate()` (tens–hundreds of tokens) instead of dumping 5K–50K tokens of raw HTML that blows the 25K tool-result cap. Live-view + human-takeover = the HITL checkpoint for browser tasks; recordings as NDJSON in S3.

## Policy (Cedar) → zero-token tool authorization

PolicyEngine on a Gateway evaluates Cedar per `tools/call` — the guardrail layer for autonomous agents (constrains what an identity *can* invoke even if prompted to do more), at sub-ms and **zero LLM tokens**. **Always start `LOG_ONLY`, inspect CloudTrail/CloudWatch, then `ENFORCE`.** Cedar is default-deny; `forbid` overrides `permit`; `ALLOW_ALL`/`DENY_ALL` findings block creation under `FAIL_ON_ANY_FINDINGS`. AI-generated policies (`policy_generation_start`) auto-delete after **7 days** — promote valid ones immediately.

## Observability → the cost feedback loop

OTel via `aws-opentelemetry-distro` → CloudWatch Transaction Search + GenAI dashboard. Captures **per-call token usage**, latency, errors, tool timing — the signal that exposes tool-bloat and raw-output-passthrough waste. Correlate turns with `baggage.set_baggage("session.id", id)`. Sample 100% briefly to baseline, then 1–5%. Non-Runtime agents: `AGENT_OBSERVABILITY_ENABLED=true` + OTel env + `opentelemetry-instrument`. Cost the trade-offs first: `python scripts/token_cost_calculator.py`.

## Pattern → primitive quick map

| Anthropic pattern | AgentCore implementation |
|---|---|
| Just-in-time retrieval (tools) | Gateway `searchType:SEMANTIC` |
| Compaction / external memory | Memory SUMMARIZATION / SEMANTIC / EPISODIC |
| Sub-agent isolation | Runtime microVM per session + A2A |
| Computation offload | Code Interpreter |
| Tool-result bounding | Lambda target with `response_format` + interceptors |
| Verification / guardrails | Policy Engine (`LOG_ONLY`→`ENFORCE`) |
