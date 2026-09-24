---
name: audit-finding-schema
description: JSON schema every detection agent MUST emit, markdown report format for Gate 1, and the null-result template for clean audits. Load before launching Phase 1 agents.
---

# Finding Schema and Report Formats

## JSON Schema — Every Agent Writes This

Every detection agent in Phase 1 writes a single JSON file to `.audit/findings-raw/<dimension>.json` with this structure. The orchestrator validates schema compliance at Phase 2 and drops non-conforming findings.

```json
{
  "agent": "correctness",
  "what_i_checked": "Scanned src/auth/, src/api/ and src/core/ for null paths, error handling, and exception contracts. Checked all 27 functions in hot-spot files from recon. Verified parseInt/Number.parseInt usage in 6 call sites.",
  "findings": [
    {
      "finding_id": "correctness-001",
      "file": "src/auth/session.ts",
      "line_start": 42,
      "line_end": 44,
      "severity": "critical",
      "confidence": 0.91,
      "category": "correctness",
      "blast_radius": "local",
      "label": "issue",
      "blocking": true,
      "subject": "Missing NaN guard on parseInt(id) allows malformed input to reach DB",
      "body": "The call at line 42 coerces the URL parameter to integer without checking for NaN. A non-numeric value produces NaN, which passes the truthy check at line 44, and the malformed value reaches the database query at line 67.",
      "failure_scenario": "GET /users/abc → parseInt('abc') = NaN → NaN > 0 is false but NaN !== null is true → DB query receives NaN as user ID → ORM either errors with cryptic type mismatch or returns the first user depending on dialect",
      "fix_sketch": "Add `if (Number.isNaN(id)) throw new BadRequestError('Invalid user ID');` after line 42",
      "fix_eligibility": "auto-fix",
      "auto_fix_blocked_reason": null,
      "pattern_count": 1,
      "pattern_locations": [],
      "context_flag": false
    }
  ]
}
```

## Required Fields (drop at Phase 2 if missing)

| Field | Type | Purpose |
|-------|------|---------|
| `finding_id` | string | Stable ID for dropping, approving, bisecting |
| `file` | string | Exact path (no location = drop) |
| `line_start`, `line_end` | int | Line range. Validated against actual file at Phase 2 |
| `severity` | enum | `critical`, `major`, `minor`, `nitpick`, `info` |
| `confidence` | float [0,1] | Agent's self-scored confidence |
| `category` | enum | `correctness`, `security`, `performance`, `design`, `tests`, `style` |
| `blast_radius` | enum | `local` (1 file), `module` (2-5), `cross-cutting` (6+) |
| `label` | enum | `issue`, `suggestion`, `question`, `thought` |
| `blocking` | bool | Whether this prevents ship/merge |
| `subject` | string | One-line summary for scan view |
| `body` | string | Full explanation with WHY, no "you" language |
| `failure_scenario` | string | **Concrete input → behavior → failure chain. Required or confidence capped at 0.60.** |
| `fix_eligibility` | enum | `auto-fix`, `review-required`, `discussion` |
| `pattern_count` | int | 1 unless this represents multiple instances |
| `pattern_locations` | array | Other locations if pattern_count > 1 |
| `context_flag` | bool | True if there's an explanatory comment suggesting intentional code |

## Optional Fields

| Field | Purpose |
|-------|---------|
| `fix_sketch` | Minimal proposed fix (direction, not full code) |
| `auto_fix_blocked_reason` | Explains why auto-fix is blocked (non-null when fix_eligibility ≠ auto-fix) |

## Severity Definitions

- **critical** — correctness bug with reachable failure path, security vulnerability with exploitable path, data loss risk. Blocks ship.
- **major** — design debt that actively compounds, missing test coverage on critical path, performance issue affecting user-visible latency. Should fix.
- **minor** — localized smell, style beyond formatter, low-impact performance. Fix when touching adjacent code.
- **nitpick** — subjective preference, cosmetic. Usually dropped at Phase 2.
- **info** — observation for context, not actionable. Rarely survives Phase 2.

## Confidence Tiers

- **≥ 0.85 (HIGH)** — kept at declared severity. Auto-fix eligible if other preconditions hold.
- **0.60 - 0.85 (MEDIUM)** — kept but severity downgraded one tier, `blocking: false`.
- **< 0.60 (LOW)** — relabeled as `question`, never auto-fix, often dropped at Phase 2 unless user opts in to see questions.

## `failure_scenario` — the most important field

This is the field that separates real findings from hallucinations. Every agent is instructed to include a concrete failure path:

**Good**: "GET `/users/abc` → `parseInt('abc')` = NaN → `NaN > 0` is false but `NaN !== null` is true → DB query receives NaN"

**Bad**: "This might allow invalid input" (no failure chain)

**Bad**: "Potentially vulnerable to SQL injection" (no concrete input)

At Phase 2, missing or vague `failure_scenario` → confidence forced to 0.60 max, label forced to `question`. This single rule cuts noise by the largest margin.

## Markdown Report Format (Gate 1)

The orchestrator emits this format from `findings-consolidated.json` at Phase 3. Present to the user verbatim.

```markdown
# Audit Report — <path>

**Generated**: <timestamp>
**Size tier**: <small|medium|large|huge> (<N> LOC)
**Agents run**: <list>
**Findings**: <raw-count> raw → <after-dedup> after dedup → **<shown>** shown (<backlog-count> in backlog)

---

## Critical — Action Required (<N>)

### [C-1] Missing NaN guard allows malformed IDs into DB query
**Location**: `src/auth/session.ts:42-44`
**Confidence**: 91% | **Fix scope**: local (1 file) | **Eligibility**: auto-fix
**Failure scenario**: `GET /users/abc` → `parseInt('abc')` = NaN → passes truthy check → DB receives NaN
**Proposed fix**: Add NaN guard after parseInt call
*Found by: correctness-agent (confidence 0.91) + security-agent (confidence 0.83) — corroborated*

---

## Major — Should Fix (<N>)

### [M-1] `for-await-of` over array runs promises serially (performance)
**Location**: `src/api/users.ts:87-91`
**Confidence**: 88% | **Fix scope**: local | **Eligibility**: auto-fix
**Failure scenario**: 50 user IDs → 50 DB calls run serially → 5s total latency → p99 timeout in prod
**Proposed fix**: Replace with `Promise.all(ids.map(fetchUser))`
*Found by: performance-agent*

---

## Cross-Cutting — Requires Discussion (<N>)
*These findings cannot be fixed with a localized change. Each requires a design conversation.*

### [X-1] Pagination missing on all list endpoints
**Files**: `src/api/users.ts`, `src/api/products.ts`, `src/api/orders.ts`
**Confidence**: 82% | **Blast radius**: module | **Eligibility**: discussion
**Failure scenario**: `GET /api/users` on 100k-user tenant returns full dataset → 20MB JSON, 30s render time
*Found by: design-agent, performance-agent — corroborated*

---

## Backlog — <N> minor/nitpick findings not shown
*Say "show backlog" to see them. Each is ≤ minor severity or < 0.60 confidence.*

---

## What Was Checked

- **correctness-agent**: scanned 27 files in hot-spots, verified all error paths, parseInt/parseFloat usage, exception contracts. Found 4 issues.
- **security-agent**: gitleaks full history scan, npm audit --omit=dev, semgrep p/javascript, manual SSRF grep on 12 fetch call sites. Found 2 issues.
- **performance-agent**: scanned hot-spots for N+1 patterns, async blocking, Promise.all vs for-await-of, bundle barrel files. Found 3 issues.
- **design-agent**: Fowler smell catalog on top-15 hot-spot files, temporal coupling analysis from recon. Found 2 issues.
- **tests-agent**: coverage gaps on hot-spot files, fixture brittleness, assertion-free tests. Found 1 issue.
- **style-agent**: ran formatter check only — 0 unique findings (all would be caught by `prettier --check`).

---

**Which findings should I address?**
Reply with: `all critical`, `1,3,5`, `none`, `show backlog`, or `cancel`.
```

## Null Result Format (clean audit = success)

When zero findings survive Phase 2 filters, present this. A clean audit is a positive result — do NOT treat silence or an empty report as valid output.

```markdown
# Audit Report — <path>

**Generated**: <timestamp>
**Size tier**: <tier> (<N> LOC)
**Result**: ✓ Clean — no actionable findings

## Summary

All 6 audit dimensions completed. No findings survived filtering at `severity × confidence` thresholds. This means either:
- The codebase has no high-signal debt findings at this scope
- All candidate findings overlapped with existing tooling (linter/type-checker) and were dropped per the tool-overlap rule
- All candidate findings lacked concrete failure scenarios and were dropped per the confidence gate

## What Was Checked

- **correctness-agent**: <what_i_checked from agent>
- **security-agent**: <what_i_checked>
- **performance-agent**: <what_i_checked>
- **design-agent**: <what_i_checked>
- **tests-agent**: <what_i_checked>
- **style-agent**: <what_i_checked>

## What Was NOT Audited

- Profiling / runtime performance (requires execution, out of scope for static audit)
- End-to-end security testing (requires runtime)
- Architectural alignment with product requirements (requires business context)
- Accessibility / UX (out of scope — use `/qa` for browser-level checks)

## Recommendations for Next Steps

- If you're about to ship: run `/pr-reviewer` on the PR instead of re-running `/audit`.
- If you suspect runtime issues: run language-specific profilers (py-spy, clinic.js, pprof).
- If new features are coming: rerun `/audit` after the feature merges.

Backlog contains <N> dropped findings (low-severity or low-confidence). Say "show backlog" if you want to see them anyway.
```

## "Show Backlog" Response

When the user says "show backlog", list dropped findings in simpler form (no `failure_scenario` required since they were already filtered):

```markdown
## Backlog (<N> findings)

**Minor** (<N>)
- src/utils/format.ts:12 — Magic number `86400` could be named constant (confidence 0.72, style)
- src/api/users.ts:200 — Long function (80 lines, single concept) — Ousterhout depth OK, not a smell (confidence 0.65, design)
...

**Nitpick** (<N>)
- Long parameter list (5 args) — not a pattern, single occurrence (confidence 0.58, design)
...

Want to promote any of these to the findings list? Reply with their IDs or `none`.
```
