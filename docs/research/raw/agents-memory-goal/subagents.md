# Custom Subagents for Claude Code (2026 state)

## TL;DR

- The subagent frontmatter schema is large (17 fields as of Sept 2026: `name`, `description`, `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `effort`, `isolation`, `color`, `initialPrompt`, `experimental`), but only `name` and `description` are required — everything else defaults to "inherit from the main session." (PRIMARY, code.claude.com/docs/en/sub-agents, fetched 2026-09-04)
- There are six/seven built-in agents: **Explore** (read-only, fast search), **Plan** (read-only, plan-mode research), **general-purpose** (full tools, complex multi-step work), **claude** (catch-all/background default), **statusline-setup** and **claude-code-guide** (both fixed-model internal helpers). All can be overridden by a same-named custom agent. (PRIMARY, same doc)
- The dominant practitioner pattern is *not* "a few hand-picked agents" — it's mass-produced catalogs: wshobson/agents ships 202 agents / 94 plugins, VoltAgent's awesome-claude-code-subagents ships 158+ agents across 10 categories, claude-code-templates offers 100+ installable agents from a web catalog. These are one-author collections, not Anthropic-vetted, and none of their READMEs offer evidence the roles were individually measured for usefulness. (PRIMARY, repo READMEs, fetched 2026-09-04)
- Anthropic's own shipped agents are narrow and few: the `feature-dev` plugin's three agents — **code-explorer**, **code-architect**, **code-reviewer** — are the clearest "official" example of a minimal, role-differentiated set (explore → design → review), each pinned to Sonnet with a restricted read-mostly toolset. (PRIMARY, anthropics/claude-plugins-official, fetched 2026-09-04)
- Context/token cost is real and documented in two independent ways: (a) the docs warn that combined subagent descriptions over 15,000 tokens trigger a warning; (b) a shipped community plugin (`lean-agents`, PR #38045 to anthropics/claude-code) exists specifically because users with 10+ MCP servers get "prompt too long" failures — MCP tool schemas (~200k+ tokens) are passed into subagents regardless of their `tools:` allowlist. (PRIMARY, GitHub, fetched 2026-09-04)
- "Subagent loses the conversation" is by design, not a bug — subagents run in an isolated context window and get only what you hand them — but this by-design isolation produces real failure modes: silent inline-instead-of-delegate behavior (issue #90182), and delivery failures where a completed subagent's report never reaches the parent, burning the tokens for nothing (issue #88822, one case losing ~190k tokens / 12 minutes of work). (PRIMARY, GitHub issues, fetched 2026-09-04)
- Anthropic's own multi-agent research system post (foundational, though from mid-2025 and thus *older guidance* than the 2026 docs) is still the best-sourced numeric claim in this space: multi-agent systems use ~15× the tokens of a single chat turn, and a lead-Opus/subagent-Sonnet research system beat single-agent Opus by 90.2% on an internal eval — i.e., the token cost buys a real, measured capability gain on genuinely parallelizable research tasks, not on everything. (PRIMARY, anthropic.com/engineering, June 2025)
- Consensus across every primary source (official docs, wshobson, VoltAgent, obra/superpowers, GitHub issues) is that giving a subagent "enough context" means writing it into the dispatch prompt explicitly (objective, output format, tool/source guidance, task boundaries) — vague dispatches cause duplicated or wasted work, which is exactly what the 437-subagent runaway issue (#67994) reproduces at scale.
- For a solo developer the load-bearing, cross-source agreement is: a **reviewer/adversarial-check agent** and an **explore/research agent** are the two roles independently reinvented by Anthropic's own built-ins, Anthropic's own plugin, and the community's SDD methodology — everything past that is domain-specific and should be added only when a role is dispatched often enough to be worth writing down.

---

## Findings

1. **Claim:** As of Sept 2026 the full set of documented subagent frontmatter fields is: `name`, `description` (both required), and optional `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `effort`, `isolation`, `color`, `initialPrompt`, `experimental`.
   **Evidence:** Docs table gives exact field names, requiredness, and semantics (e.g. `model`: "sonnet, opus, haiku, fable, a full model ID... or inherit. Defaults to main conversation's model if omitted"; `memory`: "Persistent memory scope: user, project, or local. Enables cross-session learning"; `isolation`: "Set to worktree to run the subagent in a temporary git worktree").
   **URL:** https://code.claude.com/docs/en/sub-agents
   **Date fetched:** 2026-09-04 | **PRIMARY** | **Standard/consensus** (this is the canonical spec).

2. **Claim:** Combined subagent descriptions exceeding 15,000 tokens trigger a warning — i.e., the *description* text alone (not the full agent body) is a metered context cost, because Claude Code loads every available subagent's `description` up front so the orchestrator can route to it.
   **Evidence:** "Keep descriptions brief; combined descriptions exceeding 15,000 tokens trigger a warning" (docs, `description` field row).
   **URL:** https://code.claude.com/docs/en/sub-agents
   **Date:** 2026-09-04 | **PRIMARY** | **Standard/consensus.**

3. **Claim:** The model-resolution order for a subagent's model, as of v2.1.251, is: (1) per-invocation `model` parameter, (2) the subagent definition's `model` frontmatter (`inherit` = main conversation's model), (3) `CLAUDE_CODE_SUBAGENT_MODEL` env var, (4) main conversation's model. Before v2.1.251 the env var took priority over both the per-invocation param and the frontmatter.
   **Evidence:** Docs section "Model Selection Order for Subagents," with explicit version note about the order change.
   **URL:** https://code.claude.com/docs/en/sub-agents
   **Date:** 2026-09-04 | **PRIMARY** | **Standard** (versioned changelog fact, supersedes pre-2.1.251 behavior).

4. **Claim:** Built-in agents and their properties: **Explore** (read-only tools only, Write/Edit denied, skips CLAUDE.md and git status, "as of v2.1.198 inherits main model instead of always using Haiku" — i.e. this itself supersedes an earlier default); **Plan** (same restrictions, used in plan mode); **general-purpose** (every tool available to subagents, follows model selection order); **claude** (catch-all, default for background sessions); **statusline-setup** (Sonnet, fixed) and **claude-code-guide** (Haiku, fixed, answers questions about Claude Code features).
   **Evidence:** Docs table "Built-in Subagents."
   **URL:** https://code.claude.com/docs/en/sub-agents
   **Date:** 2026-09-04 | **PRIMARY** | **Standard/consensus.**

5. **Claim:** Anthropic's own recommended workflow explicitly frames subagents as a *context-management* tool, not a capability tool: "use subagents to keep research out of [your context]... Subagents run in separate context windows and report back summaries." It also gives a concrete adversarial-review pattern: dispatch a review subagent on a finished diff in a *fresh* context so it isn't biased by the reasoning that produced the change, and warns that a reviewer told to find gaps will usually report some even on sound work, cautioning against chasing every finding.
   **Evidence:** Best-practices doc, sections "Use subagents for investigation" and "Add an adversarial review step."
   **URL:** https://code.claude.com/docs/en/best-practices
   **Date:** 2026-09-04 | **PRIMARY** | **Standard/consensus** (Anthropic's stated best practice).

6. **Claim:** Anthropic ships its own minimal three-agent pipeline for feature development: `code-explorer` (traces implementation, entry points, architecture, outputs file:line references), `code-architect` (designs the implementation blueprint, "make decisive choices — pick one approach and commit"), `code-reviewer` (confidence-scored review, "Only report issues with confidence ≥ 80... Focus on issues that truly matter — quality over quantity"). All three are pinned `model: sonnet`, given the same restricted read/search toolset (`Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput` — notably no Edit/Write), and distinguished by `color` (yellow/green/red).
   **Evidence:** Full frontmatter + body of all three agent files, fetched verbatim.
   **URL:** https://github.com/anthropics/claude-plugins-official/blob/main/plugins/feature-dev/agents/{code-explorer,code-architect,code-reviewer}.md
   **Date:** 2026-09-04 | **PRIMARY** | **Standard** (this is Anthropic's own shipped design, i.e. closest thing to an official "which roles matter" answer, though it is one plugin's opinion, not a universal ranking).

7. **Claim:** The largest community agent collection, wshobson/agents, ships 202 agents across 94 plugins (built for Claude Code and re-exported to Codex CLI, Cursor, OpenCode, Antigravity, Copilot from one Markdown source), organized by domain (architecture, languages, infra, security, data, ML, docs, business, SEO) with a stated tiered model strategy: Tier 0 Fable 5 (rare, long-horizon), Tier 1 Opus (architecture/security/code-review/production-critical), Tier 2 inherit (user-chosen), Tier 3 Sonnet (docs/testing/debugging), Tier 4 Haiku (fast ops/SEO/deployment/content). The README states "Installing a plugin loads only its components into context — not the whole marketplace," implying the authors are themselves aware of and mitigating the context-bloat problem via install-time scoping rather than a small agent count. Repo has 39.4k GitHub stars.
   **Evidence:** README + docs/agents.md tables, fetched verbatim (sample: `code-reviewer` = opus, `security-auditor` = opus, `test-automator` = sonnet, `search-specialist` = haiku).
   **URL:** https://github.com/wshobson/agents (README), https://github.com/wshobson/agents/blob/main/docs/agents.md
   **Date:** 2026-09-04 | **PRIMARY** (author's own repo) | **One practitioner's opinion** on model tiering and taxonomy, not independently validated.

8. **Claim:** VoltAgent's awesome-claude-code-subagents lists 158+ subagents across 10 categories (e.g. "01. Core Development": api-designer, backend-developer, frontend-developer, fullstack-developer, microservices-architect, mobile-developer, ui-designer, websocket-engineer, etc.), distributed as installable Claude Code plugins per category (e.g. `voltagent-core-dev`), with an explicit note that its "meta-orchestration" agents "work best when other categories installed" — i.e. the collection assumes broad, not minimal, installation.
   **Evidence:** README fetched verbatim; badge states "subagents-158."
   **URL:** https://github.com/VoltAgent/awesome-claude-code-subagents
   **Date:** 2026-09-04 | **PRIMARY** (author's own repo) | **One practitioner's collection**, explicitly optimized for breadth/catalog completeness, not solo-developer minimalism — the README nowhere argues these are all individually necessary.

9. **Claim:** claude-code-templates (davila7), a widely used CLI/web catalog (30.5k GitHub stars, "CLI tool for configuring and monitoring Claude Code"), offers 100+ installable agents/commands/settings/hooks/MCPs browsable at aitmpl.com and installable per-item (`npx claude-code-templates@latest --agent development-tools/code-reviewer --yes`), reinforcing the pattern of large browsable catalogs from which users pick individual agents rather than installing a curated bundle.
   **Evidence:** README fetched verbatim; GitHub API repo metadata.
   **URL:** https://github.com/davila7/claude-code-templates
   **Date:** 2026-09-04 | **PRIMARY** | **Descriptive fact**, not an argument about which agents are useful.

10. **Claim:** obra/superpowers (281,635 GitHub stars — by far the largest of any collection surveyed here) is *not* primarily an agent catalog but a skills-and-methodology framework whose core mechanism, "subagent-driven development" (SDD), explicitly treats subagents as disposable, context-isolated task executors: "They should never inherit your session's context or history — you construct exactly what they need. This also preserves your own context for coordination work." Its `dispatching-parallel-agents` skill formalizes when to fan out (independent problem domains only) and how to write a dispatch prompt (focused scope, self-contained context, explicit output spec) versus common mistakes ("Too broad: Fix all the tests," "No context," "No constraints," "Vague output").
   **Evidence:** SKILL.md files fetched verbatim, including explicit anti-pattern list.
   **URL:** https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md, https://github.com/obra/superpowers/blob/main/skills/dispatching-parallel-agents/SKILL.md
   **Date:** 2026-09-04 | **PRIMARY** (author's own repo) | **One practitioner's methodology**, though at 281k stars it is the most widely adopted single opinion in this space.

11. **Claim:** obra/superpowers's SDD skill assigns model tiers *by task type within a single implementation*, not by fixed agent identity: "Mechanical implementation tasks (isolated functions, clear specs, 1-2 files): use a fast, cheap model... Integration and judgment tasks: use a standard model... Architecture and design tasks: use the most capable available model... The final whole-branch review is one of these — dispatch it on the most capable available model, not the session default." Scoped re-reviews of small fix diffs explicitly get a "cheap-to-mid tier" model.
   **Evidence:** SKILL.md, "Model Selection" section, fetched verbatim.
   **URL:** https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md
   **Date:** 2026-09-04 | **PRIMARY** | **One practitioner's opinion**, contested implicitly by wshobson's approach of pinning model *per agent identity* rather than per dispatched task — both are defensible, and the docs' `model: inherit` mechanism supports either style.

12. **Claim:** Anthropic's foundational multi-agent research system writeup states multi-agent systems use "about 15× more tokens than chats" (and single agents ~4× more than chats), that vague subagent instructions cause duplicated work (worked example: overlapping semiconductor-shortage research), that a lead-Opus-4/subagent-Sonnet-4 system beat single-agent Opus 4 by 90.2% on an internal research eval, and that "upgrading to Claude Sonnet 4 is a larger performance gain than doubling the token budget on Claude Sonnet 3.7" — i.e. model quality beats brute-force subagent fan-out. Early failure modes explicitly named: spawning excessive subagents for simple queries, endless searching for nonexistent sources, redundant work from poor task delineation.
   **Evidence:** WebFetch summary of the post, with direct quotes.
   **URL:** https://www.anthropic.com/engineering/multi-agent-research-system
   **Date:** June 13, 2025 (older than the 2026 docs; still the primary numeric source for token-multiplier and lift figures — **flagged as pre-2026, potentially superseded** by whatever internal numbers exist for the current model line, none of which were found published for 2026).
   **PRIMARY** | **Standard/consensus** within Anthropic's own writing, though the specific 90.2%/15×/4× figures are tied to a 2025 model generation (Opus 4/Sonnet 4) and a research-specific eval — treat as illustrative order-of-magnitude, not a current benchmark.

13. **Claim:** The context-cost-of-many-agents problem is concrete enough that a community PR added a whole mitigation plugin: `lean-agents`, submitted to `anthropics/claude-code` (PR #38045, 2026-03-24), ships 6 lightweight replacements for Explore/Plan/general-purpose because "Users with 10+ MCP servers configured experience silent subagent failures because all MCP tool schemas (~200k+ tokens) are passed to subagents regardless of their `tools:` frontmatter. This makes Explore, Plan, and general-purpose agents unusable." It links four related open issues (#37793, #31623, #23448, #38044) as corroboration.
   **Evidence:** PR body fetched verbatim via `gh pr view`.
   **URL:** https://github.com/anthropics/claude-code/pull/38045
   **Date:** 2026-03-24 | **PRIMARY** | **Contested/unresolved** — this is a reported bug/gap (MCP schemas leaking into subagents despite a `tools:` allowlist), not yet confirmed fixed in the docs snapshot fetched 2026-09-04 (the docs do describe `tools` as an allowlist without mentioning MCP schema pass-through as an exception, so this may be a real gap between spec and implementation, or may have been fixed since March — not independently confirmed).

14. **Claim:** "437 subagents is probably too many" — a user reported that a single review-oriented workflow command fanned out 14 review agents (returning 140 issues, all duplicates of the same underlying ~10 issues due to missing dedup), then spawned 140×3=420 adversarial re-review agents, burning ~6M tokens in <15 minutes before being stopped, with an estimated ~36M tokens if left to finish for 10 real issues.
   **Evidence:** Issue body + screenshots referenced, fetched via `gh issue view`.
   **URL:** https://github.com/anthropics/claude-code/issues/67994
   **Date:** 2026-06-12 (closed as stale/inactive) | **PRIMARY** | **Contested/anecdotal** — a single (if vivid) user report illustrating the failure mode "no dedup + no fan-out cap," not evidence this is typical, but corroborated by other issues about uncapped fan-out (#66023: "one invocation spawned 46 Opus subagents (~3M tokens) with no cost confirmation," #89249: "/review high effort silently increased to 10× token cost via multi-agent fan-out").

15. **Claim:** Subagent isolation ("loses the conversation") produces two distinct, independently reported failure classes beyond the by-design isolation itself: (a) a completed subagent's final report can arrive as "a bare pointer... with no report anywhere in the conversation" — silent, terminal, no retrieval path, with one observed case losing ~190k tokens / ~12 minutes of work; (b) the main agent can silently skip delegating to installed subagents/skills entirely and do the work inline at large token cost even when project instructions explicitly say to delegate.
   **Evidence:** Issue bodies fetched verbatim via `gh issue view`.
   **URL:** https://github.com/anthropics/claude-code/issues/88822 (2026-08-22), https://github.com/anthropics/claude-code/issues/90182 (2026-08-27)
   **Date:** 2026-09-04 (fetch date) | **PRIMARY** | **Reported bugs, open as of fetch** — not confirmed fixed; illustrate that isolation's cost is not only "you must write good context in" but also "the plumbing that returns results can itself fail."

16. **Claim:** obra/superpowers's own SDD methodology explicitly names the *cost* of subagent context loss across a long session and prescribes a mitigation: "Conversation memory does not survive compaction. In real sessions, controllers that lost their place have re-dispatched entire completed task sequences — the single most expensive failure observed. Track progress in a ledger file, not only in todos." — i.e. the controller session's *own* context (not just the subagent's) is fragile, and the fix is external, durable state (a ledger file on disk) rather than relying on conversational memory or the `memory` frontmatter field.
   **Evidence:** SKILL.md, "Setup" section, fetched verbatim.
   **URL:** https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md
   **Date:** 2026-09-04 | **PRIMARY** | **One practitioner's opinion**, but directly addresses this research question's "subagent loses the conversation" downside from the orchestrator side, which the official docs do not address at all.

17. **Claim:** The docs give a canonical minimal agent-authoring example that is explicitly a **memory + narrow-tools + pinned-model** pattern: `tools: Read, Grep, Glob` (no Edit/Write), `model: sonnet`, `memory: project` for a "code-improver" agent — i.e. Anthropic's own worked example for the general concept favors read-only, narrowly-scoped, persistent-memory agents over broad general-purpose ones.
   **Evidence:** Full YAML example quoted verbatim in Finding 1's source fetch.
   **URL:** https://code.claude.com/docs/en/sub-agents
   **Date:** 2026-09-04 | **PRIMARY** | **Standard** (canonical example, but only one example — not proof this is the modal real-world config).

---

## Downsides and failure modes

- **Context isolation is the point, and also the cost.** Subagents "should never inherit your session's context or history" (obra/superpowers) — this is what makes them useful for keeping the main context clean, and exactly what makes handing them "enough context" an explicit authoring burden: every fact the main session already knows must be re-stated in the dispatch prompt, or the subagent works blind. Official docs frame this as pure upside ("keeps your main conversation clean"); community sources (superpowers, dispatching-parallel-agents) are the ones that spell out the authoring discipline required to make it actually work, and the anti-patterns when it isn't ("Too broad," "No context," "No constraints," "Vague output" — obra/superpowers, fetched 2026-09-04).
- **Description-token overhead scales with agent count.** Every defined subagent's `description` is loaded so the orchestrator can route to it; official docs put a 15,000-token combined-description warning threshold on this (code.claude.com/docs/en/sub-agents). A 202-agent or 158-agent catalog (wshobson, VoltAgent) is far above what one project would want fully loaded at once — both collections mitigate this by shipping as separately-installable plugins/categories rather than one flat agent directory, which is itself evidence the authors know full-catalog loading is a real cost, not just a theoretical one.
- **MCP tool schema pass-through can silently break subagents regardless of `tools:` scoping.** Reported by a community PR (#38045, anthropics/claude-code, 2026-03-24) with four corroborating linked issues: users with 10+ MCP servers hit "prompt too long" on Explore/Plan/general-purpose because ~200k+ tokens of MCP schema get passed in regardless of the agent's tool allowlist. Not confirmed resolved as of this report's fetch date.
- **Uncapped fan-out with no dedup can burn tens of millions of tokens for single-digit real findings.** #67994 (437 agents spawned for 10 issues, ~6M tokens burned in under 15 minutes before being stopped, closed as stale/inactive rather than fixed) plus corroborating #66023 (46 Opus subagents / ~3M tokens from one invocation, no cost confirmation) and #89249 (/review effort setting silently multiplying cost 10× via fan-out). This is a workflow/orchestration-layer problem (missing dedup, missing fan-out caps) more than a subagent-definition problem, but it means an agent role that seems individually cheap can be dispatched many times per prompt.
- **Delivery of a subagent's result back to the parent can itself fail silently and irrecoverably.** #88822 (2026-08-22, open as of fetch): a completed subagent's report can arrive as a bare pointer with no body, with no retrieval path — the only recovery is re-running (and re-paying for) the entire subagent. One observed case: ~190k tokens / ~12 minutes lost this way.
- **The main agent can silently skip delegation entirely**, doing work inline "at large token cost" even when project instructions explicitly route work to specific subagents/skills (#90182, 2026-08-27, open as of fetch) — meaning a carefully designed agent roster provides no guarantee it will actually be used on a given run.
- **Session-level memory loss compounds across long subagent-driven runs.** Per obra/superpowers, "controllers that lost their place have re-dispatched entire completed task sequences — the single most expensive failure observed" after compaction; their fix is an external ledger file, not the `memory` frontmatter field (which is per-agent persistent scope for cross-session learning, a different mechanism from within-session progress tracking).
- **Token-cost multiplier is real and Anthropic-quantified, even if the specific figures are from mid-2025.** ~4× tokens for a single agent vs. chat, ~15× for multi-agent systems, per Anthropic's own research-system writeup — a number worth budgeting against, while noting it's tied to a now-superseded model generation (Opus 4 / Sonnet 4) and a research-specific eval, not a general 2026 figure.

---

## Concrete practices / configs

### Full frontmatter field reference (Sept 2026, from code.claude.com/docs/en/sub-agents)

```yaml
---
name: string              # required. lowercase-hyphenated, no ":" (reserved for plugin scoping)
description: string       # required. routing signal for auto-delegation; combined >15k tokens across all agents warns
tools: string             # optional. allowlist (tool names or mcp__<server> patterns); omit = inherit everything
disallowedTools: string   # optional. denylist, applied before `tools` is resolved
model: sonnet|opus|haiku|fable|<full-model-id>|inherit   # optional. default = main session's model
permissionMode: default|acceptEdits|auto|dontAsk|bypassPermissions|plan|manual   # optional; ignored for plugin subagents
maxTurns: number          # optional. output marked partial when hit (v2.1.246+)
skills: [string]          # optional. FULL skill content (not just description) preloaded at startup
mcpServers: {...}         # optional. named server refs or inline defs; ignored for plugin subagents
hooks: {...}              # optional. lifecycle hooks scoped to this agent; ignored for plugin subagents
memory: user|project|local   # optional. persistent scope, enables cross-session learning
background: true|false    # optional. force-background even if asked to run foreground
effort: low|medium|high|xhigh|max   # optional. overrides session effort level while this agent is active
isolation: worktree       # optional. run in a temporary isolated git worktree
color: red|blue|green|yellow|purple|orange|pink|cyan   # optional. display-only
initialPrompt: string     # optional. auto-submitted first turn when run as main session agent
experimental:
  cacheTtl: 5m|1h          # optional. prompt cache lifetime (v2.1.248+)
---
```

### Anthropic's own worked minimal example (verbatim from docs)

```markdown
---
name: code-improver
description: Scans files and suggests improvements for readability, performance, and best practices. Use after writing or modifying code.
tools: Read, Grep, Glob
model: sonnet
memory: project
---

You are a code improvement specialist. For each issue you find, explain
the problem, show the current code, and provide an improved version.
```

### Anthropic's shipped 3-agent feature-dev pipeline (verbatim frontmatter, bodies condensed)

```markdown
---
name: code-explorer
description: Deeply analyzes existing codebase features by tracing execution paths, mapping architecture layers, understanding patterns and abstractions, and documenting dependencies to inform new development
tools: Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput
model: sonnet
color: yellow
---
```
```markdown
---
name: code-architect
description: Designs feature architectures by analyzing existing codebase patterns and conventions, then providing comprehensive implementation blueprints with specific files to create/modify, component designs, data flows, and build sequences
tools: Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput
model: sonnet
color: green
---
```
```markdown
---
name: code-reviewer
description: Reviews code for bugs, logic errors, security vulnerabilities, code quality issues, and adherence to project conventions, using confidence-based filtering to report only high-priority issues that truly matter
tools: Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput
model: sonnet
color: red
---
```
Notably: **no Edit/Write** on any of the three — all are read/analyze/report roles; code changes happen in the main session, not inside the agents. `code-reviewer`'s body defines an explicit 0–100 confidence rubric and a hard rule: "Only report issues with confidence ≥ 80."

Source: https://github.com/anthropics/claude-plugins-official/tree/main/plugins/feature-dev/agents (fetched 2026-09-04).

### Security-reviewer example from best-practices docs (verbatim)

```markdown .claude/agents/security-reviewer.md
---
name: security-reviewer
description: Reviews code for security vulnerabilities
tools: Read, Grep, Glob, Bash
model: opus
---
You are a senior security engineer. Review code for:
- Injection vulnerabilities (SQL, XSS, command injection)
- Authentication and authorization flaws
- Secrets or credentials in code
- Insecure data handling

Provide specific line references and suggested fixes.
```
Source: https://code.claude.com/docs/en/best-practices (fetched 2026-09-04). Note: this is Anthropic's second worked example and it pins `opus`, unlike the `code-improver`/feature-dev examples which use `sonnet` — i.e. even Anthropic's own docs model-pin security/review work one tier higher than general code tasks, consistent with wshobson's Tier-1-Opus bucket for "architecture, security, code review, production-critical."

### Model-pinning pattern used across every primary source surveyed

| Role | wshobson tier | Anthropic feature-dev | Anthropic best-practices example |
|---|---|---|---|
| Explore/research | Tier 3 Sonnet (some Haiku for search) | Sonnet (`code-explorer`) | — |
| Architecture/design | Tier 1 Opus | Sonnet (`code-architect`) | — |
| Code review | Tier 1 Opus | Sonnet (`code-reviewer`) | — |
| Security review | Tier 1 Opus | — | Opus (`security-reviewer`) |
| Docs/testing/debugging | Tier 3 Sonnet | — | — |
| Fast ops/SEO/deployment | Tier 4 Haiku | — | — |

Disagreement worth flagging: wshobson pins code-review/architecture to **Opus**; Anthropic's own feature-dev plugin pins the equivalent roles to **Sonnet**. Neither source explains the discrepancy — plausibly feature-dev optimizes for cost/latency on a high-frequency workflow while wshobson optimizes for per-call quality on a lower-frequency one. A solo developer should treat "which model for review" as an open tuning knob, not a settled answer.

### Giving a subagent "enough context" — the dispatch-prompt template obra/superpowers prescribes

```text
Fix the 3 failing tests in src/agents/agent-tool-abort.test.ts:

1. "should abort tool with partial output capture" - expects 'interrupted at' in message
2. "should handle mixed completed and aborted tools" - fast tool aborted instead of completed
3. "should properly track pendingToolCount" - expects 3 results but gets 0

These are timing/race condition issues. Your task:
1. Read the test file and understand what each test verifies
2. Identify root cause - timing issues or actual bugs?
3. Fix by: [explicit constraints]

Do NOT just increase timeouts - find the real issue.

Return: Summary of what you found and what you fixed.
```
Structure: (1) specific scope, (2) self-contained context — paste the actual error text/test names, don't reference "the bug," (3) explicit constraints on what NOT to touch, (4) explicit output spec. Source: https://github.com/obra/superpowers/blob/main/skills/dispatching-parallel-agents/SKILL.md (fetched 2026-09-04).

### Minimal set of custom agents worth having, for a solo developer, and why

Cross-referencing what Anthropic ships by default (Explore, Plan, general-purpose — Finding 4), what Anthropic ships as its own plugin opinion (explorer → architect → reviewer — Finding 6), what the highest-adoption community methodology converges on (subagent-driven development's fresh-implementer + task-reviewer + final-broad-reviewer loop — Finding 10), and what the official best-practices doc itself recommends by name (a fresh-context adversarial reviewer — Finding 5), the same *shape* of minimal set recurs everywhere despite different vocabularies:

1. **A reviewer agent, pinned one model tier above your default, read-only tools, no Edit/Write.** This is the single most cross-corroborated role: it's Anthropic's built-in recommendation ("Add an adversarial review step"), Anthropic's own `code-reviewer` plugin agent, wshobson's Tier-1-Opus `code-reviewer`/`security-auditor`, and the final stage of every community SDD loop. Rationale: the built-in `Explore`/`Plan`/`general-purpose` agents already cover exploration and general work reasonably well without a custom definition, but *fresh-context, unbiased review* is a distinct cognitive stance the main session structurally cannot take on its own diff — it's the one role where "a different agent than the one that wrote the code" is the entire value proposition, not just a context-window optimization.
2. **A narrowly-scoped explore/research agent only if the built-in `Explore` agent is measurably failing you** (e.g. the MCP-schema "prompt too long" problem from Finding 13) — otherwise the built-in is free and requires zero maintenance. Don't pre-emptively ship a custom explorer; wait for the built-in to break, then define a lean, tools-restricted replacement (the `lean-explore` pattern: `Glob, Grep, Read, Bash, LS` only, no MCP inheritance).
3. **Nothing else by default.** Every other role (test-writer, docs, planner-as-a-named-agent, per-language specialists) is what the 100–200-agent catalogs (wshobson, VoltAgent, claude-code-templates) are stocked with, and none of the primary sources surveyed offer usage data showing these individually pay for their description-token cost for a single developer working across a small number of repos. The `description` field is loaded for every defined agent regardless of whether it's ever invoked (Finding 2), so an installed-but-rarely-used 40-agent roster is a standing tax, not a one-time cost — directly corroborated by issue #90182 where a ~17-subagent, ~40-skill harness led the main agent to silently skip delegation and do work inline anyway, i.e. the roster's mere existence didn't guarantee it got used.
4. **Prefer the general-purpose built-in over a custom "do-everything" agent, and prefer writing a good dispatch prompt over writing a new named agent**, per obra/superpowers' explicit anti-pattern list and Anthropic's own framing of subagents as a context-management primitive first. A new named agent is worth the description-token cost only once you're dispatching the same role with the same constraints often enough that re-typing the prompt each time is the bigger cost.

---

## Disagreements and open questions

- **Model pinning for review/architecture roles is unresolved between primary sources**: wshobson pins Opus, Anthropic's own feature-dev plugin pins Sonnet for the same roles (code-architect, code-reviewer). No source explains why; this looks like a genuine unsettled tradeoff (cost/latency vs. per-call quality) rather than a documented best practice.
- **Whether the MCP-schema-leaks-into-subagents problem (Finding 13, PR #38045) is still live as of Sept 2026 could not be confirmed.** The current docs (fetched 2026-09-04) describe `tools:` as a clean allowlist with no caveat about MCP schema pass-through, which could mean it was fixed, or could mean the docs simply don't document the edge case. Flagged as an open question rather than asserted either way.
- **No source in this research — including Anthropic's own — publishes 2026-era, current-model-generation numbers for the token-multiplier or performance-lift of subagent/multi-agent use.** The only hard figures (4×/15× tokens, 90.2% eval lift) are from the June 2025 Opus 4/Sonnet 4 era. Whether those ratios still hold for the 2026 model line (which the fetched docs reference as including Opus 5 and "fable") is not established by any source found.
- **No primary source directly ranks agent roles by measured usefulness** (e.g. "reviewer agents produced X% fewer bugs," "test-writer agents caught Y issues"). The "reviewer + explorer as the two load-bearing roles" conclusion in this report is inferred from convergence across independent sources' *design choices* (what they ship, what they recommend), not from any benchmark or user study — this is the report's own synthesis, clearly labeled as such, not a claim any single source makes.
- **Whether large agent catalogs (150-200 agents) are net-positive or net-bloat for a typical user is contested by omission**: none of wshobson, VoltAgent, or claude-code-templates argue explicitly for installing everything, and wshobson's plugin-scoped install model plus VoltAgent's per-category plugin split both implicitly concede that flat, all-agents-loaded is not the intended usage pattern — but neither repo states a recommended maximum agent count for a single project.

---

## Sources

1. Claude Code docs — Subagents (frontmatter fields, built-in agents, model resolution order, tool filtering). PRIMARY. https://code.claude.com/docs/en/sub-agents — fetched 2026-09-04.
2. Claude Code docs — Common workflows (subagent delegation recipe). PRIMARY. https://code.claude.com/docs/en/common-workflows — fetched 2026-09-04.
3. Claude Code docs — Best practices (subagent use for investigation and adversarial review, worked `security-reviewer` example, context-management framing). PRIMARY. https://code.claude.com/docs/en/best-practices — fetched 2026-09-04.
4. wshobson/agents — README (202 agents, 94 plugins, model tier table). PRIMARY (author's repo). https://github.com/wshobson/agents — fetched 2026-09-04.
5. wshobson/agents — docs/agents.md (per-agent model assignments). PRIMARY. https://github.com/wshobson/agents/blob/main/docs/agents.md — fetched 2026-09-04.
6. VoltAgent/awesome-claude-code-subagents — README (158+ agents, 10 categories, plugin install model). PRIMARY (author's repo). https://github.com/VoltAgent/awesome-claude-code-subagents — fetched 2026-09-04.
7. davila7/claude-code-templates — README + GitHub API metadata (100+ agent catalog, 30.5k stars). PRIMARY (author's repo). https://github.com/davila7/claude-code-templates — fetched 2026-09-04.
8. obra/superpowers — README (methodology overview, 281,635 stars). PRIMARY (author's repo). https://github.com/obra/superpowers — fetched 2026-09-04.
9. obra/superpowers — skills/subagent-driven-development/SKILL.md (SDD process, ledger requirement, model-selection-by-task-type). PRIMARY. https://github.com/obra/superpowers/blob/main/skills/subagent-driven-development/SKILL.md — fetched 2026-09-04.
10. obra/superpowers — skills/dispatching-parallel-agents/SKILL.md (dispatch-prompt template, anti-patterns). PRIMARY. https://github.com/obra/superpowers/blob/main/skills/dispatching-parallel-agents/SKILL.md — fetched 2026-09-04.
11. anthropics/claude-plugins-official — plugins/feature-dev/agents/{code-explorer,code-architect,code-reviewer}.md (full verbatim frontmatter+body). PRIMARY. https://github.com/anthropics/claude-plugins-official/tree/main/plugins/feature-dev/agents — fetched 2026-09-04.
12. Anthropic Engineering — "How we built our multi-agent research system." PRIMARY, but dated. https://www.anthropic.com/engineering/multi-agent-research-system — published June 13, 2025, fetched 2026-09-04.
13. anthropics/claude-code PR #38045 — "feat: Add lean-agents plugin for subagent context bloat workaround." PRIMARY (GitHub PR body). https://github.com/anthropics/claude-code/pull/38045 — opened 2026-03-24, fetched 2026-09-04.
14. anthropics/claude-code issue #67994 — "[BUG] 437 subagents is probably too many." PRIMARY (GitHub issue). https://github.com/anthropics/claude-code/issues/67994 — opened 2026-06-12 (closed as stale), fetched 2026-09-04.
15. anthropics/claude-code issue #88822 — "Subagent final report can come back as a bare pointer with no body." PRIMARY (GitHub issue). https://github.com/anthropics/claude-code/issues/88822 — opened 2026-08-22, fetched 2026-09-04.
16. anthropics/claude-code issue #90182 — "[MODEL] Installed project skills and subagents are not loaded; work is done inline at large token cost." PRIMARY (GitHub issue). https://github.com/anthropics/claude-code/issues/90182 — opened 2026-08-27, fetched 2026-09-04.
17. anthropics/claude-code issues #66023, #89249 (corroborating fan-out/cost issues, referenced but not individually quoted at length). PRIMARY. https://github.com/anthropics/claude-code/issues/66023, https://github.com/anthropics/claude-code/issues/89249 — fetched via GitHub search 2026-09-04.
18. thepromptshelf.dev — "Claude Code Subagents: Official Documentation Reference (2026)." SECONDARY (docs mirror/summary blog). https://thepromptshelf.dev/blog/claude-code-subagents-official-documentation-reference-2026/ — published May 21, 2026, fetched 2026-09-04.

**Note on method:** the session's WebSearch budget was exhausted after one query (a shared session-wide limit, not specific to this task), so after the first search this research relied on WebFetch plus direct `curl`/`gh` retrieval of primary GitHub sources (raw READMEs, agent definition files, SKILL.md files, GitHub Issues/PRs via `gh issue view` / `gh pr view`) rather than further search-engine queries. All URLs above were fetched directly, not inferred.

---

## Source check (independent)

Re-fetched six of the most load-bearing claims directly (WebFetch for the two doc/blog-style sources, `gh api`/`gh issue view` for GitHub sources) and compared against the exact wording. All six held up; no edits were made to the claims above since none were UNSUPPORTED or MISATTRIBUTED.

1. **Claim checked:** Finding 1 — 17-field frontmatter schema (2 required: `name`, `description`; 15 optional: `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `effort`, `isolation`, `color`, `initialPrompt`, `experimental`).
   **Verdict: CONFIRMED.**
   **Source re-fetch of https://code.claude.com/docs/en/sub-agents** returns exactly this field list under "Required Fields" (`name`, `description`) and "Optional Fields" (the 15 named fields, including `experimental` as "Map of experimental options (e.g., `cacheTtl`)"). Field count and names match verbatim; no extra or missing fields found.

2. **Claim checked:** Finding 2 — combined subagent descriptions over 15,000 tokens trigger a warning.
   **Verdict: CONFIRMED** (with one added nuance the original claim omitted but did not contradict).
   **Exact quote from https://code.claude.com/docs/en/sub-agents:** "When the combined descriptions of your subagents, except the built-in ones, exceed 15,000 tokens, Claude Code shows a warning at startup with the total token count. Trim the `description` fields of your subagents, and move detail into each subagent's system prompt, which only loads when that subagent runs." The "except the built-in ones" carve-out isn't in the original claim's phrasing, but doesn't undermine it.

3. **Claim checked:** Finding 6 — Anthropic's `code-reviewer` feature-dev agent: tools list `Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, KillShell, BashOutput`, `model: sonnet`, `color: red`, and the quote "Only report issues with confidence ≥ 80... Focus on issues that truly matter — quality over quantity."
   **Verdict: CONFIRMED.**
   Full file re-fetched via `gh api repos/anthropics/claude-plugins-official/contents/plugins/feature-dev/agents/code-reviewer.md`. Frontmatter matches exactly (tools, `model: sonnet`, `color: red`). Body contains verbatim: "**Only report issues with confidence ≥ 80.** Focus on issues that truly matter - quality over quantity." (source uses a plain hyphen, the research doc rendered an em dash — a cosmetic transcription difference only, not a misquote of substance.)

4. **Claim checked:** Finding 7 — wshobson/agents ships 202 agents / 94 plugins, 39.4k GitHub stars, tiered model strategy (Tier 0 Fable 5 / Tier 1 Opus / Tier 2 inherit / Tier 3 Sonnet / Tier 4 Haiku), and the quote "Installing a plugin loads only its components into context — not the whole marketplace."
   **Verdict: CONFIRMED.**
   `gh repo view` reports `stargazerCount: 39404` (≈39.4k). README re-fetch shows "**94 plugins**, **202 agents**, **183 skills**, **105 commands**" and a "What's inside" table confirming 94 plugins / 202 agents exactly. The Tiered model strategy table matches verbatim (Tier 0 Fable 5 "longest-horizon autonomous work," Tier 1 Opus "architecture, security, code review, production-critical," Tier 2 inherit "user-chosen," Tier 3 Sonnet "docs, testing, debugging, API references," Tier 4 Haiku "fast operational tasks, SEO, deployment, content"). The quoted sentence appears verbatim under "How it works": "Installing a plugin loads only its components into context — not the whole marketplace."

5. **Claim checked:** Finding 12 — Anthropic's multi-agent research system post: multi-agent systems use "about 15× more tokens than chats" and a lead-Opus-4/subagent-Sonnet-4 system beat single-agent Opus 4 by 90.2% on an internal eval.
   **Verdict: CONFIRMED, both figures exact.**
   **Exact quote:** "agents typically use about 4× more tokens than chat interactions, and multi-agent systems use about 15× more tokens than chats." **Exact quote:** "a multi-agent system with Claude Opus 4 as the lead agent and Claude Sonnet 4 subagents outperformed single-agent Claude Opus 4 by 90.2% on our internal research eval." Both the 4×/15× figures and the 90.2% figure are verbatim, not paraphrased or rounded.

6. **Claim checked:** Finding 14 — issue #67994 ("437 subagents is probably too many"): 14 review agents returning 140 issues (same ~10 underlying, un-deduplicated), then 140×3=420 adversarial re-review agents, ~6M tokens burned in <15 minutes before being stopped, ~36M tokens estimated if left to finish for 10 real issues, closed as stale/inactive.
   **Verdict: CONFIRMED**, with one date-precision caveat.
   **Exact quote from the issue body** (`gh issue view 67994 -R anthropics/claude-code`): "It dispatched 14 review agents that returned 140 issues. It then spawned 140 adversarial agents in triplicate (420 total) to review from different angles. In <15 minutes it ate thru ~6M tokens before I caught it. After stopping, Fable found that it was the same 10 issues across all 14 reviewers and simply had not been deduplicated. ... I guess it would've been about 36M tokens total, for 10 issues." Closing comment (from `github-actions` bot) reads: "Closing for now — inactive for too long." — matches "closed as stale/inactive." Caveat: the issue was created 2026-06-12 and actually closed 2026-07-25 (not visible from the original claim's single date), a minor precision gap, not a substantive error — the title's own "437" figure (14+420=434, plus rounding/a lead agent) is the issue author's own number, quoted correctly, not independently re-derived by the research doc.

**Reliability note:** All six checked claims — spanning the two official docs pages, one Anthropic engineering blog post, one large community repo's README/metadata, and one GitHub issue — were independently confirmed against freshly re-fetched primary sources with matching or near-verbatim quotes. No fabricated statistics, no misattributed quotes, and no broken source URLs were found among this sample. The one nuance worth flagging for future readers: Finding 14's report date in the original doc reflects the issue's *creation* date, not its *closure* date (closed ~6 weeks later) — cosmetic, not substantive. Given a 6/6 confirmation rate on the most load-bearing (numeric, quoted, or attributed) claims, the rest of the document's sourcing discipline is likely similarly solid, though this check does not cover every claim in the file (e.g., PR #38045, issues #88822/#90182/#66023/#89249, and the obra/superpowers quotes were not independently re-verified in this pass).
