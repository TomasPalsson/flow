---
name: next
description: "The only build verb. Reads `flow next --json`, does exactly the one thing that state names, and stops: draft TASKS.md, build one wave of tasks through fresh developer subagents, run a phase's independent test, run the gates and write PASS-<sha>.md, open or promote the PR, archive a merged feature. Every turn ends with a /clear recommendation, and position is recomputed from disk so /clear, a crash or a compaction self-heals. Use WHENEVER a feature directory is current (`.specs/.current`) and the user says /flow:next, \"next\", \"keep building\", \"continue the build\", \"what's next\", \"keep going\", \"continue from where we left off\", \"ship it\" — even when the next task looks small enough to do directly; the router, not you, decides what one thing happens. Flags: --force, --escalate, --qa, --unattended, --stealth. Not for opening a feature (that is /flow:spec) and not for a bug (/flow:fix)."
---

# /flow:next — do the one thing

```
flow next --json  →  one state  →  one action  →  "Next: /clear, then /flow:next"
```

**Read `flow next --json` FIRST, every turn, before reading anything else — including any plan you think you remember.** Its `state` decides what you do; you do that and nothing else. Nothing about your position lives in this transcript: `/clear`, a crash, a compaction and a `git checkout` all self-heal because the router recomputes from disk. That is why the turn ends with the `/clear` line.

## The state table — one row fires per turn

| state | You do |
|---|---|
| `scan-failed` | STOP and print the errno. A `.specs/` you cannot read is never "clean". |
| `blocked` | STOP. Print `.specs/BLOCKED.md` verbatim. The human deletes the file; `--force` bypasses. |
| `disagreement` | STOP and print the completeness report — another approved feature has unchecked tasks. `--force` continues here. |
| `looping` | STOP: five consecutive calls with no state change. `--force` continues. |
| `invalid` | `flow lint` found an ERROR. Print the first one and its `fix:` verbatim, fix `TASKS.md`, then stop. |
| `lying` | STOP: an `[x]` whose `done:` sha is not in `Base..HEAD` or whose commit touched none of its `files:`. Never re-tick over it. |
| `loop-active` | An active `.claude/loop/loop.md` owns this repo. Print the router's command (`flow loop run` or `flow loop status`) and stop — it preempts every stop above. |
| `no-project` | `Next: /flow:spec <idea>`. Nothing in flight. |
| `prep-interviewing` | `Next: /flow:prep`. A `PREP.md` interview is unfinished; never spec over it. |
| `prep-ready` | `Next: /flow:spec`. A `PREP.md` is ready and has no `spec.md` — `/flow:spec` reuses that directory. |
| `ambiguous` | `Next: flow use <NNN-slug>`. **Never guess** which feature is live. |
| `drafting` | Write `TASKS.md` (§Drafting below), then stop. |
| `unapproved` | HARD GATE. Read `TASKS.md` and print **What will happen** — one numbered line per phase saying what exists once that phase is done (from its `Goal:`), no task IDs, no file paths — then the router's line verbatim, and stop. On the user's "approved", prepend `Approved: <YYYY-MM-DD> by user` and `Base: <sha>` — never write it yourself. When `.claude/flow.config.json` has `"autoApprove": true`, print **What will happen** the same way, then prepend `Approved: <YYYY-MM-DD> by model (autoApprove)` and `Base: <sha>` yourself and continue to the next state in the same turn — no stop. `Verified:` still needs the human, in every mode. |
| `building` | Build exactly the wave the router names (§Building). |
| `checkpoint` | Print the `CHK###` line verbatim, gather the evidence it asks for into `verify/`, and stop for the user. |
| `gating` | Run the `## Gates` (§Gates). |
| `unverified` | HARD GATE. Print the router's line verbatim (`Next: read <feature-dir>/verify/, reply "approved"`) and stop. On approval write `Verified: <YYYY-MM-DD> by user`. |
| `stale-pass` | Commits landed after the newest `PASS-*`. Re-run the gates. |
| `shippable` | Open the PR (§Ship). |
| `shipped` | `Next: gh pr view --web`. Once merged, archive (§Ship). |
| `idle` | `Next: /flow:spec <idea>, or just ask`. |

## Drafting

Write `TASKS.md` per the grammar in [`${CLAUDE_PLUGIN_ROOT}/flow-templates/TASKS.md`](../../flow-templates/TASKS.md): a header (`Spec: · Design: · Base: <sha> · Route: · Test: <cmd>`), `## Behaviors`, one `## Phase N — <title>` per phase with its `Goal:` and `Independent test:` lines, and `## Gates`. Every task line names `files:` (a comma list, no globs) and `verify:` (a runnable command, or `human: <observable>` on a `CHK###`). `after:` is what computes the waves. Run `flow lint` and fix every ERROR before stopping. Never write `Approved:` here, even when `autoApprove` is on — that line is written at the `unapproved` gate, not during drafting.

## Building

The router hands you `wave: {ids, parallel}`. That wave, then stop.

1. **Brief each task**: `${CLAUDE_PLUGIN_ROOT}/scripts/task-brief <TASKS.md> <ID>` (add `--design <design.md>` when the header names one). It records `Base:` — the sha measured **before** dispatch — into the brief. Never `HEAD~1`: a multi-commit task reviewed against `HEAD~1` silently drops all but the last commit.
2. **Dispatch**: one fresh `developer` subagent per task, handed **only the brief path** and nothing else. Never make a subagent read the whole `TASKS.md`. Every ready `[P]` task in the wave goes out **in one message**, at most **4 in parallel**. **Wave N+1 never starts before wave N reports.**
3. **Or run the Workflow**: when the wave has **≥3 ready `[P]` tasks**, run `Workflow({ name: 'flow:build-slices', ... })` instead — it does briefs, dispatch, review-package and the fix ladder deterministically. Below three, run the subagents inline: a two-task workflow costs more than it schedules.
4. **Re-run the verify yourself.** Take the task's own `verify:` command out of `TASKS.md` and run it in this session. **The agent's report is never the gate** — its exit code is. A `verify:` whose test the runner never reported as *executed* (unregistered, filtered, skipped) counts as **missing, not passing**.
5. **Review the diff**: `${CLAUDE_PLUGIN_ROOT}/scripts/review-package <task-base>..HEAD` → the two lenses and the bounded fix ladder in [`review.md`](review.md). At the cap, write a `Ruling:` line into `NOTES.md` and move on.
6. **Commit, then `flow tick <ID>` in the SAME turn.** `flow tick` is the only writer of `[x]` — it records the newest commit since Base that touched the task's `files:` (so ticking after a parallel wave still names the task's own commit, not HEAD; `--sha <commit>` overrides) and appends `— done: <sha>`. Typing an `[x]` by hand is the one thing the whole grammar exists to prevent, and the Stop hook blocks a sha-less `[x]` anyway.
7. **Out-of-plan work stays out of the wave.** Anything a task turns up that is not in its brief goes into `NOTES.md` as one append-only line — `Discovered: <what> — <defer | fold into T0NN>` — never a silent extra commit. A `defer` that is a real defect and not just a note goes to `/flow:issue`, which files it and writes the `→ I-NNN` back onto that line; otherwise it is archived with the feature and lost. Folding it in means appending a **new** task ID at the next `--amend`, never widening the one in flight.
8. **At a phase boundary**, before starting the next phase: **execute** that phase's `Independent test:` line and paste its output. Every task can pass its own `verify:` while the phase still does not work; this is the only check that catches it.

The per-task loop each subagent runs — failing test → confirm it fails → minimum implementation → confirm it passes → commit — is [`execution-prompt.md`](execution-prompt.md). Hand it the brief; it owns RED/GREEN/REFACTOR and the exit-code gates.

## Checkpoints

A `CHK###` is a human's eyes, not yours. Print the line verbatim, do the work it names (open the browser, take the screenshot, capture the console), write the artifacts into `.specs/<NNN-slug>/verify/` — **a verification claim with no file there does not count** — and stop. On the user's yes: `flow tick CHK### --by user`.

## Gates

All `T###` done, `G###` open:

1. `flow check --fix` — typecheck, lint, format, test. Fix the code, never the test.
2. One whole-branch review over `${CLAUDE_PLUGIN_ROOT}/scripts/review-package <Base>..HEAD` with a fresh reviewer, the anchored 0/25/50/75/100 blind re-score and the ≥80 keep rule from [`review.md`](review.md), and **one** fix dispatch for everything it finds — not one per finding.
3. A converge pass: append any unmet work as **new** tasks, append-only, byte-for-byte no-op when clean.
4. All green → write `.specs/<NNN-slug>/PASS-<HEAD-sha>.md` naming the gates, their commands and their exit codes. It may be committed: later commits that only touch `.specs/<NNN-slug>/` (the PASS file itself, `TASKS.md` ticks, `verify/`) keep it valid; a commit that touches anything outside the feature directory still invalidates it and the router drops back to `gating`. Then `flow tick` each `G###`.

`--qa` runs the `qa` skill as an extra gate before step 4. It is off the default path.

## Ship

`shippable` → `gh pr create --draft`, re-run G001–G00N against the PR head, then `gh pr ready`. Put every `Ruling:` line from `NOTES.md` into the PR body — a ruling that dies with the workspace was a decision made in secret. Under `--unattended` the PR **stays draft**: "user approved" is a precondition `gh pr ready` has not met.

`shipped` and merged → archive with `git mv .specs/<NNN-slug> .specs/archive/<YYYY-MM-DD>-<NNN-slug>` and append the `LEDGER.md` line. When `TASKS.md` carried an `Issue:` line, this is also the one place moment 2 fires — post the shipped comment and close the issue per [`${CLAUDE_PLUGIN_ROOT}/skills/shared/issue-refs.md`](../shared/issue-refs.md) §4, marker checked first. Never close an issue whose feature did not merge. An atomic directory move has no field to desync, so "shipped" cannot be faked or forgotten.

In stealth, §Stealth below changes the push name, the PR body and the archive.

## Stealth

Read `stealth` from `flow next --json`; when `active`:

1. No `.specs/` paths, task/gate ids, spec numbers, `PASS-` names or `Ruling:` labels in commit messages, code comments, test names, the PR title/body or a pushed branch name. The `commit-msg` hook refuses the message; the rest is on you. When `stealth.hooks` is `false` the hooks are not running — run `flow stealth` and follow its `warn:` line before the next commit. Tell every developer subagent its commit message describes the change, never the task id.
2. `flow tick` also commits the store so `flow lint` keeps catching a deleted task; if it prints `store not committed`, commit the store by hand.
3. Gates run the project's own test/lint commands; `PASS-<sha>.md` and `verify/` land in the store as usual.
4. Ship: read CONTRIBUTING.md and any AI policy first; push under a plain name (`git push -u origin HEAD:<plain-name>`, `gh pr create --head <plain-name>`); the PR body carries each `Ruling:` reworded as plain rationale for the maintainers, not as labelled lines.
5. Archive with `mv`, not `git mv` (the directory is in the store), then commit the store.
6. Never `flow publish` — it refuses in stealth anyway.

## Flags

| Flag | Effect |
|---|---|
| `--force` | Bypass one hard stop (`blocked`, `disagreement`, `looping`). Says which one it bypassed. |
| `--escalate` | Ratchet the route up (`bounded` → `oneshot` → `dispatch`) and rewrite the header. One-way; a downgrade needs `--force` and a `Ruling:` line. |
| `--qa` | Run the `qa` skill as an extra gate. |
| `--unattended` | Auto-resolve DECISION gates on the recommendation already stated, recording each as an Assumption. It resolves decisions, **never evidence**: exit codes, the re-run `verify:`, browser evidence and the `verify/` artifacts are identical in both modes. The verification gate is **deferred, not skipped** — the PR stays draft. The `.next-call-count` gate is what bounds the loop. |
| `--stealth` | Run `flow stealth` first (moves an untracked `.specs/` into a private store), then route as usual. Stealth is read from disk after that; the flag is never needed twice. |

## Ending the turn

**The last line of every turn is exactly:**

```
Next: /clear, then /flow:next
```

The one exception: when `flow next` reported a hard gate for the user — `unapproved`, `checkpoint`, `unverified`, `blocked`, `disagreement`, `ambiguous`, `shipped` — the last line is **the router's own `Next:` line, verbatim**, e.g. `Next: reply "approved" — full plan: .specs/003-entry-tagging/TASKS.md`. One `Next:` line, always last, always one runnable token or one literal instruction.

## NEVER

- **NEVER** act on anything but the state `flow next --json` just returned. A plan you remember from before a `/clear` is a rumor; the disk is the state.
- **NEVER** do two states in one turn, or "keep going" past the wave the router named. The count of turns is not the cost; a wrong second action is.
- **NEVER** hand a subagent anything but its brief path. Never paste `design.md`, and never paste anything from it but that task's own `## Contract` block.
- **NEVER** accept an agent's "verify passed". Re-run the command yourself; the exit code is the only ground truth. A test that did not run is missing, not passing.
- **NEVER** type `[x]` or a `done:` sha by hand. `flow tick` measures it, in the same turn as the commit.
- **NEVER** start wave N+1 before wave N has reported, or dispatch two `[P]` tasks that share a file — `flow lint` already proved they do not, and a hand-added task can break that.
- **NEVER** write `Approved:` yourself unless `autoApprove` is `true` in `.claude/flow.config.json` — then, and only at the `unapproved` gate, write `Approved: <YYYY-MM-DD> by model (autoApprove)`. **NEVER** write `Verified:` yourself, in any mode: that fact is always a human's word, autoApprove included.
- **NEVER** skip a phase's `Independent test:` at the boundary, and never merely quote it. Execute it.
- **NEVER** edit, skip, xfail or weaken a test to clear a finding or a gate. The Stop hook blocks the turn and the tamper notice records it anyway.
- **NEVER** let a reviewer verify or fix its own finding. Scanner ≠ fixer ≠ verifier.
- **NEVER** run `gh pr ready` on an unattended run, or delete verification evidence. A ready PR with no human verification looks reviewed and is not.
- **NEVER** create GitHub issues. Work items live in `TASKS.md`; `flow publish` mirrors them only when someone asks for it.
- **NEVER** end a turn without a last `Next:` line. Pickup after `/clear` comes from disk, and the line is what tells the user to clear.
