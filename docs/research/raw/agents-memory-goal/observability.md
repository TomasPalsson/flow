# Personal observability for a solo Claude Code developer (2026)

## TL;DR

- The cheapest, highest-signal setup is free and built in: a statusline script (context %, cost, model, git branch), `/usage` (renamed from the old `/cost`), `/context`, and the new `/insights` command that mines your own session logs into an HTML report — zero extra installs. (PRIMARY, code.claude.com, 2026-09)
- `ccusage` is the de-facto community standard for cost/usage reporting — it parses `~/.claude/projects/*.jsonl` entirely locally/offline and is what most "statusline with cost" setups actually shell out to (`bunx ccusage statusline`). (PRIMARY project docs, ccusage.com)
- OpenTelemetry export (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) is the only way to get real per-session/per-tool time-series data (metrics + structured events), including the `claude_code.code_edit_tool.decision` accept/reject signal — but it requires standing up an OTel collector, which is overkill for most solo devs. (PRIMARY, code.claude.com/docs/en/monitoring-usage)
- `claude_code.code_edit_tool.decision` (and the related `claude_code.tool_decision` event) is the closest thing Claude Code ships to a built-in "did this edit stick" signal — a rising reject rate is treated by practitioners as the earliest sign that a harness/prompt change made things worse. (PRIMARY metric definition + SECONDARY interpretation, SigNoz/General Analysis blogs, 2026)
- `~/.claude/projects/<project>/<session>.jsonl` holds the full transcript (every message, tool call, tool result) and is explicitly documented as plaintext, unencrypted, auto-deleted after `cleanupPeriodDays` (default 30 days). Community tools (claude-code-dashboard, claude-devtools, claude-code-metrics, ccusage) all mine this file for everything from "code churn" to "correction rate." (PRIMARY, code.claude.com/docs/en/claude-directory)
- There is no Anthropic-shipped "reverted commit" tracker. What exists is (a) session-local heuristics — keyword-matching user replies like "undo/revert/wrong" as a correction-rate proxy (nacorga/claude-code-metrics), and (b) org-level industry research (GitClear) showing code-churn/duplication trends associated with AI-assisted code, not a per-commit revert metric. This is a real gap. (SECONDARY, GitHub READMEs + GitClear report)
- Consensus practitioner advice for "did the harness change help": don't eyeball a single session — track ratios (lines-of-code or commits per 1M tokens, cache-hit rate, edit-reject rate) over a rolling baseline (7-day trailing average), because single-day swings are dominated by task mix, not agent quality. (SECONDARY/opinion, SigNoz blog, no date given on post)
- Noise to avoid: session cost in isolation (Pro/Max subscribers' `/usage` dollar figure isn't a real bill), `session.id`-level cardinality in OTel backends, treating one rejected edit or one bad session as signal, and dashboards that need a server/database for what a single grep over local JSONL would answer just as well.

## Findings

1. **Claude Code's statusline is a user-supplied shell command wired through `settings.json`, receiving a documented JSON object on stdin.** The official schema includes `model.id`/`display_name`, `cwd`, `workspace.*` (incl. `git_worktree`), `cost.total_cost_usd`/`total_duration_ms`/`total_lines_added`/`total_lines_removed`, `context_window.used_percentage`/`remaining_percentage`/`context_window_size`, `exceeds_200k_tokens`, and (Pro/Max only) `rate_limits.five_hour`/`seven_day` with `used_percentage` and `resets_at`. Configured via `{"statusLine": {"type": "command", "command": "...", "padding": 0}}`.
   Evidence: full field list and example script in the fetched gist, cross-confirmed by the official docs page (which additionally documents `vim.mode`, `output_style.name`, `agent.name`, `worktree.*`, `transcript_path`, and a multi-line statusline example).
   URL: https://code.claude.com/docs/en/statusline (2026, PRIMARY); https://gist.github.com/AKCodez/ffb420ba6a7662b5c3dda2edce7783de (SECONDARY, cross-checked against the primary doc)
   Consensus.

2. **Community consensus on what to show in a statusline: model name, context-window percentage (as a bar), session/day/block cost, and git branch/dirty state.** The 27.8k-star `claude-hud` plugin's default two-line layout is `[Model] │ project git:(branch*)` / `Context ███░░ 45% │ Usage ██░░ 25% (1h30m/5h)`, with cost, daily cost, duration, and token speed as opt-in extras — i.e., the "core four" are model, context%, git, and usage/cost, with everything else (tool activity, subagent tracking, todo progress) considered supplementary.
   Evidence: README, options table (60+ config keys) fetched directly from the repo.
   URL: https://github.com/jarrodwatts/claude-hud (fetched 2026-09-04, PRIMARY — project's own README; 27,826 stars per `gh search repos`)
   Consensus (this is the most-starred tool in the space, strong signal of what people actually want shown).

3. **One named practitioner explicitly argues cosmetic statusline fields (branch, color) are secondary to context-window% and quota visibility, and that "don't think about tokens, just prompt" is obsolete advice.** His recommended 3-line layout: (1) cwd + branch, (2) account email + model + context size — specifically so a dual work/personal Claude user knows which account is billing, (3) context%, 5-hour and 7-day quota bars with reset times. Claims compacting proactively at ~60% context saves roughly half the resubmitted tokens vs. waiting for a forced compact.
   URL: https://www.andrewconnell.com/articles/claude-code-cli-statusline/ (Andrew Connell, published 2026-06-06, SECONDARY, one practitioner's opinion) — the "compact at 60%" figure is his own claim, not sourced to Anthropic.
   Opinion, not consensus.

4. **`/cost` is now an alias for `/usage`; `/stats` does not appear to exist as a current built-in command.** The current cost/usage command surface is: `/usage` (session token/cost breakdown, plan usage bars, attribution by skill/subagent/plugin/MCP, "Loops" rows for scheduled tasks, `d`/`w` toggle for 24h vs 7-day), `/cost` (alias), `/status` (account/model), `/context [all]` (colored context-usage grid), `/tasks` (background work). The dollar figure in `/usage` is computed locally at list price unless an org sets `modelPricing`; it is explicitly *not* your bill for Pro/Max subscribers.
   URL: https://code.claude.com/docs/en/costs (PRIMARY, 2026); https://code.claude.com/docs/en/commands (PRIMARY, 2026 — command table gives `/insights` as "Not available in cloud sessions")
   Consensus (official docs), though older/community writeups (e.g. the dev.to piece below) still refer to a bare `/cost` as if distinct from `/usage`, showing this is recently-superseded naming.

5. **`/insights` is Anthropic's own built-in session-log-mining feature** — it runs against up to 200 not-yet-seen local sessions per invocation (skipping very short ones), and writes a timestamped HTML report to `~/.claude/usage-data/report.html` covering "what you work on, friction points such as misunderstood requests or buggy code, and suggestions for using Claude Code more effectively." Works on any plan/provider; not available for cloud sessions.
   URL: https://code.claude.com/docs/en/costs#analyze-your-usage-patterns (PRIMARY, 2026)
   Consensus (this is the first-party answer to "session log mining" — most third-party dashboards duplicate what `/insights` already does locally).

6. **`~/.claude/projects/<project-path>/<session-id>.jsonl` is the full transcript** — "every message, tool call, and tool result" — plaintext, unencrypted (protected only by OS file permissions), and deleted by Claude Code's own retention sweep after `cleanupPeriodDays` (default 30, minimum 1). Related files: `history.jsonl` (every prompt typed, with timestamp+project, kept indefinitely), `stats-cache.json` (aggregated counts behind `/usage`), `<session>/subagents/` and `<session>/tool-results/` (spilled large outputs), `file-history/<session>/` (pre-edit snapshots for `/rewind`/checkpointing, last 100 checkpoints), `usage-data/` (the `/insights` reports). `claude project purge` deletes all of the above for one project after a confirmation prompt.
   URL: https://code.claude.com/docs/en/claude-directory (PRIMARY, 2026)
   Consensus — this is the authoritative schema/retention reference every third-party JSONL-mining tool builds on.

7. **Every community JSONL-mining tool computes broadly the same derived metrics from that transcript file: tool-call counts/distribution, session duration, token/cache breakdown, error counts, and some form of "correction" or "rework" signal.** Concretely:
   - `msurendra/claude-code-dashboard` (zero-dep Python, static HTML, reads `history.jsonl` + `projects/*/` + `sessions/*.json`) computes four heuristic 0-100 scores — **Efficiency** (productive/total actions), **Autonomy** (fewer interventions = higher), **Friction** (corrections/reverts/rework, lower better), **Outcome** (error rate + test pass proxy) — plus "First-Attempt Success," "Session Shapes" (clean / iterative / death-spiral / exploration / undo-loop), "Prompt Specificity" scoring, a "Correction Tracker" (frequency of "no/wrong/try again"), "Code Churn" (files edited repeatedly or reverted), and "Context Burn." The README explicitly labels these "deterministic heuristics from local data, not model-quality measurements."
   - `matt1398/claude-devtools` (3,902 stars, Electron app) reconstructs what Claude Code's terminal UI now collapses (post-v2.1.20 "Read 3 files" style summaries) — full tool-call I/O, per-turn context attribution across 7 categories (CLAUDE.md, skills, @-mentions, tool I/O, thinking, team overhead, user text), and subagent execution trees with token/cost/duration per node.
   - `nacorga/claude-code-metrics` (SessionEnd hook + skills, JSONL-only, no DB/server) auto-captures per session: `turn_count`, `tool_calls_total`, `tool_distribution`, `tool_errors_count` (tool_result blocks with `is_error=true`), `subagent_invocations`, `user_msg_count`, `short_user_followups_count`, and `correction_keyword_hits` (a conservative regex over "undo/revert/rollback/redo/incorrect/wrong/broken/doesn't work" in user messages) — explicitly documented as "a hint... not a strict correction rate." It pairs this with a `/retrospective` skill for a subjective 0-10 rating, then `/analyze-metrics` correlates the two.
   URLs (all fetched directly, PRIMARY — project READMEs): https://github.com/msurendra/claude-code-dashboard, https://github.com/matt1398/claude-devtools, https://github.com/nacorga/claude-code-metrics
   Consensus on *what to compute* (tool counts, errors, correction/rework signal); the exact heuristics are each author's own invention, so treat specific scores/thresholds as opinion, not standard.

8. **OpenTelemetry export gives Claude Code's only first-party time-series/event data**, enabled via `CLAUDE_CODE_ENABLE_TELEMETRY=1` plus `OTEL_METRICS_EXPORTER`/`OTEL_LOGS_EXPORTER` (`otlp`/`prometheus`/`console`/`none`) and `OTEL_EXPORTER_OTLP_ENDPOINT`. Metrics: `claude_code.session.count`, `claude_code.lines_of_code.count`, `claude_code.pull_request.count`, `claude_code.commit.count`, `claude_code.cost.usage`, `claude_code.token.usage`, `claude_code.code_edit_tool.decision`, `claude_code.active_time.total`. Events (via `OTEL_LOGS_EXPORTER`): `claude_code.user_prompt`, `claude_code.assistant_response`, `claude_code.tool_decision`, `claude_code.tool_result`, `claude_code.api_request`, `claude_code.api_error`, `claude_code.api_refusal`, plus (per a secondary source) `claude_code.permission_mode_changed`, `claude_code.mcp_server_connection`, `claude_code.hook_execution_complete`/`hook_registered`. `prompt.id` links every event from one user turn. Beta tracing (`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`) adds a span tree: `claude_code.interaction` → `llm_request`/`hook`/`tool` (with `tool.blocked_on_user`, `tool.execution`, nested subagent spans).
   URL: https://code.claude.com/docs/en/monitoring-usage (PRIMARY, 2026) — event list cross-confirmed by https://generalanalysis.com/guides/claude-code-control-observability-opentelemetry (SECONDARY)
   Consensus (this is the primary spec).

9. **`claude_code.code_edit_tool.decision` (metric) / `claude_code.tool_decision` (event) is the field people point to as a proxy for "did the harness change help."** Attributes: `tool_name` (Edit/Write/NotebookEdit), `decision` (accept/reject), `source` (config/hook/user_permanent/user_temporary/user_abort/user_reject), `language`. Practitioner framing: "every rejected edit represents tokens spent generating output that contributed nothing... a rising rejection rate means an increasing share of your token spend is producing edits that get thrown away," and "a spike in rejected edits often means a prompt regression or an agent fighting its permission rules." One blog gives a concrete (self-reported, unvalidated by Anthropic) alerting rule: rejection rate >30% or a >10-point weekly increase warrants investigation.
   URLs: https://signoz.io/blog/claude-code-measure-degradation-opentelemetry/ (SECONDARY, no author/date given, opinion) and https://openobserve.ai/blog/claude-agent-sdk-observability-opentelemetry/ (Gorakhnath Yadav, 2026-06-22, SECONDARY, opinion)
   Opinion — the metric is primary/documented, but the specific interpretation and thresholds are one practitioner's judgment call, not Anthropic guidance.

10. **The "how do I know a harness change helped" question has no first-party answer; practitioner consensus across two independent blogs is: track ratios against a rolling baseline, not absolute numbers.** Recommended derived metrics: lines-of-code (or commits, or PRs) per 1M tokens as the core "output per token" signal, cache-hit rate (`cacheRead ÷ (input + cacheRead)`, alert if it drops >15pp week-over-week or below ~60%), and edit-rejection rate. One post explicitly cautions: "a single day of low output could just mean developers were working on complex refactors that produce fewer net lines" — requiring multi-day/week trend observation, not single-session judgment. A second, independent workflow (OpenObserve) frames it as trace/metric/log correlation: spot a cost/token anomaly in the metric → drill into the `llm_request` span by `session.id` → cross-reference `prompt.id` in the logs to see which tool decision or MCP call drove it → compare the same request shape before/after the prompt change.
   URLs: https://signoz.io/blog/claude-code-measure-degradation-opentelemetry/ (SECONDARY, opinion) and https://openobserve.ai/blog/claude-agent-sdk-observability-opentelemetry/ (Gorakhnath Yadav, 2026-06-22, SECONDARY, opinion)
   Contested-adjacent: both agree "trend over baseline, not single session," but propose different concrete formulas/thresholds, and neither is an Anthropic-endorsed methodology.

11. **`ccusage` is the community-standard, install-free CLI for local cost/usage reporting**, parsing local JSONL logs from Claude Code and 15+ other coding-agent CLIs (Codex, OpenCode, Amp, Droid, Gemini CLI, etc.) entirely offline, with cached pricing data — "reads local usage logs... without uploading your data." Reports: daily/monthly/session/`blocks` (5-hour billing-window view with live block + burn rate). Also ships a first-party `statusline` subcommand (`bunx ccusage statusline`) showing model+effort, session/day/block cost, burn rate (color-coded), and context tokens+%; example: `🤖 Fable 5 (high) | 💰 $0.23 session / $1.23 today / $0.45 block (2h 45m left) | 🔥 $0.12/hr | 🧠 25,000 (12%)`.
   URL: https://ccusage.com/ and https://ccusage.com/guide/statusline (PRIMARY, project's own docs, fetched 2026-09-04)
   Consensus (most widely cited community tool; ~4,800+ GitHub stars per a secondary source, https://dev.to/pederaa/... , SECONDARY).

12. **`claude-hud` (jarrodwatts/claude-hud) is the actual project matching "claude-hud" in the research question, not a hypothetical — 27,826 GitHub stars** (via `gh search repos`, live count 2026-09-04), installed as a Claude Code plugin (`/plugin marketplace add jarrodwatts/claude-hud`) rather than a raw statusline script. It reads the same statusline stdin JSON plus the session transcript JSONL directly (for tool/agent/todo activity), re-rendering debounced at 300ms after each interaction. Three presets (Full/Essential/Minimal); notable opt-in fields beyond the core four: `showDailyCost` (cross-session daily ledger in the plugin's own JSON file, resets at local midnight), `showCompactions` (count of `compact_boundary` transcript entries), `showEffortLevel`, `showAdvisor` (reads Claude Code's `/advisor` model), `showAuth`/`showAuthUser` (which account/plan is billing this session).
   URL: https://github.com/jarrodwatts/claude-hud (README fetched directly, PRIMARY)
   Not previously confirmed to exist by any web search — directly verified via `gh api repos/.../readme`.

13. **Other statusline/dashboard tools found but not deeply investigated** (name, stars, one-line role, all via `gh search repos`, 2026-09-04, SECONDARY listing only): `warrendurling/claude-statusline` ("cost-aware status line — live context gauge, per-model token counts, real dollar spend"); `GaoSSR/best-claude-hud` (645★, Rust statusline HUD); `phuryn/claude-usage` (local web dashboard + SQLite at `~/.claude/usage.db`, Homebrew/uv installable, progress bars for Pro/Max — README fetched, PRIMARY); `damejan80/tokentab` (1,158★, cost by model/project/day across Claude Code/Codex/Gemini CLI); `Leanmcp/superview.sh` (2,114★, "see your claude code logs... in your dashboard"); `daaain/claude-code-log` (1,208★, JSONL → HTML/Markdown converter); `vibe-log/vibe-log-cli` (340★, session logging/analysis for Claude Code and Cursor); Grafana-stack options `rockdarko/claude-code-metrics-prometheus`, `acreeger/claude-code-metrics-stack`, `paulrobello/claude-code-metrics-stack`, `Bardin08/cc-otel` (all small, <20★, all OTel-collector-based).
   Consensus that the space is crowded and mostly reinvents the same JSONL-parsing wheel; no single tool is a clear "second place" behind ccusage/claude-hud.

14. **A GitHub-listed "5 dashboards" roundup names**: Torii (org-wide Anthropic-account discovery/spend-per-employee via SSO/OAuth/finance data — an admin tool, not solo-dev), Anthropic Console (official billing, tokens/dollars by workspace/model/API key with CSV export and a per-developer Analytics API), ccusage, "Claude Code Usage Monitor" (Python terminal dashboard with live progress bars, burn-rate velocity, ML-based 5-hour-block forecast), and LiteLLM (self-hosted gateway giving per-developer/team hard budget caps — infra, not observability per se). The article explicitly does not mention claude-hud.
   URL: https://www.toriihq.com/articles/five-claude-code-usage-dashboards-and-monitoring-tools (SECONDARY, vendor content — Torii is itself one of the five tools listed, so treat the ranking as marketing-adjacent)
   Contested/promotional — read the "Torii is #1" framing skeptically since Torii published it.

15. **Official Claude Code cost baselines** (for calibrating whether your own spend is normal): "average cost is around $13 per developer per active day and $150-250 per developer per month, with costs remaining below $30 per active day for 90% of users" across enterprise deployments. Also documents a `Prompt cache (main)` line in `/usage` (v2.1.251+) reporting request count, % of input tokens served from cache, miss count/timing, and warm/cold cache state — a first-party, no-OTel-required version of "cache hit rate."
   URL: https://code.claude.com/docs/en/costs (PRIMARY, 2026)
   Consensus (official figures) — note these are enterprise-deployment averages, not solo-dev-specific; a solo dev running long unattended agent sessions or multiple parallel instances will likely run higher.

16. **GitClear's 2025 AI Copilot Code Quality Report (published January 2026) is the closest thing to industry data on "reverted/undone AI work" at the code level, but it measures churn/duplication, not commit reverts directly.** Findings from 211M changed lines (2020-2024, Google/Microsoft/Meta + enterprise corpora): duplicate code blocks rose from 8.3% to 12.3% of changed lines (2021→2024, ~4x prevalence growth); code attributable to refactoring fell from 25% to under 10% of changed lines over the same window; "copy/paste" code exceeded "moved" (i.e., properly refactored/reused) code for the first time on record. 63% of professional developers reported using AI in development (citing Stack Overflow's 2024 Developer Survey).
   URL: https://www.gitclear.com/ai_assistant_code_quality_2025_research (PRIMARY — GitClear's own research, fetched 2026-09-04; note: this predates and is broader than Claude Code specifically, and the report's own headline year in its title (2025) trails its January 2026 publication date)
   Consensus that AI-assisted code shows more duplication/less refactoring; contested how much of that is Claude-Code-specific vs. AI-coding-tools-in-general, since the dataset isn't broken out by tool.
   **Gap**: no dataset found (primary or secondary) that directly measures "% of Claude Code commits later reverted." The nearest solo-dev-scale proxies are session-local: `correction_keyword_hits` (nacorga/claude-code-metrics) and "Code Churn: files Claude edits repeatedly or that get reverted" (msurendra/claude-code-dashboard) — both are transcript-level heuristics, not git-history revert tracking.

## Downsides and failure modes

- **`/usage`'s dollar figure is not your bill.** For Pro/Max subscribers it's an API-equivalent estimate computed locally at list price; the docs explicitly flag it as irrelevant to actual billing. Org-level `modelPricing` settings can make it match contracted rates, but a solo dev on a subscription plan is looking at a number that means "usage intensity," not "money spent." (PRIMARY, code.claude.com/docs/en/costs)
- **Cost estimates from local JSONL parsing (ccusage, claude-code-metrics, etc.) drift from real spend.** `nacorga/claude-code-metrics`'s README states its own `cost_usd` "will drift 10-20% from your actual Anthropic invoice (cache accounting edge cases, tool result tokens, etc.)" and should be used only for relative, not absolute, comparison. (PRIMARY, project README)
- **Background token usage inflates naive per-session cost tracking**: conversation summarization for `--resume`, scheduled-task check-ins, cross-session messages, and idle "goal check-ins" (capped at 3 between prompts, uncapped before v2.1.246) all burn tokens invisibly — typically under $0.04/session but enough to confuse a delta-based "did my prompt change help" comparison if not filtered out. (PRIMARY, code.claude.com/docs/en/costs)
- **Cache misses silently multiply cost and mask the effect of a real harness change.** A cache miss (session idle beyond the TTL — 1hr on subscription/5min on API by default) reprocesses full context at full price; if you're A/B-testing a prompt change across sessions with different idle gaps, the cache-miss noise can dwarf the signal you're trying to measure. (PRIMARY, code.claude.com/docs/en/costs)
- **`code_edit_tool.decision` conflates unrelated rejection causes** — `source` can be `config`, `hook`, `user_permanent`, `user_temporary`, `user_abort`, or `user_reject`. A spike could mean your prompt got worse, or it could mean a hook or permission-config change is now auto-rejecting things it wasn't before, or you simply Ctrl-C'd more often that day. None of the fetched sources flag this conflation explicitly — it's an inference from the documented attribute list. (PRIMARY attribute list, code.claude.com/docs/en/monitoring-usage; interpretation is mine)
- **OTel session-id cardinality is a known operational cost.** SigNoz's own docs recommend `OTEL_METRICS_INCLUDE_SESSION_ID=false` "if cardinality becomes problematic" — for a solo dev this is unlikely to bite, but it's the standard warning for anyone plugging Claude Code telemetry into a shared backend. (SECONDARY, signoz.io/docs/claude-code-monitoring)
- **Session-log-mining "scores" (Efficiency/Autonomy/Friction/Outcome, Session Shapes, etc.) are self-described as heuristics, not ground truth.** `claude-code-dashboard`'s own README states: "Scores are deterministic heuristics from local data, not model-quality measurements." Treat any tool's 0-100 score or "death spiral" label as a debugging pointer, not a KPI. (PRIMARY, project README)
- **Keyword-based correction/revert detection is explicitly fragile.** `nacorga/claude-code-metrics` labels its own `correction_keyword_hits` field "heuristic, intended as a hint for `/retrospective` pre-fill, not as a strict correction rate" — it will both over-count (sarcastic/hypothetical use of "wrong") and under-count (corrections phrased without the matched keywords, or in non-English). (PRIMARY, project README)
- **Plaintext transcripts are a real exposure surface for anyone mining `~/.claude/projects`.** The official docs warn: "If a tool reads a `.env` file or a command prints a credential, that value is written to `projects/<project>/<session>.jsonl>`." Any dashboard/statusline that reads these files locally is fine; syncing `~/.claude/` to cloud storage (explicitly warned against for `flock` reasons too, per nacorga's README) or uploading transcripts to a third-party SaaS dashboard multiplies this risk. (PRIMARY, code.claude.com/docs/en/claude-directory)
- **`claude-devtools`'s own framing is itself evidence of a failure mode**: it exists specifically because Claude Code's terminal UI (since v2.1.20) collapsed tool output into opaque one-liners ("Read 3 files", "Edited 2 files") with no file paths or diffs, which the README says drew "immediate" community backlash on Hacker News. A statusline/cost dashboard doesn't fix this — it's a separate, UI-transparency failure mode, not a metrics one. (PRIMARY, project README, citing an external HN thread and a blog post the README itself links)
- **GitClear's churn/duplication data is not Claude-Code-specific** and is aggregated across all AI coding assistants 2020-2024 from a handful of large-company codebases — it should not be read as "Claude Code causes 4x more duplicate code," only as general AI-assisted-coding trend data. (PRIMARY report, but scope caveat is my inference from the fetched methodology section)
- **No fetched source gives a validated way to track reverted *commits* specifically** (as opposed to in-session correction signals or code churn). This is a genuine gap in current tooling, not merely a missed search — see gap note under Finding 16.

## Concrete practices / configs (copy-pasteable)

### 1. Minimal statusline (bash, zero dependencies) — context % + model + git branch

`~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
```

`~/.claude/statusline.sh`:
```bash
#!/bin/bash
input=$(cat)
MODEL=$(echo "$input" | jq -r '.model.display_name')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
BRANCH=$(git -C "$(echo "$input" | jq -r '.cwd')" branch --show-current 2>/dev/null)
FILLED=$((PCT * 10 / 100))
printf "[%s] %s (%s) $%.2f%s\n" "$MODEL" \
  "$(printf '█%.0s' $(seq 1 $FILLED))$(printf '░%.0s' $(seq 1 $((10-FILLED))))" \
  "${PCT}%" "$COST" "${BRANCH:+ git:($BRANCH)}"
```
(Source fields per PRIMARY schema: `model.display_name`, `context_window.used_percentage`, `cost.total_cost_usd`, `cwd` — https://code.claude.com/docs/en/statusline)

### 2. Cost/usage — ccusage statusline (no custom script needed)

```json
{
  "statusLine": {
    "type": "command",
    "command": "bunx ccusage statusline",
    "padding": 0
  }
}
```
Or via npx: `"command": "npx -y ccusage statusline"`. Flags worth setting: `--visual-burn-rate emoji`, `--context-low-threshold`, `--context-medium-threshold`, `--cost-source both` (shows both Claude Code's own cost figure and ccusage's independent estimate side by side — useful sanity check).
(PRIMARY, https://ccusage.com/guide/statusline)

### 3. Session-log mining, first-party, zero install

```
/insights
```
Run periodically (analyzes up to 200 not-yet-seen local sessions per run); report lands at `~/.claude/usage-data/report.html`. `/context` for a live per-turn breakdown of what's eating your context window right now.
(PRIMARY, https://code.claude.com/docs/en/costs#analyze-your-usage-patterns)

### 4. OpenTelemetry — minimal local setup to see metrics + the accept/reject signal

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=console      # or otlp for a real backend
export OTEL_LOGS_EXPORTER=console
export OTEL_METRIC_EXPORT_INTERVAL=1000   # short interval for a solo/short-lived session
claude
```
For a real backend (e.g. local OTel collector on :4317):
```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```
To watch edit accept/reject specifically, alert on `claude_code.code_edit_tool.decision` where `decision="reject"`, segmented by `tool_name` and `language`.
Privacy note: `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_CONTENT`, and `OTEL_LOG_RAW_API_BODIES` are **off by default** — turn them on only if you specifically need prompt/tool content in the export, since they will capture secrets that pass through tool calls.
(PRIMARY, https://code.claude.com/docs/en/monitoring-usage)

### 5. Session-level rework/correction tracking + "did the harness change help" loop (solo-dev scale)

```bash
git clone https://github.com/nacorga/claude-code-metrics.git
cd claude-code-metrics
./scripts/install.sh   # registers a SessionEnd hook; restart Claude Code
```
Then per session (optional but recommended): run `/retrospective` at session end to pair the auto-captured objective metrics (`cost_usd`, `tool_errors_count`, `correction_keyword_hits`, `tool_calls_total`, etc.) with a manual 0-10 rating; `/analyze-metrics` (markdown in-conversation) or `/metrics-report` (static HTML, `--since`/`--project` flags) to see correlations over time. Everything lands in `~/.claude/metrics/auto.jsonl` — greppable/jq-able, no server.
This is the most direct fetched answer to "how do people decide if a harness change helped" at solo-dev scale: compare `correction_rate`/`tool_errors_count`/`cost_usd` week-over-week before vs. after a CLAUDE.md or skill change, using `/metrics-diff` (on the tool's roadmap) or manual `jq` filtering by date.
(PRIMARY, https://github.com/nacorga/claude-code-metrics)

### 6. Retention / privacy hygiene (applies to all the above, since they all read plaintext transcripts)

`~/.claude/settings.json`:
```json
{
  "cleanupPeriodDays": 14
}
```
Lowers how long raw JSONL transcripts (which may contain secrets printed by tool calls) are kept, from the 30-day default. To purge a specific project's stored transcripts/memory entirely: `claude project purge` (prints the deletion plan, asks for confirmation).
(PRIMARY, https://code.claude.com/docs/en/claude-directory)

## Disagreements and open questions

- **Whether `code_edit_tool.decision` reject-rate spikes should be read as "harness regressed" or "permission config changed."** Both SigNoz and OpenObserve blogs frame rising rejects as a quality-regression canary, but neither fetched source discusses the `source` attribute's other values (config/hook auto-rejects vs. genuine user rejection) as a confound — this looks like an under-examined gap in current practitioner writing, not a resolved disagreement.
- **What counts as "noise" in cost tracking is genuinely contested between sources.** Andrew Connell (practitioner) dismisses branch/color cosmetics as noise and elevates quota visibility; the SigNoz/OpenObserve blogs treat raw `claude_code.cost.usage` as noisy unless normalized into per-token-output ratios; Anthropic's own docs treat the `/usage` dollar figure itself as approximate-by-design for subscribers. There is no single agreed noise floor.
- **No consensus tool for git-level "reverted AI commit" tracking exists in what was found.** GitHub search for "co-authored-by claude revert," "ai commit attribution git," and related terms returned zero repos. This may be a genuinely unmet need (solo devs currently improvise with `git log --author` + manual `git revert` grepping) or may exist under naming this search didn't surface — flagged as an open question rather than a settled absence.
- **Whether `/stats` ever existed as a distinct Claude Code command, or whether the research question's phrasing conflated it with `/usage`/`/status`, is unresolved** — current official docs (fetched 2026) list no `/stats` command; it's possible this refers to an older/renamed command, a third-party tool's own `stats` subcommand (e.g. `ccusage`'s reports), or misremembered naming.
- **The exact thresholds given in the SigNoz post (>30% reject rate, >20% LoC/token drop, >15pp cache-hit drop) are that author's own suggested starting points, explicitly not attributed to Anthropic or validated against real fleet data** — worth treating as a template to calibrate against your own baseline, not an industry number.
- **Session budget note**: this research session's WebSearch quota (shared across the whole Claude session, not per-agent) was exhausted after 3 of the planned 6+ distinct queries, before dedicated queries could run for "~/.claude/projects JSONL mining," "claude-hud," and "reverted AI commits" specifically. All findings on those three sub-topics were instead obtained via WebFetch on URLs surfaced by the earlier searches, plus `gh search repos`/`gh api .../readme` (GitHub search + direct README fetches, which are not subject to the WebSearch budget). This satisfies "primary sources, READMEs, official docs" per the method but means fewer independent secondary-blog perspectives were sampled on those three sub-topics than on statusline/OTel/costs.

## Sources

**PRIMARY (official Anthropic docs, code.claude.com):**
- https://code.claude.com/docs/en/monitoring-usage — OpenTelemetry metrics, events, config (fetched 2026-09-04)
- https://code.claude.com/docs/en/statusline — statusline JSON schema, config, examples (fetched 2026-09-04)
- https://code.claude.com/docs/en/costs — `/usage`, `/cost`, `/insights`, cost baselines, background usage, prompt cache stats (fetched 2026-09-04)
- https://code.claude.com/docs/en/commands — command reference incl. `/insights`, `/status`, `/context`, `/tasks` (fetched 2026-09-04)
- https://code.claude.com/docs/en/claude-directory — `~/.claude` file/directory schema, retention, purge (fetched 2026-09-04)

**PRIMARY (project's own docs/READMEs, fetched directly):**
- https://ccusage.com/ — ccusage overview (fetched 2026-09-04)
- https://ccusage.com/guide/statusline — ccusage statusline integration (fetched 2026-09-04)
- https://github.com/jarrodwatts/claude-hud — README, config reference, 27,826★ (fetched 2026-09-04)
- https://github.com/phuryn/claude-usage — README, JSONL→SQLite dashboard (fetched 2026-09-04)
- https://github.com/msurendra/claude-code-dashboard — README, feature/score list (fetched 2026-09-04)
- https://github.com/matt1398/claude-devtools — README, 3,902★ (fetched 2026-09-04)
- https://github.com/nacorga/claude-code-metrics — README, schema, correction-rate design (fetched 2026-09-04)
- https://www.gitclear.com/ai_assistant_code_quality_2025_research — GitClear's own 2025 report, published Jan 2026 (fetched 2026-09-04)

**SECONDARY (practitioner blogs, vendor docs, roundups):**
- https://signoz.io/blog/claude-code-measure-degradation-opentelemetry/ — degradation-measurement methodology, thresholds (fetched 2026-09-04, author/date not stated on page)
- https://signoz.io/docs/claude-code-monitoring/ — SigNoz's own setup docs, cardinality guidance (fetched 2026-09-04)
- https://generalanalysis.com/guides/claude-code-control-observability-opentelemetry — event/attribute cross-reference (fetched 2026-09-04)
- https://openobserve.ai/blog/claude-agent-sdk-observability-opentelemetry/ — Gorakhnath Yadav, published 2026-06-22 (fetched 2026-09-04)
- https://www.andrewconnell.com/articles/claude-code-cli-statusline/ — Andrew Connell, published 2026-06-06 (fetched 2026-09-04)
- https://www.toriihq.com/articles/five-claude-code-usage-dashboards-and-monitoring-tools — vendor roundup (fetched 2026-09-04)
- https://dev.to/pederaa/how-to-track-claude-code-usage-in-2026-built-in-commands-ccusage-and-desktop-dashboards-compared-1kk1 — comparison piece (fetched 2026-09-04)
- https://gist.github.com/AKCodez/ffb420ba6a7662b5c3dda2edce7783de — community statusline field/schema reference, cross-checked against official docs (fetched 2026-09-04)

**GitHub search results (repo existence/star-count evidence, via `gh search repos`, 2026-09-04, not independently fetched beyond metadata unless noted above):** warrendurling/claude-statusline, GaoSSR/best-claude-hud, hadamyeedady12-dev/claude-ultimate-hud, kylesnowschwartz/tail-claude-hud, MJYKIM99/ClaudeGlance, polyxmedia/claude-hud-lcars, DangJin/claudecode-ink-hud, rithkott/claude-thing, anhannin/codex-hud, daaain/claude-code-log, Leanmcp/superview.sh, ZeroSumQuant/claude-conversation-extractor, dreampulse/claude-code-logger, arsenyinfo/claude-code-logger, damejan80/tokentab, vibe-log/vibe-log-cli, rockdarko/claude-code-metrics-prometheus, acreeger/claude-code-metrics-stack, paulrobello/claude-code-metrics-stack, Bardin08/cc-otel, and others under the "claude code metrics" search.

**Fetch attempted but failed (noted for transparency, not used as evidence):**
- https://getdx.com/blog/measure-ai-code-assistants/ — 404 Not Found
- https://github.com/search?q=claude-hud (web UI) — 429 Too Many Requests (superseded by successful `gh search repos claude-hud`)

## Source check (independent)

Method: picked the 6 most load-bearing claims (specific numbers, exact field names/lists, and named attributions) and re-fetched each cited primary source directly (plus `gh api` for the one GitHub star count) rather than trusting the summary. Verdicts below.

---

**1. Cost baselines — Finding 15** ("$13/developer/active day, $150-250/developer/month, below $30/active day for 90% of users")
Source: https://code.claude.com/docs/en/costs
Verdict: **CONFIRMED**
Exact quote: "Across enterprise deployments, the average cost is around \$13 per developer per active day and \$150-250 per developer per month, with costs remaining below \$30 per active day for 90% of users."
This is a word-for-word match to the finding.

---

**2. `~/.claude/projects/<project>/<session>.jsonl` retention and plaintext status — Finding 6**
Source: https://code.claude.com/docs/en/claude-directory
Verdict: **CONFIRMED**
Exact quotes:
- "`projects/<project>/<session>.jsonl` | Full conversation transcript: every message, tool call, and tool result"
- "The default is 30 days and the minimum is 1; setting `0` fails with a validation error."
- "Transcripts and history are not encrypted at rest. OS file permissions are the only protection. If a tool reads a `.env` file or a command prints a credential, that value is written to `projects/<project>/<session>.jsonl`."
All three sub-claims (contents, 30-day default/1-day minimum, plaintext/unencrypted framing) match the finding exactly, including the near-verbatim credential-leak sentence the doc uses in Finding 6's downside note.

---

**3. `/insights` — 200-session cap and report path — Finding 5**
Source: https://code.claude.com/docs/en/costs#analyze-your-usage-patterns (cross-checked against /docs/en/commands)
Verdict: **CONFIRMED**
Exact quote: "A single run analyzes up to 200 sessions it hasn't seen before and skips very short ones... Claude Code writes the latest report to `~/.claude/usage-data/report.html` and saves a timestamped copy of each run in the same directory." Content description confirmed near-verbatim: "writes an HTML report covering what you work on, friction points such as misunderstood requests or buggy code, and suggestions for using Claude Code more effectively." /docs/en/commands also confirms: "Not available in [cloud sessions]."

---

**4. Statusline JSON schema fields — Finding 1**
Source: https://code.claude.com/docs/en/statusline
Verdict: **CONFIRMED**
Every field cited in the finding appears in the doc's field table exactly as named: `model.id`/`model.display_name`, `cwd`/`workspace.current_dir`, `workspace.project_dir`/`added_dirs`/`git_worktree`/`repo.*`, `cost.total_cost_usd`/`total_duration_ms`/`total_lines_added`/`total_lines_removed`, `context_window.used_percentage`/`remaining_percentage`/`context_window_size`, `exceeds_200k_tokens`, and `rate_limits.five_hour`/`seven_day` each with `used_percentage` and `resets_at`. The doc's own example JSON reproduces these fields with matching sample values (e.g. `"used_percentage": 8`, `"resets_at": 1738425600`). One nuance: `context_window_size` sits under the `context_window` object (`context_window.context_window_size`), not top-level as the finding's prose sentence might read out of context — a minor phrasing looseness, not a factual error, since the finding's own field list writes it correctly among the `context_window.*` group.

---

**5. `claude-hud` GitHub star count (27,826) — Finding 12**
Source: `gh api repos/jarrodwatts/claude-hud --jq '.stargazers_count'` (live GitHub API, not WebFetch's rounded "27.8k" display)
Verdict: **CONFIRMED**
Live API result: `27826` — an exact match to the finding's cited figure. (WebFetch of the README page itself only renders the abbreviated "27.8k stars" in GitHub's UI, which is consistent with but doesn't independently prove the exact digit count; the `gh api` call gives the precise number and confirms it.)

---

**6. OpenTelemetry metrics + `code_edit_tool.decision` attributes + event list — Finding 8**
Source: https://code.claude.com/docs/en/monitoring-usage
Verdict: **PARTIAL** — the metrics list and the `code_edit_tool.decision` attributes are exactly confirmed; the event-list *sourcing* is not quite right.
Exact quotes:
- Metrics table matches finding's list exactly: `claude_code.session.count`, `claude_code.lines_of_code.count`, `claude_code.pull_request.count`, `claude_code.commit.count`, `claude_code.cost.usage`, `claude_code.token.usage`, `claude_code.code_edit_tool.decision`, `claude_code.active_time.total`.
- Decision attributes match exactly: "`tool_name`: Tool name (\"Edit\", \"Write\", \"NotebookEdit\")... `decision`: User decision (\"accept\", \"reject\")... `source`: ...one of \"config\", \"hook\", \"user_permanent\", \"user_temporary\", \"user_abort\", or \"user_reject\"... `language`: Programming language of the edited file."
- Where it's off: the finding attributes `claude_code.permission_mode_changed` and `claude_code.mcp_server_connection` to "a secondary source" (generalanalysis.com) alongside `hook_execution_complete`/`hook_registered`, implying none of the three are in Anthropic's own docs. In fact the **primary** docs list `claude_code.permission_mode_changed` (event 10) and `claude_code.mcp_server_connection` (event 12) directly — these are first-party documented, not secondary-source additions. Only `hook_execution_complete`/`hook_registered` were not found in the primary events list I fetched (12 events total; none named `hook_execution_complete` or `hook_registered`) — those two remain unconfirmed against the primary source. The primary source also documents a `claude_code.auth` event (login/logout) that Finding 8 omits entirely.
Net effect: the finding under-attributes two real primary-documented events to a secondary source, and doesn't confirm two other event names it lists. Everything else in the finding checks out.

---

**Reliability note**: All 5 code.claude.com/docs primary-source claims and the GitHub star count checked out as exact, word-for-word or number-for-number matches — this research document's PRIMARY-labeled findings are trustworthy. The one PARTIAL is a sourcing/attribution nuance (secondary-source hedge applied to facts that are actually primary-documented), not a factual error in the underlying numbers or field names. No UNSUPPORTED or MISATTRIBUTED claims were found among the 6 checked, so no inline `[UNVERIFIED]` edits were made to the original document. Given the consistently high hit rate on this sample, the remaining un-spot-checked findings (2, 3, 7, 9-11, 13-14, 16) are plausible but were not independently re-verified here.
