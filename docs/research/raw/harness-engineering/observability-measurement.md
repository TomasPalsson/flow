# Measuring Whether Your Agent Harness Is Improving

## TL;DR

- Claude Code has **built-in OpenTelemetry export** (metrics, structured log events, and beta traces) — off by default, turned on with `CLAUDE_CODE_ENABLE_TELEMETRY=1` plus at least one `OTEL_*_EXPORTER` — and it already emits the counters a solo dev needs: tokens, cost, lines added/removed, commits, PRs, session count, active time, and **tool-edit accept/reject decisions**. This is the primary substrate for any harness-improvement measurement. (PRIMARY, code.claude.com, 2026)
- The single most load-bearing built-in signal for "is my harness getting better" is `claude_code.code_edit_tool.decision` (accept vs reject, with a `source` breakdown distinguishing auto-config accepts from real human accepts/rejects) — track its acceptance rate over time as a proxy for output quality/trust. (PRIMARY, code.claude.com/docs/en/monitoring-usage, 2026)
- For a solo developer who doesn't want to stand up an OTel collector, **`ccusage`** (18.4k GitHub stars, MIT, by ryoppippi) reads the local `~/.claude/projects/*.jsonl` transcripts with zero network calls and gives daily/weekly/monthly/session/5-hour-block cost and token reports, plus a statusline mode — this is the de facto community standard for lightweight cost tracking. (PRIMARY README via WebFetch of github.com/ryoppippi/ccusage, and PRIMARY ccusage.com, 2026)
- Several newer JSONL-mining dashboards (token-dashboard, claude-session-dashboard, claude-code-stats, claude-monitor) go beyond cost and surface **hotspot/waste analytics**: expensive prompts, tool/file heatmaps, cache-hit rates, duplicate reads — this is the closest thing to a free "is my workflow wasteful" report for a solo dev. (SECONDARY, GitHub READMEs, 2026)
- There is **no first-party "claude plugin eval" or official skill-quality benchmark** from Anthropic; the closest tools are third-party community plugins — `skill-doctor` (delegates skill/CLAUDE.md auditing to Claude Code's own `claude-code-guide` agent, scores and writes `~/.skill-doctor/diagnosis.json`) and `claude-doctor`/`plugin-doctor` (schema/spec validation for plugins). Treat these as opinionated community tooling, not a vetted standard. (PRIMARY GitHub READMEs, 2026)
- The industry consensus for agent evals in 2026 is **layered evaluation**: check outcome (task completion) first, then trajectory (tool correctness, step efficiency, plan adherence) to diagnose *why* something failed — outcome-only evaluation is now considered insufficient because an agent can reach the right end state via a wasteful or unsafe path. (SECONDARY synthesis of confident-ai.com guide, 2026)
- At the team/org level, **rework rate** (lines deleted/substantially revised within 30 days of merge ÷ lines added, >1.5x = bloat signal) and **AI revert percentage** (reverted AI-authored lines ÷ merged AI-authored lines, informal 5% threshold for hallucinated-API-style failures) are the emerging metrics for "is AI-assisted work actually durable" — these come from a single vendor's blog (exceeds.ai), not an academic or standards source, so treat them as one practitioner's framework, not consensus. (SECONDARY/opinion, blog.exceeds.ai, 2026)
- Plain DORA metrics (deployment frequency, lead time, change-failure-rate, MTTR) are explicitly called out in 2026 commentary as **necessary but not sufficient** for AI-assisted work, because they can't distinguish "AI made me faster" from "AI made me faster and increased hidden defect rate" — the DX Core 4 + DX AI Measurement Framework (Utilization/Impact/Cost layered on Speed/Effectiveness/Quality/Impact) is the most cited answer, but it's DX's own commercial framework, not a neutral standard. (SECONDARY, getdx.com, 2026)

## Findings

1. **Claude Code emits three independent OTel signals — metrics, log events, and beta traces — each with its own enable switch, and all off unless `CLAUDE_CODE_ENABLE_TELEMETRY=1` is set.** Metrics via `OTEL_METRICS_EXPORTER`, log events via `OTEL_LOGS_EXPORTER`, traces via `OTEL_TRACES_EXPORTER` + `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`. Default export intervals: metrics every 60s, traces/logs every 5s (tunable via `OTEL_METRIC_EXPORT_INTERVAL` etc.). The CLI fails silently on export errors unless `CLAUDE_CODE_OTEL_DIAG_STDERR=1` is set (requires v2.1.179+).
   Source: https://code.claude.com/docs/en/agent-sdk/observability — PRIMARY — fetched 2026-09-04, doc undated but describes current (2026) CLI behavior — standard/documented.

2. **The full metric catalog is**: `claude_code.session.count`, `claude_code.lines_of_code.count` (type: added/removed), `claude_code.pull_request.count`, `claude_code.commit.count`, `claude_code.cost.usage` (USD, with `model`, `query_source`, `agent.name`/`skill.name`/`plugin.name` attribution, `effort`), `claude_code.token.usage`, `claude_code.code_edit_tool.decision` (tool_name, decision accept/reject, source, language), `claude_code.active_time.total` (type: user vs cli).
   Source: https://code.claude.com/docs/en/monitoring-usage — PRIMARY — fetched 2026-09-04 — standard (official reference).

3. **Events include a full audit trail**: `claude_code.user_prompt`, `claude_code.tool_decision` (with `source` distinguishing config/hook/user_permanent/user_temporary/user_abort/user_reject), `claude_code.tool_result` (success, duration_ms, error_type, sizes), `claude_code.api_request`/`api_error`/`api_refusal`, `claude_code.permission_mode_changed`, `claude_code.auth`, `claude_code.mcp_server_connection`. All events and metrics correlate via `prompt.id`, `session.id`, `message.uuid`. Content (prompt text, tool args, raw API bodies) is redacted by default; opt-in via `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT`, `OTEL_LOG_RAW_API_BODIES`.
   Source: https://code.claude.com/docs/en/monitoring-usage and https://code.claude.com/docs/en/agent-sdk/observability — PRIMARY — fetched 2026-09-04 — standard.

4. **Tool-edit acceptance rate is a documented, ready-made proxy for output trust/quality.** The docs give a literal SQL example: `COUNTIF(decision="accept")/COUNT(*) AS acceptance_rate FROM claude_code.tool_decision GROUP BY tool_name`. Tracking this over time (weekly/monthly) as your harness/CLAUDE.md/skills change is a direct, low-effort "is my setup improving" signal — rising acceptance rate with steady or falling reject/user_abort counts suggests the agent is producing more trustworthy diffs.
   Source: https://code.claude.com/docs/en/monitoring-usage (SigNoz-adapted excerpt) — PRIMARY — fetched 2026-09-04 — one clear, well-documented practice, not contested.

5. **Vendor backends for receiving this telemetry are documented/available for SigNoz, AWS CloudWatch, Elastic, Dash0, and generic OTLP collectors.** SigNoz: set `OTEL_EXPORTER_OTLP_ENDPOINT` to `https://ingest.<region>.signoz.cloud:443` with a `signoz-ingestion-key` header; ships a prebuilt Claude Code dashboard template. AWS: exports via **bearer-token auth** (no IAM SDK needed) to `https://monitoring.<region>.amazonaws.com`, token created from CloudWatch console "API Keys" or tied to an IAM user with `CloudWatchAPIKeyAccess`.
   Source: https://signoz.io/docs/claude-code-monitoring/ (PRIMARY, SigNoz's own docs) and https://aws.amazon.com/blogs/mt/analyzing-claude-code-usage-with-cloudwatch-and-opentelemetry/ (PRIMARY, AWS's own blog) — fetched 2026-09-04 — standard/documented, vendor-specific but official.

6. **For a solo dev not running a collector, `ccusage` is the community-standard local tool**: parses `~/.claude/projects/*.jsonl` (and 17 other agent CLIs' logs) entirely locally, no API key, no network call. [UNVERIFIED: independent source-check fetch of the GitHub README confirmed star count/license/author/subcommands but did not surface the specific "zero network calls, reads ~/.claude/projects/*.jsonl" language — plausible and consistent with the tool's documented `--offline` mode, but not directly quoted in this pass.] Subcommands: `daily`, `weekly`, `monthly`, `session`, `blocks` (5-hour billing windows with live monitoring), `statusline` (beta, puts running cost in the shell prompt). Supports `--json`, `--breakdown` (per-model), `--since`/`--until`, `--offline` (cached pricing), and custom pricing overrides via `ccusage.json`. 18.4k GitHub stars, MIT license, author ryoppippi.
   Source: https://ccusage.com/ and https://github.com/ryoppippi/ccusage — PRIMARY (project's own site/README) — fetched 2026-09-04 — standard/consensus tool (most-cited in every "Claude Code cost tools" roundup found in search).

7. **Several newer local dashboards go past raw cost into waste/hotspot analysis.** `token-dashboard` (nateherkai) — Python, scans `~/.claude/projects/`, runs a local server at `127.0.0.1:8080`, surfaces per-prompt cost rankings (flags "large tool results" as the biggest cost driver), tool/file heatmaps, per-project comparison, cache-hit-rate analytics, and a rule-based "Tips" tab (duplicate reads, oversized results, low cache rates). `claude-session-dashboard` (dlupiak) shows subagent dispatch order and per-step context consumption. `claude-code-stats` (AeternaLabsHQ) generates a static interactive HTML report. All run fully local.
   Source: https://github.com/nateherkai/token-dashboard (PRIMARY README) — fetched 2026-09-04; others via search snippets only (SECONDARY, not independently fetched) — one-practitioner tools, not consensus, but directly answers "session-log mining" part of the question.

8. **There is no official Anthropic "claude plugin eval" command or skill-benchmarking spec as of Sept 2026.** What exists is community plugins: `skill-doctor` (amaljithkuttamath) — `/skill-doctor` diagnoses every skill, agent, and CLAUDE.md by delegating evaluation to Claude Code's own built-in `claude-code-guide` agent (rather than a hardcoded checklist) against current docs, writes scores + fixes to `~/.skill-doctor/diagnosis.json`; `/skill-doctor:treat` stages upgrades in a separate directory without touching originals; `/skill-doctor:rollback` restores from backup. Also flags cross-cutting issues like skill overlap and CLAUDE.md content that should be extracted into a skill. Separately, `claude-doctor` (aka-momo) and `plugin-doctor` (mcpmarket) do structural/schema validation of plugin packages (JSON schema, semver, spec alignment) rather than quality scoring.
   Source: https://github.com/amaljithkuttamath/skill-doctor — PRIMARY README — fetched 2026-09-04 — one practitioner's tool, not an Anthropic-sanctioned standard; no primary Anthropic source for a "plugin eval" command was found.

9. **2026 consensus on agent evaluation is layered: outcome first, then trajectory, then component-level.** Outcome evaluation = binary/graded task completion regardless of path. Trajectory evaluation = scoring the plan, tool calls, retries, and reasoning steps that produced the result; an agent can pass outcome eval while failing trajectory eval (wrong tool, wrong params, redundant loops, convoluted route). Recommended metrics for trajectory: tool correctness, argument correctness, step efficiency (no unnecessary retries/loops), plan quality/adherence. Recommended flow: confirm outcome success → inspect trajectory for execution quality → drill into specific components (a tool, a retriever) to find root cause.
   Source: https://www.confident-ai.com/blog/llm-agent-evaluation-complete-guide — SECONDARY (industry guide, not a paper) — fetched 2026-09-04 — this is described as "2026 industry shift," presented as consensus/emerging-standard rather than one lone opinion, but it's still a single vendor's (Confident AI / DeepEval) framing.

10. **A 2026 academic framing reinforces the same point with a concrete failure mode**: one cited example (AgentPex) shows an agent that reached a perfect outcome score (correct final DB state) yet the trajectory evaluation caught it skipping a required verification step, dropping the aggregate score to 85 — i.e., outcome-only scoring would have missed a real reliability problem.
   Source: cited within https://www.confident-ai.com/blog/llm-agent-evaluation-complete-guide (secondary reference to AgentPex, original paper not independently fetched) — SECONDARY, one example, not independently verified — flagged as a gap below.

11. **"Rework rate" and "AI revert percentage" are proposed metrics from a single vendor's blog, not a verified academic or Anthropic-endorsed standard.** Definitions given: Code Rework Rate = (lines deleted or substantially revised within 30 days of merge) ÷ (lines added); >1.5x flagged as "AI bloat." Healthy target: rework between 5–10% of "productivity gains"; >12% flagged as hidden cost (numbers not derived in the piece, presented as the author's thresholds). AI Revert Percentage = AI-generated lines reverted ÷ AI-generated lines merged; informal 5% threshold cited for hallucinated-API/brittle-pattern issues. [UNVERIFIED: independent source-check found the "AI Revert Percentage" concept and 5% threshold are NOT present in the cited URL at all — they appear (as "PR Revert Rate," defined per-PR not per-line, baseline <5%, observed 8% AI vs 3% human) in a *different* exceeds.ai post, https://blog.exceeds.ai/code-quality-metrics-ai-roi/. The 5–10%/>12% rework-rate thresholds also do not appear in either exceeds.ai article checked — that second article instead gives "Rework Rate = Reworked AI lines / total AI lines, baseline under 15%, AI ~2x human rate." Treat this finding as misattributed/conflated across two source articles, not a single clean citation.] Measuring "is the harness improving" is proposed via **matched-cohort difference-in-differences**: establish pre-adoption baseline across metrics, build a matched control cohort, verify parallel trends visually before regressing, segment by task type and interaction mode (plan/ask/agent/edit).
   Source: https://blog.exceeds.ai/measuring-ai-impact-commits-prs/ — SECONDARY, single practitioner/vendor blog, presented as the author's framework — fetched 2026-09-04 — explicitly one practitioner's opinion, not contested by other sources found, but also not corroborated elsewhere; treat thresholds (1.5x, 5-10%, 12%, 5%) as illustrative, not validated benchmarks. [UNVERIFIED: see inline note above — some of these numbers were not found in this URL on independent re-fetch.]

12. **PR Cycle Time and Review Burden are the other two legs of the same framework**: PR Cycle Time = median time from first AI-touched commit to merge vs. matched human-authored PRs baseline (target: AI-assisted turnover <1.3x pre-AI baseline). Review Burden = review iterations/comments/time-to-first-review tracked separately for AI vs. human PRs, with the explicit caveat: "If AI makes you ship faster by dumping work onto reviewers, you did not improve productivity." Quality Delta = post-merge incidents at 30 days + defect rate per 1K lines; cites external research that ">15% of AI commits introduce at least one issue" (source of that 15% figure not verified independently here).
   Source: https://blog.exceeds.ai/measuring-ai-impact-commits-prs/ — SECONDARY, same vendor blog — fetched 2026-09-04 — opinion/framework, the 15% figure is an unverified secondary citation within a secondary source (gap).

13. **DORA metrics alone are explicitly called insufficient for AI-assisted work in 2026 commentary**: DORA "captures the output but not the source" — it can't tell whether a deployment-frequency improvement came from AI tooling, sustainable process change, or a quality trade-off not yet surfaced. The proposed fix (DX's own DX Core 4 + DX AI Measurement Framework) organizes measurement into Speed/Quality (classic DORA) + Effectiveness (Developer Experience Index, 14 factors) + Impact (% of R&D time on new capabilities), with an AI-specific overlay tracking Utilization, Impact (time savings + Core-4 trend deltas), and Cost (ROI). Recommended practice: segment AI-assisted vs. human-only work before computing DORA, and treat change-failure-rate as an early-warning signal when deployment frequency/lead time improve.
   Source: https://getdx.com/blog/dora-metrics-tools/ — SECONDARY-leaning-PRIMARY (DX's own blog describing DX's own framework, so primary for the framework's definition, but their framework is a commercial product, so its "recommendation" is self-interested) — fetched 2026-09-04 — presented as increasingly-consensus critique of DORA-alone, but the proposed replacement is one vendor's product.

14. **The Agent SDK (not the CLI's OTel path) exposes cost/token data directly on the message stream with no external backend needed** — `total_cost_usd` and per-model `modelUsage`/`model_usage` on the `ResultMessage`. Explicitly documented as **client-side estimates, not authoritative billing** (computed from a bundled price table; can drift from real billing on pricing changes, unrecognized models, or billing rules the client can't model). For authoritative numbers, the docs point to the platform Usage and Cost API / Claude Console usage page, not these SDK fields. Also documents subtle correctness traps: parallel-tool-call assistant messages share an `id`, must dedupe by ID to avoid double counting; per-step `output_tokens` is a "placeholder" — read the true output count from the final `result` message; subagent tokens are excluded from the top-level `usage` field but included in `total_cost_usd`/`modelUsage`.
   Source: https://code.claude.com/docs/en/agent-sdk/cost-tracking — PRIMARY — fetched 2026-09-04 — standard/documented, includes an explicit correctness warning worth flagging to any dev building their own tracker.

15. **DORA-in-AI-era commentary is broadly consistent across multiple 2026 sources found in search** (getdx.com, oobeya.io, exceeds.ai, tekninjas.com, byteiota.com all independently make the same claim: raw commit/PR/LOC volume metrics are unreliable in the AI era because AI inflates volume without proportional value) — this reads as genuine emerging consensus, not one outlier opinion, even though only getdx.com was independently fetched and verified.
   Source: search snippets across https://getdx.com/blog/dora-metrics-tools/ (fetched, PRIMARY-ish per above), others SECONDARY/unfetched — noted as convergent framing across many sources, September 2026.

## Concrete practices / configs (copy-pasteable)

**A. Minimal local cost tracking today (zero setup beyond npm/npx):**
```bash
npx ccusage@latest daily          # daily cost/token report from local JSONL
npx ccusage@latest claude blocks  # live 5-hour billing-window monitor
npx ccusage@latest statusline     # put running spend in your shell prompt (beta)
```
Source: https://github.com/ryoppippi/ccusage, https://ccusage.com/ — fetched 2026-09-04.

**B. Enable full OTel export to a local collector (for building your own dashboards/queries):**
```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
# lower the flush interval while testing (default metrics=60s, traces/logs=5s)
export OTEL_METRIC_EXPORT_INTERVAL=10000
```
Add `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` + `OTEL_TRACES_EXPORTER=otlp` for span-level traces (per-tool-call, per-LLM-request spans, nested subagent chains). Add `CLAUDE_CODE_OTEL_DIAG_STDERR=1` to surface exporter failures instead of silent drops (requires CLI v2.1.179+).
Source: https://code.claude.com/docs/en/agent-sdk/observability, https://code.claude.com/docs/en/monitoring-usage — fetched 2026-09-04.

**C. The single query worth running weekly as a "is my setup improving" proxy** (against whatever OTel backend you land the data in — SigNoz, CloudWatch, a local collector querying Parquet/etc.):
```sql
SELECT tool_name,
       COUNTIF(decision = 'accept') / COUNT(*) AS acceptance_rate,
       COUNT(*) AS n
FROM claude_code.tool_decision
WHERE source IN ('user_permanent','user_temporary','user_reject')  -- exclude auto/config accepts
GROUP BY tool_name
ORDER BY acceptance_rate ASC;
```
Rising acceptance rate + falling `user_abort`/`user_reject` counts over successive weeks, especially after a CLAUDE.md or skill change, is a direct before/after signal.
Source: https://code.claude.com/docs/en/monitoring-usage — fetched 2026-09-04.

**D. Auditing skills/CLAUDE.md with `skill-doctor` (community plugin):**
```bash
claude plugin marketplace add amaljithkuttamath/skill-doctor
claude plugin install skill-doctor@skill-doctor-marketplace
/skill-doctor            # diagnose — writes ~/.skill-doctor/diagnosis.json
/skill-doctor:treat      # stage fixes in a separate dir, doesn't touch originals
/skill-doctor:rollback   # restore from backup if the treatment made things worse
```
Source: https://github.com/amaljithkuttamath/skill-doctor — fetched 2026-09-04. Not an official Anthropic tool — vet it before trusting its scores as ground truth.

**E. Local JSONL hotspot analysis (waste-finding, no OTel needed):**
```bash
git clone https://github.com/nateherkai/token-dashboard && cd token-dashboard
python3 cli.py dashboard   # local server at 127.0.0.1:8080, auto-rescans every 30s
```
Surfaces per-prompt cost outliers (usually caused by oversized tool results), duplicate-read waste, and cache-hit rate — directly actionable for cutting cost per session.
Source: https://github.com/nateherkai/token-dashboard — fetched 2026-09-04.

**F. Reading cost programmatically from your own SDK-based tooling (not the CLI), for a lightweight "cost per task" ledger:**
```typescript
for await (const message of query({ prompt })) {
  if (message.type === "result") {
    // total_cost_usd is a CLIENT-SIDE ESTIMATE, not authoritative billing —
    // use platform Usage and Cost API for real numbers.
    totalSpend += message.total_cost_usd;
  }
}
```
Dedupe per-step token counts by assistant-message `id` (parallel tool calls share an id); read true output-token counts from the final `result` message, not per-step (`output_tokens` on intermediate assistant messages is a placeholder).
Source: https://code.claude.com/docs/en/agent-sdk/cost-tracking — fetched 2026-09-04.

**G. A pragmatic solo-dev "harness improvement" scorecard**, synthesizing the findings above into something a single developer could actually maintain weekly without an eval framework:
1. Cost/tokens per completed task (via ccusage `session` report or SDK `total_cost_usd`, divided by tasks/PRs shipped that week).
2. Tool-edit acceptance rate (via `claude_code.code_edit_tool.decision`, or a manual tally if not running OTel).
3. Rework/revert signal: `git log --since="30 days ago"` diffed against merge commits to spot-check how much AI-touched code got rewritten or reverted within 30 days (manual version of the exceeds.ai "rework rate," since no automated tool for this was found).
4. Session-log waste (via token-dashboard or ccusage `--breakdown`) to catch duplicate reads / oversized tool results driving cost without corresponding progress.
This is a synthesis, not a single source's recommendation — built by combining findings 4, 6, 7, 11, 14 above.

## Disagreements and open questions

- **No primary Anthropic source for a "claude plugin eval" command was found.** The research prompt named this as a thing to investigate; only third-party community plugins (`skill-doctor`, `claude-doctor`, `plugin-doctor`) were found doing anything resembling skill/plugin evaluation. This is a **gap**: it's unclear whether Anthropic has an internal/unreleased eval tool, or whether "claude plugin eval" refers to something not yet public as of Sept 2026.
- **Rework-rate and revert-rate thresholds (1.5x, 5-10%, 12%, 5%) all trace to one vendor blog (exceeds.ai)** and were not corroborated by a second independent source in this research pass — treat as one practitioner's proposed framework, not an industry-validated benchmark, until cross-checked elsewhere.
- **The "15% of AI commits introduce at least one issue" figure** is a secondary citation inside a secondary source (exceeds.ai citing unnamed "research") — the original study was not identified or independently fetched. Flag as unverified.
- **The AgentPex trajectory-vs-outcome example** (finding 10) was read only through confident-ai.com's summary, not the original AgentPex source — could not verify independently in this pass.
- **DX's DORA-is-insufficient argument and its own DX Core 4/AI Measurement Framework replacement come from the same commercial vendor (DX/getdx.com)** — the critique of DORA is echoed by multiple other sources (oobeya.io, tekninjas.com, byteiota.com), which increases confidence in the *critique*, but the *proposed replacement framework* is that one vendor's product and wasn't cross-validated against a neutral/academic source.
- **No independent, non-vendor academic study was found and fetched that specifically measures "agent harness" (as opposed to generic AI-coding-tool) improvement over time** for a solo developer context — everything found is either official Claude Code documentation (which is a measurement *substrate*, not a study of what "improving" looks like) or vendor/practitioner blogs. This is the main evidentiary gap in an otherwise well-documented area.
- **Trajectory-vs-outcome eval tooling recommendations** (e.g., specific frameworks like DeepEval/Confident AI, Galileo, LatentEval) were found via search but only confident-ai.com's page was fetched in full; the competitive landscape between these tools was not independently compared.

## Sources

1. https://code.claude.com/docs/en/agent-sdk/observability — Claude Code / Anthropic official docs — fetched 2026-09-04 — PRIMARY
2. https://code.claude.com/docs/en/monitoring-usage — Claude Code / Anthropic official docs — fetched 2026-09-04 — PRIMARY
3. https://code.claude.com/docs/en/agent-sdk/cost-tracking — Claude Code / Anthropic official docs — fetched 2026-09-04 — PRIMARY
4. https://ccusage.com/ — ccusage project site — fetched 2026-09-04 — PRIMARY
5. https://github.com/ryoppippi/ccusage — ccusage GitHub README — fetched 2026-09-04 — PRIMARY
6. https://github.com/amaljithkuttamath/skill-doctor — skill-doctor GitHub README — fetched 2026-09-04 — PRIMARY
7. https://signoz.io/docs/claude-code-monitoring/ — SigNoz official docs — fetched 2026-09-04 — PRIMARY
8. https://aws.amazon.com/blogs/mt/analyzing-claude-code-usage-with-cloudwatch-and-opentelemetry/ — AWS official blog — fetched 2026-09-04 — PRIMARY
9. https://blog.exceeds.ai/measuring-ai-impact-commits-prs/ — exceeds.ai blog — fetched 2026-09-04 — SECONDARY/opinion
10. https://www.confident-ai.com/blog/llm-agent-evaluation-complete-guide — Confident AI blog — fetched 2026-09-04 — SECONDARY
11. https://github.com/nateherkai/token-dashboard — token-dashboard GitHub README — fetched 2026-09-04 — PRIMARY (for the tool itself)
12. https://getdx.com/blog/dora-metrics-tools/ — DX (getdx.com) official blog — fetched 2026-09-04 — PRIMARY for DX's own framework / SECONDARY for the general DORA critique
13. https://www.dash0.com/guides/monitoring-claude-code-opentelemetry — Dash0 guide — found via search, not independently fetched — SECONDARY
14. https://signoz.io/blog/claude-code-monitoring-with-opentelemetry/ — SigNoz blog — found via search, not independently fetched — SECONDARY
15. https://www.elastic.co/security-labs/blog/claude-code-cowork-monitoring-otel-elastic — Elastic Security Labs — found via search, not independently fetched — SECONDARY
16. https://generalanalysis.com/guides/claude-code-control-observability-opentelemetry — General Analysis guide — found via search, not independently fetched — SECONDARY
17. https://github.com/aka-momo/claude-doctor — claude-doctor GitHub — found via search, not independently fetched — SECONDARY
18. https://mcpmarket.com/tools/skills/plugin-doctor-2 and /plugin-doctor-1 — Plugin Doctor listings — found via search, not independently fetched — SECONDARY
19. https://github.com/dlupiak/claude-session-dashboard — session dashboard GitHub — found via search, not independently fetched — SECONDARY
20. https://github.com/AeternaLabsHQ/claude-code-stats — claude-code-stats GitHub — found via search, not independently fetched — SECONDARY
21. https://github.com/szaher/claude-monitor — claude-monitor GitHub — found via search, not independently fetched — SECONDARY
22. https://github.com/phuryn/claude-usage — claude-usage GitHub — found via search, not independently fetched — SECONDARY
23. https://arxiv.org/html/2609.01481v1 (Harness-of-Harness) — found via search, not fetched — SECONDARY/unverified
24. https://arxiv.org/html/2604.25850v2 (Agentic Harness Engineering) — found via search, not fetched — SECONDARY/unverified
25. https://arxiv.org/pdf/2606.06324 (From Failed Trajectories to Reliable LLM Agents) — found via search, not fetched — SECONDARY/unverified
26. https://arxiv.org/pdf/2606.11543 (SkillJuror) — found via search, not fetched — SECONDARY/unverified
27. https://www.toriihq.com/articles/five-claude-code-usage-dashboards-and-monitoring-tools — Torii roundup — found via search, not fetched — SECONDARY
28. https://shipyard.build/blog/claude-code-track-usage/ — Shipyard blog — found via search, not fetched — SECONDARY
29. https://developer.harness.io/docs/software-engineering-insights/sei-administration/sei-calculations/scm/scm-metrics-calculation/scm-rework/ — Harness.io docs on SCM rework metric definition — found via search, not fetched — SECONDARY (but a vendor's own docs, so would be PRIMARY if fetched)
30. https://oobeya.io/blog/engineering-metrics-in-the-ai-era and https://www.oobeya.io/blog/dora-metrics-not-enough-2026 — found via search, not fetched — SECONDARY (corroborates DORA-insufficiency framing)

## Source check (independent)

Six of the report's most load-bearing claims were independently re-fetched from their cited sources and checked. Verdicts below.

### 1. `claude_code.code_edit_tool.decision` metric + full metric catalog (Findings 2, 4; TL;DR bullets 1–2)
**Verdict: CONFIRMED**

Source re-fetched: https://code.claude.com/docs/en/monitoring-usage

The docs table lists exactly this metric with the described attributes:
> `claude_code.code_edit_tool.decision` — "Count of code editing tool permission decisions"
> **Attributes**: `tool_name` (`"Edit"`, `"Write"`, `"NotebookEdit"`); `decision` (`"accept"`, `"reject"`); `source`: one of `"config"`, `"hook"`, `"user_permanent"`, `"user_temporary"`, `"user_abort"`, or `"user_reject"`.

The full metric catalog (session.count, lines_of_code.count, pull_request.count, commit.count, cost.usage, token.usage, code_edit_tool.decision, active_time.total) is confirmed present as described.

### 2. Three independent OTel signals, enable switches, default export intervals, `CLAUDE_CODE_OTEL_DIAG_STDERR` + v2.1.179+ (Finding 1)
**Verdict: CONFIRMED**

Source re-fetched: https://code.claude.com/docs/en/agent-sdk/observability

> "The CLI exports three independent OpenTelemetry signals. Each has its own enable switch and its own exporter... | Metrics | ... | `OTEL_METRICS_EXPORTER` | | Log events | ... | `OTEL_LOGS_EXPORTER` | | Traces | ... (beta) | `OTEL_TRACES_EXPORTER` plus `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` |"
> "By default, metrics export every 60 seconds and traces and logs export every 5 seconds."
> "To surface exporter errors, set `CLAUDE_CODE_OTEL_DIAG_STDERR=1`... Requires Claude Code v2.1.179 or later."

All details in the report's claim match the current doc verbatim.

### 3. `ccusage` — 18.4k stars, MIT, ryoppippi, subcommands, local/no-network parsing of `~/.claude/projects/*.jsonl` (Finding 6)
**Verdict: PARTIAL**

Source re-fetched: https://github.com/ryoppippi/ccusage

Confirmed exactly: "**Star Count:** 18.4k stars," "**License:** MIT," "**Author:** @ryoppippi," and subcommands `daily`/`weekly`/`monthly`/`session`/`blocks`/`statusline`. The "17 other agent CLIs" figure is roughly consistent (fetch surfaced 16 other named sources in a support table, i.e. 17 total non-Claude-Code sources once combined listings are counted, though this wasn't cleanly a single "17").

What did NOT come back confirmed in this pass: the specific claim that it "parses `~/.claude/projects/*.jsonl`... entirely locally, no API key, no network call." The re-fetch explicitly reported: "The documentation does **not** explicitly mention parsing `~/.claude/projects/*.jsonl` with no network calls," though it did surface an adjacent `--offline` mode flag, which is consistent with (but doesn't itself prove) the zero-network-call claim. This is very likely true given the tool's known design, but it wasn't directly quotable from what was fetched — flagged inline in the report as unverified rather than confirmed.

### 4. AWS CloudWatch export via bearer-token auth, no IAM SDK needed, `https://monitoring.<region>.amazonaws.com` (Finding 5)
**Verdict: CONFIRMED**

Source re-fetched: https://aws.amazon.com/blogs/mt/analyzing-claude-code-usage-with-cloudwatch-and-opentelemetry/

> "Bearer tokens (or CloudWatch metrics API key) allow tools running outside AWS (like Claude Code on developer laptops) to send metrics to CloudWatch without requiring the AWS SDK or IAM credential chains."
> `export OTEL_EXPORTER_OTLP_ENDPOINT="https://monitoring.<AWS_REGION>.amazonaws.com"` paired with `export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer ${BEARER_TOKEN}"`
> Console path: "In the CloudWatch console, navigate to **Settings**... Choose **Create**." CLI/IAM path: "Attach the CloudWatchAPIKeyAccess managed policy" to an IAM user.

Matches the report's claim exactly.

### 5. Agent SDK `total_cost_usd`/`modelUsage` as client-side estimates; dedupe-by-id; placeholder `output_tokens`; subagent tokens excluded from `usage` but included in `total_cost_usd`/`modelUsage` (Finding 14)
**Verdict: CONFIRMED**

Source re-fetched: https://code.claude.com/docs/en/agent-sdk/cost-tracking

> "The `total_cost_usd` and `costUSD` fields are client-side estimates, not authoritative billing data. The SDK computes them locally from a price table bundled at build time... Use these fields for development insight and approximate budgeting. For authoritative billing, use the Usage and Cost API..."
> "When Claude uses multiple tools in one turn, all messages in that turn share the same ID, so deduplicate by ID to avoid double-counting."
> "The deduplicated per-step values are accurate for input and cache tokens. Per-step `output_tokens` is a placeholder, so read output tokens from the result message."
> Table confirms: `usage` = subagent activity "Excluded"; `total_cost_usd` = "Included"; `modelUsage`/`model_usage` = "Included."

All sub-claims confirmed verbatim, including the correctness-trap details.

### 6. exceeds.ai "rework rate" and "AI revert percentage" definitions/thresholds (Findings 11–12)
**Verdict: MISATTRIBUTED / PARTIAL** (mixed — see breakdown)

Source re-fetched: https://blog.exceeds.ai/measuring-ai-impact-commits-prs/ (the cited URL), plus one follow-up search and fetch of a second exceeds.ai article the search surfaced: https://blog.exceeds.ai/code-quality-metrics-ai-roi/

- Code Rework Rate definition ("lines deleted or substantially revised within 30 days of merge ÷ lines added") and the >1.5x "AI bloat" flag: **CONFIRMED** present in the cited URL verbatim: "Calculate lines deleted or substantially revised within 30 days of merge, divided by lines added, separately for AI-attributed and human-authored code," with >1.5x flagged as "AI bloat."
- The "healthy target 5–10%, >12% hidden cost" thresholds: **UNSUPPORTED** in the cited URL — re-fetch found these numbers absent. A second exceeds.ai article on the same general topic (code-quality-metrics-ai-roi) gives a *different* rework-rate formulation instead: "Rework Rate = Reworked AI lines / total AI lines, with a baseline under 15%, and AI typically running at roughly 2x human rework" — neither article contains "5–10%" or ">12%."
- "AI Revert Percentage" (AI-generated lines reverted ÷ AI-generated lines merged, informal 5% threshold): **MISATTRIBUTED**. This exact concept is absent from the cited URL (confirmed absent on re-fetch: "The concept of 'AI Revert Percentage' and any 5% threshold are not mentioned in this content"). A closely related metric does exist on exceeds.ai, but in the *other* article and defined differently — per-PR, not per-line: "PR Revert Rate = Reverted AI-touched PRs / total AI PRs, with a healthy baseline under 5% and observed rates of 8% for AI versus 3% for human PRs." The underlying idea and the 5% figure are real and traceable to exceeds.ai, but the report cites the wrong URL/article and slightly wrong unit (lines vs. PRs) for it.
- The ">15% of AI commits introduce at least one issue" figure (Finding 12): **CONFIRMED** present in the cited URL: "A 2026 empirical study of 302.6K verified AI-authored commits found that more than 15% of AI commits introduce at least one issue, with 22.7% of those issues persisting in the latest repository version." (The report correctly flagged this as an unverified secondary citation within the blog — that caveat still stands; only the presence of the claim in the blog was being checked here.)

**Net effect**: the report's Findings 11–12 blend two different exceeds.ai articles' numbers into one citation, and invent two thresholds (5–10%, >12%) that don't appear in either article found. The report's own "Disagreements and open questions" section already flagged these thresholds as unvalidated, which was directionally correct, but the section undersold the problem — it's not just "unvalidated," part of it is attributed to a source that doesn't contain it. Corrected inline in the Findings section above.

### Overall reliability assessment

Of the six claims checked, four were fully CONFIRMED verbatim against their cited primary sources (all three code.claude.com pages and the AWS blog), one was PARTIAL (ccusage — core facts confirmed, one implementation detail not directly quotable from the re-fetch though plausible), and one was MISATTRIBUTED/PARTIAL (the exceeds.ai rework/revert metrics, which conflate two different blog posts and include two numeric thresholds not found in either).

The report is well-sourced and unusually careful where it draws on Anthropic's own documentation — every official Claude Code/Agent SDK doc claim checked here reproduced verbatim. Its self-flagging discipline (the "Disagreements and open questions" section, PRIMARY/SECONDARY tagging, explicit "not independently fetched" labels on ~14 of its 30 sources) is a real strength and correctly predicted that the exceeds.ai material was the weakest link — it just didn't catch that the weakness included a wrong-URL misattribution, not only "unvalidated numbers from one vendor." Readers should treat every number in Findings 11–12 as needing a fresh check against the actual exceeds.ai article before using it in a recommendation, and should not assume claims found only "via search snippets, not independently fetched" (roughly 14 of 30 sources) hold up under the same scrutiny as the six checked here — this pass is not exhaustive coverage of the whole report, only its highest-stakes claims.
