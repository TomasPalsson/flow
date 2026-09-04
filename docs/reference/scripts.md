# Scripts

Deterministic helpers in `~/.claude/scripts/`. Output is what the model sees; the source never enters context.

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
  references/<...>  or  scripts/<...>  (relative to the containing skill)

Relative references resolve against the containing skill's own
directory. ".claude/skills/..." references resolve against $HOME and
against the skills directory's parent. "~/.claude/..." and
"$HOME/.claude/..." references resolve against $HOME. After a
candidate path exists, its basename must also appear verbatim in a
listing of its parent directory (guards against case-insensitive
filesystems hiding a wrong-case reference).

References containing "<", ">", "*", or the literal text "NNN" are
treated as placeholders and ignored.

Prints "MISSING <file>:<line> <path>" for every reference that does
not resolve; exit 1 if any. Also prints "TOOL <file>:<line> <cmd>"
(does not affect the exit code) for "command -v <cmd>" or a
backticked binary name, when <cmd> is one of the allowlisted tools
(better-plan, rtk, gh, bun, uv) and is not installed on this machine.

--usage [<history.jsonl>] (default: $HOME/.claude/history.jsonl):
counts, per installed skill (a directory under $HOME/.claude/skills)
and command ($HOME/.claude/commands/*.md), how many prompts in the
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

