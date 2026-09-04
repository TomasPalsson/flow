---
name: project-detection
description: Runtime project environment detection — package manager, test/lint/format commands, monorepo structure, dev server, and project-local skills. Detects and stores variables for use by all workflow skills.
---

# Project Detection

Before starting any workflow, detect the project environment. This ensures all commands match the actual project — never hardcode tool names.

## Preferred: Use detect-project Script

Run `${CLAUDE_PLUGIN_ROOT}/skills/shared/scripts/detect-project` first — it detects everything in one call:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/shared/scripts/detect-project --format pretty
```

Output includes: `pkg_mgr`, `test_cmd`, `e2e_cmd`, `lint_cmd`, `format_cmd`, `typecheck_cmd`, `dev_cmd`, `is_monorepo`, `packages`, `framework`, `language`, `project_skills`, and `workspace_commands` (for monorepos). Use `--dir <path>` if not in the project root.

Parse the JSON output and populate the state file variables directly. **If the script is not available**, fall back to manual detection below.

## Manual Fallback — Step 1: Package Manager & Commands

Identify the package manager from lock files in the project root (`bun.lockb`→bun, `bun.lock`→bun, `pnpm-lock.yaml`→pnpm, `yarn.lock`→yarn, `package-lock.json`→npm, `Cargo.lock`→cargo, `uv.lock`→uv, `go.sum`→go modules). In monorepos, also check workspace packages if no root lock file exists.

Read the project's config to find actual commands:
- **Node.js**: `package.json` → `scripts` for test, test:e2e, lint, format, typecheck, dev
- **Python**: `pyproject.toml` for pytest/ruff/black config
- **Rust**: `cargo test`, `cargo clippy`, `cargo fmt --check`
- **Go**: `go test ./...`, check for golangci-lint config

If a command can't be detected, leave it empty — don't guess.

## NEVER Do

- **NEVER hardcode a fallback package manager** — if no lock file is found, leave PKG_MGR empty; guessing causes wrong commands downstream
- **NEVER run commands with side effects during detection** — no `npm install`, `cargo build`, `pip install`; read config files only
- **NEVER overwrite sections of `workflow-state.local.md` other than `## Project Environment`** — the calling workflow owns the rest of the file
- **NEVER infer a package manager from directory names** — only lock files are reliable indicators

## Step 2: Project Structure

- **Monorepo**: Check for `packages/`, `apps/`, `crates/`, `modules/` or workspace config in package.json/Cargo.toml
- **If monorepo**: Identify which packages are relevant to the current task
- **Single package**: Use project root for all commands

## Step 3: Dev Server

Check in order:
1. `.claude/scripts/start-dev-server.sh` — project-specific script (parse JSON output for port/pid)
2. `package.json` → `scripts.dev` — standard dev command
3. `Makefile` → `dev` or `serve` target
4. None found → `DEV_CMD` stays empty (browser verification may not be possible)

## Step 4: Project-Local Skills

Check for `.claude/skills/` in the project. If present, list available skills — these provide domain-specific guidance for implementation and verification.

## Output

The calling workflow (feature/fix) creates `.claude/workflow-state.local.md` and is responsible for writing the detected values into its `## Project Environment` section. After detection, return the values in the format below so the calling workflow can populate the state file.

**If the state file already exists** (resume scenario): Read the existing `## Project Environment` section. If it is already populated with real values (not placeholders), skip detection entirely — use the cached values. Only re-detect if the caller explicitly requests it.

Variables to persist:

```
PKG_MGR, TEST_CMD, E2E_CMD, LINT_CMD, FORMAT_CMD, TYPECHECK_CMD, DEV_CMD
PROJECT_SKILLS[], IS_MONOREPO, PACKAGES[]
```

Format in the state file:

```markdown
## Project Environment
- PKG_MGR: [value]
- TEST_CMD: [value or ""]
- E2E_CMD: [value or ""]
- LINT_CMD: [value or ""]
- FORMAT_CMD: [value or ""]
- TYPECHECK_CMD: [value or ""]
- DEV_CMD: [value or ""]
- IS_MONOREPO: [true/false]
- PACKAGES: [comma-separated list or ""]
- PROJECT_SKILLS: [comma-separated list or ""]
```
