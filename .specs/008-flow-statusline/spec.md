# Spec: Flow statusline

**Created**: 2026-09-10 · **Route**: dispatch

## TL;DR

> Read this block. If it answers your question, stop here.

**Problem**: The harness knows exactly where a build is — feature, wave, state, which gate is waiting on a human — and shows it once, in the SessionStart hook, then lets it scroll away. Ten messages later the operator re-runs `flow next` purely to remember what they were doing.

**Solution**: A `flow statusline` subcommand that renders the whole Claude Code status line: the existing model / plan / context segment, plus a flow segment carrying the active feature slug, the router state, and the wave.

**Who it's for**: The harness operator — one person driving a `/flow:spec` → `/flow:next` build in a terminal, who is also the person the human gates block.

**MVP cut line**: everything tagged `MUST` in §4.1 ships. `SHOULD` is v1.1. `MAY` is backlog.

**Key decision**: The status line is a **read-only, cached mirror of `flow next --json --peek`**. It never advances the loop, never moves `.next-call-count`, and never becomes a second router with its own opinion about state. It is cached because the router is measured at 5.1 s wall on this repo at row 5 — see §5 — and a status line may not block on that.

## 1. Context

### 1.1 Problem statement

`flow next` is the only build verb, and its answer is the single most useful fact in a session. Today that fact reaches the operator twice: once from the SessionStart hook, and again whenever they type `flow next`. Between those two moments the terminal fills with tool output and the fact is gone. The human gates make this worse, not better: at rows 5, 7 and 9 the router is waiting on a person who has no ambient signal that they are the blocker.

**Current workaround**: re-running `flow next` to re-read state. That is a read the router charges for — plain `flow next` increments `.specs/.next-call-count`, so the habit of checking pollutes the stuck-detector that row 1 depends on.

### 1.2 Roles

| Role | What they do | Key characteristic |
|------|--------------|--------------------|
| Operator | Drives a flow build in a Claude Code terminal | Is also the human gate at rows 5, 7 and 9 |
| Installer | Runs `flow install` on a new machine | Owns `~/.claude/settings.json` and will not accept silent edits to it |

**Primary actor**: Operator.
**Hidden stakeholders**: Any repo without `.specs/` — the status line runs there too and must stay silent about flow.

## 2. Scope

### 2.1 In scope

- Render the complete status line from Claude Code's stdin JSON plus the router's state.
- A flow segment naming the active feature, the router state, and — during a build — the wave.
- Visual distinction for the three human gates and the row-0 / row-1 alarm states.
- A cache, refreshed out of band, so that a render never waits on the router.
- Opt-in installation of the `statusLine` block into `~/.claude/settings.json`, with a backup.
- A `flow doctor` check that the configured status line command resolves and exits 0.

### 2.2 Non-goals

> Binding. A change here is an amendment, not an interpretation.

- It does NOT advance, tick, approve or write anything. No file under `.specs/` is modified by a render, including `.next-call-count`.
- It does NOT become a TUI, panel, pane or progress bar. One line of text is the entire surface.
- It does NOT show git branch, dirty state, cost, token counts or session duration. Claude Code and other tools own those, and the flow segment's whole value is that it is short.
- It does NOT re-derive state. If the router is wrong, the status line is wrong in the same way, and that is correct behaviour. The cache stores the router's answer verbatim; it never computes one.
- It does NOT make the router faster. The 5.1 s at row 5 is a real cost that `/flow:next` still pays; hiding it behind a cache for the status line is not a fix for it, and this feature does not attempt one.

## 3. Journeys

### Journey 1 — Mid-build glance (Operator)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | `.specs/.current` points at `008-flow-statusline`, wave 1 has unchecked tasks | Any turn renders | The line ends `🌊 008-flow-statusline · ▸ wave 1` |
| Error | The `flow` binary is not on PATH | Any turn renders | The line shows the model segment alone; exit code 0; no error text and no empty bar |
| Edge | The router returns row 5 `unapproved` | Any turn renders | The flow segment reads `✋ approve` in the warning colour — the operator can see they are the blocker without reading scrollback |

Journey 2 covers the same glance when the cache is cold, stale, or the router is slow.

### Journey 2 — The cache (Operator)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | A warm cache under 5 s old | Any turn renders | The line is printed from cache in under 100 ms and no router runs |
| Error | The router takes 10 s, or never returns | Any turn renders | The line prints immediately from the last good cache, or the model segment alone if there is none; no render ever waits |
| Edge | The operator switches feature with `flow use`, so the cache is wrong | The next render, then the one after the refresh | The first render shows the previous feature; within one cache period the slug is correct. A cache older than 60 s carries a trailing `~` so a wrong line is never mistaken for a current one |

### Journey 3 — Turning it on (Installer)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | `~/.claude/settings.json` has no `statusLine` key | `flow statusline --install` | The key is merged in, every other key untouched, and the path of the backup copy is printed |
| Error | `~/.claude/settings.json` does not parse | `flow statusline --install` | Nothing is written; the parse error and the snippet to paste by hand are printed; exit 1 |
| Edge | `~/.claude/settings.json` already has a `statusLine` | `flow statusline --install` | Nothing is written; the existing command is quoted back with `--force` named as the way to replace it |

### Journey 4 — A repo that is not a flow project (Operator)

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | cwd has no `.specs/` directory | Any turn renders | The line is exactly the model segment — no `🌊`, no separator, no placeholder |
| Error | `.specs/` exists but the router throws | Any turn renders | The line is the model segment alone; exit code 0 |
| Edge | The router returns row 0 `scan-failed` | Any turn renders | The flow segment reads `⚠ scan failed` in the error colour — a refusal to report clean is shown, not swallowed |

## 4. Requirements

### 4.1 Functional requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | The Operator MUST see the model name, a plan badge, and the context percentage, rendered from the status line stdin JSON | Given stdin `{"model":{"display_name":"Opus 5"},"rate_limits":{},"context_window":{"used_percentage":34}}`, the model segment is exactly `Opus 5 \| ✨ MAX \| 📊 ctx 34%`; with `rate_limits` absent the badge is `⚡ API`; with any of the three fields absent that field alone is dropped |
| FR-02 | MUST | The Operator MUST see the active feature slug and a state badge whenever the router reports a state carrying a feature | Every one of the 21 state names in §4.2 renders the glyph and label that table gives it, asserted literally |
| FR-03 | MUST | The Operator MUST see the wave number while the router reports `building` | A fixture at row 6 renders `▸ wave 1` |
| FR-04 | MUST | The Operator MUST be able to distinguish a state that is waiting on them from one that is not, without reading the state name | Rows 5, 7 and 9 render the `✋` marker and the warning colour; no other row does |
| FR-05 | MUST | A render MUST NOT modify any file | A test snapshots the `.specs/` tree, renders 50 times, and asserts a byte-identical tree including `.next-call-count` |
| FR-06 | MUST | The Operator MUST get the model segment alone, with exit code 0, when no flow project is present | A fixture cwd with no `.specs/` renders the model segment and nothing else |
| FR-07 | MUST | A render MUST exit 0 and print a usable line for every failure of the router, the parse or the environment | Fault-injected fixtures (missing binary, malformed stdin, unreadable `.specs/`, router throw) each exit 0 with the model segment |
| FR-08 | MUST | The Installer MUST be able to install the `statusLine` block into `~/.claude/settings.json` in one command, with the prior file copied aside first | `flow statusline --install` against fixture HOMEs covers the three Journey 2 paths |
| FR-09 | MUST | The Installer MUST be able to obtain the settings snippet without anything being written | `flow statusline --print` emits valid JSON and leaves a fixture HOME byte-identical |
| FR-10 | SHOULD | The Installer SHOULD be told by `flow doctor` when a configured flow status line no longer resolves or exits non-zero | A doctor check named `statusline` reports PASS / WARN / FAIL against fixture settings files |
| FR-11 | MAY | The Operator MAY suppress ANSI colour | `--no-color` and `NO_COLOR=1` each produce a line with no escape sequences |
| FR-12 | MUST | The Operator MUST see a feature slug longer than the §5 width budget middle-elided, with the state badge never dropped | Given the slug `002-cross-worktree-spec-numbers-zellij-pane`, the flow segment is ≤ 40 characters and still ends in the full badge |
| FR-13 | MUST | A render MUST print from cache and MUST NOT wait on the router | A fixture whose router is stubbed to sleep 10 s renders in under 100 ms |
| FR-14 | MUST | The Operator MUST see the flow segment become current within one cache period of the state changing | A fixture ticks a task, then asserts the badge changes on a later render without any command being typed |
| FR-15 | MUST | The refresh MUST NOT run more than one router invocation at a time per repository | Ten renders fired back to back produce at most one live refresh process, asserted by a lock file and a process count |
| FR-16 | MUST | A stale cache MUST be visibly marked rather than silently believed | A cache older than the §5 staleness bound renders with a trailing `~` |

### 4.2 State badges

> This table is the whole rendering contract for FR-02 and FR-04. `wave N` is the only badge that interpolates.

| Row | State name | Glyph | Label | Tone |
|-----|-----------|-------|-------|------|
| 0 | `scan-failed` | ⚠ | scan failed | error |
| 1 | `blocked` | ⛔ | blocked | error |
| 1 | `disagreement` | ⛔ | disagreement | error |
| 1 | `looping` | ⛔ | looping | error |
| 1 | `invalid` | ⛔ | invalid tasks | error |
| 1 | `lying` | ⛔ | unreachable done | error |
| 1 | `loop-active` | ◍ | loop running | info |
| 2 | `no-project` | ○ | no project | muted |
| 2 | `prep-interviewing` | ✎ | prep | muted |
| 2 | `prep-ready` | ✎ | prep ready | info |
| 3 | `ambiguous` | ? | pick a feature | warn |
| 4 | `drafting` | ✎ | drafting | info |
| 5 | `unapproved` | ✋ | approve | warn |
| 6 | `building` | ▸ | wave N | info |
| 7 | `checkpoint` | ✋ | checkpoint | warn |
| 8 | `gating` | ⚙ | gates | info |
| 9 | `unverified` | ✋ | verify | warn |
| 10 | `stale-pass` | ⚠ | stale pass | warn |
| 11 | `shippable` | ⇧ | ship | ok |
| 12 | `shipped` | ✓ | shipped | ok |
| 13 | `idle` | ○ | idle | muted |
| — | any name absent from this table | ● | the state name verbatim | muted |

`✋` appears on exactly three rows — 5, 7 and 9 — and those are exactly the rows where the router reports `human_gate: true`. That correspondence is what FR-04 asserts.

## 5. Non-functional requirements

> The router's own cost is the measurement that shaped this whole design and is recorded here as the baseline it must not inherit.

| Dimension | Number | How it is measured |
|-----------|--------|--------------------|
| Router baseline (not a target — the constraint) | 5.1 s wall at row 5 on this repo, p95 8.2 s over 20 runs, of which only 0.42 s is CPU | Measured 2026-09-10 on `.specs/008-flow-statusline` in a git worktree; `flow lint` alone accounts for 1.2 s of it. At row 3 the same command costs 0.19 s, which is why an early reading looked cheap |
| Render latency | p95 < 100 ms, including a cache miss | 100 timed runs in the test, with the router stubbed to sleep 10 s so a render that waits cannot pass |
| Cache period | Refreshed at most once per 5 s per repository; a cache older than 60 s renders with a trailing `~` (FR-16) | Fixture clock; asserted at 4 s, 6 s and 61 s of age |
| Flow segment width | ≤ 40 characters, colour codes excluded | Asserted per state fixture and against the longest slug in this repo (FR-12); the line is truncated by the terminal, so the flow half must survive an 80-column window |
| Files written per render | Exactly 0 under `.specs/`; the cache and its lock live outside the repository | Tree hash before and after 50 renders (FR-05) |
| Exit code | Always 0 on render; non-zero permitted only on an `--install` refusal | Every fault-injected fixture asserts an exit code of 0 |

## 6. Launch criteria

- [ ] Every MUST in §4.1 has a passing test in `plugins/flow/scripts/tests/test_statusline.sh`
- [ ] All 21 state names in §4.2 have a rendering fixture asserting the literal glyph and label, plus the unknown-state row
- [ ] The `✋` set and the router's `human_gate: true` set are asserted equal, not asserted separately
- [ ] The error path of each of the four journeys in §3 is exercised
- [ ] The §5 render latency is measured against a router stubbed to sleep 10 s, so a render that waits cannot pass
- [ ] `flow doctor` is green on a machine with the status line installed and on one without it
- [ ] CHK001 — the Operator installs it, runs one real build turn, and confirms the line reads correctly at a human gate and that the refresh does not visibly stall the terminal

## 7. Assumptions

| # | Assumption | Confidence | Blast radius if wrong |
|---|------------|-----------|-----------------------|
| A1 | Claude Code passes `model.display_name`, `rate_limits` and `context_window.used_percentage` on stdin, as the operator's current status line command already consumes | High | FR-01 renders empty fields; the flow segment is unaffected |
| A2 | ~~188 ms of router work is affordable without a cache~~ **Falsified 2026-09-10.** Measured 5.1 s wall, p95 8.2 s. The cache is now required, not deferred | — | Recorded as a correction, not an assumption. The design decision it produced is reversed in `design.md` §7 |
| A3 | `flow next --json --peek` has no side effects at all, not merely no counter increment | High — **confirmed 2026-09-10**: 10 consecutive peeks left `.specs/` byte-identical | — |
| A4 | Rendering in-process from `router.js` costs no more than shelling out | High | Moot for latency now that the refresh is out of band; still preferred for the render half |
| A5 | Replacing the operator's existing status line command wholesale is preferred over composing with it | Med | If wrong, `flow statusline` grows a `--segment-only` mode that prints just the flow half |
| A6 | The three human gates (rows 5, 7, 9) are the highest-value thing to make visually distinct | Med | §4.2's tone column is re-cut; nothing structural changes |
| A7 | A 5 s refresh period is frequent enough that the line is never meaningfully wrong during a build | Med | Raise or lower the §5 cache period; no code shape changes |
| A8 | A detached background refresh is acceptable behaviour for a status line command in Claude Code — that is, the harness does not kill or wait on the child | Med | Falls back to refresh-on-next-render, which makes the line one render staler and nothing worse |
| A9 | The 4.6 s of blocked time is `flow lint`'s subprocess and git, not something pathological to this worktree | Med | If it is worktree-specific, the numbers in §5 are pessimistic and the cache is over-built but still correct |

## 8. Open questions

1. [NEEDS CLARIFICATION: should `flow install` mention the status line at all, or is `flow statusline --install` discoverable enough on its own?]

## Appendix A — Glossary

| Term | Means |
|------|-------|
| Row | One of the router's 14 numbered states (`state_no`), 0 through 13 |
| State name | One of the 21 names in `router.js`'s `STATE_NO` map; several share a row |
| Human gate | A row where `human_gate` is true — 5 unapproved, 7 checkpoint, 9 unverified |
| Flow segment | The part of the status line this feature adds, after the model segment |
| Model segment | The model / plan / context part the operator's status line already shows today |
