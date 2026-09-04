# Beads (bd) — Field Report, Sept 2026

Steve Yegge's git-backed issue tracker for coding agents. Repo: `gastownhall/beads`
(originally `steveyegge/beads`) — MIT, ~27k stars, ~10,800 commits, 699+ open
issues at time of research (2026-09-04) [UNVERIFIED: open-issue count —
`gh api repos/gastownhall/beads` on 2026-09-04 returns 936 open issues, not
699+; this also contradicts the companion `beads-source.md`'s own figure of
936 open issues fetched the same day. Stars (26,876) and commit count
(~10,770 via Link-header pagination) check out]. This report synthesizes the author's
own posts, GitHub issue-tracker evidence (the best "field report" source there
is, since the tool tracks its own bugs in itself), and independent write-ups
from Hacker News.

---

## What it is, in the author's own words

Beads (`bd`) is a **dependency-graph issue tracker** built specifically so
coding agents don't lose track of multi-session work. Core pitch, from
Yegge's own comparison to GitHub Issues (PRIMARY — his comment in
[gastownhall/beads#125](https://github.com/gastownhall/beads/issues/125),
2025-10-23):

> "GitHub Issues + gh CLI can approximate some beads features, but
> fundamentally cannot replicate the core behaviors AI agents rely on:
> typed dependency semantics, transitive blocking, deterministic ready-work
> calculation, offline/branch-scoped task memory, and AI-friendly merge
> conflict resolution... If you need offline, git-first, agent-native task
> memory with graph semantics, beads is the simpler and more reliable fit."

Original architecture (Oct 2025, per that same comment and the HN launch
thread): `.beads/beads.jsonl` (git-tracked, source of truth) + a local SQLite
cache, auto-synced. `bd ready` computes claimable work via recursive CTE over
a typed dependency graph (`blocks`, `related`, `parent-child`,
`discovered-from`). Announced on HN as "Beads – A coding agent memory system"
(SECONDARY listing, [HN #45566864](https://news.ycombinator.com/item?id=45566864),
2025-10-13) and later "Beads – A memory upgrade for your coding agent" (HN
#46075616, 2025-11-28, 111 pts/68 comments).

**The architecture changed radically since launch.** By early 2026 the
storage backend was migrated from SQLite to **Dolt** (a version-controlled
SQL database), running either embedded or as a local server process, with
`.beads/issues.jsonl` demoted to an optional export/interchange format rather
than the source of truth. This migration is the single most-discussed
field-report event in the tool's history (see below). v1.0.0 shipped
2026-04-03 with embedded Dolt as the default, replacing the earlier
server-daemon model. (PRIMARY — repo README as fetched 2026-09-04, and
[#2573 comment thread](https://github.com/gastownhall/beads/issues/2573).)

---

## Downsides practitioners report

### 1. The SQLite→Dolt migration broke things for weeks, in production
[gastownhall/beads#2573](https://github.com/gastownhall/beads/issues/2573)
("Moving to dolt pretty much made beads unusable for me," opened
2026-03-13) is the single richest field-report thread in the repo — 20+
comments over a month from independent users, PRIMARY:

- Original reporter: "Ever since the move to dolt, nothing works. Tasks
  disappear, dolt is often breaking access to tasks, or the db is
  unreachable from beads... Sometimes fixing a good thing makes it worse."
- `officiallygeorge`: "I estimate that 5-10% of my agents' time is spent
  wrangling Dolt-related bead issues now." Reported stale/hanging Dolt
  server processes locking the repo "every few hours."
- `luisalima` documented **2+ complete database wipes over 2 weeks** of
  daily multi-agent use (Claude Code, Codex, Amp), tracing a specific
  failure loop: Dolt server crashes → all `bd` commands fail → `bd init`
  refuses ("already initialized") → agent retries with hallucinated flags →
  human nukes `.beads/` → issues, dependency graphs, and status are lost →
  agent recreates issues from memory, creating duplicates.
- `gobenpark`, a self-described "heavy beads user... on a real production
  project": "Backup JSONL and Dolt DB silently drift apart (had 51 issues
  invisible to `bd list`, no error or warning)."
- Multiple users (`iamlasse`, `metalagman`, `KingMob`) reported abandoning
  Beads for alternatives (`td`/`sidecar`, `beads_rust`) or pinning to the
  last pre-Dolt release (v0.49.6).
- **Steve Yegge himself replied in-thread** (2026-03-22, PRIMARY): "The
  Dolt server lifecycle has been the #1 pain point since the migration...
  standalone users shouldn't need to manage a database server," announcing
  the embedded-Dolt rework. A maintainer closed the thread 2026-05-22 after
  v1.0.0 shipped embedded Dolt as default, though a later commenter
  (`maphew`, 2026-05-21) flagged that auto-export to JSONL had since
  flipped from on-by-default to opt-in, undercutting the "your data is
  safe in git" claim made mid-thread.

A consolidated bug report from a different user,
[#4135](https://github.com/gastownhall/beads/issues/4135) ("bd 1.0.4
embedded mode: 6 observed failure modes," 2026-05-23, PRIMARY), documented
after the embedded-mode rework: **silent write loss disguised as success**
— `bd close` returns "✓ Closed" (exit 0) but the status doesn't persist when
multiple `bd close` calls are chained in one shell invocation ("First close
in a bash chain persists; subsequent closes are written and acknowledged by
`bd close` but silently reverted"); a "split-brain" bug where two Dolt
databases coexist in one `.beads/` dir so writes land in one and reads come
from the other; an auto-flush-on-read bug that **deletes `issues.jsonl` when
run against an empty Dolt DB**, even for nominally read-only commands like
`bd list`/`bd show`/`bd count`. The report's own framing: "Tools that emit
'success' for state-changing operations that didn't actually change state
are the most expensive bugs to debug because they shift the failure
detection to whoever notices a state mismatch later (sometimes never)."
Independently reproduced by a third user in the comments
(`jeremylongshore`, 2026-05-26) with a standalone repro script.

### 2. JSONL merge conflicts and ID/state races (the classic multi-agent problem)
- [#1663](https://github.com/gastownhall/beads/issues/1663): `issues.jsonl`
  committed to `main` under `bd init --branch`, causing pull conflicts.
- [#5106](https://github.com/gastownhall/beads/issues/5106): a single ID
  present in both the `issues` and `wisps` (ephemeral message) tables
  breaks `bd export`/`bd show`/mail entirely; `bd import` can itself create
  such collisions.
- [#5991](https://github.com/gastownhall/beads/issues/5991): `bd update`
  silently discards writes when an ID exists in both tables (read path is
  issues-first, write path is wisps-first — asymmetric, so a write can be
  silently dropped).
- [#5833](https://github.com/gastownhall/beads/issues/5833): `bd import`
  overwrites a DB row that is strictly *newer* than the incoming record
  (last-write-wins logic inverted).
- HN, `laxori666` on the Gas Town thread (SECONDARY,
  [HN #46075616](https://news.ycombinator.com/item?id=46458936) discussion
  thread, Jan 2026): "There kept being merge conflicts and the agent just
  kept one or the other changes instead of merging it intelligently,
  killing any work I did... Still haven't seen how beads solves this
  problem."

### 3. Daemon / server-lifecycle problems
- [#4282](https://github.com/gastownhall/beads/issues/4282): embedded Dolt
  SQL-server daemons "never reaped on inactive projects — 7 orphaned
  servers, several at ~38% CPU / ~2 GB RSS, ~67 W battery drain."
  Concretely quantified resource leak.
- [#2636](https://github.com/gastownhall/beads/issues/2636) (closed):
  `bd doctor` infinite restart loop spawning zombie Dolt processes.
- [#3415](https://github.com/gastownhall/beads/issues/3415): `bd list
  --watch` holds the embedded-Dolt lock for its entire lifetime, blocking
  every other `bd` command.
- [#4379](https://github.com/gastownhall/beads/issues/4379): server mode
  silently loses writes when the Dolt server is unreachable (a third-party
  fork shipped an offline write-spool as a fix the upstream lacked).
- Doug Campos, independent blog post "Beads, Bloat, and Breaking Points"
  (SECONDARY, https://random.qmx.me/posts/2026/01/04/on-beads-bloat-and-breaking-points/,
  2026-01-04): reports Beads running "an unsolicited background daemon that
  performs health checks every 60 seconds," hijacking git hooks to block
  pushes on uncommitted JSON files and interrupt CI with interactive
  prompts, and — before the embedded-Dolt rework — nearly overwriting his
  Claude config during setup (avoided only because his config was on a
  read-only Nix symlink). Quotes two other named practitioners in the same
  post: Greg Wedow — "easily the most frustrating piece of software I've
  used in years. Buggy, slow, slopmaxxed to hell" — and Armin Ronacher —
  "every one of my projects starts having beads in them and I can't figure
  out why."

### 4. Context / token cost — the tool consumes agent budget it's meant to protect
- [#6115](https://github.com/gastownhall/beads/issues/6115), PRIMARY,
  2026-08-31, measured against a real shared store: `bd prime` and `bd
  memories` — the commands agents run at session start — issue an unkeyed
  `SELECT key, value FROM config`, pulling **2.79 MB per invocation**, of
  which **~94% is other agents' mailbox rows** (`kv.mail.*`), not the
  session's own memories (`kv.memory.*` was only ~72 KB / 2.6% of the
  payload). At ~50 agent clones sharing one store, "a fleet-wide restart
  wave moves 50 × 2.8 MB" and "the pull grows with *other* clients' mail:
  one seat's backlog... taxes every seat's session start." This is a
  concrete, measured instance of the "cost of the agent reading the whole
  issue list" failure mode the research brief asked about.
- [#5397](https://github.com/gastownhall/beads/issues/5397): `bd list
  --parent` on a 358-node tree takes 93 seconds (a whole Dolt engine
  opened/closed per query).
- [#6065](https://github.com/gastownhall/beads/issues/6065): embedded mode
  never compacts its chunk journal; latency grows linearly with journal
  size (a 103 MB journal added 4–29s per command).
- [#5887](https://github.com/gastownhall/beads/issues/5887): the tree
  renderer has no cycle detection — one dependency cycle costs 17.4 GB RSS
  / 119s.
- [#6099](https://github.com/gastownhall/beads/issues/6099), PRIMARY,
  2026-08-31: `bd init` on a fork-less clone silently adopts the git
  origin's *entire* Dolt issue history with no row count shown and no
  consent prompt — one reporter had 4,559 upstream issues land in their
  shared-server project database from a single bare `bd init`. Notably,
  the *outbound* direction (pushing your history to a derived remote) does
  require a consent gate (added after #5068); the inbound adoption path
  was overlooked — an asymmetry the issue's author traces in the source.

### 5. Silent failures around issue state — the "agents closing issues
prematurely / trusting wrong state" failure mode
- [#5078](https://github.com/gastownhall/beads/issues/5078), PRIMARY,
  2026-07-26, titled as an incident report: `bd show --json` returns
  `comment_count` but **no comment bodies**, so any machine consumer
  (including an agent doing acceptance-criteria review) is "structurally
  blind to comment-borne state" and will confidently report it absent. Two
  concrete production incidents cited: (1) an automated reviewer checked
  for a record via `--json`, found zero matches (the record existed only
  as a *comment*), and incorrectly filed the acceptance criterion as
  unmet; (2) a claim-checking dispatcher read `--json`, saw no claim
  metadata (it existed only in a comment), and started duplicate agent
  workers that collided with live ones on the same branch/worktree —
  "One required a hand recovery." The filer's framing: "the failure mode
  is not 'data missing' — it is a machine consumer receiving a
  well-formed, successful response that silently omits a category of
  content, and then reporting that absence as a positive fact."
- [#4816](https://github.com/gastownhall/beads/issues/4816): `bd close`
  falsely reports success (exit 0) on an issue that's already closed, and
  the `--reason` flag is silently dropped.
- [#4767](https://github.com/gastownhall/beads/issues/4767): `bd close`
  reports success but the status fails to persist under concurrent
  agentic load.
- [#5486](https://github.com/gastownhall/beads/issues/5486): `bd github
  sync --push-only` silently fails to propagate closed status on
  already-pushed issues.
- [#5442](https://github.com/gastownhall/beads/issues/5442): label
  mutations never bump `updated_at`, so `--updated-after` filters,
  stale-upsert rejection, and last-write-wins merge are all blind to label
  churn — a state-tracking agent can miss label changes entirely.

### 6. General reliability / complexity complaints (independent observers)
- HN thread on Gas Town, `qcnguy` (SECONDARY,
  https://news.ycombinator.com/item?id=46075616 subthread, 2026-01-02):
  "Beads is a good idea with a bad implementation. It's not a designed
  product in the sense we are used to, it's more like a stream of
  consciousness converted directly into code... the docs are also AI
  generated." Yegge's co-founder-adjacent reply (`danpalmer`, quoting
  Yegge) accepted the framing head-on: "it's 225k lines of Go code that
  tens of thousands of people are using every day. I just created it in
  October. If that makes you uncomfortable, get out now." (Repo size had
  grown to ~470k LOC / 29 SQLite-era migrations by the time of the Doug
  Campos post two months later, per that post's count.)
- `wild_egg`, author of the "ticket" replacement tool, in his own Show HN
  post (PRIMARY self-report, https://github.com/wedow/ticket, referenced
  via HN #46487580, 2026-01-04): "Beads grew massively in a short time and
  every release made it slower and more frustrating to use. I started
  battling it several times a week as its background daemon took to
  syncing the wrong things at the wrong times." He also flagged a
  workspace-scoping bug: agents would sometimes create a bead outside the
  intended project directory and it would land in a global
  `~/.beads/default.db`, silently mixing unrelated projects' tasks.
- `azeirah` (same thread): "Beads is an incredibly difficult-to-follow mess
  for something that is at its core a pretty simple idea."
- `OrinZ` (issue #2573 thread): extension/tooling ecosystem broke across
  the Dolt migration — "at least half of the Beads-integrated tools I use
  haven't caught up with the new architecture," specifically the daemon's
  deprecation, with "no longer a clear unified approach" for third-party
  tool authors.

---

## Comparisons practitioners actually make

| Alternative | What practitioners say (sourced) |
|---|---|
| **GitHub Issues + `gh` CLI** | Yegge's own detailed comparison (#125, PRIMARY) argues GH Issues lacks typed/transitive dependency semantics, offline operation, branch-scoped task memory, and AI-mergeable conflict resolution, and that replicating Beads on top of GH Issues means "you've essentially rebuilt beads on top of a cloud service." Independent counter-view on HN (`jannniii`, `xrd`, Jan 2026 thread): "why not just use GitHub issues... or self-host Forgejo" — cited reasons *for* GH: it's a standard humans already read; reasons *against*: vendor lock-in, slow network calls, GitHub outages, `gh search` less capable than local grep/SQLite over hundreds of issues. `_joel` and `dkdcio` describe hybrid setups: `gh` CLI + Claude/Gemini/Codex as automated PR reviewers, working "quite well," while explicitly preferring not to have "LLM-generated prose in my issue trackers" (simonw). |
| **ccpm** (`automazeio/ccpm`) | A parallel approach: GitHub-Issues-and-git-worktrees based project-management skill system for Claude Code — explicitly the "use the existing human-facing tracker, add worktrees for parallel agents" alternative to Beads' own graph store. |
| **Plain markdown task files** | Multiple practitioners (`vidarh`, `simonw`, `Jeff_Brown` on HN #46075616) already had agents append to a `notes.md`/plan file and found it "surprisingly effective," with the caveat that redundancy accumulates and needs periodic agent-driven dedup. `code_martial`: asked Claude to build a memory system, and Claude itself declined to use Beads ("beads is a task tracker and what we needed was a spec tracker") and wrote a small bespoke file-based Rust utility instead. |
| **`ticket` (wedow/ticket)** | A direct, explicit Beads replacement: single-file bash + coreutils/awk over flat markdown files, "drops everything else" but keeps the one thing its author valued — graph-based task dependencies. Built specifically because Beads "grew massively... every release made it slower." |
| **Beans (hmans/beans)**, **Backlog.md**, **git-bug**, **git-issue**, **linear-beads** | All cited on the same HN thread as lighter-weight or differently-backed alternatives: Beans and Backlog.md are markdown-in-repo trackers with agent-facing CLIs; git-bug/git-issue store issues as git objects directly (no separate DB); linear-beads is "a simpler and less invasive version of beads," optionally using Linear itself as the backend so a human can watch/direct the agent's work from Linear's UI. |
| **`td` + `sidecar`** (Haplab) | Cited repeatedly in #2573 as where multiple burned users migrated during the Dolt outage period; described as reliable but without beads' git-native sync — "It doesn't sync like beads did, but everything else is working nicely." One user (`iamlasse`) described a full multi-agent pipeline built on it (analyst → implementer → QA → committer, cheaper models doing the mechanical stages) as "almost seamless." |
| **`beads_rust`** | A from-scratch Rust reimplementation, HN-covered (`sorenbs`, Jan 2026, "A fast Rust port of Steve Yegge's beads"). One #2573 commenter switched to it and reported "quite a lot of success... but it was quite a struggle to move my gas city configuration fully to it." |
| **Claude Code's built-in TODO/task tool** | HN commenter `andai` (#46075616 thread): "the TODO tool... seemed like such a banal solution... but it works so well and allows even much smaller models to do well on long horizon tasks," contrasted directly against Beads' heavier graph model for the common case of single-session task tracking. `adamgordonbell`: Beads "doesn't compete with gh issues as much as it competes with markdown specs," useful specifically for work spanning multiple context windows/sessions — i.e., a different niche than an in-session TODO list. |
| **Superpowers** (obra/superpowers) | Referenced as a complementary skills framework combined *with* Beads rather than competing (`hmokiguess`), not as a like-for-like ledger replacement in the sources found. |
| **Anthropic's feature-list.json / TaskCreate / Workflow tool** | No independent field write-up comparing these specifically to Beads was found in this research pass (gap — see below); these are largely internal Claude Code product patterns rather than third-party-documented alternatives with public field reports. |

---

## What practitioners changed / worked around

1. **Pinned to the last pre-Dolt release** (v0.49.6) rather than upgrade
   (`OrinZ`, #2573) — traded new features for stability.
2. **Wrapped every write with a forced `bd export`** to fight JSONL/Dolt
   staleness: `jeremylongshore`'s `bd-sync` tool runs `bd export -o
   .beads/issues.jsonl` after every mutation, adding "~1s overhead per
   write on a 200-bead repo" but closing the staleness window completely
   (#4135 comment, PRIMARY, with a public repro script).
3. **One `bd close` per shell invocation**, with a `bd show` verification
   step between each, after discovering chained closes silently dropped
   all but the first (#4135, failure mode 6 workaround).
4. **Treated all `.beads/` content as potentially destructive on every
   invocation**, not just writes — because auto-flush against an empty/
   split-brain DB could delete `issues.jsonl` even on read commands like
   `bd list` (#4135, failure mode 2a).
5. **Routed anything machine-critical into `notes` instead of comments**,
   since `bd show --json` silently omits comment bodies (#5078) — with the
   caveat that `bd update --notes` overwrites rather than appends, so the
   safe pattern became read-modify-write.
6. **Excluded `.beads/issues.jsonl` from git** entirely on some projects
   (`codekiln`, #2573) rather than risk merge conflicts, accepting
   single-machine-only usage in exchange.
7. **Abandoned Beads outright** for `td`+`sidecar`, `beads_rust`, or a
   hand-rolled markdown/bash tool (`ticket`), citing the Dolt migration
   specifically as the breaking point, in at least 4 independent public
   reports found in this research.
8. Yegge/maintainers' own response: rebuilt the storage layer around
   **embedded Dolt** (v1.0.0, 2026-04-03) to eliminate the daemon/server
   lifecycle as a user-facing concern, added `bd bootstrap` as a
   non-destructive multi-source recovery path (sync remote → git Dolt refs
   → `.beads/backup/*.jsonl` → tracked `issues.jsonl` → fresh DB), and — as
   late as 2026-05 — flipped JSONL auto-export from on-by-default to
   opt-in after concluding the dual-source model itself was a recurring
   cause of confusion (#4062, #4063).

---

## Who it is for / not for (verdict, synthesized from the above)

**Fits well for:**
- Solo or small-team developers running **long-horizon, multi-session**
  agent work where the value is surviving `/clear` and context resets —
  the "memory across sessions" use case Yegge and independent users
  (adamgordonbell, qudat) both describe as the actual payoff, distinct
  from short-lived in-session TODO tracking.
- Users comfortable being early adopters of a fast-moving, still-unstable
  tool and willing to read its own issue tracker as documentation — the
  project fixes real bugs quickly (most of the #2573 thread's specific
  bugs were closed within weeks) but ships breaking architectural changes
  (SQLite→Dolt) with real data-loss risk during the transition.
- Git-first, offline-first workflows where avoiding a cloud dependency (no
  GitHub API, no rate limits, works on a plane) genuinely matters, and
  where **typed, transitive dependency graphs** (not just flat
  blocks/blocked-by links) are a real requirement — e.g., large
  agent-decomposed feature plans with epics and sub-tasks.
- Setups already running many parallel agent sessions/clones against one
  project, where a structured "ready work" queue has real value over a
  human skimming a markdown file — provided the user budgets for the
  Dolt-server/daemon operational overhead this currently still carries in
  shared/server mode.

**Poor fit for / practitioners moved away for:**
- Anyone wanting a **boring, stable** dependency in a production pipeline
  right now — the tool has shipped a fundamental storage-layer rewrite
  once already (with a multi-week community-visible outage/data-loss
  period), and as of Sept 2026 still has open issues about the Dolt
  connection layer paying "35-40 round-trips" per invocation
  ([#6114](https://github.com/gastownhall/beads/issues/6114)) and
  multi-second command latency at moderate scale (#5397, #6065).
- Small-context-budget setups: `bd prime`/`bd memories` measured at 2.79 MB
  downloaded per session-start invocation on a shared store, dominated by
  other agents' unrelated mailbox traffic (#6115) — the opposite of what a
  "memory upgrade" is supposed to buy back.
- Anyone who needs machine consumers (automated reviewers, dispatchers) to
  trust `--json` output as complete — comment bodies are omitted from it,
  which has caused real false-negative reviews and duplicate-worker
  dispatch collisions in production (#5078).
- Teams whose humans already live in a web issue tracker and want that to
  stay the shared source of truth — Yegge's own comparison concedes GitHub
  Issues is the better fit for "team primarily works in web UI... want
  built-in notifications and integrations... already standardized on
  GitHub workflows."
- Anyone who has been burned by unsolicited daemons/git-hook takeovers and
  wants a tool that doesn't modify shell/CI behavior on install — the
  Campos post and several HN commenters (Ronacher, Wedow as quoted)
  describe exactly this friction, distinct from any specific bug.
- If the actual requirement is just "keep an agent honest about a TODO
  list within one long session," several practitioners (andai, `simonw`,
  `code_martial`) found Claude Code's built-in task tool or a plain
  `notes.md` sufficient and simpler — Beads' graph machinery earns its
  keep specifically at the *cross-session, cross-agent* coordination
  layer, not below it.

---

## Source check (independent)

Six load-bearing claims re-verified directly against `gh issue view` on
`gastownhall/beads` and `gh api repos/gastownhall/beads` (2026-09-04), not
against the earlier research pass's notes.

1. **Yegge's #125 comparison quote** ("GitHub Issues + gh CLI can
   approximate some beads features, but fundamentally cannot replicate...").
   **CONFIRMED.** `gh issue view 125` returns the comment from
   `steveyegge` verbatim, including "typed dependency semantics, transitive
   blocking, deterministic ready-work calculation, offline/branch-scoped
   task memory, and AI-friendly merge conflict resolution" and "beads is
   the simpler and more reliable fit."

2. **#2573 timeline and quotes** (opened 2026-03-13 by a user reporting
   "nothing works... db is unreachable"; Yegge replies 2026-03-22 with
   "The Dolt server lifecycle has been the #1 pain point since the
   migration... standalone users shouldn't need to manage a database
   server"; thread closed 2026-05-22). **CONFIRMED.** All three dates and
   both quotes match `gh issue view 2573 --json body,comments,createdAt,
   closedAt` exactly, word for word.

3. **#6115 context-cost numbers** (`bd prime`/`bd memories` pull 2.79 MB
   per invocation, ~94% is `kv.mail.*`, `kv.memory.*` only ~72 KB / 2.6%;
   "a fleet-wide restart wave moves 50 × 2.8 MB"). **CONFIRMED** — the
   issue body reproduces every number (2,793,253 bytes measured
   2026-08-22; 72 KB / 2.6% memories share; the "50 × 2.8 MB" quote is
   verbatim) and the date (2026-08-31) is correct.
   **Caveat the field-report doesn't surface:** the issue is signed
   "_claude-fable-5 (agent) on behalf of steveyegge — measured on the
   Wyvern constellation's shared store_" — i.e. this is an AI agent's own
   dogfooding/benchmark report on the project's internal store, not an
   independent third-party practitioner hitting the problem in the wild.
   The measurement is real and PRIMARY, but citing it as parallel evidence
   to the human-filed complaints elsewhere in this report overstates how
   independent the source is.

4. **#4135 chained-`bd close` silent-drop bug**, including the exact
   quotes "First close in a bash chain persists; subsequent closes are
   written and acknowledged by `bd close` but silently reverted" and
   "Tools that emit 'success' for state-changing operations that didn't
   actually change state are the most expensive bugs to debug..." plus
   `jeremylongshore`'s 2026-05-26 reproduction. **CONFIRMED** — both
   quotes and the reproduction comment (labeled "Independent third
   reproduction with a deterministic harness") match `gh issue view 4135`
   exactly; filer is `olgasafonova`, opened 2026-05-23 as stated.

5. **#5078** — `bd show --json` omits comment bodies; two production
   incidents (false-unmet acceptance criterion; duplicate-worker dispatch
   collision, "One required a hand recovery"); framing quote "the failure
   mode is not 'data missing' — it is a machine consumer receiving a
   well-formed, successful response that silently omits a category of
   content...". **CONFIRMED** — opened 2026-07-26, all quotes verbatim.

6. **Report header stats** ("~27k stars, ~10,800 commits, 699+ open
   issues," 2026-09-04). **PARTIAL / one figure UNSUPPORTED.**
   `gh api repos/gastownhall/beads` (queried 2026-09-04) returns 26,876
   stars (✓ ~27k) and a commit-count Link-header last-page of 10,770 (✓
   ~10,800), but **936** open issues, not "699+" — see inline
   `[UNVERIFIED]` marker above. The companion `beads-source.md` from the
   same research pass, fetched the same day, already has the correct
   figure (936), so this looks like a stray/stale number that didn't get
   reconciled between the two files rather than a source-fetch error.

**Net:** 5 of 6 claims CONFIRMED outright with exact-quote matches; the
6th (header open-issue count) is UNSUPPORTED by current data and by the
report's own companion document. One additional attribution nuance
(#6115 above) doesn't invalidate the number but should temper how the
claim is framed alongside genuinely independent human bug reports.
