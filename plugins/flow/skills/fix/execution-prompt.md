---
name: fix-execution-prompt
description: The per-iteration body for a /flow:fix --loop run — restores from git and the diagnosis file, makes one smallest change toward the red test, commits, stops
---

# Fix Execution Prompt

Written to `.claude/loop/prompt.md` by `/flow:fix --loop`, with every `${CLAUDE_PLUGIN_ROOT}` substituted for a real absolute path as it is written — the fresh `claude -p` sessions that read this file have no plugin context.

This body owns **the fix and nothing else**. Verification and the PR happen back in the main session, where a human exists. Everything after the `---` is the prompt.

---

You are one iteration of a bug fix. The harness runs the verifier and decides when this is done. You cannot end the loop and you have no completion phrase — work, commit, stop.

## 1. Restore (every iteration)

Position comes from disk, not from memory:

- `.claude/fix-diagnosis.local.md` — the root cause, the affected files with line ranges, the fix approach, the sibling call sites, the risk. **This is your brief.**
- `git log --oneline <base>..HEAD` — what previous iterations already did. The base is in `.claude/loop/loop.md`.
- `.claude/loop/LEARNINGS.md` — patterns first. What has already been tried and failed.
- The verifier tail the harness handed you — what is red right now.

The first commit on this branch is the reproduction test. **Never edit it.** It is the thing being satisfied.

## 2. Do exactly one thing

Make the **one smallest change** that moves the verifier. Then run the verifier yourself, commit on green with a message naming the change, append one dated line to `LEARNINGS.md`, and stop.

- Change the shared entry point the diagnosis names, not every caller. The diagnosis lists the sibling call sites; a patch that fixes only the reported path and leaves siblings broken is the most common way a fix is wrong.
- **Read only the ranges the diagnosis names.** Widen only when a read fails to explain the failure, and write down why in `LEARNINGS.md`. Over-broad reading measurably lowers fix accuracy.
- Only files named in the diagnosis, plus test files. If you must touch another, append a line to `LEARNINGS.md` saying which and why, then proceed.
- Follow CLAUDE.md. Use the literal commands the verifier already names — never `"$TEST_CMD"`, which expands to nothing.

## 3. When it goes wrong

| Situation | Do |
|---|---|
| Same failure 2 iterations running | Stop repairing this frame. Append what you ruled out to `LEARNINGS.md` and try the diagnosis's *second* candidate cause. |
| Your change broke an existing test | `git checkout -- <files>`. Work out **why that test broke** before trying again — it usually means the root cause is wider than diagnosed. Append the finding. |
| An existing test asserts the old buggy behaviour | Do not delete it. Rewrite it to assert the *correct* behaviour and say so in the commit message. |
| The reproduction test itself looks wrong | Do not edit it — it is the contract. Write `.claude/loop/BLOCKED.md` explaining why it cannot be satisfied, and stop. |
| The bug cannot be fixed — wrong premise, missing access, contradictory tests | Write `.claude/loop/BLOCKED.md` (what you tried, why it cannot work) and stop. The run ends `stopped: blocked`, which is a true statement. |

## 4. Never

- **Never** edit, skip, xfail or weaken any test, or the verifier, to go green. The tamper check reads the test layer and marks a green run `suspect`.
- **Never** claim the fix is complete. There is no phrase that ends this loop; the verifier's exit code does.
- **Never** open a PR or run the verification workflow from inside the loop. Both belong to the main session.
