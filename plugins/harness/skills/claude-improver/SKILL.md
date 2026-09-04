---
name: claude-improver
description: Scan a repo with a parallel subagent swarm to find and generate genuinely useful Claude Code improvements — new skills, slash commands, subagents, hooks, or CLAUDE.md updates. Use WHENEVER the user says /claude-improver, "improve my claude setup", "scan my repo for claude improvements", "find useful skills for me", "build me claude commands", "what claude stuff should I add", "claude party", "subagent party". Triggers on: improve claude, claude improvements, generate skills, scan repo claude, claude-improver, useful commands. Uses a 5-lens parallel swarm grounded in actual file evidence, applies precision filters (max 5 recommendations, no duplication of existing tools), and generates artifacts that pass skill-judge. Do NOT use for: general code review (use /review), fixing bugs (use /fix), auditing CLAUDE.md only (use claude-md-improver), one-off skill authoring (use skill-forge).
---

# Claude Improver

Launch a precision-tuned subagent swarm that scans a repo, identifies genuinely useful Claude Code improvements grounded in actual file evidence, and generates skills/commands/hooks/subagents that pass quality gates.

**The hard problem this solves**: most workflow analyzers produce long lists of noise. This one optimizes for *precision* — every recommendation cites a specific file, survives signal filters, and respects what the user already has. Bad suggestions create a **trust tax** that poisons future recommendations permanently, so the bar is high and the output cap is low.

---

## The Core Precision Discipline

Five non-negotiable rules that separate this skill from noise-generators:

1. **Grounding rule**: Every finding must cite `file:line`. No file path = finding doesn't count. This is the anti-confabulation mechanism.

2. **The 5-recommendation cap**: Surface at most 5 ranked recommendations. Decision fatigue begins at 7-9 items and a longer list gets dismissed entirely.

3. **Duplication check first**: Before any recommendation is surfaced, verify no equivalent exists. Check: existing skills, commands, agents, hooks, Makefile targets, shell aliases, fish abbreviations, MCP servers. Recommending `/deploy` when `make deploy` exists destroys trust.

4. **Force a deletion finding**: LLMs have a systematic addition bias — training data celebrates what was built, hides what was removed. The swarm MUST produce at least one "remove/simplify X" candidate per run. This is a required category, not optional.

5. **Trust-tax-first**: If in doubt, drop the recommendation. One wrong suggestion poisons trust in all future suggestions. Precision > recall, always.

---

## Phased Workflow

Each phase lists the references it requires. **Do NOT load references outside the phase that needs them** — context bloat degrades later synthesis.

### Phase 0: Pre-Flight Inventory

*No references needed.*

Before launching any agents, the orchestrator (main conversation) MUST inventory what already exists. This prevents the #1 analyzer failure mode: recommending something the user already has.

```bash
# Discover target repo
TARGET="${1:-$(pwd)}"
WORKSPACE="$TARGET/.claude-improver/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$WORKSPACE/wave-1" "$WORKSPACE/generated"
```

Then inventory in parallel:
- Existing `.claude/skills/`, `.claude/commands/`, `.claude/agents/` (project + `~/.claude/`)
- `settings.json` hooks at all scopes
- `.mcp.json` servers
- All CLAUDE.md files
- Makefiles, package.json scripts, justfile targets
- Fish abbreviations / bash aliases
- Enabled plugins

Write the inventory to `$WORKSPACE/inventory.md`. Every later agent will be given this file to avoid duplicate recommendations.

### Phase 1: Swarm Scan (Wave 1)

**MANDATORY: Load `references/swarm-prompts.md` before launching. Do NOT load other references yet.**

Launch exactly **5 parallel agents**, each with `model: "sonnet"` and `mode: "bypassPermissions"`. Each has a non-overlapping concern-lens and explicit "do NOT cover X" boundaries.

The 5-lens roster (proven by brainstorm, adapted for claude-improver):

| Agent | Lens | Key question |
|-------|------|--------------|
| **friction-scanner** | Workarounds and pain | Where does the user wrestle with their own tools? |
| **claude-artifact-scanner** | Existing Claude setup | What's already wired, what's sparse, what's stale? |
| **pain-artifact-scanner** | Concrete pain evidence | Where does recurring friction have a paper trail? |
| **structure-scanner** | Architecture and entry points | What workflows does the user actually run? |
| **deletion-scanner** | What to remove | What's dead, duplicate, or deprecated? |

**Agent prompts are in `references/swarm-prompts.md`** — use those templates verbatim (they encode the grounding rule, workspace path, and scope boundaries).

After launching all 5, wait for completion. Then **verify every artifact file exists and has >50 lines**. If any is missing or stubby, re-run that specific agent (don't re-run successful ones) with a rephrased, narrower prompt.

### Phase 2: Synthesis (Orchestrator Only)

**MANDATORY: Load `references/signal-patterns.md` AND `references/artifact-decision-matrix.md`. Do NOT load swarm-prompts.md or generation-quality-bar.md yet.**

The orchestrator reads **every artifact file from disk** — never synthesize from agent return messages (those truncate). This step MUST NOT be delegated to a subagent.

For each finding across all 5 artifacts, apply these filters in order:

1. **Grounding check**: Does it cite file:line? If not, drop it.
2. **Duplication check**: Does an equivalent exist in `inventory.md`? If yes, drop it.
3. **Signal check**: Apply the signal vs anti-signal filters from `references/signal-patterns.md`. Drop anti-signals (one-time setup, pleasurably manual, rarely-triggered, framework-handled).
4. **Frequency check**: Is there evidence this pain recurs? (Shell history cluster, multiple co-changes, TODO emotional language, README gotcha, CI retry directive). Without evidence of recurrence, drop it.
5. **Artifact-type calibration**: For surviving findings, determine which artifact type fits using `references/artifact-decision-matrix.md`. Quick heuristics: deterministic/blocking → **hook**, LLM-judgment automation → **skill**, delegation with own context → **subagent**, always-needed short rule → **CLAUDE.md**, filetype-scoped rule → **skill with `paths:`**.

**Before surfacing each surviving recommendation, ask yourself:**
- Can I point to the specific file:line that motivates this?
- Would I personally feel the pain if this didn't exist?
- Will this still seem useful 6 months from now, or is it a one-time cleanup?
- Does this pass the "would I actually invoke this?" naming and memory-decay test?

If any answer is "no" or "not sure", drop the recommendation.

Rank the survivors by: (a) evidence strength, (b) frequency of pain, (c) low implementation cost, (d) zero new dependencies. **Tiebreak**: when (a) and (b) are equal, prefer the finding with narrower implementation scope — a 15-line hook beats an 80-line skill at equal evidence, since smaller artifacts face less adoption friction and break trust less if wrong.

**Single-source findings get a stricter bar**: a finding backed by only one signal type (e.g., only a TODO comment, no frequency evidence) must be corroborated by a second signal (emotional language AND a README gotcha documenting the same pain, or a TODO AND co-change coupling). Uncorroborated single-signal findings are dropped.

Take top 5. Ensure at least one is a "remove/simplify" deletion finding.

**If 0 survivors remain after filters:** the repo is already well-tooled. Go to the "No viable recommendations" fallback.

### Phase 3: Present for Approval

*No references needed.*

Show the user a compact ranked list — one line per recommendation:

```
1. [HOOK] PostToolUse on Edit(fish/**/*.fish) → auto-run `fish --no-config -c 'source {file}; exit'`
   Evidence: goto.fish:22-25 has a logic bug the dotfiles-reviewer missed
   Cost: ~15 lines in settings.json, zero deps

2. [SKILL] /stow-check — verify all stow packages' symlinks
   Evidence: CLAUDE.md documents manual `for dir in */; do stow "$dir"; done`; no health check exists
   Cost: ~40 lines, zero deps

3. [CLAUDE.md UPDATE] Remove stale "Active Technologies" section at /Users/tomas/dotfiles/CLAUDE.md:96-103
   Evidence: Go migration completed 2026-01-16, Node.js spec references are stale
   Cost: deletion
...
```

Ask: "Which of these should I generate? (numbers, 'all', 'none', or 'expand N' for more detail on item N)"

**Never generate without explicit approval.** User selects subset. If user requests "expand N", show the full supporting evidence (file contents, shell history cluster, co-change data) before they decide — then re-prompt for their selection.

### Phase 4: Generate Approved Artifacts

**MANDATORY: Load `references/generation-quality-bar.md`. Do NOT load swarm-prompts.md, signal-patterns.md, or artifact-decision-matrix.md during generation.**

Generate artifacts **one at a time** — not batch. For each approved recommendation:
1. Generate the artifact meeting the quality bar below
2. Write to `$WORKSPACE/generated/<name>.md` first
3. Show the user the full content
4. Ask: "Write this to `<target-path>`? (yes/edit/skip)"
5. Move to the next recommendation only after user responds

**Branching on user response:**
- **yes** → write to target path, move to next recommendation
- **edit** → ask one question: "What should change? (one sentence)". Regenerate the artifact with that change applied. Re-show full content. Re-prompt yes/edit/skip. **Max 2 edit rounds per artifact** — if still rejected on round 2, treat as skip.
- **skip** → log as "skipped: <name>" for the final summary. Do not regenerate or re-explain.

Key quality requirements (violations = immediate regeneration):

- **Description field** includes WHAT + WHEN (3-5 scenarios) + KEYWORDS (trigger vocabulary the user actually uses)
- **One primary verb** — if the name needs "and", split it
- **References the user's actual stack** at least 3 times (file paths, tool names, actual conventions from the repo)
- **No filler sections** ("Best Practices", "You are Claude", "Getting Started", "What is X")
- **No hallucinated tools** — only tools that exist in the environment (Read, Write, Edit, Bash, Glob, Grep, Agent)
- **Anti-patterns have reasons** — every "NEVER do X" includes the specific failure mode

### Phase 5: Deliver

*No references needed.*

After each user "yes" in Phase 4:
1. Write to the correct location (usually `~/.claude/skills/<name>/SKILL.md`, `~/.claude/commands/<name>.md`, or `$TARGET/.claude/...`)
2. Tell the user the exact trigger phrase that will activate it
3. For hooks, tell the user to verify `settings.json` loaded it (or, for user-scope, restart Claude Code session)

After all approved artifacts are written, show a summary:
- List of files created with paths
- Workspace path so the user can inspect raw agent artifacts
- One-sentence testing suggestion per artifact

---

## Swarm Mechanics — Hard Rules

These come from production skills (overkill, brainstorm, qa, skill-forge). Violations silently degrade output quality.

- **Agent count cap**: 5 agents in Wave 1. More than 6 per wave degrades synthesis quality — the deprecated `feature` skill cites this as "3 is safer than 5". Resist the urge to add more.
- **`bypassPermissions` is mandatory** on every Agent call. This is the #1 silent failure: agents without write permissions produce nothing and the pipeline silently breaks.
- **`model: "sonnet"` on all research agents**. `haiku` is too shallow for reasoning; `opus` is overkill. Never inherit — always set explicitly.
- **Write artifacts to disk, read from disk**. Agent return messages get truncated. The orchestrator reads files, not messages.
- **Facts not opinions between phases**. Pass file paths and concrete counts to later phases, never severity judgments or rankings from agents.
- **Orchestrator does synthesis**. Never delegate synthesis to a subagent — it needs the full context of all artifacts.
- **Parallel launch**: All 5 Wave 1 agents run in a single message with 5 Agent tool calls. They must not see each other's output.

See `references/swarm-prompts.md` for the exact agent prompt templates to use (they bake in all these rules).

---

## Anti-Patterns (Things the Skill Itself Must Avoid)

1. **NEVER produce more than 5 recommendations** per run. Decision fatigue destroys adoption. If the swarm surfaces 30 candidates, filter to 5.
2. **NEVER recommend something that duplicates existing tooling**. Check `inventory.md` before every recommendation. Duplication destroys trust faster than anything else.
3. **NEVER recommend generic "best practices"** like "add a linter hook" without checking the user doesn't already lint. Generic suggestions score zero knowledge delta.
4. **NEVER skip the deletion category**. LLMs have addition bias — if you don't force "what to remove", you won't see it.
5. **NEVER generate an artifact without file:line grounding in its justification**. Without grounding, the skill is confabulating — surfacing "plausible improvements" from training data rather than this repo. "Your shell history shows `docker compose down && docker compose up --build` ran 15 times in the last month — a `/rebuild` command would save ~30s × 15 = 7.5 min/month" is grounded. "You should add a deploy skill because deployment exists" is not.
6. **NEVER skip the approval gate**. Without per-recommendation approval, the user cannot inspect the evidence before committing — they'll accept a confabulated finding, discover it's wrong, and blame the tool. One bad generated artifact destroys trust for all subsequent runs. Approval is the trust-protection mechanism.
7. **NEVER inflate agent count**. Exactly 5 Wave 1 agents. Synthesis requires holding all 5 artifacts in context simultaneously to cross-reference claims and rank findings — beyond 5, orchestrator attention degrades before coherent rankings form (the deprecated `feature` skill cites 4 as ceiling, "3 is safer than 5"). More agents ≠ more signal.
8. **NEVER let an agent skip the grounding rule**. If an agent prompt lacks "no file path = finding doesn't count", the agent will fill its output with training-data plausibilities instead of repo-grounded findings. The rule must appear in every single agent prompt, not just one.

---

## Fallbacks

| Situation | Action |
|-----------|--------|
| All 5 agents return <3 findings total | **FIRST verify this isn't silent failure**: check every `$WORKSPACE/wave-1/*.md` exists and is >50 lines AND contains a "What I Checked" section AND has file:line citations. If any stub exists → treat as "agent failed" row below. Only after all 5 files have genuine, grounded findings should you conclude the repo is well-tooled. Then: "Your setup is in good shape — here's what I checked." List the 5 lenses with "clean" status. |
| An agent fails / writes stub artifact | Re-run that specific agent ONLY with a narrowed prompt. Add to the prompt: "This is a re-run. Your previous output was too brief. Focus only on [narrowed scope]. The other 4 agents covered [brief fact summary from their findings, not opinions] — do NOT cover those areas." |
| Synthesis finds contradictions between agents | Flag in the Phase 3 presentation with "⚠ Conflicting evidence:" prefix. Show both perspectives with their file:line citations. Let the user decide. |
| 0 survivors after Phase 2 filters | Legitimate case — all findings were anti-signals or duplicates of existing tooling. Tell user: "Agents found N candidates, but all were either [already-handled / one-time-setup / framework-provided / rarely-triggered]. Your setup has no high-signal gaps right now." List the 2-3 strongest dropped findings with their drop reason. |
| Shell history not accessible (CI, fresh machine) | Skip shell-history signal. Rely on Makefile/CI/README/TODO signals. Tell the user which signals were unavailable. |
| User approves 0 recommendations | Fine. Tell user: "No changes made. Run `/claude-improver` again after you've had time to consider." |
| Target repo has no `.claude/` directory | Partial inventory is fine. Note in `inventory.md`: "No `.claude/` found — user-scope artifacts only." Proceed normally. |
| User says "expand N" at approval gate | Show the full supporting evidence for item N (file contents, shell cluster counts, co-change stats). Then re-prompt for selection. |
| Workspace from prior run exists | Create new timestamped workspace. Don't reuse — stale artifacts contaminate synthesis. |

---

## Reference Loading Rules — Phase-Gated

**Do NOT load references at skill startup.** Each reference is large; loading unused ones bloats context and degrades synthesis.

| Phase | MUST load | Do NOT load |
|-------|-----------|-------------|
| Phase 0 (Inventory) | — | all four |
| Phase 1 (Swarm Scan) | `swarm-prompts.md` | signal-patterns, artifact-decision-matrix, generation-quality-bar |
| Phase 2 (Synthesis) | `signal-patterns.md`, `artifact-decision-matrix.md` | swarm-prompts, generation-quality-bar |
| Phase 3 (Present) | — | all four |
| Phase 4 (Generate) | `generation-quality-bar.md` | swarm-prompts, signal-patterns, artifact-decision-matrix |
| Phase 5 (Deliver) | — | all four |

Reference contents:
- [references/signal-patterns.md](references/signal-patterns.md) — 8 signal patterns + 6 anti-signals + grep commands + "Would I invoke this?" test + cost-of-suggestion framework
- [references/artifact-decision-matrix.md](references/artifact-decision-matrix.md) — full "if user needs X, use Y because Z" decision matrix + authoring anti-patterns per type
- [references/generation-quality-bar.md](references/generation-quality-bar.md) — description trigger patterns, 9 slop anti-patterns, skill-judge scoring targets
- [references/swarm-prompts.md](references/swarm-prompts.md) — ready-to-use agent prompt templates with grounding rules baked in
