---
name: anti-pattern-gallery
description: Agent-architecture failure modes indexed by symptom — each with the non-obvious root cause, the fix, and the AgentCore mapping. Load when an agent is broken, expensive, slow, looping, or forgetting; skip for greenfield design.
---

# Anti-Pattern Gallery (indexed by symptom)

Find your symptom, read the cause, apply the fix. Most agent failures are **engineering** failures that compound multiplicatively in a loop, not model failures — a 10-step chain at 85% per-step accuracy is only 0.85¹⁰ ≈ **19.7%** end-to-end; at 95% it's ≈60%. A smarter model does not fix that math; shorter chains with checkpoints do.

---

### Bill is 10–50× expected
**Causes (often several at once):** blanket-Opus including routers; no prompt caching; unbounded tool results re-billed every turn; a loop with no cap; LLM-as-memory re-reading degraded history (4-turn chat ≈ 1+2+3+4 = 10× turn-1 tokens from cumulative rebilling).
**Fix:** enable caching on the static prefix; route models by task (Haiku/Sonnet/Opus, escalate conditionally); cap tool results ≈5K with `response_format`; set max-iterations + token budget; instrument per-call cost. CPU/memory monitoring misses this — LLM cost is I/O-bound. **AgentCore:** Observability for per-call token attribution; alert when token-per-task > ~2× baseline.

### `cache_read_input_tokens` stays 0
**Cause:** the cached prefix hash changed. Common killers: a timestamp/request-ID/username before the breakpoint; a tool definition or `tool_choice` changed mid-session; prompt below the min-cache threshold; conversation grew past the 20-block lookback; the breakpoint sits on the volatile user turn; Go/Swift random JSON key order.
**Fix:** breakpoint on the **last block identical across requests**, dynamics after it; freeze tools+`tool_choice` for the session; check min thresholds (1,024/4,096/2,048); add a 2nd breakpoint as history grows; sort JSON keys. Verify `cache_creation_input_tokens>0` then `cache_read_input_tokens>0`. **AgentCore:** static system+tools per session; place Memory injections AFTER the breakpoint. (Full: [`token-economics.md`](token-economics.md).)

### Fine on short tasks, degrades on long ones — "context rot"
**Cause:** everything dumped upfront; no compaction. Attention is n²; quality erodes from ≈50K–150K tokens, well before the 200K wall. Four rot modes: poisoning (false premises), distraction (irrelevant data), confusion (similar-but-distinct mixed), clash (contradictory instructions).
**Fix:** just-in-time retrieval (hold identifiers, fetch via tools); tool-result clearing → compaction → external notes; preserve only high-signal tokens. Agentic search (grep/glob) beats embedding RAG for filesystem data — a vector DB can *lower* accuracy. **AgentCore:** Memory SUMMARIZATION/SEMANTIC; do NOT use in-context history as the only store. (Full: [`context-management-api.md`](context-management-api.md).)

### Picks the wrong tool / invents arguments
**Cause:** too many tools loaded at once — selection degrades past ~20, cliff at 30–50; schemas also eat 50K+ tokens. Overlapping/ambiguous tools amplify it.
**Fix:** consolidate to intent-level tools; keep active set <20; dynamic loading (Tool Search Tool / Gateway SEMANTIC); prefix-namespace; every tool must earn its slot. **AgentCore:** Gateway `searchType:SEMANTIC` — a 200-tool gateway is fine if the agent loads 5–10/query. (Full: [`tool-design.md`](tool-design.md).)

### Agent forgets decisions, repeats finished work
**Cause:** the context window used as a state store — it's lossy and degrades each step.
**Fix:** persist outside context — NOTES.md via the memory tool, filesystem artifacts, or a real state store with explicit read/write tools. **AgentCore:** Memory EPISODIC/SUMMARIZATION + `create_event`/`retrieve_records`.

### Runs hundreds of steps, never finishes — the reasoning loop
**Cause:** tools return "more results may exist"/"prices change" → the model reads that as "retry"; no terminal signal, no cap.
**Fix:** tools return explicit SUCCESS/FAILED/PARTIAL; set max-iterations, token budget, wall-clock + spend limits (correctness constraints, not perf). Harness hooks: DebounceHook (block duplicate `(tool, input)` fingerprints) + LimitToolCounts (per-tool ceilings) — ≈30 lines in Strands `HookProvider`. Clear terminal states cut one task 14→2 calls.

### Multi-agent no better than single, costs 5–10×
**Cause:** over-engineered (a workflow would do) OR subagents with overlapping scope duplicating work OR over-spawning (50 agents for a simple query).
**Fix:** apply the rung-4 gate before going multi (independent threads, value, low shared context, >200K work); for coding stay single (shared mutable state). Give each subagent objective+format+tool guidance+boundaries; embed scaling rules (1 / 2–4 / 10+). Heuristic: diminishing returns past ≈4 agents; coordinator should stay a small fraction of total tokens. **AgentCore:** separate Runtimes + A2A only when truly multi-agent. (Full: [`multi-agent.md`](multi-agent.md).)

### Confident but wrong outputs
**Cause:** no verification loop — confidence and correctness are uncorrelated; an agent with no checker confidently finishes wrong work. "All-or-nothing autonomy" lets errors cascade (e.g. an agent running `DROP DATABASE` unprompted).
**Fix:** evaluator-optimizer / LLM-as-judge (one unified 0.0–1.0 rubric beats many per-component judges); approval gates before irreversible/financial/destructive actions; intermediate checkpoints for long workflows. Start evals early — ~20 cases surface 30%→80% effect sizes. **AgentCore:** Policy Engine (`ENFORCE`) blocks non-compliant calls; Browser live-view for HITL takeover.

### Numeric/logic answers sometimes wrong, and pricey
**Cause:** reasoning in tokens for work with a provably correct answer — probabilistic where it should be deterministic; 10–50× the cost of a function.
**Fix:** if it can be coded and has a correct answer (math, dates, sort, filter, regex, JSON, dedup), make it a tool/code call. **AgentCore:** Code Interpreter — deterministic, kills the hallucination class.

### Behaves erratically, ignores instructions — the mega-prompt
**Cause:** over-specified system prompt (the 32-page SOP); pseudocode-with-if-else; conflicting rules. Wrong "altitude": too low = brittle hardcoding, too high = "be helpful" gives no signal.
**Fix:** aim for the Goldilocks zone — minimal-yet-sufficient, structured sections, concrete examples for edge cases (not an exhaustive ruleset). Start vaguer, add specificity from *observed* failures. Progressive disclosure via skills for branch-specific detail. Heuristic: if it can't be read in ~90s, it's a mega-prompt.

### Stuck on a framework when debugging
**Cause:** premature framework lock-in — abstractions hide prompts/responses; the bug is inside the framework; migration is a 6-month project. Post-2024 models need far less scaffolding.
**Fix:** start with the raw API (most patterns <100 lines); keep frameworks at the orchestration layer only, business logic framework-independent; ensure you can read the framework's source and could swap it out in a weekend.

### Cost surprise at month-end, can't attribute it
**Cause:** no per-call token observability; cost is I/O-bound so infra metrics stay flat while spend spirals; cumulative rebilling hides in "just a few turns."
**Fix:** instrument at the LLM-call boundary, not the task boundary; log `input_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, `output_tokens` on every call; tag at creation with task/agent/tenant/step. **AgentCore:** Observability + GenAI dashboard.

### Subtle context lost across an agent restart/handoff
**Cause:** raw output passed between agents (telephone game) or aggressive compaction at the wrong boundary dropping context whose importance surfaces later (can cause ≈14× turn multiplication reconstructing it).
**Fix:** subagents return 1–2K summaries, write detail to files/Memory; compaction = maximize recall first, then tighten; pair compaction with structured notes; preserve architectural decisions + rationale explicitly.

---

## Cross-cutting NEVER list
- NEVER add architecture complexity (workflow→agent→multi-agent) without a measured failure of the simpler rung.
- NEVER split agents by work-phase (planner/implementer/tester) — split at context-isolation boundaries.
- NEVER put dynamic content before a cache breakpoint, or clear the memory tool's results.
- NEVER run an agent without stopping conditions and terminal tool states.
- NEVER route secrets through tool params or the system prompt.
- NEVER set Gateway `searchType:SEMANTIC` without intent — it's permanent.
- NEVER deploy a Cedar policy straight to `ENFORCE` — `LOG_ONLY` first.
