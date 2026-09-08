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

## flow lesson

```
Usage: flow lesson <subcommand> [options]

Not a standalone script — a `flow` subcommand (plugins/flow/bin/lib/lesson/).
Turns one observed mistake into a guardrail; see the `/lesson` skill for the
one-question flow built on top of it. Spec 005 D-3/D-6.

  propose --did <t> --should <t> --input <t> [--json] [--global]
                            Decide the rung (rule | test | script | note) and
                            draft the guardrail. Writes only the draft, under
                            $TMPDIR, and prints its id.
  lock <draft-id> --choice block|note|discard
                            block: write what propose's block field names — the
                            rule, the test, or (note and script rungs, where
                            there is nothing a hook can match) the note.
                            note: write the path-scoped note instead.
                            discard: write nothing and drop the draft.
                            block and note append one Ruling to .specs/LEDGER.md
                            and print the one-line receipt.
  list [--global]           One row per lesson: slug, rung, action, created,
                            hits, enabled.
  undo <slug> [--global]    Delete the rule file, or the note line. For a test
                            lesson: print the file to delete, and stop — flow
                            never deletes code.
  off <slug> [--global]     Set enabled: false in the rule file.
  on <slug> [--global]      Set enabled: true.
  stale [--days 30] [--global]
                            Rules with zero hits that old, or whose pattern
                            matches nothing in the repo.

The rung: a command string or a path pattern → rule (a
.claude/flow.rules/<slug>.md file, read by hooks/flow-rules.sh); the input
reproduces in the project's own test runner → test (a red test file); plain
bookkeeping → script (a "script wanted" note naming what to automate);
otherwise → note (a line in .claude/rules/<area>.md).
--global reads and writes ~/.claude/flow.rules/ instead of the project's.
A second lock of a slug that was only noted promotes it to a rule.

Exit codes: 0 done · 1 refused (missing argument, unknown draft or lesson,
slug already locked)
```
