# Agents and commands

## Slash commands (plugin skills)

The plugin namespaces a skill by its **directory** name, so `skills/spec` is
`/flow:spec` and `skills/next` is `/flow:next`. There is no `commands/`
directory in the plugin — adding one would give every command two homes.

- **/flow:spec `<idea>`** — the only door. Computes the route (`bounded｜oneshot｜dispatch`) from intent gaps × irreversibles × footprint and *states* it as a fact, runs ONE batched discovery turn of pre-answered assumptions, writes only what that route needs (nothing / `TASKS.md` / `spec.md` + `TASKS.md` + `design.md`), then `flow use` and `flow lint`. Flags: `--amend "<change>"`, `--interview`, `--unattended`.
- **/flow:next** — the only build verb. Reads `flow next --json` first and does exactly that state's action: draft `TASKS.md`, build one wave through fresh `developer` subagents (≤4 in one message, or the `build-slices` Workflow at ≥3 ready `[P]` tasks), run a phase's `Independent test:`, run the gates and write `PASS-<sha>.md`, open or promote the PR, archive a merged feature. Every turn ends with `Next: /clear, then /flow:next`. Flags: `--force`, `--escalate`, `--qa`, `--unattended`.
- **/flow:prep `<idea>`** — optional pre-step: one open question per turn, writing `.specs/NNN-<slug>/PREP.md` so `/flow:spec` consolidates instead of re-asking.
- **/flow:loop** — run a task until a deterministic verifier passes; the unattended shape of everything above.

## Agents and commands (user-level, in the dotfiles)

### Agents (`~/.claude/agents/`)

- **adversary** (model: sonnet) — Adversarial diff reviewer for ultracode workflows — a kill-mandate reviewer that assumes the code is wrong and must earn any pass verdict. Read-only; returns severity-sorted, evidence-gated findings and a BLUF verdict, never edits code. Spawn 2+ per implementer with distinct lenses (correctness, security, gaming, cross-file, spec) via agentType 'adversary'. Also useful solo for a hostile second opinion on any diff or spec.
- **claim-check** (model: sonnet) — Re-runs the evidence behind status claims made in the main session ("tests pass", "committed", "deployed", "gate green", "file exists") and returns CONFIRMED / UNSUPPORTED / NOT-CHECKABLE per claim, with the command it ran and its trimmed output. Read-only; never edits; never hunts for new problems beyond the claims handed to it. Spawn after a compaction, after a failed tool call, before trusting any "done" report, and before a gate clears. Do NOT use for: reviewing a diff for defects (use adversary).
- **developer** (model: sonnet) — Fleet implementer for ultracode workflows. Implements exactly one assigned unit of work from a SPEC, returns evidence (real command output, test counts), and never touches files outside its assignment. Use as agentType 'developer' in Workflow fan-outs, or standalone for any well-specified implementation task that should run on Sonnet.
- **explorer** (model: haiku) — Read-only codebase reader for flow step 1 and any "where does X live" question. Returns locations with path:line receipts it opened this run, never a plan and never an edit. Spawn up to three in parallel with distinct questions.
- **triage** (model: sonnet) — Reproduces a reported error and localises it — returns the minimal failing command, exact error text, file:line origin, and the top two candidate causes. Never edits, never proposes a fix; that's the developer's job once triage hands off. Spawn from `fix` Step 2 (reproduction) with the pasted error text, or any time an error needs localising before someone starts changing code. Do NOT use for: implementing the fix (use developer).

### Commands (`~/.claude/commands/`)

- **/aside** — Log a note without changing course on the current task; classifies it as a durable project fact, a durable personal preference, or session-only, and proposes the exact line to add.
- **/memory-audit** — Audit ~/.claude/projects/*/memory/*.md for staleness, dead structural references, and credential-shaped strings; propose deletions and CLAUDE.md promotions as a diff.
- **/ship** — Commit, push, and open a draft PR with a conventional-commit message and a verification checklist.
- **/wrap** — Snapshot session state into PROGRESS.md — Now/Next/Done/Rulings/Blocked — and print the exact command to resume.
