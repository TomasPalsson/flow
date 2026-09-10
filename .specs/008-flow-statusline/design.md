# Design — Flow statusline

Cross-task structure only. The spec says what; this says what two agents must agree on.

## 1. Contract file

`plugins/flow/bin/lib/statusline.js` — CommonJS, imported with `require`. Node built-ins only; the flow CLI has no dependencies and this adds none. Everything below is exported from that one file and every task imports it. A name you need that is not there is an escalation, never a local declaration.

| canonical | identifier | plural | defined in | banned synonyms |
|---|---|---|---|---|
| model segment | `modelSegment` | — | statusline.js | header, left, prefix |
| flow segment | `flowSegment` | — | statusline.js | status, suffix, right |
| badge | `BADGES[state]` | badges | statusline.js | icon, chip, indicator |
| tone | `TONES[name]` | tones | statusline.js | colour, color, style, theme |
| router result | `result` | — | `lib/router.js` | state, next, json, payload |
| cache entry | `entry` | entries | statusline.js | record, snapshot, cached, blob |
| status input | `input` | — | statusline.js | stdin, ctx, session |

Signatures, exported verbatim:

```js
const BADGES = { /* the 21 rows of spec §4.2, keyed by state name -> { glyph, label, tone } */ };
const TONES  = { muted, info, warn, error, ok, reset };   // ANSI strings, '' when colour is off
const UNKNOWN_BADGE = { glyph: '●', label: null, tone: 'muted' };  // label null -> the state name verbatim
function renderLine(input, entry, opts)   // -> string, never throws
function modelSegment(input, opts)        // -> string, never throws
function flowSegment(entry, opts)         // -> string, '' when entry is null
function elide(slug, max)                 // -> string, middle-elided at max chars
function cachePath(repoRoot)              // -> absolute path, under os.tmpdir()
function readCache(repoRoot)              // -> entry | null, never throws
function writeCache(repoRoot, result)     // -> void, atomic rename, never throws
const CACHE_FRESH_MS = 5000;              // refresh trigger
const CACHE_STALE_MS = 60000;             // render a trailing '~' past this
const SETTINGS_SNIPPET = { type: 'command', command: '...' };
```

`opts` is `{ color: boolean }` and nothing else. All functions are synchronous — the status line has no async path anywhere; the refresh is a detached child process, not a promise.

**`entry` is the cache record and the only thing the render ever sees**: `{ result, at }`, where `result` is a router result verbatim and `at` is an epoch-millisecond number. `flowSegment` is handed an `entry`, never a live router result — that is what makes "the render never waits" a property of the type rather than of anybody's discipline.

## 2. Trust boundaries

| boundary | untrusted input shape | parse fn | failure granularity |
|---|---|---|---|
| Claude Code stdin | arbitrary JSON; fields may be absent, renamed or the wrong type | `modelSegment` | per-field: a missing field drops that field, never the line |
| the cache file | may be absent, truncated mid-write, or written by an older version with a different shape | `readCache` | whole entry: anything unexpected returns `null`, which renders as no flow segment |
| `lib/router.js` | may throw, or return an object with `state` absent | the refresh child only | whole refresh: a defect leaves the previous entry in place and the child exits 0 |
| `~/.claude/settings.json` | may not exist, may not parse, may not be an object | the `--install` path only | whole file: refuse and print, never a partial write |

The status line treats its own harness as untrusted. `entry.result.state` not being a key of `BADGES` is a normal case, not a bug — a router that grows a 22nd state renders as `UNKNOWN_BADGE` and must not blank the line. The cache is written by `rename()` onto its final path so a reader never sees a half-written file; that is why `readCache` can be simple.

## 3. Error taxonomy

There is exactly one rule and it is not a type: **a render never throws and always exits 0.** `renderLine` wraps the flow half in try/catch and degrades to `modelSegment` alone. Non-zero exits belong to `--install` only: `1` on a settings file that does not parse, `1` on an existing `statusLine` without `--force`. Adding a third exit code is an escalation.

## 4. Module boundaries

- `bin/lib/statusline.js` · layer 1 · may import: node built-ins · exports: the names in §1
- `bin/flow` · layer 2 · may import: `lib/statusline.js`, `lib/router.js`, `child_process` · exports: the `statusline` subcommand, its `--refresh` mode, and its doctor check
- `scripts/tests/test_statusline.sh` · layer 3 · may import: `scripts/tests/lib.sh` · exports: nothing

Anything not listed is a bug. `lib/statusline.js` never imports `lib/router.js` — it is handed an entry, it does not fetch one, and it never spawns anything. That is what makes every state testable from a literal object without building a fixture repo, and it is the structural reason a render cannot accidentally block: the module that renders has no way to call the thing that is slow.

## 5. Shared resources

| resource | constructed by | passed how | received by |
|---|---|---|---|
| cache entry | `readCache(repoRoot)` in `bin/flow` | argument to `renderLine` | `lib/statusline.js` |
| cache file | `os.tmpdir()/flow-statusline/<sha1 of the repo root path>.json` | `cachePath(repoRoot)` | the render and the refresh child |
| refresh lock | the same directory, `<sha1>.lock`, created with `wx` and carrying the child pid | `cachePath` + `.lock` | the refresh child only |
| router result | the detached `flow statusline --refresh` child | written to the cache file, never returned | the next render |
| settings path | `bin/flow`, as `path.join(process.env.HOME, '.claude', 'settings.json')` | argument | the `--install` path and the doctor check |
| colour decision | `bin/flow`, from `--no-color` and `NO_COLOR` only — **never** from `isTTY`, because Claude Code always pipes this command's stdout and a tty test would silence FR-04's colour exactly where it is needed | `opts.color` | every render function |

`HOME` is read once, in `bin/flow`, and never inside `lib/statusline.js`. The tests set `HOME` and `TMPDIR` to fixture directories; a function that resolves either path itself makes that impossible.

The cache lives under `os.tmpdir()` and not under `.specs/` because spec §5 budgets exactly zero writes into the repository per render, and not under `~/.claude/` because a cache that survives a reboot is a cache whose staleness rules have to be right twice.

A stale lock is a hazard, not a theoretical one: the refresh child can be killed with the terminal. The lock carries its pid, and a lock whose pid is not alive is removed and re-taken. A lock older than 60 s is removed regardless.

## 6. Deliberately duplicated

- `TONES` duplicates four of the eight ANSI constants in `bin/flow:20`. Do not consolidate them. That `C` is a private const inside a 126 KB single-file CLI, and hoisting it is a refactor outside every task's `files:` list.
- The `--install` merge duplicates the shape of `planSettingsDeny` in `bin/flow` (read, parse, refuse on an existing key, merge otherwise). Do not extract a shared merge helper — one writes a project file and one writes the user's global file, and their refusal rules differ.

## 7. Decisions

- **Reversed 2026-09-10, by measurement.** The first draft chose to call the router in-process on every render, on a reading of 188 ms. That reading was taken at row 3, where the router bails out before doing any work. At row 5 the same command costs 5.1 s wall (p95 8.2 s over 20 runs), of which only 0.42 s is CPU — `flow lint` alone is 1.2 s of it. The original decision is void; the entry below replaces it.
- In the context of the render, facing the measured fact that the router costs 5.1 s wall at row 5 while Claude Code renders the status line on the order of every 300 ms, we chose `readCache(repoRoot)` on the render path plus a detached `flow statusline --refresh` child holding a pid lock, and rejected calling the router synchronously, to achieve a render bounded by one small file read, accepting a line up to one cache period stale and a `~` marker past 60 s. `Makes hard:` a status line that is exact at the instant of a state change — nothing offered here will ever be newer than the last refresh.
- In the context of state rendering, facing 21 state names across 14 rows, we chose a flat literal `BADGES` object keyed by state name and rejected a switch on `state_no`, to achieve one line per state and an exhaustiveness test that reads the router's own `STATE_NO` map, accepting that a router rename falls through to `UNKNOWN_BADGE`. `Makes hard:` per-row rather than per-state styling — it would touch `lib/statusline.js` only.
- In the context of the human-gate marker, facing the risk that the `✋` set in spec §4.2 and the router's `human_gate` flag drift apart, we chose to assert the two sets equal in one test rather than assert three badges individually, and rejected trusting the table, to achieve a failure the moment a new gating row is added to the router, accepting one test that reaches into `router.js` internals. `Makes hard:` a `✋` that is deliberately not a `human_gate` row — it would touch the test as well as the table.

## Complexity Tracking

| Violation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| A cache file, a pid lock, and a detached refresh child — three moving parts where "call the function" was the obvious design | The router is measured at 5.1 s wall / 8.2 s p95 at row 5 (spec §5), against a status line that renders on the order of every 300 ms | Calling the router synchronously stalls the operator's terminal for seconds on every render. Caching without a lock lets ten renders spawn ten concurrent 5 s routers, each running `flow lint`, which is worse than no cache at all |

## Contract for T001 — statusline.js: badge table and render

CONTRACT   `plugins/flow/bin/lib/statusline.js` — you are creating it. It is the contract; every other task imports from it. The badge table is spec §4.2, copied literally, all 21 rows.
NAMES      modelSegment, flowSegment, BADGES, UNKNOWN_BADGE, TONES, renderLine, elide, cachePath, readCache, writeCache, CACHE_FRESH_MS, CACHE_STALE_MS, SETTINGS_SNIPPET. Banned: icon, chip, indicator, colour, color, style, theme, header, prefix, suffix, record, snapshot, blob.
MODULE     `plugins/flow/bin/lib/statusline.js` · layer 1 · may import: `fs`, `path`, `os`, `crypto` and nothing else — `lib/router.js` and `child_process` are both outside this layer · exports: the names above
CALLS      `renderLine(input, entry, opts) -> string`; `modelSegment(input, opts) -> string`; `flowSegment(entry, opts) -> string`; `elide(slug, max) -> string`; `cachePath(repoRoot) -> string`; `readCache(repoRoot) -> entry|null`; `writeCache(repoRoot, result) -> void`. All synchronous. `opts` is `{ color: boolean }`. An `entry` is `{ result, at }` with `at` in epoch milliseconds. `writeCache` writes a temporary name and `rename`s it onto the final path, so a reader never sees a partial file.
DUPLICATE  Define your own four-entry TONES. Do not import or hoist the `C` constants in `bin/flow` — that file is not in your `files:` list.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for T002 — the statusline subcommand, the refresh child, --install/--print, doctor check

CONTRACT   `plugins/flow/bin/lib/statusline.js` — import from it. A helper you need that is not there is an escalation, never a local declaration.
NAMES      renderLine, modelSegment, readCache, writeCache, cachePath, CACHE_FRESH_MS, CACHE_STALE_MS, SETTINGS_SNIPPET, BADGES, TONES, entry. Banned: the synonyms in the §1 table.
MODULE     `plugins/flow/bin/flow` · layer 2 · may import: `lib/statusline.js`, `lib/router.js`, `child_process` · exports: the `statusline` subcommand, its `--refresh` mode, and a doctor check named `statusline`
CALLS      Render path: read stdin to end, `JSON.parse` inside try/catch, `readCache(repoRoot)`, `renderLine(input, entry, { color })`, print, then — only if the entry is missing or older than `CACHE_FRESH_MS` — spawn `flow statusline --refresh` detached with stdio ignored and `unref()` it, and exit 0 without waiting. The render path NEVER calls the router. Refresh path (`--refresh`): take the pid lock with `wx`, exit 0 silently if it is held by a live pid, call the router with peek semantics inside try/catch, `writeCache`, release the lock. Resolve `HOME` and `TMPDIR` here and pass paths down. Exit 0 on every render path.
DUPLICATE  The `--install` merge deliberately mirrors `planSettingsDeny` in this same file. Do not extract a shared helper — the refusal rules differ.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for T003 — test_statusline.sh

CONTRACT   `plugins/flow/bin/lib/statusline.js` — the badge exhaustiveness test reads `BADGES` and `lib/router.js`'s `STATE_NO` and asserts the key sets match. A second test asserts the set of states whose tone is `warn` and glyph is `✋` equals the set the router reports `human_gate: true` for.
NAMES      BADGES, UNKNOWN_BADGE, TONES, renderLine, readCache, writeCache, cachePath, entry, SETTINGS_SNIPPET.
MODULE     `plugins/flow/scripts/tests/test_statusline.sh` · layer 3 · may import: `scripts/tests/lib.sh` · exports: nothing
CALLS      Drive `flow statusline` as a subprocess with fixture stdin, a fixture `HOME` and a fixture `TMPDIR`. Assert exit code 0 on every fault-injected case. For the zero-writes assertion, hash the `.specs/` tree before and after 50 renders. For the latency assertion, put a `flow` stub on `PATH` that sleeps 10 s so a render that waits on the refresh cannot pass. For the lock assertion, fire ten renders against a cold cache and assert at most one live refresh child.
DUPLICATE  Use `scripts/tests/lib.sh`'s existing assertion helpers. Do not add new ones.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.
