---
name: stack-decisions
description: Signal-based stack inference from natural-language project descriptions, plus decision trees for ambiguous cases. Load when the description doesn't unambiguously name a stack.
---

# Stack Decision Guide

## Signal → Stack inference table

Scan the description for these signals. Multiple matches raise confidence. Conflicting signals trigger a clarification question.

| Signal in description | Implied stack |
|---|---|
| "Rust", "cargo", "static binary", "performance-critical CLI" | Rust (`cargo new --bin`) |
| "Python", "FastAPI", "script", "data", "ML", "AI", "LLM", "notebook" | Python + uv |
| "FastAPI" specifically | Python + uv + FastAPI |
| "Django" / "admin panel + auth batteries" | Python + uv + Django |
| "Next.js", "SSR", "full-stack web", "SaaS" | Next.js (`bun create next-app`) |
| "React", "SPA", "frontend", "dashboard" (no SSR mention) | React + Vite TS (`bun create vite --template react-ts`) |
| "Svelte", "SvelteKit", "small team web" | SvelteKit (`npx sv create`) |
| "Astro", "blog", "content site", "marketing site", "docs site" | Astro (`npm create astro@latest`) |
| "Flutter", "mobile", "iOS + Android from one codebase" | Flutter (`flutter create --template=skeleton`) |
| "React Native", "Expo", "cross-platform mobile for JS team" | Expo (`bun create expo`) |
| "Hono", "edge API", "Cloudflare Workers", "low cold-start" | Hono (`bun create hono`) |
| "Node CLI", "TypeScript CLI" | Node/Bun (`bun init` + manual CLI deps) |
| "SST", "serverless", "AWS Lambda", "deploy to AWS", "full-stack AWS" | SST — scaffold base then invoke `/sst` skill |
| ANY web/API + "deploy" mentioned | Default to AWS + SST — offer `/sst` handoff after scaffold |
| "Electron" / "desktop JS" | Electron (`bun create electron-app`) |
| "Tauri" / "desktop + mobile from one codebase" | Tauri (`cargo install create-tauri-app && cargo create-tauri-app`) |
| "Go", "cloud microservice", "devops tool" | Go (`go mod init`) |
| "Elixir" / "massive concurrent connections" / "chat" | Phoenix (`mix phx.new`) |

## Decision trees for ambiguous cases

### "Backend API" (no language given) — MUST ASK

Options to present:
- Python (FastAPI + uv) — best if ML/AI is involved
- TypeScript (Hono on Bun) — best for edge/serverless
- TypeScript (NestJS) — best for complex domain + opinionated
- Go — best for cloud microservices, DevOps tooling
- Rust (Axum) — best for sub-millisecond latency, memory safety

### "Web app" (no framework given)

```
Is it primarily content (blog/docs/marketing)?
├── YES → Astro
└── NO (application: forms, auth, dashboards)
    ├── "Small team / side project" in description? → SvelteKit
    ├── "Enterprise" / "hiring" in description? → Next.js
    └── Default when unsure → Next.js (largest safety net)
```

### "CLI tool"

```
Needs to distribute as a single static binary?
├── YES
│   ├── Performance critical? → Rust (cargo new)
│   └── Simple cross-platform? → Go (go mod init)
└── NO (script or package-manager distribution)
    ├── Python ecosystem → uv init --package
    └── Node/TS ecosystem → bun init + commander/clack
```

### "Mobile app"

```
Does the team already know JavaScript/React?
└── YES → Expo (React Native)

Does it need pixel-perfect animations / game-like UI?
└── YES → Flutter

Enterprise / deep native API integration?
└── Native (Swift + Kotlin) or Kotlin Multiplatform

Default when no signal → Expo (fastest iteration, lowest initial cost)
```

### "Desktop app"

```
Team knows JavaScript → Electron
Size-conscious / Rust-willing → Tauri 2.0
Desktop + mobile from one codebase → Tauri 2.0 (only option)
```

### "LLM / AI / Agent app"

```
Python-friendly?
├── YES → uv init --package + anthropic SDK + FastAPI (for serving)
│   Multi-step agent orchestration? → add langgraph or strands-agents
└── NO, TypeScript team → bun + @anthropic-ai/sdk or Vercel AI SDK
```

## Defaults cheat sheet (when user says "you pick")

| Project type | 2026 default | Deploy target |
|---|---|---|
| Web app (full-stack) | Next.js (App Router) + bun | AWS via SST |
| Web app (small team/solo) | SvelteKit | AWS via SST |
| Content site / blog | Astro (Cloudflare-native) | AWS via SST or Cloudflare (ask) |
| Python API | FastAPI + uv | AWS via SST (Lambda container) |
| Python CLI | uv init --package | n/a (distribute via PyPI) |
| TS API (edge) | Hono on Bun | AWS via SST |
| CLI binary | Go (simple) or Rust (perf-critical) | n/a (release binaries via GitHub) |
| Mobile | Expo (JS) or Flutter (UI-first) | App stores |
| Desktop | Tauri (small) or Electron (full npm) | GitHub Releases |
| Database | PostgreSQL (default) or SQLite (read-heavy/edge) | RDS / Aurora via SST |

**Deploy default policy:** for anything web/API/server, default deployment target is **AWS via SST v3 (Ion)**. The `/sst` skill handles all SST-specific config. Only suggest alternatives (Vercel, Cloudflare, Fly) if the user explicitly asks or the project is incompatible with SST.

## Do NOT start new projects with

- **Create React App** — deprecated, no security patches. Use Vite instead.
- **Gatsby for content** — Astro replaced it. Use Astro.
- **Custom Webpack config** — Vite, Turbopack, or Rspack instead.
- **Pages Router** in new Next.js — App Router only.
- **`setup.py`** for new Python — `pyproject.toml` + uv.
- **Poetry for new apps** — uv is the 2026 default (keep Poetry for library publishing if preferred).
- **Express.js** — Hono, Fastify, or Elysia are faster and edge-native.
- **Cordova/Ionic** — Expo or Flutter.

## When to ask vs. infer

**Infer (skip asking)** when:
- Stack keyword is explicit ("Rust CLI", "FastAPI service")
- Description + type have a single dominant default ("blog" → Astro)
- User said "you decide" / "sensible defaults"

**Ask** when:
- Multiple plausible stacks match (e.g., "API" without language)
- Description is high-stakes (production service, team project) AND ambiguous
- User mentioned a constraint Claude can't reconcile (e.g., "must work on Cloudflare Workers AND use Prisma" — conflicts)
