---
name: new-project
description: Scaffold a new project from a natural-language description. Infers the best 2026 tech stack from the description (or asks when ambiguous), runs the canonical scaffolding command (uv init / bun create / cargo new / flutter create / sv create / create-next-app / etc.), writes a type-appropriate README and stack-specific .gitignore, creates an initial commit, and optionally creates a GitHub repo. Use WHENEVER the user says /new-project, "create a new project", "scaffold a project", "start a new repo", "bootstrap a project", "new Rust/Python/Next/React/Flutter project", or describes something they want to build from scratch. Triggers on - /new-project, new project, scaffold, bootstrap, spin up a project, start a repo, create a repo, make me a project, initialize a project, generate a project skeleton.
---

# /new-project — Scaffold New Projects

Pipeline: **Clarify → Decide → Safety-check → Scaffold → Customize → [GitHub] → Report**.

Everything runs inline — no subagents. Scaffolding is fast, sequential, deterministic.

## User's environment (confirmed from dotfiles)
- Package manager for JS/TS: **bun** (not npm/pnpm) — Fish config sets `BUN_INSTALL`
- Project location: **`~/projects/NAME`** (matches `goto` tmux switcher convention)
- **direnv** is active — write `.envrc` stub for projects needing env vars
- GitHub user: `TomasPalsson`
- **Deployment default: AWS via SST v3 (Ion).** When the project is web/API/serverless AND deployment is relevant, default to SST on AWS. Delegate SST-specific setup to the `/sst` skill — do not duplicate SST knowledge here.
- Existing Go TUI `new-project` binary exists but this skill supersedes it (TUI cannot be driven non-interactively)

---

## Stage 0: Parse input and check for resume

Read `$ARGUMENTS` for free-form description and optional flags (`--name`, `--stack`, `--dir`, `--no-github`, `--dry-run`).

Check `.claude/workflow-state.local.md`. If it exists with `type: new-project`, resume from the first incomplete phase. Otherwise proceed.

---

## Stage 1: Clarification Gate (HARD GATE when ambiguous)

**Classify unknowns as load-bearing vs cosmetic.**

| Assumption | Load-bearing? |
|---|---|
| Project name | YES — directory name, package name, repo name |
| Stack | YES — different scaffolding commands |
| Location (if not `~/projects/NAME`) | YES — hard to undo |
| GitHub intent + visibility | YES — `gh repo create` can't be undone |
| Template variant (e.g., Vite react vs react-swc) | No — cosmetic |
| License | No — add later |
| README description text | No — editable |

**Stack inference — if description unambiguously names a stack or type, SKIP asking stack:**

Use the signal table in [`references/stack-decisions.md`](references/stack-decisions.md). Common high-confidence signals:
- "Rust CLI" → `cargo new --bin`
- "Python FastAPI" / "Python script" / "data" → `uv init` (+ `--package` if CLI)
- "Next.js" / "full-stack web app" → `bun create next-app`
- "React SPA" / "Vite React" → `bun create vite ... --template react-ts`
- "SvelteKit" → `npx sv create`
- "Astro" / "blog" / "marketing site" → `npm create astro@latest`
- "Flutter" / "mobile app" → `flutter create --template=skeleton`
- "Hono" / "edge API" → `bun create hono`
- "SST" / "serverless AWS" / "deploy to AWS" → scaffold base project, then delegate to `/sst` skill
- ANY web app / API where the user mentions deployment at all → default target is AWS via SST; after scaffold, offer to invoke `/sst`

If the description is truly ambiguous between two stacks (e.g., "backend API" without language context), ASK. Do not guess.

**If description is vague enough to need clarification, ask all load-bearing unknowns in ONE batched message** — never sequential wizard:

> Before I scaffold this, a few things to confirm:
> 1. Project name: `<inferred>`? (or what would you prefer)
> 2. Stack: `<inferred>`? (or different)
> 3. Location: `~/projects/<name>`? (or current dir / specify)
> 4. GitHub: create a private repo after scaffolding, or skip?
>
> Anything else I should know?

**Skip this gate** when the user said "just do it" / "go" / "you decide" OR the description is fully explicit. In that case, show the Pre-Execution Summary (Stage 3) instead.

---

## Stage 2: Stack Decision (inline)

**MANDATORY — READ ENTIRE FILE**: Load [`references/scaffold-commands.md`](references/scaffold-commands.md) before proceeding. Do not guess commands from memory — the 2026 syntax differs from older tutorials for nearly every tool.

**Also load** [`references/stack-decisions.md`](references/stack-decisions.md) IF the description didn't already unambiguously name a stack at Stage 1. **Do NOT load** if the stack was explicit — skip straight to scaffold-commands.md.

For the chosen stack, determine:
- **Canonical 2026 command** — use the exact invocation from `scaffold-commands.md`
- **Project layout mode** — e.g., `uv init` defaults to flat; for a CLI use `--package` so you get `src/` layout + `[project.scripts]` entry
- **Whether the tool creates its own `.git`** — `cargo new` and `uv init` do; `bun create` typically does not

---

## Stage 3: Pre-Execution Summary (SOFT GATE)

Before touching the filesystem, show:

```
About to create:
  Name:      <name>
  Stack:     <stack + exact command>
  Location:  <abs path>
  GitHub:    <private|public|skip>

Steps:
  1. <scaffold command>
  2. Write README.md, .gitignore (stack-specific), .env.example (if needed), .envrc (if needed), CLAUDE.md (minimal)
  3. git init -b main (if not already) + initial commit (Conventional Commits)
  4. [GitHub step — separate HARD GATE]

Proceed?
```

Skip this if the user already explicitly approved ("go", "just do it"). Never skip if any load-bearing value was inferred silently.

---

## Stage 4: Safety Checks + Scaffold

**HARD GATE — Directory existence:**
```bash
test -d "<TARGET_DIR>" && echo EXISTS
```
If it exists: ABORT. Do not overwrite. Tell the user to pick a different name or remove the existing directory.

**Run the scaffold command** (exact syntax already loaded from `scaffold-commands.md` at Stage 2). Keep the command inline in the Bash call — do not generate scripts.

**Error recovery — common scaffold failures:**

| Symptom | Cause | Recovery |
|---|---|---|
| `command not found: bun` / `uv` / `cargo` / `flutter` | Tool not installed | Tell user which tool to install (`curl -fsSL https://bun.sh/install \| bash`, `curl -LsSf https://astral.sh/uv/install.sh \| sh`, etc.). Do NOT proceed. |
| `fatal: empty ident name` on git commit | Git user not configured | Run `git config user.name` / `user.email` check first; if missing, abort and tell user to set globally |
| Scaffold command exits non-zero, partial dir exists | Network, permission, or tool bug | `rm -rf "<TARGET_DIR>"` — rollback. Report exact command + stderr. |
| `gh: To get started with GitHub CLI, please run: gh auth login` (Stage 6 only) | Not authenticated | Abort Stage 6. Tell user to run `gh auth login`. Keep the local scaffold — don't delete it. |
| Target is on a different filesystem / permission denied | Unusual `--dir` | Abort before any work; ask user for a writable path |

**Always rollback partial directories** on mid-pipeline failure:
```bash
rm -rf "<TARGET_DIR>"
```
Do NOT leave broken scaffolds on disk.

---

## Stage 5: Customize (write supporting files)

Write each file only if the scaffold tool didn't already create it, or if theirs is inadequate.

### 5a. README.md (type-appropriate)

**MANDATORY — READ ENTIRE FILE**: Load [`references/readme-templates.md`](references/readme-templates.md) before writing README.md. Use the template matching the stack (library / CLI / web-app / service). Do NOT produce a 200-line README — match the template, fill blanks, leave `TODO:` stubs for unknowns.

**Also skim** [`references/anti-patterns.md`](references/anti-patterns.md) before writing any supporting file — it lists the landmines (gitignore ordering, `.env.example` importance, incompatible tool combos).

Universal rules (apply regardless of template):
- First 3 lines: what / who / how-to-run
- Quickstart must produce a working result in under 30 seconds (no config required before first run)
- Max 5 badges; no badge soup
- Every code block is copy-pasteable (no `$ ` prefix)

### 5b. .gitignore (stack-specific)

**Create `.gitignore` BEFORE `git init`** — entries don't affect already-tracked files. If the scaffold tool already wrote one, audit it for stack-specific omissions commonly missed:

| Stack | Commonly missed |
|---|---|
| Python | `.ruff_cache/`, `.mypy_cache/`, `htmlcov/`, `*.egg-info/` |
| Node/TS | `.next/`, `.turbo/`, `.vercel/`, `dist/`, `.env.local` |
| Rust | `target/` is huge (10GB+) — must be there |
| All | `.env`, `.env.*.local` |

Do NOT add OS/editor files (`.DS_Store`, `.vscode/`, `.idea/`) to project `.gitignore` — those belong in the user's global gitignore.

### 5c. .env.example

If the project is likely to use env vars (Python service, Node API, any web app, anything with a database or LLM API), write `.env.example` with placeholder values and inline comments. **Missing `.env.example` is the #1 onboarding friction cause.** It costs nothing to create.

### 5d. .envrc

If `.env` will exist, write `.envrc` with `dotenv` (direnv is active in user's shell).

### 5e. CLAUDE.md (minimal)

Write a ~30-line CLAUDE.md with: stack, primary commands (run/test/lint), any non-obvious conventions. Do not be comprehensive — user can run `/init` later to elaborate.

### 5f. LICENSE

One-question test: does this touch patent-heavy domains (crypto, video codecs, ML, container orchestration) OR are corporate contributors likely? → `Apache-2.0`. Otherwise → `MIT`. For Rust crates, prefer `MIT OR Apache-2.0` dual-license (ecosystem convention). Default: MIT unless user indicated otherwise.

### 5g. Initial commit

```bash
git init -b main         # only if scaffold tool didn't already
git add -A
git commit -m "chore: initial scaffold

Scaffolded with: <tool> <command>
Stack: <stack summary>
"
```

Do NOT use "initial commit" — use Conventional Commits format so later `commitlint` doesn't reject history rewrites.

**Do NOT** scaffold CI, Docker, pre-commit hooks, or commitlint at init time unless the user explicitly asked. These are premature before there's code to check.

---

## Stage 6: GitHub (HARD GATE — requires explicit yes)

Only runs if user opted into GitHub. **Even if they said yes in Stage 1, confirm again here** with the exact command:

```
Ready to create GitHub repository:
  Name:       TomasPalsson/<name>
  Visibility: private
  Will push:  main branch (1 commit)

This will run:
  gh repo create <name> --private --source=. --push

Confirm?
```

On explicit confirmation:
```bash
gh repo create <name> --private --source=. --push --description "<short description>"
```

The `--source=. --push` single-command pattern handles remote add + initial push. Do NOT split into three commands unless `gh` is unavailable.

**Never pass these flags to `gh repo create` — they don't exist:** `--default-branch`, `--add-topic`, `--enable-discussions`. For topics/discussions, use `gh api` after creation.

If declined: record, skip, proceed to Stage 7.

---

## Stage 7: Completion Report

```
Created: <absolute path>
Stack:   <stack>
GitHub:  <url or "skipped">

Run it:
  cd <path>
  <primary run command>

Suggested next:
  <1-3 stack-relevant next steps, e.g., "add first test", "run /sst if this becomes serverless">
```

Delete `.claude/workflow-state.local.md` on success.

---

## NEVER rules (irreversible-damage only)

- **NEVER overwrite an existing directory.** Check `test -d` before any scaffolding command.
- **NEVER run `gh repo create` without explicit Stage-6 confirmation** — even if the user said yes earlier. Show the exact command.
- **NEVER leave partial directories on failure.** Always `rm -rf` the scaffold target on mid-pipeline error.
- **NEVER `git add` before `.gitignore` exists with `.env` in it.** `.gitignore` does not affect already-tracked files — the ordering matters.
- **NEVER invoke the existing `new-project` Go binary** — it is a TUI, cannot be driven non-interactively, and will hang the session.

Other anti-patterns (tool mixing, stale templates, setup.py, Pages Router, etc.) are covered in [`references/anti-patterns.md`](references/anti-patterns.md).

---

## Reference loading (summary)

Each stage above specifies exactly when to load a reference. Summary:

| Reference | Loaded by |
|---|---|
| `scaffold-commands.md` | Stage 2 — always |
| `stack-decisions.md` | Stage 1 — only if description is ambiguous |
| `readme-templates.md` | Stage 5a — always |
| `anti-patterns.md` | Stage 5 — skim before writing supporting files |

Load with the Read tool. **Do NOT pre-load all references at Stage 0** — wait for the stage that needs each one. This keeps the orchestrator context lean.

---

## Integration with other skills

- **`/sst`** — default deployment path for web/API projects. After base scaffold completes, if the user indicated deployment is relevant OR the project type is clearly deployable (web app, API, service), offer: "Deployment target is AWS via SST by default. Run `/sst` now to add SST v3 to this project at `<path>`?" Hand off there — do not duplicate SST config knowledge in this skill. If the user says they don't need deploy yet, skip.
- **`/init`** — after scaffold completion, suggest the user run `/init` if they want a more comprehensive CLAUDE.md.
- **`/feature`** — suggested next step when the user is ready to build their first feature.
