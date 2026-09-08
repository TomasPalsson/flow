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
| `flow publish` | Optional leaf: mirror unchecked tasks to GitHub issues. Never called by the pipeline. |

Optional pre-step: `/flow:prep` interviews first and leaves a `PREP.md` that
`/flow:spec` consolidates from. Unattended runs are `/flow:loop`.

## State on disk — six files, no transcript

```
.specs/
  .current                     one line: 003-entry-tagging
  .next-call-count             consecutive `flow next` calls; reset by any state change
  LEDGER.md                    append-only: one line per shipped feature, plus every Ruling:
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
├── workflows/                   build-slices · review-diff · research-sweep · plan-review
│                                 (registered as flow:<name> via the Workflow tool)
├── flow-templates/              spec.md · TASKS.md · REVIEW.md · PROGRESS.md ·
│                                 CLAUDE.project.md · gates.yml.tmpl
├── bin/flow                     the CLI · bin/lib/ (router, lint, tick, use, publish) ·
│                                 bin/lib/loop/ (contract, tick, verify, tamper, CLI)
└── skills/                      spec, next, prep, spec-judge, qa, audit,
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
