# Saved workflows

Discovered from the plugin's `workflows/` at session start and registered as `flow:<name>`; invoked with `Workflow({ name: 'flow:<name>' })`.

## flow:build-slices

export const meta = {
  name: 'build-slices',
  description: 'Implement TASKS.md tasks wave by wave with brief, developer, review-package, adversarial review, and a bounded fix ladder',
  whenToUse: 'Use in Workflow mode when a wave has three or more ready [P] tasks in an approved TASKS.md',
  phases: [
    { title: 'Schedule', detail: 'flow-lint --json validates TASKS.md and returns the dispatch waves' },
    { title: 'Brief', detail: 'task-brief cuts one task (and its design contract) into a brief file' },
    { title: 'Implement', detail: 'a developer agent implements the task from the brief only' },
    { title: 'Review', detail: 'review-package builds the diff; two adversary lenses check it' },
    { title: 'Fix', detail: 'bounded fix ladder on fatal/significant findings, then a recorded ruling' },
  ],
}

Args: `tasks` (path to the approved `TASKS.md`), `base`, `testCmd`, optional
`design`, `ids` (build only these task ids), `waves` (skip stage 0 and use this
schedule), `scriptsDir`, `reviewDir`. The schedule is **not** this workflow's to
invent — `flow-lint --json` already proved `[P]` disjointness per wave, so stage
0 runs the linter and uses its `waves` array verbatim; a plan with a lint ERROR
returns `{lintOk: false}` before any developer agent starts. `/flow:next` calls
it only when a wave has **three or more** ready `[P]` tasks; below that it
dispatches fresh `developer` subagents inline, because a two-task workflow costs
more than it schedules.

## flow:plan-review

export const meta = {
  name: 'plan-review',
  description: 'Attack a spec and plan with adversarial lenses, then adjudicate the findings into decisions',
  whenToUse: 'Use before implementation starts to pressure-test a frozen spec and plan',
  phases: [
    { title: 'Attack', detail: 'independent lenses attack the spec and plan' },
    { title: 'Adjudicate', detail: 'one agent merges findings into decisions' },
  ],
}

## flow:research-sweep

export const meta = {
  name: 'research-sweep',
  description: 'Decompose a question into angles, research and check each, then synthesize a cited report',
  whenToUse: 'Use for open research questions needing verified, cited claims',
  phases: [
    { title: 'Angles', detail: 'decompose the question into distinct angles' },
    { title: 'Search', detail: 'one researcher agent per angle gathers claims' },
    { title: 'Check', detail: 'one checker agent per angle refetches load-bearing claims' },
    { title: 'Synthesize', detail: 'one agent writes the cited report' },
  ],
}

## flow:review-diff

export const meta = {
  name: 'review-diff',
  description: 'Package a diff, review it through independent lenses, and re-score every finding blind',
  whenToUse: 'Use to review a range of commits before merge with independently re-scored findings',
  phases: [
    { title: 'Package', detail: 'review-package builds the diff for base..head' },
    { title: 'Find', detail: 'independent lenses read the diff for real issues' },
    { title: 'Score', detail: 'each unique finding is re-scored 0-100 against fixed anchors' },
  ],
}

# flow CLI

The two-command surface (`/flow:spec`, `/flow:next`) leans on these. `flow next`
is a pure query of disk — `$FLOW_SPEC` → `.specs/.current` → branch `flow/<slug>`,
anchored at the git toplevel — and `flow tick` is the only thing that may write an
`[x]`. Neither ever consults PROGRESS.md.

Spec 004 adds four subcommands beside `next`; the fenced block below is `flow
--help` verbatim (a doc-drift test asserts that), so they appear there once the
CLI slice lands:

| Subcommand | What it does |
|---|---|
| `flow lint [--waves] [--json]` | Parse the active `TASKS.md`: ERROR/WARN/INFO, every ERROR carrying its own `fix:` string, `[P]` disjointness proved per wave |
| `flow tick <ID> [--dir <spec-dir>] [--by user]` | The only writer of `[x]` — it measures `git rev-parse --short HEAD` itself |
| `flow use <NNN-slug>` | Write `.specs/.current` |
| `flow publish` | Mirror unchecked tasks to GitHub issues. Off the pipeline; only when asked |

```

flow — deterministic project harness CLI

Usage:
  flow <command> [options]

Commands:
  doctor [--json] [--verbose] [--deep]              Diagnose the ~/.claude deployment
                                                     (--verbose names each check as it runs;
                                                      --deep adds the slow skills-lint check)
                                                     Its gates-runnable check EXECUTES this
                                                     project's own test/lint/format/typecheck
                                                     scripts from the cwd (120s cap per gate),
                                                     so their side effects happen for real
  init [--stack auto|node|python|rust|go] [--dry-run] [--force]
                                                     Scaffold REVIEW.md, PROGRESS.md,
                                                     CLAUDE.md, CI gate, lint thresholds
  install [--dry-run] [--dotfiles <path>] [--marketplace <path>] [--force]
                                                     Deploy the harness on this machine
                                                     (idempotent); ends by running doctor
  check [--fix]                                     Run project quality gates (check-all)
  skills-lint                                       Run ~/.claude/scripts/skills-lint
  next [--json] [--force]                           Print the one thing to do next, from
                                                     .specs/ and git alone (14 states; --json
                                                     adds the gates as data)
  lint [<TASKS.md>] [--json] [--waves]              Check a TASKS.md against the task grammar:
                                                     [P] disjointness per wave, missing verify:,
                                                     ticks that no commit backs
  tick <ID> [--dir <d>] [--by user]                 The only writer of [x] — measures the sha
                                                     rather than trusting a claim
  use <NNN-slug>                                    Point .specs/.current at one feature
  publish [--dry-run]                               Optional leaf: mirror unchecked tasks to
                                                     GitHub issues. Never on the pipeline
  loop <subcommand> [options]                       Run a task until a deterministic
                                                     verifier passes (flow loop --help)
  tutorial [--list] [--reset] [--lesson N] [--sandbox <dir>] [--force]
                                                     Walk the harness lessons in a scratch
                                                     git repo
  off [<dir>] [--unsafe]                            Turn the judging hooks off for <dir>
                                                     (default: cwd) and everything under it;
                                                     --unsafe also disables git-guard
  on [<dir>]                                        Turn them back on

Options:
  -h, --help   Show this help message

Exit codes:
  0  ok
  1  doctor found a FAIL, or the underlying tool failed
```

## flow loop

Runs a task until a deterministic verifier passes — never until the model
says so. See spec `.specs/006-loop-engineering/spec.md` for the full
`.claude/loop/` contract and `/flow:loop` (`plugins/flow/skills/loop/SKILL.md`)
for how to pick a shape and arm one. All commands anchor at the git toplevel
(`git rev-parse --show-toplevel`; exit 1 `not a git repository` otherwise) and
every read command takes `--json`. While a contract is `active`, `flow doctor`
warns and `flow next` prefers `flow loop status` (shape `session`) or
`flow loop run` (shape `fresh`) over its usual resume line.

```
flow loop — run a task until a deterministic verifier passes

Usage:
  flow loop <command> [options]

Commands:
  init "<goal>" --verify "<cmd>" [options]   Arm a loop contract (red first)
  check [--json]                             Run the verifier + tamper check once
  tick [--json|--hook] [--session <id>]      One state transition (K-H)
  run [options]                              Fresh-shape driver (outer claude -p loop)
  status [--json]                            Contract summary + tail of verify.last
  stop [--reason <text>]                     Stop the active loop
  log [-n N]                                 Last N log lines (default 20)

Options:
  -h, --help   Show this help message
```

### init

```
flow loop init "<goal>" --verify "<cmd>" [--shape session|fresh]
  [--prompt-file <path> | --prompt "<text>"] [--session <id>]
  [--max-iterations N] [--max-minutes N] [--max-usd N] [--stall-after N]
  [--verify-timeout S] [--permission-mode M] [--model M] [--max-turns N]
  [--allow-green] [--force]

Usage:
  flow loop init "<goal>" --verify "<cmd>"
```

Runs the verifier once; refuses (exit 1, `verifier already passes; nothing to
loop (use --allow-green to loop anyway)`) unless it is red or `--allow-green`
is given. Refuses (exit 1) when an `active` contract already exists unless
`--force` (which first stops it with reason `manual`). On success, prints the
goal, verifier, shape, caps and the files written, and — for `shape: session`
— `armed: loop-gate.sh will re-feed the prompt on every Stop until the
verifier passes`.

### check

```
flow loop check [--json]

Usage:
  flow loop check [--json]
```

Runs the verifier and the tamper check once, without mutating the contract.
Prints `verdict: pass|fail|suspect`, `verify_rc`, `tamper: [...]` and the last
40 lines of verifier output. Exit 0 pass, 1 fail, 2 suspect.

### tick

```
flow loop tick [--json|--hook] [--session <id>]

Usage:
  flow loop tick [--hook]
```

One state transition of the K-H machine; always exits 0. `--hook` prints
exactly the Claude Code Stop JSON to emit (`{"decision":"block","reason":...}`)
or nothing when the loop should allow the turn to end — this is the only
form `loop-gate.sh` consumes. Not meant to be run by hand outside the hook.

### run

```
flow loop run [--max-iterations N] [--max-minutes N] [--max-usd N]
  [--permission-mode M] [--model M] [--max-turns N] [--dry-run]
  [--no-checkpoint] [--worktree]

Usage:
  flow loop run [--dry-run]
```

The fresh-shape driver: an outer loop of `claude -p` sessions, run until the
verifier passes or a cap trips. `--dry-run` prints the plan without spawning
anything. `--worktree` builds on `loop/<slug>` under `.claude/worktrees/`.
Exit 0 `done`, 2 `suspect`, 1 any `stopped` reason.

### status

```
flow loop status [--json]

Usage:
  flow loop status
```

Contract summary, the last log line and the last 20 lines of `verify.last`.
Exit 0, or 3 when there is no contract.

### stop

```
flow loop stop [--reason <text>]

Usage:
  flow loop stop
```

Sets `status: stopped`, `stop_reason: manual` (or the given text) and
`finished_at`. Exit 0 even when nothing was active (prints `no active loop`).

### log

```
flow loop log [-n N]

Usage:
  flow loop log [-n N]
```

Prints the last N `loop.log` lines verbatim (default 20).
