# harness

A deterministic harness for Claude Code: lifecycle hooks that enforce what prose only requests, a script toolbox that owns numbering, briefs and gates, saved workflows for fan-out with independent review, a small set of agents and commands that usage data actually justifies, and a rewritten `flow` pipeline that reads one step at a time.

The code lives in a stowed dotfiles package (`~/.dotfiles/claude/.claude/` → `~/.claude/`). This repo holds the research it was built from, the frozen spec, and generated reference docs. Status: built 4 September 2026 by a fleet of Sonnet implementers with three adversary lenses per unit; see `docs/SPEC.md` for the contracts and `docs/research/06-adversary-panel-decisions.md` for what the panel changed before anything was built.

## Why

Three facts about the setup this replaced, measured on the day:

| Fact | Consequence |
|---|---|
| `settings.json` had no `hooks` key; `~/.claude/hooks` did not exist | ~40 quality rules were prose the model could skip; 0 were enforced |
| `~/.claude/CLAUDE.md` was never symlinked | none of the global rules had ever loaded, on either machine |
| 66 skills, ~50,000 description chars | 39 skill descriptions silently dropped from the session index (1% listing budget); those skills could not auto-trigger |

The research consensus (vendor docs, independent measurements, thirteen framework codebases read at source level) reduces to one line: **give the agent a check it can run, and make the check impossible to skip.** Everything here is a way of doing that.

## What is in this repo

This repo is a Claude Code **plugin marketplace**. `harness` is the core plugin; the others bundle domain skills so they load only where enabled.

```
.claude-plugin/marketplace.json
plugins/
├── harness/           hooks/ (+ hooks.json) · scripts/ · workflows/ · harness-templates/ · bin/harness · skills/ (flow suite, qa, audit, fix, ultracode, …)
├── design/            design, impeccable, ui-ux-pro-max, mobile-design, polish, showcase, ui-animation, explainer
├── finance/           alpha-hunt, portfolio, investment, etoro
├── aws/               aws-explore, aws-lambda-microvms, strands-agentcore, strands-steering-hooks, agui-strands, sst
├── web/               seo-audit, google-ads, figma-to-strapi, website-cloner, api-explorer, agent-browser
└── tooling/           new-project, node-cli-builder, python-code-style, clean-code, gh-cli, version-audit, …
docs/                  research, SPEC, decisions, generated reference
```

User-level config stays in the dotfiles: `~/.claude/{CLAUDE.md, settings.json, agents/, commands/}`. Hooks register from the plugin's `hooks.json`, so `settings.json` carries no hooks block (the doctor reports a double registration if it does).

Live loading on a machine with this checkout: `~/.claude/skills` is a symlink to `plugins/`, so each plugin auto-loads in place as `<name>@skills-dir` and edits are live (`git pull` is the sync). `~/.claude/{hooks,scripts,harness-templates}` link into `plugins/harness/`. Workflows register as `harness:<name>`.

## The spine (always on)

| Moment | Hook | Effect |
|---|---|---|
| Session start | `session-context.sh`, `codebase-map.sh` | branch, dirty count, last commits, head of PROGRESS.md, any loosened thresholds; optional codebase map |
| Every prompt | `turn-stamp.sh` | stamps the turn so the Stop gate scopes itself to what changed |
| Before a shell command | `git-guard.sh` | denies force-push, hard reset, `clean -f`, `branch -D`, `commit --no-verify`, `rm -rf` of roots; quote-aware; `--force-with-lease` allowed |
| After every edit | `format-lint.sh` · `size-guard.sh` · `tamper-notice.sh` | formats; flags files > 400 lines / functions > 60 with a teaching message; puts newly added `.skip`/`xfail` or loosened thresholds on the record |
| Turn end | `stop-gate.sh` | runs tests related to the change (full sweep every 15 min); refuses to end the turn while red; wedge valve after three identical failures; honours `stop_hook_active` |
| Compaction | `pre-compact-backup.sh`, `postcompact-context.sh` | transcript backup; "treat the summary as untrusted" reminder |
| Subagent end | `subagent-log.sh` | logs the final message so a lost report is recoverable |
| Permission / idle | `notify.sh` | desktop notification (notify-send / osascript) |

Per-project knobs in `.claude/harness.json`: `maxFileLines`, `maxFuncLines`, `stopGate` (`scoped` | `true` | `false`), `stopGateFullEverySec`, `sizeGuard`, `formatOnEdit`, `ignore`, `codebaseMap`.

## The loop (instead of "throw a goal at /flow")

1. Name the task, pick a tier. One-sentence diff → just do it; the spine still fires.
2. Multi-file or uncertain → plan in plan mode, approve the plan, fresh session to implement, `review-diff` before done.
3. Real feature with a spec and browser verification → `/flow` v2 (judge opt-in, waves for independent slices, `build-slices` in Workflow mode, deepen split out).
4. Mechanical migration across independent files → `ultracode`, only with an exhaustive suite as referee.
5. Always: audit the test/CI config diff by hand before the code diff; commit small; `/clear` after two failed corrections; `/wrap` before leaving.
6. When Claude gets something wrong: `/lesson <what went wrong>`. It walks test → hook → script → skill → CLAUDE.md, writes the most deterministic rung red-then-green, has an adversary try to bypass it, and records the ruling in PROGRESS.md. The stop gate says so itself from the second identical block.

Full version with justifications: [`docs/research/01-harness-engineering-2026.md`](docs/research/01-harness-engineering-2026.md) §4.

## Install (each machine)

```bash
git clone git@github.com:TomasPalsson/harness.git ~/Desktop/Projects/harness   # or set HARNESS_REPO
git clone git@github.com:TomasPalsson/dotfiles.git ~/.dotfiles   # or set DOTFILES=<path>; install refuses to run without one
node ~/Desktop/Projects/harness/plugins/harness/bin/harness install   # links ~/.claude/* and ~/.local/bin/harness, then runs doctor
# An existing real ~/.claude/agents or /commands is merged (your files stay); a real settings.json is kept;
# a real CLAUDE.md is linked when identical, otherwise kept and reported (--force replaces it, backup kept).
harness doctor
cd <any project> && harness init && git add REVIEW.md PROGRESS.md .claude/harness.json
harness next   # prints the next command to run (PROGRESS.md resume line, flow state, dirty tree)
```

Without a checkout: `claude plugin marketplace add TomasPalsson/harness && claude plugin install harness@harness` (copy mode; `claude plugin update` to refresh).

Tests: `bash plugins/harness/hooks/tests/run.sh` and `bash plugins/harness/scripts/tests/run.sh` (zero dependencies; portability grep for bash 3.2 / BSD; shellcheck when installed).

## Research

| Doc | What it settles |
|---|---|
| [01 Harness engineering 2026](docs/research/01-harness-engineering-2026.md) | 12 ranked principles with evidence grades, what changed since 2025, the gap audit, the loop, the hooks |
| [02 Frameworks at source level](docs/research/02-frameworks-source-review.md) | spec-kit, OpenSpec, BMAD, superpowers, GSD, ccpm, Agent OS, Conductor, HumanLayer, Anthropic plugins, hooks-mastery, tdd-guard/checkwash: what recurs, what to steal, what not to copy |
| [03 Agents, commands, memory, /goal](docs/research/03-agents-commands-memory-goal.md) | which agents earn their context cost (usage audit: 42 of 67 skills never named), memory policy, /goal templates, advanced hooks, a 40-item downsides register |
| [04 Codebase maps and graphs](docs/research/04-codebase-maps-and-graphs.md) | graphify/GitNexus/Serena/LSP/repo-map/memory compared; the explorer brief is the measured win |
| [05 Beads](docs/research/05-beads.md) | not adopted; which of its ideas were borrowed |
| [06 Panel decisions](docs/research/06-adversary-panel-decisions.md) | 38 findings from seven adversary lenses, adjudicated before the build |

Raw per-dimension reports with independent source checks: [`docs/research/raw/`](docs/research/raw/).

## Downsides accepted (short list)

- Hooks are a regex blocklist over a command string, not a security boundary; CI remains the backstop.
- `PostToolUse` hooks see only `Edit|Write`; files written through Bash heredocs are caught at Stop, not at write time.
- Size thresholds (400/60) are a defensible mid-band, not a validated number; tune per repo.
- The skill index still exceeds the 1% listing budget; the fraction was raised to 2% (≈12K tokens per session). Moving domain skills to a per-project marketplace is the real fix and is still open.
- `/rewind` skips symlinked paths; git is the only undo for the harness itself.

Full register: `docs/research/03-agents-commands-memory-goal.md` §7 and `docs/decisions.md`.
