---
name: flow-orchestration
description: Index for the three flow execution modes — subagents (default), agent team, and deterministic Workflow. Mode detection, the rule that human gates never delegate, and a pointer to the one mode file to read. Loaded once in step 0.
---

# Flow Orchestration — index

## The one rule
**Human gates and stateful orchestration decisions stay in the main loop — always.** Subagents, teammates and workflows do autonomous fan-out (reading, building, reviewing), never: the spec discovery dialogue, the plan approval gate, or user verification. A workflow can build every slice and run every review, but it **cannot talk to the user** — it returns control at each gate. Treat it as the autonomous body between two human checkpoints, not the whole pipeline.

## Mode detection (step 0.4) — decide in this order
1. **Workflow** — a `<system-reminder>` in this session confirms ultracode / workflow orchestration is ON. That is the user's standing opt-in to spend tokens on deterministic fan-out.
2. **Agent team** — no ultracode signal, AND either Large with 4+ **independent** slices (not a single straight dependency chain), OR the user asked for a "team", "swarm", or "agents working together".
3. **Subagents** — the default for everything else. Cheapest, simplest, lowest coordination overhead. When torn between team and subagents, pick subagents.

State the choice once: *"Orchestration: **<mode>** — <one-line why>. Human gates stay with me."*

**Mid-run signal change**: if the ultracode signal appears after a mode is committed, finish the current phase, then switch the next fan-out phase to Workflow mode.

## Now read ONE file

[`orchestration/subagents.md`](orchestration/subagents.md) · [`orchestration/team.md`](orchestration/team.md) · [`orchestration/workflow.md`](orchestration/workflow.md) — the other two are dead weight for this run.
