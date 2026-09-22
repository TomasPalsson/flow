---
name: yolo-bootstrap
description: How `--yolo` turns one idea into a spec, a task list, a composed verifier and an armed, isolated run with no question asked. Load before writing any of the three inputs by hand (spec .specs/010-autonomous-loop-on-ramp-yolo).
---

# The `--yolo` bootstrap

Step 0 states the outcome in four sentences. This file is the procedure behind them: how to
route the idea to a spec, derive tasks that carry their own proof, compose one verifier out of
both, and keep every byte of it off the branch the operator was standing on. Nothing here
invents a flag or a file format that does not already exist — every command below is a flag
`flow loop init`/`flow loop run` or `new-spec` already accepts.

## 1. Spec routing

`/flow:spec` computes one of three routes (`bounded`, `oneshot`, `dispatch`) from intent gaps,
irreversibles and footprint, then runs one discovery turn to close the gaps. `--yolo` skips the
discovery turn entirely — FR-03 is zero questions — so the route computation collapses to one
rule: **always write the `dispatch` artifacts**, `spec.md` and `TASKS.md`, never the bare-chat
`bounded` plan. Nobody is present to read a plan that only exists in this turn's transcript; an
operator who has left needs a file. `design.md` is skipped unless two or more tasks obviously
share a name, an id shape or a module boundary (the same seam trigger `/flow:spec` §4 uses) —
judge it the same way, silently, rather than asking.

Every gap the discovery turn would normally have surfaced is auto-resolved on its stated,
best-guess position and recorded as a `spec.md` §7 Assumption with a confidence, exactly as
FR-14 describes. A gap with no reasonable default (the goal itself is ambiguous, the repo has
no test command at all) is not auto-resolved — it is the FR-03 error path: nothing is armed,
and the run exits non-zero naming which input could not be produced.

Allocate the directory with `${CLAUDE_PLUGIN_ROOT}/scripts/new-spec "<idea>" --dir .specs
--current --no-branch`. Pass `--no-branch`: the isolated branch for this run is created once,
later, by `flow loop run --worktree` (§4 below); a second branch from `new-spec` itself would
be a branch nobody drives and a second thing to clean up.

## 2. Task derivation

Every task item must start unproven and carry its own runnable check (FR-06) — that is the
loop's own `.claude/loop/tasks.json` shape from `verifier-design.md` §5's "backlog empty" row,
not `TASKS.md`'s checkbox lines: `TASKS.md` lives in `.specs/`, which the isolated worktree
never receives a copy of (§4), while `.claude/loop/*` does. Use it as the operational list; keep
`TASKS.md` as the human-readable record the draft PR points to.

Each item is `{ id, desc, files, verify, passes: false }`:

- `files` — the repo-relative paths this item touches, smallest first. The first path of the
  first item is the file the negative control breaks (FR-04) — a first item naming no tracked
  file refuses to arm rather than silently picking a different one.
- `verify` — a command scoped to `files`, not the whole suite (FR-13): `<runner> <files>`, not
  `<runner>`. This is the item's own proof; nothing marks it `passes: true` but this command
  exiting 0.
- No item may require a human. `--yolo` has nobody to ask, so a task that can only be judged by
  eye is not a task — split it until every item has a command, or leave the judgement for the
  reviewer's read of the draft PR (spec §2.2 non-goal: the reviewer still confirms the work).

## 3. Verifier composition

One command, fastest and most-discriminating first, exactly `verifier-design.md` §2's rules.
`--yolo` adds one clause at the front — every item proven — reusing the same pattern
`verifier-design.md` §5 already names for a backlog:

```bash
--verify 'node -e "const t=require(\"./.claude/loop/tasks.json\");process.exit(t.items.every(i=>i.passes)?0:1)" && <scoped test command>'
```

`<scoped test command>` is the union of every item's `files`, narrowed to the test files that
cover them (FR-13) — not the full suite; the full suite stays red at base (spec §7 A4) and is
the independent check CI runs on the reviewer's behalf, out of the agent's reach on purpose
(spec §2.2 non-goal). Composing this way means an item flipped to `passes: true` with no code
behind it still fails the verifier the moment its own `files` regress — the two clauses check
different things and neither substitutes for the other.

The composed command is what `--neg-control-file` proves can fail (FR-04): the file broken is
the first path of the first task item (§2), and the negative control runs this exact string, so
a verifier that only *reads* `tasks.json` truthfully is worth nothing if the code path it
gestures at was never exercised.

## 4. Shared-repo rules

A repo co-owner never consented to this run (spec §1.2); everything here exists so their
branches, their CI minutes and the operator's own working copy are unaffected whether the run
finishes, caps out, or is never armed at all.

1. **Preflight, before any file is written.** `git status --porcelain` on the operator's current
   checkout must be empty. This is not enforced by any CLI here — `new-spec --help` says so
   outright ("Does not check working-tree dirtiness") — so it is this bootstrap's job: dirty
   means the operator has work `git worktree add`'s `HEAD` would silently leave behind, and
   Journey 3's error path is "the run refuses to start rather than committing or discarding that
   work". Refuse and stop before `new-spec` runs. This whole-tree check never reaches `cmdInit`
   — it is this skill's own gate, run before `flow loop init` is even called, so it has no exit
   code of its own; the negative control's own preflight (`init.js:124-132`) is scoped to the
   `--neg-control-file` target only (§5, exit 3), never the whole tree.
2. **Init on the current checkout, arm on a worktree.** Run `flow loop init "<goal>" --verify
   "<composed>" --yolo --neg-control-file "<first file>" [--max-usd N]` from the operator's
   current checkout — it is the only place the negative control can compare against the tree
   the operator actually has. `flow loop init` writes only `.claude/loop/*`
   (gitignored except `LEARNINGS.md`, `ensureLoopGitignore`) and `.gitignore`'s two lines; it
   commits nothing. **Refusal at this step (any of exit 1/3/4/5/6) leaves no contract file and
   no commit — nothing half-armed (FR-11).**
3. **`flow loop run --worktree`, then end the turn.** This is what makes FR-08 true: a new
   branch `loop/<slug>` in a new working copy at `.claude/worktrees/loop-<slug>`, created from
   the current `HEAD` — never the branch the operator was standing on. It copies the whole
   `.claude/loop/` directory (contract, `tasks.json`, `LEARNINGS.md`) into that copy, which is
   why §2 put the task list there instead of under `.specs/`. Run it backgrounded
   (`run_in_background: true`); a fresh loop is an outer loop by definition and must not run
   inside this turn.
4. **Nothing merges, nothing pushes to a protected ref, nothing commits back here.** The
   isolated branch accumulates its own checkpoint commits (`driver.js`); the operator's original
   branch is at the same commit it started at when the run ends, whatever cap ended it (FR-08's
   acceptance, verbatim).
5. **The draft pull request is the only thing that leaves the worktree.** It opens whether the
   run finished or hit a cap (FR-10), names what remains, and never records that a human
   verified the result — that stays the reviewer's line to write, four hours later, with no
   memory of the run (spec Journey 2).

## 5. Reading a refusal

Every refusal here is `cmdInit`'s exit code (`design.md` §3) with a one-line reason on stderr
naming the field or file responsible — never a stack trace, never a partial contract:

| Exit | Means | What changed |
|---|---|---|
| 1 | the verifier itself removed or changed the first file during its own unbroken run, before the induced break ever ran (`init.js:133-135`) | nothing armed; unlike 4/5/6 there is no restore on this path — the tree is left however that verifier run left it, since the control never got as far as taking a backup to restore from |
| 3 | an input could not be composed: no goal, no verifier, no task list, or the first file is untracked, missing, a symlink or a directory, or has uncommitted changes of its own (`init.js:124-132`, the negative control's own preflight, scoped to that one file) | nothing — no contract, no branch, no worktree |
| 4 | the composed verifier survived the induced break | nothing armed; the file named by `--neg-control-file` is back to its original bytes |
| 5 | the tree could not be restored after the break | **the loudest case** — say so to the operator directly; a human must look at the named file before anything else touches this repo |
| 6 | the negative control exceeded `2 × verify_timeout` | nothing armed; likely the composed command itself is too slow — narrow the scoped test command (§3) before retrying |

Report the exit code and its one-line reason verbatim. Never retry the same bootstrap silently
on a refusal — a 3, 4 or 6 means one of the three inputs was wrong, and arming anyway on a
second guess is exactly the "unwatched agent grading its own homework" the negative control
exists to prevent (spec TL;DR).
