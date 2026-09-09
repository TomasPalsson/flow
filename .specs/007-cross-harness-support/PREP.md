# Prep — Cross-harness support (AGENTS.md / ~/.agents)
Gathered: 2026-09-09 · Questions: 2 of 12 · Route: dispatch · Status: ready for spec

## Decisions
- D-01 Hooks travel to opencode only. Not Antigravity, not Codex, not Cursor, not Grok, not Copilot. — user, Q1
- D-02 Strategy is the SHIM, not a rewrite: thin TypeScript plugin hooks that synthesize Claude-shaped hook JSON, pipe it to the EXISTING bash scripts on stdin, and act on their stdout. The 3,067 lines of bash and 15 shell test files stay the single source of truth. — user, Q2

## Not this
- Antigravity hook/plugin packaging (`~/.gemini/antigravity-cli/`, its own `hooks.json`). No Codex/Cursor/Grok/Copilot hook shims.

## Discretion
- Plugin file layout and naming inside the opencode plugin dir.
- Whether one plugin file registers all hooks or one file per hook.
- How the Claude-shaped JSON is synthesized per event (field-by-field mapping).
- Install mechanism for the plugin (symlink vs npm vs checked-in file).

## Assumptions
- A-01 opencode already reads `~/.claude/skills` and `~/.agents/skills` as skill roots, so flow's six plugins load there today with zero work — evidence: https://opencode.ai/docs/skills/ — confidence: high — unconfirmed
- A-02 Antigravity does NOT read `~/.claude`; global skills live at `~/.gemini/antigravity-cli/skills/`, workspace skills at `.agents/skills/`, plugins at `~/.gemini/antigravity-cli/plugins/<name>/` as `plugin.json` + optional `hooks.json` + `skills/ agents/ rules/` — evidence: https://antigravity.google/docs/cli/plugins/ — confidence: high — unconfirmed
- A-03 flow's SKILL.md frontmatter is already portable: `name` + `description` only, which is exactly opencode's required pair, and unknown fields are ignored — evidence: plugins/flow/skills/next/SKILL.md:1-4 — confidence: high — unconfirmed
- A-04 The 14 lifecycle hooks are the only genuinely non-portable layer: bash reading Claude's hook JSON from stdin via `hook_field`, registered against Claude-shaped events. opencode hooks are TS/JS modules (`tool.execute.before/after`, `session.*`) in `~/.config/opencode/plugin/`; Antigravity uses its own `hooks.json` — evidence: plugins/flow/hooks/lib/hookout.sh:1-20, plugins/flow/hooks/hooks.json — confidence: high — unconfirmed
- A-05 This repo already ships a working multi-harness hook pattern: the impeccable skill writes per-project manifests for Claude Code, Codex, Cursor, Grok Build and Copilot from one `hook-admin.mjs` — the pattern to copy, not invent — evidence: plugins/design/skills/impeccable/reference/hooks.md:17 — confidence: high — unconfirmed
- A-06 `flow` the CLI is already harness-agnostic (node ≥18, zero deps, reads state off disk). Only `flow loop run` spawns `claude -p` — 2 occurrences in the whole plugin — evidence: plugins/flow/bin/flow:1-10 — confidence: high — unconfirmed
- A-07 `flow install` links only into `~/.claude/*` and `~/.local/bin`; nothing today writes `AGENTS.md`, `~/.agents/`, or any other harness home — evidence: plugins/flow/bin/flow:2316 (cmdInstall) — confidence: high — unconfirmed
- A-08 No `AGENTS.md` exists anywhere in this repo, and `CLAUDE.md` is named 127 times in plugin prose; `CLAUDE_PROJECT_DIR` 215 times and `CLAUDE_PLUGIN_ROOT` 103 times — the prose itself is Claude-shaped, not just the wiring — evidence: repo-wide grep — confidence: high — unconfirmed

## Verify
- In a real opencode session in a repo with a failing test: the agent cannot end its turn while red
  (stop-gate fires), and a destructive VCS command is denied by the guard hook. Stated by prep, not
  user-confirmed - the user cut the interview short at Q2.

## Open
- Q: does opencode have ANY event that can block turn end? If not, stop-gate.sh has no host and the
  port delivers deny-hooks only. -> settled by the in-flight research, not by the spec.
- Q: are hooks awaited, so a shim can synchronously run a subprocess and act on its exit code? -> same research.
