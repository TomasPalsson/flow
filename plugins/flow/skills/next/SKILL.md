---
name: next
description: "The only build verb. Reads `flow next --json`, does exactly the one thing that state names, and stops: draft TASKS.md, build one wave of tasks through fresh developer subagents, run a phase's independent test, run the gates and write PASS-<sha>.md, open or promote the PR, archive a merged feature. Every turn ends with a /clear recommendation, and position is recomputed from disk so /clear, a crash or a compaction self-heals. Use WHENEVER a feature directory is current (`.specs/.current`) and the user says /flow:next, \"next\", \"keep building\", \"continue the build\", \"what's next\", \"keep going\", \"continue from where we left off\", \"ship it\", \"keep going until the spec is done\", \"I approve everything\", \"I'm leaving\" — even when the next task looks small enough to do directly; the router, not you, decides what one thing happens. Flags: --force, --escalate, --qa, --unattended, --stealth, --finish. Not for opening a feature (that is /flow:spec) and not for a bug (/flow:fix)."
---

# /flow:next — do the one thing

```
flow next --json  →  one state  →  one action  →  "Next: /clear, then /flow:next"
```

**Read `flow next --json` FIRST, every turn, before reading anything else — including any plan you think you remember.** Its `state` decides what you do; you do that and nothing else. Nothing about your position lives in this transcript: `/clear`, a crash, a compaction and a `git checkout` all self-heal because the router recomputes from disk. That is why the turn ends with the `/clear` line.

## The state table — one row fires per turn

Every "stop" in this table means end the turn, UNLESS §Keep going or §Finish applies — then re-run `flow next --json` and continue — except hard stops and human gates, which still stop (§Keep going, §Finish rule 7).

On `blocked`, `disagreement`, `looping`, `lying`, `ambiguous`, `unapproved`, `checkpoint`, `unverified` and `shipped` the last line of the turn is the router's own `Next:` line, verbatim — never the /clear line.

| state | You do |
|---|---|
| `scan-failed` | STOP and print the errno. A `.specs/` you cannot read is never "clean". |
| `blocked` | STOP. Print `.specs/BLOCKED.md` verbatim. The human deletes the file; `--force` bypasses. |
| `disagreement` | STOP and print the completeness report — another approved feature has unchecked tasks. `--force` continues here. |
| `looping` | STOP: five consecutive calls with no state change. `--force` continues. |
| `invalid` | `flow lint` found an ERROR. Print the first one and its `fix:` verbatim, fix `TASKS.md`, then, if §Keep going / §Finish applies, re-run `flow next --json` NOW and act on the next state; otherwise stop with the /clear line. |
| `lying` | STOP: an `[x]` whose `done:` sha is not in `Base..HEAD` or whose commit touched none of its `files:`. Never re-tick over it. |
| `loop-active` | An active `.claude/loop/loop.md` owns this repo. Print the router's command (`flow loop run` or `flow loop status`) and stop — it preempts every stop above. |
| `no-project` | `Next: /flow:spec <idea>`. Nothing in flight. |
| `prep-interviewing` | `Next: /flow:prep`. A `PREP.md` interview is unfinished; never spec over it. |
| `prep-ready` | `Next: /flow:spec`. A `PREP.md` is ready and has no `spec.md` — `/flow:spec` reuses that directory. |
| `ambiguous` | `Next: flow use <NNN-slug>`. **Never guess** which feature is live. |
| `drafting` | Write `TASKS.md` (§Drafting below), then, if §Keep going / §Finish applies, re-run `flow next --json` NOW and act on the next state; otherwise stop with the /clear line. |
| `unapproved` | First check `.claude/flow.config.json` for `"autoApprove": true` — read the file, every time; the router does not report it. Print **What will happen** — exactly one numbered line per `## Phase N` heading in `TASKS.md`, saying what exists once that phase is done (from its `Goal:`), no task IDs, no file paths, and no line for `## Gates` or anything else; nothing may follow it except the router's `Next:` line. `autoApprove: true`: prepend `Approved: <YYYY-MM-DD> by model (autoApprove)` and `Base: <sha>` yourself, then re-run `flow next --json` in the same turn — no stop. `autoApprove: false` — HARD GATE: print the router's line verbatim and stop; on the user's "approved", prepend `Approved: <YYYY-MM-DD> by user` and `Base: <sha>` — never write it yourself. `Verified:` still needs the human, in every mode. Under `--finish`: see §Finish rule 3. |
| `building` | Build exactly the wave the router names (§Building). |
| `checkpoint` | Print the `CHK###` line verbatim, gather the evidence it asks for into `verify/`, and stop for the user. Under `--finish`: see §Finish rule 4. |
| `gating` | Run the `## Gates` (§Gates). |
| `unverified` | HARD GATE. Print the router's line verbatim (`Next: read <feature-dir>/verify/, reply "approved"`) and stop. On approval write `Verified: <YYYY-MM-DD> by user`. Under `--finish`: see §Finish rule 5. |
| `stale-pass` | Commits landed after the newest `PASS-*`. Re-run the gates. |
| `shippable` | Open the PR (§Ship). |
| `shipped` | `Next: gh pr view --web`. Once merged, archive (§Ship). When §Ship's babysit conditions hold, first run one `pr-watch --once` and print its single line (you called /flow:next, so this is on demand); the `Next:` line stays last. |
| `idle` | `Next: /flow:spec <idea>, or just ask`. |

## Drafting

Write `TASKS.md` per the grammar in [`${CLAUDE_PLUGIN_ROOT}/flow-templates/TASKS.md`](../../flow-templates/TASKS.md): a header (`Spec: · Design: · Base: <sha> · Route: · Test: <cmd>`), `## Behaviors`, one `## Phase N — <title>` per phase with its `Goal:` and `Independent test:` lines, and `## Gates`. Every task line names `files:` (a comma list, no globs) and `verify:` (a runnable command, or `human: <observable>` on a `CHK###`). `after:` is what computes the waves. Each phase is a vertical slice through every layer the feature touches, demoable on its own, and its `Independent test:` exercises those layers together; a phase that is one layer (all the schema, then all the API, then all the UI) proves nothing until the last one lands. A prefactor, a change that makes the real change easy, is its own first task. Size each task so one fresh developer context can finish it. Run `flow lint` and fix every ERROR before stopping. Read `spec.md`'s acceptance criteria first: `## Behaviors` gets exactly one row per criterion (a task may serve several rows), and each row opens with the spec's own criterion id (e.g. `AC-1:`) when `spec.md` numbers its criteria, so coverage is checkable by id. A criterion only a human can judge becomes a `CHK###` task with `verify: human: <observable>`. A wide refactor (one mechanical change whose blast radius breaks many call sites at once, such as renaming a column or retyping a shared symbol) is sequenced expand → migrate → contract: an expand task adds the new form beside the old, one migrate task per batch (per package or directory) is `after:` the expand, and a contract task that deletes the old form is `after:` every batch, so each tick lands green. When `spec.md` carries `**Behaviour-preserving**: yes` (a refactor or port whose output must not change), the header also names `Parity: <cmd>` (a command whose output is the behaviour) and the plan opens with a task `T000` that runs it at Base, before any other task commits, into `verify/baseline.txt` (every first-wave task carries `after: T000`, or lint puts it in wave 1 beside them); a half-changed baseline proves nothing. A gate `G###` then runs `<cmd> | diff verify/baseline.txt -` (path under `.specs/<NNN-slug>/`; gates run from the repo root), and any difference fails; a difference you mean to keep needs a `NOTES.md` `Ruling:` naming it and the gate updated to match. A migration that changes behaviour on purpose is not declared, so none of this applies. Two tasks that touch the same file are ordered with `after:`, never `[P]` together. Never write `Approved:` here, even when `autoApprove` is on — that line is written at the `unapproved` gate, not during drafting.

## Building

The router hands you `wave: {ids, parallel}`. That wave, then stop.

1. **Brief each task**: `${CLAUDE_PLUGIN_ROOT}/scripts/task-brief <TASKS.md> <ID>` (add `--design <design.md>` when the header names one). It records `Base:` — the sha measured **before** dispatch — into the brief. Never `HEAD~1`: a multi-commit task reviewed against `HEAD~1` silently drops all but the last commit.
2. **Dispatch**: one fresh `developer` subagent per task, handed **only the brief path** and nothing else — never restate or paraphrase the report format; the brief owns it. A report without a `Seen:` section — or whose `Seen:` is only the search receipt — is incomplete: re-ask before ticking. Never make a subagent read the whole `TASKS.md`. Every ready `[P]` task in the wave goes out **in one message**, at most **4 in parallel**. **Wave N+1 never starts before wave N reports.**
3. **Or run the Workflow**: when the wave has **≥3 ready `[P]` tasks**, run `Workflow({ name: 'flow:build-slices', ... })` instead — it does briefs, dispatch, review-package and the fix ladder deterministically. Below three, run the subagents inline: a two-task workflow costs more than it schedules.
4. **Re-run the verify yourself.** Take the task's own `verify:` command out of `TASKS.md` and run it in this session. **The agent's report is never the gate** — its exit code is. A `verify:` whose test the runner never reported as *executed* (unregistered, filtered, skipped) counts as **missing, not passing**.
5. **Review the diff**: `${CLAUDE_PLUGIN_ROOT}/scripts/review-package <task-base>..HEAD` → the two lenses and the bounded fix ladder in [`review.md`](review.md). At the cap, write a `Ruling:` line into `NOTES.md` and move on.
6. **Commit, then `flow tick <ID>` in the SAME turn.** A task commits ONLY its own `files:`, with a pathspec commit — `git commit -m "<msg>" -- <each path in files:>` — never `git add -A` or `git add .`, and `git show --name-only --format= HEAD` must list only those files. The orchestrator never folds several tasks into one commit, so a parallel wave lands one commit per task. `flow tick` is the only writer of `[x]` — it records the newest commit since Base that touched the task's `files:` (so ticking after a parallel wave still names the task's own commit, not HEAD; `--sha <commit>` overrides) and appends `— done: <sha>`. Typing an `[x]` by hand is the one thing the whole grammar exists to prevent, and the Stop hook blocks a sha-less `[x]` anyway.
7. **Out-of-plan work stays out of the wave.** The `Seen:`→`Discovered:` step is a precondition of the tick, and it happens AFTER the developer returns: Read, in full, each file in the task's `files:` and log every defect — those in the report's `Seen:` lines and those you find yourself in lines the diff did not touch (a wrong format string, an injectable query, a swallowed error beside the new code) — into `NOTES.md` as `- Discovered: <file>:<line> — <what> — defer` BEFORE `flow tick`. A read made before dispatch does not count, and a `Seen:` that was reported but never logged is the failure this step exists to stop; a defect is never a silent fix. Anything else a task turns up that is not in its brief goes into `NOTES.md` the same way, as one append-only bulleted line — `- Discovered: <what> — <defer | fold into T0NN>` — never a silent extra commit. A `defer` that is a real defect and not just a note goes to `/flow:issue`, which files it and writes the `→ I-NNN` back onto that line; otherwise it is archived with the feature and lost. Folding it in means appending a **new** task ID at the next `--amend`, never widening the one in flight.
8. **At a phase boundary**, before starting the next phase: **execute** that phase's `Independent test:` line and paste its output. Every task can pass its own `verify:` while the phase still does not work; this is the only check that catches it. Run the LAST phase's `Independent test:` the same way, after its final task and before the gates.

The per-task loop each subagent runs — failing test → confirm it fails → minimum implementation → confirm it passes → commit — is [`execution-prompt.md`](execution-prompt.md). Hand it the brief; it owns RED/GREEN/REFACTOR and the exit-code gates.

## Checkpoints

A `CHK###` is a human's eyes, not yours. Print the line verbatim, do the work it names (open the browser, take the screenshot, capture the console), write the artifacts into `.specs/<NNN-slug>/verify/`, each named `verify/<CHK-id>*` (`CHK011.md`, `CHK011-375px.png`), because `flow tick CHK### --by user` refuses a checkpoint with no non-empty file by that prefix (`no evidence for CHK011`) — **a verification claim with no file there does not count** — and stop. On the user's yes: `flow tick CHK### --by user`. (Under `--finish`: rule 4.)

The first browser checkpoint in a project follows [`verification.md`](../shared/verification.md) Step 2: when no `.claude/skills/verify-*/SKILL.md` exists, stealth is off and flow-extras is installed, that step runs `verify-skill` `create` once, and the generated skill lands in its own commit. If create needs an input only a human has (under `--finish` or `--unattended`; attended, ask), or the app will not start, it is written as "draft, not run" and the checkpoint continues on the generic steps; say so in the report. It never stops the run.

## Gates

All `T###` done, `G###` open:

1. The gate command is `flow check --fix --since <Base>` (lint/format only on files changed since Base; tests everywhere). Run `flow check --since <Base>` first, without `--fix`. Fix the code, never the test. After EVERY `--fix` run, `git status --porcelain` must show nothing outside the feature — revert anything else (`git checkout <Base> -- <file>`, then re-apply only the feature's hunks, or `git restore -p`) before writing PASS or disarming finish. A red that exists at Base on a file this feature did not touch is not this spec's: append `- Discovered: <file> fails <gate> at Base — defer`, never reformat or edit it, and never edit an existing test line to turn a gate green. If the scoped gate still cannot go green, stop with a `Ruling:` in `NOTES.md` for a human.
2. One whole-branch review over `${CLAUDE_PLUGIN_ROOT}/scripts/review-package <Base>..HEAD` with a fresh reviewer (when `REVIEW.md` exists at the repo root, pass `reviewMd: <abs path>` to `review-diff`, or hand the path to each lens inline, so its rules are checked), the anchored 0/25/50/75/100 blind re-score and the ≥80 keep rule from [`review.md`](review.md), and **one** fix dispatch for everything it finds — not one per finding.
3. A converge pass that checks evidence: for every acceptance criterion in `spec.md` and every row of `TASKS.md ## Behaviors`, run the command that proves it NOW and record criterion, command, exit code in `verify/acceptance.md` (same shape as §Finish step 5; the exit column is always the integer from `<cmd>; echo $?`, never "pass", "ok", "n/a" or blank — a human-only row says `human` there and points at its `verify/<CHK>.md`). A criterion with no task, a failing command, or a ticked task whose `verify:` does not exercise the criterion is unmet → append a new task (append-only; `TASKS.md` is byte-for-byte unchanged when clean; after appending a task the state returns to building, so re-run `flow next --json` and the gates after it is done). Never cite an existing task as coverage without a passing command for that criterion. No PASS file and no `G###` tick while any row is unmet.
4. All green → write `.specs/<NNN-slug>/PASS-<HEAD-sha>.md` with a literal table `| Gate | Command | Exit |`, one row per gate; Exit is the integer printed by `<cmd>; echo $?`, never "pass"/"ok". It may be committed: later commits that only touch `.specs/<NNN-slug>/` (the PASS file itself, `TASKS.md` ticks, `verify/`) keep it valid; a commit that touches anything outside the feature directory still invalidates it and the router drops back to `gating`. Then `flow tick` each `G###`.

`--qa` runs the `qa` skill as an extra gate before step 4. It is off the default path.

## Ship

`shippable` → `gh pr create --draft`, re-run G001–G00N against the PR head, then `gh pr ready`. The body follows [`pr-body.md`](../shared/pr-body.md) with the Ruling lines appended. Before `gh pr create`, run `flow digest --json` yourself and fill the body's `## Left out` section from the entries of kind `discovered` (the unfiled defers, each with its `NOTES.md` text), and its `## Could be smaller` section from the gating review's `advisory` list; omit either section when it would be empty. Put every `Ruling:` line from `NOTES.md` into the PR body — a ruling that dies with the workspace was a decision made in secret. Under `--unattended` the PR **stays draft**: "user approved" is a precondition `gh pr ready` has not met.

**Babysit** applies only when all three hold: `gh` works, the PR head has `.github/workflows/*.yml`, and the `flow-extras:babysit` skill is available. Otherwise skip it without a word: a check that cannot run is not worth a message. Attended, the `shipped` state runs one `pr-watch --once` and prints its line; the `Next:` line becomes `/flow-extras:babysit <pr>` only when that line's action is `fix-ci` or `resolve-conflict`. Under `--finish` it runs as §Finish rule 6 says. babysit never merges, never runs `gh pr ready` and never force-pushes, so it stays inside the draft-PR rule above.

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

## Finish

`--finish` means the user pre-approved every gate of THIS spec (the usual prompt: "keep going until the spec is done, I approve everything, I'm leaving"). Evidence is never pre-approved: exit codes, the re-run `verify:`, `PASS-*` files and each phase's `Independent test:` run exactly as always.

1. **First state-changing action: `flow finish on`** (reading `flow next --json` first is fine, and so is creating or switching to the feature branch the router asks for — that writes no file and makes no commit; pass `--note` with the user's own words if they gave any). `--finish` implies `--unattended` for DECISION gates.
2. **Loop in this turn.** After each state's action run `flow next --json` again and act on the new state. Do NOT end the turn with `Next: /clear, then /flow:next` between states; the finish-gate Stop hook re-prompts if you try to stop early. Context pressure: if the conversation is long, let compaction happen — state is on disk; re-read `flow next --json` after it.
3. `unapproved` → print **What will happen**, then prepend `Approved: <YYYY-MM-DD> by user (pre-approved: /flow:next --finish)` and `Base: <sha>`, and continue.
4. `checkpoint` → do the work the `CHK` line names, write its evidence into `.specs/<NNN-slug>/verify/<CHK-id>.md` (commands run, output, screenshot paths), then `flow tick <CHK-id> --by user`. No evidence file → no tick.
5. `unverified` → before writing `Verified:`, write `.specs/<NNN-slug>/verify/acceptance.md`: one row per acceptance criterion / Behavior in `spec.md` and `TASKS.md ## Behaviors` — criterion, the command you ran NOW, its exit code, what it showed. The exit-code column is the integer from `<cmd>; echo $?` — never "pass", "ok", "n/a" or blank; a human-only row says `human` there and points at its `verify/<CHK>.md`. Any row unmet → append new task(s) per the converge rule and keep building; never write `Verified:` over an unmet row. Then, before the `Verified:` line, spawn the `claim-check` agent with each row (criterion, command, exit code) as one claim and tell it to write its findings to `.specs/<NNN-slug>/verify/claim-check.md` (in stealth, the store's `verify/`). Nobody watches this line while the user is away, and a row the agent calls UNSUPPORTED is unmet: append a task per the converge rule. INCONCLUSIVE and NOT-CHECKABLE rows go into the final report. All met → write `Verified: <YYYY-MM-DD> by user (pre-approved: /flow:next --finish)`.
6. `shippable` → run `flow digest --json` and fill the body's `## Left out` section from it as §Ship says (rule 9's `flow finish off` prints the digest only after the PR is written), then `gh pr create --draft`. The PR stays draft: never `gh pr ready`, never merge. The PR body carries the `Ruling:` lines, as in §Ship. Right after the draft PR exists, when §Ship's babysit conditions hold, run the `flow-extras:babysit` skill in `drive` mode before rule 9's `flow finish off`. `FINISH.md` stays armed, so poll `pr-watch` in the foreground (Bash `timeout 600000`, the 10 minute maximum, so a 9 minute chunk is not killed at the 2 minute default) in chunks of `--max-minutes 9`, repeated up to babysit's 60 minute and 5 push-wave caps: ending the turn to wait would make the finish-gate Stop hook re-prompt in a loop. After each push re-read `flow next --json` and re-run the gates on `stale-pass`. Put babysit's report (CI per check, Fixed, Asked, Flakes) into the final report. No git remote or `gh` fails → write one `NOTES.md` line `- Discovered: no PR opened — <reason>` and run `flow finish off`; the spec is done locally.
7. **Hard stops** (`blocked`, `lying`, `looping`, `scan-failed`, `disagreement`, `ambiguous`, `loop-active`, `prep-interviewing`, `prep-ready`) still stop: print the reason and the router's line; `FINISH.md` stays armed.
8. **Pause on request.** Only an explicit user request to pause or stop ("pause", "stop here", "stop now") triggers this; "keep going" and "I'm leaving" are not pauses. Finish the current atomic step or back it out, start nothing new, run `flow finish off`, and commit the tracked edits with a pathspec commit `wip: <task> (tree may be red)`. Do not push and do not open a PR. Append `- Ruling: paused at <state> by user — resume with /flow:next --finish` to `NOTES.md`. The `finish-gate` hook is silent once disarmed, but the `stop-gate` hook judges the red tree on its own: it blocks the turn with its escape hatch (`CC_NO_STOP_GATE=1`, which only the user sets), releases on the fourth identical block, and does not block on an open task alone. If it blocks, say once that the tree is red on purpose and why, then stop.
9. **Done** (`shipped`/`idle`, or rule 6's no-PR path) → before `flow finish off`, run one audit: spawn a fresh agent (`model: sonnet`) with the newest `~/.claude/projects/<cwd-slug>/*.jsonl` (the current session's transcript; `<cwd-slug>` is the working directory with every character that is not a letter or digit replaced by `-`, so `.` and `_` become `-` too; if no transcript is found, say so in the report instead of skipping the audit silently) and the feature's `NOTES.md`. It returns each choice between options, and each assumption acted on, that has no `NOTES.md` line, with a transcript line number. Append each as `- Assumption: <what> — evidence: transcript:<line> (audit)` (in stealth, to the store's `NOTES.md`) and never edit an existing line, so the digest below shows them. Then `flow finish off` (it prints the `flow digest` Attention list: unfiled defers, assumptions, rulings; carry it into the report), then a final report: tasks done, gates and their exit codes, acceptance rows, PR link or why none. The last line is then the router's `Next:` line.

## Flags

| Flag | Effect |
|---|---|
| `--force` | Bypass one hard stop (`blocked`, `disagreement`, `looping`). Says which one it bypassed. |
| `--escalate` | Ratchet the route up (`bounded` → `oneshot` → `dispatch`) and rewrite the header. One-way; a downgrade needs `--force` and a `Ruling:` line. |
| `--qa` | Run the `qa` skill as an extra gate. |
| `--unattended` | Auto-resolve DECISION gates on the recommendation already stated, recording each as an Assumption. It resolves decisions, **never evidence**: exit codes, the re-run `verify:`, browser evidence and the `verify/` artifacts are identical in both modes. The verification gate is **deferred, not skipped** — the PR stays draft. The `.next-call-count` gate is what bounds the loop. |
| `--finish` | Run this spec to the end in this session: `flow finish on`, then every state back to back. The user's `--finish` IS their approval of the plan, every checkpoint and verification for THIS spec — never evidence. See §Finish. |
| `--stealth` | Run `flow stealth` first (moves an untracked `.specs/` into a private store), then route as usual. Stealth is read from disk after that; the flag is never needed twice. |

## Ending the turn

**The last line of every turn is exactly:**

```
Next: /clear, then /flow:next
```

Under `--finish`, or when the user's own message explicitly asks to keep going until done (§Keep going), the `/clear` line is not printed between states; it appears only once, on the final report or a hard stop, as the router's own `Next:` line.

The one exception: when `flow next` reported a hard gate for the user — `unapproved`, `checkpoint`, `unverified`, `blocked`, `disagreement`, `looping`, `lying`, `ambiguous`, `shipped` — the last line is **the router's own `Next:` line, verbatim**, e.g. `Next: reply "approved" — full plan: .specs/003-entry-tagging/TASKS.md`. One `Next:` line, always last, always one runnable token or one literal instruction.

## Keep going

Keep going applies when the user's own message asks for /flow:next to run repeatedly, until done, or until a gate needs a human ("repeatedly", "until nothing left", "keep going", "don't stop", "keep running /flow:next"). Multi-turn phrasing ("turn after turn", "each turn") does not mean end this turn. Loop states in this turn exactly like §Finish rule 2: re-read `flow next --json` after each state, no /clear line between states. Human gates still stop: `unapproved` (unless `autoApprove`), `checkpoint`, `unverified`, and every hard stop. Only `--finish` pre-approves those.

## NEVER

- Never act on anything but the state `flow next --json` just returned. A plan you remember from before a `/clear` is a rumor; the disk is the state.
- Never do two states in one turn, or "keep going" past the wave the router named — unless `--finish` is armed (§Finish) or the user's own message asked to keep going until done (§Keep going), where looping back to `flow next --json` is the point. The count of turns is not the cost; a wrong second action is.
- Never hand a subagent anything but its brief path. Never paste `design.md`, and never paste anything from it but that task's own `## Contract` block.
- Never accept an agent's "verify passed". Re-run the command yourself; the exit code is the only ground truth. A test that did not run is missing, not passing.
- Never type `[x]` or a `done:` sha by hand. `flow tick` measures it, in the same turn as the commit.
- Never start wave N+1 before wave N has reported, or dispatch two `[P]` tasks that share a file — `flow lint` already proved they do not, and a hand-added task can break that.
- Never write `Approved:` yourself unless `autoApprove` is `true` in `.claude/flow.config.json` — then, and only at the `unapproved` gate, write `Approved: <YYYY-MM-DD> by model (autoApprove)`. Never write `Verified:` yourself, in any mode: that fact is always a human's word, autoApprove included — except the `--finish` form, written only after `flow finish on` recorded the user's pre-approval, always with the `(pre-approved: /flow:next --finish)` suffix and never plain `by user`, and only once `verify/acceptance.md` has every row met. The same suffix rule covers `Approved:` under `--finish`.
- Never skip a phase's `Independent test:` at the boundary, and never merely quote it. Execute it.
- Never edit, skip, xfail or weaken a test to clear a finding or a gate. The Stop hook blocks the turn and the tamper notice records it anyway.
- Never let a reviewer verify or fix its own finding. Scanner ≠ fixer ≠ verifier.
- Never run `gh pr ready` on an unattended run, or delete verification evidence. A ready PR with no human verification looks reviewed and is not.
- Never create GitHub issues. Work items live in `TASKS.md`; `flow publish` mirrors them only when someone asks for it.
- **NEVER** end a turn without a last `Next:` line. Pickup after `/clear` comes from disk, and the line is what tells the user to clear.
