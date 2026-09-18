# flow (plugin)

Core plugin of the `harness` marketplace: deterministic lifecycle hooks, a
scripts toolbox, saved workflows, the `flow` CLI, and the skill set behind the
two-command build surface.

## The surface

Two slash commands, and the CLI they lean on. There is no third door.

| Command | What it does |
|---|---|
| **`/flow:spec <idea>`** | The only door. Computes the route (`bounded｜oneshot｜dispatch`) from intent gaps × irreversibles × footprint, runs ONE batched discovery turn, writes only what that route needs, points `.specs/.current` at it, lints it. Flags: `--amend "<change>"`, `--interview`, `--unattended`. |
| **`/flow:next`** | The only build verb. Reads `flow next --json`, does exactly that one state's action, and ends with `Next: /clear, then /flow:next`. Flags: `--force`, `--escalate`, `--qa`, `--unattended`. |
| `flow next [--json]` | The router. A pure query of disk → `{state, command, why, gates}`. |
| `flow lint [--waves] [--json]` | Parses `TASKS.md`: ERROR/WARN/INFO, each ERROR with its own `fix:` string, `[P]` disjointness proved per wave. |
| `flow tick <ID>` | The only writer of `[x]`. Measures the sha itself. |
| `flow use <NNN-slug>` | Writes `.specs/.current`. Only needed with two features open. |
| `flow stealth [<store>] [--check [--offline] [--json]]` | Moves an untracked `.specs/` into a private store repo outside the target, links it back, hides it in `.git/info/exclude`, installs `post-checkout`/`commit-msg` hooks. `--check` only reports. |
| `flow publish` | Optional leaf: mirror unchecked tasks to GitHub issues. Never called by the pipeline. |
| `flow statusline [--install\|--print]` | Cached, read-only mirror of `flow next --peek` for Claude Code's `statusLine` hook. Never blocks a render; `--install` wires it into `~/.claude/settings.json`, `--print` hands you the snippet instead. |

Optional pre-step: `/flow:prep` interviews first and leaves a `PREP.md` that
`/flow:spec` consolidates from. Only a sliver of an idea? `/flow:develop-idea`
grows it first and, on your yes, leaves a seed `PREP.md` that `/flow:prep`
resumes. Unattended runs are `/flow:loop`. A defect
spotted while building something else is parked with `/flow:issue` — a GitHub
issue when `gh` is available, else an `.specs/ISSUES.md` entry carrying the
five fields a spec needs — never fixed inline. An issue reference (`143`,
`#143`, `I-003`, "do issue 143") is a first-class argument to `/flow:prep`,
`/flow:spec` and `/flow:fix`: the body and every comment become discovery
input. Flow writes back exactly twice — picked up, and shipped — per
`skills/shared/issue-refs.md`. GitHub is never a routing predicate.

### Stealth mode

For a public or client repo where the spec itself must not ship: `/flow:spec
--stealth` (or `flow stealth` by hand, once per clone) moves `.specs/` into a
private git repo outside the target, links it back as an untracked symlink,
and hooks re-link it in new worktrees while blocking spec vocabulary from
commit messages. Nothing is saved as config — `flow next` detects stealth
from disk on every call, so every other command behaves exactly as before.

## State on disk — six files, no transcript

```
.specs/
  .current                     one line: 003-entry-tagging
  .next-call-count             consecutive `flow next` calls; reset by any state change
  LEDGER.md                    append-only: one line per shipped feature, plus every Ruling:
  ISSUES.md                    append-only: parked out-of-scope defects (I-NNN). Only /flow:issue writes it
  BLOCKED.md                   presence sentinel — the router stops while it exists
  003-entry-tagging/
    spec.md                    dispatch only, ~110 lines
    design.md                  only when 2+ tasks share a name, id type, error shape or resource
    TASKS.md                   plan + progress + resume + commit ledger. THE state
    NOTES.md                   append-only: Discovered:, Ruling:, Amendment refs
    PASS-<sha>.md              the machine half of done; a later commit invalidates it for free
    verify/                    tracked evidence. A claim with no artifact here does not count
    review/                    gitignored. Diffs only. Never a routing predicate
  archive/2026-09-08-002-price-rules/
```

Position is recomputed from these files on every call, so `/clear`, a crash, a
compaction and a `git checkout` all self-heal. Nothing lives in the transcript
— which is why every `/flow:next` turn ends by recommending `/clear`.

## Layout

```
plugins/flow/
├── .claude-plugin/plugin.json   name, version, description, skills: ["./skills/"]
├── hooks/                       lifecycle hooks + hooks.json manifest + tests/
├── scripts/                     new-spec · flow-lint · task-brief · review-package ·
│                                 skills-lint · workflow-lint · codebase-map · tests/
├── agents/                      developer · adversary · triage · explorer · claim-check
│                                (the subagent types the skills and workflows dispatch by
│                                name; shipped here so the plugin stands alone)
├── workflows/                   build-slices · review-diff · research-sweep · plan-review
│                                 (registered as flow:<name> via the Workflow tool)
├── flow-templates/              spec.md · TASKS.md · REVIEW.md · PROGRESS.md ·
│                                 CLAUDE.project.md · gates.yml.tmpl
├── bin/flow                     the CLI · bin/lib/ (router, lint, tick, use, publish) ·
│                                 bin/lib/loop/ (contract, tick, verify, tamper, CLI)
└── skills/                      spec, next, prep, issue, spec-judge, qa, audit,
                                  flow-deepen, fix, loop, ultracode, overkill, pr-reviewer, claude-md,
                                  skill-forge, skill-improver, skill-judge, claude-improver,
                                  find-skills, prompt-engineer, better-plan, grill-me,
                                  grill-with-docs, brainstorm, develop-idea, scrutinize-idea,
                                  shared
```

The plugin namespaces a skill by its **directory** name: `skills/spec` is
`/flow:spec`, `skills/next` is `/flow:next`. There is no `commands/` directory.

`shared/` is reference material and scripts consumed by other skills
(`shared/scripts/`, `shared/*.md`); it has no `SKILL.md` and is never loaded
directly.

## Live loading

`~/.claude/skills/flow -> ~/Desktop/Projects/flow/plugins/flow`
(created by `flow install`) makes this plugin auto-load in place as
`flow@skills-dir`; its `workflows/` directory registers each workflow as
`flow:<name>`. See `../../docs/SPEC.md` (`C21`) for the full contract.
