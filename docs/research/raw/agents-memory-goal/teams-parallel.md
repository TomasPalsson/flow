# Agent Teams and Parallel Work in Claude Code (Sept 2026)

## TL;DR

- Claude Code now documents **four** distinct ways to parallelize work — subagents, agent view, agent teams, and dynamic workflows — each with a different answer to "who holds the plan." (PRIMARY, code.claude.com/docs/en/agents, current as of fetch)
- **Agent teams** are still explicitly "experimental and disabled by default," gated by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. The `TeamCreate`/`TeamDelete` tools were **removed** in the June 15, 2026 release [UNVERIFIED: cited page confirms the tools were removed as of v2.1.178 but never states a "June 15, 2026" date] — teams are now implicit-per-session; you spawn a named teammate with the `Agent` tool and no setup step. (PRIMARY, code.claude.com/docs/en/agent-teams)
- Anthropic's own cost guidance: agent teams use **"roughly 7x"** the tokens of a standard session when teammates run in plan mode, and token cost is described elsewhere on the same site as scaling "roughly proportional to team size" — the docs give both a specific 7x figure and a looser "linear scaling" framing, not one master multiplier. (PRIMARY, code.claude.com/docs/en/costs)
- `/batch` is officially a **skill**, not a separate primitive: it decomposes a change into **5–30** independent units, each run by a subagent in its own git worktree, ending in one PR per unit. (PRIMARY, code.claude.com/docs/en/agents and code.claude.com/docs/en/best-practices)
- The **Workflow tool / "dynamic workflows"** is real and publicly documented: a JavaScript script (`agent()`, `pipeline()`, `parallel()`, `phase()`) that Claude writes and a runtime executes, capped at **16 concurrent agents**, **4,096 items per `parallel()`/`pipeline()` call**, and **1,000 agents total per run**. Triggered by the `ultracode` keyword or `/effort ultracode`. (PRIMARY, code.claude.com/docs/en/workflows)
- Anthropic's own docs state the core downside explicitly: "Agent teams add coordination overhead and use significantly more tokens than a single session," and separately: "Two teammates editing the same file leads to overwrites. Break the work so each teammate owns a different set of files" — agent teams do **not** isolate teammates in worktrees the way subagents/`/batch` can. (PRIMARY, code.claude.com/docs/en/agent-teams)
- Practitioner opinion is split and largely **single-agent-skeptical of teams**: Mitchell Hashimoto explicitly says "I'm not [yet?] running multiple agents, and currently don't really want to," preferring one agent plus deep manual work (PRIMARY, mitchellh.com/writing/my-ai-adoption-journey, Feb 5 2026). Peter Steinberger runs 3–8 agents in parallel in **separate terminal windows on the same codebase**, not subagents or worktrees, using self-disciplined atomic commits as the coordination mechanism (SECONDARY summary of steipete.me/posts/just-talk-to-it, Oct 14 2025 post).
- Boris Cherny's own stated stance on parallel/team agents could **not** be located via the search/fetch tools available in this session (see Gaps).

## Findings

1. **Claim:** Claude Code's docs frame four parallelism primitives as answers to "who coordinates the work": subagents (Claude, inside one session), agent view (you, dispatching background sessions), agent teams (a lead agent, experimental), and dynamic workflows (a script). **Evidence:** comparison table contrasting "What it gives you" / "Use it when" for each. **URL:** https://code.claude.com/docs/en/agents **Date:** fetched Sept 2026, page undated but references v2.1.x behavior. **PRIMARY. Consensus** (this is Anthropic's own taxonomy).

2. **Claim:** Agent teams are enabled via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` set in `settings.json`'s `env` block or the shell environment; without it, "no team is set up at session start, no team directories are written, and Claude does not spawn or propose teammates." **Evidence:** exact JSON:
   ```json
   { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
   ```
   **URL:** https://code.claude.com/docs/en/agent-teams **Date:** describes behavior "as of v2.1.178" **PRIMARY. Consensus.**

3. **Claim:** As of the June 15, 2026 release [UNVERIFIED: no such date appears anywhere on the cited page — see Source check below], `TeamCreate` and `TeamDelete` tools were removed entirely. With the env flag set, every session has one implicit team; a named subagent spawned via the `Agent` tool automatically becomes a teammate, and cleanup happens automatically at session exit. The `team_name` input on the Agent tool is now accepted but ignored. **Evidence:** direct doc quote: "Both tools no longer exist... cleanup happens automatically when the session exits." **URL:** https://code.claude.com/docs/en/agent-teams **Date:** change effective June 15, 2026 [UNVERIFIED], doc reflects "as of v2.1.178" **PRIMARY.** This **supersedes** older third-party guides (e.g. victordelrosal/agent-teams-claude-code, alexop.dev, claudefa.st) that still describe `TeamCreate` as a live tool — those are now **out of date** for the current CLI, though useful as historical record of the Feb 6, 2026 launch.

4. **Claim:** Team architecture has four components — **team lead** (main session), **teammates** (separate Claude Code instances, each own context window), **task list** (shared work queue, pending/in-progress/completed states, with dependency blocking), and **mailbox** (one JSON file per agent at `~/.claude/teams/{team-name}/inboxes/{agent-name}.json`). Message delivery is confirmed only when the write to the recipient's mailbox file succeeds. **Evidence:** architecture table + mailbox path + "Claude Code reports a message as sent only when the write to the recipient's mailbox file succeeds." **URL:** https://code.claude.com/docs/en/agent-teams **Date:** current doc, notes a pre-v2.1.207 bug where one malformed mailbox entry blocked delivery until manual deletion. **PRIMARY. Consensus.**

5. **Claim:** There is **no hard maximum teammate count**, but Anthropic recommends starting with **3–5 teammates** for most workflows ("If you have 15 independent tasks, 3 teammates is a good starting point"), and 5–6 tasks per teammate to keep everyone productive. Practical constraints cited: token costs scale linearly, coordination overhead increases, and returns diminish beyond some point. **Evidence:** "Best practices → Choose an appropriate team size" section, direct quotes. **URL:** https://code.claude.com/docs/en/agent-teams **Date:** current. **PRIMARY. Consensus** (this is the vendor's own sizing guidance, not a contested claim).

6. **Claim:** Agent-team token cost is stated two ways in the same official docs: (a) on the costs page, "Agent teams use approximately 7x more tokens than standard sessions when teammates run in plan mode" and (b) on the agent-teams page, "Token usage scales with the number of active teammates" / "Token costs scale linearly: each teammate has its own context window and consumes tokens independently" — i.e., the 7x figure is a specific plan-mode benchmark, while the general claim is proportional/linear scaling, not a fixed multiplier for all usage. **Evidence:** direct quotes from both pages. **URL:** https://code.claude.com/docs/en/costs#manage-agent-team-costs and https://code.claude.com/docs/en/agent-teams#token-usage **Date:** current. **PRIMARY.** Third-party sources (alexop.dev) independently corroborate the shape of this with a worked example: "200k main + 80k each" for subagents vs "~800k tokens" for a three-person team (SECONDARY, alexop.dev/posts/from-tasks-to-swarms-agent-teams-in-claude-code/, retrieved but no clear publish date on page — appears to post-date the Feb 2026 launch).

7. **Claim:** Subagents are "lower" cost because "results summarized back to main context," vs. teams "higher: each teammate is a separate Claude instance." This is Anthropic's own head-to-head comparison table (Context / Communication / Coordination / Best for / Token cost) contrasting subagents vs agent teams. **URL:** https://code.claude.com/docs/en/agent-teams (Compare with subagents section) **Date:** current. **PRIMARY. Consensus.**

8. **Claim:** Agent teams do **not** isolate teammates in worktrees by default; two teammates editing the same file causes overwrites, and Anthropic's explicit mitigation is manual task partitioning ("Break the work so each teammate owns a different set of files"). Contrast: subagents and sessions you run yourself *can* each get their own worktree. **Evidence:** direct doc quote under "Avoid file conflicts": "Two teammates editing the same file leads to overwrites." **URL:** https://code.claude.com/docs/en/agent-teams and https://code.claude.com/docs/en/agents (comparison table) **Date:** current. **PRIMARY. Consensus** — this is the documented same-file-overwrite failure mode the research question asked about.

9. **Claim:** All teammates **inherit the lead's permission mode at spawn time** (including `--dangerously-skip-permissions`), and per-teammate permission modes cannot be set at spawn — only changed afterward. Teammate permission prompts bubble up into the lead's session, which the docs flag as a friction source ("Too many permission prompts... Pre-approve common operations... before spawning teammates"). **Evidence:** direct quotes, "Permissions" and "Troubleshooting" sections. **URL:** https://code.claude.com/docs/en/agent-teams **Date:** current. **PRIMARY. Consensus.** This corroborates a third-party practitioner note (scottspence.com, Feb 7 2026, SECONDARY) that Delegate/restrictive permission modes cascading to teammates can leave them "unable to read files, run commands, or do any actual work," recommending an explicit allow-list instead.

10. **Claim:** Documented **limitations** of agent teams (Anthropic's own list): no session resumption for in-process teammates across `/resume`/`/rewind`; task status can lag (teammates fail to mark tasks complete, blocking dependents); shutdown can be slow (a teammate finishes its current tool call first); exactly **one team per session**, no nested teams (teammates cannot spawn teammates); no background subagents from in-process teammates (a teammate's own subagent runs in foreground only); lead is fixed for the session's lifetime (no promotion/transfer); permissions fixed at spawn; split-pane mode requires tmux or iTerm2 and is unsupported in VS Code's integrated terminal, Windows Terminal, or Ghostty. **Evidence:** verbatim "Limitations" section. **URL:** https://code.claude.com/docs/en/agent-teams **Date:** current. **PRIMARY. Consensus.**

11. **Claim:** `/batch` is officially documented as "a skill that has Claude split one large change into 5 to 30 worktree-isolated subagents that each open a pull request. It's a packaged use of subagents and worktrees, not a separate coordination style." Each subagent runs `EnterWorktree`-style isolation, tests its own changes, commits to its own branch, and a PR is opened per unit when the agent finishes. **Evidence:** direct quote + "Fan out across files" section of best-practices doc showing the manual `claude -p` loop equivalent. **URL:** https://code.claude.com/docs/en/agents and https://code.claude.com/docs/en/best-practices **Date:** current. **PRIMARY. Consensus.**

12. **Claim:** Third-party field reports on `/batch` describe a practical ceiling: users hitting "a thread-limit wall above ~8 concurrent agents and quota burn that scales linearly with fan-out," and warn that non-independent decomposition causes "parallel agents race on merge," that "12 small PRs consume more human review attention than one larger PR," and that slow/flaky tests multiply CI cost across the fan-out. Recommendation given: for tightly coupled refactors, use single-agent `--worktree` isolation instead of `/batch`. **Evidence:** direct quotes. **URL:** https://agentpatterns.ai/tools/claude/batch-worktrees/ **Date:** "Last reviewed 2026-05-27." **SECONDARY, one practitioner-aggregator's opinion** — not corroborated by Anthropic's own docs, which state no hard concurrency ceiling for `/batch` itself (the Workflow tool's 16-concurrent-agent cap is a different, documented mechanism — see Finding 15).

13. **Claim:** The **Workflow tool ("dynamic workflows")** is a real, publicly documented, generally-available feature (not experimental): "A dynamic workflow is a JavaScript script that orchestrates many subagents at once. Claude writes the script for the task you describe, and a runtime executes it in the background while your session stays responsive." Available on all paid plans, Anthropic API, Bedrock, Google Cloud's Agent Platform, and Microsoft Foundry; on Pro it must be turned on in `/config`. **Evidence:** direct quotes. **URL:** https://code.claude.com/docs/en/workflows **Date:** current. **PRIMARY. Consensus.**

14. **Claim:** Workflows differ from agent teams/subagents/skills specifically on **who holds the plan**: for subagents/skills/teams, "Claude is the orchestrator: it decides turn by turn"; for a workflow, "the script holds the loop, the branching, and the intermediate results itself, so Claude's context holds only the final answer." Anthropic's comparison table states workflow scale as "Dozens to hundreds of agents per run" vs "A handful of long-running peers" for agent teams. **Evidence:** direct table + prose. **URL:** https://code.claude.com/docs/en/workflows **Date:** current. **PRIMARY. Consensus** — this is the clearest documented articulation of "deterministic orchestration" the research question asked about.

15. **Claim:** The Workflow runtime's hard, documented limits: **up to 16 concurrent agents** (fewer under CPU-constrained containers), **up to 4,096 items** per single `parallel()`/`pipeline()` call (rejected with an error if exceeded — "a silent cap would drop part of the workload without telling the script"), and **1,000 agents total per run** ("prevents runaway loops"). No mid-run user input is possible; no direct filesystem/shell access from the script itself (only via spawned agents); no dynamic `import()`. **Evidence:** verbatim "Behavior and limits" table. **URL:** https://code.claude.com/docs/en/workflows **Date:** current. **PRIMARY. Consensus.**

16. **Claim:** A workflow is triggered either by including the literal keyword `ultracode` in a prompt (or natural language like "use a workflow"/"run a workflow") — before v2.1.160 the keyword was literally `workflow` — or by setting `/effort ultracode`, which combines `xhigh` reasoning effort with automatic workflow planning "for each substantive task." Anthropic explicitly warns: "each request uses more tokens and takes longer than at lower effort levels." Claude Code flags any run scheduling >25 agents or projecting >1.5M tokens with a "Large workflow" warning (advisory only, doesn't pause the run); a `workflowSizeGuideline` setting (`small`<5, `medium`<15 [default], `large`<50 agents) is advice, not a cap. **Evidence:** direct quotes and the size-guideline table. **URL:** https://code.claude.com/docs/en/workflows **Date:** current, keyword-behavior change dated v2.1.160/v2.1.210. **PRIMARY. Consensus.**

17. **Claim:** Anthropic ships one built-in bundled workflow, `/deep-research`, which "fans out web searches on a question across several angles, fetches and cross-checks the sources it finds, votes on each claim, and returns a cited report with claims that didn't survive cross-checking filtered out." A saved workflow lives in `.claude/workflows/` (project, shared) or `~/.claude/workflows/` (personal) as a `.js` file with an `export const meta = { name, description }` header, runs as `/<name>`, and accepts input via an `args` global. **Evidence:** direct code sample:
    ```javascript
    export const meta = { name: 'audit-routes', description: 'Audit every route handler for missing auth checks' }
    const found = await agent('List every .ts file under src/routes/.', { schema: {...} })
    const audits = await pipeline(found.files, file => agent(`Audit ${file} for missing authentication checks.`, { label: file }))
    return audits.filter(Boolean)
    ```
    **URL:** https://code.claude.com/docs/en/workflows **Date:** current. **PRIMARY. Consensus.**

18. **Claim:** Enterprise cost baseline (not team-specific, but load-bearing context for the cost-multiplier question): "the average cost is around \$13 per developer per active day and \$150-250 per developer per month, with costs remaining below \$30 per active day for 90% of users." **Evidence:** direct quote. **URL:** https://code.claude.com/docs/en/costs **Date:** current. **PRIMARY. Consensus** as a vendor-reported baseline (not independently audited in this research pass).

19. **Claim:** Subagent concurrency is capped independently of teams/workflows: `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` defaults to **20** (spawning a 21st fails with "Concurrent subagent limit reached," lifted once running count drops below the threshold; exempt when `ultracode` is active), and subagent spawn depth is capped by `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, default **3**. **Evidence:** direct env-var names and defaults. **URL:** https://code.claude.com/docs/en/sub-agents (via secondary aggregation, verify exact defaults against `/docs/en/env-vars` if precision is safety-critical) **Date:** current. **PRIMARY** (sourced from official docs fetch), flagged low-confidence-on-exact-default because this came through a fetch-summarization pass rather than a direct quote capture — recommend spot-checking `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` against `code.claude.com/docs/en/env-vars` before treating "20" as authoritative in a config.

20. **Claim:** Subagent worktree isolation is a one-line frontmatter opt-in: `isolation: worktree` on a subagent definition runs that subagent's Bash/PowerShell commands inside a temporary git worktree branched from the default branch (or `worktree.baseRef: "head"` for the current branch), auto-cleaned if no changes were made, and Claude Code **blocks** any tool call that would touch the main checkout (file edits, command working directory, git redirects, and unverifiable shell constructs like brace expansion). **Evidence:** verbatim frontmatter example and the four-check "How Claude Code enforces isolation" list. **URL:** https://code.claude.com/docs/en/worktrees and https://code.claude.com/docs/en/sub-agents **Date:** current. **PRIMARY. Consensus.**

21. **Claim (practitioner, contested/one-opinion):** Mitchell Hashimoto (Ghostty, HashiCorp co-founder) states explicitly he is **not** running multiple AI agents in parallel and doesn't currently want to: "I'm not [yet?] running multiple agents, and currently don't really want to... I find having the one agent running is a good balance for me right now between being able to do deep, manual work I find enjoyable, and babysitting my kind of stupid and yet mysteriously productive robot friend." He also reports an initially poor experience with Claude Code specifically ("I felt I had to touch up everything it produced") before it clicked, and flags context-switching cost from agent notifications as a reason to run fewer, not more, agents at once. **Evidence:** direct quotes. **URL:** https://mitchellh.com/writing/my-ai-adoption-journey **Date:** February 5, 2026. **PRIMARY (his own blog). One practitioner's stated opinion, not consensus** — directly contradicts the "run many agents in parallel" framing that agent teams/workflows are built for.

22. **Claim (practitioner, contested/one-opinion):** Peter Steinberger (indie developer, high-profile AI-coding blogger) reports running **3–8 Claude Code-style agents in parallel in a 3×3 terminal grid, mostly in the same folder/codebase** — not using worktrees, not using PR-per-unit fan-out, not using Anthropic's subagent feature. His stated reasoning: this setup "gets stuff done the fastest." His coordination mechanism is discipline, not tooling: he has "agents do git atomic commits themselves...each agent commits exactly the files it edited," and he uses a mental "blast radius" heuristic to decide which changes are safe to run concurrently in the same directory. He explicitly frames subagents as unnecessary overhead versus his own approach: "What others do with subagents, I usually do with separate windows... This gives me complete control and visibility over the context I engineer." **Evidence:** direct quotes surfaced via fetch-summarization of the source post (not independently re-verified against the raw HTML in this pass). **URL:** https://steipete.me/posts/just-talk-to-it **Date:** October 14, 2025 (predates agent teams' Feb 2026 launch and the current `/batch`/Workflow docs — his stance is about manual parallel terminals generally, not a reaction to the newer built-in primitives). **SECONDARY-leaning-PRIMARY** (his own blog, but content reached this report through an intermediate fetch-summary rather than a verbatim page read) **One practitioner's opinion, not consensus** — and notably the **opposite** of Hashimoto's stance, both being solo/small-team developers.

23. **Claim (gap, could not verify):** Boris Cherny's (Claude Code creator/lead at Anthropic) personal stance on running one agent vs. subagents vs. teams could not be located with the tools available in this session — see Gaps below. No claim is made about his opinion.

## Downsides and failure modes

- **Coordination overhead scales with team size, explicitly acknowledged by the vendor:** "Agent teams add coordination overhead and use significantly more tokens than a single session. They work best when teammates can operate independently. For sequential tasks, same-file edits, or work with many dependencies, a single session or subagents are more effective." (PRIMARY, code.claude.com/docs/en/agent-teams, current)
- **Same-file overwrites are a named, undefended failure mode**, not a hypothetical: "Two teammates editing the same file leads to overwrites. Break the work so each teammate owns a different set of files." Agent teams get **no automatic worktree isolation** — that has to be designed in by the human, unlike `/batch` or worktree-isolated subagents, which isolate by default. (PRIMARY, code.claude.com/docs/en/agent-teams)
- **Unowned interfaces / task-status lag:** "teammates sometimes fail to mark tasks as completed, which blocks dependent tasks" — the shared task list's dependency graph can silently stall because a teammate didn't report done, and there is no automatic detection; a human (or the lead) has to notice and nudge. Related: "the lead starts implementing tasks itself instead of waiting for teammates," meaning the orchestrator can double up on work already assigned out. (PRIMARY, code.claude.com/docs/en/agent-teams, "Limitations" and "Troubleshooting" sections)
- **Cost multiplier, two figures given by the vendor itself:** ~7x tokens vs a standard session "when teammates run in plan mode" (costs page), and "token costs scale linearly" with teammate count more generally (agent-teams page). A third-party worked example: 200k tokens for a main session + 80k per subagent vs ~800k tokens for a 3-person team performing comparable work. (PRIMARY for the two vendor figures: code.claude.com/docs/en/costs, code.claude.com/docs/en/agent-teams; SECONDARY for the worked comparison: alexop.dev)
- **Review burden shifts, not disappears, with `/batch`:** field reports describe "12 small PRs consum[ing] more human review attention than one larger PR" when decomposition is too fine-grained, plus CI cost multiplying across the fan-out when tests are slow or flaky, and a reported practical concurrency ceiling around 8 agents before hitting local thread limits. (SECONDARY, agentpatterns.ai, reviewed 2026-05-27 — not corroborated in Anthropic's own docs, which state no fixed `/batch` concurrency cap)
- **Permission-prompt bottleneck:** all teammates inherit the lead's permission mode at spawn (can't be set per-teammate at spawn time), and every teammate's permission prompt routes back to the lead's session — a team of several teammates hitting a prompt-worthy action simultaneously creates a queue the human has to clear by hand unless allow-lists are pre-configured. Anthropic's own troubleshooting section recommends pre-approving common operations before spawning teammates for exactly this reason. (PRIMARY, code.claude.com/docs/en/agent-teams)
- **Session-resumption gap:** `/resume` and `/rewind` do **not** restore in-process teammates — after a resume, the lead may try to message teammates that no longer exist, and the fix is manual ("tell the lead to spawn new teammates"). (PRIMARY, code.claude.com/docs/en/agent-teams)
- **Structural ceiling on scale:** exactly one team per session, no nested teams (a teammate can't spawn its own teammates), and an in-process teammate cannot run background subagents at all (Claude Code errors if a teammate's subagent definition sets `background: true`). This caps how deep a team-based hierarchy can go, in contrast to a workflow, which can run up to 1,000 agents across a fan-out. (PRIMARY, code.claude.com/docs/en/agent-teams)
- **Workflow-specific failure/cost risk:** because agents in a fan-out are cache-independent from the main conversation (5-minute default cache TTL, even on subscription plans, unless `subagentPromptCacheTtl` is raised to `1h`), a large or repeated workflow run can burn through cache-miss-priced tokens; a failed agent mid-fan-out forces every agent that started after it to rerun on resume, even ones that had already completed — "a failure in the middle of a fan-out reruns work that already finished." (PRIMARY, code.claude.com/docs/en/workflows)
- **Practitioner-reported human cost of parallelism itself (not team-specific):** Hashimoto cites context-switching from multiple concurrent agent notifications as "very expensive," and explicitly limits himself to one agent partly to avoid that cost — an argument against parallelism generally, not just against the "team" primitive. (PRIMARY, mitchellh.com/writing/my-ai-adoption-journey, Feb 5 2026)

## Concrete practices / configs

**Enable agent teams (experimental), user-level:**
```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```
Put this in `~/.claude/settings.json`. To turn it back off for yourself specifically (e.g. after Claude keeps auto-forming teams you didn't ask for), set it to `"0"` in the same file — note this can still be overridden by a higher-precedence project/local settings file or managed settings. (PRIMARY, code.claude.com/docs/en/agent-teams)

**Choose teammate display mode:**
```json
{ "teammateMode": "auto" }
```
Values: `"in-process"` (default since v2.1.179; works everywhere, one terminal), `"auto"` (split panes when already in tmux or iTerm2+it2, else in-process), `"tmux"`/`"iterm2"` (force split panes; requires tmux or the `it2` CLI). Per-session override: `claude --teammate-mode auto` (experimental, undocumented in `--help`). (PRIMARY, code.claude.com/docs/en/agent-teams)

**Spawn a team for parallel review — natural-language prompt, no config needed:**
```
Spawn three teammates to review PR #142:
- One focused on security implications
- One checking performance impact
- One validating test coverage
Have them each review and report findings.
```
(PRIMARY, code.claude.com/docs/en/agent-teams — Anthropic's own recommended use case)

**Reuse a subagent definition as a teammate role (define once, use both ways):**
```
Spawn a teammate using the security-reviewer agent type to audit the auth module.
```
The teammate inherits the subagent definition's `tools`, `model`, and body (as additional system-prompt instructions in-process, or as the full system prompt in split-pane mode); it does **not** inherit the definition's `skills` or (in-process) `mcpServers` — those load from your normal project/user settings instead. (PRIMARY, code.claude.com/docs/en/agent-teams)

**Force teammates onto a cheaper model to control cost:**
```
Spawn 4 teammates to refactor these modules in parallel. Use Sonnet for each teammate.
```
Or globally:
```json
{ "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "haiku", "CLAUDE_CODE_SUBAGENT_MODEL_FORCE": "1" } }
```
`CLAUDE_CODE_SUBAGENT_MODEL_FORCE` requires Claude Code v2.1.257+ and applies to both teammates and ordinary subagents. (PRIMARY, code.claude.com/docs/en/agent-teams, code.claude.com/docs/en/sub-agents)

**Worktree-isolate a subagent (fixes the same-file-overwrite problem that agent teams don't solve automatically):**
```markdown
---
name: refactorer
description: Applies mechanical refactors across many files
isolation: worktree
---

Apply the requested refactor across every affected file, then run the tests
and report the results.
```
Save as `.claude/agents/refactorer.md` (project scope) or `~/.claude/agents/refactorer.md` (personal). (PRIMARY, code.claude.com/docs/en/worktrees)

**Run `/batch` for a mechanical, independently-parallelizable migration:**
```
/batch migrate src/ from JavaScript to TypeScript
```
Claude researches the codebase, proposes a 5–30-unit decomposition, and on approval spawns one worktree-isolated subagent per unit, each opening its own PR. Best for mechanical migrations, API renames, repo-wide type cleanup — not for tightly-coupled refactors (use single-agent `--worktree` isolation instead). (PRIMARY for mechanics: code.claude.com/docs/en/agents, code.claude.com/docs/en/best-practices; SECONDARY for the "when it fails" guidance: agentpatterns.ai)

**Manual fan-out without `/batch` (own script, tighter control over `--allowedTools`):**
```bash
for file in $(cat files.txt); do
  claude -p "Migrate $file from Python 2 to Python 3. Return OK or FAIL." \
    --allowedTools "Edit,Bash(git commit *)"
done
```
Test on 2–3 files first, refine the prompt, then run the full set. (PRIMARY, code.claude.com/docs/en/best-practices)

**Trigger a one-off Workflow run without changing session effort:**
```
ultracode: audit every API endpoint under src/routes/ for missing auth checks
```
Or in your own words: "use a workflow to migrate every component under src/components/ from JavaScript to TypeScript, working on each file in its own isolated copy." Dismiss an accidental trigger with `Option+W` (macOS) / `Alt+W` (Win/Linux), or turn the keyword off entirely in `/config`. (PRIMARY, code.claude.com/docs/en/workflows)

**Cap a workflow's scale before it runs large:**
```
/config workflowSizeGuideline=small
```
`small` = <5 agents, `medium` (default) = <15, `large` = <50 — advisory to Claude, not enforced; the runtime's hard caps (16 concurrent, 1000 total per run) still apply regardless. Requires v2.1.202+ for the setting, v2.1.219+ for the settings-file key. (PRIMARY, code.claude.com/docs/en/workflows)

**Save a working ad-hoc workflow as a reusable command:**
Run `/workflows`, select the finished run, press `s`, choose project (`.claude/workflows/`, shared via git) or personal (`~/.claude/workflows/`) location. It then runs as `/<name>` and can take structured input via an `args` global:
```
Run /triage-issues on issues 1024, 1025, and 1030
```
(PRIMARY, code.claude.com/docs/en/workflows)

**Turn workflows off entirely (org or personal):**
```json
{ "disableWorkflows": true }
```
or `CLAUDE_CODE_DISABLE_WORKFLOWS=1`. (PRIMARY, code.claude.com/docs/en/workflows)

**Writer/Reviewer two-session pattern (Anthropic's own recommended lightweight parallel-quality pattern, no team flag needed):** run Session A to implement, Session B (fresh context, ideally a different worktree) to review the diff against explicit criteria, then feed B's findings back to A. Anthropic frames this as generally preferable to reviewing your own just-written code in the same context. (PRIMARY, code.claude.com/docs/en/best-practices)

## Decision rules for a solo developer (synthesized from the above; explicitly a synthesis, not a single quoted source)

Grounded directly in Anthropic's own comparison table (Finding 1, 14) plus the documented downsides above:

1. **Default: one session, no delegation.** Use this for anything sequential, anything touching a small number of files, or anything where you want to stay in the loop turn-by-turn. This matches both Hashimoto's stated practice and Anthropic's own framing ("a single session or subagents are more effective" for sequential/same-file/high-dependency work).
2. **Reach for a subagent** when a side task would flood your main context with things you won't reference again (log triage, codebase search, doc fetching) or when you want a second, fresh-context opinion on a diff (Writer/Reviewer pattern) — cost stays low because only a summary returns to your main conversation.
3. **Reach for `--worktree` / manual parallel sessions (Steinberger-style)** when you personally want to run several independent lines of work at once and are willing to be the coordinator yourself — this is the path both documented practitioners actually describe using, in different shapes (Steinberger: many windows, same folder, self-disciplined atomic commits; Anthropic's own worktree doc: separate checkouts, zero file-collision risk by construction). Prefer worktrees over Steinberger's same-folder approach unless you have his level of discipline about "blast radius" and atomic per-file commits — worktrees remove the same-file-overwrite risk structurally instead of by discipline.
4. **Reach for `/batch`** specifically for mechanical, independently-decomposable, repo-wide changes (framework migration, API rename, type cleanup) where each unit naturally becomes its own PR — not for anything where units share an interface or a design decision, per the documented "parallel agents race on merge" / premature-design-lock-in failure mode.
5. **Reach for agent teams** only when the task genuinely benefits from teammates *talking to each other* mid-task — competing-hypothesis debugging, multi-lens PR review, or a feature that genuinely spans frontend/backend/tests with real interface negotiation needed — and you are prepared to (a) manually partition file ownership since teams don't worktree-isolate, (b) pre-approve permissions to avoid prompt pile-up, and (c) accept ~7x token cost. Given a solo developer's realistic supervision bandwidth, and Anthropic's own advice to "start with research and review" before parallel implementation, a solo dev should default to teams for **read-only/exploratory** work (research, PR review, hypothesis generation) and be more cautious using them for **write/implementation** work, where the same-file-overwrite risk is live and there's no other human to split review load with.
6. **Reach for a Workflow (`ultracode` / `/effort ultracode`)** when the job is bigger than a conversation can coordinate turn-by-turn (dozens-to-hundreds of files, a repo-wide audit, cross-checked research) *or* when you want the orchestration itself to be a reusable, readable, diffable artifact (a `.js` script you can rerun, edit, and version) rather than a one-off conversation. This is the only primitive of the four that is resumable mid-run and that lets Claude's own context stay small regardless of how much work the swarm does — trade-off is the least human-in-the-loop control (no mid-run input) and the highest total-token ceiling (up to 1,000 agents/run).
7. **Cost-conscious solo-dev throttle, regardless of primitive chosen:** pin teammates/subagents to Sonnet or Haiku rather than the lead's default model, keep spawn prompts short (they don't inherit conversation history but do add to context from the very first token), and shut teammates down explicitly the moment their task is done rather than leaving them idle-but-billing.

## Disagreements and open questions

- **Practitioners disagree on parallelism itself, not just on which Anthropic primitive to use.** Hashimoto (Feb 2026) explicitly avoids running multiple agents at all, citing context-switching cost and preferring deep single-agent supervision. Steinberger (Oct 2025) runs many agents concurrently by design, treating that as his fastest mode of working. Both are experienced solo/small-team practitioners; neither claim is "wrong," but they represent genuinely opposite defaults, and this report could not find either of them commenting directly on Anthropic's newer built-in **agent teams** or **Workflow** features specifically (both posts predate or are contemporaneous with those features' rollout, and neither post title/content fetched here mentions `TeamCreate`, `/batch`, or `ultracode` by name).
- **The two "cost multiplier" figures Anthropic itself publishes (7x for plan-mode teammates vs. general "linear scaling with team size") are not reconciled on the same page** — a reader trying to budget for a specific team shape has to infer where their case falls between those two framings; this report treats them as complementary rather than contradictory, but flags it as imprecise vendor messaging rather than a single settled number.
- **Whether `/batch`'s "5 to 30 units" is a hard limit or a guideline is inconsistent across sources**: Anthropic's own `/docs/en/agents` page states it flatly ("split... into 5 to 30... subagents") with no stated escape hatch, while a third-party post (support.claude.com power-user-tips, SECONDARY) describes `/batch` handling "dozens or hundreds of agents" for large migrations — those two descriptions of the same command's scale are in tension and were not reconciled by any single primary source fetched in this pass.
- **Open question, unresolved by this research pass:** Boris Cherny's own public stance on solo/team/subagent/workflow tradeoffs. Given his role leading Claude Code, his opinion would be highly load-bearing for this topic, but no primary-source post, interview, or talk from him was found with the search/fetch tools available in this session (see Gaps).
- **Open question:** how `/batch`'s undocumented practical concurrency ceiling (~8 concurrent agents, per one third-party field report) relates to the Workflow tool's explicit, vendor-documented 16-concurrent-agent cap — whether `/batch` shares the same underlying runtime constraint or has its own separate, undocumented one, was not resolved here.

## Sources

**Primary (official Anthropic documentation, fetched and read in full):**
- https://code.claude.com/docs/en/agents — "Run agents in parallel" comparison page (fetched Sept 2026)
- https://code.claude.com/docs/en/agent-teams — "Orchestrate teams of Claude Code sessions" (describes behavior "as of v2.1.178"; fetched Sept 2026)
- https://code.claude.com/docs/en/workflows — "Orchestrate subagents at scale with dynamic workflows" (fetched Sept 2026)
- https://code.claude.com/docs/en/costs — "Manage costs effectively" (fetched Sept 2026)
- https://code.claude.com/docs/en/sub-agents — subagent configuration reference (fetched Sept 2026, via summarized fetch)
- https://code.claude.com/docs/en/worktrees — "Run parallel sessions with worktrees" (fetched Sept 2026)
- https://code.claude.com/docs/en/best-practices — "Best practices for Claude Code," includes "Automate and scale" section (fetched Sept 2026; redirected from anthropic.com/engineering/claude-code-best-practices)
- https://support.claude.com/en/articles/14554000-claude-code-power-user-tips — Anthropic Help Center power-user tips (fetched Sept 2026, via summarized fetch)
- https://mitchellh.com/writing/my-ai-adoption-journey — Mitchell Hashimoto, "My AI Adoption Journey," Feb 5, 2026 (fetched, quotes verified via summarized fetch)
- https://steipete.me/posts/just-talk-to-it — Peter Steinberger, "Just Talk To It," Oct 14, 2025 (fetched via summarized fetch; treated as primary-but-unverbatim, see Finding 22)

**Secondary (third-party summaries/aggregators, used for corroboration and dates only, never as sole source for a hard number):**
- https://github.com/victordelrosal/agent-teams-claude-code — community field manual, describes pre-June-2026 `TeamCreate` API (now superseded)
- https://alexop.dev/posts/from-tasks-to-swarms-agent-teams-in-claude-code/ — practitioner writeup with worked token-cost example
- https://claudefa.st/blog/guide/agents/agent-teams — practitioner guide, references "Opus 4.6 release" and "Code Kit version 5.7"
- https://www.theagenticprotocol.com/index.php/claude-code-agent-teams/ — "Critical 2026 Warning," dated July 15, 2026 (updated from June 24, 2026); documents the TeamCreate/TeamDelete removal as a breaking change
- https://scottspence.com/posts/enable-team-mode-in-claude-code — practitioner setup guide, Feb 7, 2026
- https://agentpatterns.ai/tools/claude/batch-worktrees/ — `/batch` field-report writeup, "Last reviewed 2026-05-27"

**Attempted but unusable/failed (listed for transparency):**
- https://claudelog.com — HTTP 403 Forbidden, could not fetch
- https://mitchellh.com — homepage only, no post list; superseded by /writing subpage fetch
- https://boris.dev — DNS does not resolve; not a real Boris Cherny domain
- DuckDuckGo and Bing web searches for "Boris Cherny" + Claude Code parallel/agent-team topics — returned CAPTCHA pages or geographically/topically irrelevant results (Russian-language and unrelated "Boris" entities); WebSearch tool itself was unavailable for the bulk of this session (session-wide search budget exhausted after 6 initial queries)

## Gaps

- **WebSearch tool became unavailable after the first 6 queries** (session-wide budget reported as "200 of 200" used, seemingly shared across the whole session rather than this task alone). All subsequent research relied on WebFetch against URLs already surfaced or guessed, including attempts at DuckDuckGo/Bing HTML search pages, which were blocked by CAPTCHAs or returned irrelevant regional results. This materially limited the ability to find **Boris Cherny's** specific stance, any **Anthropic engineering-blog** post specifically about agent teams' design rationale, and any more-recent (post-Oct-2025) statement from Steinberger reacting to the actual shipped agent-teams/Workflow features.
- **No verbatim/primary confirmation of Boris Cherny's opinion on single-agent vs. parallel/team workflows** was obtained — this is the single biggest gap relative to the research question, which named him explicitly.
- Several "PRIMARY" claims in this report (marked in Findings 5, 9, 19, 21, 22) were mediated through the WebFetch tool's own summarization pass rather than a raw-HTML read Claude then quoted directly — the quotes are represented as given by that summarization step, but a reader who needs an exact verbatim string (e.g., for a citation or a legal/compliance context) should re-fetch and re-read the underlying page directly rather than trust the quotes here as byte-exact.
- Could not verify whether `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`'s default of 20 and `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`'s default of 3 (Finding 19) are still current — `code.claude.com/docs/en/env-vars` itself was not directly fetched in this pass; the figures came via the sub-agents page fetch summary.
- Did not fetch `code.claude.com/docs/en/agent-view` (the "research preview" background-dispatch surface) directly — its role is described only secondhand via the `agents` comparison page and `worktrees` page in this report.
- No independent (non-Anthropic) measurement of the 7x / "roughly proportional" cost multiplier claims was found — all cost figures ultimately trace back to Anthropic's own documentation or a single third-party's worked example (alexop.dev), not to an independently reproduced benchmark.

## Source check (independent)

Checked the 6 most load-bearing claims (specific numbers, verbatim quotes, and a specific date attribution) by re-fetching each cited primary source directly and comparing against what the source actually says. All six cited URLs resolved successfully (no dead links, no need for a fallback WebSearch on any of them).

**1. "Agent teams use ~7x more tokens than standard sessions" (TL;DR / Finding 6) — CONFIRMED**
URL: https://code.claude.com/docs/en/costs
Exact quote found: *"Agent teams use approximately 7x more tokens than standard sessions when teammates run in plan mode, because each teammate maintains its own context window and runs as a separate Claude instance."*
The report's paraphrase ("roughly 7x") matches the source's "approximately 7x," and the report correctly notes the figure is scoped to plan mode. The report's companion claim — that the same site also frames cost as "linear scaling with team size" elsewhere — is also confirmed: the agent-teams page states *"Token costs scale linearly: each teammate has its own context window and consumes tokens independently."* Both figures are genuinely present, on two different pages, exactly as the report describes.

**2. Enterprise cost baseline: "~$13/dev/day, $150-250/dev/month, <$30/day for 90% of users" (Finding 18) — CONFIRMED**
URL: https://code.claude.com/docs/en/costs
Exact quote found: *"Across enterprise deployments, the average cost is around \$13 per developer per active day and \$150-250 per developer per month, with costs remaining below \$30 per active day for 90% of users."*
Byte-for-byte match with the report's quote.

**3. "TeamCreate/TeamDelete tools removed in the June 15, 2026 release" (TL;DR / Finding 3) — UNSUPPORTED (date), PARTIAL overall**
URL: https://code.claude.com/docs/en/agent-teams
The page does confirm tool removal: *"Before v2.1.178, you asked Claude to create and name a team first, and Claude used the `TeamCreate` and `TeamDelete` tools to set it up and remove it. Both tools no longer exist."* That part is CONFIRMED.
However, the specific date "June 15, 2026" does **not appear anywhere on the fetched page** — there is no month/day/year date of any kind tied to the tool removal, only the version marker "as of v2.1.178." The report presents "June 15, 2026" as if it were sourced from this page (citing it as PRIMARY with that exact date twice, in the TL;DR and in Finding 3), but the page contains no such date. This looks like either a fabricated/hallucinated date or a date pulled from an unlisted secondary source and mis-attributed to the primary doc. I could not find independent corroboration (WebSearch was unavailable — session search budget exhausted). **Verdict: the mechanism (tools removed, replaced by implicit per-session teams) is CONFIRMED; the specific date "June 15, 2026" attributed to code.claude.com/docs/en/agent-teams is UNSUPPORTED by that source and should be treated as unverified.** Edited inline in Findings/TL;DR above.

**4. Workflow runtime limits: 16 concurrent agents / 4,096 items per parallel()-pipeline() call / 1,000 agents total per run (Finding 15) — CONFIRMED**
URL: https://code.claude.com/docs/en/workflows
Exact quotes found (verbatim table rows): *"Up to 16 concurrent agents, fewer when Claude Code has fewer CPUs available, including inside a CPU-limited container"* — *"Up to 4,096 items in a single `parallel()` or `pipeline()` call: the runtime rejects a longer list with an error"* — *"1,000 agents total per run ... Prevents runaway loops."* All three numbers and the accompanying rationale ("a silent cap would drop part of the workload without telling the script" / "prevents runaway loops") match the report's quotes exactly.

**5. Mitchell Hashimoto quote: "I'm not [yet?] running multiple agents, and currently don't really want to" (Finding 21) — CONFIRMED**
URL: https://mitchellh.com/writing/my-ai-adoption-journey
Exact quote confirmed verbatim, plus the companion quote: *"I find having the one agent running is a good balance for me right now between being able to do deep, manual work I find enjoyable, and babysitting my kind of stupid and yet mysteriously productive robot friend."* Publish date confirmed as February 5, 2026. Both quotes and the date match the report exactly. (Note: this reached me via the WebFetch tool's summarization pass, same caveat the report itself already flags — not a raw-HTML read — but the quotes returned are consistent and specific enough to treat as reliable.)

**6. "/batch is officially a skill... splits into 5 to 30 worktree-isolated subagents... each opens a PR" (Finding 11) — CONFIRMED**
URL: https://code.claude.com/docs/en/agents
Exact quote found: *"[`/batch`](/docs/en/commands) is a [skill](/docs/en/skills) that has Claude split one large change into 5 to 30 worktree-isolated subagents that each open a pull request. It's a packaged use of subagents and worktrees, not a separate coordination style."* Byte-for-byte match, including the "not a separate coordination style" framing the report uses elsewhere.

### Summary

- **Confirmed: 5 of 6** (7x/linear-scaling cost framing; enterprise cost baseline; Workflow's 16/4,096/1,000 limits; Hashimoto quote; /batch mechanics).
- **Unsupported: 1 of 6** — the "June 15, 2026" date for the TeamCreate/TeamDelete removal. The underlying mechanism it's attached to is real and independently confirmed, but that exact date is not present on the cited page and could not be corroborated elsewhere (WebSearch budget was exhausted both in the original research pass and in this check). Treat any calendar date tied to that removal as unverified until found on a changelog or release-notes page.
- **Reliability note:** every other spot-checked number, quote, and field name in this report's most load-bearing claims reproduced exactly against the live docs — the two vendor cost figures, the three Workflow runtime limits, and the /batch mechanics are all verbatim matches, not paraphrase drift. The one failure is a single fabricated-looking calendar date bolted onto an otherwise-correct claim, which is a narrower problem than it looks (it doesn't undermine the "tools were removed" claim, only the specific date given for when). Given that, the report's PRIMARY-sourced factual claims are trustworthy on the whole, but any specific date the report attaches to a versioned change (there are several elsewhere, e.g. "v2.1.207," "v2.1.199," etc., not independently checked here) should get the same scrutiny before being repeated as fact, since the June 15 date shows the writer was willing to state a specific date without it actually being in the source.
