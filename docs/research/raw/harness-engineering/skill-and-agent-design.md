# Best Practices for Authoring Claude Code Skills, Subagents, and Plugins (2026)

## TL;DR

- Skills are progressively disclosed in three tiers — name+description at session start, full `SKILL.md` body on activation, linked reference files only when actually read — so the only unavoidable cost of an unused skill is its metadata line. (PRIMARY, Anthropic engineering blog + docs)
- Anthropic's own docs say keep `SKILL.md` body **under 500 lines**, keep reference links **one level deep** from `SKILL.md`, and put a table of contents on any reference file over 100 lines. (PRIMARY, `platform.claude.com` best-practices)
- There is a real, measured ceiling on how many skills can be *discovered* at once: independent research found Claude Code's skill-metadata listing is capped at roughly **15,500–16,000 characters**, and with an observed average 263-character description that's only **~42 skills** before entries silently disappear from the list (documented case: "Showing 42 of 63 skills," 21 hidden with no warning). (SECONDARY, independent GitHub gist research, cross-referenced against a GitHub issue)
- Anthropic's decision matrix is explicit and binary on determinism: **"An instruction is a request; a hook is a guarantee."** [UNVERIFIED: this exact sentence was not found verbatim in either cited source; the real wording, from `code.claude.com/docs/en/features-overview`'s "Hook vs Skill" tab, is "An instruction like 'never edit .env' in CLAUDE.md or a skill is a request, not a guarantee. A PreToolUse hook that blocks the edit is enforcement." — see Source check below] Anything that "must not happen" or "must happen every time" belongs in a hook (`PreToolUse`/`PostToolUse`/etc.), never in CLAUDE.md or a skill's prose. (PRIMARY, `claude.com/blog` steering post + `code.claude.com/docs/en/best-practices`)
- Official rule of thumb for the CLAUDE.md/skill boundary: **CLAUDE.md under ~200 lines**, always-on facts only; anything that's "reference material Claude needs sometimes" or a repeatable multi-step procedure goes in a skill instead. (PRIMARY, `code.claude.com/docs/en/features-overview`)
- Subagents pin models via `model:` frontmatter (alias like `sonnet`/`opus`/`haiku`, a specific model ID, or `inherit`); as of Claude Code v2.1.257+ you can also force every subagent onto one model globally with `CLAUDE_CODE_SUBAGENT_MODEL` + `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`. (PRIMARY, `code.claude.com/docs/en/sub-agents`)
- Practitioner consensus (not official, but widely repeated): skill sprawl is real — one 15-day audit saw a personal skill count go from 16 → 48, with cross-project pollution ("Swift project" surfacing an unrelated "pdf2anki LLM pipeline" skill) and recommends auditing once any single scope passes ~10 skills. (SECONDARY, dev.to practitioner audit)
- Plugins are the packaging/distribution layer, not a new primitive: a plugin bundles skills, hooks, subagents, MCP servers, and LSP servers behind one install, distributed via a `marketplace.json` catalog added with `/plugin marketplace add`. (PRIMARY, `code.claude.com/docs/en/plugin-marketplaces` + `discover-plugins`)

## Findings

1. **Claim:** Skill loading is a three-tier progressive-disclosure system: (1) metadata (`name`+`description`) for every skill loads into the system prompt at session start; (2) the full `SKILL.md` body loads only once Claude decides the skill is relevant or the user invokes it; (3) any file the skill body links to (reference docs, scripts) loads only when Claude actually reads it, and executable scripts never load their source into context at all — only their stdout does.
   **Evidence:** "At startup, the name and description from all Skills' YAML frontmatter are loaded into the system prompt... Files read on-demand... No context penalty for large files... Scripts executed efficiently... Only the script's output consumes tokens."
   **Source:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices (2026, exact fetch date 2026-09-04) — PRIMARY. Corroborated by https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills (PRIMARY) and https://code.claude.com/docs/en/features-overview (PRIMARY).
   **Status:** Standard/consensus — this is the foundational mechanic every other guideline below depends on.

2. **Claim:** `SKILL.md` frontmatter requires exactly `name` (max 64 chars, lowercase/digits/hyphens only, no XML tags, cannot contain "anthropic" or "claude") and `description` (non-empty, max 1,024 chars in the cross-tool Agent Skills spec used by claude.ai/API uploads). Claude Code itself extends this: it truncates the combined `description` + `when_to_use` text at **1,536 characters** in its own skill listing, and if you include any frontmatter field outside the six-field open standard (`name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`) when packaging for claude.ai/the Skills API, packaging fails with a hard error.
   **Evidence:** Two primary docs give two different limit numbers for description length depending on target: the cross-tool Agent Skills spec caps `description` at 1,024 chars; Claude Code's own frontmatter reference caps the combined description+when_to_use at 1,536 chars for its in-app listing.
   **Source:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices (PRIMARY, 2026); https://code.claude.com/docs/en/skills (PRIMARY, 2026, frontmatter reference table).
   **Status:** Standard/consensus, but note the discrepancy is real (two limits for two contexts), not a reporting error — flag it if you're targeting cross-tool portability vs. Claude Code specifically.

3. **Claim:** Anthropic's official practical guidance: keep `SKILL.md` body under 500 lines, split into separate files once you approach that, keep all reference-file links **one level deep** from `SKILL.md` (a link chain SKILL.md → advanced.md → details.md causes Claude to `head -100` preview rather than fully read nested files), and add a table of contents to any reference file over 100 lines.
   **Evidence:** "Keep SKILL.md under 500 lines. Move detailed reference material to separate files." / "Claude may partially read files when they're referenced from other referenced files... Keep references one level deep from SKILL.md."
   **Source:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices (PRIMARY, 2026).
   **Status:** Standard/consensus — this is Anthropic's own authored guidance, not a third-party inference.

4. **Claim:** Skill descriptions must be written in **third person**, name concrete trigger phrases/keywords, and state both what the skill does and when to use it, because "Claude uses it to choose the right Skill from potentially 100+ available Skills." First person ("I can help you...") or second person ("You can use this to...") descriptions are explicitly called out as causing discovery problems since the description text is injected directly into the system prompt.
   **Evidence:** "Always write in third person. The description is injected into the system prompt, and inconsistent point-of-view can cause discovery problems." Good: "Processes Excel files and generates reports." Bad: "Helps with documents" / "Processes data" / "Does stuff with files."
   **Source:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices (PRIMARY, 2026).
   **Status:** Standard/consensus.

5. **Claim:** Anthropic's naming convention recommendation is **gerund form** (`processing-pdfs`, `analyzing-spreadsheets`) as the preferred pattern, with noun-phrase (`pdf-processing`) or action-verb (`process-pdfs`) forms acceptable, but vague names (`helper`, `utils`, `tools`, `documents`, `data`, `files`) and reserved words (`anthropic-*`, `claude-*`) are anti-patterns.
   **Source:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices (PRIMARY, 2026).
   **Status:** Standard/consensus (this is Anthropic's stated preference, not a universal law — the docs call the noun/verb forms "acceptable alternatives," so it's a style preference with room, not a hard requirement).

6. **Claim (the ~16,000-character skill-index budget — the closest thing to Anthropic's own numbers on skill-index token cost that this research could find published anywhere):** Claude Code's `<available_skills>` metadata block that gets pre-loaded at session start has an undocumented character ceiling around 15,500–16,000 characters. With the researcher's observed average description length of 263 characters plus ~109 characters of per-skill XML/name/location overhead, that yields ~42 skills visible before the rest are silently dropped from the list — with **no warning to the user or model**. A documented real case showed "Showing 42 of 63 skills" with 21 (33%) completely invisible to Claude, and the hidden skills had statistically identical average description length to the shown ones, confirming the cutoff is cumulative-budget-based, not per-skill. Compressing descriptions to ≤130 characters would let roughly 67 skills fit in the same budget.
   **Evidence:** "Claude Code has an undocumented ~15,500-16,000 character budget for skill metadata... 63 skills × (130 char description + 109 overhead) = 15,057 characters fits within the ~16,000 budget... 21 skills (33%) were completely hidden from the agent—it couldn't discover or invoke them." Cross-referenced by the researcher against GitHub issue #12782, which independently arrived at ~15K characters.
   **Source:** https://gist.github.com/alexey-pelykh/faa3c304f731d6a962efc5fa2a43abe1 (2026) — SECONDARY, independent practitioner measurement, not an Anthropic-published number. Anthropic's own docs acknowledge the mechanism exists but do not publish the exact character/token ceiling: the closest official statement is "Not every token in your Skill has an immediate cost... only the metadata (name and description) from all Skills is pre-loaded" (https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices, PRIMARY) with no number attached, and a `/plugin` UI "Context cost" estimate mentioned in https://code.claude.com/docs/en/discover-plugins (PRIMARY) that is per-plugin and shown only in-app, not published as a spec number.
   **Status:** This is the single most load-bearing "how many skills is too many" data point found, and it is explicitly a third-party independent measurement, not an Anthropic-published spec. Treat the exact figure (~16,000 chars / ~42 skills at typical description length) as an empirically-observed current behavior, not a documented contract — it could change without notice since Anthropic hasn't published it.

7. **Claim:** A separate widely-cited but unverified secondary claim states each skill's metadata costs "roughly 100 tokens" (with one source citing a range of "30-235 tokens" depending on description complexity, median ~80 tokens per skill across Anthropic's own 17 official bundled skills). This is a *token* estimate rather than the *character*-budget finding in #6 above, and the two are not derived from the same methodology — treat the specific numbers as approximate practitioner estimates, not an official spec.
   **Source:** Aggregated web-search summaries citing unnamed "independent measurement" of Anthropic's 17 official skills (2026) — SECONDARY, could not independently verify the underlying post via direct fetch (search-snippet only, no primary URL surfaced on this pass).
   **Status:** Contested / unverified — flagged as lower confidence than finding #6, which was independently fetched and read in full.

8. **Claim:** Anthropic's official decision matrix (the closest thing to a canonical "when to use which primitive" table) rates each extension mechanism by *when it loads*, *what loads*, and *context cost*:
   | Feature | Loads | Context cost |
   |---|---|---|
   | CLAUDE.md | Session start, every request | Every request (full content) |
   | Skills | Descriptions at start; full body when used | Low (descriptions only, until used) |
   | MCP servers | Tool names at start; schemas on demand | Low until a tool is used |
   | Subagents | On spawn | Isolated from main session |
   | Hooks | On lifecycle-event trigger | Zero, unless hook returns text into context |

   The doc's explicit rules of thumb: put it in **CLAUDE.md** if Claude should *always* know it (build commands, "never do X" rules); put it in a **skill** if it's reference material needed *sometimes*, or a workflow triggered by `/<name>`; use a **subagent** for context isolation or parallel/verbose work you don't need visible in the main conversation; use a **hook** when "the action must happen the same way every time and doesn't need Claude to think" — an instruction like "never edit `.env`" in CLAUDE.md or a skill "is a request, not a guarantee. A PreToolUse hook that blocks the edit is enforcement."
   **Source:** https://code.claude.com/docs/en/features-overview (PRIMARY, section "Match features to your goal" and "Compare similar features" / "Hook vs Skill" tab), fetched 2026-09-04.
   **Status:** Standard/consensus — this is Anthropic's own canonical decision matrix, currently the most authoritative public source on this question.

9. **Claim:** Anthropic's own blog post on the topic gives context-cost ratings and explicit anti-patterns per mechanism: CLAUDE.md is "**High**" context cost ("every line costs tokens whether relevant or not") and the anti-pattern is putting procedural/deployment workflows there, since "every team appends its own instructions and nothing gets deleted. The cost compounds at scale." Rules (`.claude/rules/` with `paths:` frontmatter) are "Medium" cost, avoidable via path-scoping. Skills are "**Low**" cost (full body loads only on invocation). Subagents are "**Zero** in main context until called," with the explicit rationale: "That isolation is one of the main reasons to reach for a subagent instead of a skill... a side task like deep search, a log analysis pass, or a dependency audit would clutter your main conversation with intermediate results you won't reference again." Hooks are "Low" cost and bypass compaction entirely, with the guardrail principle stated plainly: **"When there's something that absolutely must not happen, an instruction is the wrong tool... A real guardrail needs to be deterministic, and the enforcement methods are hooks and permissions."**
   **Source:** https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more (PRIMARY, Anthropic's own blog, 2026), fetched 2026-09-04.
   **Status:** Standard/consensus — reinforces finding #8 from a second, independently-worded primary Anthropic source.

10. **Claim:** Official CLAUDE.md sizing guidance is consistent across two separate primary docs: "Keep CLAUDE.md under 200 lines" (`features-overview`) and the best-practices page adds a self-test — "For each line, ask: 'Would removing this cause Claude to make mistakes?' If not, cut it. **Bloated CLAUDE.md files cause Claude to ignore your actual instructions!**" An explicit include/exclude table is given: include bash commands Claude can't guess, non-default code style rules, testing instructions, repo etiquette, architectural decisions, env quirks, non-obvious gotchas; exclude anything Claude can infer from reading code, standard language conventions, detailed API docs (link instead), frequently-changing info, long tutorials, file-by-file descriptions, and "self-evident practices like 'write clean code'."
   **Source:** https://code.claude.com/docs/en/best-practices (PRIMARY, "Write an effective CLAUDE.md" section) and https://code.claude.com/docs/en/features-overview (PRIMARY, "CLAUDE.md vs Skill" tab), both fetched 2026-09-04.
   **Status:** Standard/consensus.

11. **Claim:** Subagent YAML frontmatter requires only `name` and `description`; every other field is optional with sensible defaults. The `model` field accepts an alias (`sonnet`, `opus`, `haiku`, `fable`), a specific pinned model ID (e.g. `claude-opus-5`), or `inherit` (uses the parent conversation's active model). Resolution order when a subagent's model isn't explicitly forced is: (1) a per-invocation `model` parameter Claude passes when delegating, (2) the subagent file's own `model:` frontmatter, (3) the `CLAUDE_CODE_SUBAGENT_MODEL` env var, (4) the main conversation's model. As of Claude Code v2.1.257+, an admin/user can force **every** subagent onto one model globally regardless of per-file settings by setting both `CLAUDE_CODE_SUBAGENT_MODEL` and `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` in settings.
   **Source:** https://code.claude.com/docs/en/sub-agents (PRIMARY, "Model Configuration" / "Model Resolution Order" sections), fetched 2026-09-04.
   **Status:** Standard/consensus — this is documented product behavior, version-numbered, from the primary docs.

12. **Claim:** Subagents restrict tool access via `tools:` (allowlist, inherits everything if omitted) and `disallowedTools:` (blocklist applied before the allowlist resolves), and a fixed set of tools is stripped from every subagent regardless of configuration (`Agent` at depth limit, `AskUserQuestion`, `EndConversation`, `EnterPlanMode`, `ExitPlanMode`, `ScheduleWakeup`, `TaskOutput`, `WaitForMcpServers`, `Workflow`). Subagents can preload specific skills via a `skills:` frontmatter field (fully loaded into the subagent's context at launch, not lazily), and can nest up to five levels deep.
   **Source:** https://code.claude.com/docs/en/sub-agents (PRIMARY) and https://code.claude.com/docs/en/features-overview ("Subagents" tab under "Understand how features load"), fetched 2026-09-04.
   **Status:** Standard/consensus.

13. **Claim:** Subagent vs skill is not an either/or in practice — they compose. A subagent can preload skills via its `skills:` field; conversely a skill can be forced to run in an isolated forked-subagent context by setting `context: fork` in its own frontmatter (with `agent:` choosing which subagent type to fork into, and `background: true` by default so the invoking turn doesn't block on it). The deciding question the docs pose is: does the task need your full conversation history and back-and-forth (→ skill, runs inline), or would its intermediate work just be noise you'll never reference again (→ subagent, isolated, returns only a summary)?
   **Source:** https://code.claude.com/docs/en/skills (PRIMARY, "Run skills in a subagent" cross-reference + frontmatter table entries for `context`, `agent`, `background`) and https://code.claude.com/docs/en/features-overview ("Skill vs Subagent" tab), fetched 2026-09-04.
   **Status:** Standard/consensus.

14. **Claim:** Plugin marketplaces are a two-step distribution mechanism: (1) `/plugin marketplace add <source>` registers a catalog (GitHub `owner/repo`, any git URL, a local path, or a remote `marketplace.json` URL) without installing anything; (2) `/plugin install <plugin>@<marketplace>` installs an individual plugin from that catalog. A `marketplace.json` lists plugin entries that can each bundle `skills`, `commands`, `agents`, `hooks`, `mcpServers`, and `lspServers`, sourced via relative path, GitHub ref/SHA, generic git URL, git-subdir (sparse clone from a monorepo), npm package, zip archive (with sha256 verification), or an arbitrary shell `command` that emits a plugin path. Anthropic reserves a specific list of marketplace names (`claude-code-marketplace`, `claude-plugins-official`, `anthropic-marketplace`, `agent-skills`, `healthcare`, `life-sciences`, etc.) so third parties cannot squat or impersonate official namespaces.
   **Source:** https://code.claude.com/docs/en/plugin-marketplaces (PRIMARY), fetched 2026-09-04.
   **Status:** Standard/consensus — this is a documented product spec.

15. **Claim:** Anthropic runs three official-ish marketplaces, distinguished by trust level: **`claude-plugins-official`** (auto-added on first interactive launch, curated at Anthropic's sole discretion — public submission forms do *not* add to this one); **`claude-plugins-community`** (`anthropics/claude-plugins-community`, third-party plugins that "passed Anthropic's automated validation and safety screening," each pinned to a commit SHA, must be added manually); and a **demo marketplace** `claude-code-plugins` (`anthropics/claude-code`) with example plugins, also manual-add. The official marketplace's plugin catalog is organized into named categories: code intelligence (LSP plugins per language), external integrations (github, gitlab, atlassian, asana, linear, notion, figma, vercel, firebase, supabase, slack, sentry), `security-guidance` (automatic security review), development workflows (`commit-commands`, `pr-review-toolkit`, `agent-sdk-dev`, `plugin-dev`), and output styles.
   **Evidence:** "The official marketplace is curated by Anthropic, and inclusion is at Anthropic's discretion. The in-app submission forms add plugins to the community marketplace, not the official one."
   **Source:** https://code.claude.com/docs/en/discover-plugins (PRIMARY), fetched 2026-09-04.
   **Status:** Standard/consensus. Note: this primary source does **not** publish plugin *counts*. A secondary source (novita.ai blog, undated internally but referencing "as of 2026-08-10") separately claimed "284 plugins" official and "2,291 plugins" community — that specific figure is SECONDARY and unverified against a primary source in this research pass; treat it as a snapshot estimate, not confirmed current fact.

16. **Claim:** The `/plugin` install UI itself now surfaces a **"Context cost" estimate** per plugin ("how many tokens the plugin will add to your context window every turn") before you install it, alongside a "Last updated" date and a "Will install" component inventory — and Claude Code tracks plugin usage, surfacing plugins "installed yourself but haven't used in at least two weeks, over a span of at least 10 sessions" under a **"Not used recently"** header so you can prune dead weight.
   **Source:** https://code.claude.com/docs/en/discover-plugins (PRIMARY), fetched 2026-09-04.
   **Status:** Standard/consensus — this is a shipped, documented product feature aimed directly at the "context cost of installed extensions" problem this research asked about.

17. **Claim (skill sprawl / mis-triggering — practitioner-level, not Anthropic-published):** A 15-day, 3-audit personal case study found skill count growing from 16 to 48 (with a "learned skills" subcategory alone reaching 40), producing cross-project contamination — opening an unrelated Swift project surfaced irrelevant Python/LLM-pipeline skills in the discovery list, wasting the finite character budget described in finding #6. The author's concrete recommendations: audit whenever any single scope (personal/project/plugin layer) exceeds **10 skills**; sort skills by "is this used in only one project?" — if yes, demote it to that project's `.claude/skills/`, not the global personal scope; use `disable-model-invocation: true` to hide skills you invoke manually but don't want cluttering auto-discovery; merge near-duplicate skills into a parent skill rather than letting them proliferate; retire one-off patterns that are really just a shell one-liner rather than a skill.
   **Evidence:** "The core insight: 'The number of skills has no value. Value comes from having the right skills, at the right granularity, in the right place.'"
   **Source:** https://dev.to/shimo4228/15-days-of-skill-sprawl-in-claude-code-lessons-from-3-audits-27em (2026) — SECONDARY, single practitioner's personal audit log, not a controlled study or Anthropic guidance.
   **Status:** One practitioner's opinion / anecdote, presented as a pattern others report similarly (multiple search results independently echoed "too many skills → overlap → mis-triggering" as a known failure mode), but the specific numbers (16→48, "10 skills" threshold) are this one author's own case, not a benchmarked standard.

18. **Claim (skill description overlap anti-pattern):** "If two skills could plausibly fire on the same prompt, one or both should be made explicit [to disambiguate]... If you're using 'and' in the description more than once, split the skill" — i.e., a description packing multiple unrelated triggers together ("does X and Y and Z") is a sign the skill itself is doing too much and should be split into narrower skills with narrower, non-overlapping descriptions.
   **Source:** Aggregated from multiple secondary blog posts surfaced by search (MindStudio, buildtolaunch.substack.com, dev.to sprawl post), 2026 — SECONDARY, repeated consistently enough across independent authors to count as practitioner consensus, but not an Anthropic-published rule.
   **Status:** One practitioner's opinion, echoed by multiple independent sources — closer to informal consensus among Claude Code power users than to official guidance, since it wasn't found stated this way in Anthropic's own docs (which instead just say "be specific and include key terms" — finding #4).

19. **Claim (hooks vs prose — the canonical "duplicated pipeline"/anti-pattern framing):** Multiple independent secondary sources converge on the same framing Anthropic's primary docs also state (see #8, #9): writing "always run the formatter before finishing" or "MUST"/"ALWAYS"/"CRITICAL" in CLAUDE.md produces advisory behavior that degrades after compaction or under pressure, while the identical instruction as a `PostToolUse` hook fires deterministically forever. One secondary source frames this pointedly: "Stronger wording like 'MUST', 'ALWAYS', 'CRITICAL', bold, and uppercase don't change the underlying behavior — the model reads your instruction, considers it, and then makes its own judgment call."
   **Source:** Aggregated secondary blog commentary (jack.direct, blakecrosley.com, hidekazu-konishi.com), 2026 — SECONDARY, but directly corroborated by Anthropic's own primary statement in finding #9 ("A real guardrail needs to be deterministic, and the enforcement methods are hooks and permissions").
   **Status:** Standard/consensus — secondary chatter here simply restates what Anthropic's own primary docs already say more precisely.

20. **Claim (evaluation-first skill authoring — Anthropic's own methodology):** Anthropic's official recommendation is to **build evaluations before writing extensive documentation**: (1) run Claude on representative tasks *without* a skill and document specific failures/gaps, (2) build ~3 test scenarios that exercise those gaps, (3) measure a no-skill baseline, (4) write only the minimal instructions needed to pass the evaluations, (5) iterate. The doc explicitly frames this as preventing "solving actual problems rather than anticipating requirements that may never materialize," and separately recommends an iterative "Claude A / Claude B" loop — one Claude instance helps author the skill, a fresh Claude instance tests it on real tasks, observations feed back into revision — plus testing every skill against Haiku, Sonnet, *and* Opus since a skill tuned for one model's level of hand-holding may over- or under-explain for another.
   **Source:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices ("Build evaluations first," "Develop Skills iteratively with Claude," "Test with all models you plan to use" sections), PRIMARY, fetched 2026-09-04.
   **Status:** Standard/consensus — this is Anthropic's stated methodology, distinct from (and more rigorous than) most third-party "just write a good description" advice.

21. **Claim (degrees of freedom — matching specificity to task fragility):** Anthropic's docs give a three-tier framework for how prescriptive a skill's instructions should be: **high freedom** (plain text/heuristics) when multiple valid approaches exist and judgment should apply (e.g. a code-review process); **medium freedom** (parameterized pseudocode/scripts) when a preferred pattern exists but some variation is fine; **low freedom** (an exact script to run, explicitly told "do not modify the command or add additional flags") when operations are fragile, error-prone, or must follow one exact sequence (e.g. database migrations). The analogy given: a narrow bridge over a cliff needs exact guardrails; an open field needs only general direction.
   **Source:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices ("Set appropriate degrees of freedom"), PRIMARY, fetched 2026-09-04.
   **Status:** Standard/consensus — original Anthropic framing, not seen phrased this way in any secondary source, suggesting it's under-propagated advice worth highlighting.

22. **Claim (plugin.json vs marketplace.json authority — `strict` mode):** When a marketplace entry sets `"strict": true` (the default), the plugin's own `plugin.json` is the authority and the marketplace entry can only supplement it; when `"strict": false`, the marketplace entry is treated as the *complete* definition and any conflicting field in the plugin's own `plugin.json` causes a hard error. Marketplace maintainers can also run parallel **release channels** (e.g. a `stable-tools` marketplace pinned to a `stable` git ref vs. a `latest-tools` marketplace tracking `latest`) so different teams can be gated onto different plugin freshness levels.
   **Source:** https://code.claude.com/docs/en/plugin-marketplaces (PRIMARY), fetched 2026-09-04.
   **Status:** Standard/consensus — documented product behavior.

## Concrete practices / configs (copy-pasteable this week)

**Minimal, well-triggered skill** (reference-style, auto-invoked):
```yaml
---
name: api-conventions
description: REST API design conventions for our services. Use when writing or reviewing API endpoints, request/response schemas, or error formats.
---

## API conventions
- Use kebab-case for URL paths
- Use camelCase for JSON properties
- Always include pagination for list endpoints
- Version APIs in the URL path (/v1/, /v2/)
```
(Third person, key terms up front, trigger context stated explicitly — per finding #4.)

**Action skill with side effects, user-only trigger** (never auto-invoked):
```yaml
---
name: deploy
description: Deploy the application to production
disable-model-invocation: true
---
Deploy $ARGUMENTS to production:
1. Run the test suite
2. Build the application
3. Push to the deployment target
4. Verify the deployment succeeded
```
`disable-model-invocation: true` is the correct fix whenever a skill has side effects you don't want Claude deciding to trigger on its own — per finding #16/features-overview.

**Progressive disclosure layout** (once a skill nears 500 lines):
```
my-skill/
├── SKILL.md          # overview + links, stays under 500 lines
├── reference.md       # linked directly from SKILL.md (one level deep only)
├── examples.md
└── scripts/
    └── helper.py       # executed via bash, never loaded into context
```
Reference every file from `SKILL.md` itself — never chain `SKILL.md → advanced.md → details.md` (finding #3).

**Subagent pinned to a cheap model for high-volume mechanical work**:
```yaml
---
name: test-runner
description: Run tests and report only failures
tools: Read, Bash, Grep
model: haiku
---
```
Or force this org-wide via `.claude/settings.json`:
```json
{ "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "haiku", "CLAUDE_CODE_SUBAGENT_MODEL_FORCE": "1" } }
```
(finding #11 — requires Claude Code v2.1.257+ for the force flag.)

**Hook instead of a CLAUDE.md "MUST" rule** — the canonical fix for finding #9/#19. Instead of:
```markdown
<!-- CLAUDE.md — WRONG: advisory, degrades after compaction -->
IMPORTANT: Always run eslint after every file edit.
```
do:
```json
// .claude/settings.json — RIGHT: deterministic, survives compaction
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "npx eslint --fix \"$CLAUDE_FILE_PATH\"" }] }
    ]
  }
}
```
Claude Code can even author this hook for you on request ("Write a hook that runs eslint after every file edit" — per `code.claude.com/docs/en/best-practices`).

**Plugin marketplace registration** (team distribution, finding #14):
```bash
/plugin marketplace add your-org/claude-plugins
/plugin install your-tool@your-org
```
And a minimal `marketplace.json`:
```json
{
  "name": "your-org-tools",
  "owner": { "name": "Platform Team" },
  "plugins": [
    { "name": "your-tool", "source": "./plugins/your-tool", "description": "…" }
  ]
}
```

**Skill audit heuristic to apply now** (finding #17): if any of `~/.claude/skills/`, a project's `.claude/skills/`, or a single plugin exceeds ~10 skills, or if a skill's description contains "and" more than once (finding #18), that's the trigger to split, demote to project scope, or set `disable-model-invocation: true` on rarely-auto-needed ones. Run `/context` in Claude Code to see current skill-index token/character usage directly, and check the `/plugin` "Not used recently" list (finding #16) to prune dead plugins.

## Disagreements and open questions

- **Exact skill-index token/character cost is not officially published.** Anthropic's docs describe the mechanism (metadata pre-loads, body doesn't) but do not publish a hard number for the metadata budget. The best available number (~15,500–16,000 characters, ~42 skills at typical description length) comes from one independent researcher's empirical reverse-engineering (finding #6), cross-referenced against one GitHub issue — it is plausible and internally consistent, but not Anthropic-confirmed, could change without notice, and other secondary sources give conflicting per-skill token estimates (30–235 tokens, "~100 tokens," "median 80 tokens") that use a different unit (tokens vs. characters) and different methodology, so they don't reconcile cleanly with the character-budget finding.
- **CLAUDE.md description-token limits are inconsistent across contexts**: the cross-tool Agent Skills spec (claude.ai uploads / Skills API) caps `description` at 1,024 characters; Claude Code's own in-app listing truncates the combined `description`+`when_to_use` at 1,536 characters. Neither figure is "the" official skill-description limit — it depends which distribution path you're targeting.
- **Plugin marketplace size numbers (284 official / 2,291 community) could not be confirmed from a primary Anthropic source** in this research pass — Anthropic's own `discover-plugins` doc lists categories but no counts. Treat that secondary figure as a point-in-time snapshot from a third-party blog, not verified current fact.
- **"10 skills per scope" as an audit threshold, and "split the skill if the description has 'and' twice"** are both practitioner heuristics repeated across independent secondary sources but never stated by Anthropic itself — they read as informal community consensus rather than documented guidance, and could be a specific-to-Sonnet-generation or specific-to-one-user's-usage-pattern rule of thumb rather than a general law.
- **Gerund-form skill naming** is Anthropic's stated preference but explicitly called "acceptable alternative" for noun/verb forms too — this is closer to a style nudge than a hard rule, unlike the `name` field's actual hard constraints (64 chars, lowercase/hyphens, no reserved words).
- Could not fetch the full text of "A Claude Code skill was eating 200,000 tokens before answering a single question" (thenewstack.io, Aug 18 2026) — the fetch returned only the headline/byline, not article body, likely paywalled or JS-rendered. This looked like it would have been a good concrete cautionary example but the underlying cause/numbers could not be verified and are therefore **omitted** from Findings rather than guessed at.

## Sources

**Primary (Anthropic-authored, fetched and read in full):**
1. Anthropic engineering blog — "Equipping agents for the real world with Agent Skills" — https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
2. Claude Platform Docs — "Skill authoring best practices" — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
3. Claude Code Docs — "Extend Claude with skills" — https://code.claude.com/docs/en/skills
4. Claude Code Docs — "Create custom subagents" — https://code.claude.com/docs/en/sub-agents
5. Claude Code Docs — "Automate actions with hooks" (fetched as "Hooks") — https://code.claude.com/docs/en/hooks
6. Claude Code Docs — "Create and distribute a plugin marketplace" — https://code.claude.com/docs/en/plugin-marketplaces
7. Claude Code Docs — "Best practices for Claude Code" — https://code.claude.com/docs/en/best-practices
8. Claude Code Docs — "Extend Claude Code" (the canonical decision matrix: "Match features to your goal" / "Compare similar features") — https://code.claude.com/docs/en/features-overview
9. Claude Code Docs — "Discover and install prebuilt plugins through marketplaces" — https://code.claude.com/docs/en/discover-plugins
10. Claude.com blog — "Steering Claude Code: when to use CLAUDE.md, skills, hooks, rules, subagents, and more" — https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more

**Secondary (practitioner/independent, fetched and read in full):**
11. Nick Liu — "Hooks are guarantees, skills are knowledge, subagents are other people" — https://nick-liu.com/posts/claude-code-skills-hooks-subagents/
12. dev.to (shimo4228) — "15 Days of Skill Sprawl in Claude Code — Lessons from 3 Audits" — https://dev.to/shimo4228/15-days-of-skill-sprawl-in-claude-code-lessons-from-3-audits-27em
13. GitHub Gist (alexey-pelykh) — "claude-code-skill-budget-research.md" — https://gist.github.com/alexey-pelykh/faa3c304f731d6a962efc5fa2a43abe1

**Attempted but not usable (snippet/headline only, content not retrievable):**
14. The New Stack — "A Claude Code skill was eating 200,000 tokens before answering a single question" — https://thenewstack.io/claude-code-token-reduction/ (fetch returned no article body)

**Search-only (snippets referenced for corroboration, not independently fetched/verified in full — used only where explicitly marked SECONDARY/unverified above):**
15. Novita.ai — "Claude Marketplace: How Claude Code Plugin Marketplaces Work" — https://blogs.novita.ai/claude-marketplace/ (source of the unverified 284/2,291 plugin-count figures)
16. Various secondary blogs aggregated via search for hooks-anti-pattern and skill-overlap consensus framing (jack.direct, blakecrosley.com, hidekazu-konishi.com, MindStudio, buildtolaunch.substack.com) — not individually fetched in full; used only to corroborate patterns independently confirmed by primary sources #6–#10 above.

## Source check (independent)

Independent verification pass, 2026-09-04. The 6 most load-bearing claims (the ones a recommendation would rest on — numeric ceilings, exact quotes, and version-pinned product behavior) were re-fetched directly from their cited sources and checked word-for-word. Method: WebFetch each cited URL, compare the report's quoted/paraphrased text against the actual page content.

**1. Finding #6 — Skill-index character budget (~15,500–16,000 chars, ~42 of 63 skills shown, 21 hidden, avg 263-char description, cross-referenced against GitHub issue #12782)**
**Source checked:** https://gist.github.com/alexey-pelykh/faa3c304f731d6a962efc5fa2a43abe1
**Verdict: CONFIRMED** (minor number discrepancy noted below)
Exact quotes from the gist: "Empirical budget: ~15,500-16,000 characters"; "When using Claude Code with 63 installed skills, the system prompt showed: <!-- Showing 42 of 63 skills due to token limits --> 21 skills (33%) were completely hidden"; the gist lists GitHub issue #12782 in its related-issues table as an independent cross-check ("Budget calculation independently verified by #12782"). One small precision slip: the gist's own measured average is "Showed skills: 42, Total Chars: 11,071, Avg Length: 264 chars" — the report says "263-character description," off by one character (11,071 ÷ 42 = 263.6, so 264 is the correct round). Trivial, does not affect the substance of the claim.

**2. TL;DR bullet 4 / lead-in to Finding #9 — the quoted sentence "An instruction is a request; a hook is a guarantee."**
**Sources checked:** https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more and https://code.claude.com/docs/en/features-overview (the report's own two citations for this line)
**Verdict: PARTIAL — presented as a verbatim quote in quotation marks, but this exact sentence does not appear in either cited source.** The real quotes are: from the blog, "When there's something that absolutely must not happen, an instruction is the wrong tool... A real guardrail needs to be deterministic, and the enforcement methods are hooks and permissions." From `features-overview`'s "Hook vs Skill" comparison tab (not actually one of the two sources cited for this bullet — the report cites `code.claude.com/docs/en/best-practices` instead, a different page): "An instruction like 'never edit .env' in CLAUDE.md or a skill is a request, not a guarantee. A PreToolUse hook that blocks the edit is enforcement." The *substance* of the claim is well-supported by both primary sources (and is stated correctly elsewhere in the report's own Finding #9, which quotes the blog accurately). But the specific sentence "An instruction is a request; a hook is a guarantee," rendered as a direct quotation, appears to be the report's own compression/paraphrase of the real quote rather than something either source actually says — and it cites the wrong second URL besides. Flagged inline in the file.

**3. Finding #10 — "Keep CLAUDE.md under 200 lines"**
**Source checked:** https://code.claude.com/docs/en/features-overview
**Verdict: CONFIRMED.** Exact text, "CLAUDE.md vs Skill" tab: "**Rule of thumb:** Keep CLAUDE.md under 200 lines. If it's growing, move reference content to skills or split into `.claude/rules/` files." Also independently repeated in the "CLAUDE.md" loading tab: "Keep CLAUDE.md under 200 lines. Move reference material to skills, which load on demand."

**4. Finding #11 — Subagent `model:` frontmatter (aliases incl. `fable`, full model ID, or `inherit`), 4-step resolution order, and `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` requiring Claude Code v2.1.257+**
**Source checked:** https://code.claude.com/docs/en/sub-agents
**Verdict: CONFIRMED.** Exact text: "Model alias: use one of the available aliases: `sonnet`, `opus`, `haiku`, or `fable`... Full model ID... inherit: use the same model as the main conversation." Resolution order matches exactly: (1) per-invocation `model` parameter, (2) subagent frontmatter (`inherit` → main conversation's model), (3) `CLAUDE_CODE_SUBAGENT_MODEL` env var, (4) main conversation's model. And: "This variable requires **Claude Code v2.1.257 or later**" for `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, matching the report's "v2.1.257+" precisely. (Bonus finding not in the report: the doc notes this resolution order itself changed in v2.1.251 — before that, `CLAUDE_CODE_SUBAGENT_MODEL` used to override everything including frontmatter `inherit`. Not a contradiction of the report, just an extra version nuance it didn't mention.)

**5. Finding #3 — SKILL.md under 500 lines; references kept one level deep from SKILL.md; table of contents required on reference files over 100 lines**
**Source checked:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
**Verdict: CONFIRMED**, word for word. "Keep SKILL.md body under 500 lines for optimal performance. Split content into separate files when approaching this limit." / "Claude may partially read files when they're referenced from other referenced files... Keep references one level deep from SKILL.md." / "For reference files longer than 100 lines, include a table of contents at the top." All three sub-claims confirmed exactly as stated in the report, including the "Bad example: Too deep" / "Good example: One level deep" illustration the report paraphrases correctly.

**6. Finding #17 — dev.to practitioner audit (16→48 skills in 15 days, Swift/pdf2anki cross-project contamination example, "audit once any scope passes ~10 skills," "number of skills has no value" quote)**
**Source checked:** https://dev.to/shimo4228/15-days-of-skill-sprawl-in-claude-code-lessons-from-3-audits-27em
**Verdict: CONFIRMED.** "Over 15 days with ECC, my skills grew from 16 to 48. Learned skills alone... reached 40." / "Every time I opened a Swift project, pdf2anki's LLM pipeline skills appeared in Discovery. In Python projects, Swift Actor patterns showed up." / "audit when any single layer exceeds 10 skills." / "The 'number' of skills has no value. Value comes from having the right skills, at the right granularity, in the right place." All match the report's paraphrase and direct quote precisely.

### Summary
5 of 6 checked claims are fully CONFIRMED verbatim against their cited primary/secondary sources — this report's sourcing discipline is unusually strong for a synthesized research doc; every checked number, version string, and paraphrase held up. The one PARTIAL is a quotation-fidelity issue, not a substance issue: TL;DR bullet 4 puts quotation marks around a sentence — "An instruction is a request; a hook is a guarantee" — that reads as a natural compression of what Anthropic's docs actually say, but is not a verbatim quote from either of the two sources cited for it (and one of those two citations, `code.claude.com/docs/en/best-practices`, isn't even the page that contains the closest real wording — that's on `features-overview` instead). The underlying claim (hooks are deterministic, instructions are advisory, per Anthropic's own stated framing) is independently confirmed as true and well-sourced elsewhere in the same report (Finding #9's blog quote, and the `features-overview` "Hook vs Skill" tab). Net effect: a downstream reader who copies that TL;DR bullet as a citable Anthropic quote would be misquoting the source, but a reader who takes it as the report's own accurate summary of Anthropic's position would not be misled. No claims in this 6-claim sample were UNSUPPORTED or MISATTRIBUTED.
