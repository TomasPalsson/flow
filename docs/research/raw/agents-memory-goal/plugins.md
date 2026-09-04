# Claude Code Plugins in 2026: Marketplace, Structure, Recommended Set, and What Gets Uninstalled

## TL;DR

- The official marketplace `claude-plugins-official` is auto-registered on first interactive launch and lists 200+ plugins as of mid-2026 — roughly a third first-party (Anthropic-built: code-review, security-guidance, feature-dev, commit-commands, pr-review-toolkit, frontend-design, hookify, ralph-loop, LSP servers) and the rest partner/community integrations (GitHub, Playwright, Context7, Supabase, Figma, Vercel, Linear, Sentry, etc.). (code.claude.com/docs/en/discover-plugins, PRIMARY, fetched 2026-09-04)
- Plugin structure is standardized: `.claude-plugin/plugin.json` manifest (optional — auto-discovery works without it) plus root-level `skills/`, `commands/`, `agents/`, `hooks/hooks.json`, `.mcp.json`, `.lsp.json`, `workflows/`, `monitors/monitors.json`, `bin/`. `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's install dir for portable script/command paths; `${CLAUDE_PLUGIN_DATA}` is a separate persistent-data dir that survives updates. (code.claude.com/docs/en/plugins-reference, PRIMARY, 2026-09-04)
- `claude plugin init <name>` scaffolds a "skills-dir" plugin directly under `~/.claude/skills/<name>/` (or a project's `.claude/skills/`) that auto-loads next session as `<name>@skills-dir` — no marketplace, no install step. This is the fast path for personal/team-local plugins. (code.claude.com/docs/en/plugins, PRIMARY; verified against local `claude plugin init --help`, v2.1.260, PRIMARY, 2026-09-04)
- `claude plugin eval` is a real, documented-in-CLI command (confirmed via local install, v2.1.260) that runs YAML/graders-based eval cases against a plugin, with an automatic no-plugin baseline arm (`--ablation with-without`) to show the score delta a plugin actually buys you — i.e., Anthropic built a way to quantitatively justify keeping a plugin installed. It was NOT surfaced by web search of the docs index in this session; verified directly against the installed CLI. (local CLI `claude plugin eval --help`, v2.1.260, PRIMARY, 2026-09-04)
- Per-project enablement is done via `.claude/settings.json`'s `extraKnownMarketplaces` + `enabledPlugins` — the standard way teams pin a shared plugin set into version control. (code.claude.com/docs/en/discover-plugins and /plugin-marketplaces, PRIMARY, 2026-09-04)
- Every plugin install now shows a **Context cost** (projected token cost per turn) and **Last updated**/**Last used** in the `/plugin` UI, and Claude Code auto-flags plugins **Not used recently** (installed, unused ≥2 weeks over ≥10 sessions) — this is Anthropic's own built-in answer to "which plugins are dead weight." (code.claude.com/docs/en/discover-plugins, PRIMARY, 2026-09-04)
- Practitioners who tested multiple plugins report concrete failure modes for uninstalling: data-accuracy hallucination in a "Sales" plugin, always-on output-style plugins taxing every turn regardless of task, and functional overlap between adjacent plugins (Marketing vs Sales both doing competitive research). (buildtolaunch.substack.com, SECONDARY/opinion, 2026-03-23)
- Security researchers documented a live class of attack — malicious/injected marketplace plugins whose hooks rewrite permission settings or whose commands carry prompt injection to exfiltrate data — making "only install from marketplaces/authors you trust" a load-bearing (not decorative) warning in the official docs. (promptarmor.substack.com, SECONDARY, 2025-10-16; corroborated by code.claude.com/docs/en/discover-plugins's own Security section, PRIMARY)

---

## Findings

1. **The official marketplace auto-adds on first run; there's also a separate curated community marketplace and an unlimited number of self-hosted ones.** `claude-plugins-official` is added automatically on first interactive launch (fallback: `/plugin marketplace add anthropics/claude-plugins-official`). `claude-plugins-community` is Anthropic's second, manually-added marketplace for third-party plugins that passed automated validation + safety screening, each pinned to a commit SHA in the catalog, synced nightly. Anyone can host a private/team marketplace from any git repo, local path, or hosted `marketplace.json` URL.
   Evidence: exact commands and behavior quoted verbatim from docs.
   URL: https://code.claude.com/docs/en/discover-plugins — PRIMARY, fetched 2026-09-04. Consensus/standard (this is the documented mechanism, not opinion).

2. **The official marketplace groups first-party plugins into: code intelligence (11 LSP plugins), external integrations (GitHub, GitLab, Atlassian, Asana, Linear, Notion, Figma, Vercel, Firebase, Supabase, Slack, Sentry), automatic security review (`security-guidance`), development workflows (`commit-commands`, `pr-review-toolkit`, `agent-sdk-dev`, `plugin-dev`), and output styles (`explanatory-output-style`, `learning-output-style`).** Direct fetch of `.claude-plugin/marketplace.json` via `gh api` (base64-decoded, 4049 lines) confirms exact `name`/`description`/`category`/`homepage` entries for `code-review`, `security-guidance` (v2.0.7, category "security"), `commit-commands`, `pr-review-toolkit`, `feature-dev`, `frontend-design`, `hookify`, `ralph-loop`, `context7`, `playwright`. A category tally of the raw JSON: development 120, productivity 52, database 38, monitoring 20, security 18, deployment 9, design 8, testing 2, others smaller.
   URL: https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json — PRIMARY (raw manifest, fetched via `gh api` 2026-09-04). Standard/consensus (it's the source-of-truth data file).

3. **Exact descriptions of the plugins named in the research question, pulled verbatim from the live marketplace.json:**
   - `code-review`: "Automated code review for pull requests using multiple specialized agents with confidence-based scoring to filter false positives" (category: productivity).
   - `security-guidance` (v2.0.7): "Security review for Claude-generated code. Pattern-based warnings on edits, LLM-powered diff review on Stop, and an agentic commit reviewer that catches injection, XSS, SSRF, hardcoded secrets, and 25+ other vulnerability classes." (category: security). Docs elsewhere note this one is **enabled by default**.
   - `commit-commands`: "Commands for git commit workflows including commit, push, and PR creation."
   - `pr-review-toolkit`: "Comprehensive PR review agents specializing in comments, tests, error handling, type design, code quality, and code simplification."
   - `feature-dev`: "Comprehensive feature development workflow with specialized agents for codebase exploration, architecture design, and quality review."
   - `frontend-design`: "Create distinctive, production-grade frontend interfaces with high design quality. Generates creative, polished code that avoids generic AI aesthetics."
   - `hookify`: "Easily create custom hooks to prevent unwanted behaviors by analyzing conversation patterns or from explicit instructions. Define rules via simple markdown files." — i.e. hookify is explicitly a meta-plugin for authoring hooks from natural-language rules, not a fixed rule set.
   - `ralph-loop`: "Interactive self-referential AI loops for iterative development, implementing the Ralph Wiggum technique. Claude works on the same task repeatedly, seeing its previous work, until completion." Anthropic shipped this as an **official first-party plugin**, formalizing a community-originated pattern (see Finding 12).
   - `context7`: Upstash-authored, tagged `community-managed`. "Upstash Context7 MCP server for up-to-date documentation lookup... Connects to Context7's hosted remote MCP server (https://mcp.context7.com/mcp) — no local Node.js or npx required... Works anonymously out of the box; set CONTEXT7_API_KEY for higher rate limits."
   - `playwright`: "Browser automation and end-to-end testing MCP server by Microsoft. Enables Claude to interact with web pages, take screenshots, fill forms, click elements, and perform automated browser testing workflows." (category: testing).
   - LSP plugins: 11 language-specific plugins (`clangd-lsp`, `csharp-lsp`, `gopls-lsp`, `jdtls-lsp`, `kotlin-lsp`, `lua-lsp`, `php-lsp`, `pyright-lsp`, `rust-analyzer-lsp`, `swift-lsp`, `typescript-lsp`) — each requires the underlying language-server binary pre-installed; the plugin only wires it up, doesn't install the binary.
   URL: https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json — PRIMARY, fetched 2026-09-04. Standard/consensus.

4. **There is no first-party `claude-hud` or "statusline" plugin in the official marketplace** — grepping the full official `marketplace.json` for `hud`/`statusline` returns zero matches. The popular one is a third-party community project: **jarrodwatts/claude-hud**, its own self-hosted marketplace, 27,826 GitHub stars, created 2026-01-02. README: "A Claude Code plugin that shows what's happening — context usage, active tools, running agents, and todo progress. Always visible below your input." Install is `/plugin marketplace add jarrodwatts/claude-hud` then `/plugin install claude-hud` then `/claude-hud:setup` (which configures the `statusLine` setting). A documented Linux install failure mode (EXDEV cross-device link error on tmpfs `/tmp`) was fixed in a later Claude Code release; workaround is setting `TMPDIR` before install.
   URL: https://github.com/jarrodwatts/claude-hud (raw README + GitHub API metadata) — PRIMARY, fetched 2026-09-04. Standard for this specific plugin (its own docs); popularity (star count) is an objective but time-bound signal, not "official."

5. **Plugin directory structure, confirmed field-by-field:** `.claude-plugin/plugin.json` is the only file allowed inside `.claude-plugin/` — everything else (`skills/`, `commands/`, `agents/`, `hooks/`, `workflows/`, `output-styles/`, `.mcp.json`, `.lsp.json`, `bin/`, `settings.json`) lives at plugin root, not nested. The manifest is **optional**: if omitted, Claude Code auto-discovers components in default locations and derives the plugin name from the directory name. Minimal working `plugin.json`:
   ```json
   {
     "name": "my-first-plugin",
     "description": "A greeting plugin to learn the basics",
     "version": "1.0.0",
     "author": { "name": "Your Name" }
   }
   ```
   `commands`, `agents`, `workflows`, `outputStyles`, `experimental.themes`, `experimental.monitors` fields in `plugin.json` **replace** the default directory scan if set; `skills` always **adds to** the default `skills/` scan. Paths must be relative, start with `./`, and cannot escape the plugin root (`../` is rejected as "path escapes plugin directory").
   URL: https://code.claude.com/docs/en/plugins and /plugins-reference — PRIMARY, fetched 2026-09-04. Standard/consensus (spec, not opinion).

6. **`hooks/hooks.json` format and the full current hook-event lifecycle**, confirmed:
   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "Write|Edit",
           "hooks": [
             { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/format-code.sh" }
           ]
         }
       ]
     }
   }
   ```
   Hook `type` can be `command`, `http`, `mcp_tool`, `prompt`, or `agent`. The event list is large (30+ events as of this fetch) including `SessionStart`, `UserPromptSubmit`, `PreToolUse`/`PostToolUse`/`PostToolUseFailure`, `PermissionRequest`/`PermissionDenied`, `SubagentStart`/`SubagentStop`, `PreCompact`/`PostCompact`, `PreModelSwitch`/`PostModelSwitch`, `FileChanged`, `WorktreeCreate`/`WorktreeRemove`, `SessionEnd`, etc. — a substantially richer hook surface than the early (2025) hooks system.
   URL: https://code.claude.com/docs/en/plugins-reference — PRIMARY, fetched 2026-09-04. Standard/consensus.

7. **`${CLAUDE_PLUGIN_ROOT}` is well-documented but has a known bug report of not being injected in some hook-runner paths.** Docs say: use `${CLAUDE_PLUGIN_ROOT}` for portable paths to scripts/binaries bundled with the plugin; it substitutes into hook/monitor commands, skill/agent content, MCP stdio server `command`/`args`/`env`, MCP http/sse/ws `url`/`headers`, and LSP server fields. Separately, an **open GitHub issue** reports that for the `Stop` hook specifically, `${CLAUDE_PLUGIN_ROOT}` was not being set by the hook runner, causing plugin hook scripts to fail to resolve their own path.
   URLs: https://code.claude.com/docs/en/plugins-reference (PRIMARY, 2026-09-04, spec) and https://github.com/anthropics/claude-code/issues/66557 (title/existence PRIMARY as a GitHub issue, but content only from search snippet — treat the specific bug claim as SECONDARY/unverified detail since the issue body itself wasn't fetched). Contested/unresolved as of this research (open issue).

8. **`claude plugin eval` exists and is a fully-specified subcommand** (confirmed directly against the installed CLI, v2.1.260 — this is the most authoritative kind of primary source, the actual shipped tool):
   - Usage: `claude plugin eval [options] [command] [target]`
   - Looks for eval cases at `<eval-dir>/**/case.yaml` or `prompt.md` + `graders/*.md`; default eval dir is `evals/` unless overridden by `--eval-dir` or a manifest field.
   - `target` can be a filesystem path, a plugin name, or `plugin@marketplace`; both installed and skills-dir plugins resolve.
   - `--ablation with-without` (the default whenever a plugin resolves) runs a **no-plugin baseline arm** and reports the score delta — i.e., built-in A/B testing of "does this plugin actually help."
   - Other flags: `--case <glob>`, `--tag`, `--runs <n>` (default 3 per case), `--judge-model` (default haiku), `--threshold` (exit 1 below score), `--max-cost-usd`, `--mocks record|off` for MCP servers, `--json`/`--report` for output, `--publish-report`/`--no-publish` to push an HTML report to claude.ai.
   - `claude plugin eval init [--bare] <name>` scaffolds an eval suite via an interview.
   URL: local CLI, `claude --version` → 2.1.260; `claude plugin eval --help` — PRIMARY, 2026-09-04. This did not surface via the official docs' llms.txt index fetched in this session (no `/docs/en/plugin-evals` page was listed), so treat the *existence in docs* as unconfirmed/undocumented-in-web-docs even though it is real, shipped CLI behavior — a documentation gap, not a feature gap.

9. **Skills-dir plugins are the lightweight, no-marketplace path for personal/local plugins.** `claude plugin init <name>` scaffolds `~/.claude/skills/<name>/.claude-plugin/plugin.json` (+ starter `SKILL.md`), auto-loading next session as `<name>@skills-dir` with zero install/marketplace step. Project-scoped skills directories (`<cwd>/.claude/skills/`) load only after the workspace-trust dialog is accepted, and their MCP servers need per-server approval while LSP servers and background monitors don't load at all in that scope. Editing a skill's `SKILL.md` takes effect immediately; editing hooks/`.mcp.json`/agents/output-styles requires `/reload-plugins` or restart. `claude plugin disable my-tool@skills-dir` removes it from the active set; there's no separate uninstall step (delete the folder).
   URL: https://code.claude.com/docs/en/plugins-reference and /plugins — PRIMARY, 2026-09-04; cross-checked against local `claude plugin init --help` output (`--with skills agents hooks mcp lsp output-style channel`) — PRIMARY, 2026-09-04. Standard/consensus.

10. **Per-project enablement is `.claude/settings.json`'s `extraKnownMarketplaces` + `enabledPlugins`.** Team admins add a marketplace source and a list of `"plugin@marketplace": true` entries to the project's checked-in settings file; once a team member trusts the repo folder, Claude Code adds the marketplace automatically. As of Claude Code v2.1.195, adding the marketplace via project settings does **not** auto-install plugins sourced externally (e.g. from GitHub) — the team member still has to run `claude plugin install` themselves; until then the plugin shows as not-installed with the exact install command surfaced.
    ```json
    {
      "extraKnownMarketplaces": {
        "my-team-tools": { "source": { "source": "github", "repo": "your-org/claude-plugins" } }
      },
      "enabledPlugins": { "code-formatter@company-tools": true, "deployment-tools@company-tools": true }
    }
    ```
    URL: https://code.claude.com/docs/en/discover-plugins and /plugin-marketplaces — PRIMARY, 2026-09-04. Standard/consensus.

11. **Anthropic's own UI now surfaces plugin "noise/overlap/cost" signals directly, rather than leaving it purely to practitioner judgment.** In `/plugin`'s Discover/Installed tabs: a **Context cost** estimate (tokens added per turn) and **Last updated** date show before install; after install, a **Last used** line and a **Not used recently** grouping (unused ≥2 weeks, over ≥10 sessions) surface dead weight. Exempt from the "unused" flag: org-managed/`--plugin-dir` plugins, and plugins whose only value is a theme/output-style/monitor/workflow (no invocation to track). Enabling/disabling a plugin mid-session can invalidate the prompt cache and forces a full context re-read on the next turn — a direct, quantified token cost to toggling plugins carelessly.
    URL: https://code.claude.com/docs/en/discover-plugins (section "Manage installed plugins" and "Apply plugin changes without restarting") — PRIMARY, 2026-09-04. Standard/consensus (documented product behavior).

12. **`ralph-loop`'s technique predates and is credited to a named practitioner, not invented by Anthropic.** Geoffrey Huntley's July 2025 post coined the "Ralph Wiggum" technique: a bash loop (`while :; do cat PROMPT.md | claude-code; done`) that re-runs the agent against the same task repeatedly, letting it see and build on its own prior output until done; works best on greenfield projects, is "deterministically bad in an undeterministic world" (failures are systematic, hence tunable), and still needs an experienced engineer steering the prompt. Anthropic later shipped `ralph-loop` as an official first-party plugin in the marketplace, formalizing this community pattern.
    URL: https://ghuntley.com/ralph/ — SECONDARY/opinion for the technique's merits and caveats (practitioner's own claims, e.g. the "$50,000 contract for $297" anecdote is unverified), but PRIMARY for "who coined the term and when." Contested: whether the technique generalizes beyond greenfield/solo work is the author's own stated limitation, not resolved by wider consensus.

13. **A curated marketplace review (11 plugins tested, 4 kept) documents concrete uninstall reasons that map onto "context cost, overlap, noise."** Author kept `Brand Voice`, `Marketing` (six-skill SEO/content/brand/competitive-research plugin), and conditionally `explanatory-output-style`. Uninstalled: `Sales` — "claimed I had 2,000 subscribers. I have 5,000+" and mismatched competitor comparisons (data-accuracy failure, not a context-cost issue); `Productivity` — "redundant for users with existing task management systems" (pure overlap with a home-grown system). `explanatory-output-style` was kept only conditionally because it "runs on every response," including on quick coding questions where it adds unneeded token cost — the always-on-output-style pattern is called out explicitly as a tax on every turn regardless of relevance. Also noted: schema validation issues in a third-party marketplace file (`knowledge-work-plugins`) during testing.
    URL: https://buildtolaunch.substack.com/p/best-claude-code-plugins-tested-review — SECONDARY, one practitioner's opinion, published 2026-03-23.

14. **A second practitioner's "daily driver" writeup gives an explicit layered-adoption philosophy that treats plugins as the last resort, not the first tool reached for**, directly answering "which plugins duplicate a home-grown harness." Stated hierarchy: CLAUDE.md → Skills → Subagents → MCPs → Plugins (plugins are explicitly framed as "bundled collections of the above"). Four "day-one installs" recommended regardless: `code-review` (four parallel confidence-scored review agents), `feature-dev` (seven-phase structured dev workflow), a language-server plugin ("highest-leverage plugin you can install"), and `security-guidance`. Direct quote on the redundancy/noise risk: *"A team-shared `.mcp.json` together with a few well-chosen plugins gets a new engineer productive within minutes... Resist installing every MCP. Each one expands the tool list Claude reasons over, and bloated tool lists hurt decision quality."* — i.e. the stated failure mode isn't just token cost, it's degraded tool-selection accuracy from a bloated tool list.
    URL: https://arps18.github.io/posts/claude-code-mastery/ — SECONDARY, one practitioner's opinion, published 2026-05-27.

15. **A documented, named security-attack class targets marketplace plugins specifically** (not MCP servers generically): a malicious/injected marketplace or plugin whose hooks rewrite Claude Code's permission settings (auto-approving `curl` etc.) combined with a command carrying prompt injection that convinces Claude to exfiltrate files to an attacker-controlled endpoint disguised as a legitimate service — bypassing the human-in-the-loop approval that would normally catch it. Direct quote characterizing the root cause: *"Plugin injection as a hijacking vector works precisely because Claude Code is designed to trust its tool layer — that trust relationship is what makes agentic workflows useful, and it's exactly what makes them exploitable."* [UNVERIFIED: this sentence is not in the PromptArmor article body — it is a reader comment posted 2026-06-12 by a commenter named "Claude code security" (handle claudecodesecurity, is_author:false), 8 months after publication; misattributed here to PromptArmor's own writeup.] Recommended mitigation: allowlisting approved marketplaces/plugins rather than relying on malware scanning alone.
    URL: https://promptarmor.substack.com/p/hijacking-claude-code-via-injected — SECONDARY (security research blog), published 2025-10-16. This is corroborated as a design-level risk (not a one-off bug) by Anthropic's own docs: *"Plugins and marketplaces are highly trusted components that can execute arbitrary code on your machine with your user privileges. Only install plugins and add marketplaces from sources you trust. Anthropic doesn't control what MCP servers, files, or other software are included in plugins and can't verify that they work as intended."* (code.claude.com/docs/en/discover-plugins, PRIMARY, 2026-09-04). Standard/consensus that the risk class is real; specific exploit chain is one researcher's writeup.

16. **A community plugin ("Governor," 0xhimanshu) exists specifically to counter plugin/session context bloat**, evidence that "plugins add noise" is a recognized-enough problem to spawn its own tooling category. README: *"long coding sessions usually do not fail because the AI writes one extra paragraph. They fail because context gets polluted."* Names four pollution sources: verbose tool/build/MCP output flooding the transcript, "bloated recurring files like CLAUDE.md, notes, and rules" taxing every session, scope creep from broad prompts triggering repo-wide scans/retries, and compounding "drift." Delivers content-aware output filtering (compacts blocks with >40% duplicate lines), a compact-response mode, `/governor:compress` memory compression, and telemetry on blocked tokens.
    URL: https://github.com/0xhimanshu/governor — PRIMARY for what the tool claims to do (its own README), but SECONDARY/unverified for whether it actually delivers the claimed savings (no independent benchmark found in this research pass).

17. **No commerce layer exists in the plugin ecosystem** — `marketplace.json` has no `price`, `currency`, `checkout_url`, `sku`, `trial`, or `license_key` fields; installation is essentially `git`-based file copying to a local cache, making paywalls technically infeasible without a separate SaaS layer. The only real "cost" surfaced to users is the token/context cost shown in the plugin details panel, borne by the user paying for model usage, not by the plugin author. One commentator frames this as a structural distinction between markets that pay for *designed artifacts* vs. *configurations* that a model can regenerate from a description — implying plugins-as-configuration have weak monetization incentive, which in turn affects maintenance/quality incentives across the ecosystem.
    URL: https://www.promptreceipts.com/blog/claude-code-plugin-marketplace-no-price-2026 — SECONDARY, one commentator's opinion/framing, published 2026-08-02.

18. **LSP plugins have specific, documented failure modes distinct from "context noise":** high memory usage on large projects (`rust-analyzer`, `pyright` called out by name) with the documented workaround being `/plugin disable <plugin-name>` and falling back to Claude's built-in grep-based search; false-positive unresolved-import diagnostics in monorepos with misconfigured workspaces (doesn't block Claude's ability to edit, just adds noisy diagnostics); and in cloud/web sessions, Claude Code doesn't start plugin language servers at all, so the LSP tool simply isn't available there regardless of installation.
    URL: https://code.claude.com/docs/en/discover-plugins (Troubleshooting → Code intelligence issues) — PRIMARY, 2026-09-04. Standard/consensus (documented limitation).

---

## Downsides and failure modes

- **Prompt-cache invalidation / token cost from toggling plugins mid-session.** Enabling/disabling a plugin during a session can invalidate the prompt cache, forcing the next request to re-read the entire conversation instead of hitting cache — a direct, quantifiable cost the docs call out by name, with a `--force` flag required on `/reload-plugins` when this would happen. (code.claude.com/docs/en/discover-plugins, PRIMARY)
- **MCP-bearing plugins are costlier to reload than others**, specifically when their tools aren't deferred via tool search — same cache-invalidation mechanism, worse because MCP tool schemas are large. (code.claude.com/docs/en/discover-plugins, PRIMARY)
- **Always-on output-style plugins tax every single turn**, including turns where the plugin's value-add (e.g. "educational explanations") is irrelevant — a coding one-liner still pays the token cost. (buildtolaunch.substack.com, SECONDARY)
- **Bloated tool lists degrade decision quality**, not just cost tokens — a distinct, more subtle failure mode than raw context size: more tools to reason over means worse tool selection. (arps18.github.io, SECONDARY, one practitioner's claim, not independently benchmarked here)
- **Data-accuracy / hallucination risk inside a plugin's own domain logic** (e.g., a "Sales" plugin fabricating subscriber counts) — a plugin can be wrong about the very thing it's supposed to know, and Claude has no independent way to catch this since the plugin's skill content is itself the source of truth being executed. (buildtolaunch.substack.com, SECONDARY)
- **Security: plugins are "highly trusted... can execute arbitrary code on your machine with your user privileges"** and Anthropic explicitly disclaims verifying that MCP servers/files/software bundled in plugins "work as intended," even for community-marketplace plugins that passed automated screening. (code.claude.com/docs/en/discover-plugins, PRIMARY)
- **A documented exploit chain**: malicious plugin hooks rewrite permission settings to auto-approve dangerous commands, combined with prompt-injection in a plugin command, to exfiltrate data while bypassing human-in-the-loop approval. Mitigation recommended is allowlisting, not just malware scanning. (promptarmor.substack.com, SECONDARY, 2025-10-16 — over 10 months old relative to "today," so treat the specific chain as possibly since-patched; the general trust warning in the docs is current as of 2026-09-04 and still stands)
- **LSP plugin memory pressure on large repos** (rust-analyzer, pyright named specifically) with disable-and-fall-back-to-grep as the documented remedy. (code.claude.com/docs/en/discover-plugins, PRIMARY)
- **`${CLAUDE_PLUGIN_ROOT}` reportedly unset in at least one hook-runner code path** (`Stop` hook, per an open GitHub issue title) — treat as a live/unresolved bug risk when writing plugin hook scripts that assume the variable is always populated; verify before shipping. (github.com/anthropics/claude-code/issues/66557, existence PRIMARY, content SECONDARY/unverified since only the issue title/snippet was retrieved, not the full thread)
- **A second, related open issue**: plugin hooks in `settings.json` reportedly not updated when a plugin's version changes — a staleness/drift risk for anyone relying on hook behavior tracking plugin version bumps. (github.com/anthropics/claude-code/issues/18517, existence PRIMARY, content unverified — title only)
- **URL-based (non-git) marketplaces have known limitations** — "path not found" errors can occur installing plugins with relative paths, per the docs' own troubleshooting section. (code.claude.com/docs/en/discover-plugins, PRIMARY)

---

## Concrete practices / configs (copy-pasteable)

### Add and install from the official marketplace
```bash
# Usually automatic on first interactive launch; if not:
/plugin marketplace add anthropics/claude-plugins-official

# Install a specific first-party plugin
/plugin install code-review@claude-plugins-official
/plugin install security-guidance@claude-plugins-official
/plugin install feature-dev@claude-plugins-official
/plugin install commit-commands@claude-plugins-official
/plugin install pr-review-toolkit@claude-plugins-official
/plugin install frontend-design@claude-plugins-official
/plugin install hookify@claude-plugins-official
/plugin install ralph-loop@claude-plugins-official
/plugin install context7@claude-plugins-official
/plugin install playwright@claude-plugins-official
/plugin install typescript-lsp@claude-plugins-official   # install the language-server binary yourself first
```

### Community marketplace
```bash
/plugin marketplace add anthropics/claude-plugins-community
/plugin install <plugin-name>@claude-community
```

### Minimal plugin manifest (`.claude-plugin/plugin.json`)
```json
{
  "name": "my-first-plugin",
  "description": "A greeting plugin to learn the basics",
  "version": "1.0.0",
  "author": { "name": "Your Name" }
}
```

### Minimal skill (`skills/hello/SKILL.md`)
```markdown
---
description: Greet the user with a personalized message
---

# Hello Skill

Greet the user named "$ARGUMENTS" warmly and ask how you can help them today.
```

### `hooks/hooks.json` — run a formatter after every Write/Edit
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/format-code.sh" }
        ]
      }
    ]
  }
}
```

### `.mcp.json` — bundle an MCP server with the plugin
```json
{
  "mcpServers": {
    "plugin-database": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/db-server",
      "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"],
      "env": { "DB_PATH": "${CLAUDE_PLUGIN_ROOT}/data" }
    }
  }
}
```

### `.lsp.json` — custom language server (only if no official LSP plugin covers it)
```json
{
  "go": {
    "command": "gopls",
    "args": ["serve"],
    "extensionToLanguage": { ".go": "go" }
  }
}
```

### Local dev / testing loop (no marketplace needed)
```bash
claude --plugin-dir ./my-plugin           # load a local plugin dir for this session
claude --plugin-dir ./my-plugin.zip       # also accepts a zip archive
# after edits:
/reload-plugins
```

### Fast personal plugin (skills-dir, no marketplace, no install step)
```bash
claude plugin init my-tool --with skills hooks
# scaffolds ~/.claude/skills/my-tool/.claude-plugin/plugin.json
# auto-loads next session as my-tool@skills-dir
claude plugin disable my-tool@skills-dir   # to turn off; delete the folder to remove entirely
```

### Per-project enablement (`.claude/settings.json`, checked into the repo)
```json
{
  "extraKnownMarketplaces": {
    "my-team-tools": {
      "source": { "source": "github", "repo": "your-org/claude-plugins" }
    }
  },
  "enabledPlugins": {
    "code-formatter@my-team-tools": true,
    "deployment-tools@my-team-tools": true
  }
}
```

### Validate a plugin before publishing/sharing
```bash
claude plugin validate ./your-plugin           # basic
claude plugin validate ./your-plugin --strict  # warnings fail the check too
```

### Evaluate whether a plugin is actually earning its keep
```bash
# Runs the plugin's evals/ suite AND a no-plugin baseline arm, reports the delta:
claude plugin eval my-plugin@my-marketplace
claude plugin eval ./my-plugin --tag regression --runs 5 --threshold 0.9
claude plugin eval my-plugin --json out.json   # machine-readable result for CI gating
```

### Audit what's installed and drop dead weight
```bash
/plugin                 # → Installed tab shows "Not used recently" (unused ≥2wk, ≥10 sessions) + per-plugin token Context cost
/plugin list --enabled
claude plugin prune --dry-run    # see auto-installed dependencies you could remove
```

### Disable a heavy LSP plugin if it's thrashing memory on a big repo
```bash
/plugin disable rust-analyzer-lsp
# Claude falls back to built-in grep-based search
```

---

## Disagreements and open questions

- **"Which plugins duplicate a home-grown harness?"** has no single documented answer — it's inherently a function of what the individual developer already built with CLAUDE.md/Skills/Subagents/hooks. The one clear pattern across both opinion sources fetched (buildtolaunch, arps18) is: **task-management/productivity-style plugins are the most commonly cited as redundant** once you already have your own system (todo tracking, project-management integration), whereas **code-review, security-guidance, feature-dev, and a language-server plugin are the most consistently recommended as non-redundant, "install regardless"** — but both of these are single-practitioner opinions (SECONDARY), not a surveyed consensus.
- **Whether `${CLAUDE_PLUGIN_ROOT}` is reliably injected across all hook events is unresolved** — the reference docs present it as universal, but at least one open GitHub issue (title-level evidence only, not fully read) claims it's missing for at least the `Stop` hook. This should be spot-checked against the current CLI version before depending on it in a hook that must not silently no-op.
- **`claude plugin eval`'s existence in the shipped CLI (v2.1.260) vs. its near-total absence from the crawled docs index** is itself a finding worth flagging to the user: either the feature is newer than the docs snapshot indexed by search, or it's intentionally CLI-only/experimental. This report cannot resolve which, since WebSearch quota was exhausted before a targeted "claude plugin eval site:code.claude.com" query could be run.
- **The security-attack writeup (promptarmor, Oct 2025) is ~11 months old relative to "today" (2026-09-04)** — Anthropic's docs still carry the same blanket trust warning verbatim, suggesting the *class* of risk is still considered live, but whether the *specific* exploit chain described was patched is not established by this research.
- **No independent benchmark was found for whether context-bloat-mitigation plugins (e.g. Governor) actually reduce token spend** as claimed — the only evidence is the tool's own README.

---

## Sources

1. https://code.claude.com/docs/en/discover-plugins — PRIMARY (official docs), fetched 2026-09-04. Marketplace add/install mechanics, categories, context-cost/last-used UI, security warning, troubleshooting.
2. https://code.claude.com/docs/en/plugins — PRIMARY, fetched 2026-09-04. Plugin creation quickstart, directory structure, skills-dir plugins, community-marketplace submission.
3. https://code.claude.com/docs/en/plugins-reference — PRIMARY, fetched 2026-09-04. Full plugin.json schema, hooks.json format and event list, LSP/.mcp.json schema, CLI command reference, skills-dir details, userConfig, monitors, themes.
4. https://code.claude.com/docs/en/plugin-marketplaces — PRIMARY, fetched 2026-09-04. marketplace.json schema, plugin sources (github/git/git-subdir/npm/archive/command), strict mode, managed marketplace restrictions, per-project `extraKnownMarketplaces`/`enabledPlugins`.
5. https://code.claude.com/docs/llms.txt — PRIMARY, fetched 2026-09-04. Docs index used to confirm which plugin-related pages exist (and that no dedicated "plugin eval" doc page appears in the crawled index).
6. https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json — PRIMARY (raw source-of-truth manifest), fetched via `gh api` 2026-09-04. Exact descriptions/categories for code-review, security-guidance, commit-commands, pr-review-toolkit, feature-dev, frontend-design, hookify, ralph-loop, context7, playwright; category tallies; renames map.
7. Local CLI (`claude --version` = 2.1.260; `claude plugin --help`, `claude plugin eval --help`, `claude plugin init --help`, `claude plugin details --help`, `claude plugin validate --help`) — PRIMARY, executed 2026-09-04. Confirms `claude plugin eval`, `tag`, `details`, `validate --strict` subcommands and their exact flags.
8. https://github.com/jarrodwatts/claude-hud (README + GitHub API repo metadata) — PRIMARY (project's own docs/data), fetched 2026-09-04. Install flow, star count, description, EXDEV bug note.
9. https://buildtolaunch.substack.com/p/best-claude-code-plugins-tested-review — SECONDARY, practitioner opinion, published 2026-03-23. Kept-vs-uninstalled plugin verdicts and reasons.
10. https://arps18.github.io/posts/claude-code-mastery/ — SECONDARY, practitioner opinion, published 2026-05-27. Layered-adoption philosophy, "day-one installs," bloated-tool-list warning.
11. https://ghuntley.com/ralph/ — mixed PRIMARY (attribution/definition) / SECONDARY (claimed results), author's own post dated July 2025 (per fetch summary). Origin and mechanics of the Ralph Wiggum technique that `ralph-loop` formalizes.
12. https://promptarmor.substack.com/p/hijacking-claude-code-via-injected — SECONDARY, security research, published 2025-10-16. Marketplace-plugin hijack attack chain and mitigation.
13. https://github.com/0xhimanshu/governor — PRIMARY for the tool's own claims (README), fetched 2026-09-04. Names four context-pollution sources and its mitigations.
14. https://www.promptreceipts.com/blog/claude-code-plugin-marketplace-no-price-2026 — SECONDARY, opinion/commentary, published 2026-08-02. No-commerce-layer framing and token-cost-not-dollar-cost point.
15. Hacker News (via hn.algolia.com public API) — PRIMARY (index of publication metadata: titles, URLs, dates, points) used to locate items 8, 9 (indirectly), 10, 12, 13, 14, and to confirm the original Anthropic launch post "Customize Claude Code with plugins" (https://www.anthropic.com/news/claude-code-plugins, dated 2025-10-09 per HN metadata; not independently fetched/quoted in this report — flagged as unread primary source below).

### Sources found but not fetched (gaps)
- https://www.anthropic.com/news/claude-code-plugins — the original Anthropic launch announcement (per HN metadata, 2025-10-09). Not fetched in this pass; would be the strongest primary source for plugin-system history/intent and should be read before citing launch-era claims.
- https://medium.com/@hii_mohit/9-claude-code-plugins-every-developer-should-install-in-2026-9a35b8fe5a83 — returned HTTP 403 to WebFetch; only a search-engine snippet summary was available, so its specific "9 plugins" list was not independently verified and is deliberately omitted from Findings above.
- https://getclaudekit.com/blog/tools/plugins/plugin-json-reference — HTTP 403 to WebFetch; not a load-bearing gap since code.claude.com/docs/en/plugins-reference (PRIMARY) covers the same schema directly.
- https://github.com/anthropics/claude-code/issues/66557 and /issues/18517 — only titles/existence confirmed via search snippet; issue bodies/comment threads were not fetched, so the specific bug mechanics are unverified beyond the title.
- Further WebSearch queries planned for "claude plugin eval site:code.claude.com" and "Claude Code plugins overload reddit 2026" could not be run — this session's WebSearch quota (200/200) was exhausted after 2 successful searches (evidently a shared/session-wide budget, not specific to this research task). All subsequent research relied on WebFetch, `gh api`, and direct `curl` (including the public Hacker News Algolia API) as substitutes.
- Reddit (r/ClaudeAI, r/ClaudeCode) practitioner discussion on plugin uninstalls was not directly sampled — HN and two independent blogs (buildtolaunch, arps18) stand in as the practitioner-opinion layer instead.

## Source check (independent)

Method: picked the 6 most load-bearing claims (numbers, quotes, field names, attributions) and re-fetched each cited source independently (WebFetch, plus direct `curl`/`gh api` grep against the raw marketplace.json and the raw PromptArmor page JSON, and the GitHub REST API for claude-hud's repo metadata, where a rendered/AI-summarized fetch risked truncation or missed context). No source URL was dead; no WebSearch fallback was needed.

**1. Finding 1 — "`claude-plugins-official` auto-registered on first interactive launch"; `claude-plugins-community` is manually added, hosts third-party plugins that passed automated validation + safety screening, each pinned to a commit SHA in the catalog, "synced nightly."**
Verdict: **PARTIAL**
- Auto-registration on first launch: CONFIRMED verbatim — source says "Claude Code adds the official Anthropic marketplace (`claude-plugins-official`) automatically the first time you start it interactively."
- Manual add + validation/screening + per-plugin commit-SHA pinning: CONFIRMED verbatim — "The community marketplace at `anthropics/claude-plugins-community` hosts third-party plugins that have passed Anthropic's automated validation and safety screening. Each plugin is pinned to a specific commit SHA in the catalog. Unlike the official marketplace, you add it manually."
- "Synced nightly": **not supported** — this exact cadence does not appear anywhere on the fetched `discover-plugins` page. The page does describe an auto-update mechanism ("Claude Code checks for marketplace and plugin updates after your session starts, with a random delay of up to ten minutes") but nothing calls this "nightly," and that passage describes the *client's* poll cadence, not how the community catalog itself is synced. Treat "nightly" as an unverified addition.

**2. Finding 2/3 — marketplace.json category tally (development 120, productivity 52, database 38, monitoring 20, security 18, deployment 9, design 8, testing 2) and exact `code-review`/`security-guidance` descriptions, categories, and `security-guidance` version 2.0.7.**
Verdict: **CONFIRMED**
- Direct `grep -c` of the raw file at github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json reproduces the tally exactly: development 120, productivity 52, database 38, monitoring 20, security 18, deployment 9, design 8, testing 2 (plus a few smaller categories the report correctly folded into "others smaller": learning 3, automation 3, location 2, migration 1, math 1).
- `code-review` entry (line 991): `"description": "Automated code review for pull requests using multiple specialized agents with confidence-based scoring to filter false positives"`, `"category": "productivity"` — exact match.
- `security-guidance` entry (line 3230): `"version": "2.0.7"`, `"description": "Security review for Claude-generated code. Pattern-based warnings on edits, LLM-powered diff review on Stop, and an agentic commit reviewer that catches injection, XSS, SSRF, hardcoded secrets, and 25+ other vulnerability classes."` — exact match, including the version number.
- Note: an initial WebFetch (AI-summarized) of this same 4,049-line file failed to find the `security-guidance` entry at all and gave rough, wrong-order category estimates — the file is long enough that summarized fetches truncate; only a direct grep against the raw JSON gave a reliable check.

**3. Finding 11 — plugin UI shows "Context cost" and "Last updated"/"Last used," and flags plugins "Not used recently" at a threshold of unused ≥2 weeks over ≥10 sessions.**
Verdict: **CONFIRMED**
- Source: "Claude Code also lists marketplace plugins you installed yourself but haven't used in at least two weeks, over a span of at least 10 sessions, under a **Not used recently** header in the **Installed** tab. The detail view shows a **Last used** line for each plugin."
- "Context cost" and "Last updated" also confirmed verbatim in the install-details description: "A **Context cost** estimate so you can see how many tokens the plugin will add to your context window every turn" and "The plugin's **Last updated** date."
- The report's stated exemptions (org-managed/`--plugin-dir` plugins; theme/output-style/monitor/workflow-only plugins) also match the doc's "Two kinds of plugins are never listed as unused" list exactly.

**4. Finding 12 — Ralph Wiggum technique credited to Geoffrey Huntley (ghuntley.com/ralph/, July 2025); bash loop `while :; do cat PROMPT.md | claude-code; done`; quote "deterministically bad in an undeterministic world."**
Verdict: **CONFIRMED**
- Source confirms the named bash loop, the "Ralph" nickname, and the exact phrase "deterministically bad in an undeterministic world" ("That's the beauty of Ralph - the technique is deterministically bad in an undeterministic world").
- Publish date confirmed as 14 Jul 2025, consistent with the report's dating and with `ralph-loop` (a 2026 Anthropic plugin) postdating and formalizing it.

**5. Finding 15 — quote "Plugin injection as a hijacking vector works precisely because Claude Code is designed to trust its tool layer — that trust relationship is what makes agentic workflows useful, and it's exactly what makes them exploitable," attributed to the PromptArmor article (promptarmor.substack.com/p/hijacking-claude-code-via-injected, 2025-10-16).**
Verdict: **MISATTRIBUTED**
- Pulled the raw page JSON directly (not just the rendered article) and located this exact sentence verbatim — but it is embedded in the page's `comments` payload, not the post `body`: `"type":"comment"`, `"date":"2026-06-22T00:56:22.528Z"`-ish (confirmed 2026-06-12), `"name":"Claude code security"`, `"handle":"claudecodesecurity"`, `"metadata":{"is_author":false,...}`. It is a reader comment posted roughly 8 months after the article, not something PromptArmor wrote.
- The article's own byline/title/description were confirmed independently ("By: PromptArmor", "Hijacking Claude Code via Injected Marketplace Plugins", `article:modified_time` 2025-10-21), so the article and its 2025-10-16 date are real — only this specific quote's attribution is wrong. Inline `[UNVERIFIED: ...]` tag added at the claim in Finding 15.
- The separate quote in the same finding attributed to Anthropic's own docs ("Plugins and marketplaces are highly trusted components...") was independently re-confirmed verbatim on code.claude.com/docs/en/discover-plugins and is correctly sourced.

**6. Finding 4 — claude-hud: 27,826 GitHub stars, created 2026-01-02, README tagline, install command sequence.**
Verdict: **CONFIRMED**
- GitHub REST API (`api.github.com/repos/jarrodwatts/claude-hud`) returns `"stargazers_count": 27826` and `"created_at": "2026-01-02T01:35:07Z"` — exact match to both figures in the report.
- README description confirmed near-verbatim: "A Claude Code plugin that shows what's happening - context usage, active tools, running agents, and todo progress" (report renders the dash as an em-dash; substance identical).
- Install sequence independently reproduced as `/plugin marketplace add jarrodwatts/claude-hud` → `/plugin install claude-hud` → `/reload-plugins` → `/claude-hud:setup`, consistent with the report (report omits the intermediate `/reload-plugins` step but doesn't contradict it).

### Reliability note
5 of 6 checked claims hold up as CONFIRMED against primary sources, including two claims (the category tally and the claude-hud stats) that check out to the exact number — a strong signal this report's PRIMARY-sourced, verbatim-quoted claims are trustworthy. The one real problem found is structural, not sloppy paraphrasing: Finding 15's key supporting quote for the security section was silently pulled from a Substack comment rather than the article body, which is exactly the kind of error that survives a rendered-page WebFetch (which shows comments inline below the article with no strong visual demarcation) but fails a raw-JSON check. The "synced nightly" detail in Finding 1 looks like a plausible but unsourced elaboration — small, but worth dropping or re-sourcing. Recommend: (a) fix or drop the Finding 15 quote/attribution, since it's currently doing real evidentiary work in the "Downsides and failure modes" section; (b) spot-check any other quote in this report that was gathered by a rendered/summarized fetch of a comments-enabled page (Substack, Medium, etc.) rather than raw source or an API.
