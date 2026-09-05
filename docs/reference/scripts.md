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

## slice-brief

```
Usage: slice-brief <plan-file> <N> [--design <code-design.md>] [--out <path>]

Extracts the "## Slice N — ..." section from <plan-file> (through the
line before the next top-level "## " heading; fence-aware per the plan
grammar — a line inside a ``` or ~~~ fence is never a heading).

When --design is given and contains a matching
"## Contract for this slice — Slice N" block, appends that block.

Writes the result to --out (default .claude/slices/<N>-brief.md,
directory created) and prints the output path.

Exit 1 if the slice heading is not found in <plan-file>.
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

## slice-overlap

```
Usage: slice-overlap <plan-file> [--json] [--waves]

Parses every slice's "- **Files**:" list (fence-aware per the plan
grammar — a line inside a ``` or ~~~ fence is never a heading, and never
contributes to a slice's file list). Prints one line per file owned by
2 or more slices as:
  <file>: Slice A, Slice B

Exit 1 if any overlap is found, 0 otherwise.
--json prints {"overlaps":[{"file":"..","slices":["Slice A","Slice B"]}]}.

--waves computes dependency waves per "- **Depends-on**:" (a slice is
ready when every Depends-on slice is done): prints one line per wave
  wave <k>: Slice A, Slice B
Overlap detection runs first and is unchanged: when an overlap exists,
--waves prints the same overlap output (plain or --json) described
above and exits 1 without computing waves. Otherwise, --waves --json
prints {"waves":[[1],[2,3]]} (raw slice numbers, one array per wave).
A dependency cycle prints "INVALID: dependency cycle among Slice A,
Slice B" and exits 1.
```

## plan-lint

```
Usage: plan-lint <plan-file>

Validates a feature-plan.local.md file against the plan grammar (C7):
  - required top-level headings, in order:
      ## Behavior Inventory
      one or more ## Slice <N> — <title>
      ## Gate Phases
  - the Behavior Inventory section contains a table with the header row
      | Behavior | Slice | Verified by |
    a separator row, and at least one data row
  - every slice has ### Slice <N> — RED / GREEN / REFACTOR sub-headings
  - every "- **Depends-on**: Slice <M>" refers to an existing,
    lower-numbered slice
  - optional "## Discovered" section (C17): only after the last
    ## Slice <N> and before ## Gate Phases; each bullet must read
    "- <what> — discovered in Slice <N> — <defer|fold into Slice M>"
    and name an existing slice. Its absence is never reported.

Lines inside ``` or ~~~ fences are never treated as headings, bullets,
or table rows.

Prints "OK" when the plan is clean, or one MISSING/INVALID line per
problem found. Exit 1 if any problem is found, 0 otherwise.
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

## lesson-sites

```
Usage: lesson-sites [--dir <path>] [--json]

Inspects <path> (default: the current directory's git toplevel, else cwd)
and prints, per rung of the /lesson ladder, the site a guardrail would use:

  test      the project's test runner and directory, or the harness suites
            when <path> is the harness plugin itself
  deny      <path>/.claude/settings.json permissions.deny block (present
            only when the file exists and contains "deny"); ~/.claude/
            settings.json for a machine-wide rule
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
Usage: lesson-record --what <text> --mechanism <text> --cost <text> [--file <PROGRESS.md>] [--date <YYYY-MM-DD>]

Appends
  - Ruling: <what> — <mechanism> — <cost> (<YYYY-MM-DD>)
under "## Rulings" in <PROGRESS.md> (default ./PROGRESS.md), after the
last ruling of that section (fenced ``` blocks are never headings). The
date defaults to today (UTC) and may be pinned with --date; an existing
undated legacy ruling is never rewritten. Creates the section at the end
when it is missing, and the file from the minimal template when it does
not exist. Refuses an exact duplicate line (exit 3, nothing written); a
ruling with the same <what> but a new mechanism or cost is written and
noted on stderr as superseding. Every write is checked and serialised
through <PROGRESS.md>.lock. Prints the line written, then a second line
`marker: lesson(<YYYY-MM-DD>): <what>` to paste on the rung; when the
file is now over 60 lines, a warning to stderr (exit stays 0).

Exit codes: 0 written · 2 usage or malformed --date · 3 exact duplicate · 4 cannot write
```

## lesson-stats

```
Usage: lesson-stats [--dir <project>] [--file <PROGRESS.md>] [--log <lesson-fires.log>] [--now <YYYY-MM-DD>] [--prune-days <days, default 30>] [--json]

<project> defaults to the current directory's git toplevel, else the
current directory (pwd -P). <PROGRESS.md> defaults to PROGRESS.md and
<lesson-fires.log> to .claude/lesson-fires.log, both under <project>
unless given as an absolute path.

Reads the "## Rulings" section of <file> and <log> and prints one row per
ruling, in file order, then one row per orphan fire (a fire whose
(date, what) pair matches no ruling), grouped by date and what, in
first-seen order:

  date  rung  caught  last  escaped  verdict  what

caught is the number of matching lesson-fires.log lines; last is days
since the most recent one, relative to --now (default: today); escaped
counts later rulings with the same what; verdict is one of unmeasured,
escaped, held, prune?, young (or orphan, for an unmatched fire). Missing
values print as "-" in the default tab-separated output, or as null with
--json (a JSON array of objects, numbers unquoted, keys in the order
date, rung, caught, last, escaped, verdict, what). Malformed
lesson-fires.log lines are skipped and counted in a single warning on
stderr.

Exit codes: 0 printed · 2 usage, a malformed --now, or no PROGRESS.md
```

## lesson-claude-md

```
Usage: lesson-claude-md --file <CLAUDE.md> --line "<text>" [--what <what> --date <YYYY-MM-DD>] [--cut "<exact existing line>"] [--budget <lines>]

Appends <text> to <CLAUDE.md>, followed by " <!-- lesson(<date>): <what> -->"
when --what is given (date defaults to today, UTC). Refuses an exact
duplicate (normalised: strip any HTML comment, lowercase, keep only
a-z0-9 and space, collapse spaces) with exit 3, naming the matching line.
At or over the line budget (100 lines for a project file, 40 for
$HOME/.claude/CLAUDE.md, or the --budget override) the line is refused
with exit 5 unless --cut names an existing line to remove first, in
which case that line is removed and the new one appended in the same
locked write. Advisory: any existing line sharing at least half of the
new line's distinct 4-letter-or-longer words is printed to stdout as
"similar: <n>: <line>" (exit stays 0). Creates a missing project file;
refuses to create a missing $HOME/.claude/CLAUDE.md (exit 4).

Exit codes: 0 written · 2 usage · 3 duplicate or --cut target missing · 4 cannot write · 5 at budget
```
