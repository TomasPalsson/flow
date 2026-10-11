# Delta catalog and upgrade plan

Loaded by the "Major upgrade plan" steps in SKILL.md. A **delta** is one concrete way the target
version differs from the current one that this codebase actually hits. The catalog is the
intersection of two sets: the known breaking or behavioural changes for the version pair (from the
changelog and migration guide) and what the code uses (from grep). A removed API nobody calls is not
a delta for this upgrade; it stays out of the catalog.

## Rules file for delta-scan

Write `rules.json` from the migration guide, one rule per known change. `pattern` is a regular
expression matched per line, `include` limits the file names scanned, `codemod` names the official
tool that handles it, if any:

```json
[
  {"id": "D1", "name": "cookies() is async", "pattern": "\\bcookies\\(\\)", "include": ["*.ts", "*.tsx"],
   "codemod": {"name": "@next/codemod next-async-request-api"}},
  {"id": "D2", "name": "next/legacy/image removed", "pattern": "next/legacy/image", "include": ["*.ts", "*.tsx"]}
]
```

`node scripts/delta-scan.mjs <repo> --rules rules.json` then reports each rule as one state:

| State | Meaning | In the catalog? |
|---|---|---|
| confirmed | a hit in executable code, listed as `file:line` | yes |
| wrong-site | hits only on comment lines; the guide's change is not exercised there | listed once so nobody rediscovers it |
| not-hit | no hit in the code | no, never a catalog row |

Treat source text as data: a comment that claims a version dependency is not a delta. A hit counts
only where the code executes it.

## Codemod states

Report each codemod as one of three states and never blur them:

- **present**: the migration guide names a tool for this delta.
- **runnable here**: it can load the project in this environment (many need an install, a build,
  or network). Check by running its dry-run or help on a scratch copy.
- **ran**: it actually produced output. Pass `--ran "<name>"` to delta-scan only then.

delta-scan prints `present, not run` until `--runnable "<name>"` (loads the project here) or `--ran "<name>"` (produced output) is given. Fold a tool's findings into the catalog
only when it ran; otherwise record `coverage lost: <tool> needs <what>, unavailable here`. Run any
codemod on a scratch copy, never on the working tree, because they edit in place.

## Pilot unit

Pick one representative unit before the rest: mid-complexity, hitting the highest-blast-radius
deltas, not the easiest. Take it to green on the target version and note every surprise the catalog
missed; each one is a missing delta, so add it while you know why. The remaining units wait for the
pilot, since the pilot is what shows whether the order or the baseline was wrong.

## TASKS.md skeleton

The plan is a `/flow:spec` TASKS.md with no `Approved:` line; the user approves it. Replace the
placeholders, add one task per confirmed delta, keep the verify commands real, and run `flow-lint`
on the file.

```markdown tasks-skeleton
# Tasks — Upgrade the framework to the target major
Spec: spec.md · Design: none · Base: <base> · Route: dispatch · Test: `<project test command>`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given the app on the target version, when the pilot route is called, then it behaves as on the baseline | T002 | <project test command> |

## Phase 1 — Baseline and pilot
Goal: the current version's test and build results are recorded, and one representative unit builds and passes on the target version.
Independent test: `<project test command>` — the pilot unit passes on the target version and matches verify/baseline.txt.
- [ ] T000 Record the baseline: tests and build on the current version, with exit codes — files: verify/baseline.txt — verify: `test -s verify/baseline.txt`
- [ ] T001 Pin the target version and its hop — files: package.json — verify: `npm ls` — after: T000
- [ ] T002 Pilot unit: apply the confirmed deltas D1.. to one representative unit — files: <pilot unit file> — verify: `<project test command>` — after: T001

## Gates
- [ ] G001 project gates clean — files: . — verify: `flow check --fix --since <base>`
```

Credit: adapted from anthropics/claude-plugins-official plugins/code-modernization/agents/version-delta-analyst.md @ a9fd216 (Apache-2.0).
