# harness (plugin)

Core plugin of the `harness` marketplace: deterministic lifecycle hooks, a
scripts toolbox, saved workflows, the `harness` CLI, and the skill set that
implements `/flow` and its supporting agents.

## Layout

```
plugins/flow/
├── .claude-plugin/plugin.json   name, version, description, skills: ["./skills/"]
├── hooks/                       *.sh, lib/hookout.sh, tests/ moved from dotfiles;
│                                 hooks/hooks.json (the manifest binding events to
│                                 ${CLAUDE_PLUGIN_ROOT}-relative paths) is unit M2's job
├── scripts/                     new-spec · slice-brief · review-package · slice-overlap
│                                 plan-lint · skills-lint · workflow-lint · codebase-map · tests/
├── workflows/                   build-slices · review-diff · research-sweep · plan-review
│                                 (registered as flow:<name> via the Workflow tool)
├── flow-templates/           REVIEW.md · PROGRESS.md · CLAUDE.project.md · gates.yml.tmpl
├── bin/flow                  the harness CLI (doctor · init · check · skills-lint · install ·
│                                 loop) · bin/lib/loop/ (contract, tick, verify, tamper, CLI)
└── skills/                      flow, flow-spec, flow-deepen, flow-handoff, flow-to-issues,
                                  feature, spec-judge, shared, qa, audit, fix, loop, ultracode,
                                  overkill, pr-reviewer, claude-md, skill-forge, skill-improver,
                                  skill-judge, claude-improver, find-skills, prompt-engineer,
                                  better-plan, grill-me, grill-with-docs, brainstorm,
                                  develop-idea, scrutinize-idea, prep
```

`shared/` is reference material and scripts consumed by other skills (`shared/scripts/`,
`shared/*.md`); it has no `SKILL.md` of its own and is never loaded directly.

## Status (this unit — M1, layout only)

This unit performed the **copy** of hooks, scripts, workflows, flow-templates,
the CLI binary and skills from `~/.dotfiles/claude/.claude/` into this repo,
unchanged (`cp`/`rsync -a`, preserving file modes and the executable bit), with
two narrow exceptions:

- `rtk-fast.sh`, `rtk-rewrite.sh` and `.rtk-hook.sha256` under `hooks/` were
  **not** copied — the SPEC marks them out of scope for every unit ("No unit
  edits, wires, or tests them"; the orchestrator wires `rtk-rewrite.sh` into
  settings by hand). `__pycache__/` (a gitignored build artifact) was not
  copied either.
- `scripts/tests/test_agents.sh`, `test_commands.sh` and `test_explorer.sh`
  were **not** copied, and the wrap.md-specific assertions inside
  `test_spec_prose.sh` / `test_wave5_prose.sh` were removed: all of them
  hard-depend on `claude/.claude/agents/` and `claude/.claude/commands/` as
  siblings of `scripts/`, and per C21 those two directories "stay in the
  dotfiles forever, never plugin content" — there is no layout in which that
  relationship can exist inside this repo. The full tests still run, and
  pass, against the real files in the dotfiles' own `scripts/tests/` suite.

This unit did **not**:

- rewrite any in-file references (`.claude/skills/...`, `~/.claude/scripts/...`,
  `Workflow({name:'build-slices'})`, etc.) to `${CLAUDE_PLUGIN_ROOT}`-relative
  paths, or write `hooks/hooks.json` (the event-to-script manifest) — both are
  unit M2's job per the C21 unit map;
- remove anything from the dotfiles tree — the dotfiles copies are still the
  live, deployed source until the orchestrator (M4) verifies the plugin loads
  and cuts over.

Until M2/M3 land, files under `skills/**` and `hooks/**` still reference
`~/.claude/...` and `.claude/...` paths (including `CC_SHARED_SCRIPTS`/
`CC_SCRIPTS_DIR` defaults inside `stop-gate.sh`/`spec-gate.sh`), and
`bin/flow`'s template resolution still expects the dotfiles layout as its
fallback — do not treat this plugin as installable yet.

## Live loading (once cut over)

`~/.claude/skills/flow -> ~/Desktop/Projects/flow/plugins/flow`
(created by `flow install`) makes this plugin auto-load in place as
`flow@skills-dir`; its `workflows/` directory registers each workflow as
`flow:<name>`. See `../../docs/SPEC.md` (`C21`) for the full contract.
