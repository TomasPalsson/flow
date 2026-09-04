# humanlayer-ace

## What it is
The `.claude/commands/` + `.claude/agents/` directory inside HumanLayer's own monorepo (github.com/humanlayer/humanlayer) — the dogfooded implementation of the research→plan→implement→validate loop known as "Advanced Context Engineering for Coding Agents" (ACE-FCA), authored by HumanLayer founder Dex Horthy. It is not a packaged plugin; it's a set of markdown slash-commands and subagent definitions checked into the repo's `.claude/` directory, paired with a separate git-backed "thoughts" system (`hlyr thoughts ...`) for durable, synced spec/plan documents.

Repo: https://github.com/humanlayer/humanlayer (no stars shown in `git log`/clone metadata — not fetched from GitHub API).
Last commit at clone time: `Thu Jun 18 20:27:53 2026 -0700` (`git log -1 --format=%cd`, clone was shallow `--depth 1`).

## Workflow it implements
The actual sequence, as coded in `.claude/commands/*.md`:

1. **Research** — `/research_codebase` (`.claude/commands/research_codebase.md`, 213 lines). Reads any files the user names FULLY in the main context, then fans out read-only subagents (`codebase-locator`, `codebase-analyzer`, `codebase-pattern-finder`, `thoughts-locator`, `thoughts-analyzer`, optionally `web-search-researcher`) in parallel. Explicitly forbidden from critiquing or proposing changes — "ONLY describe what exists." Writes `thoughts/shared/research/YYYY-MM-DD-ENG-XXXX-description.md`.
2. **Plan** — `/create_plan` (`.claude/commands/create_plan.md`, 449 lines). Interactive, multi-step: read ticket/research fully → spawn locator/analyzer subagents → present findings + open design questions → get buy-in on phase structure → only then write the full plan document with per-phase automated/manual success criteria. Explicitly bans shipping a plan with open questions.
3. **Implement** — `/implement_plan` (`.claude/commands/implement_plan.md`, 84 lines). Reads the plan (checking existing `- [x]` boxes for resumability) plus the original ticket, implements phase by phase, runs the phase's automated checks, checks off items in the plan file via `Edit`, and pauses for human manual verification between phases unless told to run multiple phases consecutively.
4. **Validate** — `/validate_plan` (`.claude/commands/validate_plan.md`, 166 lines). Works from git history + `make check test` + parallel verification subagents to produce a Matches-Plan / Deviations / Potential-Issues / Manual-Testing-Required report, independent of whatever session did the implementing.
5. **Commit / PR** — `/commit` (43 lines, explicitly forbids Claude attribution/co-author lines) and `/describe_pr.md` close the loop.

A second, fully autonomous variant chains these through Linear as a state machine and launches each phase as a **separate, fresh CLI session** rather than continuing in one context window:
- `/ralph_research` moves a Linear ticket `research needed → research in progress → research in review`, writes the research doc, syncs, attaches it to the ticket.
- `/ralph_plan` moves `ready for spec → plan in progress → plan in review`, requires the research doc to exist, writes the plan.
- `/ralph_impl` moves `ready for dev → in dev`, requires a linked plan to exist (exits back to "ready for spec" if not), then does:
  ```
  ./hack/create_worktree.sh ENG-XXXX BRANCH_NAME
  humanlayer-nightly launch --model opus --dangerously-skip-permissions --dangerously-skip-permissions-timeout 15m \
    --title "implement ENG-XXXX" -w ~/wt/humanlayer/ENG-XXXX \
    "/implement_plan and when you are done implementing and all tests pass, read ./claude/commands/commit.md and create a commit, then read ./claude/commands/describe_pr.md and create a PR, then add a comment to the Linear ticket with the PR link"
  ```
  (`.claude/commands/ralph_impl.md:31`)
- `/oneshot` and `/oneshot_plan` chain research→plan→impl end-to-end by calling `SlashCommand()` and re-launching new `humanlayer launch` sessions between phases (`.claude/commands/oneshot.md`, `.claude/commands/oneshot_plan.md`).
- Manual "handoff" path for mid-session compaction: `/create_handoff` writes a compact summary doc and tells the user to resume with `/resume_handoff path/to/handoff.md` in a brand-new session (`.claude/commands/create_handoff.md`, `.claude/commands/resume_handoff.md`).

## Artifacts it produces
All under `thoughts/` (a separately git-synced directory, not the code repo), named `YYYY-MM-DD[-ENG-XXXX]-description.md` with YAML frontmatter (`date`, `researcher`, `git_commit`, `branch`, `repository`, `topic`, `tags`, `status`, `last_updated`, `last_updated_by`).

**Research doc template** (`.claude/commands/research_codebase.md:99-155`) headings:
```
## Research Question
## Summary
## Detailed Findings
## Code References
## Architecture Documentation
## Historical Context (from thoughts/)
## Related Research
## Open Questions
```

**Plan doc template** (`.claude/commands/create_plan.md:182-277`) headings — this is the load-bearing artifact:
```
# [Feature/Task Name] Implementation Plan
## Overview
## Current State Analysis
## Desired End State
### Key Discoveries:
## What We're NOT Doing
## Implementation Approach
## Phase 1: [Descriptive Name]
### Overview
### Changes Required:
#### 1. [Component/File Group]
### Success Criteria:
#### Automated Verification:
- [ ] ...: `make ...`
#### Manual Verification:
- [ ] ...
## Phase 2: [Descriptive Name]
...
## Testing Strategy
### Unit Tests:
### Integration Tests:
### Manual Testing Steps:
## Performance Considerations
## Migration Notes
## References
```
Each phase carries the split success-criteria block verbatim; the plan file itself is later edited in place (`- [x]`) by `/implement_plan` as a checklist.

**Handoff doc template** (`.claude/commands/create_handoff.md:27-65`) headings:
```
# Handoff: ENG-XXXX {very concise description}
## Task(s)
## Critical References
## Recent changes
## Learnings
## Artifacts
## Action Items & Next Steps
## Other Notes
```

## Deterministic vs prompt

| Mechanism | Enforced by script/hook/CLI | Asked of the model in prose |
|---|---|---|
| Thoughts dir separation from code repo | `hlyr thoughts init/sync` (`hlyr/src/commands/thoughts/*.ts`) + git pre/post-commit hooks (per `hlyr/THOUGHTS.md`) that block `thoughts/` from being committed to the code repo and auto-sync it to a separate thoughts repo | — |
| Filename/date/commit/branch metadata for every doc | `hack/spec_metadata.sh` (prints date, git commit, branch, repo name, timestamp) | Model is told to "run the script" and copy its output into frontmatter — no enforcement that it actually did |
| Worktree isolation per ticket | `hack/create_worktree.sh` — creates git worktree, copies `.claude/`, runs `make setup`, fails hard and tears down the worktree if setup fails | — |
| Automated success-criteria execution | `make check test`, `make migrate`, `golangci-lint run` etc. — real shell commands | The *split* between automated vs manual criteria, and which commands map to which phase, is entirely prose convention in `create_plan.md` |
| Fresh-context compaction between phases | `humanlayer-nightly launch` / `npx humanlayer launch` — a brand-new CLI process/session per phase (`ralph_impl.md:31`, `oneshot.md`) | Handoff *content* (what to carry forward) is entirely prose-authored by the model per the handoff template |
| Ticket state machine (research needed → ... → in dev → ...) | Linear MCP tool calls (move status) | The rule "only work on ONE item, the highest-priority SMALL/XS" and "EXIT IMMEDIATELY if none" is prose instruction, not code-enforced |
| Plan checkbox tracking during implementation | Actual `- [ ]`/`- [x]` markdown edited via the `Edit` tool in the plan file | Whether to trust existing checkmarks vs re-verify is a prose judgment call ("Resuming Work" section, `implement_plan.md:78-82`) |
| No-Claude-attribution commits | — | Pure prose instruction in `commit.md` ("NEVER add co-author information") — nothing prevents the model from ignoring it |
| Pause for manual verification between phases | — | Entirely prose: "pause here for manual confirmation... do not check off items in the manual testing steps until confirmed by the user" (`create_plan.md:240`, `implement_plan.md:50-65`) — no hook blocks the model from proceeding anyway |

## Mechanisms worth stealing

1. **Split automated/manual success criteria per phase, written as literal shell commands, not descriptions.**
   Problem solved: vague "should work" acceptance criteria that can't be checked deterministically or resumed after a compaction/restart.
   Path: `.claude/commands/create_plan.md:225-238`
   ```
   #### Automated Verification:
   - [ ] Migration applies cleanly: `make migrate`
   - [ ] Unit tests pass: `make test-component`
   ...
   #### Manual Verification:
   - [ ] Feature works as expected when tested via UI
   ```
   Fit for a solo dotfiles harness: any `/plan` or `/feature`-style skill should force every phase's Definition-of-Done into copy-pasteable commands (`make check`, a specific `curl`, a specific test file) rather than prose, so a fresh session — or you, six weeks later — can re-verify without re-deriving intent.

2. **Fresh session per phase, handed only a document — not scrollback.**
   Problem solved: context rot / the model losing the plot over a long single session; this is the actual "frequent intentional compaction" mechanism, and it's not summarization inside one window, it's literally spawning a brand-new process per phase.
   Path: `.claude/commands/ralph_impl.md:31`, `.claude/commands/oneshot.md`
   ```
   humanlayer-nightly launch --model opus --dangerously-skip-permissions --dangerously-skip-permissions-timeout 15m \
     --title "implement ENG-XXXX" -w ~/wt/humanlayer/ENG-XXXX "/implement_plan and when you are done ..."
   ```
   Fit: for long-running dotfiles/agent tasks, a "handoff" skill that writes a small doc and then literally starts a new Claude Code session (or new subagent) pointed only at that doc — instead of trying to keep one context alive across a multi-hour task — maps directly onto the existing `EnterWorktree`/session-spawning tools available here.

3. **The handoff document as the compaction artifact, with an explicit anti-pattern warning against large code snippets.**
   Problem solved: handoffs that either omit critical context or bloat themselves back into a full transcript.
   Path: `.claude/commands/create_handoff.md:92-96`
   ```
   - **avoid excessive code snippets**. ... Prefer using `/path/to/file.ext:line` references that an agent can follow later
   ```
   Fit: a personal "checkpoint" skill for long dotfiles/config work that writes Task/Learnings/Artifacts/Next-Steps to a scratch file and references line numbers instead of pasting diffs.

4. **Read-only, non-evaluative subagents with a hard-enforced "documentarian, not critic" contract.**
   Problem solved: research subagents that go off-script and start "fixing" things or making judgment calls that pollute the research phase with premature opinions.
   Path: `.claude/agents/codebase-locator.md:10-16`, repeated near-verbatim in `codebase-analyzer.md`/`codebase-pattern-finder.md`
   ```
   ## CRITICAL: YOUR ONLY JOB IS TO DOCUMENT AND EXPLAIN THE CODEBASE AS IT EXISTS TODAY
   - DO NOT suggest improvements or changes unless the user explicitly asks for them
   ```
   Fit: any research/locator subagent definition here should carry the same explicit negative-constraint list — cheap to add, meaningfully reduces scope creep in fan-out research.

5. **"No open questions in the final plan" hard rule.**
   Problem solved: plans that ship with unresolved ambiguity, which then surfaces mid-implementation as a stall.
   Path: `.claude/commands/create_plan.md:338-343`
   ```
   6. **No Open Questions in Final Plan**:
      - If you encounter open questions during planning, STOP
      - Research or ask for clarification immediately
      - Do NOT write the plan with unresolved questions
   ```
   Fit: directly portable to `/flow-spec`/`/better-plan`-style skills already in this dotfiles setup — a gate before "plan approved" that scans for `?` / TBD markers.

6. **Ticket-status-as-orchestration-state via Linear MCP, with a hard "only touch ONE ticket, smallest first" throttle.**
   Problem solved: an autonomous loop grabbing too much work at once or losing track of what stage a task is in — the kanban column *is* the state machine, no separate DB needed.
   Path: `.claude/commands/ralph_impl.md:15,33` — "select the highest priority SMALL or XS issue... EXIT IMMEDIATELY if none... only work on ONE item"
   Fit: for a solo dev without Linear, the same pattern maps onto GitHub issue labels or even a flat `thoughts/queue/*.md` directory with a status field — cheap, inspectable, resumable state.

7. **Plan file doubles as the progress tracker (checkboxes edited in place), separate from ephemeral TodoWrite.**
   Problem solved: losing track of implementation progress across a restart, when TodoWrite state doesn't survive a new session but a file does.
   Path: `.claude/commands/implement_plan.md:12,49,79-82` — "check for any existing checkmarks", "Check off completed items in the plan file itself using Edit", "If the plan has existing checkmarks: Trust that completed work is done, Pick up from the first unchecked item".
   Fit: a durable, git-tracked checklist file is a stronger resumability primitive than any in-session todo list; worth adopting for any multi-session dotfiles automation.

8. **Worktree-per-task with fail-closed setup verification.**
   Problem solved: parallel/autonomous agent work stepping on the main working tree, or building on a broken base.
   Path: `hack/create_worktree.sh:93-101` — creates the worktree, runs `make setup`, and on failure force-removes the worktree and branch and exits nonzero rather than leaving a half-built environment around.
   Fit: directly reusable shape for any dotfiles automation that spins up agent sessions against a repo — refuse to hand off work into an environment that doesn't build.

## Weaknesses / ceremony cost
- **Lines of prompt loaded per invocation of the core loop**: `research_codebase.md` (213) + `create_plan.md` (449) + `implement_plan.md` (84) + `validate_plan.md` (166) = **912 lines** just for the four core commands, plus the root `CLAUDE.md` (88 lines) always in context = ~1000 lines before any actual research content is read. `create_plan.md` alone is 449 lines / 14.7KB of prose for a single slash command.
- Subagent prompts (`codebase-locator` 122 lines [CORRECTED: report said 123; `wc -l .claude/agents/codebase-locator.md` = 122 — the stated 873-line total across all six agent files is itself only consistent with 122, so this was a simple typo], `codebase-analyzer`, `codebase-pattern-finder`, `thoughts-locator`, `thoughts-analyzer`, `web-search-researcher` — 873 lines total across `.claude/agents/`) don't hit the *orchestrator's* context (each runs in its own Task window), which is the framework's actual context-economy trick — but it does mean six near-duplicate "documentarian, not critic" boilerplate blocks to maintain.
- **Gates that are pure prose, not enforced**: the "pause for manual verification between phases" gate (`implement_plan.md:50-65`), "no Claude attribution in commits" (`commit.md`), "no open questions in final plan" (`create_plan.md:338`), and the Linear "only ONE ticket at a time" throttle (`ralph_impl.md:33`) are all things the model could silently skip under load or with a terse enough instruction — nothing in tooling stops it.
- **`--dangerously-skip-permissions` baked into the autonomous launch commands** (`ralph_impl.md:31`, `oneshot.md`) — the fully-autonomous variant explicitly disables the human-approval safety rail that the rest of HumanLayer's product exists to provide; the ceremony of phased manual-verification gates is entirely bypassed in this mode.
- Two full duplicate command families exist per core command (`create_plan.md` / `create_plan_nt.md` / `create_plan_generic.md`; `research_codebase.md` / `_nt.md` / `_generic.md`; `describe_pr.md` / `_nt.md`) — `_nt` appears to be a "no thoughts-system" variant and `_generic` a non-Linear variant, meaning ~3x the maintenance surface for near-identical prompts (not diffed here, but the file-size parity — 439 vs 442 vs 449 lines for the three `create_plan*` variants — strongly suggests near-duplication).
- The whole loop depends on two external, humanlayer-specific systems not portable out of the box: the `thoughts` CLI/git-sync system (`hlyr thoughts ...`) and Linear MCP tools for the autonomous `ralph_*`/`oneshot*` variants.

## Plugin/packaging structure
Not a marketplace plugin. No `plugin.json`, no `.claude-plugin/`, no `mcp.json` found anywhere in the repo. It is a **project-local `.claude/` directory** (`commands/`, `agents/`, `settings.json`) checked directly into the humanlayer monorepo — it works because Claude Code auto-discovers `.claude/commands/*.md` as slash commands and `.claude/agents/*.md` as subagents in any repo you open. `.claude/settings.json` only sets `enableAllProjectMcpServers: false`, an `env.MAX_THINKING_TOKENS=32000`, and an allowlist for `hack/spec_metadata.sh`. The companion `thoughts` system is a real installable CLI subcommand (`hlyr thoughts init/sync/status/config`, `hlyr/src/commands/thoughts/*.ts`) that sets up git pre/post-commit hooks in the *user's other* repos — but that CLI does not scaffold the `.claude/commands` files themselves; those must be copied by hand into another project (this was verified: no reference to `.claude/commands` or `.claude/agents` exists anywhere under `hlyr/src`).

## Second-reader additions

1. **One-command "spin up a colleague's PR as an isolated running environment."**
   Problem solved: reviewing someone else's branch normally means manually adding their fork as a remote, fetching, worktreeing, and re-running setup — enough friction that people skip it and review from the diff alone.
   Path: `.claude/commands/local_review.md:22-31`
   ```
   - Check if the remote already exists using `git remote -v`
   - If not, add it: `git remote add USERNAME git@github.com:USERNAME/humanlayer`
   - Fetch from the remote: `git fetch USERNAME`
   - Create worktree: `git worktree add -b BRANCHNAME ~/wt/humanlayer/SHORT_NAME USERNAME/BRANCHNAME`
   - Copy Claude settings: `cp .claude/settings.local.json WORKTREE/.claude/`
   - Run setup: `make -C WORKTREE setup`
   - Initialize thoughts: `cd WORKTREE && humanlayer thoughts init --directory humanlayer`
   ```
   Fit: a `/review-pr <gh_username>:<branch>` skill that does remote-add + worktree + `make setup` in one shot turns "let me pull that branch" into a zero-friction habit — directly composable with the existing worktree-per-task pattern (mechanism 8) and reusable outside Linear/humanlayer since it's pure `git`/`gh`.

2. **PR-description checklist items are only checked off if the command was actually run and passed — not asserted from memory.**
   Problem solved: a PR description's "How to verify" section is usually pure prose the author fills in optimistically; here the item's checked state is a direct, immediate readback of a real command's exit status, so a stale or false claim can't survive into the description.
   Path: `.claude/commands/describe_pr.md:41-48`
   ```
   - Look for any checklist items in the "How to verify it" section of the template
   - For each verification step:
     - If it's a command you can run (like `make check test`, `npm test`, etc.), run it
     - If it passes, mark the checkbox as checked: `- [x]`
     - If it fails, keep it unchecked and note what failed: `- [ ]` with explanation
     - If it requires manual testing ..., leave unchecked and note for user
   ```
   Fit: distinct from the plan's split success-criteria (mechanism 1 above) because it fires at PR-description time rather than plan-authoring time — a `/describe-pr`-style skill here should refuse to check any box it didn't just run a command to confirm, and explicitly leave manual-only items unchecked rather than letting the model guess.

3. **Self-updating git hooks that version-stamp themselves and never clobber a pre-existing non-HumanLayer hook.**
   Problem solved: installing a git hook via tooling normally either silently overwrites whatever hook was already there, or has no way to know its own hook is stale and needs replacing on a later version of the tool.
   Path: `hlyr/src/commands/thoughts/init.ts:262-301`
   ```js
   const hookNeedsUpdate = (hookPath) => {
     if (!fs.existsSync(hookPath)) return true
     const content = fs.readFileSync(hookPath, 'utf8')
     if (!content.includes('HumanLayer thoughts')) return false // Not our hook
     const versionMatch = content.match(/# Version: (\d+)/)
     if (!versionMatch) return true // Old hook without version
     return parseInt(versionMatch[1]) < parseInt(HOOK_VERSION)
   }
   // backup existing hook to `.old` only if it isn't ours; if it's an outdated
   // HumanLayer hook, just remove and rewrite it
   ```
   Fit: directly reusable shape for any dotfiles installer (this repo's own `stow`-based setup included) that writes shell hooks or config into a user's other repos/dirs — a version comment plus "back up if foreign, silently replace if ours-but-stale" avoids both clobbering a user's own hook and endless duplicate backups on every reinstall.

## Verdict: adopt / borrow parts / ignore
**Borrow parts, don't adopt wholesale.** The four-command core loop (research → plan → implement → validate) with the phase/success-criteria plan template and the handoff-based fresh-session compaction is a genuinely good, load-bearing pattern and maps closely onto skills already present in this dotfiles setup (`flow-spec`, `feature`, `better-plan`, `flow-handoff`) — worth diffing those against mechanisms 1, 3, 5, and 7 above specifically. The autonomous Linear-driven `ralph_*`/`oneshot*` variants are humanlayer-specific (Linear MCP, `thoughts` CLI, `humanlayer-nightly launch`) and run with permission checks disabled — not portable as-is, and the safety trade-off (bypassing the very human-approval gates the rest of HumanLayer sells) is a real cost, not just ceremony. The `_nt`/`_generic` triplication of every core command is pure ceremony worth ignoring/collapsing rather than copying.
