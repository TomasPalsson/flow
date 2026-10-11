# Scripts

Deterministic helpers in `plugins/flow/scripts/` (`~/.claude/scripts` links here). Output is what the model sees; the source never enters context.

## new-spec

```
Usage: new-spec "<title>" [--dir .specs] [--prefix flow/] [--no-branch] [--worktree] [--json]

Computes the next 3-digit spec number from existing <dir>/NNN-* entries
(001 when none exist), slugifies <title> to lowercase ASCII [a-z0-9-]
(max 40 chars, computed under LC_ALL=C), and creates <dir>/NNN-slug/.

Unless --no-branch is given, creates and checks out branch
<prefix><slug> from the current HEAD. With --worktree, instead creates
the branch in a sibling worktree at
  $(git rev-parse --show-toplevel)/../code-worktrees/<branch>
via `git worktree add -b`.

Writes .claude/flow.json =
  {"number":"NNN","slug":"...","spec_dir":"...","branch":"...","worktree":"..."|null}
and prints the same JSON to stdout.

--json is accepted for symmetry with the other scripts; output is
already JSON on every run.

Does not check working-tree dirtiness. Exit 1 only when a branch is
requested outside a git repository, or <dir> is not writable.
```

## task-brief

```
Usage: task-brief <TASKS.md> <ID> [--design <design.md>] [--out <path>]

Writes a one-task brief containing:
  Base: <short sha of HEAD, measured now — before the task is dispatched>
  the task's phase heading with its Goal: and Independent test: lines
  the task's own line, verbatim
  any "## Contract" block in --design whose heading names <ID>

Default --out is <dir-of-TASKS.md>/review/<ID>-brief.md (review/ is
gitignored; a brief is a generated artifact and never a predicate).
Prints the output path. Exit 1 when <ID> is not a task in <TASKS.md>.
```

## review-package

```
Usage: review-package <base> [<head>] [--out <path>]

<head> defaults to HEAD. Verifies both refs with `git rev-parse --verify`.
Writes to --out (default .claude/review/<base-short>..<head-short>.diff):
  git log --oneline base..head
  (blank line)
  git diff --stat base..head
  (blank line)
  git diff -U10 base..head

Prints the output path, then the line count of the written file.
Exit 1 if a ref does not resolve. The diff is never printed to stdout.
```

## flow-lint

```
Usage: flow-lint [<TASKS.md>] [--json] [--waves]

Validates a TASKS.md against the flow v2 task grammar:

  header   Spec: · Design: · Base: <sha> · Route: bounded|oneshot|dispatch
           · Test: <cmd>          (optional Approved:/Verified: lines)
  sections ## Behaviors, ## Phase N — <title>, ## Gates
  task     - [ |x|~] <ID> [P]? <desc> — files: <p,p> — verify: <`cmd`|human: <obs>>
                     [— after: <IDs>] [— dropped: <reason>] [— done: <sha>]
  IDs      T### tasks · CHK### human checkpoints · G### gates

ERRORS   [P] tasks whose files: intersect inside one wave; missing verify:;
         an [x] whose done: sha is not in Base..HEAD or whose commit touched
         none of its files:; an ID present at HEAD: and absent now; [~] with
         no dropped:; unknown or cyclic after:; a malformed task line.
WARNINGS a phase with no Goal: or no Independent test:; [x] with no done:.
INFO     Route: oneshot with more than 5 tasks.

Every ERROR carries a fix: string. --json prints the machine form
{ok, errors, warnings, info, waves, tasks, header}. --waves prints the
computed dispatch waves. Exit 1 when there is at least one ERROR.

With no <TASKS.md>, resolves the active feature the way the router does:
$FLOW_SPEC → .specs/.current → branch flow/<slug>.
```

## prep-lint

```
Usage: prep-lint <prep-file>

Validates a PREP.md file against the prep grammar:
  # Prep — <title>
  Gathered: <date> · Questions: <n> of <m> · Route: <route> · Status: <status>

  ## Decisions
  - D-NN <text> — user, Q<n>
  ## Not this
  - <text>
  ## Discretion
  - <text>
  ## Assumptions
  - A-NN <text> — evidence: <path:line|none> — confidence: high|medium|low — <confirmed Qn|corrected Qn|unconfirmed>
  ## Verify
  - <text>
  ## Open
  - Q: <question> → <resolution or "deferred to spec">

Route must be one of: spike, bounded, oneshot, dispatch.
Status must be one of: interviewing, ready for spec, done in chat.
The header separator may be " · " or " - "; matching is on field names,
not the separator.

Lines inside ``` or ~~~ fences are never treated as headings or bullets.

Prints "OK" when the prep file is clean, or one "ERROR: ... — fix: ..." or
"WARN: ... — fix: ..." line per problem found. Exit 1 if any ERROR is
found, 0 otherwise (including when only WARNs are found).
```

## skills-lint

```
Usage: skills-lint [<skills-dir>]
       skills-lint --usage [<history.jsonl>]

Scans every *.md file under <skills-dir> (default: $HOME/.claude/skills)
for path references of the form:
  .claude/skills/<...>
  ~/.claude/<...>
  $HOME/.claude/<...>
  ${CLAUDE_PLUGIN_ROOT}/<...>
  references/<...>  or  scripts/<...>  (relative to the containing skill)

Relative references resolve against the containing skill's own
directory. ".claude/skills/..." references resolve against $HOME and
against the skills directory's parent. "~/.claude/..." and
"$HOME/.claude/..." references resolve against $HOME.
"${CLAUDE_PLUGIN_ROOT}/..." references resolve against the nearest
ancestor directory of the scanned file that contains a
.claude-plugin/plugin.json (that plugin's root); a reference with no
such ancestor is reported MISSING. After a candidate path exists, its
basename must also appear verbatim in a listing of its parent
directory (guards against case-insensitive filesystems hiding a
wrong-case reference).

References containing "<", ">", "*", or the literal text "NNN" are
treated as placeholders and ignored, as is any reference whose basename
stem is a single character or the literal X, Y, foo, or bar (e.g.
"references/a.md"), and any reference inside a ``` or ~~~ fence (C16).

Prints "MISSING <file>:<line> <path>" for every reference that does
not resolve; exit 1 if any. Also prints "TOOL <file>:<line> <cmd>"
```

## workflow-lint

```
Usage: workflow-lint [<file-or-dir>...]

Validates each saved Workflow-tool script (*.js) against the C11/C13 rules:
meta purity/name (top-level keys only), phase() titles (quoted or backtick,
failing closed on anything else), no Date.now/Math.random/new Date, no
TypeScript syntax, every agent() call pins a top-level agentType or model,
the file parses, and build-slices.js schedules slices via parallel().

With no arguments, scans $HOME/.claude/workflows. A directory argument
scans its top-level *.js files; a file argument is checked directly.

Prints "OK <file>" or "<file>: <rule>: <problem>" lines; exit 1 on any
problem found in any file.
```

## ui-score

```
usage: ui-score [-h] {capture,score} ...

positional arguments:
  {capture,score}

options:
  -h, --help       show this help message and exit
```

```
usage: ui-score capture [-h] --target TARGET [--url URL]
                        [--from-image FROM_IMAGE] [--viewports VIEWPORTS]
                        [--height HEIGHT]

options:
  -h, --help            show this help message and exit
  --target TARGET
  --url URL
  --from-image FROM_IMAGE
  --viewports VIEWPORTS
  --height HEIGHT
```

```
usage: ui-score score [-h] --target TARGET --url URL

options:
  -h, --help       show this help message and exit
  --target TARGET
  --url URL
```

## codebase-map

```
Usage: codebase-map [--out .claude/codebase-map.md] [--max-lines 150] [--force]

Writes a markdown map of the current git repo to --out (default
.claude/codebase-map.md, resolved relative to the current directory).
Line 1 is a stamp comment:

  <!-- codebase-map: head=<short sha> dirty=<8-char hash> generated=<date> -->

Sections:
  ## Entry points   from package.json (main/bin/scripts.dev|start),
                     pyproject.toml [project.scripts], Cargo.toml
                     [[bin]]/src/main.rs, go.mod + main.go, and the
                     first line of README.md
  ## Layout         git ls-files directories to depth 3, with file
                     counts, top 40 by count
  ## Seams          files matching route/router/schema/migration/
                     config/auth/middleware, at most 25
  ## Recipes        3 fixed grep recipes (find a route, find a schema,
                     find where an env var is read)

--max-lines caps total output (default 150); an overflowing map is
truncated with a final "<!-- truncated -->" line.

If the file at --out already exists and its stamp's head+dirty match
the current repo state, prints "unchanged" and exits 0 without writing
anything, unless --force is given.

No dependency beyond git, awk, sed, cksum (python3 is never required).
Exit 1 when not run inside a git repository.
```

## lesson-sites

```
Usage: lesson-sites [--dir <path>] [--json]

Inspects <path> (default: the current directory's git toplevel, else cwd)
and prints, per rung of the /lesson ladder, the site a guardrail would use:

  test      the project's test runner and directory, or the harness suites
            when <path> is the harness plugin itself
  hook      .claude/settings.json (project hooks) or the plugin hooks dir
  lint      .claude/flow.config.json thresholds / .flow/ threshold files
  script    the plugin scripts dir (harness) or the project's bin dir
  skill     the plugin skills dir the current session loads
  claude-md ./CLAUDE.md and ~/.claude/CLAUDE.md with their line counts and
            budget (100 project / 40 global)
  progress  PROGRESS.md (present or not; line count)

Text form: "<rung> <status> <detail>", status is one of present|absent.
--json prints the same as a JSON object keyed by rung.
```

## lesson-record

```
Usage: lesson-record --what <text> --mechanism <text> --cost <text> [--file <PROGRESS.md>]

Appends
  - Ruling: <what> — <mechanism> — <cost>
under "## Rulings" in <PROGRESS.md> (default ./PROGRESS.md), after the
last ruling of that section (fenced ``` blocks are never headings). Creates
the section at the end when it is missing, and the file from the minimal
template when it does not exist. Refuses an exact duplicate line (exit 3,
nothing written); a ruling with the same <what> but a new mechanism or cost
is written and noted on stderr as superseding. Every write is checked and
serialised through <PROGRESS.md>.lock. Prints the line written and, when
the file is now over 60 lines, a warning to stderr (exit stays 0).

Exit codes: 0 written · 2 usage · 3 exact duplicate · 4 cannot write
```

## case-selfcheck

```
Usage: case-selfcheck [--root <evals-dir>] [--keep] [<case-name>...]

Proves each eval case can tell a no-op from a fix. Default: every
evals/xhard-* case. Per case: shape (case.yaml, tags, executable scaffold),
then scaffold a pristine tree — its file graders + postcheck.sh must NOT all
pass (unless the case ships selfcheck-pristine-passes) — then scaffold again,
run solution.sh, and every file grader + postcheck.sh must pass. llm,
tool_used and trace graders are skipped and counted.
Prints PASS/FAIL per case; exit 0 iff no FAIL.

case-selfcheck --live [--model M] [--judge-model J] [--runs N] [-j N]
                      [--out <dir>] [--keep] [--ledger] [<case-name>...]

Runs the cases headless with `claude -p` outside the plugin-eval sandbox, in
throwaway trees, with this checkout's plugin bin first on PATH. Grades regex,
tool_used, llm (headless judge), file graders and postcheck.sh. One
`LIVE <case> score=.. post=.. turns=.. cost=$.. <secs>s` line per run, results in
<out>/results.json. --ledger appends one line to evals/ledger.jsonl.
Exit 0 iff every run passed, 1 otherwise, 2 on setup errors. Spends money.
```

## version-drift

```
Usage: version-drift <repo>

For each plugin in <repo>/.claude-plugin/marketplace.json, read at HEAD:
  (a) its plugin.json version must equal its marketplace entry;
  (b) when files under the plugin changed since the merge-base with main,
      its version must be semver-greater than main's.
(b) is skipped on main, with no main, or for a plugin new on this branch.
git-guard runs it before `gh pr create` / `gh pr ready` in a repo that has
.claude-plugin/marketplace.json.

Exit codes: 0 clean · 1 drift (one line per plugin) · 2 usage or unreadable input
```

## lesson-mine

```
lesson-mine — compact candidate rows from raw Claude Code session transcripts.

Usage: lesson-mine [--skills <dir>]... [--max-bytes N] <session.jsonl>...

/lesson --retro reads these rows instead of a raw jsonl: one transcript line can be
a megabyte, and in Claude Code transcripts tool results, injected system-reminders
and hook output arrive under the user role, so a reader of the raw file mistakes
them for the human correcting the agent. Read-only; stdlib only.

One JSON object per line: {"session", "line", "kind", "text"} with text <= 300 chars.
  correction     a user-role message of plain text (never a tool_result) that is the
                 human's own words once system-reminder, command and hook-output spans
                 are removed, that follows at least one assistant tool_use since the
                 previous human turn, and that reads as a correction
  revert         an assistant Bash call that undoes work (git revert/restore/reset --hard/...)
  hook_block     a hook that blocked or denied an action
  skill_invoked  one row per distinct skill the Skill tool was called with, at its first use
--skills <dir> (repeatable; each <dir>/<skill>/SKILL.md) adds "may_have_fired": the
installed skills whose description shares at least two distinctive words with a
correction and that the session never invoked. A hint to check by reading the
description, not a verdict.
Output is capped at --max-bytes (default 16000); rows drop lowest-priority first
(revert, hook_block, skill_invoked, correction) and a notice goes to stderr.
```

## receipt-check

```
receipt-check - mechanical check of review findings' receipts.

Usage: receipt-check --diff <review-package diff> --root <repo root> < findings.json

stdin is a JSON array of findings (or {"findings": [...]}), each with file, line
and an optional quote. Prints one compact JSON array, one object per finding in
input order: {"index", "disposition", "line", "reason"}.

  verified      the quote is within 5 lines of the cited line at head, or on a
                '-' line of that file's hunks in the diff
  moved         the quote is elsewhere in the same file; "line" is corrected
  unsupported   the quote exists only in another file of the diff
  failed        the file is neither at head nor deleted in the diff, the path
                leaves the root, or the quote appears nowhere
  unverifiable  no quote given, or the finding is malformed

Only "failed" is meant to dismiss a finding. Never throws on a bad finding.
Exit 2 on a usage error (bad flags, unreadable diff, unparseable stdin).

Credit: adapted from vercel-labs/agent-skills vercel-optimize/lib/verify-claim.mjs @ 063bee9 (MIT).
```

## redact

No `--help` (a stdin filter; `--help` prints nothing). Its header comment:

```
redact - stdin -> stdout with secrets, URL credentials and signed-URL query
params masked. Used by /flow:issue before a body is written to .specs,
ISSUES.md or gh. flow-extras handoff.sh keeps an identical copy of the
function below (flow-extras cannot depend on flow); test_redact.sh pins them.
bash 3.2 / BSD portable.
```

## spec-merge

```
spec-merge: fold an archived feature's Behaviors rows into the living SPEC.md.

Usage: spec-merge <TASKS.md> [--into <SPEC.md>] [--slug <name>] [--base <hash>]

The living file (default: .specs/SPEC.md, found by walking up from TASKS.md;
under stealth .specs is a symlink, so the file lands inside the store) is the
current truth of what the product does: one row per behaviour, keyed by the
stable Key column of the Behaviors table. Rows without a Key are ignored, and
nothing is backfilled.

Key cell grammar (comma or semicolon separated):
  tags/add-persists                          add a row
  tags/add-persists, Replaces: tags/add      replace that row; keeps "(Previously: ...)"
  Retire: tags/old                           remove that row (listed under ## Retired)

Exit 0: merged, or nothing to do (a second run changes nothing, byte for byte).
Exit 1: key collision with no Replaces, replaces/retire target missing, a
        duplicate key inside the feature, or a base hash that does not match.
Exit 2: usage error.

A header line `Spec-base: <hash>` (or --base) pins the living file the feature
was written against (the 12-hex prefix printed by the last merge); a living file
that has moved on makes the merge refuse instead of guessing.
```

## version-ledger-lint

No `--help` (`--help` is read as a ledger path, exit 2). Its docstring:

```
version-ledger-lint [--list] [<ledger.md> ...]

Checks version-claims ledgers: markdown tables with the columns
Claim | File | Anchor | Verified | Re-verify. A ledger row fails when
  - the cited file does not exist,
  - the anchor (exact text, quoted in backticks) is not on any line of that
    file (the same test as `grep -F`; line numbers are never used, so
    unrelated edits above the anchor cannot break a row),
  - the Verified cell is not YYYY-MM-DD,
  - the Re-verify command is empty.
File paths are relative to the ledger's own directory. A cell may hold a
literal pipe as \|.

With no ledger arguments it checks every versions.md that has a ledger table
under the plugins tree this script lives in (plugins/*/skills/*/references/).
--list prints those paths and exits 0. Prints nothing when clean.
Exit 0 clean, 1 at least one failing row (one line each, naming the row),
2 on an unreadable ledger (missing, or not UTF-8). A ledger with no parsable
table or zero rows fails (1).
```
