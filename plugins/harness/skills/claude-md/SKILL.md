---
name: claude-md
description: "Generate, audit, and optimize CLAUDE.md files for Claude Code projects. Use when: (1) user asks to create, generate, write, or set up a CLAUDE.md, (2) user says /claude-md, (3) user wants to improve Claude Code instruction-following or compliance, (4) user asks why Claude isn't following instructions, (5) user asks how to enforce behaviors (hooks vs CLAUDE.md vs rules), (6) user mentions 'project instructions', 'Claude Code setup', 'instruction budget', or 'token budget'. Covers: enforcement hierarchy (hooks/rules/CLAUDE.md), path-scoped rules, 100-line methodology, Boris Cherny approach, anti-patterns that waste instruction budget."
---

# CLAUDE.md Generator

Generate production-grade CLAUDE.md files that maximize instruction-following within tight token budgets.

## The Core Constraint

Claude Code's system prompt consumes ~50 of the ~150-200 instructions a frontier model reliably follows. Your CLAUDE.md budget: **roughly 100 additional instructions** before compliance degrades uniformly across ALL content.

**Target: 80-100 lines, under 2,500 tokens.** Boris Cherny (Claude Code creator) uses exactly this size. Files over 200 lines cause measurable degradation.

## The Single Test

For every line: **"Would Claude make a mistake without this?"** If no, don't write it. This eliminates 60-80% of typical CLAUDE.md content. Claude already knows standard conventions, common patterns, and anything it can infer from config files.

## Phase 1: Project Intelligence Gathering

Explore the project, then answer these questions — they directly map to CLAUDE.md sections:

| Question | Where to Look | CLAUDE.md Impact |
|----------|---------------|------------------|
| What commands aren't standard? | `package.json` scripts, Makefile, Taskfile | → Commands section (only non-obvious ones) |
| What conventions differ from defaults? | Linter configs, tsconfig, pyproject.toml | → Conventions section (only the diffs) |
| What has caused bugs or confusion? | Existing CLAUDE.md, README warnings, git history | → Gotchas section (highest-value content) |
| What Claude Code config exists? | `.claude/settings.json`, `.claude/rules/`, `.claude/agents/` | → What NOT to duplicate |
| Is this a monorepo or multi-area project? | `packages/`, `apps/`, `services/` dirs | → Suggests path-scoped rules over root CLAUDE.md |

**Critical:** Read the existing CLAUDE.md first if one exists — preserve team knowledge, don't replace it.

### Scenario Router

| Situation | Approach |
|-----------|----------|
| **No CLAUDE.md exists** | Generate from scratch using Phase 2 |
| **CLAUDE.md exists but is under 100 lines** | Audit, suggest targeted additions only |
| **CLAUDE.md exists but is 100-300 lines** | Audit, prune redundant content, restructure for compliance |
| **CLAUDE.md exists and is 300+ lines** | Emergency triage: for each rule, apply the Content Decision Tree — area-specific rules → `.claude/rules/`, enforcement-critical → hooks, inferrable from code → delete, remainder stays in root. Target: root under 100 lines. |
| **Monorepo with multiple teams** | Thin root CLAUDE.md (~30 lines) + `.claude/rules/<area>.md` per subsystem. Shared utilities touched by multiple teams: rules go in root only. If subsystem rules conflict with root, root wins. |
| **Empty/new project** | Minimal skeleton: project name + commands + one gotcha placeholder |
| **CLAUDE.md exists and appears correct** | Run the pruning test: generate output WITH and WITHOUT each rule group. If identical, mark for deletion. Report: "X of Y sections appear deletable." |

## Phase 2: Generate the CLAUDE.md

### Placement Strategy — Primacy and Recency Bias

LLMs attend more to the beginning and end of prompt content:

```
Lines 1-5:    Most critical rules (highest compliance zone)
Lines 6-80:   Conventions, commands, architecture
Lines 80-95:  Gotchas and warnings
Lines 95-100: Repeat the 2-3 most violated rules (recency zone)
```

### Writing Rules — Phrasing for Maximum Compliance

Before phrasing any rule, ask: **"Am I stating a fact about how this project works, or issuing a command?"** Facts transfer more reliably than commands.

**Declarative over imperative.** State facts, not commands.
```
BAD:  "NEVER use default exports"
GOOD: "Exports: named only (no default exports)"
```

**Positive over negative.** Tell Claude what TO do — cuts violations ~50%.
```
BAD:  "Don't add docstrings to unchanged code"
GOOD: "Add docstrings only to new functions you write"
```

**Specific over vague.** Remove all judgment calls from Claude.
```
BAD:  "Be brief when appropriate"
GOOD: "Maximum 3 paragraphs unless showing code"
```

**One rule per line.** Dense, scannable. No prose paragraphs.

**Emphasis sparingly.** Use IMPORTANT/MUST only if the rule would go in lines 1-5 AND has historically been violated. If you can't confirm past violations, use declarative phrasing — emphasis loses power when overused.

### Content Decision Tree

```
Does Claude already do this correctly without being told?
  YES → Don't write it
  NO  ↓

Can Claude infer this from project config files?
  YES → Don't write it
  NO  ↓

Must this happen 100% of the time, zero exceptions?
  YES → Make it a hook, not a CLAUDE.md line
  NO  ↓

Does this apply to every session or only specific file areas?
  SPECIFIC → .claude/rules/<topic>.md with paths: frontmatter
  EVERY    → CLAUDE.md
```

### The Enforcement Hierarchy

| Mechanism | Reliability | Use For |
|-----------|------------|---------|
| Hooks (PreToolUse/PostToolUse) | Deterministic | Non-negotiable: lint, test, format, security |
| `.claude/rules/` with `paths:` | High (conditional) | Area-specific: API conventions, frontend patterns |
| CLAUDE.md | Advisory | Universal: project context, conventions, preferences |
| Skills | On-demand | Domain knowledge, workflows, recipes |

CLAUDE.md is advisory. The `<system-reminder>` wrapper tells Claude the content "may or may not be relevant." For anything that MUST happen, use hooks.

### Structure

Most projects need 40-60 lines. Required section: **Behavioral Rules** (the four Karpathy rules — see below, mandatory in every CLAUDE.md). Other sections as needed: **Commands** (non-obvious only), **Architecture** (only if non-self-evident), **Conventions** (only diffs from defaults), **Gotchas** (highest-value section — things that caused real bugs). Omit empty sections except Behavioral Rules. Put the 2-3 most critical project-specific rules at lines 1-5 (primacy) and repeat them at lines 95-100 (recency); the Karpathy rules belong in the primacy zone.

### Karpathy Behavioral Rules (MANDATORY — include verbatim in every CLAUDE.md)

These four rules MUST appear in every CLAUDE.md this skill generates or audits. They address documented LLM coding failures and pass the "Would Claude make a mistake without this?" test for every codebase. Do not paraphrase, do not omit, do not mark optional. If auditing an existing CLAUDE.md that lacks them, add them.

- Surface assumptions. When multiple interpretations exist, ask — don't pick silently.
- Minimum code that solves the problem. No speculative abstractions, flags, or features.
- Surgical changes only. Every edited line traces to the request. No drive-by refactors, reformatting, or style shifts.
- Define verifiable success criteria before implementing. For bugs: write the reproducing test first.

Place under a `## Behavioral Rules` (or equivalent) heading near the top of the file (lines 1-15, primacy zone). Source: Karpathy's LLM coding pitfalls — [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) ([EXAMPLES.md](https://github.com/forrestchang/andrej-karpathy-skills/blob/main/EXAMPLES.md)). Only carve-out: if the project already enforces an identical rule via a hook (deterministic), note that hook and skip the duplicate line — but do not skip merely because the team "knows" it.

## Phase 3: Suggest Companion Config

Trigger companion config only when Phase 1 found these signals:

| Signal Found | Action |
|-------------|--------|
| 2+ distinct subsystems with different conventions | Path-scoped `.claude/rules/<area>.md` per subsystem |
| User says "must always happen", "guarantee", or "never skip" | Hook (PreToolUse/PostToolUse) |
| Project uses sub-agents, has latency or cost concerns | Model routing in agent `.md` frontmatter |
| Single-area project, conventions apply everywhere | No companion config — root CLAUDE.md is sufficient |

If none of these signals are present, do not suggest companion config. Say so explicitly.

**Path-scoped rules** syntax:
```yaml
# .claude/rules/api-conventions.md
---
paths:
  - "src/api/**/*.ts"
---
# API patterns
- All endpoints include input validation
- Error format: { error: { code, message } }
```

**Hooks** — when the user mentions behaviors that must be guaranteed:
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "./scripts/pre-commit-check.sh" }]
    }]
  }
}
```

**Agent model routing** — advisory in CLAUDE.md, enforced in frontmatter:
```markdown
## Subagent Model Selection
- Explore/search agents: haiku
- Code review, testing: sonnet  
- Complex implementation: opus (default)
```
Note: CLAUDE.md model routing is advisory only (~93.8% of tokens default to Opus without enforcement). For real enforcement, add `model: haiku` to agent `.md` frontmatter files.

**Caveat:** The hook/rule YAML and JSON syntax examples above reflect current Claude Code conventions. Verify against current docs if syntax has evolved.

## NEVER Do These

- **NEVER rely on CLAUDE.md for enforcement** — the `<system-reminder>` wrapper tells Claude it "may or may not be relevant." If it must happen every time, make it a hook. Engineers who skip this discover it the hard way.
- **NEVER embed code snippets** — they go stale after any refactor. Use `file:line` references instead ("See `src/auth.ts:42`"). Snippets are also token-expensive.
- **NEVER import large files with @** — `@docs/architecture.md` (500 lines) loads into every session, burning your instruction budget before a single actual rule is read.
- **NEVER put everything in root CLAUDE.md for multi-area projects** — use `.claude/rules/<area>.md` with `paths:` frontmatter. A 150-line root CLAUDE.md degrades ALL instructions uniformly; 40-line root + scoped rules does not.
- **NEVER include time-sensitive facts** ("as of v2.1 this API is deprecated") — CLAUDE.md persists across months. Stale gotchas actively mislead Claude and are worse than having no gotcha.
- **NEVER assume a rule is working by intuition** — test empirically: generate output without the rule, then with it. If identical, delete the rule. If different but the "with" output is worse, the rule is actively harmful — also delete. Run this test during initial generation and monthly reviews. Most CLAUDE.md files are 30-40% deletable.
- **NEVER write rules Claude can infer from config files** — Claude reads `package.json`, `tsconfig.json`, `.eslintrc` directly. Duplicating their content is pure token waste with zero compliance benefit.
- **NEVER omit the four Karpathy Behavioral Rules** — they are mandatory in every CLAUDE.md this skill produces or audits (see "Karpathy Behavioral Rules" above). The pruning test does NOT apply to them; they stay even if the team "already knows" them. The only carve-out is replacement by an identical deterministic hook.

## After Generation

1. Report the generated CLAUDE.md size (~X lines / ~Y tokens)
2. Suggest the correction → rule loop: "After every mistake, tell Claude: 'Update CLAUDE.md so you don't repeat this.' Claude is skilled at writing its own rules."
3. Suggest the pruning cadence: review monthly, apply the pruning test to every line
4. If hooks were suggested: "Hooks are deterministic — they execute regardless of what Claude decides. CLAUDE.md is advisory. Use hooks for anything that must happen 100% of the time."
