# Spec 005 — `/lesson` v2: one entry point, one question, rules as data

Source: docs/research/10-idiot-proof-harness-2026.md §6 and docs/research/raw/idiot-proof/lesson-ux.md §9–11. Read both first. Runs AFTER spec 004 (it uses `.specs/LEDGER.md` for rulings and the `bin/lib/` module layout).

## Rules for every slice

Same as spec 003. New CLI code goes in `plugins/flow/bin/lib/lesson.js`. Bash 3.2 for hooks. Red-then-green in owned test files. Never weaken tests. Paste both suite summary lines.

## Design (frozen)

D-1 Entry: `/lesson [what went wrong]` (existing skill `flow:lesson`, rewritten to ~60 lines). No hook proposes lessons; `lesson-nudge.sh` is already gone. The model handles "don't do that" by invoking `/lesson` itself when the user corrects it.

D-2 Steps the skill performs: (a) pin the mistake in three lines (Did / Should have / Input) from the conversation — if `$ARGUMENTS` is empty, list ≤4 candidate mistakes from the last ~30 messages newest-first and pick the newest unless the user named one; (b) run `flow lesson propose --did "<…>" --should "<…>" --input "<…>" --json` which DECIDES the rung and DRAFTS the guardrail; (c) ask exactly one question with three options and a default (`Block it` — the drafted rule; `Just note it` — a path-scoped note; `Not a lesson` — discard) via AskUserQuestion when interactive, else default to `Block it` and say so; (d) `flow lesson lock <draft-id> --choice block|note|discard`; (e) print ONE line: `flow: lesson locked — <what> (<file>, <n> tests). Undo: flow lesson undo <slug>`. No rung table, no site survey, no cost question, no PROGRESS.md edit, no decisions.md step.

D-3 Rung decision in `propose` (superpowers' triage line): input is a command string or a path pattern → `rule` (a `.claude/flow.rules/<slug>.md` file); input reproduces in the repo's existing test runner (a failing test can be written) → `test` (draft the test file under the project's test dir, red); bookkeeping → `script`; otherwise → `note` (a line in `.claude/rules/<area>.md`, path-scoped; CLAUDE.md only when no path scope applies). Irreversible classes (destructive commands, secrets, generated dirs) always `rule`. `--global` writes to `~/.claude/flow.rules/`. Recurrence gate: a `note` is promoted to `rule` on the second lock of the same slug.

D-4 Rule file format (hookify-shaped), `.claude/flow.rules/<slug>.md`:
```
---
event: PreToolUse | PostToolUse | Stop
tool: Bash | Edit | Write | NotebookEdit | "*"
pattern: <ERE over tool_input.command or tool_input.file_path>
action: deny | warn | note
enabled: true
created: 2026-09-08
source: "<the Did line>"
hits: 0
---
<message shown when the rule fires; must name the undo: flow lesson undo <slug>>
```

D-5 `hooks/flow-rules.sh`: ONE generic hook registered in hooks.json on PreToolUse (Bash|Edit|Write|NotebookEdit), PostToolUse (same matcher), Stop. Reads project rules (walk up from `hook_project_dir` to the toplevel) then `~/.claude/flow.rules/`; skips `enabled: false`; matches `event`+`tool`+`pattern`; `deny` → `hook_deny` (PreToolUse only), `warn` → `hook_feedback` (PostToolUse) / `hook_block` (Stop), `note` → `hook_note`. Increments `hits:` in the rule file (atomic rewrite) and appends to `.claude/flow.rules/.hits.log`. Honours `.claude/flow.off`. Under 5 ms with no rules; fail-open on unreadable rule files with a `hook_note` naming the file.

D-6 CLI `flow lesson`: `propose` (D-3, writes the draft to `${TMPDIR}/flow-lesson-<id>.json`, prints `{id, rung, slug, files:[...], preview, tests:[...]}`), `lock <id> --choice …` (writes the rule/test/note, appends `Ruling: <date> <slug> — <what> — <mechanism>` to `.specs/LEDGER.md`, prints the one-line receipt), `list` (slug, rung, action, created, hits, enabled), `undo <slug>` (delete the rule/note; for `test` print the file to delete and do not delete code), `off|on <slug>`, `stale [--days 30]` (zero hits, or pattern matches nothing in the repo). Slugs are kebab-case from `should`. Duplicate slug → exit 1 "already locked; undo first". Keep `lesson-record`'s mkdir lock + fence-aware awk for LEDGER appends (move into lesson.js or call the script).

## Slices

### L1 — rule engine hook (model: opus). Owns: NEW `plugins/flow/hooks/flow-rules.sh`, `plugins/flow/hooks/hooks.json` (add the three registrations), NEW `plugins/flow/hooks/tests/test_flow_rules.sh`, `plugins/flow/hooks/tests/fixtures/flow-rules/*.md`.
Implement D-4/D-5. Tests: deny on Bash pattern; warn on Edit path; note on Stop; disabled rule ignored; global + project precedence; malformed frontmatter → hook_note + allow; hits increment; flow.off honoured; no rules → rc 0 silent under 5 ms.

### L2 — CLI (model: opus). Owns: NEW `plugins/flow/bin/lib/lesson.js`, `plugins/flow/bin/flow` (dispatch `lesson` only), `plugins/flow/scripts/lesson-record` (retarget to LEDGER or delete if folded in), `plugins/flow/scripts/lesson-sites` (delete), `plugins/flow/scripts/tests/test_lesson.sh` (rewrite for the new CLI), `plugins/flow/flow-templates/CLAUDE.project.md` (the lesson line).
Implement D-3/D-6. Tests: propose decides `rule` for a command string, `test` when a runner exists (fixture package.json with vitest), `note` otherwise; lock writes the file with the exact frontmatter; list/undo/off/stale; duplicate refused; LEDGER ruling appended once; recurrence promotion.

### L3 — skill + docs (model: sonnet; after L1+L2). Owns: `plugins/flow/skills/lesson/SKILL.md`, `docs/reference/hooks.md` (flow-rules entry), `docs/reference/scripts.md`, `~/.claude/CLAUDE.md` is NOT yours — instead write the replacement wording for its lesson line into `docs/reference/CLAUDE.md.example`, `plugins/flow/scripts/tests/test_spec_prose.sh` (lesson prose tests if any).
Rewrite the skill per D-1/D-2 (~60 lines, no rung table, no `${CLAUDE_PLUGIN_ROOT}` literals, the before/after transcript from research §11 as the example). Run `skills-lint`.

### L4 — integration (model: sonnet; last). Both suites green, `flow doctor`, a dry run in a temp repo: `flow lesson propose --did 'ran git push --force' --should 'never force-push' --input 'git push --force origin main'` → lock → run `flow-rules.sh` with that command → deny → `flow lesson list` shows hits 1 → `undo` → allow. Report receipts.
