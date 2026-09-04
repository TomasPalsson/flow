# Slash Commands vs Skills in Claude Code (2026)

## TL;DR

- As of 2026, **custom commands have been merged into skills**: `.claude/commands/deploy.md` and `.claude/skills/deploy/SKILL.md` both create `/deploy` and behave the same way; old `.claude/commands/` files still work but skills are the recommended path going forward (PRIMARY, code.claude.com/docs/en/skills, undated but current as of fetch 2026-09-04).
- `/name` resolution has a strict precedence order when names collide: enterprise > personal > project skills; a skill beats a bundled skill of the same name (but not its alias); a skill beats a `.claude/commands/` file of the same name; plugin skills are namespaced `plugin:skill` so they never collide; any local skill/command beats a claude.ai-synced skill of the same name (PRIMARY).
- The full SKILL.md frontmatter schema is large: `name`, `description`, `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `disallowed-tools`, `model`, `effort`, `context`, `agent`, `background`, `hooks`, `paths`, `shell`, `metadata`, `license`, `compatibility` — only `description` is recommended, all fields optional (PRIMARY).
- Two frontmatter switches govern the command-vs-autonomous-skill split: `disable-model-invocation: true` (only a human can trigger it — use for side-effecting actions like `/commit`, `/deploy`) and `user-invocable: false` (only Claude can trigger it — background knowledge, hidden from the `/` menu) (PRIMARY).
- Many "built-in" commands practitioners think of as hardcoded are actually **bundled skills** (prompt-based, e.g. `/doctor`, `/code-review`, `/batch`, `/loop`, `/schedule`, `/simplify`, `/security-review`, `/fewer-permission-prompts`, `/verify`, `/debug`), distinct from true built-ins with fixed logic (`/clear`, `/compact`, `/context`, `/permissions`, `/memory`, `/hooks`, `/resume`, `/rewind`, `/fork`) (PRIMARY).
- `/loop` (session-scoped, requires the session to stay open, min 1-minute interval) and `/schedule` (background cloud/CLI-created routine that doesn't need the session open, requires claude.ai subscription login) are distinct scheduling mechanisms — `/schedule` is a thin CLI entry point into cloud "Routines," not a local-only feature (PRIMARY).
- Practitioner/secondary sources broadly agree the killer custom commands that survive long-term are commit and PR/review workflows; hard adoption numbers for standup/retro/worklog/handoff are not documented anywhere primary — this is an evidence gap (SECONDARY, low confidence).
- One secondary source (jsmanifest.com) describes SKILL.md fields (`trigger_keywords`, `category`) that do **not** appear anywhere in the official frontmatter table — treat that article's technical claims as unreliable/likely fabricated (CONTESTED).

## Findings

1. **Custom commands have been merged into skills; both produce `/name` identically.** A file at `.claude/commands/deploy.md` and a skill at `.claude/skills/deploy/SKILL.md` both create `/deploy` and "work the same way." Existing `.claude/commands/` files keep working; skills add optional features (supporting-file directory, invocation-control frontmatter, automatic Claude-triggered loading).
   Evidence: direct quote from docs. URL: https://code.claude.com/docs/en/skills (also reachable via the now-aliased `/docs/en/slash-commands` URL, which redirects to the same content). Date: fetched 2026-09-04, page undated. PRIMARY. Consensus (matches multiple secondary sources too).

2. **Files in `.claude/commands/` support the same frontmatter as SKILL.md, except `name` and `paths`**, which Claude Code ignores in a command file; the command name always comes from the file name. Skills are recommended over command files because they support extra features like supporting files.
   URL: https://code.claude.com/docs/en/skills (section "Discovery from parent and nested directories"). PRIMARY.

3. **`$ARGUMENTS` and richer substitution syntax.** `$ARGUMENTS` = all arguments as typed; `$ARGUMENTS[N]` / `$N` = 0-based positional access; `$name` = named argument declared via the `arguments` frontmatter field (maps by position); plus system variables `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`. If a skill takes arguments but no placeholder consumes them, Claude Code appends `ARGUMENTS: <value>` to the end automatically. Argument values are shell-quoted (`"hello world"` → single `$0`). A literal `$1` etc. can be escaped with a single backslash (`\$1.00`).
   URL: https://code.claude.com/docs/en/skills (§ "Available string substitutions", § "Pass arguments to skills"). PRIMARY.

4. **`argument-hint` frontmatter field**: "Hint shown during autocomplete to indicate expected arguments," e.g. `[issue-number]` or `[filename] [format]`. Optional.
   URL: https://code.claude.com/docs/en/skills (frontmatter reference table). PRIMARY.

5. **`allowed-tools` and `disallowed-tools` frontmatter**: `allowed-tools` pre-approves tools "without asking permission during the turn that invokes this skill" — the grant clears on your next message (not session-persistent); accepts space/comma-separated string or YAML list; supports `Bash(cmd *)` glob patterns and `${CLAUDE_SKILL_DIR}`/`${CLAUDE_PROJECT_DIR}` substitution inside the pattern so a bundled script can run without a prompt. `disallowed-tools` removes tools from Claude's pool while the skill is active (e.g. blocking `AskUserQuestion` in an autonomous loop); can't remove `EndConversation` while any other tool remains. Neither field restricts general availability — permission settings still govern everything not listed.
   URL: https://code.claude.com/docs/en/skills (§ "Pre-approve tools for a skill", frontmatter table). PRIMARY.

6. **`model` frontmatter field**: sets the model while the skill is active, for the rest of that turn only (not saved to settings — resumes the session model on the next prompt). Accepts the same values as `/model`, or `inherit`. With `context: fork` it instead sets the forked subagent's model. A value outside the org's `availableModels` allowlist is ignored and the session keeps its current model.
   URL: https://code.claude.com/docs/en/skills (frontmatter table). PRIMARY.

7. **Namespacing rules, in full:**
   - Skill locations: Enterprise (`/etc/claude-code/.claude/skills/...` style managed settings) > Personal (`~/.claude/skills/<name>/SKILL.md`) > Project (`.claude/skills/<name>/SKILL.md`) — enterprise overrides personal, personal overrides project.
   - A skill at any of these levels overrides a bundled skill of the same name, but never a bundled skill's *alias* (e.g. a project `code-review` skill replaces `/code-review` but typing alias `/review` still runs the bundled one).
   - Plugin skills are namespaced `plugin-name:skill-name` (e.g. `/my-plugin:deploy`) so they never collide with other levels.
   - Nested `.claude/skills/` in a subdirectory: if the name clashes with a root skill, the nested one is addressed as `/apps/web:deploy` (directory-qualified); both stay available; invoking the unqualified name still auto-appends an instruction for Claude to also consider directory-qualified variants relevant to files it's touching.
   - A skill or `.claude/commands/` file always overrides a same-named skill synced from a claude.ai account.
   - Name comparison ignores case, spacing, invisible characters, and normalizes look-alike Unicode compatibility forms (fullwidth letters, dash variants) — but a genuinely different-alphabet look-alike letter counts as a different name.
   URL: https://code.claude.com/docs/en/skills (§ "Where skills live", § "When a synced skill name matches another command"). PRIMARY.

8. **How a skill gets its command name (full table):** directory name for personal/project skills (frontmatter `name` only sets the *display* label, not the command, at those levels); nested nameclash → directory-qualified path; `.claude/commands/` file → file name minus extension; plugin `skills/<x>/SKILL.md` → frontmatter `name` (or dir name fallback), namespaced by plugin; plugin root `SKILL.md` → frontmatter `name` is the whole final segment, plugin dir name is the fallback. If a plugin skill's `name` already starts with the plugin's own prefix, Claude Code (v2.1.246+) doesn't double it — versions v2.1.216–v2.1.245 had a doubling bug.
   URL: https://code.claude.com/docs/en/skills (§ "How a skill gets its command name"). PRIMARY.

9. **`disable-model-invocation: true` vs `user-invocable: false`** — the two levers for command-vs-skill control:
   | Frontmatter | You can invoke | Claude can invoke | Description always in context? |
   |---|---|---|---|
   | (default) | Yes | Yes | Yes, full content loads when invoked |
   | `disable-model-invocation: true` | Yes | No | No — description isn't loaded, so Claude can't even choose to run it |
   | `user-invocable: false` | No | Yes | Yes |
   Recommended use: `disable-model-invocation: true` for anything with side effects you want to control the timing of — the docs explicitly cite `/commit`, `/deploy`, `/send-slack-message` as examples ("You don't want Claude deciding to deploy because your code looks ready"). `user-invocable: false` is for background knowledge that isn't a meaningful user action (e.g. a `legacy-system-context` skill).
   URL: https://code.claude.com/docs/en/skills (§ "Control who invokes a skill"). PRIMARY. Consensus — matches secondary sources' general guidance too.

10. **Skill content persists in context once loaded**, across later turns, until compaction. Re-invoking a skill whose rendered content is unchanged just adds a short "already loaded" note rather than duplicating it. Auto-compaction re-attaches the most recent invocation of each skill after a summary, keeping the first 5,000 tokens of each, sharing a combined 25,000-token budget across all re-attached skills (oldest dropped first if budget is exceeded). `allowed-tools` grants do NOT persist this way — they clear every turn.
    URL: https://code.claude.com/docs/en/skills (§ "Skill content lifecycle"). PRIMARY. This is a concrete, load-bearing mechanic for anyone reasoning about skill token cost.

11. **Bundled skills vs true built-in commands.** Claude Code ships "bundled skills" — prompt-based, giving Claude instructions it orchestrates via tools — including `/doctor`, `/code-review`, `/batch`, `/debug`, `/loop`, `/schedule`, `/security-review`, `/simplify`, `/fewer-permission-prompts`, `/verify`, `/claude-api`, `/dataviz`, `/design`, `/design-sync`. "Most built-in commands instead execute fixed logic directly" — e.g. `/clear`, `/compact`, `/context`, `/permissions`, `/memory`, `/hooks`, `/resume`, `/rewind`, `/fork`, `/model`, `/cost`(`/usage`), `/stats`. `disableBundledSkills` setting turns off every bundled skill except `/doctor` (which stays typable as of v2.1.205+; before that version `/doctor` was a true built-in, not a bundled skill).
    URL: https://code.claude.com/docs/en/skills (§ "Bundled skills"); https://code.claude.com/docs/en/commands (full table). PRIMARY.

12. **`/compact [instructions]`** — built-in, fixed logic. Frees context by summarizing the conversation; optional focus instructions for the summary; preserves rules/skills/memory per documented compaction survival rules (linked separately at `/docs/en/context-window#what-survives-compaction`, not independently fetched here).
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

13. **`/rewind [N|description]`** — alias `/undo`. Rolls back code AND conversation to a checkpoint, or can summarize part of the conversation without rolling back. Pass a number to rewind N turns or a description to search checkpoints by name; no argument opens an interactive checkpoint menu. Requires Claude Code v2.1.169+. Note: a forked skill that ran in the background applies its edits **outside** the session's checkpoints, so `/rewind` cannot undo those — only `git` can.
    URL: https://code.claude.com/docs/en/commands; https://code.claude.com/docs/en/skills (§ "Run skills in a subagent"). PRIMARY.

14. **`/goal [condition|clear]`** — built-in. Sets a goal; "Claude keeps working across turns until the condition is met or the goal clears for another reason." No argument shows current/most recent goal. `clear`/`stop`/`off`/`reset`/`none`/`cancel` removes it early. This differs from `/loop`, which is interval-based rather than condition-based.
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

15. **`/loop [interval] [prompt]`** — bundled skill, alias `/proactive`. Session-scoped: runs only while the session stays open (min 1-minute granularity, cron under the hood, rounded to nearest clean cron step). Three modes depending on what you supply: (a) interval+prompt → fixed cron schedule; (b) prompt only → Claude self-paces the interval (1 min–1 hr) based on what it observes, printing its chosen delay and reasoning each iteration; (c) neither → runs the built-in maintenance prompt (continue unfinished work → tend to the current branch's PR → run cleanup passes) or a project/user `loop.md` override if present. Can chain a skill as the prompt, e.g. `/loop 20m /review-pr 1234`. Stopped with `Esc` (self-paced only) or by canceling the scheduled task; auto-expires after 7 days; a session can hold up to 50 scheduled tasks. `loop.md` search order: `.claude/loop.md` (project, wins) then `~/.claude/loop.md` (user); truncated beyond 25,000 bytes.
    URL: https://code.claude.com/docs/en/scheduled-tasks. PRIMARY.

16. **`/schedule <interval> <prompt>`** — bundled skill, alias `/routines`. Unlike `/loop`, `/schedule` "creates a background task" — actually a CLI entry point into cloud **Routines**, run on Anthropic-managed cloud infra (or self-hosted), independent of the local session staying open. Requires a claude.ai subscription login (Console API keys / cloud-provider auth / Anthropic profiles don't support it — returns "Unknown command" or an explicit enterprise-migration message). Minimum recurring interval is 1 hour (vs. `/loop`'s 1 minute). Supports one-off natural-language scheduling (`/schedule tomorrow at 9am, summarize yesterday's merged PRs`), and management subcommands `/schedule list`, `/schedule update`, `/schedule run`. Routines can also trigger on GitHub events or via an authenticated HTTP POST to a per-routine `/fire` endpoint (ships under an experimental beta header). Routines run with **no permission-mode picker and no approval prompts** — fully autonomous.
    URL: https://code.claude.com/docs/en/routines; https://code.claude.com/docs/en/scheduled-tasks (comparison table). PRIMARY.

17. **`/batch <instruction>`** — bundled skill. Orchestrates large-scale changes across a codebase in parallel: researches the codebase, decomposes work into 5–30 independent units, presents a plan; once approved, spawns one background subagent per unit in an isolated git worktree, each implementing its unit, running tests, and opening a PR. Requires a git repo. Example given: `/batch migrate src/ from JavaScript to TypeScript`.
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

18. **`/code-review`, `/simplify`, `/security-review`** — all bundled skills sharing effort levels `low|medium|high|xhigh|max|ultra` and a common `[--fix] [--comment] [pr#|branch|path]` shape. `/code-review` alias `/review`; runs as a **forked subagent** since v2.1.218 (was inline before). `--comment` posts inline GitHub PR comments; `ultra` runs a deep cloud review (ultrareview), and on a github.com PR target `--post` preselects posting findings to the PR. `/simplify` reviews for simplification opportunities specifically (not bug-hunting — the report's job spec for /simplify explicitly says "Quality only — it does not hunt for bugs; use /code-review for that", matching skill-listing metadata seen in this session). `/security-review` checks for vulnerabilities.
    URL: https://code.claude.com/docs/en/commands. PRIMARY. (The /simplify quality-only distinction is corroborated by this session's own skill listing metadata — SECONDARY but internally consistent.)

19. **`/fewer-permission-prompts`** — bundled skill. "Scan your transcripts for common read-only Bash and MCP tool calls, then add a prioritized allowlist to project `.claude/settings.json` to reduce permission prompts." No arguments.
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

20. **`/doctor`** — bundled skill (was a true built-in before v2.1.205). Runs a setup checkup: installation health (duplicate/leftover installs, PATH issues, unparseable settings), finds unused skills/MCP/plugins vs. their context cost, flags slow hooks, checks version currency, deduplicates local vs. checked-in CLAUDE.md, **trims checked-in CLAUDE.md by cutting derivable content and migrates always-loaded guidance into skills/nested CLAUDE.md** (v2.1.206+), offers to set auto mode as default and pre-approve frequently-denied read-only commands. Reports findings and asks confirmation before changing anything. `claude doctor` (terminal, not slash) prints read-only diagnostics without starting a session. Alias `/checkup`. Stays typable even when `disableBundledSkills` is on; hide it via `DISABLE_DOCTOR_COMMAND` env var or `skillOverrides: {"doctor": "off"}`.
    URL: https://code.claude.com/docs/en/commands; https://code.claude.com/docs/en/skills. PRIMARY.

21. **`/context [all]`** — built-in. Visualizes current context usage as a colored grid; shows optimization suggestions for context-heavy tools, memory bloat, capacity warnings; when over the limit, shows how far over and which command frees space; `all` expands the per-item breakdown (collapsed by default in fullscreen mode).
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

22. **`/cost` / `/usage`** — `/cost` is a pure alias for `/usage`, which shows token usage for the current session **and account plan, including cost**.
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

23. **`/stats`** — built-in. "Show statistics about the current session, including token usage by model, reasoning tokens if applicable, and tool calls by category." Distinct from `/usage`/`/cost` (which is about $ and plan-level consumption) and `/status` (current model, effort level, working directory, session state).
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

24. **`/skills`** — built-in menu. "View and manage skills: browse the bundled library, install community skills, create your own, or edit and delete existing ones. Also shows which skills are loaded in the current session." This is also where synced-from-claude.ai skills are labeled under a `claude.ai sync` group, and where `skillOverrides` states can be toggled per-skill (highlight + Space to cycle `on`/`name-only`/`user-invocable-only`/`off`, Esc to save to `.claude/settings.local.json`).
    URL: https://code.claude.com/docs/en/commands; https://code.claude.com/docs/en/skills (§ "Override skill visibility from settings"). PRIMARY.

25. **`/hooks`** — built-in. "View hook configurations for tool events." (Read-only viewer per the docs; configuration itself happens in settings files / `hooks` frontmatter field on skills.)
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

26. **`/permissions`** — built-in, alias `/allowed-tools`. Interactive dialog: view allow/ask/deny rules by scope, add/remove rules, manage working directories, review recent auto-mode denials, and edit auto-mode classifier rules from an "Auto mode" tab. Opens immediately mid-turn as of v2.1.234 (previously queued until turn end).
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

27. **`/memory`** — built-in. "Edit CLAUDE.md files, enable or disable auto memory, and view auto memory entries."
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

28. **`/fork [prompt]`** — copies the current conversation into a new **background** session while you keep working in the current one; pass a prompt to have the copy start immediately. As of v2.1.221 it creates its own git worktree before making code changes (except when it edits in place). Distinguished from `/branch` (switches you *into* a new branch of the same conversation, preserving the original for `/resume`) and `/subtask` (hands a side task to a subagent that reports *back into* this conversation). Requires v2.1.212+; on v2.1.161–v2.1.211, or whenever agent view is off, `/fork` instead starts a forked *subagent* rather than a background session.
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

29. **`/resume [name]`** — alias `/return`. Returns to a previous conversation started via `/clear`, `/branch`, or `/fork`, or one that ended by exiting Claude Code; no argument opens a recency-sorted picker.
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

30. **`/clear [name]`** — aliases `/reset`, `/new`. Starts a new conversation with empty context; optional name labels the previous conversation in the `/resume` picker. Distinguished explicitly from `/compact` ("To free up context while continuing the same conversation, use `/compact` instead").
    URL: https://code.claude.com/docs/en/commands. PRIMARY.

31. **"Custom commands have been merged into skills" is presented as a 2026 fait accompli, not a roadmap item** — this is stated definitively in the current docs with no "coming soon" hedge, and a specific hard-error example is given for the *opposite* direction (uploading a skill outside Claude Code, e.g. to claude.ai or the Skills API, where only the six Agent-Skills-spec fields — `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools` — are legal, and anything else, e.g. `argument-hint`, fails packaging with `Unexpected key(s) in SKILL.md frontmatter`). This shows Claude-Code-only fields (like `argument-hint`, `context`, `disable-model-invocation`) are Claude Code **extensions** to the open Agent Skills standard (agentskills.io), not part of the portable spec.
    URL: https://code.claude.com/docs/en/skills (§ "Using skill frontmatter outside Claude Code"). PRIMARY.

32. **Skills follow the open "Agent Skills" standard** (agentskills.io), which "works across multiple AI tools." Claude Code extends it with invocation control, subagent execution (`context: fork`), and dynamic context injection (`` !`command` `` shell injection).
    URL: https://code.claude.com/docs/en/skills (intro paragraph). PRIMARY.

33. **Dynamic context injection**: `` !`command` `` at start-of-line or after whitespace runs a shell command before the skill content reaches Claude, substituting its output inline (one-pass, not recursively re-scanned); multi-line via a fenced ` ```! ` block. A failed command (non-zero exit, with a carve-out for exit code 1 from search/diff commands) **aborts the entire skill invocation** — Claude never sees the skill content that turn. Injected commands never prompt for permission; a matching ask/deny rule aborts the invocation regardless of `allowed-tools`. `disableSkillShellExecution: true` in settings globally disables this (each command replaced with a placeholder string) except for bundled/managed skills — most useful as a managed-settings lockdown users can't override.
    URL: https://code.claude.com/docs/en/skills (§ "Inject dynamic context", § "When an injected command fails"). PRIMARY.

34. **`context: fork` runs a skill as a forked, isolated subagent** (no access to conversation history) — runs in the background by default (you keep working; result arrives later), with `background: false` to block instead (requires v2.1.218+). A backgrounded fork gets a **narrower tool set** than a foreground one. The docs explicitly warn: `context: fork` "only makes sense for skills with explicit instructions" — a skill of pure reference guidelines with no task, forked, "returns without meaningful output."
    URL: https://code.claude.com/docs/en/skills (§ "Run skills in a subagent"). PRIMARY.

35. **Up to six skills can be chained in one message** (`/skill-a /skill-b do XYZ` style), stacking and sharing the trailing text as `$ARGUMENTS` for each — but expansion stops at the first token that isn't an "inline user-invocable" skill (i.e., a forked skill like `/code-review`, or one like `/loop` whose own arguments may start with a slash, ends the chain there). Before v2.1.199, only the first skill in a chain loaded; the rest were literal text.
    URL: https://code.claude.com/docs/en/skills (§ "Pass arguments to skills"). PRIMARY.

36. **Restricting Claude's own skill invocation**: three levers — deny the `Skill` tool entirely in `/permissions`; allow/deny specific skills with `Skill(name)` (exact) or `Skill(name *)` (prefix, any args) permission rules; or set `disable-model-invocation: true` per-skill. `skillOverrides` in settings.json is a fourth, out-of-band lever (four states: `on`, `name-only`, `user-invocable-only`, `off`) for skills you don't want to edit directly (e.g. checked into a shared repo) — as of v2.1.199, `"off"` also hides the skill from Remote Control and Agent SDK callers, not just the terminal menu.
    URL: https://code.claude.com/docs/en/skills (§ "Restrict Claude's skill access", § "Override skill visibility from settings"). PRIMARY.

37. **Practitioner consensus (secondary, unverifiable adoption numbers): commit and code-review/PR workflows are "the two most repeated prompts" that get automated first.** One guide frames `.claude/commands/` as "middle ground" for testing a workflow before converting it into a full skill once it's stable. No primary source or practitioner post found gives concrete data on standup/retro/worklog/handoff/fix-ci adoption specifically — this appears to be an assumption in the research brief rather than a documented pattern. GAP: could not verify with a primary source which of {commit, pr, handoff, standup, test-this, fix-ci, retro, worklog} practitioners "keep after a year"; no such longitudinal survey was found.
    URL: https://www.buildthisnow.com/blog/guide/mechanics/claude-code-custom-slash-commands. SECONDARY, one practitioner's framing, unverifiable adoption claim.

38. **Command-sprawl threshold, one opinionated heuristic (not documented by Anthropic)**: "invoking the same command 3-4+ times weekly signals conversion to skill status," with a suggested sweet spot of "5–10 well-scoped skills" rather than a sprawling library, and a warning that over-automating minor tasks with excessive skills degrades performance.
    URL: https://www.mindstudio.ai/blog/claude-code-skills-vs-slash-commands (dated April 18, 2026). SECONDARY, one practitioner's opinion, not corroborated elsewhere — treat as an unverified heuristic, not a documented Anthropic guideline.

39. **CONTESTED/likely-inaccurate secondary claim**: jsmanifest.com describes SKILL.md frontmatter fields `trigger_keywords` and `category` and an invocation flow where Claude "requests permission to load the skill." None of these appear in the official frontmatter reference table (finding #3 above), which instead documents `description`/`when_to_use` for autonomous triggering and no permission-request step for loading (only for tool use via `allowed-tools`). This source's technical specifics should not be trusted; it is included only to be explicitly flagged as contradicted by primary docs.
    URL: https://jsmanifest.com/claude-code-skills-slash-commands-unified-model (dated June 6, 2026). SECONDARY, CONTESTED — conflicts with PRIMARY docs.

## Downsides and failure modes

- **Context cost of loaded skills is sticky and budget-limited.** Once invoked, a skill's full rendered content stays in context across turns (not re-read on later turns), so poorly-scoped or verbose skills are a recurring token tax for the rest of the session; after compaction, only the most recent invocation of each skill is kept (5,000 tokens each, 25,000-token combined budget across all re-attached skills), so older invoked skills can be silently dropped entirely in a long session with many skills invoked. PRIMARY: https://code.claude.com/docs/en/skills (§ "Skill content lifecycle").
- **`allowed-tools` grants are turn-scoped, not session-scoped**, which is an easy mental-model trap: re-invoking the skill re-applies the grant, but it silently disappears on your very next message even if the skill's *instructions* are still sitting in context. A skill author who assumes the permission grant persists as long as the skill's content does will get unexpected permission prompts. PRIMARY: https://code.claude.com/docs/en/skills (§ "Pre-approve tools for a skill").
- **A failed shell injection kills the entire skill invocation silently from Claude's perspective** — Claude never even sees the skill content for that call, and non-zero exit from an unexpected command (e.g. `grep`/`diff` finding nothing on some platforms) aborts unless you defensively append `|| true`. This is a common gotcha for anyone porting shell one-liners into a skill's `` !`cmd` `` injection. PRIMARY: https://code.claude.com/docs/en/skills (§ "When an injected command fails").
- **Project skills with `allowed-tools` are NOT gated by workspace trust** — "Claude Code applies a project skill's allowed-tools whenever you or Claude invoke the skill, including in a `-p` run in a folder you've never trusted... A skill can grant itself broad tool access, so review the allowed-tools of skills checked into a repository before you run Claude Code there." This is a concrete supply-chain / trust-boundary risk explicitly called out in the docs. PRIMARY: https://code.claude.com/docs/en/skills (§ "Pre-approve tools for a skill").
- **Autonomous invocation can silently stop influencing behavior** without any error — "the content is usually still present and the model is choosing other tools or approaches." The documented remedy is to strengthen the `description`, or fall back to hooks for deterministic enforcement, or re-invoke after compaction. This is effectively an admission that skill triggering is soft/probabilistic, not a guarantee. PRIMARY: https://code.claude.com/docs/en/skills (§ "Skill content lifecycle").
- **Command sprawl / duplication risk is structural, not just a hygiene problem**: because `.claude/commands/*.md` and `.claude/skills/*/SKILL.md` both produce `/name`, and skills additionally auto-load into context just from their description text sitting in the always-visible skill listing, a large skill library imposes an always-on context cost (descriptions) even for skills nobody invokes, on top of the load-when-used cost of the body. `/doctor` (v2.1.206+) exists specifically to find "unused skills, MCP servers, and plugins versus their context cost" — i.e., Anthropic's own tooling treats skill/command bloat as a real, common problem worth an automated checkup for. PRIMARY: https://code.claude.com/docs/en/skills (§ "Bundled skills"); https://code.claude.com/docs/en/commands (`/doctor` row).
- **Name-collision ambiguity across five namespaces** (enterprise/personal/project/plugin/synced, plus nested directory-qualified variants) means "unclear triggering" is a real, documented failure mode: a user typing `/deploy` may get a different skill than they expect depending on where a same-named file exists, and the resolution rules (finding #7) require memorizing a precedence order to predict which one runs. PRIMARY: https://code.claude.com/docs/en/skills (§ "Where skills live").
- **Secondary/opinion-level warning**: over-automating minor tasks into skills "degrades performance" and creates cognitive overhead once past ~20 near-duplicate commands, per one practitioner blog — not corroborated by a primary source, but consistent with the token-budget mechanics in finding #10 above. SECONDARY, opinion: https://www.mindstudio.ai/blog/claude-code-skills-vs-slash-commands.
- **`/schedule` and cloud Routines run with zero permission prompts** ("no permission-mode picker and no approval prompts during a run") — an explicit autonomy/blast-radius tradeoff documented by Anthropic itself, worth flagging for anyone converting a `/loop` habit into a `/schedule` routine without re-scoping connectors/environment access. PRIMARY: https://code.claude.com/docs/en/routines.

## Concrete practices / configs

**Minimal skill/command with argument capture (goes in `~/.claude/skills/fix-issue/SKILL.md` or `.claude/commands/fix-issue.md`):**
```yaml
---
description: Fix a GitHub issue
disable-model-invocation: true
---

Fix GitHub issue $ARGUMENTS following our coding standards.

1. Read the issue description
2. Understand the requirements
3. Implement the fix
4. Write tests
5. Create a commit
```
Source: https://code.claude.com/docs/en/skills (§ "Pass arguments to skills"). PRIMARY.

**Commit-style command with pre-approved git tools, human-only invocation (the canonical "beats a skill" pattern for side-effecting actions):**
```yaml
---
name: commit
description: Stage and commit the current changes
disable-model-invocation: true
allowed-tools: Bash(git add *) Bash(git commit *) Bash(git status *)
---
```
Source: https://code.claude.com/docs/en/skills (§ "Pre-approve tools for a skill"). PRIMARY.

**Deploy skill — the docs' own canonical "command beats skill" example** (side effects, human-timed):
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
Source: https://code.claude.com/docs/en/skills (§ "Control who invokes a skill"). PRIMARY.

**Reference-only skill — the canonical "skill beats command" example** (autonomous, never manually invoked, no side effects):
```yaml
---
name: api-conventions
description: API design patterns for this codebase
---

When writing API endpoints:
- Use RESTful naming conventions
- Return consistent error formats
- Include request validation
```
Source: https://code.claude.com/docs/en/skills (§ "Types of skill content"). PRIMARY.

**Positional named arguments:**
```yaml
---
name: migrate-component
description: Migrate a component from one language to another
arguments: [component, from, to]
---

Migrate the $component component from $from to $to.
Preserve all existing behavior and tests.
```
(Equivalent to `$0`/`$1`/`$2`.) Source: https://code.claude.com/docs/en/skills. PRIMARY.

**Dynamic context injection (git diff auto-pulled into the prompt):**
```yaml
---
description: Summarizes uncommitted changes and flags anything risky. Use when the user asks what changed, wants a commit message, or asks to review their diff.
---

## Current changes

!`git diff HEAD`

## Instructions

Summarize the changes above in two or three bullet points, then list any risks you notice such as missing error handling, hardcoded values, or tests that need updating. If the diff is empty, say there are no uncommitted changes.
```
Source: https://code.claude.com/docs/en/skills (Getting started example). PRIMARY.

**Subagent-isolated research skill (`context: fork` + `agent:`):**
```yaml
---
name: deep-research
description: Research a topic thoroughly
context: fork
agent: Explore
---

Research $ARGUMENTS thoroughly:

1. Find relevant files using Glob and Grep
2. Read and analyze the code
3. Summarize findings with specific file references
```
Source: https://code.claude.com/docs/en/skills (§ "Run skills in a subagent"). PRIMARY.

**Bundled-script permission pattern using `${CLAUDE_SKILL_DIR}` (avoids a permission prompt for a script shipped with the skill):**
```yaml
---
name: render-chart
description: Render a chart from a CSV file
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)
---

Run `${CLAUDE_SKILL_DIR}/scripts/render.sh <csv-file>` to render the chart.
```
Source: https://code.claude.com/docs/en/skills (§ "Available string substitutions"). PRIMARY.

**Turning off command sprawl / auditing bloat:** run `/doctor` periodically — it finds unused skills/MCP/plugins by context cost, and can trim/deduplicate CLAUDE.md files, moving always-loaded guidance into on-demand skills. To hard-disable all bundled skills except `/doctor` itself: `"disableBundledSkills": true` in settings. To hide/lock a specific skill without editing its file (e.g. checked into a shared repo you don't own): 
```json
{
  "skillOverrides": {
    "legacy-context": "name-only",
    "deploy": "off"
  }
}
```
Source: https://code.claude.com/docs/en/skills (§ "Override skill visibility from settings"). PRIMARY.

**Scheduling: local session-scoped vs. durable cloud routine.**
- Quick polling while you keep the terminal open: `/loop 5m check if the deployment finished and tell me what happened`
- Durable, no-machine-required recurring automation: `/schedule daily PR review at 9am` (requires claude.ai subscription login; creates a cloud Routine with no permission prompts at run time — scope its connectors/environment deliberately).
Source: https://code.claude.com/docs/en/scheduled-tasks; https://code.claude.com/docs/en/routines. PRIMARY.

## Disagreements and open questions

- **No primary-source data on which custom commands practitioners keep after a year.** The research brief's list (commit, pr, handoff, standup, test-this, fix-ci, retro, worklog) could not be verified against any longitudinal or survey-style source, primary or secondary. The only concrete secondary claim found is that commit + code-review/PR are "the two most repeated prompts" worth automating first (buildthisnow.com) — everything else in that list is unconfirmed by any source this research could reach. This is a genuine gap: it may reflect real practitioner behavior the research agent simply couldn't find with the tools available (WebSearch budget was exhausted after 2 queries this session — see Gaps below), rather than the claim being false.
- **Command-sprawl thresholds ("5-10 skills," "3-4x/week signals convert to skill") are single-blogger heuristics**, not Anthropic guidance and not corroborated by a second independent source. Should be treated as opinion, not consensus.
- **jsmanifest.com's described frontmatter fields (`trigger_keywords`, `category`) directly contradict the official frontmatter table** — either the article is describing a hypothetical/aspirational design, an older or different product, or is simply inaccurate. This is a clear-cut disagreement between a secondary source and the primary docs; the primary docs should be trusted.
- **Whether `/simplify` and `/code-review` fully overlap** is not entirely resolved by the docs fetched: the commands table says `/simplify` is for "opportunities to simplify" while `/code-review` is for "correctness bugs and cleanup opportunities" — the exact line between "cleanup opportunities" (code-review) and "opportunities to simplify" (simplify) is somewhat fuzzy in the docs' own wording, and this session's own skill-listing metadata frames `/simplify` as explicitly *not* bug-hunting ("Quality only... use /code-review for that"), which is a cleaner distinction than the commands-table prose alone gives. Worth a follow-up fetch of `/docs/en/code-review` directly if more precision is needed (not fetched in this pass).

## Sources

- https://code.claude.com/docs/en/skills — PRIMARY, fetched 2026-09-04 (page itself undated; also reachable via `/docs/en/slash-commands`, which now serves the same content). Frontmatter reference, namespacing, invocation control, dynamic context injection, subagent forking, skill lifecycle, synced-skill behavior.
- https://code.claude.com/docs/en/commands — PRIMARY, fetched 2026-09-04. Full built-in-command and bundled-skill reference table (A–Z), used for /clear, /compact, /context, /goal, /rewind, /resume, /fork, /branch, /subtask, /loop, /batch, /schedule, /code-review, /simplify, /security-review, /doctor, /fewer-permission-prompts, /skills, /hooks, /permissions, /memory, /stats, /usage, /cost, /status, /verify, /worktree, /workflow, and dozens more.
- https://code.claude.com/docs/en/scheduled-tasks — PRIMARY, fetched 2026-09-04. `/loop` full mechanics: interval modes, `loop.md` override, jitter, 7-day expiry, cron tools (`CronCreate`/`CronList`/`CronDelete`), comparison table of cloud/desktop/`/loop` scheduling.
- https://code.claude.com/docs/en/routines — PRIMARY, fetched 2026-09-04. `/schedule` CLI entry point into cloud Routines: triggers (schedule/API/GitHub), autonomy model (no permission prompts), connectors, network access, troubleshooting "Unknown command" cases.
- https://code.claude.com/docs/en/cli-reference — PRIMARY, fetched 2026-09-04, but returned mostly non-slash CLI subcommands (`claude update`, `claude mcp`, `claude doctor`, etc.) rather than the slash-command table; superseded in this report by the `/docs/en/commands` fetch.
- https://www.mindstudio.ai/blog/claude-code-skills-vs-slash-commands — SECONDARY, dated April 18, 2026. Practitioner opinion on when to use skills vs. commands, command-sprawl heuristics (20+ commands = overhead, 5–10 skills sweet spot, 3-4x/week conversion signal).
- https://jsmanifest.com/claude-code-skills-slash-commands-unified-model — SECONDARY, dated June 6, 2026. CONTESTED — describes frontmatter fields not present in the official docs; low reliability, included for contrast only.
- https://www.buildthisnow.com/blog/guide/mechanics/claude-code-custom-slash-commands — SECONDARY, undated (references "As of 2026"). Practitioner guide; commit/review as the two most-automated workflows; commands-as-prototype-before-skill framing.
- https://aiopsschool.com/blog/the-master-tutorial-every-claude-code-slash-command-explained-april-2026-edition/ — SECONDARY, dated April 25, 2026 ("April 2026 Edition"). Three-tier command taxonomy (deterministic built-ins / bundled skills / custom-MCP); recommends `disable-model-invocation: true` for side-effecting commands (consistent with primary docs); recommends running `/help` for the authoritative live list rather than trusting any written doc.
- (Search-only, not fetched) https://github.com/qdhenry/Claude-Command-Suite; https://oneaway.io/blog/claude-code-commands-vs-skills; https://www.youngleaders.tech/p/claude-skills-commands-subagents-plugins; https://thepromptshelf.dev/blog/claude-code-skills-vs-slash-commands-complete-guide-2026/; https://agenticschool.dev/guides/claude-code-skills-and-commands; https://yingtu.ai/en/blog/claude-code-skills-vs-slash-commands — surfaced by WebSearch but not fetched due to search-budget exhaustion; listed here as unverified leads only, not used as evidence for any claim above.

### Note on method deviation
This session's WebSearch tool reported its budget already exhausted (200/200) after only 2 successful queries were run by this agent — the cap appears to be shared session-wide rather than per-agent-call, and had apparently been consumed by prior activity in this session before this task began. Per the harness's own instruction ("continue with the information already gathered instead of issuing more searches"), this research relied on 2 WebSearch queries (both successful, both used above) plus 11 WebFetch calls against primarily official documentation to compensate. All built-in/bundled-skill command claims and all frontmatter/namespacing claims are PRIMARY and directly quoted/paraphrased from code.claude.com/docs. The practitioner-adoption question (which custom commands survive a year of use) remains the weakest-evidenced part of this report as a direct result of the search-budget constraint — see "Disagreements and open questions" above.

## Source check (independent)

Method: re-fetched the cited primary source for each of the 6 most load-bearing claims in this report (specific numbers, version ranges, and near-verbatim mechanic descriptions) and compared the fetched text against the claim as written. All 6 sources loaded successfully on the first try — no WebSearch fallback was needed.

1. **Claim (Finding #5): "the grant clears on your next message (not session-persistent)."**
   Source: https://code.claude.com/docs/en/skills, frontmatter reference table + § "Pre-approve tools for a skill."
   Exact quote: *"Tools Claude can use without asking permission during the turn that invokes this skill. **The grant clears when you send your next message.**"* And: *"The grant clears when you send your next message, even though the skill content stays in context; invoking the skill again re-applies it for that turn."*
   Verdict: **CONFIRMED.**

2. **Claim (Finding #10): "keeping the first 5,000 tokens of each... sharing a combined 25,000-token budget across all re-attached skills (oldest dropped first if budget is exceeded)."**
   Source: https://code.claude.com/docs/en/skills, § "Skill content lifecycle."
   Exact quote: *"Auto-compaction carries invoked skills forward within a token budget. When the conversation is summarized to free context, Claude Code re-attaches the most recent invocation of each skill after the summary, **keeping the first 5,000 tokens of each. Re-attached skills share a combined budget of 25,000 tokens.** Claude Code fills this budget starting from the most recently invoked skill, so older skills can be dropped entirely after compaction if you have invoked many in one session."*
   Verdict: **CONFIRMED** (numbers exact; "oldest dropped first" is an accurate paraphrase of "fills this budget starting from the most recently invoked skill").

3. **Claim (Finding #16): "Minimum recurring interval is 1 hour (vs. `/loop`'s 1 minute)... Requires a claude.ai subscription login... Routines run with no permission-mode picker and no approval prompts."**
   Sources: https://code.claude.com/docs/en/scheduled-tasks (comparison table) and https://code.claude.com/docs/en/routines.
   Exact quotes: comparison table row *"Minimum interval | 1 hour [Cloud] | 1 minute [Desktop] | 1 minute [/loop]"*; *"`/schedule` requires a claude.ai subscription login."*; *"Routines run autonomously as full Claude Code cloud sessions: **there is no permission-mode picker and no approval prompts during a run.**"*
   Verdict: **CONFIRMED**, all three sub-claims verbatim.

4. **Claim (Finding #33): "A failed command (non-zero exit, with a carve-out for exit code 1 from search/diff commands) aborts the entire skill invocation."**
   Source: https://code.claude.com/docs/en/skills, § "When an injected command fails."
   Exact quote: *"A failed command aborts the entire skill invocation, not just its own placeholder. Claude never sees the skill content for that invocation... With the default `bash` shell, any non-zero exit code counts as a failure. **One carveout applies: Claude Code treats exit code 1 from search and comparison commands as a normal result and injects their output. Exit codes of 2 or higher fail even for those commands.**"*
   Verdict: **CONFIRMED.**

5. **Claim (Finding #7): "A skill at any of these levels overrides a bundled skill of the same name, but never a bundled skill's alias... enterprise overrides personal, personal overrides project."**
   Source: https://code.claude.com/docs/en/skills, § "Where skills live."
   Exact quotes: *"Across levels, enterprise overrides personal, and personal overrides project."* And: *"A skill at any of these levels also overrides a bundled skill with the same name, but not the bundled skill's aliases. For example, a `code-review` skill in your project's `.claude/skills/` replaces the bundled `/code-review`, and typing the bundled alias `/review` never runs your skill."*
   Verdict: **CONFIRMED**, including the specific `/code-review` vs. `/review` example, which the report's own worked example matches almost word-for-word.

6. **Claim (Finding #8): "If a plugin skill's `name` already starts with the plugin's own prefix, Claude Code (v2.1.246+) doesn't double it — versions v2.1.216–v2.1.245 had a doubling bug."**
   Source: https://code.claude.com/docs/en/skills, § "How a skill gets its command name."
   Exact quote: *"If the `name` you write already starts with the plugin's own prefix, Claude Code doesn't add the prefix again on v2.1.246 or later. For example, `name: my-plugin:fancy` still becomes `/my-plugin:fancy`. **From v2.1.216 through v2.1.245, Claude Code doubled the prefix when the `name` already carried it.**"*
   Verdict: **CONFIRMED**, version boundaries exact.

### Summary
6/6 checked claims CONFIRMED against their cited primary source, with exact or near-exact quote matches (including specific numbers and version ranges). No UNSUPPORTED or MISATTRIBUTED claims found among the 6 checked, so no inline `[UNVERIFIED: ...]` edits were needed in the Findings section above. This sample was deliberately drawn from the report's most specific, falsifiable claims (token counts, version ranges, interval minimums, exit-code carve-outs); it does not re-verify the SECONDARY/opinion-sourced claims (findings #37–39, the mindstudio/jsmanifest/buildthisnow material), which the report itself already flags as unverified practitioner opinion rather than presenting as fact.

**Reliability note**: the PRIMARY-sourced portion of this report (the large majority of it — frontmatter, namespacing, scheduling, injection mechanics) is highly reliable: every spot-checked claim, including ones with exact numbers and version strings that are easy to misremember or fabricate, matched the live docs verbatim. The weak spots are exactly where the report itself already says they are — the SECONDARY-sourced adoption/heuristic claims (#37, #38) and the CONTESTED jsmanifest source (#39) — not anywhere in the PRIMARY material.
