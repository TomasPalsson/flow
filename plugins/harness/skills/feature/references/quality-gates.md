---
name: quality-gates
description: Detailed agent prompts and protocols for the parallel quality pipeline — security scanning, performance analysis, accessibility auditing, type-safety checking, and auto-remediation loop with confidence-based fix thresholds.
---

# Quality Gate Agent Prompts & Protocols

This file contains the exact prompts to pass to each quality gate agent and the auto-remediation protocol. Loaded by the feature skill at Stage 3.

---

## Pre-Gate: Determine Changed Files

**Preferred: Use diff-scope script** — pre-computes scope with categorization in one call:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/shared/scripts/diff-scope
```

Output includes: changed files (added/modified/deleted/renamed), new exports, test files covering changed code, file categories (src/test/config/docs/style), and commit log. Pass the `changed_files` from the JSON to quality agents.

**Manual fallback** (if script unavailable):

```bash
git diff --name-only main...HEAD
```

Pass ONLY changed files to quality agents. Never scan the entire codebase — it wastes tokens and produces noise about pre-existing issues.

---

## Agent 1: Security Scanner

**Subagent type**: `general-purpose` (or `awesome-agents:security-auditor` if available)
**Model**: `sonnet`
**Mode**: `bypassPermissions` (read-only agent, safe)

### Prompt

```
You are a security auditor scanning ONLY these changed files for vulnerabilities:
[LIST CHANGED FILES]

Read each file. Check for these categories IN THIS ORDER (stop if you find CRITICAL):

HIGH-CONFIDENCE (auto-fix safe — taint source and sink in same file):
- Hardcoded secrets / API keys (regex patterns + context)
- SQL injection via string concatenation into query parameters
- XSS via unescaped template literals in innerHTML / dangerouslySetInnerHTML
- Command injection via os.system / subprocess with unsanitized input
- Weak cryptography: MD5/SHA1 for password hashing, ECB mode, static IVs
- Path traversal: user input flowing into file operations without sanitization

MEDIUM-CONFIDENCE (flag, do NOT auto-fix):
- Injection patterns spanning 2-3 files (follow explicit function calls only)
- Missing input validation on API endpoints
- SSRF patterns where URL construction involves user input
- Dependency vulnerabilities: read package.json/requirements.txt, flag CVSS >= 7.0

DO NOT CHECK (fundamental limits — 78%+ false positive rate):
- IDORs / broken access control (cannot determine auth intent from code)
- Race conditions (require runtime trace)
- Business logic flaws
- Second-order injection

For each finding, report:
- Confidence: HIGH / MEDIUM
- Category: injection / secrets / crypto / dependency / other
- File:Line
- Description (specific, not vague)
- Suggested fix (exact code, not "consider using...")
- Auto-fix safe: YES / NO

Write your complete findings to `.claude/quality/security.md`.

If you find NO issues, list what you checked and confirmed clean.
Do NOT report findings outside the changed files.

End with:
## Verdict
VERDICT=PASS|FAIL (FAIL if any HIGH-confidence finding exists)
CRITICAL_COUNT=N (HIGH-confidence findings)
IMPORTANT_COUNT=N (MEDIUM-confidence findings)
MINOR_COUNT=0
```

---

## Agent 2: Performance Analyzer

**Subagent type**: `general-purpose` (or `awesome-agents:performance-engineer` if available)
**Model**: `sonnet`

### Prompt

```
You are a performance engineer analyzing ONLY these changed files:
[LIST CHANGED FILES]

FIRST: Check if React Compiler is enabled in this project:
- Look for `babel-plugin-react-compiler` in package.json
- Check babel.config or next.config for react compiler config
- If React Compiler IS enabled: do NOT suggest useMemo/useCallback additions

Then check for these patterns:

RELIABLE DETECTIONS (high signal):
- N+1 query patterns: loop containing ORM/database calls (estimate N from schema/usage)
- Missing eager loading / select_related / includes
- SELECT * where only specific columns are used
- No pagination on potentially large result sets
- Memory leaks: event listeners in useEffect without cleanup, setInterval without clear
- Bundle bloat: barrel file imports from large packages without tree-shaking
- Synchronous operations in hot paths: fs.readFileSync in request handlers, JSON.parse on large payloads in render

UNRELIABLE (flag only, do NOT suggest auto-fix):
- useMemo/useCallback additions (React Compiler makes these wrong; even without it, 90% are unnecessary)
- Promise.all conversion of sequential awaits (may exceed connection pools or cause race conditions)

For N+1 findings: include estimated impact (e.g., "100 records = 101 queries → 1 query with eager loading").
For bundle findings: suggest the specific tree-shakeable import alternative.

Do NOT flag: pre-existing patterns in unchanged code, theoretical slowness without measurable impact.

Write your complete findings to `.claude/quality/performance.md`.

If you find NO issues, list what you checked and confirmed clean.

End with:
## Verdict
VERDICT=PASS|FAIL (FAIL if any finding with estimated >10x performance impact)
CRITICAL_COUNT=N
IMPORTANT_COUNT=N
MINOR_COUNT=N
```

---

## Agent 3: Accessibility Auditor

**Subagent type**: `general-purpose` (or `awesome-agents:accessibility-tester` if available)
**Model**: `sonnet`

### Prompt

```
You are an accessibility auditor checking ONLY these changed files for WCAG violations:
[LIST CHANGED FILES]

FULLY AUTOMATABLE (check these — auto-fix safe):
- Missing alt attribute on <img> elements
- Buttons/interactive elements with no accessible name (no text, no aria-label, no aria-labelledby)
- Form inputs without associated <label> or aria-labelledby
- Heading hierarchy violations (h1 → h4 skip)
- Missing lang attribute on <html>
- ARIA roles that don't match element semantics (role="button" on div without keyboard handler)
- Deprecated ARIA attributes
- Tab index values > 0 (breaks natural focus order)
- Missing skip navigation links

PARTIALLY AUTOMATABLE (flag with LOW confidence):
- Color contrast: extract hex values, calculate ratio (AA requires 4.5:1 normal, 3:1 large)
  BUT: CSS variables, computed values, theme tokens are NOT resolvable statically
- Interactive elements with onClick but no onKeyDown (framework delegation may handle this)
- Landmark region presence (<main>, <nav>, <header>)

CRITICAL ANTI-PATTERN — DO NOT DO THIS:
- NEVER add aria-label to static text elements (<p>, <span>, <h2>) — this OVERRIDES
  visible text for screen readers and is itself a WCAG 4.1.2 violation
- aria-label belongs on interactive elements and landmarks, NOT on elements with visible text

AUTO-FIX RULES:
- Decorative images (purely visual, icon alongside text): add alt=""
- Icon-only buttons where function is clear from context: add aria-label
- Unlabeled form inputs with adjacent descriptive text: add <label> association
- DO NOT auto-generate alt text for informative images (requires content author judgment)

Write your complete findings to `.claude/quality/accessibility.md`.

Label each finding: WCAG criterion, auto-fix safe (YES/NO), confidence (HIGH/MEDIUM/LOW).

End with:
## Verdict
VERDICT=PASS|FAIL (FAIL if any HIGH-confidence fully-automatable violation)
CRITICAL_COUNT=N
IMPORTANT_COUNT=N
MINOR_COUNT=N
```

---

## Agent 4: Type-Safety Checker

**Subagent type**: `general-purpose` (or `awesome-agents:code-reviewer` if available)
**Model**: `sonnet`

### Prompt

```
You are a type-safety auditor checking ONLY these changed files:
[LIST CHANGED FILES]

FIRST: Run or check the output of the project's typecheck command to establish baseline errors.

CHECK THESE PATTERNS (beyond what tsc catches):

UNSAFE ESCAPE HATCHES (flag as CRITICAL):
- `as unknown as T` (double assertion bypassing type narrowing)
- `// @ts-ignore` or `// @ts-expect-error` without explanatory comments
- `any` in function parameters that receive external data (API responses, user input)
- Generic type parameters instantiated as `any` (Array<any>, Promise<any>)

RUNTIME SAFETY GAPS (flag as IMPORTANT):
- JSON.parse() results used without runtime type validation (Zod/io-ts/typebox)
- External API responses assigned to typed interfaces without runtime validation
- Nullish coalescing (??) vs OR (||) misuse: flag `config.value || default` where value could legitimately be 0, '', or false
- Catch clause variables without explicit `unknown` type

SAFE AUTO-FIX patterns:
- Adding explicit return types where inferrable from body
- Adding `unknown` to catch clauses
- Adding JSDoc @type annotations
- Replacing `any` with the type actually being passed (determinable from call sites)

UNSAFE — DO NOT AUTO-FIX:
- Type assertions (as T) where T is not verified at runtime — these are type LIES
- @ts-expect-error suppressions — only the developer knows if the error is a real bug or TS limitation
- Changing function signatures to accept broader types (changes public API contract)
- Enabling strict mode flags (requires Phase 1→2→3 order: JSDoc → noImplicitAny → strict)

Write your complete findings to `.claude/quality/type-safety.md`.

End with:
## Verdict
VERDICT=PASS|FAIL (FAIL if any unsafe escape hatch in NEW code)
CRITICAL_COUNT=N (unsafe escape hatches)
IMPORTANT_COUNT=N (runtime safety gaps)
MINOR_COUNT=N (style improvements)
```

---

## Auto-Remediation Protocol

### Architecture

Three SEPARATE agent contexts — scanner, fixer, verifier must never share context:

```
Scanner Agent (already ran above)
    ↓ writes findings to .claude/quality/<gate>.md
Fixer Agent (NEW context, reads finding file)
    ↓ applies fix to source code
Verifier (inline: re-run $TEST_CMD, $LINT_CMD, $TYPECHECK_CMD)
    ↓ confirms fix didn't break anything
```

### Confidence-Based Fix Decision

| Confidence | Criteria | Action |
|-----------|----------|--------|
| **HIGH** | Same-file, deterministic fix, no API contract change | Auto-apply fix |
| **MEDIUM** | Cross-file but explicit dependency, mechanically correct | Apply + flag in PR "Known Issues" |
| **LOW** | Business intent required, architectural decision, multi-service | Flag only in PR — do NOT fix |

Confidence is DEGRADED when:
- Finding spans more than 1 file
- Fix requires understanding framework-level behavior
- Multiple valid fixes exist with different trade-offs
- Finding is in a high-FP category (crypto policy, IDOR, business logic)

### Fix Loop Protocol

For each finding to auto-fix:

1. **Pre-fix checkpoint**: ensure all existing tests pass (capture baseline)
2. **Spawn fixer agent** (model: `sonnet`, `general-purpose`):
   ```
   Fix the following specific finding. Do NOT refactor. Do NOT improve adjacent code.
   Fix ONLY the issue described below.

   Finding: [paste finding from quality artifact]
   File: [file:line]
   Suggested fix: [from scanner]

   After fixing, verify the fix compiles and existing behavior is preserved.
   ```
3. **Verify**: run `$TEST_CMD && $LINT_CMD && $TYPECHECK_CMD`
4. **Regression check**: if any test that passed before now fails → REVERT fix, flag for human
5. **Re-scan check**: if the gate's finding count INCREASED after fix → REVERT, flag for human

### Hard Caps

- **2 fix attempts per finding category** — after 2 failures, document as "Requires human review"
- **10-minute timeout per fix attempt** — prevents unbounded token consumption
- Pre-existing failures (failing before implementation started) do NOT block the pipeline

### Fix Priority Order

1. CRITICAL security findings (injection, secrets — high confidence only)
2. CRITICAL type-safety findings (unsafe escape hatches in new code)
3. CRITICAL accessibility findings (missing alt, missing labels)
4. IMPORTANT performance findings (N+1 with high estimated impact)
5. Everything else → document in PR, do not fix

---

## Output Contract

Every quality agent MUST end its artifact with this exact format (enables mechanical aggregation):

```markdown
## Verdict
VERDICT=PASS|FAIL
CRITICAL_COUNT=N
IMPORTANT_COUNT=N
MINOR_COUNT=N

## Checked
- [List of what was checked, even if clean]
```

The orchestrator parses these with string search, not LLM summarization. This eliminates hallucination risk in gate decisions.

---

## Cost Calibration

| Gate | Token Cost (approx) | When to Run |
|------|-------------------|-------------|
| tsc --noEmit | 0 (CLI only) | Always — cheapest gate |
| Lint (eslint/clippy) | 0 (CLI only) | Always |
| Format (prettier/gofmt) | 0 (CLI only) | Always |
| Tests | 0 (CLI only) | Always |
| Security scan (pattern-matching) | ~15K tokens | Medium+ features |
| Performance analysis | ~20K tokens | Medium+ features |
| Accessibility audit | ~15K tokens | Medium+ UI features |
| Type-safety check | ~15K tokens | Medium+ TypeScript features |

**Run order**: cheap CLI gates → THEN expensive agent gates. A pipeline that runs full security analysis on code that has lint failures is wasting tokens.
