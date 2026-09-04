---
name: scaffold-commands
description: Exact 2026 scaffolding commands per stack. Load during Stage 2/4 to get the canonical command. These are the authoritative invocations — do not guess or use older tutorial syntax.
---

# Scaffold Commands (2026)

All commands assume the user's `~/projects/` convention and `bun` as the JS/TS package manager. Run from `~/projects/` — the command creates the subdirectory.

## Python (uv)

```bash
# Application (flat layout, main.py at root — good for services, scripts, notebooks)
uv init <name>

# Application with src/ layout + [project.scripts] entry point — preferred for CLIs
uv init --package <name>

# Library (src/ layout + py.typed marker + build system)
uv init --lib <name>

# With specific Python version
uv init --python 3.12 <name>
```

**Post-init additions:**
```bash
cd <name>
uv add <runtime-deps>
uv add --dev ruff mypy pytest
```

**pyproject.toml additions the skill should inject for production apps:**
```toml
[tool.ruff]
line-length = 88
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I", "N", "UP", "B", "S"]

[tool.mypy]
python_version = "3.12"
strict = true
ignore_missing_imports = true
```

**Gotchas:**
- `uv init` default is flat — use `--package` for CLIs where you want `src/` + entry point
- `uv init` creates `.python-version` and `.gitignore` automatically
- `uv init` runs `git init` automatically

## Rust

```bash
# Binary crate (most common — CLIs, services)
cargo new <name>

# Library crate
cargo new --lib <name>

# Template-based (Leptos, etc.)
cargo generate <template>
```

**For Axum API servers (no official template):**
```bash
cargo new <name>
cd <name>
cargo add axum tokio --features full
cargo add serde serde_json tower-http tracing tracing-subscriber
```

**Workspace lints to add to `Cargo.toml` for serious projects:**
```toml
[lints.rust]
unsafe_code = "deny"

[lints.clippy]
pedantic = { level = "warn", priority = -1 }
unwrap_used = "deny"
expect_used = "deny"
```

**Gotchas:**
- `cargo new` runs `git init` automatically
- `target/` is huge (10GB+) — ensure `.gitignore` has it (cargo writes one, but verify)

## JavaScript / TypeScript

Always use `bun`, not `npm` or `pnpm`, per user preference.

### React SPA (Vite)
```bash
bun create vite <name> --template react-ts
cd <name>
bun install
```

### Next.js (Turbopack stable, App Router)
```bash
bun create next-app <name> --typescript --eslint --app --src-dir --turbopack
cd <name>
```

The flags above force non-interactive creation with sensible 2026 defaults. Omit `--react-compiler` flag — still experimental.

### SvelteKit
```bash
npx sv create <name>
# Interactive — select template (minimal / demo), TypeScript, and add-ons:
# vitest, playwright, prettier, eslint, tailwindcss, drizzle, lucia
```

`sv` is the new CLI — replaces old `npm create svelte@latest`.

### Astro
```bash
npm create astro@latest <name>
# Interactive wizard picks template + TS strictness
```

Component frameworks added post-init with `npx astro add react` / `astro add svelte` etc.

### Hono (edge API)
```bash
bun create hono@latest <name>
# Prompts for runtime template: bun / cloudflare-workers / nodejs / deno / aws-lambda
```

### Bun (raw CLI or library)
```bash
mkdir <name> && cd <name>
bun init -y
```

### Expo (React Native)
```bash
bun create expo <name>
```

Use `bun create expo`, NOT `npx create-expo-app` + manual Bun — the bun-created flow configures metro.config.js correctly.

## Flutter

```bash
# Default app — skeleton template is better than the default counter
flutter create --template=skeleton --org com.tomaspalsson <name>

# Package (Dart-only shareable code)
flutter create --template=package <name>

# Plugin (platform-specific via method channels)
flutter create --template=plugin --platforms=android,ios <name>
```

For serious Flutter apps, suggest Very Good CLI as an alternative:
```bash
dart pub global activate very_good_cli
very_good create flutter_app <name>
```

## Go

```bash
mkdir <name> && cd <name>
go mod init github.com/TomasPalsson/<name>
# Create cmd/<name>/main.go for CLI, or main.go at root
```

## SST (Serverless Stack v3 / Ion)

Scaffold base project first (usually Next.js or bare Node), then:
```bash
cd <existing-project>
npx sst@latest init
```

Or delegate to the `/sst` skill for full setup — that skill has detailed knowledge of `sst.config.ts`, resource linking, and deployment stages.

## Elixir / Phoenix

```bash
mix phx.new <name>
cd <name>
mix deps.get
mix ecto.create
```

Requires `mix phx_new` archive installed first:
```bash
mix archive.install hex phx_new
```

## Tauri (desktop, optionally + mobile)

```bash
cargo install create-tauri-app
cargo create-tauri-app <name>
# Interactive — select frontend framework
```

For mobile support (Tauri 2.0), answer YES to mobile prompts.

## Electron

```bash
bun create electron-app <name>
cd <name>
bun install
```

## Decision flags summary

| Tool | Init git? | Init .gitignore? | Sensible defaults? |
|---|---|---|---|
| `uv init` | Yes | Yes | Yes |
| `cargo new` | Yes | Yes | Yes (minimal) |
| `bun create vite` | No | Yes | Yes |
| `bun create next-app` | Yes | Yes | Yes |
| `sv create` | Yes | Yes | Yes (choose in wizard) |
| `flutter create` | Yes | Yes | No (use `--template=skeleton`) |
| `go mod init` | No | No | No (manual) |

**If the tool doesn't init git:** run `git init -b main` yourself AFTER writing `.gitignore`.

## Post-scaffold verification

```bash
# Confirm the project dir structure looks sane
ls -la <name>

# Verify git exists
cd <name> && git log --oneline 2>/dev/null | head -3

# Confirm .gitignore is stack-appropriate
head .gitignore
```
