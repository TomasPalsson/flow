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
