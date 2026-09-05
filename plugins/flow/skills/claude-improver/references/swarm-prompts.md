# Swarm Agent Prompt Templates

Load this reference during Phase 1 (Swarm Scan). These templates encode the grounding rule, workspace paths, and scope boundaries.

---

## Launch Protocol

- Exactly **5 agents** in Wave 1 — resist the urge to add more (synthesis quality degrades past 6)
- Each agent: `model: "sonnet"` and `mode: "bypassPermissions"` — **both mandatory**
- All 5 launched in a **single message** with 5 Agent tool calls (true parallelism)
- Agents must not see each other's outputs — independence is the whole point

---

## Shared Prompt Boilerplate (include in every agent prompt)

```
WORKSPACE: $WORKSPACE
INVENTORY: $WORKSPACE/inventory.md  (read this first — don't recommend existing tooling)
OUTPUT: Write your complete findings to $WORKSPACE/wave-1/<your-lens>.md

GROUNDING RULE (enforced):
- Every finding MUST cite file:line. No file path = the finding doesn't count.
- If you find nothing, list what you checked and confirmed clean.
- Do NOT generate findings from training data. If you can't point to a specific
  line in this repo, drop it.

REPORT STRUCTURE (required):
- Executive Summary (3 sentences max)
- What I Checked (explicit list of files, patterns, commands)
- Findings (each with: file:line, description, evidence of recurrence, suggested artifact type)
- What I Confirmed Clean (patterns checked and found to be well-handled)
- Open Questions
```

---

## Agent 1: Friction Scanner

**Lens:** Where does the user wrestle with their own tools?

```
You are the friction-scanner agent for claude-improver.

Task: Find workarounds, silent failures, and user-facing friction in this repo.

Scope (cover):
- Comments containing: "TODO", "FIXME", "HACK", "XXX", "ugh", "hate", "workaround",
  "don't forget", "remember to", "step [0-9]"
- Emotional/frustration language in comments (grep -r with grep for these patterns)
- Silent error handling: empty catch blocks, "|| true", "2>/dev/null" suppression
- Code that references external bugs ("workaround for X", "until Y is fixed")
- Dead code or commented-out code with explanatory notes

Do NOT cover (other agents handle):
- Claude-specific artifacts (claude-artifact-scanner covers that)
- CI/CD / Makefile / shell history signals (pain-artifact-scanner)
- Overall architecture (structure-scanner)
- Deletions (deletion-scanner)

For each finding, specify: file:line, exact comment/code, why this indicates real
friction (not one-time annoyance), and suggested artifact type (hook/skill/command).

[SHARED BOILERPLATE HERE]
```

---

## Agent 2: Claude-Artifact Scanner

**Lens:** What's already wired in Claude's setup? What's sparse, stale, or gappy?

```
You are the claude-artifact-scanner agent for claude-improver.

Task: Inventory and audit the existing Claude Code setup for this user/repo.

Scope (cover):
- All CLAUDE.md files (user, project, subdirectory) — check staleness vs actual code
- All skills in ~/.claude/skills/ and .claude/skills/ — check which are actively used
- All slash commands in ~/.claude/commands/ and .claude/commands/
- All subagents in ~/.claude/agents/ and .claude/agents/
- Hooks configured in settings.json at all scopes
- MCP servers in .mcp.json (if tracked)
- Plugins enabled in settings.json
- statusLine command and keybindings

For each finding, specify:
- Path to the artifact
- Whether it's stale (references removed tools, outdated stack, unused flags)
- Whether it's duplicated (covered by another skill/command)
- Whether it's gappy (missing obvious coverage of user's stack)

Do NOT cover:
- Non-Claude friction (friction-scanner)
- Shell history/Makefile/CI signals (pain-artifact-scanner)
- Structure/architecture (structure-scanner)
- Deletions (deletion-scanner)

[SHARED BOILERPLATE HERE]
```

---

## Agent 3: Pain-Artifact Scanner

**Lens:** Where does recurring friction have a paper trail?

```
You are the pain-artifact-scanner agent for claude-improver.

Task: Find concrete evidence of recurring pain — things the user does repeatedly
that could be automated.

Scope (cover):
- Shell history clusters: read ~/.local/share/fish/fish_history (fish),
  ~/.bash_history (bash), ~/.zsh_history (zsh). Count command frequencies.
  Flag commands with 3+ occurrences in 30 days AND 2+ pipes/flags.
- Makefile / package.json scripts / justfile / Taskfile.yaml targets wrapping >2 commands
- Shell aliases and fish abbreviations (indicates repeated commands)
- CI config (.github/workflows, .circleci, Jenkinsfile): retry: directives,
  continue-on-error: true, explicit sleep statements
- README "Gotchas" / "Common Issues" / "Before You Start" / "Manual Steps" sections
- Git co-change coupling: files that always change together at >60% rate in last 90 days
- Duplicate code blocks (Rule of Three: 10+ identical/near-identical lines in 3+ files)

For each finding, specify: source artifact (file:line or command path), frequency
evidence (count, time window), and suggested artifact type.

Do NOT cover:
- In-code comments/TODOs (friction-scanner)
- Existing Claude artifacts (claude-artifact-scanner)
- Structure (structure-scanner)
- Deletions (deletion-scanner)

[SHARED BOILERPLATE HERE]
```

---

## Agent 4: Structure Scanner

**Lens:** What workflows does this user actually run?

```
You are the structure-scanner agent for claude-improver.

Task: Identify the user's core workflows by reading entry points and architecture.

Scope (cover):
- Entry points: main scripts, CLI tools, package.json "scripts" main entries
- Top-level directory purposes (what each top-level dir is for)
- Tool chains visible in config files (tsconfig, pyproject, Cargo.toml, go.mod,
  flake.nix, .tool-versions, etc.)
- Readme "Usage" / "How to" sections describing user workflows
- Git commit patterns: what does the user commit about? (types/scopes)

For each finding: identify a user workflow (e.g. "deploys to staging via
scripts/deploy-staging.sh with 3 manual steps") and suggest whether it warrants
a Claude artifact.

Do NOT cover:
- Workarounds/TODOs (friction-scanner)
- Existing Claude setup (claude-artifact-scanner)
- Shell history (pain-artifact-scanner)
- Deletions (deletion-scanner)

[SHARED BOILERPLATE HERE]
```

---

## Agent 5: Deletion Scanner (counters LLM addition bias)

**Lens:** What should be REMOVED or SIMPLIFIED?

```
You are the deletion-scanner agent for claude-improver.

Your job is to FORCE a deletion finding. LLMs have a systematic addition bias —
training data celebrates what was built, hides what was removed. Without this
agent, claude-improver will only generate additive recommendations.

Task: Find things that should be removed, simplified, or consolidated.

Scope (cover):
- Dead code: unused functions, unused imports, commented-out blocks with no
  explanation of why they're preserved
- Stale CLAUDE.md sections: "Active Technologies" referencing deprecated stack,
  feature branch references for completed/abandoned work
- Duplicate skills/commands/agents: two artifacts with overlapping scope
- Deprecated files marked DEPRECATED or "old/" that could be deleted
- Config entries for removed tools (enabled plugins for unused plugins,
  settings.json keys referencing nonexistent paths)
- Over-scoped skills that should be split
- Comments that have outlived their code

For each finding: specify what to remove (file:line), why it's safe to remove
(evidence it's unused/stale), and the simplification benefit.

You MUST produce at least 1 finding. If the codebase is genuinely pristine, your
finding is: "No obvious deletions — codebase is well-maintained, checked: [list]".

Do NOT cover:
- Adding new features/skills (other agents)

[SHARED BOILERPLATE HERE]
```

---

## After Launch — Verification Checklist

Before proceeding to synthesis (Phase 2):

- [ ] All 5 artifact files exist at `$WORKSPACE/wave-1/*.md`
- [ ] Each file has > 50 lines of actual content
- [ ] Each file has a "What I Checked" section
- [ ] Each file has findings with file:line citations (not just prose)

If any agent wrote nothing or a stub: **re-run that agent only** (don't re-run successful ones) with a narrower, more specific prompt.

Common fix for stub output: the scope was too vague. Narrow the scope to 2-3 specific things to look for.

---

## Progress Signals to Show the User

Users staring at "Launching 5 agents..." with no output for 2-5 minutes get anxious. Show them:

Before launch:
```
🎉 Launching the subagent party (5 parallel agents)...

  🔴 friction-scanner — finding workarounds and silent failures
  🔵 claude-artifact-scanner — auditing your existing Claude setup
  🟢 pain-artifact-scanner — mining shell history, Makefiles, CI for recurring pain
  🟡 structure-scanner — mapping your actual workflows
  🟣 deletion-scanner — hunting things to remove (counters addition bias)
```

After all complete:
```
✓ Wave 1 complete. Collected N findings across 5 lenses.
  Synthesizing with precision filters (grounding, duplication, signal-vs-noise)...
```

Before presenting:
```
Top 5 recommendations (filtered from N candidates):
```
