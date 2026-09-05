---
name: audit
description: "Stage-gated parallel code audit for a whole codebase or module: recon → 6 parallel detection agents (correctness, security, performance, design, tests, style) → dedup + triage → user approval gate → fix planning → second approval gate → serialized apply with revert-on-failure → verification. Use for whole-codebase/module debt inventory, health checks, modernization, production-readiness sweeps, or quality audits. Triggers on: /audit, audit this codebase, audit repo, find tech debt, pay down debt, code health check, make production-ready, refactor everything, apply clean code, quality sweep. Do NOT use for: single-PR or branch review ≤10 files (use /pr-reviewer), one-file cleanup (use /simplify), bug fix (use /fix), feature work (use /feature), style-only formatting (run the formatter), or uncommitted-change review (use /review). Scope threshold: whole-codebase or whole-module only — not for incremental branch work."
---

# /audit — Stage-Gated Codebase Audit

Auditing a codebase badly makes it worse. You produce 200 findings, the user reads 10, fixes 3, and ignores the rest. Or an agent "cleans up" intentional code and the build breaks. This skill enforces the discipline that keeps audits useful: **hot-spot-first entry**, **bounded parallel detection**, **hard budget caps**, **user approval gates before any change**, **serialized fixes with revert-on-failure**, and **separate contexts for detect vs. fix**.

> "An agent that simultaneously detects and fixes has no opportunity for human review between 'this looks wrong' and 'I changed it'. Trust destroyed." — core principle, non-negotiable.

## Pre-flight thinking framework

Before running Phase 0, think about the user's actual goal. The answer changes the budget allocation across dimensions and which findings get priority at Phase 2. The Phase 2 scoring formula is `severity_weight × confidence`, but the pre-flight goal tilts which dimensions' findings reach the budget cap first.

- **Production readiness / pre-launch** → At Phase 2 budget step (8), fill slots from `category: security` and `category: correctness` first (ranked by `severity_weight × confidence` within each category), then fill remaining slots from other categories by score. Performance matters only for user-facing latency.
- **Onboarding a new team member** → At Phase 2, fill slots from `category: design` and `category: tests` first. Set all Phase 4 `fix_eligibility` to `review-required` or `discussion` — no auto-fix path. The audit is a MAP of where to look, not a fix plan.
- **Paying down accumulated debt** → At Phase 0, limit hot-spot scope to recon top-10 only. At Phase 2, drop every P3 finding (not to backlog — DROP) and surface only P0-P2. Fix phase prioritizes `local` blast radius with mutation-score > 70% coverage.
- **Selling the team on debt** → Quality over quantity. At Phase 2, cap the budget at 5 findings regardless of size tier. Rank by `failure_scenario` clarity and blast-radius impact, not severity alone. One killer example beats ten nitpicks.

If the user's goal is unclear, ask ONE clarifying question before starting. Record the goal in `plan.md` — Phase 2 step 8 reads it to apply the category promotion above.

## Workspace

All audit state lives in `.audit/` at the project root. This is persistent across sessions — a paused audit can be resumed. If `.audit/` already exists when the skill starts, ASK the user: "Resume previous audit or start fresh?" before touching anything.

```
.audit/
├── recon.txt                  # Phase 0 output
├── plan.md                    # which dimensions, which agents, which scope
├── findings-raw/              # Phase 1 — one JSON file per agent
│   ├── correctness.json
│   ├── security.json
│   └── ...
├── findings-consolidated.json # Phase 2 — deduplicated, ranked
├── findings-approved.json     # Phase 3 — user-selected subset
├── findings-backlog.json      # dropped findings (user can recall)
├── fix-plans/                 # Phase 4 — one per approved finding
├── applied-fixes.log          # Phase 6 — audit log
└── verification.md            # Phase 7 — final report
```

### Resume protocol

If the user says "resume", determine the last completed phase from artifact presence and re-enter at the next one. Do NOT re-run completed phases — they're expensive and the existing artifacts are valid.

| Artifact state | Re-enter at |
|----------------|-------------|
| `recon.txt` missing | Phase 0 — reconnaissance |
| `plan.md` missing | Phase 0 — re-plan from existing recon |
| `findings-raw/*.json` incomplete (some agents missing) | Phase 1 — re-run ONLY missing agents, do not re-run completed ones |
| `findings-consolidated.json` missing | Phase 2 — dedup from existing raw files |
| `findings-approved.json` missing | Phase 3 — re-present Gate 1 to user from existing consolidated file |
| `fix-plans/` incomplete | Phase 4 — plan only the approved findings not yet planned |
| `applied-fixes.log` incomplete | Phase 6 — continue from the last applied finding ID, never re-apply |
| all present | Phase 7 — verification (or "audit already complete, re-run?") |

Budget/size-tier is determined by the audited SCOPE (subtree, monorepo package, single subsystem), NOT the total repo size. A single `medium` package in a `huge` monorepo uses the medium budget of 15 findings.

## NEVER rules (orchestrator hard drops — read before ANY phase)

These apply regardless of what detection agents claim. No agent override. Internalize before Phase 0.

- **NEVER let a detection agent plan or apply its own fix.** Confirmation bias corrupts review of own work — always spawn a fresh context for fix planning and another fresh context for verification.
- **NEVER pass Wave 1 severity or confidence scores to other agents.** Only pass facts (file lists, hot-spots, stacks, framework). Opinion cascades poison independence.
- **NEVER auto-fix auth / permissions / payments / PII / data deletion.** No confidence score, no coverage level, no user override makes this safe.
- **NEVER parallelize fix application.** Line numbers drift after the first patch and subsequent patches fail silently or patch the wrong location. Fixes are serialized, smallest blast radius first.
- **NEVER surface P3/nitpick/style findings as primary report.** They go to `findings-backlog.json`. The user can recall with "show backlog".
- **NEVER treat a null finding result as failure.** A clean audit is a success — present the "Clean Audit" template with "What Was Checked".
- **NEVER refactor a file with <50% line coverage or no tests** without explicit user opt-in after a warning. "Refactoring without tests is restructuring" — you have no oracle for semantic preservation.
- **NEVER drop findings below the budget without recording them.** Dropped ≠ deleted. Every filtered finding goes to `findings-backlog.json` so the user can recall them.

(Detection-domain rules — what NOT to flag as findings — live in the Detection anti-patterns section below. This NEVER list covers orchestrator process discipline only.)

## Detection anti-patterns (never flag these — the audit noise catalog)

Internalize before Phase 0. These are the most common audit noise generators — every finding report with more than three of these loses credibility entirely. Agents that flag them produce noise that trains teams to ignore all audit output.

- **Style a formatter catches** — just run the formatter (prettier/black/gofumpt/rustfmt). If the formatter accepts it, it's not a finding.
- **SHA-256+ as "weak hash"** — only SHA-1 and MD5 are weak. SHA-256, SHA-384, SHA-512, BLAKE2 are fine.
- **Long functions by line count alone** — Ousterhout's deep modules are good. Only flag when the function does multiple distinct things.
- **DRY violations before the Rule of Three** — two instances could be coincidence. Sandi Metz: "duplication is far cheaper than the wrong abstraction."
- **Single-implementation interfaces** — `UserRepository` + `UserRepositoryImpl` never mocked, never swapped = DIP noise. Only flag when substitution is actually needed.
- **SRP violations with a single actor** — one class with 15 behaviors all owned by the same stakeholder has ONE reason to change, not 15. Pulverized code is worse than cohesive code.
- **`console.log` / `print` / dead comments** — not debt. Not security. Not audit scope.
- **Dev-dependency CVEs** — not actionable without compromising the dev environment (different threat model).
- **Access control without specific middleware-trace evidence** — SAST cannot prove coverage. The agent cannot know if middleware enforces it globally. Always `propose-only`, never a primary finding.
- **`.env.example` with placeholder values** — if the values are clearly fake, it's documentation, not a leak.
- **Informational CVSS (< 4.0)** — noise unless there's a concrete exploitability path in this codebase's call graph.
- **Refactoring without tests** — the finding is "missing tests", not "bad structure." You have no oracle for semantic preservation without tests.
- **Comments explaining WHY** — business rationale, non-obvious constraint, workaround for a specific bug — these are assets, not smells.
- **Speculative findings without a concrete `failure_scenario`** — "this might be a problem" is uncitable. Every finding needs `input → behavior → failure` or it's capped at 0.60 confidence and dropped.
- **Failure scenario laundering** — a `failure_scenario` that ends with "in the worst case", "could potentially", "an attacker could", or similar hedging is NOT concrete. It's speculation dressed up as evidence. Require the input, the observed behavior, and the exact undesired outcome with no hedging verbs. If the agent cannot phrase it without hedging, it doesn't have evidence.
- **Findings on generated code** — `*.d.ts`, `*_pb.go`, `*_pb2.py`, `schema.graphql.ts`, OpenAPI SDK output, migration snapshots. These produce finding floods that drown real findings, and there is no actor-owner for the fix (every finding closes as "won't fix — regenerated"). Agents must filter these even if they appear in hot-spots (SDK regeneration produces high churn).
- **Finding IDs from a previous session when resuming** — when a user resumes and says "approve C-1", the IDs may have been re-assigned if Phase 2 consolidation re-ran. Always re-present the finding list with fresh IDs on resume; never accept cross-session ID references from memory.

> **Loading discipline**: Do NOT pre-load all references at skill activation. References are phase-scoped. Load each reference only when the phase that requires it is reached — `orchestration.md` and `finding-schema.md` at Phase 1 launch, `triage.md` at Phase 2 start, `finding-schema.md` again at Phase 3 presentation, `fix-safety.md` at Phase 4 start. `language-playbooks.md` and `security-playbook.md` are loaded by their respective dimension agents, not by the orchestrator.

> **Architecture note**: SKILL.md is the process orchestrator; references carry the domain knowledge. A reference is a tool the orchestrator reaches for, not content that lives in context by default.

## Phase 0 — Reconnaissance (MANDATORY first step)

Run the reconnaissance script. Do NOT skip this and jump to reading files — you will audit the wrong files.

```bash
bash scripts/audit-recon.sh "${PROJECT_DIR:-.}" > .audit/recon.txt
```

**What it produces**: detected language stacks, build tools, monorepo structure, size tier (small/medium/large/huge), top-20 hot-spot files by `churn × LOC`, temporal coupling pairs, test coverage signals, `.gitignore` hygiene flags.

**Hot-spot first, not file-first**: Adam Tornhill's principle — complexity is only a problem where there is ALSO high change frequency. Beautiful stable code can wait; messy frequently-changed code is where debt costs real money. The recon output is the input to every other phase.

**Monorepo disambiguation**: If recon detects nx/lerna/pnpm-workspace/turbo/cargo-workspace/go-workspace, STOP and ask the user which package(s) to audit. Auditing the entire monorepo at once violates the budget cap. Accept user input as any of: filesystem path (`packages/api`), workspace name (`@company/api`), or build target (`//api:server`). Verify the path exists and is non-empty before running recon on it — if no match, re-ask with the list of detected packages.

**Size-tier implications**:
| Tier | LOC | Findings budget | Agent strategy |
|------|-----|-----------------|----------------|
| small | <5k | 10 | all 6 dimensions |
| medium | 5k-50k | 15 | all 6 dimensions, hot-spot focused |
| large | 50k-500k | 20 | hot-spot top-15, sample by subsystem |
| huge | >500k | 25 per subsystem | audit one subsystem at a time, ask user to pick |

Write `plan.md` summarizing: stacks detected, size tier, which dimensions will run, hot-spot files, findings budget.

## Phase 1 — Parallel Detection (6 dimensions, strict scope bounds)

**MANDATORY — READ ENTIRE FILE** before launching agents: [`references/orchestration.md`](references/orchestration.md) — wave discipline, agent prompt template, dedup rules, failure modes.

**MANDATORY — READ ENTIRE FILE** before launching agents: [`references/finding-schema.md`](references/finding-schema.md) — every agent writes findings in this schema. Schema compliance is validated at Phase 2.

Launch 6 agents in parallel (single message, multiple Agent tool calls). Each agent writes findings as JSON to `.audit/findings-raw/<dimension>.json`. Each agent is `sonnet` model, `mode: bypassPermissions`. Each agent MUST load `references/finding-schema.md` (schema compliance) plus the specific references in the table below. Do NOT load references from other agents' rows — token waste and scope bleed.

| Dimension | Agent scope | Load (required) | Do NOT load |
|-----------|-------------|-----------------|-------------|
| correctness | type errors, null paths, error handling, contract violations | `language-playbooks.md` (correctness sections) | `security-playbook.md`, `triage.md` |
| security | secrets, dep CVEs, injection, crypto, auth | `security-playbook.md` | `language-playbooks.md`, `triage.md` |
| performance | hot-path allocations, N+1, async blocking, bundle signals | `language-playbooks.md` (performance sections) | `security-playbook.md`, `triage.md` |
| design | hot-spot smells (Fowler), temporal coupling, shallow modules | `triage.md` | `language-playbooks.md`, `security-playbook.md` |
| tests | coverage gaps, brittleness, missing assertions, no mutation signal | (no extra ref — agent prompt template) | all language/security/triage refs |
| style | beyond-formatter inconsistency only | (no extra ref — run formatter check only) | all refs — most findings are dropped as tool-overlap at Phase 2 |

**Bounded scope directive** — every agent prompt MUST include an explicit "Do NOT cover" clause listing the OTHER dimensions' scope. Without this, findings duplicate.

**Facts not opinions**: pass only recon facts (hot-spot file list, language, framework) to agents. Never pass severity or classification — let each agent independently score confidence. Severity cascades are a real failure mode.

**Wait for ALL agents** before proceeding. Check each output file exists and is >20 lines of JSON. Re-run any silent failures.

## Phase 2 — Deduplication and Prioritization (orchestrator-only)

**MANDATORY — READ ENTIRE FILE**: [`references/triage.md`](references/triage.md) — ranking by `business_impact × technical_risk / fix_cost`, Fowler quadrant, P0-P3 tiers, when NOT to refactor.

Do NOT delegate this phase to a subagent — synthesis is orchestrator work.

Rules (in order):
1. **Schema validation** — drop any finding missing required fields (`file`, `line_start`, `severity`, `confidence`, `failure_scenario`, `what_i_checked`).
2. **Tool-overlap drop** — drop any finding a standard linter/type-checker already flags (unused imports, missing semicolons, formatter violations, type errors).
3. **Failure scenario gate** — any finding lacking a concrete `failure_scenario` → confidence capped at 0.60 and labeled `question`.
4. **Exact-location merge** — same `file + line_range` across agents → merge to single finding at highest severity; increment `agent_count`.
5. **Pattern merge (Rule of Three)** — ≥3 findings sharing a category across different files → collapse to one pattern-level finding with `pattern_count`.
6. **Confidence gating** — ≥0.85 keep; 0.60-0.85 downgrade one tier; <0.60 → label `question`, never auto-fix.
7. **Access control cap** — auth/access-control findings are capped at medium confidence NO MATTER WHAT the agent claimed (SAST on access control is unreliable regardless of tool).
8. **Budget enforcement** — rank by `severity_weight × confidence` (critical=4, major=3, minor=2, nitpick=1), keep top-N where N comes from the size-tier table. Critical + live-secrets + exploited-CVE findings EXCEED the budget (always shown).
9. **Blast radius tagging** — `local` (1 file), `module` (2-5), `cross-cutting` (6+). Only `local` is auto-fix eligible.

Dropped findings go to `findings-backlog.json` (user can recall with "show backlog").

## Phase 3 — Gate 1 — User Approval (HARD STOP, non-skippable)

**MANDATORY — READ ENTIRE FILE** before presenting: [`references/finding-schema.md`](references/finding-schema.md) §"Report Format" and §"Null Result Format".

Present the ranked, deduplicated findings in Markdown using the template in finding-schema.md. Group by `Critical / Major / Cross-Cutting Discussion / Backlog Count`.

**This gate is not automatable**. Do NOT proceed until the user gives a clear answer. "Maybe", "interesting", "looks good" are NOT approval.

Ask: *"Which findings should I address? Reply with: `all critical`, `all`, `1,3,5`, `none`, `show backlog`, `auto-fix all eligible`, or `cancel`."*

Approval vocabulary (parse user input deterministically):

| Command | Behavior |
|---------|----------|
| `all critical` | Approve all `severity: critical` findings only |
| `all` | Approve every shown finding |
| `1,3,5` (comma list of IDs) | Approve only the listed finding IDs |
| `none` / `skip` | Approve nothing, skip directly to verification summary |
| `show backlog` | Present the dropped findings; then re-ask |
| `auto-fix all eligible` | Approve all AND set `auto_fix_opted_in: true` — Gate 2 is skipped for `fix_eligibility: auto-fix` findings, still required for others |
| `cancel` | Abort the audit; leave `.audit/` intact for later resume |

Anything else → re-ask. Do NOT interpret "maybe", "interesting", "looks good" as approval.

**Null result case**: If zero findings survive filters, present the "Clean Audit" template. This IS a success — do not treat silence as failure.

Persist the user's selection to `findings-approved.json`:
```json
{
  "approved_finding_ids": ["C-1", "M-1"],
  "auto_fix_opted_in": false,
  "approved_at": "<timestamp>",
  "user_command": "all critical"
}
```

## Phase 4 — Fix Planning (separate agent contexts, orchestrator pre-screens eligibility)

**MANDATORY — READ ENTIRE FILE**: [`references/fix-safety.md`](references/fix-safety.md) — safe-refactoring decision tree, auto-fix precondition stack, "safe-looking" refactorings that break code.

**Orchestrator pre-screening (before spawning any fix agent)**: The auto-fix eligibility decision is fragile — a misclassification bypasses Gate 2 and risks applying changes without human review. The orchestrator must deterministically evaluate these conditions from existing artifacts BEFORE delegating to a fix agent:

| Condition | How orchestrator checks | If fails |
|-----------|------------------------|----------|
| 1. `confidence ≥ 0.85` | Read from `findings-approved.json` | → `review-required` |
| 2. `blast_radius == local` | Read from `findings-approved.json` | → `review-required` |
| 5. NOT in auth / payments / PII / data deletion | Grep target file for `auth/`, `payment`, `pii`, `delete.*user`, `drop.*table`, `rm -rf`, session / token / credential keywords; if any match → `review-required` regardless of agent opinion | → `review-required` |
| 6. NOT a public API / exported symbol | Check if `file` path matches `src/index.*`, `**/api/**`, `**/public/**`; grep for `export ` on target symbol | → `review-required` |
| 7. NOT in code with explanatory comment | Read target file, check for `// intentional`, `# audit-ignore`, `/* explains */` within 5 lines of finding | → `review-required` |
| 8. NOT same file as another approved finding | Scan `findings-approved.json` — if two approved findings share a `file`, both go to `review-required` (serialization forces review to avoid patch conflicts) | → `review-required` |

For the findings that pass pre-screening, spawn a fix-planning agent with a FRESH context that sees ONLY: the finding body, the target file, and `fix-safety.md`. The agent evaluates only the remaining two conditions:
- **3. Semantic-preserving transformation** — matches one of the `safe-to-automate` refactorings in fix-safety.md; NOT in the "looks safe but breaks code" list.
- **4. Mutation score > 70%** — check for mutation testing data (stryker, mutmut, PITest) OR tests exist AND user explicitly opted in at Gate 1 (`auto_fix_opted_in: true`).

Both must hold for `fix_eligibility: auto-fix`. Otherwise the agent downgrades to `review-required` or `discussion`.

Each fix plan records: proposed diff, blast radius, which preconditions hold (pre-screened by orchestrator vs evaluated by agent), and the final `fix_eligibility`:
- `auto-fix` — all 8 conditions hold
- `review-required` — needs user to see the diff before applying
- `discussion` — cross-cutting or architectural; cannot be fixed mechanically. Skill presents but does not propose a mechanical fix.

## Phase 5 — Gate 2 — Fix Approval

This gate is the last stop before destructive operations. It must be at least as deterministic as Gate 1.

**Skip conditions** — a fix skips Gate 2 ONLY when ALL of these hold:
- `fix_eligibility: auto-fix` (all Phase 4 preconditions held)
- `findings-approved.json.auto_fix_opted_in == true` (user explicitly said `auto-fix all eligible` at Gate 1)
- Not in auth / payments / PII / data deletion code (checked again at Gate 2, regardless of Phase 4)

Otherwise, present each approved fix as a reviewable diff block:

```
[F-N] <finding subject>  [blast_radius: local | module | cross-cutting]
--- <file>
+++ <file>
<unified diff of proposed fix>

Approve, reject, or edit? Reply:
  `approve` — apply this fix as-is
  `reject` — skip this fix, mark as "user declined"
  `edit: <instruction>` — SPAWN A FRESH fix-planning agent with the original finding + current diff + user's edit instruction, then re-present the revised patch at Gate 2. The orchestrator does NOT revise the patch inline — that would reintroduce confirmation bias on the already-reviewed diff, violating the scanner/fixer/verifier isolation principle
  `cancel` — abort Phase 6 entirely, leave all remaining fixes unapplied
```

Record each Gate 2 decision in `findings-approved.json` under the finding's `gate2_status` field: `approved`, `rejected`, `edited`, or `cancelled`. Do NOT proceed to Phase 6 for a finding until its `gate2_status` is set.

For `discussion` findings, Gate 2 behaves differently — the skill presents the cross-cutting concern but does NOT propose a mechanical fix. Ask: *"This is a design conversation, not a mechanical fix. Note it, dismiss it, or create a ticket?"*

## Phase 6 — Apply Fixes (SERIALIZED, one commit per fix, revert on failure)

**Never parallelize fixes**. Fix-ordering conflicts on shared files are a real failure mode — fix A changes line numbers, fix B's patch no longer applies.

Protocol for each approved fix, in strict order. The working tree MUST be clean before each iteration — check `git status --porcelain` first.

1. **Verify clean state**: `git status --porcelain` must be empty. If not, STOP — there are uncommitted changes from a prior fix or human edit.
2. **Read tests** for the affected code path. If absent AND this is an auto-fix → STOP, flag as "unverifiable", escalate to user.
3. **Run tests** (pre-fix). Record pass/fail state. If any test is already failing, STOP — don't apply fixes on a red tree.
4. **Apply the fix** (minimal diff via Edit tool, never sed/awk). The fix remains UNCOMMITTED at this point.
5. **Run tests** (post-fix). If any previously-passing test now fails → **REVERT uncommitted changes** with `git checkout -- <changed-files>`, mark the finding "fix attempt failed", escalate. Do NOT commit a broken fix.
6. **Commit** with format: `refactor(audit): <finding-summary> [audit/<finding-id>]`. Use `refactor:` for semantic-preserving, `fix:` for bug fixes, `chore:` for tidyings. ONE fix per commit.
7. **Append** to `applied-fixes.log`: finding ID, commit SHA, tests-before, tests-after, timestamp.

**Always test BEFORE committing.** The revert at step 5 uses `git checkout --` (discards uncommitted changes), not `git reset --hard HEAD~1` (which would reset an already-committed state). If the fix has already been committed when a test regression is detected later, use `git revert HEAD --no-edit` (safer than hard reset because it creates a revert commit and preserves history).

**Two-attempt rule mechanics**:
- **Attempt 1**: apply the fix exactly as planned in Phase 4 (the plan was produced in a fresh context and should not be second-guessed).
- If tests fail → `git checkout -- <files>`, re-read the target file (it may have changed from a prior fix in the queue), produce a MINIMAL revised patch addressing only the same finding, apply once more.
- **Attempt 2**: if tests fail again → revert, mark the finding as "fix attempt failed — requires human review", move on.
- **NEVER make a third attempt**. Two failures with tests signal a semantic dependency static analysis missed. Iteration will not fix it; human context will.

**Cascade failure threshold**: if ≥50% of approved fixes fail both attempts, STOP the apply phase immediately. Present to the user:
> *"N of M approved fixes failed to apply cleanly — the codebase likely has interdependencies that static analysis missed. Options: `continue` (attempt remaining fixes one-by-one with your review), `abort` (leave remaining fixes unapplied), or `replan` (re-run Phase 4 with the failed fixes as additional context)."*

This prevents the scenario where an audit consumes significant user attention while producing minimal net improvement.

## Phase 7 — Verification

Spawn a separate verifier agent (fresh context, never the detection or fix agent). Give it: the original finding list, the applied-fixes log, the changed files. It verifies each approved finding is actually resolved by rereading the code.

Output `.audit/verification.md`:
- Approved findings: N
- Auto-fixed (tests passed): N
- User-approved + applied: N
- Reverted: N
- Remaining for human: N
- Cross-cutting discussion items: N (links)
- Backlog count: N (say "show backlog" to see)

Present a 5-line summary to the user. Done.
