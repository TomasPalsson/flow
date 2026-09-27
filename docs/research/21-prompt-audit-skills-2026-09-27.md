# Prompt audit: every skill against /claude-api (2026-09-27)

Applies the `/claude-api` prompt-audit guide (`shared/prompt-audit.md`, plus the Claude
Opus 5.5 behavioral shifts in `shared/model-migration.md`) to every skill in this repo.

## Assumptions

- **Scope:** the 69 skills under `plugins/{aws,design,finance,flow,flow-extras,tooling,web}/skills/`
  — each `SKILL.md` and every `*.md` under the skill directory, plus `plugins/flow/skills/shared/`.
  Skipped: `plugins/synced/` (untracked copies of Anthropic's own skills), the 5 skills under
  `plugins/flow/scripts/tests/fixtures/` (tests pin their text), agents, workflows, output styles,
  and user-level `~/.claude/`.
- **Target model:** Claude Opus 5.5, the model Claude Code runs these skills on; no skill pins its
  own model. Advice about *building* Claude apps is written model-generally and names a model only
  where the claude-api docs tie a fact to it.
- **Applied:** documented-pattern findings at high or medium confidence. **Not applied:** frontmatter
  (routing text with its own evals), volatile specifics the claude-api docs cannot confirm,
  low-confidence idiom-dating, and text a test asserts.

## Summary

1. **Prompting advice that taught dated patterns** — `prompt-engineer`, `agent-architecture`,
   `agent-evals`, `claude-md`. They said to skip the "because" behind rules, steer thinking with
   prose or `budget_tokens`, never improve a prompt by adding to it, cap output with numbers,
   "remove all judgment calls", and listed wrong cache minimums (Opus 4.7 at 4,096 where the source
   says 2,048; the 512-token minimum on the newest models missing). All rewritten to current guidance.
2. **Pressure language in ~60 skills** — caps `NEVER/MUST/ALWAYS`, `CRITICAL:`/`IMPORTANT:`
   prefixes and `MANDATORY — READ ENTIRE FILE` load-gates now read at normal volume. Every
   constraint, load condition and reason is kept. This also matches the repo's own `skill-judge`
   rule (more than ~3 caps-emphasis lines costs points).
3. **Fossils** — old-model behavior claims ("Claude 4.6 …", "Sonnet 4.5 began treating MUST as
   suggestions", the Opus 4.5 "think" word sensitivity), migration-relative wording ("now",
   "no longer", "a fix that just landed"), and history asides.

Counts: first pass 352 findings (269 applied, 83 report-only), then a consistency sweep of ~90
load-gate and prefix edits, then 12 corrections after review. Group 1 (prompt text): nearly all
findings. Group 2 (brittle config): 18 volatile specifics, report-only. Group 3 (tool
descriptions): not applicable — skills define no tool schemas. Group 4 (request config): not
applicable — no request-building code in skills.

Clean, no change: `aws-lambda-microvms`, `ui-animation`, `find-skills`, `grill-me`,
`grill-with-docs`, `issue`, `prep`, `spec-judge`, `clean-code`, `cocoindex`, `python-code-style`,
`slack`.

## Kept on purpose

- `## NEVER` headings — a house convention `skill-judge` and the tests look for. Only the items
  under them were lowered in volume.
- Design skills' lists of named defaults to avoid (fonts, colors, radii, shadows) — Claude Opus 5.5
  responds best to named patterns, not "avoid a generic look".
- Numbered steps wherever order matters: flow's state machine, gates, pipelines, destructive and
  auth flows.
- `no-slop/SKILL.md:35` naming Opus 4.5/4.6 — a mitigation should name the model it patched so it
  can be re-tested (see open item 6).
- Severity labels (`CRITICAL/HIGH/…`), quotes of the bad pattern used as examples, and domain rules
  (Icelandic grammar, third-party API contracts).
- Test-pinned: `next/SKILL.md` "**NEVER** end a turn without a last `Next:` line"
  (`test_wave5_prose.sh`) and `skill-forge/SKILL.md` "STOPS before Step 1" (`test_skill_forge.sh`).

## Open — needs a human (not applied)

| # | Where | Finding | Proposed |
|---|---|---|---|
| 1 | `strands-agentcore/SKILL.md:199,270,331-333`, its `references/{deployment,production,patterns}.md`; `agui-strands/references/ag-ui-strands.md:21,85`; `worklog/references/api-reference.md:123` | Model IDs in code examples are a generation or more old (Sonnet/Opus 4.5, Opus 4.6). | Swap to current IDs after confirming the exact Bedrock runtime ID your account lists; the claude-api docs only give Mantle IDs (`anthropic.claude-opus-5`). |
| 2 | `ultracode/references/fleet-economics.md:8,15-25` | Sonnet price row framed around a Sep 1, 2026 intro-price cliff that has passed. | Confirm today's Sonnet 5 price, then restate one current number. |
| 3 | `gh-cli/SKILL.md:10` | Pins gh 2.85.0 (Jan 2026); installed gh is 2.100.0. | Re-verify the documented flags, then bump the version line. |
| 4 | `agent-architecture/SKILL.md:129`, `references/context-management-api.md` | Compaction cheat-sheet names `compact-2026-01-12`; the on-demand `compaction` parameter (`compact-2026-09-04`) is not mentioned. | Add the on-demand form once its docs are checked. |
| 5 | `claude-md/SKILL.md:12,175`; `agent-architecture/references/tool-design.md:42`; `prompt-engineer/references/claude-specific.md:14` | Uncited numbers (rule-capacity, XML "15-20% gains", tool-search uplift on Opus 4/4.5). | Source them or drop the number. |
| 6 | `no-slop/references/developer-block.md` | Anthropic's over-engineering countermeasure written for Opus 4.5/4.6. | Re-test on Opus 5.5 with `flow eval` before keeping or trimming. |
| 7 | Frontmatter of `agent-architecture`, `agent-browser`, `agent-evals`, `api-explorer`, `audit`, `better-plan`, `brainstorm`, `claude-improver`, `claude-md`, `develop-idea`, `figma-to-strapi`, `google-ads`, `hubspot-prospect`, `icelandic-professor`, `new-project`, `seo-audit`, `ui-ux-pro-max`, `website-cloner`, and others | Caps and long trigger-phrase lists in `description`. | Change only against the routing eval in `plugins/flow/evals/`. |
| 8 | `agent-evals/references/agentcore-and-bedrock.md:77` | Bedrock judge-model list pinned to older models. | Check AWS's current list. |
| 9 | `loop/SKILL.md:14` | `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=8`, dated. | Re-verify against the current Claude Code release. |

## Verification

- Every changed file is inside a skill directory; no frontmatter line changed
  (`git diff -U0 | grep -E '^[-+](description|name|model|allowed-tools):'` is empty).
- 266 of the first pass's 396 hunks changed only letter case (meaning identical by construction).
  The other 130, and every sweep edit, were read by hand; 12 were corrected (e.g. a dropped
  "check both `Task` and `Agent` names" tip restored, a judge template's thinking line restored for
  judges that run without thinking, a "disable thinking" tip that contradicts Opus 5.5 rewritten).
- The 30 test files that read skill text: 3715 passed / 35 failed after, 3708 / 42 before — no new
  failure. Every remaining failure existed before and is unrelated to skill wording
  (`test_commands` 24, `test_install` 5, `test_lint` 5, `test_cli_plugin` 1); the loop-UI tests
  are flaky and passed on this run.
