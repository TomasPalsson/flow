---
name: anti-patterns
description: Critical landmines in project initialization that senior devs avoid but AI tools reliably step on. Skim before Stage 5 customization. Covers AI-generated incompatible tool selection, secrets leakage, premature engineering, and stack-specific traps.
---

# Project Init Anti-Patterns (The Landmines)

## AI scaffolding failures (most common)

### Mutually incompatible tools
AI tools pick from a menu of "reasonable" options without checking conflicts. Common bad combinations:
- **ESLint + Biome** together — conflict on rules, fight over "fix on save"
- **Jest + Vitest** in the same monorepo without per-package scoping
- **Husky + Lefthook** — two hook runners racing on the same hook
- **Prettier + Biome formatter** — produce different outputs

**Rule:** one tool per responsibility. Pick ESLint OR Biome. Pick Husky OR Lefthook. Document the choice in CLAUDE.md so future AI sessions don't "helpfully" add the other.

### Stale templates
AI trained on old tutorials produces deprecated patterns:
- Next.js Pages Router (`pages/`) instead of App Router (`app/`)
- Python `setup.py` instead of `pyproject.toml`
- husky v8 `prepare: "husky install"` instead of v9 `prepare: "husky"`
- `create-react-app` (officially deprecated)

**Rule:** use the 2026 commands in [`scaffold-commands.md`](scaffold-commands.md). Do not guess syntax from memory.

### Comprehension debt
Accepting 200+ scaffolded files without reading them. Tests report 85% coverage because they're tautological. When a bug surfaces at month 4, nobody can identify blast radius.

**Rule:** walk the scaffold file-by-file before the first commit. Delete anything you can't explain.

---

## Secrets & `.gitignore`

### `.gitignore` doesn't affect already-tracked files
Most common silent failure: developer adds `.env` to `.gitignore` AFTER already staging it once. The file keeps being tracked. `git rm --cached .env` is required — but rarely done.

**Rule:** write `.gitignore` BEFORE `git init` or BEFORE the first `git add`. The canonical order is: write `.gitignore` → `git init` → first commit.

### Missing `.env.example`
The #1 onboarding friction source. New contributors crash 3 levels deep in a stack trace because `DATABASE_URL` is undefined. Costs nothing to create at scaffold time. Absence costs 30–90 minutes per contributor.

**Rule:** `.env.example` is a first-class scaffold artifact. Every env var gets a comment and a non-secret example value.

### Committed credentials
GitHub permanently archives commits even after deletion. `git rm` doesn't un-leak. The only remediation is revoke + rewrite history (which breaks every contributor's clone).

**Rule:** if the stack uses secrets, ship `.env.example` + `.env` in `.gitignore` + a secret-detection pre-commit hook (`detect-secrets` or `gitleaks`). Never put real values in tracked files, even "just for testing."

### Generic vs stack-specific `.gitignore`
AI tools produce generic gitignores missing stack-specific outputs. Frequently missed:

| Stack | Missed entries |
|---|---|
| Python | `__pycache__/`, `.pytest_cache/`, `.ruff_cache/`, `.mypy_cache/`, `htmlcov/`, `*.egg-info/` |
| Node/TS | `.next/`, `.turbo/`, `.vercel/`, `dist/`, `.env.local`, `.env.*.local` |
| Terraform | `.terraform/`, `*.tfstate`, `*.tfstate.backup`, `*.tfplan` |
| Rust | `target/` (enormous — 10GB+) |

**Rule:** use `gitignore.io` or GitHub's language templates as base, add stack-specific. OS/editor files (`.DS_Store`, `.vscode/`) belong in the user's GLOBAL gitignore, not project-level.

---

## Initial commit hygiene

### "500-file initial commit" with no narrative
Single commit with all scaffold output + dependencies + config dumps. Impossible to bisect. Every architectural decision traces back to "initial commit." Post-mortem archaeology fails.

**Rule:** for new projects, split the first commits into a readable narrative (scaffold / deps / tooling / skeleton / README). For codebase migrations, one large commit is acceptable.

### "initial commit" as message
Breaks commitlint if added later. Loses context forever. "Why are we using Biome?" → "I don't know, initial commit."

**Rule:** initial commit message uses Conventional Commits + brief ADR:
```
chore: initial scaffold

Scaffolded with: bun create next-app
Stack: Next.js 16 (App Router), Turbopack, TS, Tailwind, Bun
```

---

## Over-engineering at scaffold time

- **Premature CI** — full lint/test/build/deploy pipeline before there's a test to run. CI stays green because it checks nothing. When real checks are added, fixing the pipeline becomes an interruption.
- **Premature Docker** — Dockerfile + docker-compose on day 1 for a single-developer project. Slows dev loop, introduces new failure modes. Add Docker when there's a real deployment target or parity problem.
- **Premature microservices** — scaffold as 4-8 services from day 1. Coordination overhead dominates before product-market fit. Start as a modular monolith with clear internal boundaries.
- **Premature commitlint + husky** — enforces conventions before there's a team to enforce them on.

**Rule:** do NOT scaffold CI, Docker, or commit-hook enforcement unless the user explicitly asked OR the project has a test to run.

---

## Under-engineering at scaffold time

- **No linter / type checker** — "we'll add it later" never happens because activation energy grows with every new file. Strict from day 1 is dramatically cheaper.
- **No `.env.example`** — covered above.
- **No `engines` field** (Node) or equivalent version pin — contributors with wrong Node/Python version get cryptic errors.
- **No `LICENSE`** — "no license" means all rights reserved. A public repo without a license is legally hostile. Pick MIT, Apache-2.0, or `MIT OR Apache-2.0` on day 1.

**Rule:** strict TypeScript / strict mypy from day 1. Pin runtime versions (`.python-version`, `.nvmrc`, or `engines`). Include LICENSE.

---

## Stack-specific traps

### Python: flat layout when you need a library
Flat layout puts project root on `sys.path` — tests run against source tree, not installed package. Subtle bugs only appear after distribution. `setuptools` auto-discovery may include `tests/`, `docs/` in the wheel.

**Rule:** `src/` layout for anything meant to be installed as a library. Flat layout OK for applications. `uv init --package` gets the right layout for CLIs.

### Node: `"type": "module"` vs CommonJS mismatch
Errors are famously cryptic: `ReferenceError: exports is not defined in ES module scope`. Surfaces at runtime in specific code paths, not at install time.

**Rule:** always set `"type"` explicitly in `package.json`. Verify major deps support your choice.

### Next.js: Pages Router scaffolded instead of App Router
Pages Router is maintenance mode. New features (Server Components, Streaming) are App Router only.

**Rule:** `bun create next-app <name> --app --turbopack` forces App Router non-interactively.

### Rust: forgetting `target/` in `.gitignore`
`cargo new` writes this, but if you're initializing manually, omitting it permanently bloats the repo.

---

## GitHub setup traps

- **`git init` without `-b main`** — creates `master`. Rename later breaks CI references, webhooks, contributor configs. Always `git init -b main`.
- **`gh repo create --default-branch` / `--add-topic` / `--enable-discussions`** — these flags DON'T EXIST on `gh repo create`. Must use `gh api` after creation.
- **No branch protection on `main`** — one `git push --force` can rewrite history for the whole team. Set protection on day 1.

**Rule:** `git init -b main` always. Use `gh repo create <name> --private --source=. --push` for the one-shot create+push. Set branch protection separately via `gh api` if needed.

---

## The five most common failure cascades

1. **Silent Security Bomb** — no `.env.example` → contributor commits real `.env` → secret in GitHub history forever.
2. **Comprehension Death Spiral** — 300-file AI scaffold accepted without review → bug at month 4 has no clear owner.
3. **Tooling Civil War** — ESLint + Biome both configured → every PR has formatting noise → team adds `// lint-disable` everywhere.
4. **Python Import Hell** — flat layout for a library → wheel accidentally ships `tests/` → next version removes tests → consumer breaks.
5. **Stale Branch Catastrophe** — project init on `master` → rename to `main` at 20 contributors → CI breaks, force-pushes lose work.

Each is prevented by a single scaffold-time decision. Make the decisions up front.
