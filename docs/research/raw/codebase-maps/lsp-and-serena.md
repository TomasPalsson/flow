# LSP-Style Code Navigation for Claude Code Agents (Sept 2026)

## TL;DR

Claude Code now ships two competing paths to semantic code navigation: (1) **native `.lsp.json` LSP plugins** (official marketplace covers 13 languages: TS/JS, Python, Rust, Go, Java, C#, C/C++, Kotlin, Swift, Ruby, PHP, Lua, Shopify Liquid) that inject go-to-definition, find-references, hover, rename, and diagnostics directly as first-class tools with no separate server process to manage; and (2) **Serena**, a third-party (Oraios) MCP server built on the same LSP backends but adding symbol-level *editing*/refactoring, cross-session memories, and 40+ language coverage via generic LSP wrapping — and which Anthropic itself now lists (as "community-managed") in the official plugin marketplace, even though Serena's own README tells users **not** to install it that way. Anthropic's own guidance (context-engineering blog, sub-agents docs) doesn't push semantic tools at all — it recommends Grep/Glob/Read plus the built-in **Explore** subagent as the default, isolating verbose search from the main context. A dated practitioner benchmark (Aug 2026) found agents themselves mostly *don't* choose LSP-style tools when given the choice (0–6% adoption for rename/localization tasks) and that forcing semantic-first tool use can *reduce* success rate — semantic tools help most on noisy/dynamic codebases and reference-completeness tasks, and can add tokens with zero accuracy gain on clean, well-typed code. For a solo dev with Serena already configured and working: **keep Serena, and layer the free official LSP plugins for languages you touch — don't rip Serena out, but don't treat either as a default-on replacement for grep.**

## Findings

1. **Serena's tool surface**: symbol find/overview, find-referencing-symbols, type hierarchy (JetBrains backend only), find-declaration, find-implementations, diagnostics, rename (symbols only via LSP backend; symbols/files/dirs via paid JetBrains backend), move/inline/safe-delete (JetBrains only), replace-symbol-body, insert-before/after-symbol, plus basic `search_for_pattern`/`read_file`/`execute_shell_command` utilities that Serena disables by default inside harnesses like Claude Code because the harness already provides overlapping tools. Serena also ships a persistent **memory system** (files an agent writes/reads across sessions, e.g. seeded `memory_maintenance` conventions doc) and **project activation** (`activate_project` tool, or `--project <path>` at MCP-server startup; disabled in single-project contexts like Claude Code where a project is pre-supplied). — PRIMARY, github.com/oraios/serena README, fetched 2026-09-04 (undated content, repo active as of Sept 2026).

2. **Serena language coverage**: "support for over 40 programming languages" via the free/default LSP backend (Python, TS/JS, Go, Rust, Java, C#, Ruby, PHP, Kotlin, Swift, Bash, Elixir, Haskell, Terraform, and many more listed by name), or via a **paid** JetBrains-plugin backend that adds type hierarchy, dependency search, move/inline refactors, and an interactive debugger (breakpoints/REPL) — capabilities the free LSP backend does not have. — PRIMARY, oraios/serena README §"Programming Language Support," fetched 2026-09-04.

3. **Serena indexing/staleness**: `serena project index` pre-caches symbol info "especially for larger projects" to avoid first-call latency; the docs state indexing "has to be called only once" because the index updates automatically as files change during regular usage, and provide no documented staleness threshold or manual re-index trigger beyond that. `serena memories check` exists to report *stale memory references* (a different staleness concern — memory text pointing at renamed/deleted code, not the symbol index). — PRIMARY, oraios.github.io/serena/02-usage/040_workflow.html, fetched 2026-09-04.

4. **Serena's own vendor evaluation has no hard numbers**: Serena's published "evaluation" (oraios.github.io/serena/04-evaluation) is a qualitative, agent-self-report exercise (~20 routine tasks across navigation/small-edits/large-edits/cross-file-refactor/workflow categories, agents include Claude Code, Codex, Copilot CLI, Junie) with **no token-savings %, time-savings %, or success-rate numbers published** — findings are quotes like Opus-in-Claude-Code calling cross-file renames/reference lookups "the single most impactful addition to my toolkit," collapsing "8–12 careful, error-prone steps" into one call. Treat as VENDOR CLAIM / marketing quote, not a measured benchmark. — PRIMARY (vendor doc), fetched 2026-09-04.

5. **Real-world failure modes are actively being filed against Serena** (oraios/serena GitHub issues, all Aug 27–Sept 2 2026, i.e. very recent/open): stale/partial results while the project graph is still loading (#1937, TypeScript find_referencing_symbols "returns silently partial results"); symbol-body-replace corrupting code (#1956, duplicated `export const` on TS; #1952, GDScript loses separator whitespace); LSP getting stuck after a timeout on large projects (#1951, Godot/GDScript); resource blowup from concurrent sessions each spawning their own language-server instance against the same workspace (#1944, Eclipse JDTLS "unbounded CPU/RAM"; #1966, Kotlin LSP fails outright with multiple instances); and a streamable-HTTP mode where cold symbol calls make new-session handshakes ~30x slower (#1890). These are open issues, not resolved-and-documented limitations — read as evidence of active rough edges rather than settled consensus on severity. — PRIMARY, github.com/oraios/serena/issues, fetched 2026-09-04.

6. **Claude Code's native LSP plugins**: a plugin can ship an `.lsp.json` (or inline `lspServers` in `plugin.json`) declaring `command`/`args`/`extensionToLanguage` for a language-server binary; Claude Code manages the process (stdio transport enforced even when `socket` is requested), exposes **go-to-definition, find-references, hover, rename, diagnostics, and cross-file code navigation** as tools, and can auto-inject diagnostics into context after edits (toggle via the `diagnostics` field, default on — settable to `false` to keep navigation but cut the token overhead of auto-injected diagnostics). Reliability knobs exist: `startupTimeout`, `shutdownTimeout`, `restartOnCrash` (default true), `maxRestarts` — the latter two require Claude Code ≥2.1.205, and setting either on an older build causes Claude Code to skip that LSP server entirely at startup. When two enabled servers claim the same file extension, only the first-registered one runs; `claude --debug` and the `/plugin` Errors tab surface startup failures (e.g., `Executable not found in $PATH` if you forgot to install the language-server binary separately — plugins configure the connection, they don't bundle the server). — PRIMARY, code.claude.com/docs/en/plugins-reference, fetched 2026-09-04.

7. **Official LSP plugin catalog** (`claude-plugins-official` marketplace, fetched via GitHub API 2026-09-04): `clangd-lsp` (C/C++), `csharp-lsp`, `gopls-lsp` (Go), `jdtls-lsp` (Java/Eclipse JDT.LS), `kotlin-lsp`, `liquid-lsp` (Shopify Liquid), `lua-lsp`, `php-lsp` (Intelephense), `pyright-lsp` (Python), `ruby-lsp`, `rust-analyzer-lsp`, `swift-lsp` (SourceKit-LSP), `typescript-lsp` — 13 languages, each a thin wrapper Anthropic maintains that expects you to install the underlying language-server binary yourself (e.g. `npm install -g typescript-language-server typescript`, `pip install pyright`). Notably, **`serena` is also listed in this same official marketplace** (category "development", tag "community-managed", pointing at `anthropics/claude-plugins-public/external_plugins/serena`) — yet Serena's own README explicitly warns: *"Do not install Serena via an MCP or plugin marketplace! They contain outdated and suboptimal installation commands. Instead, follow our Quick Start instructions."* This is a direct, dated (both current as of 2026-09-04) contradiction between Anthropic's marketplace listing and the upstream vendor's install guidance. — PRIMARY (marketplace.json) + PRIMARY (Serena README), both fetched 2026-09-04.

8. **Anthropic's own guidance does not recommend semantic-navigation tools by default.** The "Effective context engineering for AI agents" post and the sub-agents doc both describe the *baseline* Claude Code philosophy as: prefer lightweight primitives (Bash `head`/`tail`, file paths, Grep/Glob/Read) over pre-built semantic indexes, use the built-in **Explore** subagent (read-only: Read/Grep/Glob/Bash, tools like Write/Edit denied) to isolate verbose search from the main thread and return only a condensed summary (subagent may burn "tens of thousands of tokens" internally but returns "often 1,000–2,000 tokens" to the parent), and use tool-result clearing to drop stale search output from history. Neither doc mentions LSP, Serena, or MCP-based semantic navigation as a recommended default — LSP plugins are documented separately as an opt-in extension mechanism, not folded into the default agent-context guidance. — PRIMARY, anthropic.com/engineering/effective-context-engineering-for-ai-agents + code.claude.com/docs/en/sub-agents, fetched 2026-09-04.

9. **The clearest practitioner-measured comparison found is "Grep beats LSP? Why coding agents ignore your fancier tools"** (agentconnect.md, published 2026-08-12, discussed on Hacker News 2026-09-04). Core measured claims: agents given a choice of tools picked LSP-style semantic lookup only **0–6% of the time** for localization/rename tasks vs **45–57%** for reference-completeness tasks; forcing a semantic-first tool path dropped task success from 100% to 89% (semantic references are a *subset* of textual occurrences — renames also need to touch comments/strings/config that only grep sees); results were codebase-dependent — on a "clean" typed TypeScript repo (remeda) LSP added **zero F1 improvement at +16% token cost**, on a "noisy" TypeScript repo (hono) LSP added **+0.246 F1 at −12% token cost**, and on a Python repo (requests) LSP added **+0.072 F1 at +19% token cost**; and returning surrounding source context alongside semantic-search hits (rather than bare symbol locations) raised pass@1 from 0.67 to 0.83 and cut follow-up file-read calls from 15.2 to 3.2 per task. — SECONDARY (independent blog, methodology not independently audited by this research), dated 2026-08-12, fetched 2026-09-04. Treat the specific numbers as one team's benchmark, not an industry consensus — but the qualitative shape (semantic tools help more on messy/dynamic code and reference-completeness, hurt on clean typed code and renames) is consistent with Serena's own capability table (declaration/implementation lookup explicitly caveated as incomplete) and with Anthropic's default-to-grep posture.

10. **ast-grep / tree-sitter is a third, distinct lane** — structural pattern search/lint/rewrite over an AST (Rust, tree-sitter-based, multi-core) rather than a running language server: patterns are written "as if you are writing ordinary code" with `$METAVAR` wildcards matching syntax, not live symbol resolution, so it has no notion of type info, cross-file reference resolution, or diagnostics from a compiler — it is grep-plus-structure, not LSP. No official Anthropic integration or MCP wrapper was found in the Claude Code docs; independent projects exist (e.g. a Rust TUI agent "VT Code" combining tree-sitter + ast-grep, several small Show-HN MCP wrappers) but adoption looks thin — one practitioner (HN comment, solmaz.io blog "Typed languages are better suited for vibecoding," Aug 2025) reported building "a custom MCP server that attempts to teach the LLM how to use ast-grep, but that didn't really work as hoped," citing smaller-model difficulty with the pattern-YAML format, and said they'd look at GritQL next instead. — SECONDARY (github.com/ast-grep/ast-grep README + HN/blog anecdote), fetched 2026-09-04.

## Downsides and Failure Modes

- **Stale/partial results mid-load**: Serena's TypeScript backend can return "silently partial results" from `find_referencing_symbols` while the project's dependency graph is still building (oraios/serena #1937, open, Aug 2026) — a wrong-answer-without-warning failure mode, not just slowness.
- **Symbolic edits corrupting code**: Serena's `replace_symbol_body` has open bugs duplicating `export const` declarations in TypeScript (#1956) and eating separator whitespace in GDScript (#1952) — both filed Aug 30–31, 2026, i.e. current/unresolved as of this research.
- **Resource blowup with concurrency**: multiple Claude Code sessions (or session + IDE) opening the same project each spawn their own language-server process against the same workspace, causing unbounded CPU/RAM (Eclipse JDTLS, #1944) or outright failure (Kotlin LSP, #1966) — a real cost for anyone running parallel agent sessions/worktrees on one repo, which is common in this dotfiles user's own workflow (feature/flow skills spin up worktrees).
- **Latency cliffs**: Serena's streamable-HTTP mode reportedly gets ~30x slower on new-session handshakes when a heavy/cold symbol call is in flight (#1890, open).
- **Timeout hangs**: on large GDScript/Godot projects, a reference-lookup timeout can leave the whole LSP connection blocked (#1951).
- **Token cost is workload-dependent, not uniformly positive**: the agentconnect.md benchmark found LSP-assisted lookup *cost more tokens for the same or worse accuracy* on a clean, well-typed TypeScript codebase (+16% tokens, 0 F1 gain) and on a Python codebase (+19% tokens for a small F1 gain); it only clearly paid off on a "noisy" codebase. Blanket "semantic tools save tokens" claims should be treated as workload-dependent, not universal.
- **Structural incompleteness for rename-class tasks**: since semantic references are a strict subset of all textual occurrences of a name (comments, strings, config files, docs), semantic-only rename/localization is unsafe without a grep-based completeness pass — this is both a documented Serena capability caveat (find-declaration "will generally not work for declarations in external dependencies"; find-implementations "only available for some languages") and the agentconnect.md finding that forcing a semantic-first path dropped success 100%→89%.
- **Install-channel confusion**: Anthropic's own official plugin marketplace lists Serena as installable, directly contradicting Serena's README instruction not to install it that way because marketplace/MCP-registry install commands are "outdated and suboptimal." A solo dev following the marketplace UI could end up on a stale config.
- **JetBrains-only features**: type hierarchy, dependency search, move/inline refactors, propagate-deletion, and interactive debugging are gated behind Serena's *paid* JetBrains plugin — the free/default LSP backend does not have them, a real capability gap versus what an IDE user might expect from "IDE for your coding agent" marketing.

## Concrete Setup

**Serena (already configured, per user's situation) — exact commands from the vendor Quick Start:**
```bash
# one-time: install uv, then install serena via uv
uv tool install -p 3.13 serena-agent

# verify + write default config
serena init
# add -b JetBrains to use the paid JetBrains backend instead of the free LSP backend

# optional: pre-build the symbol index for a large project (avoids first-call latency)
serena project index

# check for memory files whose referenced code has moved/renamed
serena memories check
```
Do **not** install Serena from a Claude Code / MCP marketplace per the vendor's own README — configure the MCP launch command directly per their client docs (oraios.github.io/serena/02-usage/030_clients.html) even though Anthropic's official marketplace does list a `serena` entry.

**Claude Code native LSP plugins (official marketplace, per-language, free):**
```bash
# 1. install the language-server binary yourself, e.g.:
npm install -g typescript-language-server typescript   # for typescript-lsp
pip install pyright                                     # for pyright-lsp   (or: npm install -g pyright)
# rust-analyzer: see https://rust-analyzer.github.io/manual.html#installation

# 2. install the plugin from Anthropic's official marketplace
/plugin install typescript-lsp@claude-plugins-official
/plugin install pyright-lsp@claude-plugins-official
/plugin install rust-analyzer-lsp@claude-plugins-official
# ...also available: clangd-lsp, csharp-lsp, gopls-lsp, jdtls-lsp, kotlin-lsp,
#    liquid-lsp, lua-lsp, php-lsp, ruby-lsp, swift-lsp

# 3. verify a server actually started
/plugin        # check the Errors tab for "Executable not found in $PATH" etc.
claude --debug # see why a server was skipped, if the Errors tab isn't enough
```
To write a custom LSP plugin for a language without an official one, drop an `.lsp.json` at the plugin root:
```json
{
  "go": {
    "command": "gopls",
    "args": ["serve"],
    "extensionToLanguage": { ".go": "go" }
  }
}
```
Tune reliability/cost knobs as needed (requires Claude Code ≥2.1.205 for `restartOnCrash`/`shutdownTimeout`):
```json
{
  "go": {
    "command": "gopls",
    "args": ["serve"],
    "extensionToLanguage": { ".go": "go" },
    "startupTimeout": 15000,
    "shutdownTimeout": 5000,
    "restartOnCrash": true,
    "maxRestarts": 3,
    "diagnostics": false
  }
}
```
Setting `"diagnostics": false` keeps navigation (go-to-def/find-refs/hover/rename) while suppressing automatic diagnostic injection into context after every edit — a direct token-cost lever if diagnostics noise gets expensive on a large/noisy codebase.

## Recommendation: Keep, Switch, or Both?

**Use both — but scope Serena down, don't hand it more surface area than it earns.** For a solo developer who already has Serena working:

- **Keep Serena** for what it uniquely gives you beyond native LSP plugins: cross-session **memories** (project conventions surviving across sessions, distinct from CLAUDE.md), atomic multi-file **refactoring/editing** primitives (rename, replace-symbol-body, insert-before/after-symbol, safe-delete) that Claude Code's native LSP plugins do not expose (native plugins give navigation + diagnostics, not symbol-level *editing* operations), and its 40+-language reach if you work across languages the official marketplace doesn't yet cover (13 languages as of this research).
- **Add the free official LSP plugin(s) for your primary language(s)** (e.g. `typescript-lsp`, `pyright-lsp`, `rust-analyzer-lsp`) — they're zero-cost, Anthropic-maintained, and give live diagnostics injected into context (a thing Serena's LSP backend does but arguably less tightly integrated with the harness), and they don't carry Serena's per-session server-spawn / memory-system overhead. Running both is not wasteful: Claude Code de-duplicates by only starting the first-registered server per file extension, and skills/prompting can nudge which tool the agent reaches for per task type.
- **Do not treat either as "index once, trust forever."** The agentconnect.md benchmark and Serena's own open-issue list both point the same direction: semantic tools win on reference-completeness and noisy/dynamic codebases, and lose (extra tokens, sometimes lower accuracy, occasional wrong/partial results) on clean typed code and on rename/localization tasks where grep's textual completeness matters more than symbol precision. Keep grep as the fallback/cross-check for renames and after large edits, and re-run `serena project index` after big structural changes even though the docs claim auto-update, given the open partial-result issue on TypeScript.
- **Skip the marketplace install path for Serena** specifically — follow the vendor's Quick Start (`uv tool install`, `serena init`) instead of `/plugin install serena@claude-plugins-official`, since the vendor explicitly says the marketplace command is outdated.
- If your solo workflow involves **parallel worktrees/sessions on the same repo** (this user's dotfiles setup uses `feature`/`flow` skills that spin up worktrees), watch for the concurrent-language-server resource issues filed against Serena (#1944, #1966) — that's the sharpest concrete risk for exactly this kind of usage pattern.

## Sources

1. [oraios/serena — GitHub README](https://github.com/oraios/serena) — PRIMARY, vendor, fetched 2026-09-04 (undated content)
2. [oraios/serena — GitHub Issues](https://github.com/oraios/serena/issues) — PRIMARY, fetched 2026-09-04 (issues dated Aug 18 – Sept 2, 2026)
3. [Serena workflow docs — project activation, indexing, onboarding](https://oraios.github.io/serena/02-usage/040_workflow.html) — PRIMARY, vendor, fetched 2026-09-04
4. [Serena evaluation methodology/results](https://oraios.github.io/serena/04-evaluation/000_evaluation-intro.html) — PRIMARY, vendor (qualitative, no hard numbers), fetched 2026-09-04
5. [Claude Code docs — Create plugins (LSP servers section)](https://code.claude.com/docs/en/plugins) — PRIMARY, Anthropic, fetched 2026-09-04
6. [Claude Code docs — Plugins reference (full `.lsp.json` schema, official LSP plugin table)](https://code.claude.com/docs/en/plugins-reference) — PRIMARY, Anthropic, fetched 2026-09-04
7. [anthropics/claude-plugins-official — marketplace.json](https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json) — PRIMARY, Anthropic, fetched via `gh api` 2026-09-04 (13 LSP plugins + `serena` entry confirmed by direct JSON parse)
8. [Anthropic Engineering — Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — PRIMARY, Anthropic, fetched 2026-09-04
9. [Claude Code docs — Subagents](https://code.claude.com/docs/en/sub-agents) — PRIMARY, Anthropic, fetched 2026-09-04
10. ["Grep beats LSP? Why coding agents ignore your fancier tools"](https://www.agentconnect.md/blog/grep-beat-lsp-harness/) — SECONDARY, independent blog, published 2026-08-12, fetched 2026-09-04; discussed on [Hacker News](https://hn.algolia.com/) 2026-09-04 (comment by user poytr1)
11. [ast-grep — GitHub README](https://github.com/ast-grep/ast-grep) — PRIMARY (project's own description), fetched 2026-09-04
12. [Hacker News Algolia search — "claude code lsp plugin"](https://hn.algolia.com/api/v1/search?query=claude%20code%20lsp%20plugin&tags=story) — SECONDARY, aggregator of Show-HN posts (ts7-lsp-plugin, typemux-cc, svelte-lsp), low engagement (0–9 points), fetched 2026-09-04
13. [Hacker News Algolia search — Serena MCP comments](https://hn.algolia.com/api/v1/search) — SECONDARY, scattered practitioner comments, e.g. zachwills (Aug 2025, "~$6k" token spend using Serena among other MCPs in a 20-agent swarm experiment), sixothree (Aug 2025, "Serena MCP to keep my context smaller... claude uses it pretty much exclusively"), marwamc/Launch HN Nia (Dec 2025, built a competing BM25-based tool used "alongside serena-mcp"), fetched 2026-09-04
14. [solmaz.io — "Typed languages are better suited for vibecoding"](https://solmaz.io/typed-languages-are-better-suited-for-vibecoding) — SECONDARY, independent blog, Aug 2025, via HN comment thread, fetched 2026-09-04
15. [lsp-client.github.io — "LSP Skill" project](https://lsp-client.github.io/) — PRIMARY (project's own site), v0.1.0, 2026, fetched 2026-09-04 — example of a third-party effort to make LSP more agent-friendly (Python/TS/Go/Rust/Deno), no comparative benchmarks published

## Gaps

- No independently-audited, large-sample benchmark comparing Serena specifically (as opposed to generic "LSP tools") against native Claude Code LSP plugins or against grep-only baselines was found — the one quantitative practitioner source (#10) benchmarks "LSP-style" navigation broadly, not Serena by name, and is a single team's methodology, not a peer-reviewed or widely-replicated study.
- Could not confirm exact rollout date of Claude Code's `.lsp.json` plugin feature (changelog fetch was unreliable/possibly noisy); only confirmed that `restartOnCrash`/`shutdownTimeout` require Claude Code ≥2.1.205, which anchors it as a 2026-era (v2.1.x) feature.
- Reddit (r/ClaudeAI, r/ClaudeCode) was inaccessible to this research (fetch blocked), so a likely-rich vein of practitioner day-to-day complaints/praise was not directly sampled — HN and GitHub issues were used as substitutes.
- Session's WebSearch budget was exhausted before this task began (shared session-wide quota, 200/200 used by prior activity), so this research relied entirely on WebFetch against GitHub, Anthropic docs, HN's Algolia API, and direct URL guesses rather than iterative web search — coverage of practitioner blogs/comparisons outside what HN indexed may be incomplete.
- No data found on Serena's actual MCP-server cold-start latency in seconds, nor a direct head-to-head token-count measurement of "Serena find-references" vs "native LSP plugin find-references" vs "grep -r" for the same query on the same repo.

## Source check (independent)

Method: picked the 6 most load-bearing claims (the ones the recommendation actually rests on) and independently re-fetched each cited primary source via WebFetch / `gh api` on 2026-09-04. All 6 verified CONFIRMED — no unsupported or misattributed claims found among this set.

**1. Claim #6 — Native LSP plugin config fields, stdio enforcement, version gate, first-registered-wins.**
Verdict: **CONFIRMED**. Re-fetched code.claude.com/docs/en/plugins-reference directly.
- Version gate, exact match: *"restartOnCrash and shutdownTimeout require Claude Code v2.1.205 or later. Before v2.1.205, setting either option caused Claude Code to skip that LSP server entirely at startup."*
- stdio-enforcement, exact match: *"Claude Code accepts both stdio (default) and socket as transport values, but runs every server over stdio. The stdout protocol rules apply to all servers regardless of the declared transport."*
- First-extension-wins, exact match: *"The first server registered handles files with that extension — Other servers with the same extension never start."*
- Diagnostics toggle, exact match: *"false: Keeps code navigation features (go-to-definition, find-references, hover, rename) but suppresses automatic diagnostic injection."*
- Also confirmed: *"You must install the language server binary separately. LSP plugins configure how Claude Code connects to a language server but don't include the server itself."*

**2. Claim #7 — Official marketplace lists 13 LSP plugins + a `serena` entry tagged "community-managed," contradicting Serena's own README.**
Verdict: **CONFIRMED**. Re-fetched `anthropics/claude-plugins-official` marketplace.json via `gh api` and `oraios/serena` README via `gh api`.
- Marketplace JSON confirms the exact serena entry: `"name": "serena", "description": "Semantic code analysis MCP server providing intelligent code understanding, refactoring suggestions, and codebase navigation through language server protocol integration.", "category": "development", ... "tags": ["community-managed"]`.
- Counted all 13 named LSP plugins present in the same marketplace.json: clangd-lsp, csharp-lsp, gopls-lsp, jdtls-lsp, kotlin-lsp, liquid-lsp, lua-lsp, php-lsp, pyright-lsp, ruby-lsp, rust-analyzer-lsp, swift-lsp, typescript-lsp.
- Serena README, near-verbatim match to the claim's quote: *"> [!IMPORTANT] > Do not install Serena via an MCP or plugin marketplace! They contain outdated and suboptimal installation commands. > Instead, follow our Quick Start instructions."* — direct contradiction of the marketplace listing, confirmed on both sides.

**3. Claim #8 — Anthropic's own context-engineering post and sub-agents doc don't recommend LSP/Serena; describe Explore subagent and token-savings pattern.**
Verdict: **CONFIRMED**. Re-fetched anthropic.com/engineering/effective-context-engineering-for-ai-agents and code.claude.com/docs/en/sub-agents.
- Context-engineering post: LSP/Serena/MCP-based semantic navigation "not mentioned" as a recommendation; preference for lightweight primitives confirmed via direct quote: Claude Code *"use[s] targeted queries, store results, and leverage Bash commands like head and tail to analyze large volumes of data without ever loading the full data objects into context."*
- Token-savings pattern, near-exact match: *"Each subagent might explore extensively, using tens of thousands of tokens or more, but returns only a condensed, distilled summary of its work (often 1,000-2,000 tokens)."*
- Sub-agents doc confirms Explore subagent is read-only, exact match: *"Tools: read-only tools; Write and Edit are denied"* (Read, Grep, Glob, Bash), and confirms the context-preservation framing: *"This keeps exploration results out of your main conversation context."*

**4. Claim #9 — agentconnect.md benchmark: adoption rates, success-rate drop, per-repo F1/token numbers.**
Verdict: **CONFIRMED**. Re-fetched agentconnect.md/blog/grep-beat-lsp-harness/ directly; all cited figures reproduced verbatim in the source.
- Localization/rename adoption by model: Opus 4.8 0%, Sonnet 4.6 4%, Haiku 4.5 6% — matches the doc's "0–6%" range.
- Reference-completeness adoption: Opus 45%, Sonnet 50%, Haiku 57% — matches the doc's "45–57%" range.
- Success-rate drop: forcing semantic-first on localization tasks "reduced success from 100% to 89%" — exact match.
- Per-repo table confirmed exactly: remeda (TS) ΔF1 +0.000 / +16% tokens; hono (TS) ΔF1 +0.246 / −12% tokens; requests (Python) ΔF1 +0.072 / +19% tokens — all three figures match the doc precisely.

**5. Claim #5 — Seven specific Serena GitHub issues (#1937, #1956, #1952, #1951, #1944, #1966, #1890), all open, filed Aug 18–Sept 2 2026, matching the described failure modes.**
Verdict: **CONFIRMED**. Re-fetched all 7 issues via `gh api repos/oraios/serena/issues/<n>`; every one exists, is `state: open`, and its title matches the failure mode attributed to it in the doc:
- #1937 (2026-08-26, open): "TypeScript: find_referencing_symbols returns silently partial results while the project graph is still loading — Serena waits only before the FIRST cross-file query"
- #1956 (2026-08-31, open): "[LS][TypeScript] replace_symbol_body still corrupts top-level exported const declarations by duplicating export const"
- #1952 (2026-08-30, open): "replace_symbol_body removes separator whitespace before the following GDScript function"
- #1951 (2026-08-30, open): "find_referencing_symbols can leave Godot LSP blocked after a reference timeout on large GDScript projects"
- #1944 (2026-08-27, open): "Concurrent stdio instances on one project hand the same Eclipse JDTLS -data workspace to N language servers, causing unbounded CPU/RAM and silent index corruption"
- #1966 (2026-09-02, open): "Kotlin LSP fails when multiple Serena instances open the same workspace"
- #1890 (2026-08-18, open): "Streamable-HTTP listener stalls during heavy/cold symbol calls: health probes time out, new-session handshakes slow ~30x"

**6. Claim #2 — Serena's free backend covers "over 40 programming languages"; the JetBrains backend is paid.**
Verdict: **CONFIRMED**. Re-fetched oraios/serena README directly.
- Exact match: *"When using Serena's language server backend, we provide **support for over 40 programming languages**, including Ada / SPARK, AL, Angular, Ansible, Bash, ... Zig."* (67 languages/frameworks actually named in the list — comfortably "over 40").
- Paid-tier confirmed, exact match: *"The paid Serena JetBrains Plugin (free trial available) leverages the powerful code analysis capabilities of your JetBrains IDE."*

### Summary
6/6 confirmed, 0 unsupported, 0 partial, 0 misattributed. No inline `[UNVERIFIED: ...]` markers were needed in the body text above — every checked claim's source said what the doc attributed to it, with figures and quotes reproducing near-verbatim. This does not itself validate the 4 unchecked findings (#1, #3, #4, #10 and the ast-grep/HN secondary sources in #10/#12/#13) — those were out of scope for this pass and carry the same caveats the original doc already flagged (vendor self-report, single-team benchmark, low-engagement HN threads).
