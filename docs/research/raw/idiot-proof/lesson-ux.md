# `/lesson` UX — the idiot-proofing delta

Angle: flow's `/lesson`, which the developer says "isn't very intuitive". Source-level.
flow claims are quoted from the file they live in; external claims from a fetched source,
dated, marked PRIMARY/SECONDARY. Delta only — see research 01/02/07/08 and audit 09.
Research date 2026-09-07.

## 0. BLUF

1. `/lesson` is not one feature: **two scripts, one hook, one hook-lib function, an 82-line
   skill, one CLAUDE.md line and a PROGRESS.md section** the user must hold at once.
2. The entry point resolves (plugin skills answer the bare name, S4), but the cheapest
   complete pass costs 6 steps, 2 scripts, 1 subagent, 2–4 questions and a commit.
   Hashimoto's version of the identical habit is one line appended to `AGENTS.md` (S8).
3. On "don't do that" the user **sees nothing**: `lesson-nudge.sh` writes stdout on
   `UserPromptSubmit`, which S3 says is added to *Claude's* context, not the transcript.
   The only visible artefact is the model's generated paraphrase — non-deterministic wording.
4. `/lesson` **with no argument has no defined behaviour**. Anthropic's own `hookify`
   solves exactly this with a transcript-scanning subagent (S6). flow has none.
5. The "blocked twice" signal is **partial**: `size-guard.sh` ends in
   `exec python3 size_guard.py` and never calls `hook_feedback`, so the most repeatable
   advisory in the harness can never raise it.
6. The nudge is written *to the model* inside text the *user* reads ("suggest /lesson to
   the user in one line; do not run it unasked") — internals in the user's face at the
   moment they are already annoyed.
7. `lesson-nudge.sh` **contradicts the user's own recorded ruling**: last edited
   2026-09-05T12:09Z (20fc933); `no-nudge-noise.md` recorded 2026-09-05T15:30Z demanding
   "zero new per-turn hook output… surface on demand (a command such as `lesson-stats`)".
   `lesson-stats` was never built (`grep -r lesson-stats` → nothing); the hook is still registered.
8. `lesson-record` defaults to cwd-relative `./PROGRESS.md`; `lesson-sites` defaults to the
   git toplevel. In a worktree or subdir they disagree and a stray PROGRESS.md is templated.
9. Rulings are **write-only**: no `--list`, no id, no `--undo`. Undo = find a commit whose
   `chore(lesson):` convention nothing enforces, revert it, hand-edit PROGRESS.md.
10. Superseding is announced on stderr only; the superseded ruling stays unmarked in a
    60-line file shared with Now/Next/Done.
11. The ladder's *order* is right and matches Anthropic (S11). Its *cost profile* is the
    bug: the correct rung is also the most expensive, so the habit dies on second use.
12. Auto memory is already on in this repo, already writes `type: feedback` files from the
    user's corrections, already survives sessions — and `/lesson` neither reads nor writes
    it. Two correction pipelines, zero bridge.
13. Highest-leverage fix: **one command that decides the rung itself and asks at most one
    question**, with an already-written guardrail as the default branch.
14. Second: report in one user-visible line via hooks' `systemMessage` — the user-facing
    channel (S3) that flow uses **nowhere** (`grep -rn systemMessage plugins/flow` → 0).
15. Delete list is concrete: `hooks/lesson-nudge.sh` + its `hooks.json` registration + its
    tests + `_lesson_nudge` in `lib/hookout.sh` + `scripts/lesson-sites`.

## 1. Sources (all fetched 2026-09-07)

S1–S5 PRIMARY, Anthropic docs: `code.claude.com/docs/en/{memory,features-overview,hooks,skills,commands}`.
S6 PRIMARY source, `gh api anthropics/claude-code plugins/hookify/**` (README, `commands/hookify.md`,
`agents/conversation-analyzer.md`, `core/config_loader.py`, `hooks/hooks.json`).
S7 PRIMARY, `gh api obra/superpowers skills/{writing-skills,using-superpowers}/SKILL.md`, `CLAUDE.md`.
S8 PRIMARY, `mitchellh.com/writing/my-ai-adoption-journey`, published 2026-02-05.
S9 PRIMARY real files, `gh api ghostty-org/ghostty AGENTS.md` + `src/inspector/AGENTS.md`.
S10 PRIMARY, `gh api open-gsd/get-shit-done-redux commands/gsd/extract-learnings.md`,
`docs/features/{extract-learnings,global-learnings-store}.md`.
S11 PRIMARY, `claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more`, 2026-06-18.
S12 **UNVERIFIED — HTTP 403**, `openai.com/index/harness-engineering/` (§8.7).
S13 SECONDARY, `zed.dev/blog/agentic-engineering-with-mitchell-hashimoto` (2025-06-19) — fetched,
contained none of the sought material.

## 2. What `/lesson` is, file by file

`skills/lesson/SKILL.md` (82 ln) — the ladder. Frontmatter: `argument-hint: "[what went
wrong]"`, **no `user-invocable`, no `disable-model-invocation`**. S4: defaults are "both you
and Claude can invoke any skill"; a plugin skill answers `/flow:lesson` and "the bare
`/fancy` also invokes the skill unless another command already uses that name". So the
"**This skill proposes; the user decides**" rule is prose, not enforcement.

`scripts/lesson-sites` (143 ln) — read-only survey, 7 lines `<rung> present|absent <detail>`
for test/hook/lint/script/skill/claude-md/progress. `DIR` defaults to `git rev-parse
--show-toplevel`. Harness detected by `[ -f "$DIR/.claude-plugin/plugin.json" ] && [ -d
"$DIR/hooks/tests" ]`.

`scripts/lesson-record` (121 ln) — appends `- Ruling: <what> — <mechanism> — <cost>` under
`## Rulings`; `mkdir` lock, exact-duplicate refusal (exit 3), templates the file when
absent, warns over 60 lines. `FILE="PROGRESS.md"` — cwd-relative.

`hooks/lesson-nudge.sh` (41 ln) — `UserPromptSubmit`, registered in `hooks/hooks.json`
(2nd entry, `timeout: 5`). Eight `grep -E` alternations over the lower-cased prompt; on a
match prints one line: *"flow: this prompt may be a correction… finish the current step and
then offer /lesson in one line (a test, hook or script beats a promise); run it only if the
user agrees."*

`hooks/lib/hookout.sh:128-153` `_lesson_nudge()` — wraps every `hook_deny`/`hook_block`/
`hook_feedback` reason. `cksum` of `basename $0` + reason's first line → appended to
`${TMPDIR:-/tmp}/claude-lesson-<session>`; from the 2nd occurrence appends *"the same thing
was blocked <n> times this session (<hook>)… suggest /lesson to the user in one line; do not
run it unasked."* `hooks/stop-gate.sh:535-543` carries its own copy of the same counter.

`~/.claude/CLAUDE.md`, one line: *"When the user corrects a mistake, or the same hook blocks
twice in a session, offer `/lesson` in one line… run it only when the user agrees or typed it."*

Tests: `hooks/tests/test_lesson_nudge.sh` (120 ln), `scripts/tests/test_lesson.sh` (183 ln).

## 3. Journey 1 — "don't do that"

**T0** model errs. Nothing fires; there is no wrongness detector.
**T1** user types `don't do that again`. `lesson-nudge` matches
`(don'?t|do not|stop) (do|doing) (that|this|it)( again)?` and prints its line. Per S3,
`UserPromptSubmit` plain stdout is "context that Claude can see and act on"; stderr → debug
log. **User sees nothing.** The model then emits its own offer sentence — the first visible
thing, and its wording is generated, so it differs run to run.
**T2** user says yes. Step 1 demands Did / Should have / Input, and *"If there is no concrete
input, ask for it in one question"* → **question 2**, which is the normal case, because
"don't do that" is a sentence, not a command string.
**T3** Step 2 runs `lesson-sites` (7 lines of paths and budgets scroll past); Step 3 walks a
5-row table internally. The user must now trust an unexplained rung choice.
**T4** Step 4: for the CLAUDE.md rung, *"propose the exact line and, at budget, the line to
cut; write only after the user agrees"* → **question 3**, and a 4th at budget. For the hook
rung: bash 3.2 + BSD only, `command -v` guards, fail-closed vs fail-open, register in
`hooks.json`, re-run `flow doctor`.
**T5** Step 5 spawns an `adversary` subagent.
**T6** Step 6 runs `lesson-record` with three required flags, one of which
(`--cost "<what it costs if this ruling is wrong>"`) is a judgement the user was never asked
for and the model invents; plus a manual `docs/decisions.md` row in the harness repo, plus a
standalone `chore(lesson):` commit, plus `flow next`.

**Cheapest complete pass: 2 user turns minimum, 4 realistic; 6 steps; 2 scripts; 1 subagent;
1 unenforced doc edit; 1 commit.** S8: *"For simple things, like the agent repeatedly running
the wrong commands or finding the wrong APIs, update the `AGENTS.md`"* — one line, no questions.

## 4. Journey 2 — a hook blocks twice

Coverage = exactly the hooks that route through `hookout.sh`: `git-guard` (8× `hook_deny`),
`spec-gate` (`hook_deny`), `format-lint`, `tamper-notice`, `post-bash-write`
(`hook_feedback`), `stop-gate` (own counter). **`size-guard.sh` is excluded**: it ends at
line 77 with `exec python3 "$HERE/size_guard.py" …` and the Python emits its own stderr/exit 2.

What appears: for a `PreToolUse` deny the text lands in `permissionDecisionReason`, which S3
confirms is the user-visible blocking message — so the user reads a denial ending in an
instruction addressed to the model. For `hook_feedback` it is stderr fed to Claude.

The counter file is per session (`claude-lesson-<session_id>`), so the same mistake on Monday
and Tuesday counts once each. There is **no reader**: `flow --help` lists
`doctor|init|install|check|skills-lint|next|off|on`, and no `lesson-stats` exists anywhere.
The on-demand surface the user's own memory asked for was never built.

## 5. Journey 3 — `/lesson` with and without an argument

**With** an argument: works as designed.
**Without**: the skill has no `$ARGUMENTS`-empty branch. Step 1 says take the mistake "from
the user's correction or the hook output"; with neither in reach the model invents or asks —
and asking is the failure mode, because the user typed `/lesson` precisely so they would not
have to re-describe what just happened.

S6, `plugins/hookify/commands/hookify.md`: *"**If `$ARGUMENTS` is empty:** Launch the
conversation-analyzer agent to find problematic behaviors — Agent will scan user prompts for
frustration signals — Agent will return structured findings."* The agent
(`agents/conversation-analyzer.md`, `tools: ["Read","Grep"]`, `model: inherit`) reads user
messages newest-first for "Don't use X" / "Why did you do X?" / reversions / repeats and
returns `category / tool / pattern / context / severity`, told *"Focus on the most recent
issues (last 20-30 messages)."*

That is the missing ~30 lines — and flow already owns the phrase list. It is hard-coded in
`lesson-nudge.sh`, running per turn against one prompt, where it would be far more useful
running once against the last 30.

## 6. Journey 4 — finding and undoing a ruling

**Finding:** `## Rulings` in PROGRESS.md, `- Ruling: <what> — <mechanism> — <cost>`. This
repo holds 4, in a file budgeted at 60 lines *total* shared with Now/Next/Done/Blocked;
`lesson-record` warns on the total, never on the rulings' share.
**Undoing:** none. `lesson-record --help` lists `--what --mechanism --cost --file` and exits
`0 written · 2 usage · 3 exact duplicate · 4 cannot write`. No `--list`, no id, no `--remove`.
**Superseding:** stderr-only — *"an earlier ruling starts with the same text; this one is
recorded as superseding it"* — and the old line stays, unmarked. Contradictory rulings
accumulate in a budgeted file.
**Scope:** a ruling about a *harness-wide* guardrail lands in whichever project's PROGRESS.md
the session happened to be in. Guardrail global, record local.

## 7. Every internal the user must understand (14)

Rungs · sites · `present`/`absent` (meaning "a guardrail could live here", not "broken") ·
**harness checkout vs project** (the skill says *"the site is the harness plugin checkout,
not the project: `cd` there"* and never says where; measured on this machine
`~/.claude/skills/flow/scripts/lesson-sites` and `<repo>/plugins/flow/scripts/lesson-sites`
share inode 929022 — hardlinks, so an in-place edit stays in sync but a full-file rewrite
silently forks the two copies; `bin/flow:793` only WARNs about the shape) ·
`${CLAUDE_PLUGIN_ROOT}` appearing literally in the transcript · the Rulings grammar with its
counterfactual cost field · the 60-line PROGRESS budget · the 100/40 CLAUDE.md budgets ·
`hooks.json` registration + `flow doctor` as a two-step publish · bash 3.2/BSD portability
and fail-closed vs fail-open · `t_<unit>_*` naming in two suites · the `adversary` subagent ·
the `docs/decisions.md` ledger row · the `chore(lesson):` commit convention ·
`CC_NO_LESSON_NUDGE=1`, documented only in the hook header and `docs/reference/hooks.md`,
never printed at the point of friction.

Fourteen concepts before the first successful `/lesson`. Each is a rule the developer must
remember — the exact thing the harness exists to abolish.

## 8. External delta

### 8.1 Anthropic auto memory (S1) — PRIMARY, the incumbent flow is competing with

> "**Auto memory**: notes Claude writes itself based on your corrections and preferences" …
> "`feedback`: corrections you give Claude and approaches you confirm" … "Auto memory is on by
> default." … "When you ask Claude to remember something … Claude saves it to auto memory."

Store: `~/.claude/projects/<project>/memory/`, `MEMORY.md` index + one topic file per memory,
shared across worktrees, exempt from the transcript retention sweep. **This repo already has
one** — `no-nudge-noise.md`, `type: feedback`. Zero commands, zero questions, browsable via
`/memory`. Three mechanisms to steal:

- **Budget enforced by an error, not a reminder.** "If the file is near a limit, Claude Code
  reminds Claude to shorten it… If the file is over a limit, the write still succeeds, but
  Claude Code returns an error telling Claude to rewrite the index." `lesson-record` warns on
  stderr at 60 lines and exits 0 — the weaker form.
- **Freshness stamping.** "Claude Code records the write time in a `modified` frontmatter
  field as an ISO 8601 timestamp." Rulings carry no date.
- **The published CLAUDE.md budget is 200, not 100/40.** "**Size**: target under 200 lines per
  CLAUDE.md file." `lesson-sites` prints `${pl}/100` and `${gl}/40` and shouts `AT BUDGET`,
  forcing a one-out-for-one-in negotiation far earlier than the platform requires. Being
  tighter is defensible; being tighter *silently* is what makes the cheap rung feel punitive.

The rung flow's ladder lacks entirely, from S1/S2: `.claude/rules/` with `paths:` frontmatter
— "Rules with `paths` frontmatter only load when Claude works with matching files, saving
context." A path-scoped rule beats a global CLAUDE.md line for most lessons.

### 8.2 Anthropic `hookify` (S6) — PRIMARY, the closest analogue

> "The hookify plugin makes it simple to create hooks without editing complex `hooks.json`
> files. Instead, you create lightweight markdown configuration files that define patterns to
> watch for and messages to show when those patterns match." … "**No restart needed!** Rules
> take effect on the very next tool use."

Rule = frontmatter + body: `name / enabled / event (bash|file|stop|prompt|all) / pattern |
conditions[{field,operator,pattern}] / action (warn|block)`, then the message. Four generic
hooks (`pretooluse.py`, `posttooluse.py`, `stop.py`, `userpromptsubmit.py`) are registered
once in `hookify/hooks/hooks.json`; **every user rule is data, never a registration**.
`core/config_loader.py` globs `.claude/hookify.*.local.md` and defaults `enabled: true`,
`event: all`, `action: warn`.

The question protocol is what flow needs most. `commands/hookify.md` declares
`allowed-tools: [... "AskUserQuestion" ...]` and asks **"Which behaviors to hookify?"**
(`multiSelect: true`, max 4 options) then **"Should this block the operation or just warn?"** —
and closes with a literal receipt: *"Created 3 hookify rules: - .claude/hookify.dangerous-rm.local.md
… These rules will trigger on: - dangerous-rm: Bash commands matching "rm -rf""* and
*"Rules are active immediately - no restart needed!"*

**Delta in one sentence: hookify's default rung is a declarative markdown file needing no
test, no registration and no restart; flow's default rung is a bash hook needing all three.**

### 8.3 Hashimoto (S8, 2026-02-05) + Ghostty (S9) — PRIMARY

The definition flow is built on: *"anytime you find an agent makes a mistake, you take the
time to engineer a solution such that the agent never makes that mistake again."* But note the
rung he reaches for first: *"For simple things… update the `AGENTS.md`"*, and *"scripts to take
screenshots, run filtered tests… usually paired with an AGENTS.md change to let it know about
this existing."* Each line "is based on a bad agent behavior, and it almost completely resolved
them all."

The real artefact (S9): `ghostty/src/inspector/AGENTS.md` is **12 lines, scoped to one
subsystem**, and reads as accumulated failures — *"On macOS, run builds with
`-Demit-macos-app=false` to verify API usage."*, *"There are no unit tests in this package."*

flow inverts both: (a) his **doc line is the default, the script the pairing**; flow makes the
doc line the last resort. (b) His docs are **directory-scoped**, so a lesson costs nothing
outside that subsystem; flow's CLAUDE.md rung is paid in every session — which is why it needs
a 100-line budget and a one-out-for-one-in ritual, which is why the cheap rung feels expensive.

### 8.4 obra/superpowers (S7) — PRIMARY

The sharpest triage line anyone has written for this, from `writing-skills/SKILL.md` under
"Don't create for": *"**Mechanical constraints** (if it's enforceable with regex/validation,
automate it—save documentation for judgment calls)"* — flow's whole 5-row rung table compressed
into one test the model can apply without a survey script. Same file supplies the red/green
discipline flow already copied (*"If you didn't watch an agent fail without the skill, you
don't know if the skill teaches the right thing"*) — but superpowers applies it to the
**documentation** rung too, while flow exempts it: *"Skip this step only for a CLAUDE.md-only
lesson."* `using-superpowers/SKILL.md` shows the enforcement style flow's prose "propose, don't
run" lacks: a Red Flags table naming each rationalisation (*"This doesn't need a formal skill"
| If a skill exists, use it.*).

### 8.5 GSD / get-shit-done-redux (S10) — PRIMARY

Capture as a **boundary event, not a user action**: *"With `features.global_learnings: true`,
phase completion runs the extraction for the just-completed phase automatically and copies the
artifact to the global store at `~/.gsd/knowledge/` … extraction and copy failures never block
completion. With the gate off (the default), extraction stays fully manual."* Requirements
worth lifting verbatim: *REQ-LEARN-02: Each extracted item includes source attribution
(artifact and section)*; *REQ-LEARN-03: Injection MUST be capped by `learnings.max_inject`*;
*REQ-LEARN-04: If `capture_thought` is unavailable, completes successfully and logs that
external capture was skipped.* Three properties flow lacks: per-record source attribution, a
cap on re-injection, and graceful degradation — `lesson-record` exits 4 and blocks the skill's
final step when the target is unwritable.

### 8.6 Anthropic's own ladder (S2 + S11) — PRIMARY

S2 "Build your setup over time": *"Claude gets a convention or command wrong twice → Add it to
CLAUDE.md"*; *"You want something to happen every time without asking → Write a hook"*;
*"A repeated mistake or a recurring review comment is a CLAUDE.md edit, not a one-off
correction in chat."* S11 (2026-06-18) supplies the counterweight flow is right about:
*"When there's something that absolutely must not happen, an instruction is the wrong tool…
A real guardrail needs to be deterministic, and the enforcement methods are hooks and permissions."*

**Reconciliation, and the root cause of "isn't very intuitive": Anthropic escalates on the
*second* occurrence and starts at the doc line; flow starts at the test on the *first*.
flow's ordering is right for must-not-happen and wrong for gets-it-wrong. One ladder serves
both, so the common case is over-charged.**

### 8.7 OpenAI doc-gardening — **UNVERIFIED**

`openai.com/index/harness-engineering/` returned HTTP 403 on 2026-09-07. The circulating claim
— a recurring doc-gardening agent that scans for stale documentation and opens fix-up PRs —
reached me only via a search summary. **Do not cite as primary.** The adoptable idea (a pass
that re-checks whether each recorded lesson is still true and proposes deletions) stands on
its own; listed in §9.7 as such.

## 9. The intuitive version

**9.1 One entry point.** `/lesson`, bare, no argument required, no other way in. "Don't do
that" is handled by the model, not by a hook.

**9.2 What it does before asking anything.** (a) If `$ARGUMENTS` is empty, a `Read`+`Grep`-only
subagent reads the last ~30 messages and returns ≤4 candidate mistakes newest-first, each with
tool + concrete input (S6's conversation-analyzer, ported; `lesson-nudge.sh`'s phrase list
moves here). (b) One script, `lesson propose`, folds today's survey into a **decision, not a
menu**, using S7's triage line: command string or file+line → **rule/hook**; reproduces in the
existing runner → **regression test**; bookkeeping/counting/path assembly → **script**;
otherwise → **path-scoped `.claude/rules/` line**, falling back to CLAUDE.md only when no path
scope applies. (c) Write the guardrail. Nothing is proposed that is not already written.

**9.3 The one question**, asked *after* the draft exists, never before:

```
Lock this in?
▸ Block it      <one line describing the written rule>     (default)
  Just note it  one line in .claude/rules/<area>.md
  Not a lesson  discard
```

No question about rungs, sites, cost, or which CLAUDE.md line to cut. `--cost` dies with the
ladder; the script derives it from the action (`block` → "a false deny costs one manual retry").

**9.4 What it writes, by default.** Guardrail = a declarative, hookify-shaped rule file at
`.claude/flow.rules/<slug>.md` (frontmatter `event / pattern|conditions / action / enabled /
created / source`, plus the message body). One generic `flow-rules.sh` per event is registered
in `hooks.json` **once, forever**; user lessons never touch `hooks.json`, never need
`flow doctor`, never need a restart. Regression test unchanged when the rung is `test`.
**The rule file's frontmatter *is* the ruling** (`what`, `mechanism`, `created`, `source` per
S10 REQ-LEARN-02) — PROGRESS.md `## Rulings` stops being the store, which retires the 60-line
budget fight. Scope: project by default, `--global` → `~/.claude/flow.rules/`. The phrase
"harness checkout" never appears; the script resolves it and prints the absolute path.

**9.5 One-line report** via `systemMessage`, the user-facing channel S3 defines ("To surface a
message to the user on any platform, return `systemMessage` in JSON output") and flow uses nowhere:

```
flow: lesson locked — `git push --force` now blocked (.claude/flow.rules/no-force-push.md, 3 tests). Undo: flow lesson undo no-force-push
```

**9.6 Find and undo.** `flow lesson list` → slug, action, created, hit count.
`flow lesson undo <slug>` → delete the rule, revert its commit if any, one line out.
`flow lesson off <slug>` → `enabled: false` (hookify's model). Hit counts come from promoting
the existing `${TMPDIR}/claude-lesson-<session>` counter to a durable per-project file — which
is exactly what `no-nudge-noise.md` asked for and never got.

**9.7 Later:** `flow lesson stale` — rules with zero hits in N days, or whose pattern no longer
matches anything in the repo, proposed for deletion. Adopt the idea from §8.7, cite nothing.

## 10. Delete list

| Delete | Why | Replaced by |
|---|---|---|
| `plugins/flow/hooks/lesson-nudge.sh` | per-turn hook whose entire output is invisible to the user (S3); contradicts `no-nudge-noise.md` recorded 3h21m after its last edit; a process spawn every prompt | phrase list moves into the on-demand analyzer (§9.2) |
| its `UserPromptSubmit` entry in `hooks/hooks.json` (2nd, `timeout: 5`) | same | — |
| `hooks/tests/test_lesson_nudge.sh` `t_lesson_nudge_*` (3 tests) | tests a deleted hook | analyzer fixture |
| `_lesson_nudge()` in `hooks/lib/hookout.sh:128-153` + its 3 call sites in `hook_deny`/`hook_block`/`hook_feedback` | injects model-directed prose into user-visible block reasons; coverage incomplete anyway (`size-guard` bypasses it) | silent `hook_count <sig>` → durable per-project file, read only by `flow lesson list` |
| `t_lesson_counter_*` (2 tests) | same | counter + reader tests |
| `hooks/stop-gate.sh:535-543` `/lesson` paragraph | same; keeps the wedge valve, drops the sentence | wedge valve stays |
| `scripts/lesson-sites` (143 ln, whole script) | a survey the user must interpret | `lesson propose`, which decides |
| `--cost` on `lesson-record` | a counterfactual the user is never asked and the model invents | derived from the action |
| the `docs/decisions.md` step in `SKILL.md` §6 | manual, unenforced, harness-only | rule-file frontmatter is the ledger |
| the 5-row rung table in `SKILL.md` §3 | all 14 internals of §7 enter through it | S7's one line + `lesson propose` |
| the two `${CLAUDE_PLUGIN_ROOT}` literals in `SKILL.md` | leaks a shell variable into the transcript | one `flow lesson …` CLI on PATH |

Keep unchanged: `lesson-record`'s `mkdir` lock, duplicate refusal, fence-aware `awk`, and the
concurrency test — good machinery, moves to the new store. Keep Step 4's red-then-green and
Step 5's adversary **for the `test` and `hook` rungs only**.

## 11. Before / after — "don't do that"

**Before** (today, per the files above):

```
user> don't do that again
      [lesson-nudge.sh prints to stdout — invisible to the user]
flow> Reverted. That was a mistake — I edited the generated file. Want me to run
      /lesson so it can't happen again? (a test, hook or script beats a promise)
user> yes
flow> Step 1 — I need a concrete input: which file, and the exact edit? A lesson
      without a reproducible input becomes prose.
user> src/generated/api.ts, you rewrote it by hand
flow> $ ~/.claude/skills/flow/scripts/lesson-sites
      test present package.json test script
      hook absent no project hooks; add a hooks block to /repo/.claude/settings.json…
      lint present /repo/.claude/flow.config.json (maxFileLines, maxFuncLines…)
      script present /repo/scripts
      skill present ~/.claude/skills/harness/skills/<name>/SKILL.md…
      claude-md present /repo/CLAUDE.md 96/100; ~/.claude/CLAUDE.md 40/40; global AT BUDGET
      progress present /repo/PROGRESS.md 41/60 lines
      Rung: hook (project) — but this project has no hooks block, so I'd add one to
      .claude/settings.json. Alternatively a CLAUDE.md line: the project file is
      96/100, so that costs a line. Which do you want?
user> the hook
flow> [hook + registration + flow doctor + adversary + lesson-record --what/--mechanism/
       --cost + decisions.md row + chore(lesson) commit]
      Lesson: hand-edited a generated file · Rung: hook + test (project)
      Red: t_generated_guard_blocks_edit — FAIL (allowed) · Green: 118 passed, 0 failed
      Adversary: 1 significant (Write instead of Edit), added as test, now caught
      Ruling: hand-edited src/generated — hook generated-guard.sh + 2 tests — a false
      deny costs one manual retry
      Next: /flow --resume
```

Four user turns; two of them are the user doing the harness's bookkeeping.

**After** (proposed):

```
user> don't do that again
flow> Reverted. I hand-edited src/generated/api.ts, which is generated.
      Locking that out — one question:

      Lock this in?
      ▸ Block it      Edit/Write under **/generated/** is refused          (default)
        Just note it  one line in .claude/rules/generated.md
        Not a lesson  discard
user> [enter]
flow: lesson locked — edits under **/generated/ now blocked
      (.claude/flow.rules/no-edit-generated.md, 2 tests). Undo: flow lesson undo no-edit-generated
```

One user turn, one keypress. Same guardrail, same tests, same revertability. The whole
difference is who does the bookkeeping.

## 12. UNVERIFIED register

- **§8.7 / S12** — `openai.com/index/harness-engineering/` HTTP 403; doc-gardening is
  second-hand, must not be cited as OpenAI's practice.
- **`/remember`** — named in the brief; **does not exist**. S5 lists `/memory`, `/init`,
  `/doctor` and no `/remember`. S1: the trigger is plain English ("remember that…"), not a command.
- **`hook_feedback` stderr rendering** — S3 confirms `permissionDecisionReason` is
  user-visible and `UserPromptSubmit` stdout is Claude-only; the exact transcript treatment of
  PostToolUse exit-2 stderr was not isolated to a quotable sentence. Treated as
  "Claude-visible, user-visible at most in transcript detail".
- **Bare `/lesson` vs `/flow:lesson`** — S4 states the bare form works "unless another command
  already uses that name"; not exercised live this session. No collision found in the skill list.
- **Hardlink divergence** — inodes 929022 / 929070 measured 2026-09-07 on this machine.
  Whether the Edit tool preserves the link on a partial edit was reasoned from tool semantics,
  not measured.
- **`flow doctor` `plugin-skills-flow` WARN** — read from `bin/flow:793`, not executed.
