# Artifact Decision Matrix

Load this reference during Phase 2 to pick the right Claude Code artifact type for each surviving finding.

---

## The Calibration Question

Given user need X, which artifact type is the RIGHT answer? Picking wrong doesn't break anything — it silently underperforms, wastes tokens, or runs at the wrong time.

---

## Primary Decision Matrix

| User need | Best artifact | Why | Anti-choice |
|-----------|---------------|-----|-------------|
| "Do X every time I do Y" (deterministic) | **Hook** (PreToolUse/PostToolUse) | 100% reliable, event-driven, can block | Skill — Claude must choose to invoke |
| "Claude should know our API conventions" (always) | **CLAUDE.md** or **.claude/rules/** with `paths:` | Always-loaded knowledge | Skill with `user-invocable: false` — loading overhead |
| "I want `/deploy` that I trigger manually" | **Skill** with `disable-model-invocation: true` | Prevents Claude auto-triggering deploys | Plain skill — Claude might auto-deploy |
| "Complex multi-file workflow" | **Skill** with `context: fork` | Runs isolated, preserves main context | Inline skill — pollutes main conversation |
| "Reusable research/exploration agent" | **Subagent** (`.claude/agents/`) | Custom system prompt, tool restrictions, per-model | Skill — can't restrict tools/model per-invocation |
| "Keep exploration out of main context" | **Subagent** | Separate context window | Inline skill — every Read/Grep stays in main |
| "Add external API (GitHub, Slack, DB)" | **MCP server** | Structured tools, auth, resources | Bash hook — brittle shell around APIs |
| "Project-specific conventions for team" | **Project CLAUDE.md** (committed) | Travels with repo | User CLAUDE.md — stays on one machine |
| "Auto-format on every file edit" | **Hook** (PostToolUse on Edit/Write) | Deterministic | Subagent — too heavy for per-edit ops |
| "Block dangerous commands" | **Hook** (PreToolUse on Bash, exit 2) | Hard block before execution | CLAUDE.md — Claude might ignore under pressure |
| "Domain knowledge for specific filetypes" | **Skill** with `paths:` frontmatter | Only loads when working matching files | CLAUDE.md rule — always-loaded token cost |
| "Sharable across projects / team / community" | **Plugin** | Namespaced, versioned, installable | `.claude/skills/` — manual copy required |
| "Persistent learning Claude accumulates" | **Subagent** with `memory:` or auto-memory | Auto-written, persists across sessions | CLAUDE.md — manual updates only |
| "Status bar context" | **statusLine** command | stdin JSON, outputs ANSI | Skill — can't produce UI chrome |

---

## Quick Decision Heuristics

**"Should this be a hook or a skill?"**
- Need guaranteed automation without Claude's judgment → **Hook**
- Need Claude to apply judgment → **Skill**
- Need to block an action → **Hook** (only hooks can block)
- Need to modify tool input → **Hook** (`updatedInput` field)

**"Should this be a skill or CLAUDE.md?"**
- Always needed + short (< 10 lines of guidance) → **CLAUDE.md**
- Situationally needed OR > 100 lines of content → **Skill**
- Filetype-scoped → **Skill** with `paths:` (NOT CLAUDE.md)

**"Should this be a skill or a subagent?"**
- You know the task at authoring time → **Skill** with `context: fork`
- Claude should decide when to delegate dynamically → **Subagent**
- Need custom tool restrictions per-invocation → **Subagent**
- Need separate context window → **Subagent**

**"Project `.claude/` or plugin?"**
- Share with this project's team → commit `.claude/skills/` (simpler, no namespace friction)
- Distribute outside the project → **Plugin** (namespacing, versioning worth it)

---

## Non-Obvious Gotchas (expert-only)

🚨 **`disable-model-invocation: true`** removes the skill description from Claude's context entirely. Claude literally doesn't know it exists. Much stronger than "disabled" — use for side-effect skills (deploys, sends).

🚨 **Plugin subagents silently ignore** `hooks`, `mcpServers`, and `permissionMode` fields. If you port a project agent to a plugin, you lose these without warning. Don't recommend plugin form for agents that need these.

🚨 **`--add-dir` loads skills but NOT CLAUDE.md** (unless `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`). One of the few exceptions in the scoping rules.

🚨 **Subagents cannot spawn subagents**. Only the main thread can. If you recommend a subagent that needs to orchestrate a swarm, that's an error — use a skill instead.

🚨 **CLAUDE.md content injects as a user message after system prompt, NOT as part of system prompt**. It's context, not enforcement. Claude can ignore it under pressure. Over 200 lines shows measurable compliance degradation.

🚨 **Skill beats command on name collision**. Use skills for all new work. Commands are legacy alias.

🚨 **`.claude/settings.json` is committed to VCS**. Don't put hook paths referencing `~/personal-scripts/` there — collaborators get broken hooks.

---

## Scope Rules (where to write the artifact)

| Scope | Path | When to use |
|-------|------|-------------|
| User (all projects, one user) | `~/.claude/skills/<name>/SKILL.md` | Default for personal workflows the user runs across projects |
| Project (this repo, all contributors) | `./.claude/skills/<name>/SKILL.md` | Team conventions, project-specific flows |
| Local (this repo, this user only) | `./.claude/settings.local.json` for hooks; skills always travel | Personal overrides, experimental, gitignored |
| Managed (org-wide) | Enterprise MDM path | Usually not within scope of this skill |

**Rule of thumb for claude-improver:**
- If it references the user's specific stack/tools only they use → **User scope**
- If it references repo-specific conventions → **Project scope**
- When in doubt → **User scope** (less blast radius)

---

## Authoring Anti-Patterns Per Type

### Skills
- Long descriptions truncate at 250 chars → front-load trigger condition
- SKILL.md over 500 lines → move detail to `references/`
- `user-invocable: false` does NOT block programmatic use — use `disable-model-invocation: true` instead
- Use `${CLAUDE_SKILL_DIR}` for bundled scripts (not hardcoded paths)

### Hooks
- Exit 2 + JSON stdout → JSON is IGNORED. Use exit 2 + stderr for blocking.
- Relative paths in commands → depend on cwd. Use `"$CLAUDE_PROJECT_DIR"`.
- Shell startup output breaking JSON → redirect: `source ~/.bashrc 2>/dev/null 1>/dev/null`
- Blocking Stop hook without checking `stop_hook_active` → infinite loop

### Subagents
- Parent skills are NOT inherited — list every needed skill in `skills:` field
- Broad "use for coding" description → over-delegation, everything becomes an agent task
- Subagent trying to spawn subagents → silently fails

### CLAUDE.md
- Instructions Claude already knows ("use TypeScript best practices") → waste tokens
- Rules that belong in `.claude/rules/` with `paths:` → don't bloat root CLAUDE.md
- Conflicting instructions across multiple CLAUDE.md levels → Claude picks arbitrarily

### MCP
- `--scope project` + personal API keys → committed secrets. Use `--scope local`.
- All MCPs in main session → context bloat. Define inline in subagents that need them.

### Plugins
- Plugin structure: only `plugin.json` goes in `.claude-plugin/`; everything else at root
- Long plugin names become typing friction (namespaced: `plugin-name:skill-name`)
- Using plugin for single-project customization → overhead not worth it
