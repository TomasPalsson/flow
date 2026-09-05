---
name: lesson
description: "Turn one observed mistake into a guardrail that makes it impossible, not discouraged. Use WHENEVER the user corrects Claude ('don't do that', 'you did X again', 'that was wrong', 'stop doing X', 'why did you delete…'), whenever a hook blocks or flags the same thing a second time in a session, after a review finding that an existing rule already covered, or when the user says /lesson. Walks a fixed ladder — regression test, hook or lint rule, script, skill edit, CLAUDE.md line — picks the most deterministic rung that fits, writes it red-then-green, has an adversary try to bypass it, and records the ruling in PROGRESS.md. Do NOT use for: fixing the bug itself (/fix), logging a note without acting (/aside), general skill polish (/skill-improver), or a one-off preference that only applies to this conversation."
argument-hint: "[what went wrong]"
---

# /lesson — never the same mistake twice

Anytime an agent makes a mistake, engineer it out so the mistake cannot recur. A sentence in CLAUDE.md is a request; a test, hook or script is enforcement. This skill exists so the enforcement gets written every time, not just remembered.

Finish the interrupted task's current step first if one is mid-flight. **This skill proposes; the user decides.** When a hook or a correction suggested it (rather than the user typing `/lesson`), do Steps 1–3 only, present the proposal in three lines (mistake, rung, what would be written), and wait for a yes. A normal prompt that merely sounded like a correction gets no lesson. Once started, never leave the guardrail half-written.

## Step 1 — Pin the mistake

Write three lines before touching anything:

- **Did:** the exact action (command, edit, claim) — quote it.
- **Should have:** the correct behaviour in one sentence.
- **Input:** the concrete thing that reproduces it: the command string, the file and line, the diff, the prompt.

Take these from the user's correction or the hook output. If there is no concrete input, ask for it in one question; a lesson without a reproducible input becomes prose and prose is the weakest rung.

## Step 2 — Find the sites

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lesson-sites"        # or: lesson-sites --json
```

It prints, per rung, where a guardrail would live in this project: the test runner, project or plugin hooks, lint thresholds, scripts, the skills dir, both CLAUDE.md files with their line budgets, PROGRESS.md. It reads disk state only; the choice is yours.

When the mistake was the harness's own (a hook let something through, a script miscounted, a flow step misled), the site is the harness plugin checkout, not the project: `cd` there, and the rung comes with its test suite.

## Step 3 — Pick the highest rung that fits

Ask the questions in this order and stop at the first yes. Pair any lower rung with a mechanism from a higher one whenever both apply.

| Rung | Question | Site |
|---|---|---|
| **Test** | Can the exact input be written as a test that fails right now? | Project suite; the harness hook or script test suites (`t_<unit>_*`) |
| **Hook / lint** | Must the action never run (PreToolUse deny), always be corrected (PostToolUse exit 2), or never end a turn (Stop block)? Is it a threshold? | Harness hook when it applies to every project; project `.claude/settings.json` hooks or `.claude/flow.config.json` when it is local |
| **Script** | Was the model doing bookkeeping, counting, path assembly or formatting by hand? | A script with `--help`, tests, bash 3.2 / BSD safe |
| **Skill** | Did a skill's instructions lead here? | Edit that step; add the case to its fixture or checklist; run `skills-lint` |
| **CLAUDE.md** | Is it a judgment call no machine can make? | One line; project file at or over 100 lines or global at or over 40 means one line out for one in |

Rules of thumb:
- "Claude ignored a rule" is never fixed by restating the rule. Find the rung that removes the choice.
- A memory note is not a rung. `/aside` files notes; this skill builds mechanisms.
- Two rungs beat one when the second is cheap: the test proves the hook, the hook enforces the test.

## Step 4 — Write it red, then green

- **Test first**: add the failing case, run it, paste the red output. Then the fix, then the green output with the test count. Both go in the reply.
- **Hooks**: bash 3.2 and BSD tools only (the suite's portability grep enforces the banned list); guard every optional tool with `command -v`; fail closed for deny-hooks, fail open for advisory ones; keep the hook under its timeout. Register in `hooks.json` and re-run `flow doctor`.
- **Thresholds**: never loosen one to make a lesson pass; a lesson that needs a looser threshold is the wrong rung.
- **CLAUDE.md**: propose the exact line and, at budget, the line to cut; write only after the user agrees.

## Step 5 — Try to break it

Spawn one `adversary` with the gaming lens over the diff: does the guardrail catch the original input, and what is the cheapest bypass (a quoted variant, a different tool, a second line, a rename)? Fix fatal and significant findings, add each bypass as a test, and log the rest. Skip this step only for a CLAUDE.md-only lesson.

## Step 6 — Record and hand back

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lesson-record" --what "<the mistake, 6-12 words>" \
  --mechanism "<rung and file, e.g. hook git-guard.sh + 3 tests>" \
  --cost "<what it costs if this ruling is wrong>"
```

It appends the ruling under `## Rulings` in PROGRESS.md (creating the section or file) and refuses a duplicate. In the harness repo, also add one row to `docs/decisions.md`'s ledger. Commit the lesson on its own (`chore(lesson): …`) so it is revertable and reviewable alone. Then resume the interrupted task and end with `Next:` from `flow next`.

## What a finished lesson looks like

```
Lesson: git guard let `git push --force` through when it was the second line of a heredoc
Rung: hook + test (harness)
Red:  t_git_guard_multiline_push_force — FAIL (allowed)
Fix:  hooks/git-guard.sh treats newline and & as separators
Green: 493 passed, 0 failed
Adversary: 1 significant (`git push -f` via `sh -c`), added as test, now caught
Ruling: multi-line push --force slipped past the guard — hook git-guard.sh + 4 tests — a false deny costs one manual retry
Next: /flow --resume
```
