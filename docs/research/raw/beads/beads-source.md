# Beads (`bd`) — source-level research

Repo: https://github.com/gastownhall/beads (org resolved directly, no need to
fall back to steveyegge/beads — that name lives on only as the Go module path).
Cloned `--depth 1` to
`/tmp/claude-1000/-home-tomas--dotfiles/65f7117c-29cb-4945-b826-0a4f06e8ef17/scratchpad/repos/beads`.
HEAD at clone time: `c0d8da4` "fix(storage/uow): retry transient ping failures
during openDB bootstrap (#6003)", 2026-09-02. [PRIMARY, repo, 2026-09-02]

## What it is

Beads is a CLI (`bd`) issue tracker purpose-built for AI coding agents:
dependency-aware "beads" (issues) with hash-based IDs, a `ready` queue of
unblocked work, and semantic compaction to keep closed history from bloating
an agent's context. Author: Steve Yegge. It is explicitly *not* a Jira
replacement or long-range planning tool — narrow scope by design.
[PRIMARY, `README.md`, `plugins/beads/skills/beads/SKILL.md`]

Scale/traction (GitHub API, 2026-09-04): 26,876 stars, 1,814 forks, 936 open
issues, 1,640 closed issues, 2,539 merged PRs, 30 listed contributors, repo
created 2025-10-12 — so ~11 months old and growing very fast (65 commits in
the last 14 days alone via `gh api commits?since=...`). [PRIMARY, GitHub API
via `gh api repos/gastownhall/beads`, queried 2026-09-04]

## The architecture claim that matters most: storage moved off SQLite/JSONL onto Dolt

This is the single biggest divergence between what's on the web about beads
and what the current source actually does, and it should headline any
write-up.

- **Current (source of truth, `docs/architecture/dolt.md`, primary):** "Beads
  uses Dolt as its storage backend... Dolt provides a version-controlled SQL
  database with cell-level merge, native branching, and two deployment
  modes": **embedded mode** (in-process Dolt engine, `.beads/embeddeddolt/`,
  single-writer, default for solo use — "no server, no ports, no PID files")
  and **server mode** (`dolt sql-server`, `.beads/dolt/`, multi-writer, for
  orchestrators/concurrent agents). Dolt is pinned to **2.2.0** specifically
  because 2.3.0 (released 2026-08-13) "regressed `CALL DOLT_RESET('--hard')`"
  — measured 3/60 fresh databases broken on 2.3.0 vs 0/60 on 2.2.0, and
  `bd flatten` / `bd admin compact` / merge-abandon paths all depend on that
  call. [PRIMARY, `docs/architecture/dolt.md`]
- SQLite is explicitly **legacy**: "Migrate from SQLite (Legacy)... The `bd
  migrate --to-dolt` command was removed in v0.58.0. For pre-0.50
  installations with JSONL data, use the migration script:
  `scripts/migrate-jsonl-to-dolt.sh`." JSONL export
  (`.beads/issues.jsonl`) still exists but only "for migration and
  interoperability; they do not capture Dolt branches, full commit history,
  working-set state, or non-issue tables" — `bd backup`/`bd backup restore`
  is the real backup path. [PRIMARY, `docs/architecture/dolt.md`]
- Issue data itself is stored in Dolt under `refs/dolt/data`, separate from
  git branch commits; worktrees share one `.beads` workspace by default, and
  cross-clone sync is `bd dolt push` / `bd dolt pull`. [PRIMARY,
  `docs/reference/worktrees.md`]
- The older "SQLite cache + `issues.jsonl` + background sync daemon"
  architecture that most public writeups (including the task brief's own
  framing) describe is **gone from the current repo** — no `daemon`
  reference anywhere in `README.md`, `AGENTS.md`, or the architecture docs
  I grepped. [PRIMARY, grep over cloned repo, confirmed absence]
- Confirmed against secondary sources: Better Stack's guide (undated on
  page, indexed article) still describes "SQLite (`beads.db`) ... syncs to
  `issues.jsonl` ... a background daemon automatically exports SQLite
  changes ... imports remote changes." [SECONDARY,
  https://betterstack.com/community/guides/ai/beads-issue-tracker-ai-agents/,
  fetched 2026-09-04] — and Paddo's deep-dive similarly says "Beads stores
  everything in version-controlled markdown files within Git... A SQLite
  cache enables fast queries." [SECONDARY,
  https://paddo.dev/blog/beads-memory-for-coding-agents/, fetched
  2026-09-04]. Both are now stale descriptions of a pre-Dolt beads. The
  project's own `ARTICLES.md` warns of exactly this: "the development pace
  of Beads is very fast and it's easy for offsite content to become
  outdated." [PRIMARY, `ARTICLES.md`]

## Data model

- **Hash-based IDs** (`bd-a1b2`, `bd-a3f8e9.1` for hierarchy up to 3 levels):
  generated from title + creation timestamp + random salt, so two agents
  creating issues concurrently on different branches never collide, unlike
  sequential `#7`/`#7` IDs that collide on merge. [PRIMARY,
  `docs/core-concepts/hash-ids.md`]
- **Dependency types** (`docs/core-concepts/dependencies.md`): blocking
  types that affect `bd ready` — `blocks` (default), `parent-child`,
  `conditional-blocks` (runs only if the dependency fails),
  `waits-for` (fan-in on all children); non-blocking/annotation-only types —
  `related`, `tracks`, `discovered-from`, `caused-by`, `validates`,
  `supersedes`. Set via `bd dep add A B --type X`. [PRIMARY,
  `docs/core-concepts/dependencies.md`]
- Task's brief mentions "blocks/related/parent-child/discovered-from" as the
  full dependency-type set — the current source has a materially larger set
  (10 types total, including `conditional-blocks` and `waits-for` for
  fan-out/fan-in orchestration), another sign the public mental model of
  beads lags the code.

## CLI surface (from `cmd/bd/`, cross-checked against `docs/cli-reference/`)

Core loop (per `plugins/beads/skills/beads/SKILL.md`, "Session Protocol"):
`bd ready` → `bd show <id>` → `bd update <id> --claim` (atomic:
assignee + status=in_progress) → work, adding notes → `bd close <id> --reason
"..."` → `bd dolt push`. [PRIMARY]

- `bd create "Title" -p 0`, with `--parent`, `-t <type>`, etc.
  (`cmd/bd/create.go` + friends — 25+ create-related source/test files,
  including `create_atomic.go`, `create_deps.go`, `create_form.go`).
- `bd dep add/remove`, alias `bd dep rm` (`cmd/bd/dep.go`).
- `bd ready [--priority] [--label] [--assignee] [--unassigned] [--claim]
  [--json]` (`cmd/bd/ready.go`, `ready_input.go`).
- `bd close <id> --reason "..."` (`cmd/bd/close.go`, plus
  `close_direct.go`, `close_gate_test.go`, `close_routing_test.go`,
  `close_last_touched_test.go`).
- `bd sync`, `bd dolt push`/`bd dolt pull` (`cmd/bd/sync.go`,
  `sync_git.go`, `sync_push_pull.go`, `sync_remote.go`).
- `bd compact [--days N] [--dry-run] [--force]` — this is **Dolt commit
  history squashing** (garbage-collection-adjacent), not the semantic
  "memory decay" feature. From `docs/cli-reference/compact.md`: "Squash Dolt
  commits older than N days into a single commit... For semantic issue
  compaction (summarizing closed issues), use `bd admin compact`. For full
  history squash, use `bd flatten`." [PRIMARY]
- `bd admin compact` — the actual "memory decay" feature (see below).
- `bd list`, `bd show <id> [--long]`, `bd update <id>` (`cmd/bd/list.go`,
  `show.go`, `update.go`).
- `bd prime` — prints agent workflow context + persistent memories; this is
  what `AGENTS.md`/`CLAUDE.md`/hooks tell agents to run at session start
  (`cmd/bd/prime.go`, plus `prime_divergence.go`, `prime_memory_caps_test.go`,
  `prime_gemini_hook_test.go`). `bd onboard` is the human-facing setup/print
  path (`cmd/bd/onboard.go`).
- `bd remember "insight"` — stores project memory injected by `bd prime`
  later; README explicitly says "do not create MEMORY.md files" instead.
  [PRIMARY, `README.md`]
- Admin/maintenance: `bd admin cleanup` (hard-delete closed issues,
  `--cascade`, `--ephemeral`, `--older-than`, requires `--force`), `bd
  prune`/`bd purge` (reference-aware protection — skips closed beads still
  cited by open ones, unless `--ignore-references`), `bd flatten`, `bd
  doctor [--fix]`, `bd hooks install/list/uninstall`, `bd backup
  init/sync/restore`. [PRIMARY, `docs/cli-reference/admin.md`,
  `docs/architecture/dolt.md`]

## "Memory decay" / compaction — deterministic vs. AI-assisted

`bd admin compact` ("Compact old closed issues using semantic
summarization... permanent graceful decay - original content is discarded")
has three explicit modes [PRIMARY, `docs/cli-reference/admin.md`]:

1. **Analyze** — export candidates for agent review, `bd compact --analyze
   --json`, no API key needed.
2. **Apply** — accept an agent-provided summary, `bd compact --apply --id
   bd-42 --summary summary.txt`, no API key needed. This is the
   "agent-driven workflow (recommended)" — i.e., the calling coding agent
   (Claude, etc.) writes the summary itself, deterministically applied by
   `bd`.
3. **Auto** — "AI-powered compaction (requires ANTHROPIC_API_KEY or
   ai.api_key, **legacy**)" — `bd compact --auto --dry-run` /
   `--auto --all`. Explicitly marked legacy in favor of the agent-driven
   analyze/apply flow.

Tiers: "Tier 1: Semantic compression (30 days closed, 70% reduction)"; "Tier
2: Ultra compression (90 days closed) - planned, not yet implemented."
[PRIMARY] So the semantic-decay feature is deterministic-plumbing +
prompted-content: `bd` decides *what* is eligible and *applies* the
resulting summary transactionally, but *writing* the summary is delegated to
whatever LLM agent is driving it (no bundled model call in the recommended
path).

Separately, `bd compact --dolt` runs Dolt garbage collection to reclaim disk
from the auto-commit-per-mutation history — a different, purely mechanical
axis of "compaction" from the semantic one. [PRIMARY,
`docs/cli-reference/admin.md`]

## What's deterministic vs. prompted, overall

- **Deterministic (pure CLI/DB, no model involved):** ID generation (hash of
  title+timestamp+salt), dependency graph maintenance and `bd ready`
  resolution, claim/assign atomicity, git hook shims
  (`pre-commit`/`post-merge`/`pre-push`/`post-checkout`/`prepare-commit-msg`
  — thin shims calling `bd hooks run <name>`, upgraded transparently when
  `bd` is upgraded), Dolt sync/push/pull/merge mechanics, `bd doctor`
  diagnostics/fixes, `bd prune`/`purge`/`flatten`/`admin cleanup` deletion
  logic (with reference-aware protection), `bd compact` (Dolt history
  squash). [PRIMARY, `docs/reference/git-integration.md`,
  `docs/architecture/dolt.md`]
- **Prompted / agent-supplied (bd is plumbing, the agent supplies
  judgment):** the actual text of `bd admin compact --apply` summaries in
  the recommended flow; whatever an agent chooses to `bd remember`; the
  optional legacy `--auto` compaction path that does call an Anthropic model
  directly via `ANTHROPIC_API_KEY`.

## Claude Code integration surface

- **Plugin manifest** `plugins/beads/.claude-plugin/plugin.json` (v1.2.2)
  declares Claude Code lifecycle hooks:
  ```json
  "hooks": {
    "SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": "bd prime"}]}],
    "PreCompact":   [{"matcher": "", "hooks": [{"type": "command", "command": "bd prime"}]}]
  }
  ```
  i.e., beads context (ready work + persistent memories) is injected both at
  the start of a Claude Code session **and** right before Claude's own
  context-window auto-compaction — directly targeting the context-loss
  problem beads exists to solve. [PRIMARY,
  `plugins/beads/.claude-plugin/plugin.json`]
- **Skill**: `plugins/beads/skills/beads/SKILL.md`, name `beads`, version
  `0.60.0`, `allowed-tools: "Read,Bash(bd:*)"`, `compatible-with:
  [claude-code, codex]`. Ships a `bd vs TodoWrite` decision rule ("Will I
  need this context in 2 weeks? YES = bd, NO = TodoWrite") and a "Session
  Protocol" (ready → show → claim → notes → close → dolt push). Also ships
  ~29 command reference files under
  `plugins/beads/skills/beads/commands/` (create.md, ready.md, close.md,
  compact.md, sync.md, dep.md, epic.md, ...). [PRIMARY]
- **Codex parity**: `.codex-plugin/hooks/hooks.json` wires the equivalent
  `SessionStart` (full `bd prime` injection), `PreCompact` (warns if
  `bd prime --memories-only` can't run), `PostCompact` (records a one-shot
  refresh marker), and `UserPromptSubmit` (injects `bd prime` once after a
  compaction, then clears the marker) — i.e. Codex gets a slightly richer
  compaction-aware refresh cycle than the plain Claude Code hook pair.
  [PRIMARY, `plugins/beads/README.md`]
- **`bd init` / `bd setup`**: `bd init` writes/updates `AGENTS.md` by
  default and installs Claude/Codex integration unless `--skip-agents` or
  `--stealth`; `bd setup claude` "installs hooks/settings" specifically;
  `bd setup --list` enumerates supported agents (codex, factory, claude,
  mux, cursor, ...). [PRIMARY, `README.md`]
- **MCP server**: separate PyPI package `beads-mcp` (`uv tool install
  beads-mcp` / `pip install beads-mcp`), for **CLI-unavailable**
  environments only — Claude Desktop (no shell), Sourcegraph Amp without
  shell, etc. Docs explicitly say: "Prefer CLI + hooks when shell is
  available - it's more context efficient." [PRIMARY,
  `docs/integrations/mcp-server.md`] So the MCP server is a fallback, not
  the primary integration path for Claude Code itself (which uses the
  plugin/hooks/skill trio instead).
- Repo's own dogfooding: the beads repo ships its own `AGENTS.md` (11.7 KB)
  and `AGENT_INSTRUCTIONS.md` (19.2 KB) plus a `.claude/skills/beads-docs/`
  skill and `.claude/settings.json` — beads is used to manage its own
  development. [PRIMARY, repo root listing]

## Multi-agent / worktree support

- Agent coordination primitives: `bd assign <id> <agent>`, `bd update <id>
  --claim` (atomic self-claim), `bd ready --claim --json` (claim-first-match),
  release via `bd assign <id> ""` or `bd update <id> --status open`.
  Documented patterns: sequential handoff (comment + reassign), parallel
  work (coordinator assigns N issues to N agents), fan-out/fan-in (child
  issues under an epic, a merge issue depends on all children).
  [PRIMARY, `docs/multi-agent/coordination.md`]
- Worktrees: "Beads works from normal Git worktrees without a separate sync
  branch... All worktrees in the same repository use the same beads
  workspace unless you override discovery with `BEADS_DIR`." An external
  `BEADS_DIR` lets one issue-tracker workspace serve multiple unrelated code
  checkouts. Legacy note: an older `sync.branch` design that created hidden
  `.git/beads-worktrees/<branch>/` worktrees "has been removed" — recovery
  doc still explains how to clean up stale remnants of it. [PRIMARY,
  `docs/reference/worktrees.md`]
- Federation/routing docs exist for larger deployments:
  `docs/multi-agent/{federation,bucket-federation,routing,multi-repo-migration}.md`,
  plus an `internal/routing` package and a `FEDERATION-SETUP.md` at repo
  root — federation is real enough to have its own setup doc and package,
  though I did not deep-read it. [PRIMARY, directory listing +
  `FEDERATION-SETUP.md` presence]

## Git integration and conflict handling

- `.beads/` layout: `config.yaml` and `metadata.json` are git-tracked;
  `embeddeddolt/` (embedded mode) and `dolt/` (server mode) are
  git-ignored — `bd init` writes `.beads/.gitignore` automatically; docs
  explicitly warn "Never track the database directory... in git or via Git
  LFS." [PRIMARY, `docs/reference/git-integration.md`]
- Git hooks (`bd hooks install`) are thin shims calling `bd hooks run
  <hook-name>`, so upgrading `bd` updates hook behavior without
  reinstalling; shims use section markers to coexist with pre-existing hook
  content. Detects and coexists with lefthook, husky, pre-commit, prek, hk,
  overcommit, yorkie, simple-git-hooks — `bd doctor --fix` reinstalls with
  `--chain` to keep an external manager's hooks running. Hook install is
  worktree-aware (resolves the shared git dir). [PRIMARY,
  `docs/reference/git-integration.md`]
- **Merge conflicts are Dolt's problem, not line-based git diff/merge**:
  conflicts surface as `bd dolt pull` failures; the documented recovery
  runbook is `cp -r .beads .beads.backup` → `bd doctor` → `bd doctor --fix`
  → verify with `bd list`/`bd stats` → `bd dolt push`. [PRIMARY,
  `docs/recovery/merge-conflicts.md`]
- Storage-reclaim operations (`bd flatten`, Dolt-history compaction inside
  `bd admin compact`, and the pull/sync merge-abandon fallback) all finish
  with a Dolt hard-reset, which is exactly the operation broken on Dolt
  2.3.x for ~5% of fresh databases — the reason the project pins 2.2.0.
  [PRIMARY, `docs/architecture/dolt.md`]

## Release cadence

- No git tags visible in the shallow clone (expected with `--depth 1`); via
  GitHub API [PRIMARY, `gh api repos/gastownhall/beads/releases`, queried
  2026-09-04]:
  - `v1.3.0-rc.1` — 2026-08-31
  - `v1.2.2` — 2026-08-15 (`v1.2.2-rc.1` — 2026-08-15)
  - `v1.2.1` — 2026-08-11
  - `v1.1.2` — 2026-07-26
  - i.e., roughly a release (often with an rc first) every 1–3 weeks.
- Latest commit at clone time: 2026-09-02 (`c0d8da4`), pushed-at per API:
  2026-09-04T13:00:37Z — active same-day commits.
- CHANGELOG.md is 514 KB and structured Keep-a-Changelog style with an
  `[Unreleased]` section actively accumulating detailed entries (e.g. an
  `actor` column added to the events journal, `bd count
  --metadata-field` filters) — indicates a genuinely maintained changelog,
  not a stub. [PRIMARY, `CHANGELOG.md` head]

## Weaknesses visible in code/issues

- **Storage-layer data-loss bugs, repeatedly, through mid-2026** (GitHub
  issue search, all now closed but instructive of the project's stability
  history) [PRIMARY, `gh api search/issues ... data loss`, 2026-09-04]:
  - #911 "bd sync export-before-pull causes data loss" (2026-01-05)
  - #1623 "Daemon mutation-triggered exports overwritten by auto-imports
    causing data loss" (2026-02-09) — from the pre-Dolt daemon era
  - #1669 "bd migrate --to-dolt creates prefix-named DB but bootstrap check
    hardcodes 'beads', causing data loss re-import" (2026-02-10)
  - #2251 "Dolt migration in one clone causes data loss in other
    independent clones via committed metadata.json" (2026-03-01)
  - #3822 "Import/Export JSONL in server mode may result in data loss"
    (2026-05-08)
  - #4069 "auto-export uses default filter, drops infra/ephemeral rows...
    (89% data loss in our workspace)" (2026-05-21)
  All closed/fixed, but the pattern — recurring data-loss bugs concentrated
  around the SQLite→Dolt migration and export/import paths, as recently as
  three months before this research date — says the storage layer is still
  actively hardening, not settled. Anyone adopting beads today should treat
  `bd backup` as mandatory, not optional.
- **Dolt operational fragility reported by users**: #2559 "On system
  restart, or beads updates, connecting to dolt fails" (16 comments,
  reactions:2, still shows in top-reacted open issues); #3392 "bd dolt
  auto-start is nondeterministic + stale-lock races leave tracker
  unreachable"; #3596 "`bd human respond` errors with 'storage is nil' in
  embedded mode"; #4380 "Aux row re-key crashes the migration pass on
  dolt#11131-class drifted storage (server panic 'invalid hash length:
  19')" (26 comments) — these point at real rough edges in the
  embedded-Dolt bootstrap/locking path. [PRIMARY, `gh api
  search/issues?q=repo:gastownhall/beads...`, 2026-09-04]
- **Dolt itself is a moving dependency the beads team doesn't fully
  trust**: the project pins to Dolt 2.2.0 specifically because 2.3.0
  regressed a hard-reset call that three of beads' own maintenance
  operations depend on — a third-party correctness bug the beads team had
  to measure and route around themselves. [PRIMARY,
  `docs/architecture/dolt.md`] This is a structural fragility: beads'
  reliability is coupled to an actively-changing embedded database engine.
- **Public knowledge lags the code substantially.** Two independent,
  reasonably careful secondary write-ups (Better Stack, Paddo) both
  describe an architecture — SQLite + JSONL + background sync daemon —
  that no longer exists in the current source, which has moved to Dolt with
  no daemon. The project's own `ARTICLES.md` flags this risk itself. Any
  answer sourced only from blog posts or general knowledge risks describing
  a version of beads roughly 6-9+ months stale.
- **Feature gaps requested but not yet built**, per open, low-drama issues:
  `bd edit --all` ($EDITOR-based full-field edit), `bd attachment`, `.beads/
  version`-pinned per-repo `bd` version management (#3006) — normal
  backlog churn for a fast-moving CLI, not urgent, but shows some
  ergonomics (attachments, bulk field edit, version pinning) are still
  missing.
- Tier 2 "ultra compression" for the memory-decay feature is explicitly
  "planned, not yet implemented" — the semantic compaction story is only
  half-built per the CLI's own doc. [PRIMARY, `docs/cli-reference/admin.md`]

## Verdict on maturity

Beads is not a toy weekend project pretending to be a mature system — it has
substantial engineering behind it: 2,840 Go source files with 1,597
`_test.go` files (>50% of files are tests), a 514 KB actively-maintained
changelog, 30 contributors, 2,539 merged PRs, weekly-ish tagged releases with
release candidates, and a documented pin/measurement discipline around its
core dependency (Dolt version regression testing). The Claude Code
integration is real and deliberately designed around Claude's own
context-compaction behavior (SessionStart + PreCompact hooks both calling
`bd prime`), not a bolted-on afterthought.

At the same time, it is young (repo created 2025-10-12, so ~11 months old
at research time) and has undergone a full storage-engine rewrite
(SQLite/JSONL/daemon → Dolt embedded/server) mid-flight, which produced a
recurring class of data-loss bugs through at least May 2026 and ongoing
Dolt-bootstrap fragility reports as of the current open-issue set. The
project is transparent and responsive about this (detailed changelog,
measured Dolt-version pins, `bd doctor`/`bd backup` tooling, reference-aware
deletion protection) — this reads as an actively-hardening, fast-iterating
project with real engineering discipline, not an abandoned or careless one.
But "distributed graph database as the backbone of your agent's memory,
11 months old, still stabilizing its storage layer" is a fair one-line
characterization: promising and unusually well-engineered for its age, not
yet a boringly stable dependency. Anyone adopting it in a serious multi-agent
setup should pin the Dolt version as documented, treat `bd backup` as
mandatory, and expect to track a genuinely fast-moving changelog.

## Gaps / what I could not verify

- **WebSearch budget was exhausted session-wide before I could run it** (the
  tool reported "this session has used its web search budget (200 of 200
  WebSearch calls)" on my first two queries) — I could not do the requested
  ≥6 WebSearch queries. I substituted `gh api` (GitHub search/issues,
  releases, repo metadata — all primary, authenticated) for cadence/issue
  research, and WebFetch (which still worked) for 4 external pages,
  reaching 8 fetched pages total (2 docs/repo pages + 1 Yegge Medium post
  attempt [blocked, 403] + 1 more Yegge post attempt [blocked, 403] + 2
  successful community posts + repo/docs site fetches). Medium blocks
  WebFetch with HTTP 403 on both Yegge URLs I tried
  (`introducing-beads-a-coding-agent-memory-system-637d7d92514a` and
  `beads-blows-up-a0a61bb889b4`), so I could not directly quote Yegge's own
  framing of the "50 First Dates" problem or adoption-growth claims from
  "Beads Blows Up" — only the article titles/URLs from `ARTICLES.md` and
  secondhand mentions in the WebFetch summary of the docs site. If exact
  quotes from those posts matter, they need a different fetch path (browser
  tool, Google cache, or the user's own Medium access).
- I did not deep-read `internal/routing`, `internal/molecules`,
  `internal/formula`, or the federation docs beyond confirming they exist —
  multi-repo federation is real but under-characterized here.
- I did not independently verify the Dolt 2.3.0 regression claim against
  Dolt's own issue tracker/changelog — I'm reporting beads' own measured
  table as primary-source-for-beads, but it is beads' characterization of a
  third-party bug, not something I cross-checked upstream.
- No adoption/production-usage numbers beyond GitHub stars/forks/issue
  counts — no telemetry or user-survey data was available to me.

## Source check (independent)

Re-cloned repo re-inspected at the same commit (`c0d8da4`, "fix(storage/uow):
retry transient ping failures during openDB bootstrap (#6003)", confirmed via
`git log -1` in the existing clone). The 6 most load-bearing claims in this
document were checked directly against the cited files.

1. **CONFIRMED** — Storage backend is Dolt, with embedded and server
   deployment modes, replacing SQLite.
   Cited: `docs/architecture/dolt.md`.
   Quote (file header, lines 1-14): "Beads uses Dolt as its storage backend.
   Dolt provides a version-controlled SQL database with cell-level merge,
   native branching, and two deployment modes." ... "Single-binary option —
   embedded mode for solo users (no server needed)" ... "Multi-writer
   support — server mode enables concurrent agents." Exact match to the
   document's paraphrase.

2. **CONFIRMED** — Dolt pinned to 2.2.0 because 2.3.0 regressed
   `CALL DOLT_RESET('--hard')`, measured 3/60 broken on 2.3.0 vs 0/60 on
   2.2.0.
   Cited: `docs/architecture/dolt.md`.
   Quote (lines 47-70): "Beads pins Dolt to **2.2.0**." ... "Dolt 2.3.0
   (released 2026-08-13) regressed `CALL DOLT_RESET('--hard')`." Table:
   "| Dolt version | Fresh databases with `DOLT_RESET('--hard')` broken |"
   ... "| 2.2.0 | 0 / 60 |" ... "| 2.3.0 | 3 / 60 |". Numbers match exactly.

3. **CONFIRMED** — `bd migrate --to-dolt` was removed in v0.58.0; the
   `scripts/migrate-jsonl-to-dolt.sh` path replaces it for pre-0.50 JSONL
   installs.
   Cited: `docs/architecture/dolt.md`.
   Quote (line 133): "**Note:** The `bd migrate --to-dolt` command was
   removed in v0.58.0." (line 137): "scripts/migrate-jsonl-to-dolt.sh".
   Exact match.

4. **CONFIRMED** — Dependency-type set is larger than the task brief's
   assumed "blocks/related/parent-child/discovered-from": 4 blocking types
   (`blocks`, `parent-child`, `conditional-blocks`, `waits-for`) plus 6
   non-blocking annotation types (`related`, `tracks`, `discovered-from`,
   `caused-by`, `validates`, `supersedes`) — 10 total.
   Cited: `docs/core-concepts/dependencies.md`.
   Quote (lines 42-56): table rows `blocks` (default) | B cannot start until
   A closes; `parent-child` | Children blocked when parent blocked;
   `conditional-blocks` | B runs only if A fails; `waits-for` | B waits for
   all of A's children; then `related`, `tracks`, `discovered-from`,
   `caused-by`, `validates`, `supersedes`. Count and names match exactly
   (10 types).

5. **CONFIRMED** — `bd admin compact` has three modes (Analyze/Apply/Auto),
   Auto is marked legacy and requires `ANTHROPIC_API_KEY`, and there are two
   compression tiers with Tier 2 "planned, not yet implemented."
   Cited: `docs/cli-reference/admin.md`.
   Quote (lines 68-81): "Compact old closed issues using semantic
   summarization." ... "This is permanent graceful decay - original content
   is discarded." ... "Analyze: Export candidates for agent review (no API
   key needed)" / "Apply: Accept agent-provided summary (no API key
   needed)" / "Auto: AI-powered compaction (requires ANTHROPIC_API_KEY or
   ai.api_key, legacy)" ... "Tier 1: Semantic compression (30 days closed,
   70% reduction)" / "Tier 2: Ultra compression (90 days closed) - planned,
   not yet implemented." Word-for-word match, including the exact
   percentage and tier wording.

6. **CONFIRMED** — Claude Code plugin manifest wires `SessionStart` and
   `PreCompact` hooks, both invoking `bd prime`.
   Cited: `plugins/beads/.claude-plugin/plugin.json`.
   Quote (full `hooks` block, verified byte-for-byte against the document's
   inline JSON snippet):
   ```json
   "hooks": {
     "SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": "bd prime"}]}],
     "PreCompact":   [{"matcher": "", "hooks": [{"type": "command", "command": "bd prime"}]}]
   }
   ```
   Also confirms the adjacent claim that plugin version is `1.2.2` — the
   file's top-level `"version": "1.2.2"` matches.

**Result: 6/6 CONFIRMED, 0 UNSUPPORTED, 0 MISATTRIBUTED.** No claim needed an
`[UNVERIFIED: reason]` tag. All six quotes were pulled directly from the
cited files in the shallow clone at the same commit the source document
recorded, with wording matching closely enough (exact or near-exact
phrasing, exact numbers) to rule out paraphrase drift or misattribution to
the wrong file/section.
