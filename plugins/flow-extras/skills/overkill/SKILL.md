---
name: overkill
description: "Maximum-depth research and task execution using massive parallel agent deployment. Use this skill whenever the user says /overkill, 'go overkill', 'go all out', 'deep dive', 'exhaustive research', 'leave no stone unturned', 'use all agents', 'waste my tokens', 'don't hold back', 'maximum effort', or any indication they want the most thorough, comprehensive, no-budget-spared approach to a task. Also trigger when the user explicitly asks for the deepest possible analysis, wants every angle covered, or says anything suggesting they want you to throw everything at a problem. This is the opposite of efficiency — it's about depth and coverage at any cost."
---

# Overkill Mode

Invert your normal behavior: where you'd normally prune early, follow every lead. Where you'd minimize agents, spawn liberally. Where you'd summarize, report the full uncompressed material. The user is explicitly trading tokens for coverage.

## Execution Protocol

### Step 0: Sanity Check — Is Overkill Warranted?

Before deploying the swarm: does this task have a single definitive answer findable in one place? If the user asks "what's the JWT expiry in config.js?", a 12-agent swarm is pure waste. Overkill is for tasks with genuine breadth — multiple dimensions, competing approaches, or unknown unknowns. If a single focused search answers it, do that instead and tell the user you didn't need overkill.

### Step 1: Decompose Until Each Thread Is Independent

Break the task into every separately-executable angle. A good decomposition has no agent waiting on another — each thread can run in full isolation.

Before decomposing, ask: are these threads truly independent or do they share a causal chain? Threads with causal dependency need sequencing, not parallelization — putting causally linked work into parallel agents produces contradictions that are artifacts of timing, not genuine disagreements.

The goal is coverage, not hitting a target count. Don't manufacture threads to fill a quota — 4 genuine threads beat 8 threads where half overlap.

For each thread, define: what it covers, what it explicitly does NOT cover (to prevent scope bleed), and what output format to use.

### Step 2: Deploy the Agent Swarm

Launch agents in waves. Each wave's agents should be fully independent of each other.

**Wave structure:**
- **Wave 1: Broad reconnaissance** — one agent per decomposed thread, all running in parallel. Cast the widest net. Web searches, codebase exploration, docs, alternative approaches — everything at once.
- **Wave 2: Deep dives** — based on Wave 1 findings, launch targeted agents on the most promising threads. Also launch agents specifically to investigate surprising or contradictory findings from Wave 1.
- **Wave 3: Cross-validation** — have agents verify each other's findings. When two Wave 1/2 agents disagree, the disagreement is a signal. Launch a dedicated agent whose only job is resolving that specific contradiction.
- **Wave 4+** — keep going until you've exhausted all productive angles. There is no upper limit.

**Agent selection:** Use specialist agent types when available (e.g., `awesome-agents:security-engineer` for security, `awesome-agents:performance-engineer` for performance). If a specialist isn't installed, fall back to `general-purpose` with a focused prompt — never skip coverage because a specialist is unavailable. Use `sonnet` for substance agents; reserve `opus` for synthesis and genuinely complex reasoning sub-tasks. Use `haiku` only for pure file-lookup exploration.

**Run agents in background** whenever possible so you can launch the next wave or do synthesis prep while earlier agents are still running.

### Step 3: Write Effective Agent Prompts (Artifact-Driven)

The quality of your swarm depends almost entirely on prompt quality. Poor prompts produce hallucinated or overlapping findings.

**Every research/analysis agent must write a full standalone document to disk.** Don't rely on agent return messages — those get truncated. Instead, instruct each agent to write its complete findings to a file. Create a workspace directory for the overkill session (e.g., `.overkill/<task-slug>/`) and have each agent write to its own file within that workspace.

Example workspace structure:
```
.overkill/evaluate-auth-system/
├── wave-1/
│   ├── security-audit.md          # Full security review with findings
│   ├── architecture-analysis.md   # Deep dive into component design
│   ├── performance-profile.md     # Benchmarks, bottlenecks, data
│   ├── dependency-review.md       # Supply chain, versions, CVEs
│   └── competitive-comparison.md  # How alternatives solve this
├── wave-2/
│   ├── jwt-deep-dive.md           # Following up on Wave 1 finding
│   ├── session-store-options.md   # Exploring alternative identified
│   └── oauth-flow-audit.md        # Specific concern from Wave 1
├── wave-3/
│   ├── contradiction-jwt-vs-session.md  # Resolving disagreement
│   └── cross-validation.md              # Verifying key claims
└── synthesis.md                   # Final orchestrator synthesis
```

Each agent prompt must include:
1. **Bounded scope** — explicitly state what this agent covers AND what it does NOT cover. "Research X. Do NOT investigate Y — another agent handles that."
2. **Write a comprehensive document** — "Write your complete findings to `<path>`. This is your primary deliverable. Be exhaustive — include code snippets, data, links, everything you find. Length is not a concern. Another agent will synthesize later, so include raw material, not just conclusions."
3. **Null result format** — instruct the agent to report what it searched even when it finds nothing. "If you find no issues, list what you checked and confirmed clean." Silent non-findings are indistinguishable from search failures.
4. **Document structure** — each document should follow: Executive Summary, Detailed Findings (with evidence), Confidence Level per finding, What I Searched, Open Questions, Raw Data/References.
5. **Contradiction flag** — "If you find evidence that contradicts a reasonable assumption, flag it prominently — these are often the most important findings."

**Good prompt:** "Research JWT token vulnerabilities in Node.js express apps. Do NOT investigate session management or OAuth — other agents cover those. Write full findings to `.overkill/auth-audit/wave-1/jwt-vulnerabilities.md`. If you find no vulnerabilities, list what attack vectors you checked and confirmed safe."

**Bad prompt:** "Research authentication security." (No scope bound, no output path, no null-result instruction — produces vague, overlapping work.)

The point of writing to disk: the orchestrator (you) can read all documents after each wave, identify gaps and contradictions, and use the full uncompressed material for synthesis. Nothing gets lost to message truncation.

### Step 4: Resolve Contradictions Actively

When agents contradict each other, do NOT average away the disagreement. The disagreement itself is valuable intelligence.

Launch a targeted agent with the specific contradiction as its mandate: "Agent A found X. Agent B found Y. These appear mutually exclusive. Your only job is to determine which is correct and provide definitive evidence."

If the contradiction cannot be resolved, present both findings to the user with the evidence each side has, and your assessment of which is more likely correct and why.

### Step 5: Synthesize from Artifacts

Read every document in the workspace. This is where the artifact-driven approach pays off — you have full, uncompressed research material to work with, not truncated agent messages.

Write a `synthesis.md` to the workspace root that:
1. **Leads with the answer** — executive summary of the key findings, recommendations, or deliverables
2. **Cross-references findings across agents** — where did multiple agents independently reach the same conclusion? Where did they disagree?
3. **Includes confidence ratings** for each major finding:
   - **High** — multiple independent agents agree, evidence is strong
   - **Medium** — some corroboration but incomplete, or partial disagreement
   - **Low** — single source, speculative, or unresolved contradiction
4. **Links to source documents** — "see `wave-1/security-audit.md` for full details"
5. **Lists open questions** — what couldn't be resolved, what needs human judgment

Then present the synthesis to the user. Tell them the workspace path so they can browse the raw documents if they want to go deeper on any thread. The full research corpus persists on disk — they can revisit it later.

## Scaling Guide

- **Small task** (e.g., "research this library"): 2-3 waves. Web research, docs, community sentiment, and alternatives can all run in parallel.
- **Medium task** (e.g., "audit this module"): 3 waves. Multiple specialist reviewers plus cross-validation wave.
- **Large task** (e.g., "design this system"): 4+ waves. Full specialist team, research wing, and dedicated synthesis/validation wave.

Scale by coverage gaps, not by hitting a count target.

## Anti-Patterns (NEVER Do These)

- **NEVER let agents see each other's partial results** before reporting independently. Agents anchor on each other's findings and stop searching for alternatives. Each agent must operate in isolation until synthesis.
- **NEVER treat "I found nothing" as task completion.** Verify: did the agent actually search thoroughly, or did it fail silently? Require explicit confirmation of what was searched, not just what was found.
- **NEVER synthesize prematurely.** Wait for all agents in a wave to complete before launching the next wave. Partial synthesis creates false consensus that poisons subsequent research directions.
- **NEVER assign overlapping scope without a merge strategy.** Two agents covering the same ground produce contradictory findings with no principled way to resolve them. Make scope boundaries explicit in each agent's prompt.
- **NEVER manufacture agents to hit a number.** 3 excellent agents with clear, bounded scope beat 8 agents with vague, overlapping mandates. The goal is coverage, not agent count.
- **NEVER skip coverage because a specialist agent isn't available.** Fall back to `general-purpose` with a focused system prompt. The user asked for exhaustive — deliver it with whatever agents you have.
- **NEVER summarize away the depth.** The user paid for thoroughness. Give them the full picture with structured formatting (headers, tables, code blocks). They can skim — but they can't recover details you discarded.
- **NEVER synthesize from memory instead of reading the artifact files.** The whole point of writing to disk is that the full, uncompressed material is there. Read every `.md` in the workspace before writing `synthesis.md` — synthesizing from what you remember the agents "said" defeats the artifact-driven approach.
- **NEVER start synthesis while artifact files are still being written.** Wait for all agents in a wave to fully complete and confirm their files exist on disk before reading them. File write races produce partial reads that look like complete findings.
