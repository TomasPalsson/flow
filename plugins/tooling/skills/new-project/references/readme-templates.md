---
name: readme-templates
description: README skeletons by project type (library / CLI / web-app / service). Load during Stage 5a to pick the right template. Each template has different required sections — library READMEs need API reference, CLI READMEs need platform matrix + completions, web-app READMEs need env-vars table, service READMEs need runbook + dependencies.
---

# README Templates by Project Type

**Universal rules** (apply to ALL templates below):
- First 3 lines: what does this do / who is it for / how to run. This is what GitHub search and social-graph preview shows.
- Quickstart must work in under 30 seconds. No config required before first successful run.
- Max 5 badges on one line above description. No badge soup.
- Every code block copy-pasteable. No `$ ` prefix.
- No table of contents unless README exceeds ~80 lines.
- Do NOT fill in placeholder sections with lorem-ipsum. Leave `TODO:` stubs so the user knows what's missing.

---

## Library template (npm package, crate, pip package)

Users arrive from a package registry. They know what it does. They need the API shape FAST.

```markdown
# <name>

[![CI](https://github.com/<user>/<name>/workflows/CI/badge.svg)](...) [![version](...)](...) [![license](...)](...)

<one-sentence description — no heading, just text>

## Installation

\`\`\`bash
<single-command install>
\`\`\`

## Quickstart

\`\`\`<lang>
<5-15 lines of minimal working example — not a full app>
\`\`\`

## API

<function signatures with types — ideally auto-generated from code comments>

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| ... | ... | ... | ... |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

<MIT / Apache-2.0 / MIT OR Apache-2.0>
```

**Omit:** feature lists (the API is the feature list), architecture diagrams, deployment instructions, team bios.

---

## CLI template

Users arrive via `brew install` / `cargo install` / `curl | bash`. They need to know what flags to pass RIGHT NOW.

```markdown
# <name>

[![CI](...)](...)  [![version](...)](...)

<one-sentence description>

<optional: GIF or screenshot of the CLI in action>

## Installation

\`\`\`bash
# macOS (Homebrew)
brew install <name>

# Cargo / npm / pip / etc.
<install command>

# Manual (download from releases)
<url>
\`\`\`

## Usage

\`\`\`bash
<most common invocation — not full --help dump>
\`\`\`

## Commands

| Command | Flags | Description |
|---|---|---|
| ... | ... | ... |

## Configuration

<config file format, env vars, precedence order>

## Shell Completion

\`\`\`bash
# Bash
<name> completion bash > /etc/bash_completion.d/<name>

# Fish
<name> completion fish > ~/.config/fish/completions/<name>.fish

# Zsh
<name> completion zsh > /usr/local/share/zsh/site-functions/_<name>
\`\`\`

## Platform Support

| Platform | x86_64 | ARM64 |
|---|---|---|
| macOS | ✓ | ✓ |
| Linux | ✓ | ✓ |
| Windows | ✓ | - |

## License

<MIT / Apache-2.0>
```

**Critical:** Platform support matrix + shell completion. These are the two most-forgotten CLI sections.

---

## Web App template

Audience split: developers cloning to run locally + evaluators deciding to self-host. Serve both.

```markdown
# <name>

[![CI](...)](...)  [![license](...)](...)

<description — one paragraph>

<screenshot of the UI>

## Live Demo

<url or "No public demo">

## Tech Stack

- Framework: <e.g., Next.js 16 with App Router>
- Database: <e.g., PostgreSQL on RDS>
- Auth: <e.g., Lucia + session cookies>
- Deploy target: AWS via SST v3 (or specify alternative)

## Prerequisites

- <Node 22 / Bun 1.2 / Python 3.12>
- <Docker, if docker-compose is used>
- <other>

## Quick Start

\`\`\`bash
git clone <url>
cd <name>
cp .env.example .env   # fill in values
<package-manager> install
<package-manager> run dev
\`\`\`

Then open <http://localhost:3000>.

## Environment Variables

| Variable | Required | Description | Example |
|---|---|---|---|
| DATABASE_URL | yes | Postgres connection string | `postgres://user:pass@localhost:5432/db` |
| SESSION_SECRET | yes | Random 32-byte hex | `openssl rand -hex 32` |
| ... | ... | ... | ... |

See [.env.example](.env.example) for the full list.

## Deployment

Default target: **AWS via SST v3**.

\`\`\`bash
bun run sst deploy --stage production
\`\`\`

See [sst.config.ts](sst.config.ts) for infrastructure definition. For stage-specific env vars use SST secrets: `bun run sst secret set NAME VALUE --stage production`.

## License

<license>
```

**Critical:** The Environment Variables table is the most-neglected section. Include every variable with a description AND a non-secret example.

---

## Service / Microservice template

Audience is internal engineers, SREs, on-call responders. README doubles as operational runbook reference.

```markdown
# <service-name>

**Owner:** <team> | **On-call:** <PagerDuty link> | **Last reviewed:** <YYYY-MM-DD>

## Purpose

<what does this service do, what systems does it interact with>

## SLOs

- p99 latency: <target>
- Error budget: <target>
- Dashboards: <link>

## Dependencies

**Upstream** (services this calls):
- <name> — <why>

**Downstream** (services that call this):
- <name> — <why>

## Local Development

\`\`\`bash
<setup commands>
\`\`\`

## Configuration

| Variable | Required | Description |
|---|---|---|
| ... | ... | ... |

## Deployment

\`\`\`bash
<deploy command>
<rollback command>
<verify command>
\`\`\`

## Runbook

### Common incidents

**Alert: <name>**
- Check: <dashboard/query>
- Typical cause: <...>
- Mitigation: <...>

## Architecture

\`\`\`mermaid
flowchart LR
  A[client] --> B[<this service>]
  B --> C[(database)]
  B --> D[other service]
\`\`\`

(Prefer inline Mermaid over Confluence links — those rot.)

## On-Call Notes

- <known gotchas>
- <common false alarms>

## License

<internal / license>
```

**Critical:** `**Last reviewed:** <date>` at top prompts quarterly freshness checks. Service READMEs rot fastest.

---

## Quick reference: which sections are critical by type

| Section | Library | CLI | Web App | Service |
|---|---|---|---|---|
| API reference | ✓✓✓ | — | — | — |
| Install methods | ✓ | ✓✓✓ | — | — |
| Platform support matrix | — | ✓✓✓ | — | — |
| Shell completion | — | ✓✓✓ | — | — |
| Env vars table | — | — | ✓✓✓ | ✓✓✓ |
| Dependencies graph | — | — | — | ✓✓✓ |
| Runbook | — | — | — | ✓✓✓ |
| Deploy instructions | — | ✓ | ✓✓ | ✓✓✓ |
| SLOs / metrics | — | — | — | ✓✓✓ |
| Screenshot/GIF | — | ✓ | ✓✓ | — |

`✓✓✓` = required. `✓✓` = strongly recommended. `✓` = nice to have. `—` = omit.
