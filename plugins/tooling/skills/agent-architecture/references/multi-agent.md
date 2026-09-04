---
name: multi-agent
description: When and how to build multi-agent systems — the cost math, orchestrator-worker pattern, subagent scaling rules, Claude Agent SDK AgentDefinition constraints, and AgentCore A2A. Load when considering or building multi-agent; skip for confirmed single-agent tasks.
---

# Multi-Agent Patterns

## The break-even math (decide BEFORE building)

From Anthropic's production research system (BrowseComp): **single agent ≈ 4× chat tokens; multi-agent ≈ 15× chat tokens** (⇒ multi ≈ 3.75× single). The task must produce ≈15× the value of a chat answer to justify it. Yet multi-agent (Opus lead + Sonnet subagents) **outperformed single-agent Opus 4 by 90.2%** on research — because it spends more tokens in parallel, not because of a smarter algorithm (**token usage explains 80% of variance**). Upgrading subagents Haiku→Sonnet beat *doubling the token budget*: subagent model quality > subagent token budget.

## The gate (ALL must hold, else stay single-agent)

1. Task is breadth-first with genuinely **independent** parallel threads.
2. Value justifies the ≈15× cost.
3. Subtasks need **little shared context**.
4. Work overflows one 200K window.

**Coding usually fails this** — Anthropic states coding has few parallelizable components and shared mutable repo state; coordination overhead dominates. Multi-agent is for *research/breadth*, not *building*. Directional heuristics (practitioner data, not first-party): diminishing returns past ≈4 agents; the *45% saturation rule* — adding agents helps most when single-agent baseline is **below ~45%**, and above ~80% baseline they add coordination noise.

## Orchestrator-workers — the production shape

- **Lead (Opus):** decomposes the query, writes the plan to **external memory** (context truncates at 200K), spawns workers, synthesizes. A separate **CitationAgent** verifies sources *after* research — not in the main loop.
- **Workers (Sonnet):** 3–5 spawned in parallel, each given **objective + output format + tool/source guidance + explicit boundaries + what NOT to do**. Each runs in an **isolated context window** and returns a **1,000–2,000 token** summary (detail → files/memory), never raw output.
- **Two levels of parallelism:** lead spawns workers concurrently AND each worker fires 3+ tool calls in parallel (sequential tool calls are "painfully slow"). Anthropic's lead waits synchronously for the worker batch before proceeding — async is better but not yet shipped; design around the slowest worker.

**Scaling rules — embed verbatim in the orchestrator's system prompt** (without them, early systems spawned 50 subagents for trivial queries):
- Simple fact-finding → **1 subagent, 3–10 tool calls**
- Comparisons → **2–4 subagents, 10–15 calls each**
- Complex/breadth-first research → **10+ subagents** with divided responsibilities

**The named anti-pattern: "problem-centric decomposition"** — splitting by work-phase (planner/implementer/tester/reviewer). These share too much context; sequential handoffs degrade via telephone game. Split only at true context-isolation boundaries (independent research paths, components with clean API contracts, blackbox verification). The agent that implements a feature should write its tests — it holds the context.

## Topology trade-offs

| Pattern | Cost | Debuggability | Best for |
|---|---|---|---|
| Agent-as-tool (orchestrator-worker) | low absolute, high value/token | high (isolated) | research, parallel breadth |
| Handoff (sequential) | medium | medium | specialist pipelines |
| Graph (branching state) | medium | low (state corruption risk) | branching workflows |
| Swarm / peer-to-peer | variable, shared state costly | low | rarely production-ready |

Key question: *what must each subagent know about the others?* For research, ≈nothing — that's what makes orchestrator-workers efficient. If they need shared context, use a single agent with compaction, or a deterministic pipeline.

## Claude Agent SDK — `AgentDefinition` constraints

```python
AgentDefinition(
  description="when Claude uses this agent",  prompt="subagent system prompt",
  tools=["Read","Grep"], disallowedTools=["Edit"], model="sonnet",  # or opus/haiku/inherit/full-id
  maxTurns=20, effort="high", skills=["my-skill"], mcpServers=[...], background=False)
```
- **Nesting limit = 1.** Subagents cannot spawn subagents — do NOT put `Agent` in a subagent's `tools`.
- **The only channel parent→subagent is the prompt string.** Subagent does NOT inherit parent conversation, tool results, system prompt, or skills (unless listed in `skills`). It gets its own prompt + project CLAUDE.md + tools.
- Tool was renamed `Task`→`Agent` (Claude Code v2.1.63); check both names when parsing tool_use blocks. Transcripts persist 30 days (`cleanupPeriodDays`). Windows: 8,191-char command-line limit can break long prompts — use file-based agent defs.
- Set `maxTurns` and an orchestrator-level total budget — unbounded auto-spawning (≈100 agents, ≈1,500 tool calls) has no cost ceiling and cascades failures.

## On AgentCore: A2A

| Protocol | Port | Path |
|---|---|---|
| HTTP | 8080 | `/invocations` |
| MCP | 8000 | `/mcp` |
| A2A | 9000 | `/` + `/.well-known/agent-card.json` |

A2A (JSON-RPC 2.0) is the orchestrator-worker protocol. **A2A errors return JSON-RPC error codes at HTTP 200** (e.g. throttling `-32503`) — monitoring that checks HTTP status misses ALL A2A errors; parse the JSON-RPC `error` field. Orchestrator's IAM role needs `bedrock-agentcore:InvokeAgentRuntime` on the worker ARN; **deploy the specialist first** (its ARN is the orchestrator's `AGENT2_ARN`) — encode the dependency in IaC. Stateful long-running agents need **rainbow deployments** (gradual traffic shift) — rolling restarts interrupt in-flight state. Full primitive details: [`agentcore-mapping.md`](agentcore-mapping.md). Verification/eval design for multi-agent output: [`anti-pattern-gallery.md`](anti-pattern-gallery.md).
