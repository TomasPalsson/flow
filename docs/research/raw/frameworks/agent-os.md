# agent-os

## What it is

Agent OS (buildermethods/agent-os, by Brian Casel / Builder Methods) is a set of five Claude-Code-style slash-command prompt files plus two shell scripts that install/sync a `agent-os/standards/` tree into a project and teach an agent to discover, index, and selectively inject those standards (and product docs) into context. As of v3.0 it is deliberately *not* a spec/task/orchestration framework anymore — it dropped its old spec-writing, task-breakdown, and multi-agent-orchestration phases and now only does "establish standards, inject them smartly, enhance spec-driven development via plan mode." Repo has no visible star count in the clone; shallow clone's only reachable commit (`475b0ca`, 2026-08-29, "Add orb setup and resume scripts") is unrelated internal tooling — the real v3.0 content dates from the `[3.0] - 2026-01-20` CHANGELOG entry.

## Workflow it implements

Two independent tracks, both slash commands read directly off disk (`.claude/commands/agent-os/*.md`), no subagents, no orchestrator:

**Standards track** (the core of v3):
1. `/discover-standards` — analyzes codebase, proposes 3-5 areas via `AskUserQuestion`, for each area proposes candidate standards, then for *each selected standard* runs a mandatory ask-why → draft → confirm → create loop (never batches), writes `agent-os/standards/[folder]/[name].md`, then auto-runs `/index-standards` as its final step.
2. `/index-standards` — scans all `.md` under `agent-os/standards/`, diffs against `index.yml`, asks the user to approve a one-line description for each new file, silently prunes entries for deleted files, rewrites `index.yml` alphabetized by folder then filename.
3. `/inject-standards` — the consumption side. Auto-suggest mode reads `index.yml`, matches descriptions against the current conversation's topic, asks the user to confirm 2-5 suggestions, then formats the injected content differently depending on a detected "scenario" (Conversation / Creating a Skill / Shaping-Planning) — either read-and-announce, `@file` references, or full copy-paste, decided again via `AskUserQuestion`. Explicit mode (`/inject-standards api/response-format`) skips suggestion but still asks which of the three output formats to use.

**Product/spec track** (thin, defers to the host tool's own plan mode):
4. `/plan-product` — interview via `AskUserQuestion` (problem → users → differentiator → MVP scope → post-launch → tech stack, with tech stack pre-filled from `agent-os/standards/global/tech-stack.md` if present) → writes `agent-os/product/{mission,roadmap,tech-stack}.md`.
5. `/shape-spec` — **must** be run while the host agent is already in "plan mode" (it refuses otherwise); interviews scope/visuals/reference-code, reads `agent-os/product/*`, reads `standards/index.yml` and asks which standards apply, then always makes "Task 1" of the resulting plan be "Save spec documentation" to `agent-os/specs/{YYYY-MM-DD-HHMM-slug}/{plan,shape,standards,references}.md` before any implementation tasks. Everything past that (breaking work into tasks, executing them) is left to the host tool's own plan-mode/todo machinery — v3 explicitly retired its own task-breakdown and orchestration phases (see CHANGELOG "Why the major version bump").

Install/sync is pure shell, no LLM involved: `scripts/project-install.sh` copies a profile's `standards/` tree (following an inheritance chain from `config.yml`) into a project's `agent-os/standards/`, regenerates `index.yml` with `Needs description - run /index-standards` placeholders for anything without a prior description, and copies the 5 command `.md` files into `.claude/commands/agent-os/`. `scripts/sync-to-profile.sh` does the reverse — an interactive checkbox picker (bash, `tput cuu1`/`tput el` for redraw) lets you push project-local standards edits back up into a shared base profile, with automatic timestamped backups (`.backups/YYYY-MM-DD-HHMM/`) on overwrite.

## Artifacts it produces

- `agent-os/standards/index.yml` — the match index. Schema (from `commands/agent-os/index-standards.md`):
  ```yaml
  folder-name:
    file-name:
      description: Brief description here
  ```
  `root:` is a reserved pseudo-folder for `.md` files directly under `standards/`.
- `agent-os/standards/[folder]/[standard].md` — free-form standard files, but the command prescribes a template discipline: "Lead with the rule... Use code examples... Skip the obvious... One standard per concept... Bullet points over paragraphs" (`commands/agent-os/discover-standards.md:170-174`).
- `agent-os/product/mission.md` — headings `## Problem`, `## Target Users`, `## Solution`.
- `agent-os/product/roadmap.md` — headings `## Phase 1: MVP`, `## Phase 2: Post-Launch`.
- `agent-os/product/tech-stack.md` — headings `## Frontend`, `## Backend`, `## Database`, `## Other`.
- `agent-os/specs/{YYYY-MM-DD-HHMM-feature-slug}/` — `plan.md`, `shape.md` (headings `## Scope`, `## Decisions`, `## Context`, `## Standards Applied`), `standards.md` (per-standard `## folder/name` sections with full file content pasted in), `references.md` (`## Similar Implementations` → `### {name}` with Location/Relevance/Key patterns), `visuals/`.
- `config.yml` (base install) — just `version:`, `default_profile:`, and an optional `profiles:` map of `inherits_from:` relationships.
- `profiles/{name}/standards/**.md` and `profiles/{name}/global/tech-stack.md` — the reusable base library that `project-install.sh` copies from.

## Deterministic vs prompt

| Mechanism | Enforced by script/hook/CLI | Asked of the model in prose |
|---|---|---|
| Copying a profile's standards into a project | `scripts/project-install.sh` (`install_standards`, pure `cp`/`find`) | — |
| Profile inheritance resolution (base→override order, cycle/missing-profile detection) | `scripts/common-functions.sh: get_profile_inheritance_chain` (awk/bash) | — |
| Regenerating `index.yml` skeleton with placeholder descriptions on install | `scripts/project-install.sh: create_index` (bash, preserves old descriptions via awk lookup) | — |
| Writing the actual one-line descriptions | — | `/index-standards` via `AskUserQuestion`, model proposes text |
| Deciding *which* standards are relevant to inject | — | entirely prose: `/inject-standards` "Analyze Work Context" + `AskUserQuestion` confirmation; no embeddings/keyword scoring, just the model reading `index.yml` |
| Deciding conversation vs skill vs plan output format | — | `AskUserQuestion`, "Always ask when uncertain — don't assume" |
| Backing up conflicting files before overwrite on sync | `scripts/sync-to-profile.sh: backup_files` (timestamped dir, bash) | — |
| Refusing to run `/shape-spec` outside plan mode | — | prose-only gate: "check if you are currently in plan mode... stop immediately" — nothing external verifies this, the model self-reports |
| Task 1 of every spec plan being "Save spec documentation" | — | prose convention in `/shape-spec`, no enforcement if the model skips it |
| Interactive multi-select file picker for sync | `scripts/sync-to-profile.sh: select_files` (bash `read`/array toggle UI) | — |
| Standard-writing quality bar (concise, lead-with-rule) | — | prose guidelines only, no linter |

## Mechanisms worth stealing

1. **Index-file indirection for context injection** — `agent-os/standards/index.yml` (schema above), read by `commands/agent-os/inject-standards.md` Step 2. Problem solved: avoids reading every standards file to decide relevance — the model reads one small YAML of one-line descriptions and does semantic matching against that, only opening the 1-5 matched files. For a global dotfiles harness: a single `~/.claude/standards/index.yml` (or per-project override) that any project's agent can read cheaply before deciding what to pull in, instead of grepping a standards directory on every turn.

2. **Three-mode output shaping for the same content** (`commands/agent-os/inject-standards.md:92-227`) — the same matched standards get formatted three different ways depending on destination: full inline read-and-announce for a live conversation, `@file` references for a Skill being authored ("keeps skill lightweight, standards stay in sync"), or pasted full content for a spec/plan. Fits a dotfiles harness that has both interactive sessions and generated Skill/CLAUDE.md artifacts — same source-of-truth file, injected differently depending on whether the consumer will re-read it live or needs to be self-contained.

3. **Profile inheritance chain resolved by a pure shell function, not the model** — `scripts/common-functions.sh: get_profile_inheritance_chain` walks `config.yml`'s `profiles: {name: {inherits_from: parent}}` links, detects cycles and missing profiles deterministically, returns base-first order so later profiles override earlier ones. Directly reusable for a dotfiles repo that wants e.g. a `base` profile plus per-machine/per-stack overlays (`work`, `personal`, `rust-projects`) without asking an LLM to reason about merge order.

4. **Sync-back with automatic timestamped backup, never silent overwrite** — `scripts/sync-to-profile.sh: backup_files` (`.backups/$timestamp/` under the *destination* before any `cp`) plus a three-way conflict prompt (overwrite-with-backup / skip / cancel) in `check_conflicts`. Good pattern for a global-dotfiles-harness command that pushes a project-local tweak (e.g. a CLAUDE.md snippet, a hook) back up into the shared `~/.dotfiles` copy — never destroys the previous shared version silently.

5. **Ask-why-before-writing loop, one standard at a time, never batched** (`commands/agent-os/discover-standards.md` Step 3: "IMPORTANT: For each selected standard, you MUST complete this full loop before moving to the next" — ask 1-2 why-questions, draft, confirm, create, *then* repeat). Forces the *rationale* behind a convention to get captured, not just the pattern — worth stealing for any "extract standards/conventions from an existing config/codebase" onboarding flow so the harness doesn't just mirror surface patterns without the reasoning that would let it know when an exception is legitimate.

6. **A hard, self-reported gate that a command must run inside a specific host-tool state** — `/shape-spec`'s Prerequisites section refuses to proceed unless the model believes it is in the host's "plan mode," printing a stop message otherwise (`commands/agent-os/shape-spec.md:11-23`). It's unenforced (prose-only) but it's a cheap, explicit way to prevent a heavyweight interactive command from running half-cocked in the wrong mode — worth the one-line convention even without real enforcement.

7. **Placeholder-driven "needs description" queue instead of blocking install** — `scripts/project-install.sh: create_index` writes `description: Needs description - run /index-standards` for any standards file lacking a prior description rather than stopping the install or guessing silently; this makes the gap visible and grep-able (`grep "Needs description"`) and defers the judgment call to the one command built for it. Useful pattern for any generated index/manifest in a dotfiles harness: never let automated generation silently invent content it isn't confident about — leave a searchable stub.

8. **Standards-writing style guide baked into the authoring command itself** (`commands/agent-os/discover-standards.md:166-196`, explicit good/bad examples) — "lead with the rule," "skip the obvious," one concept per file. Directly portable as a short constitution for how CLAUDE.md / skill reference files should be written in this dotfiles repo, since the same token-cost pressure applies to anything injected into every session.

## Weaknesses / ceremony cost

- **Every command is `AskUserQuestion`-gated at nearly every step** — `/discover-standards` alone has 6 numbered steps and the phrase "Wait for user response before proceeding" or equivalent appears after almost every step; a full standards-discovery pass for one area is at minimum 4-5 round trips (area choice → findings choice → per-standard why-questions → per-standard draft confirm → index description confirm), and Step 3 explicitly forbids batching multiple standards' questions together, so N standards ≈ N sequential Q&A loops. There is no unattended/batch mode.
- **Nothing is machine-enforced end to end** — every gate in the table above that isn't a shell script is pure prose ("stop immediately," "MUST complete this full loop," "Always ask when uncertain"). A model under instruction pressure elsewhere in a long conversation can silently skip the plan-mode check in `/shape-spec`, skip Task-1-is-always-save-spec in the plan structure, or auto-answer its own `AskUserQuestion` calls without truly waiting — nothing outside the prompt text catches that.
- **Relevance matching in `/inject-standards` is unscored prose** — Step 3/4 just says "look at the current conversation... match index descriptions against the context," with no retrieval algorithm, similarity threshold, or fallback if `index.yml` is stale; quality is entirely bounded by how well the one-line descriptions were written and how attentively the model reads them at that moment.
- **Total prompt weight of the 5 commands is small in isolation but each is standalone** — `commands/agent-os/*.md` total 1147 lines across 5 files (discover 261, index 124, inject 291, plan-product 204, shape-spec 267); a single `/shape-spec` invocation loads its own 267-line file plus, at Step 5 and later, however many full standards files get selected (each pasted in full for the "Copy content" option) — so effective context cost is unbounded and depends entirely on how many/how large the matched standards are, since there's no truncation or summarization step anywhere in the pipeline.
- **No test suite, no lint, no CI validation of the shell scripts themselves** beyond the two CHANGELOG-noted bugfixes (`((var++))` under `set -e` silently aborting scripts because `((0))` returns nonzero, fixed by appending `|| true` everywhere; and GNU-only `tac` swapped for portable `awk`) — both are the kind of bug a test harness would have caught before release, not after user reports (`#328`, `#327`).
- **Product/spec track is now almost entirely delegated away** — v3's own CHANGELOG says implementation orchestration, task breakdown, and spec-writing itself are "now best handled using Plan Mode" / "Frontier models manage task delegation on their own"; `/shape-spec` only wraps the host tool's plan mode with a forced first save-step, so the actual planning quality is 100% outsourced to whatever plan mode the host tool (Claude Code, Cursor, etc.) provides — the framework contributes almost nothing deterministic to that half of the workflow anymore.

## Plugin/packaging structure

No plugin manifest, no marketplace listing, no npm package, no `plugin.json`/`marketplace.json` anywhere in the repo. Installation is base-repo-then-project-script:
1. Clone/download the `agent-os` repo somewhere as the "base installation" (holds `config.yml` + `profiles/`).
2. From inside a target project, run `scripts/project-install.sh [--profile NAME] [--commands-only] [--verbose]`. It:
   - resolves `EFFECTIVE_PROFILE` from `--profile` or `config.yml`'s `default_profile`,
   - walks the inheritance chain via `common-functions.sh`,
   - copies `profiles/{chain}/standards/**.md` into `./agent-os/standards/` (later profiles in the chain override earlier files of the same relative path),
   - regenerates `agent-os/standards/index.yml`,
   - copies the 5 command files from `commands/agent-os/*.md` into `./.claude/commands/agent-os/` (Claude Code's native slash-command discovery path — no separate registration step or hook).
3. `scripts/sync-to-profile.sh [--profile NAME | --new-profile NAME] [--all] [--overwrite]` is the reverse path, run from inside a project, writing back into the *base install's* `profiles/{name}/standards/`.

No runtime hooks are registered (no `hooks.json`, no `SessionStart`/`PreToolUse` wiring) — the mechanism relies entirely on the 5 files existing under `.claude/commands/agent-os/` and being explicitly invoked by name (`/discover-standards`, `/index-standards`, `/inject-standards`, `/plan-product`, `/shape-spec`).

## Second-reader additions

1. **Install-time overwrite confirmation has no backup, unlike sync-back** — `scripts/project-install.sh: confirm_standards_overwrite` (lines 164-189). Before `install_standards` runs, if `agent-os/standards/` already exists it prints a warning and does a plain `read -p "Do you want to continue? (y/N) "`; if the user says yes, `install_standards` proceeds straight to `cp` over the existing files (line 238) with **no timestamped backup** — unlike `sync-to-profile.sh: backup_files`, which always snapshots to `.backups/$timestamp/` before overwriting. So the "never overwrite silently" property the first reader credited to mechanism #4 holds only on the sync-back (project→profile) path; the install (profile→project) path is a bare confirm-or-cancel with the old standards gone for good if you confirm. Worth flagging when porting mechanism #4 — the backup discipline needs to be added to the install direction too, not just assumed to already be there.
   ```bash
   confirm_standards_overwrite() {
       ...
       read -p "Do you want to continue? (y/N) " -n 1 -r
       echo ""
       if [[ ! $REPLY =~ ^[Yy]$ ]]; then
           ...
           exit 0
       fi
   }
   ```

2. **Guard against installing into the framework's own repo** — `scripts/project-install.sh: validate_not_in_base` (lines 97-106), called from `main()` before anything else runs. Compares `$PROJECT_DIR` (`pwd`) against `$BASE_DIR` (the script's own parent) and hard-exits with a pointed error + "cd to your project directory first" hint if they match. Cheap, fully deterministic footgun-prevention for exactly the kind of mistake a base-repo-then-project-script install flow invites (running the installer from inside the cloned framework repo itself, which would self-overwrite `agent-os/standards/` and `.claude/commands/agent-os/` in the tool's own checkout). Worth stealing verbatim for any dotfiles script that has a "base library repo" + "run this from inside a consumer project" shape.
   ```bash
   validate_not_in_base() {
       if [[ "$PROJECT_DIR" == "$BASE_DIR" ]]; then
           print_error "Cannot install Agent OS in the base installation directory"
           ...
           exit 1
       fi
   }
   ```

3. **`--commands-only` escape hatch decouples command updates from content updates** — the `COMMANDS_ONLY` flag (parsed at `project-install.sh:62-65`, gates `confirm_standards_overwrite` at line 165-167 and short-circuits `install_standards` at lines 205-208) lets a user re-run the installer to pick up newer versions of the 5 `.claude/commands/agent-os/*.md` prompt files without touching `agent-os/standards/` at all — skips both the destructive-overwrite confirmation and the standards `cp` loop entirely, going straight to `create_index`/`install_commands`. Useful pattern for a dotfiles harness that separately versions "prompt/command logic" vs. "content the user has customized locally" — an update path that can refresh the former without ever risking the latter, no confirmation prompt needed because nothing destructive happens.
   ```bash
   install_standards() {
       if [[ "$COMMANDS_ONLY" == "true" ]]; then
           print_status "Skipping standards (--commands-only)"
           return
       fi
       ...
   ```

## Verdict: adopt / borrow parts / ignore

**Borrow parts, don't adopt wholesale.** The framework's core standards-library mechanics (index.yml indirection, profile inheritance resolved deterministically in shell, backup-before-overwrite sync-back) are clean, small, and map almost directly onto a dotfiles-managed global harness's actual need: a shared base of conventions/snippets, per-project or per-machine overlays, and a cheap way for an agent to decide what's relevant without reading everything. Those four scripts/mechanisms (#1, #3, #4, #7 above) are worth porting close to verbatim.

Ignore the product/spec track (`/plan-product`, `/shape-spec`) as a model to copy structurally — v3 itself deprioritized it, admitting plan mode and the host tool now do that job better, and what's left is a thin `AskUserQuestion` interview wrapper with no enforcement. Also skip the AskUserQuestion-heavy, no-batch-mode interaction style for anything meant to run unattended in a personal harness — a solo dev's global tooling should default to sensible auto-decisions with an escape hatch, not force a multi-step interview for every standards file. Treat the "ceremony cost" list above as the checklist of what to strip out when porting the mechanisms into something leaner.
