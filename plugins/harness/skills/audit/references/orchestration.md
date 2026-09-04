---
name: audit-orchestration
description: Parallel agent wave discipline, failure modes, dedup rules, and agent prompt template for the /audit skill. Load before Phase 1 launches detection agents.
---

# Audit Orchestration — Wave Discipline and Agent Contracts

## The Wave Discipline

**Every audit agent runs in parallel within a wave. Waves are sequential. Synthesis is always the orchestrator's job, never delegated.**

1. Wave 1 agents run in full isolation from each other — no shared partial results.
2. Wave 2 does not start until ALL Wave 1 artifacts are validated on disk (file exists, >20 JSON lines, valid schema, "what_i_checked" present).
3. Silent agent failures are indistinguishable from "nothing found" unless you enforce artifact validation. Check every file before proceeding.

**Pipeline failure recovery**:
| Failure | Symptom | Recovery |
|---------|---------|----------|
| Agent wrote nothing | Expected file missing | Re-run agent. Check `mode: "bypassPermissions"` was set |
| Agent wrote stub | File <20 lines or no findings array | Rephrase prompt, split scope if needed |
| Agent produced plausible-but-wrong finding | No `failure_scenario` or cannot verify line exists | Drop at Phase 2 — confidence capped at 0.60, relabeled `question` |
| Two agents found the same thing | Overlapping scope | Merge at Phase 2 exact-location rule, fix scope bounds for next run |

## Agent Prompt Template

Every detection agent gets this prompt shape. DO NOT deviate — the structure prevents scope bleed, confirmation bias, and null-result ambiguity.

```
You are the [DIMENSION] audit agent for /audit. You scan the target files and write findings as JSON to disk.

## Target
Files: [LIST FROM RECON HOT-SPOTS]
Stack: [PYTHON | TYPESCRIPT | RUST | GO | ...]
Framework: [DJANGO | FASTAPI | NEXTJS | ...]

## Your scope (audit these, nothing else)
- [SCOPE 1]
- [SCOPE 2]
- [SCOPE 3]

## Do NOT cover (other agents handle these)
- [OTHER DIMENSION 1] — handled by [OTHER AGENT]
- [OTHER DIMENSION 2] — handled by [OTHER AGENT]

## Reference knowledge
MANDATORY — read in full before starting: references/finding-schema.md (required for ALL agents)

Additional reference — load EXACTLY ONE of the following based on your dimension, do NOT load multiple:
- correctness agent → references/language-playbooks.md (correctness sections only)
- security agent → references/security-playbook.md
- performance agent → references/language-playbooks.md (performance sections only)
- design agent → references/triage.md
- tests agent → none (use this prompt only)
- style agent → none (use this prompt only)

## What to flag
Only findings you can accompany with a CONCRETE failure scenario: "input X → behavior Y → failure Z". If you cannot describe the failure scenario with a specific input, DO NOT flag it. Pattern-matching without a failure scenario is a false positive generator.

## Hard drops (never flag)
- Style violations a formatter catches
- Unused imports, unused variables (linter catches these)
- Subjective naming preferences
- Findings on test files unless the test itself is broken
- Findings where the code has a comment explaining it's intentional

## Output format
Write a SINGLE JSON file to: .audit/findings-raw/[dimension].json

The file must be: {"agent": "...", "what_i_checked": "...", "findings": [...]}

Every finding in the array must follow the schema in references/finding-schema.md. No exceptions. Missing fields will cause the finding to be dropped at synthesis.

## Confidence
Score each finding 0.0-1.0 on your OWN confidence that this is a real issue. Do NOT pad confidence to "make the finding stick" — the orchestrator caps anything below 0.60 as a question, and the whole audit report is judged on signal-to-noise.

## Null result
If you find zero issues, STILL write the file with an empty findings array, but fill "what_i_checked" with a detailed description of what you examined, what patterns you searched for, and why you believe the code is clean. Silent non-findings are indistinguishable from search failures.

## When done
Write the file, report "done", end your turn. Do NOT summarize findings in your return message — the orchestrator reads the file, not your message.
```

## Facts Not Opinions Between Waves

Every agent scores severity and confidence INDEPENDENTLY. When findings are merged at Phase 2, the orchestrator uses `max(severity) + corroboration_bonus` — if two agents independently arrive at the same finding, that's evidence, not noise.

**Never pass a Wave 1 agent's classification into a Wave 2 agent's prompt.** If you tell the security agent "correctness agent thinks this is critical", the security agent will anchor on it. Let each agent form its own view.

## Dedup Rules (in order, applied at Phase 2)

1. **Schema validation** — drop anything missing required fields. No exceptions. If you loosen this, the whole pipeline degrades.

2. **Exact-location merge** — `(file, line_range overlap)` → single finding at max severity. Merge body fields to preserve both agents' perspective. Increment `agent_count`.

3. **Pattern merge (Rule of Three)** — if ≥3 findings share the same `category` + similar `subject` pattern across different files, collapse into one pattern-level finding. Body lists all locations. `pattern_count` = N.

4. **Tool-overlap drop** — if a configured linter/type-checker/formatter would already flag this, drop it. The tool has higher recall than an LLM at pattern detection. Do not duplicate tool output in audit findings.

5. **Confidence gating**:
   - `confidence >= 0.85` — keep as-is
   - `0.60 <= confidence < 0.85` — downgrade severity one tier
   - `confidence < 0.60` — relabel as `question`, `blocking: false`, never eligible for auto-fix

6. **Access control cap** — any finding in `category: security` touching auth/permissions/access control is forcibly capped at `confidence = 0.75, label: suggestion, fix_eligibility: review-required`. No matter what the agent said. Rationale: SAST on access control has inherently high false-positive rates because middleware and infrastructure-level checks can't be traced from source alone.

7. **Failure scenario enforcement** — any finding without a concrete `failure_scenario` field is capped at `confidence = 0.60` and relabeled `question`. This is the single highest-ROI rule for reducing noise.

8. **Budget enforcement** — rank remaining findings by `severity_weight × confidence` where critical=4, major=3, minor=2, nitpick=1. Keep the top-N per size tier. Critical findings and live-secret findings exceed the budget (always shown).

9. **Blast radius tagging** — tag each finding `local` (1 file), `module` (2-5 files), `cross-cutting` (6+ files or architectural). Only `local` is eligible for auto-fix.

## Failure Modes of Parallel Audits

### FM-1: Duplicate findings (scope overlap)
**Why**: Scope defined only by concern type. Security AND performance agents both scan `parseUser()` and both flag the same N+1 query.
**Fix**: Scope by dimension + explicit "do NOT cover X" directive in each prompt. Then Phase 2 exact-location merge catches the rest.

### FM-2: Confident-wrong hallucinations
**Why**: Agent pattern-matches without full context — sees `db.query("SELECT ... WHERE id = " + userId)` and flags SQL injection, missing that `userId` is type-coerced to int upstream.
**Fix**: Mandatory `failure_scenario` field. If the agent can't construct "specific input → specific failure", it's not a finding. At Phase 2, missing failure scenarios force confidence below 0.60.

### FM-3: Nitpick overwhelm
**Why**: 6 agents each find 30 issues. Merged = 180. User reads top 10, gives up.
**Fix**: Hard budget cap at Phase 2. Agents find everything; orchestrator picks top-N by severity × confidence. Dropped items go to backlog, not trash.

### FM-4: Scope creep (audit becomes rewrite)
**Why**: No blast-radius ceiling in agent instructions. Agent concludes "this module needs to be restructured."
**Fix**: Blast radius tagging. `cross-cutting` findings are presented as discussion items, never as proposed fixes.

### FM-5: Context blindness (breaking intentional code)
**Why**: Agent flags `catch (e) {}` as missing error handling. Code is fire-and-forget telemetry where swallowing is intentional.
**Fix**: Honor `// audit-ignore`, `# noqa`, `//nolint` comments. Flag findings touching code with explanatory comments as `context_flag: true` — human review required.

### FM-6: Fix conflicts on shared files
**Why**: Fix A adds a null check at line 42; Fix B restructures the function. When applied, B's patch no longer applies.
**Fix**: Fixes are SERIALIZED. One commit per fix. Tests before and after. Revert on failure. Smallest blast-radius first.

### FM-7: Silent agent failure
**Why**: An agent hits a token limit or errors out. Orchestrator doesn't notice. Coverage silently reduced.
**Fix**: After launching agents, wait for all to complete. Validate every expected output file exists AND has at least 20 lines of JSON AND contains a `what_i_checked` field. If any missing, re-run that specific agent.

## Scanner / Fixer / Verifier Context Isolation

A detection agent that also applies its own fixes cannot review its own work — confirmation bias makes it ignore its own noise.

- **Phase 1**: detection agents (6 in parallel)
- **Phase 4**: fix-planning agents (one per approved finding, fresh context, sees ONLY the finding + target file + fix-safety.md)
- **Phase 7**: verification agent (fresh context, sees findings list + applied-fixes log + changed files)

Never let the same context do two of these roles. This discipline prevents the majority of "agent broke working code" failures.

## Conflict Resolution Between Agents

If two agents contradict each other on the same location (one says "this is a bug", one says "this is intentional"):

1. Browser/runtime evidence beats static analysis.
2. Multiple agents agreeing beats single agent.
3. Specific evidence (file:line, concrete input) beats general assessment.
4. Tie → surface as "Conflicting Evidence" with BOTH agents' perspectives to the user. Do not silently resolve.

## Budget Formula

| Codebase size | Max findings | Grouping |
|---------------|--------------|----------|
| <5k LOC | 10 | single list |
| 5k-50k LOC | 15 | local / module / cross-cutting |
| 50k-500k LOC | 20 | same + per-subsystem |
| >500k LOC | 25 per subsystem | audit one subsystem per run |

Dropped findings go to `findings-backlog.json` — they are NOT discarded. User can recall with "show backlog".
