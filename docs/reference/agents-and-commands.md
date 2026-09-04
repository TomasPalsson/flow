# Agents and commands

## Agents (`~/.claude/agents/`)

- **adversary** (model: sonnet) — Adversarial diff reviewer for ultracode workflows — a kill-mandate reviewer that assumes the code is wrong and must earn any pass verdict. Read-only; returns severity-sorted, evidence-gated findings and a BLUF verdict, never edits code. Spawn 2+ per implementer with distinct lenses (correctness, security, gaming, cross-file, spec) via agentType 'adversary'. Also useful solo for a hostile second opinion on any diff or spec.
- **claim-check** (model: sonnet) — Re-runs the evidence behind status claims made in the main session ("tests pass", "committed", "deployed", "gate green", "file exists") and returns CONFIRMED / UNSUPPORTED / NOT-CHECKABLE per claim, with the command it ran and its trimmed output. Read-only; never edits; never hunts for new problems beyond the claims handed to it. Spawn after a compaction, after a failed tool call, before trusting any "done" report, and before a /goal clears.
- **developer** (model: sonnet) — Fleet implementer for ultracode workflows. Implements exactly one assigned unit of work from a SPEC, returns evidence (real command output, test counts), and never touches files outside its assignment. Use as agentType 'developer' in Workflow fan-outs, or standalone for any well-specified implementation task that should run on Sonnet.
- **explorer** (model: haiku) — Read-only codebase reader for flow step 1 and any "where does X live" question. Returns locations with path:line receipts it opened this run, never a plan and never an edit. Spawn up to three in parallel with distinct questions.
- **triage** (model: sonnet) — Reproduces a reported error and localises it — returns the minimal failing command, exact error text, file:line origin, and the top two candidate causes. Never edits, never proposes a fix; that's the developer's job once triage hands off. Spawn from `fix` Step 2 (reproduction) with the pasted error text, or any time an error needs localising before someone starts changing code.

## Commands (`~/.claude/commands/`)

- **/btw** — Log a note without changing course on the current task; classifies it as a durable project fact, a durable personal preference, or session-only, and proposes the exact line to add.
- **/memory-audit** — Audit ~/.claude/projects/*/memory/*.md for staleness, dead structural references, and credential-shaped strings; propose deletions and CLAUDE.md promotions as a diff.
- **/ship** — Commit, push, and open a draft PR with a conventional-commit message and a verification checklist.
- **/wrap** — Snapshot session state into PROGRESS.md — Now/Next/Done/Rulings/Blocked — and print the exact command to resume.
