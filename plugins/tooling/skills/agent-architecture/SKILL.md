---
name: agent-architecture
description: "Architecture and token-economics for Claude agents: workflow vs agent vs multi-agent selection; subagent count; tool & MCP design; prompt caching; model routing; context-window blowup; AgentCore Runtime/Memory/Gateway/Identity/Code Interpreter/Observability. Use when: agent is too expensive/slow/forgets/loops; cutting token spend (caching, compaction, tool-result clearing, dynamic tool loading); context rot; tool count/federation; managing agent memory. Delivers Anthropic decision trees, exact token-cost mechanics, and AgentCore primitive mappings. Do NOT use for AgentCore deployment mechanics (containers, port 8080, ARM64, IAM, OAuth decorators, session backends) — use strands-agentcore instead."
---

# Agent Architecture & Token Economics

This skill is the **architecture and token-economics layer** above deployment. It answers *what to build and why*, and *how to make it cheap without making it dumb*. For *how to ship it on AWS* (containers, port 8080, ARM64, IAM, `@requires_access_token`, session backends), defer to the **`strands-agentcore`** skill — this skill cross-references it rather than repeating it.

All figures here are dated to mid-2026 and tiered by confidence: **stated as fact** = corroborated against Anthropic/AWS primary docs; **"≈" / "reported"** = single credible source; **"rule of thumb"** = practitioner heuristic, directional only. Verify pricing against the live pricing page before budgeting — model prices move.

---

## The one mental model: token economics *is* the architecture

On Anthropic's BrowseComp evaluation, **token usage alone explained 80% of performance variance**; tokens + tool-call count + model choice together explained 95%. The architectural consequence inverts most engineers' instinct:

> The primary lever is not clever routing or prompt wording. It is ensuring the agent can spend its tokens on **real work** rather than **overhead** (loading every tool, re-reading verbose tool results, dragging dead context forward). Token *waste* is the principal failure mode; token *budget spent on the right thing* is the principal win.

Two corollaries that should shape every decision below:
- **Context is not neutral.** Every irrelevant token actively degrades the rest. Attention is n² — 10K tokens = 100M pairwise relationships, 100K = 10B — so a 90%-full window has far less than 90% of an empty window's reasoning power. **Context rot is a gradient, not a cliff**; degradation can begin at 50K–150K tokens, well before the 200K wall.
- **More structure = more cost AND more reliability — pick the least structure that passes evals.** Single call → workflow → agent → multi-agent each multiply tokens; each also multiplies the error surface. Escalate only on *measured* failure, never on "I think it won't work."

---

## Before you build: the escalation ladder (Anthropic's "start simple")

Walk DOWN this ladder. Stop at the first rung that passes your evals. Do **not** skip ahead. **MANDATORY when designing or choosing an architecture — open and fill in [`scripts/decision-ladder.md`](scripts/decision-ladder.md)**: it forces the "measured, not assumed" gate at each rung and records *why* you chose one, so the decision isn't re-litigated later.

```
1. Single optimized LLM call  (+ retrieval + in-context examples)
        ↓ measured insufficient?
2. Workflow                   (predefined code paths; LLM at fixed steps)
        ↓ steps can't be predetermined?
3. Single autonomous agent    (model drives its own loop: gather → act → verify → repeat)
        ↓ proven insufficient for THIS task?
4. Multi-agent (orchestrator-workers)
```

**The operative question for rung 2 vs 3 — memorize it:** *Can the step count and sequence be determined before execution begins?* **Yes → workflow** (deterministic, cheap, debuggable). **No → agent** (needs environmental feedback to self-correct).

**The gate for rung 4** (ALL must hold, else stay single-agent): task is breadth-first with genuinely independent parallel threads; value justifies ≈15× chat token cost; subtasks need little shared context; work overflows one 200K window. **Coding usually fails this gate** — Anthropic states coding has few parallelizable components and shared mutable repo state, so coordination overhead dominates. Multi-agent is for *research/breadth*, not *building*. **STOP — before committing to rung 4, complete the rung-4 section of [`scripts/decision-ladder.md`](scripts/decision-ladder.md) and run the cost comparison** (`python scripts/token_cost_calculator.py … --multiagent`); if you can't check all four boxes with evidence, stay on rung 3.

---

## Decision 1 — Which workflow pattern? (rung 2)

| Situation | Pattern | Token/latency note |
|---|---|---|
| Fixed known sequence of steps | **Prompt chaining** (+ programmatic gates between steps) | Serial latency; lower per-step cost; gates catch errors before they propagate |
| Distinct input categories need different handling | **Routing** | Only helps if classifier ≈>90% accurate — measure it first, a misroute gets the wrong specialist |
| Independent subtasks, speed matters | **Parallelization: sectioning** | Wall-clock = slowest branch, not sum; total tokens still N× |
| High-stakes answer needs confidence | **Parallelization: voting** (N=3–5) | N× cost — justify with consequence of being wrong |
| Subtasks unknown until runtime | **Orchestrator-workers** | This is rung 4 territory; see multi-agent reference |
| Output iteratively improvable with a *reliable* checker | **Evaluator-optimizer** | Needs BOTH: LLM can improve output AND can reliably judge it — missing either makes it a random walk |

First lever before any of this: **parallel tool calls *within* one agent** (3+ at once) — up to ≈90% wall-clock reduction with no architecture change.

---

## Decision 2 — Cut tokens without cutting quality

Apply in this order (biggest, safest wins first). Full mechanics + exact prices: **load [`references/token-economics.md`](references/token-economics.md)**.

1. **Prompt caching** — 90% read discount on the stable prefix (system + tools). Single highest-leverage lever. Easy to silently break (see cheat-sheet + symptom index).
2. **Right-size the model per role** — route mechanical work to Haiku, reasoning to Sonnet, novel/hard to Opus; escalate *conditionally* (run cheap first, escalate only when flagged wrong). Never blanket-Opus a router.
3. **Bound tool results** — `response_format: concise|detailed` (72 vs 206 tokens ≈65% off), pagination, truncation with steering messages; cap ≈5K tokens, never dump raw payloads.
4. **Manage context** — tool-result clearing → compaction → external memory, as the run grows. New API primitives: **load [`references/context-management-api.md`](references/context-management-api.md)**.
5. **Shrink the tool surface** — dynamic tool loading once you pass ~20 tools. See [`references/tool-design.md`](references/tool-design.md).
6. **Offload computation to code** — anything with a provably correct answer (math, sorting, parsing, dedup) is a tool/code call, not reasoning tokens.
7. **Defer the deferrable** — Batch API = flat 50% off for non-interactive work; stacks with 1h caching toward ≈95% off real-time.

---

## Decision 3 — Tool & MCP design

Tools are contracts between deterministic systems and a non-deterministic reasoner — not human APIs. **Load [`references/tool-design.md`](references/tool-design.md)** when designing/auditing tools or hitting selection errors. Headlines:
- Build tools for **agent intents/workflows, not API endpoints** (`schedule_event`, not `list_users`+`list_events`+`create_event`). Five sharp tools beat twenty overlapping ones.
- **Tool count is an architecture signal:** ≤~20 fine; **20 = reconsider** (consolidate or load dynamically); **30–50 = selection-accuracy cliff** when all loaded at once.
- Return **semantic names, not raw UUIDs**; **prefix-namespace** (`asana_projects_search` > `search`); make **error messages steer** the next call.

---

## Decision 4 — Implement on Amazon Bedrock AgentCore

Each architecture pattern has a native AgentCore primitive. **Load [`references/agentcore-mapping.md`](references/agentcore-mapping.md)** when targeting AgentCore. Map at a glance:

| Architecture need | AgentCore primitive | Token/cost effect |
|---|---|---|
| Sub-agent context isolation | **Runtime** (microVM per `runtimeSessionId`) | Clean window per worker; isolate then return a 1–2K summary |
| Compaction + cross-session memory | **Memory** (4 strategies; STM `get_last_k_turns` + LTM `retrieve_memory_records`) | k=3 STM + topK=5 LTM stays ~flat vs unbounded history |
| Just-in-time tool loading | **Gateway** (`searchType: SEMANTIC`) | ≈95% tool-schema token cut at 268 tools; `___` naming; **searchType is PERMANENT** |
| Computation offload | **Code Interpreter** | Spend compute not tokens; kills numeric hallucination |
| Auth without token leakage | **Identity** (`@requires_*` decorators) | Secrets never enter LLM context |
| Cost/quality feedback loop | **Observability** (OTel → CloudWatch) | Per-call token attribution — find waste before the bill |

> Deployment specifics (ports, ARM64, Dockerfile, IAM, OAuth flows, session backends) live in **`strands-agentcore`** — do NOT duplicate that work here.

---

## Reference loading guide

| File | Load WHEN | Do NOT load when |
|---|---|---|
| [`references/token-economics.md`](references/token-economics.md) | Cutting cost; caching; model routing; budgeting; "agent too expensive" | Pure architecture-shape questions with no cost concern |
| [`references/context-management-api.md`](references/context-management-api.md) | Long-running agent; compaction/clearing/memory-tool; context limit blowups | Short single-shot tasks |
| [`references/tool-design.md`](references/tool-design.md) | Designing/auditing tools or MCP; selection errors; tool bloat | No tools involved |
| [`references/multi-agent.md`](references/multi-agent.md) | Considering/building multi-agent; subagent scaling; A2A | Confirmed single-agent task |
| [`references/agentcore-mapping.md`](references/agentcore-mapping.md) | Implementing on Bedrock AgentCore | Provider-agnostic design; non-AWS target |
| [`references/anti-pattern-gallery.md`](references/anti-pattern-gallery.md) | Something is broken/expensive/slow and you want the cause | Greenfield design (use the ladder above instead) |
| [`scripts/decision-ladder.md`](scripts/decision-ladder.md) | **MANDATORY** when choosing/justifying an architecture rung | After the rung is decided and recorded |
| [`scripts/token_cost_calculator.py`](scripts/token_cost_calculator.py) | Budgeting; caching break-even; single-vs-multi cost delta | No cost/budget question in play |

When a reference is needed, **read the ENTIRE file** — these are dense and load-bearing; do not range-limit them.

---

## API cheat-sheet — copy these EXACTLY (low freedom: a wrong char silently no-ops)

Architecture choices above are judgment calls. The strings below are **not** — one wrong byte and the feature silently fails (no error). Copy verbatim; full context in the references.

```
Prompt caching:    order tools→system→messages; static first, volatile LAST.
                   read 0.1× · 5m-write 1.25× · 1h-write 2.0× · max 4 breakpoints
                   20-block lookback (turn-1 breakpoint misses by ~turn 21 → add a 2nd)
                   min-to-cache: 1,024 (Sonnet 4.x, Opus 4.8/4.1/4) · 4,096 (Opus 4.5/4.6/4.7, Haiku 4.5) · 2,048 (Haiku 3.5)
                   verify: cache_creation_input_tokens>0 then cache_read_input_tokens>0
                   Bedrock: NO auto-caching (explicit only); 1h TTL only on 4.5-tier; CRIS scatters cache
Compaction:        type "compact_20260112"  header "anthropic-beta: compact-2026-01-12"
                   trigger default 150K / min 50K; `instructions` REPLACES default prompt
                   add "Do not call tools; respond with text only"; sum usage.iterations for true cost
Tool-result clear: type "clear_tool_uses_20250919"  header "context-management-2025-06-27"
                   keep:N · clear_at_least:tokens · exclude_tools:["memory"]  ← mandatory
Memory tool:       type "memory_20250818" (6 ops: view/create/str_replace/insert/delete/rename)
Tool Search Tool:  header "advanced-tool-use-2025-11-20"; defer_loading:true on deferred tools
                   (NEVER on the search tool itself); regex_20251119 | bm25_20251119
Programmatic tools: "allowed_callers": ["code_execution_20250825"]
Token-efficient:   header "token-efficient-tools-2025-02-19"  (confirmed Claude 3.7 Sonnet; 4.x unconfirmed)
AgentCore Gateway: tool name = ${target}___${tool} (THREE underscores); schemas self-contained (no $ref/$defs)
```

Estimate cost / caching break-even / multi-agent comparison before committing:
`python scripts/token_cost_calculator.py --model opus-4.8 --input 30000 --output 800 --calls-per-day 5000 --cache-hit 0.8`

---

## Symptom → cause → fix (debug index)

When something is already broken, start here, then **MANDATORY — READ ENTIRE FILE**: load [`references/anti-pattern-gallery.md`](references/anti-pattern-gallery.md) for the full entry (root cause + AgentCore mapping). The `why` column carries the non-obvious mental model — the part that stops the bug recurring.

| Symptom | Cause + the non-obvious *why* | First move |
|---|---|---|
| Bill 10–50× expected | Blanket-Opus / no caching / unbounded tool results / uncapped loop. *Why:* cost is cumulative — a 4-turn chat bills ≈10× turn-1 because each turn re-bills all prior context | Cache; route models; cap tool results ≈5K; set max-iterations |
| `cache_read_input_tokens` stays 0 | Dynamic content before the breakpoint, tool/`tool_choice` change, sub-min tokens, or 20-block overflow. *Why:* **Haiku 4.5 needs 4,096 min-cache tokens vs Sonnet's 1,024** — small Haiku prefixes silently never cache | Move dynamics after the breakpoint; freeze tools; check the min threshold |
| Good on short tasks, degrades on long ones | Context rot — everything dumped, no compaction. *Why:* attention is n², so a 90%-full window has *far less* than 90% of an empty one's reasoning; rot starts ~50–150K, not at 200K | JIT retrieval; tool-result clearing → compaction; external notes |
| Picks wrong tool / invents args | >20–50 tools loaded at once. *Why:* selection degrades past ~20 and cliffs at 30–50; schemas also burn 50K+ tokens before turn 1 | Consolidate; dynamic loading (Tool Search / Gateway SEMANTIC) |
| Agent forgets decisions, redoes work | LLM context used as state store. *Why:* the window is lossy — it degrades each step, so by step ~10 it's an unreliable record of its own past | Persist to NOTES.md / memory tool / AgentCore Memory |
| Runs hundreds of steps, never finishes | No terminal states / no cap. *Why:* "more results may exist" reads as "retry" with no stop signal | Tools return SUCCESS/FAILED/PARTIAL; set max-iterations + budget |
| Multi-agent no better than single, costs 5–10× | Over-engineered, or overlapping subagent scope. *Why:* multi ≈15× chat = ~3.75× single, so it must deliver ~3.75× the value — coding can't parallelize enough to clear that bar | Drop to single-agent; or give each subagent objective+format+boundaries |
| Confident but wrong outputs | No verification loop. *Why:* confidence and correctness are uncorrelated — an unchecked agent confidently finishes wrong work | Add evaluator / LLM-as-judge; approval gates before irreversible actions |
| Numeric/logic answers sometimes wrong | Reasoning in tokens. *Why:* LLMs are probabilistic where the task is deterministic | Offload to code / Code Interpreter |

---

## Non-negotiables (NEVER)

- **NEVER reach for multi-agent before a single agent measurably fails** — it's ≈15× chat tokens (vs ≈4× single); teams routinely match elaborate multi-agent systems with better single-agent prompting after months wasted.
- **NEVER split agents by work-phase** (planner/implementer/tester/reviewer) — "problem-centric decomposition" shares too much context and degrades via telephone-game handoffs. Split only at true context-isolation boundaries.
- **NEVER put dynamic content (timestamps, IDs, the latest user turn) before a cache breakpoint** — it silently zeroes your hit rate while you keep paying the write premium.
- **NEVER clear the memory tool's results** (`exclude_tools:["memory"]`) — you erase the agent's own paper trail.
- **NEVER pass raw subagent output upward** — return 1,000–2,000 token summaries; write detail to files/Memory.
- **NEVER run an agent without stopping conditions** (max iterations, token budget, terminal tool states) — these are correctness constraints, not performance tuning.
- **NEVER route credentials through tool parameters or the system prompt** — they land in conversation history and traces; use Identity decorators / credential providers.
- **NEVER trust a framework's abstractions you can't read** — start with the raw API (most patterns are <100 lines); keep frameworks at the orchestration layer only.
- **NEVER pick `searchType: SEMANTIC` casually on AgentCore Gateway** — it's permanent; changing it means deleting and recreating the gateway and all targets.
