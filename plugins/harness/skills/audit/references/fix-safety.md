---
name: audit-fix-safety
description: Safe-refactoring decision tree, auto-fix precondition stack, and refactorings that LOOK safe but break code. Load before Phase 4 fix planning and Phase 6 apply.
---

# Fix Safety — What to Auto-Fix, What to Propose, What to Never Touch

**Refactoring is behavior-preserving. Every automated fix must leave observable behavior identical.** The main failure mode is not the refactoring itself — it's the missing preconditions: no tests, implicit side effects, dynamic dispatch, or language-specific coercions.

**Discipline**: one refactoring, one commit, tests green before and after.

## The Auto-Fix Precondition Stack

A fix qualifies for `auto-fix` only if ALL of these hold. Missing any → propose-only.

1. **Confidence ≥ 0.85** (from Phase 2 gating)
2. **Blast radius = `local`** (single file)
3. **Semantic-preserving transformation** (from the safe list below)
4. **Mutation score > 70% on the module OR (tests exist AND user explicitly opted in)**
5. **NOT in auth / payments / PII / data-deletion code**
6. **NOT touching a public API / exported symbol**
7. **NOT in code with an explanatory comment suggesting intentionality**
8. **NOT affected by any other approved finding in the same file** (serialization constraint)

If ANY fails, downgrade to `review-required` at minimum, or `discussion` for cross-cutting.

## Safe-to-Automate Refactorings (when preconditions hold)

### LSP-based Rename (Variable / Function / Private Method)
**Safe when**: IDE/LSP performs the rename via AST (not grep/sed), no dynamic dispatch (`getattr`, `eval`, reflection), not a public API.
**Auto-fix verdict**: Yes, if private. Propose-only if public.
**NEVER use grep/sed for rename** — it misses string references, reflection, dynamic dispatch.

### Extract Variable (Introduce Explaining Variable)
**Safe when**: The expression has NO side effects (no function calls that mutate state, no I/O).
**Auto-fix verdict**: Yes, for pure expressions. Flag for review if any function call is in the expression.

### Extract Function
**Safe when**: No implicit shared mutable state, all variables used in the block are passed explicitly or genuinely local, single entry/single exit (no `return`/`break`/`continue` altering outer scope).
**Auto-fix verdict**: Yes, when IDE refactoring confirms clean variable scope.

### Inline Variable (single-assignment, single-use)
**Safe when**: Variable is assigned once AND used once, the expression has no side effects that must happen exactly once.
**Auto-fix verdict**: Yes.

### Inline Function
**Safe when**: Called from exactly one place OR all callers can be updated atomically, no recursion, no overriding subclasses depending on it as a dispatch point.
**Auto-fix verdict**: Yes, for private/internal functions with one caller.

### Replace Nested Conditional with Guard Clauses
**Safe when**: Each guard clause returns/throws immediately, no `try/finally` or resource cleanup that depends on reaching end of function (use `with`/RAII instead).
**Auto-fix verdict**: Yes, after verifying no `try/finally` wraps the conditionals.

### Remove Dead Code
**Safe when**: Code coverage confirms path is never executed (100% line coverage OR mutation testing shows removing it doesn't kill any tests), no `#ifdef`/conditional compilation, no reflection that could invoke it by name.
**Auto-fix verdict**: Yes, only with coverage evidence. Flag for human review if coverage < 80% on the module.

### Slide Statements (reorder locals with no dependency)
**Safe when**: No data dependency, no exception side effects.
**Auto-fix verdict**: Yes, within pure initialization blocks.

## Risky Refactorings — Propose-Only

### Move Function / Move Method
**Risk**: Changes visibility, changes `this`/`self`, may alter method resolution order, dynamic-language callers may duck-type against the original location.
**Verdict**: Propose-only. The fix agent can sketch the move, the user confirms.

### Replace Conditional with Polymorphism
**Risk**: Changes dispatch mechanism. The polymorphic object is chosen at construction time; the original conditional was evaluated at call time. Subtle semantic difference when the tested condition is mutable state.
**Verdict**: **Human-only**. This is a design decision, not mechanical.

### Introduce Parameter Object
**Risk**: Breaks all callers immediately. In dynamic languages, positional-by-convention calls become object-based.
**Verdict**: Propose-only with diff showing all affected callers.

### Change Function Declaration
**Risk**: Breaks callers in proportion to visibility. Any public API change is a contract change.
**Verdict**: Auto-fix only for private with full call-graph confidence. Propose-only for public.

### Replace Loop with Functional Pipeline
**Risk**: Laziness changes exception semantics. `map`/`filter` are lazy in many languages — `list(map(...))` fails fast on first exception; the loop version may have been intentionally tolerant. `reduce` is not a drop-in for loops with early exit.
**Verdict**: Propose-only. Agent must verify no side effects in the loop body.

### Decompose Conditional (split complex condition)
**Risk**: If the condition has side effects (function calls with mutation), short-circuit evaluation order matters.
**Verdict**: Auto-fix only for pure boolean conditions.

## Refactorings That LOOK Safe But Break Code

These are the landmines. If a fix plan proposes any of these, the fix agent MUST flag the specific risk and require Gate 2 approval.

### `==` to `===` in JavaScript
```js
if (value == "")     // passes for 0, false, null, undefined (coerced)
if (value === "")    // passes only for ""

null == undefined    // true
null === undefined   // false
```
APIs that intentionally return either will break. This is NOT a safe mechanical refactor.

### Adding Type Annotations in Python
```python
def process(stream): ...                # accepts any duck-typed object with .read()
def process(stream: IO[str]): ...        # mypy enforces, pydantic validates at runtime
```
`pydantic` and similar frameworks **validate at runtime** based on annotations — adding an annotation can cause a runtime validation error on previously-valid input. Adding `from __future__ import annotations` changes when annotations are evaluated.

### Replacing Loops with `map`/`filter` in Python
```python
for item in items:
    try: process(item)
    except: pass       # intentionally tolerant

results = list(map(process, items))  # fails fast on first exception
```
`map`/`filter` are lazy; `list()` materialization changes fail semantics.

### Converting Callbacks to async/await in Node.js
```js
fs.readFile(path, (err, data) => {
  if (err) return;       // silent in callback mode
  process(data);
});

const data = await fs.promises.readFile(path);  // unhandled rejection crashes Node 15+
```
Unhandled promise rejections terminate the process in Node 15+. The error propagation semantics are fundamentally different.

### Removing "Unused" Imports in Python
```python
import sqlalchemy             # registers dialect
import django.contrib.staticfiles  # registers app
```
Side-effectful imports: many frameworks use import as a registration mechanism. Static analysis cannot distinguish these from truly unused imports. **Before removing any import**, check if the module has `__init__.py` side effects.

### Auto-Formatting Entire Files
- Destroys `git blame` — every line shows the formatter commit
- Creates enormous diffs that obscure the actual refactoring in code review
- May interact badly with mixed-indentation files in indentation-significant languages (Python, YAML)

**Rule**: Format only lines changed by the refactoring, or format in a separate standalone commit with message `chore: format` and NO logic changes.

### Inlining a Constant Used in Many Places
```ts
export const MAX_RETRIES = 3;  // named, tree-shakeable
// ... vs literal 3 appearing in 40 call sites
```
No runtime change, but: bundle size may increase, named constant served as documentation. This is a regression, not an improvement.

### Ruff UP040 Autofix (Python)
Ruff rewrites `Url: TypeAlias = str` to `type Url = str` automatically. The new `type` statement creates a `TypeAliasType` object, NOT a type — `isinstance(x, Url)` raises TypeError, as does using `Url` as a base class. If the codebase uses type aliases in isinstance or subclass checks, the autofix silently breaks runtime code.

**Rule**: If Phase 1 detection proposes applying UP040, the fix agent must grep for `isinstance(.*Url)`, `issubclass(.*Url)`, `class .*\(Url\)` first. If any matches, flag as "auto-fix blocked — runtime usage".

## Kent Beck's Tidyings vs Refactorings

From *Tidy First?* (2023). Tidyings are cosmetic; refactorings change structure.

| Tidying | Refactoring |
|---------|-------------|
| Rename local variable | Rename public API |
| Extract explaining variable | Extract class |
| Delete commented-out code | Move function between modules |
| Reorder function parameters (private) | Change function declaration (public) |
| Normalize blank lines | Introduce parameter object |

**Why they must be separate commits**:
1. Mixed with logic changes, code review becomes impossible
2. Tidyings are reviewed differently (fast, low scrutiny) vs structural changes
3. Git bisect needs clean commits — mixing ambiguates which change caused a regression

**Commit message discipline**:
- `refactor(audit): <structural change> [audit/<id>]` — behavior-preserving structural change
- `chore(audit): <tidying> [audit/<id>]` — cosmetic, no structural change
- `fix(audit): <bug fix> [audit/<id>]` — behavior change (rare for audit — mostly propose)

## Mikado Method (for discussion items only — never auto-applied)

For large refactorings, the Mikado Method prevents a "mid-refactor broken" state:

1. Set the goal. Attempt it naively.
2. If tests pass: commit. Done.
3. If tests fail: **revert immediately**. Do NOT keep a broken state. Record the prerequisite.
4. Recurse: apply Mikado to the prerequisite.
5. Once prerequisite is fixed and committed, reattempt the original goal.

The Mikado Graph is a DAG — leaves are the first things you implement. At every commit, the codebase is green.

Audit's `discussion` findings should be presented with a Mikado sketch ("to achieve X, you'll likely need to first do Y then Z"), not a single patch. The user drives the structural work.

## Character / Approval Tests (preconditions for auto-fix)

When there are no tests, Feathers' **characterization tests** capture current behavior — including bugs — as the baseline:

1. Run the code with representative inputs
2. Capture outputs (return values, DB state, HTTP responses)
3. Write tests that assert those exact outputs
4. THEN refactor. Failures mean semantic change
5. SEPARATELY fix the bugs — that's a behavior change

**Coverage requirement for auto-fix confidence**:
- Mutation testing (Stryker for JS, mutmut for Python, PITest for Java) verifies tests detect changes
- 80% line coverage + 40% mutation score → NOT sufficient for auto-fix
- Minimum for auto-fix: mutation score > 70% on the affected module OR user explicit opt-in

## Decision Tree (the algorithm for Phase 4)

```
For each approved finding:

  Does the target module have mutation score > 70%?
  ├─ NO  →
  │   Does it have line coverage > 80% AND user opted in to "fix without mutation data"?
  │   ├─ NO  →  HUMAN-ONLY. Flag: "no safety net — build characterization tests first."
  │   └─ YES →  continue below with caveat
  │
  Does the fix touch a public API / exported symbol?
  ├─ YES →  PROPOSE-ONLY. Show diff of affected callers.
  └─ NO  →
      Does the fix involve dynamic dispatch, reflection, string-based lookup,
      or framework magic (decorators, metaclasses, routes)?
      ├─ YES →  PROPOSE-ONLY.
      └─ NO  →
          Is the fix in auth / payments / PII / data-deletion code?
          ├─ YES →  PROPOSE-ONLY, no auto-fix path regardless.
          └─ NO  →
              Is it a tidying (cosmetic, no structural change)?
              ├─ YES →  AUTO-FIX. Separate commit, message: "chore(audit): ...".
              └─ NO  →
                  Is it one of the safe-to-automate refactorings?
                  (LSP rename, extract var, extract fn, inline var,
                  guard clauses, remove dead code)
                  ├─ YES →  AUTO-FIX. One commit, tests before/after.
                  └─ NO  →  PROPOSE-ONLY.
```

## Commit + Revert Protocol (Phase 6)

**Golden rule: test BEFORE committing, so revert is always a discard of uncommitted changes, not a reset of history.**

```bash
# 1. Verify clean state BEFORE each fix
git status --porcelain  # must be empty. If not — STOP, there are unrelated changes
                        # or a prior fix left the tree dirty

# 2. Run tests pre-fix to establish baseline
pytest || npm test || cargo test || go test
# Record pass/fail. If anything is already red, STOP — don't fix on a red tree

# 3. Apply the fix (Edit tool, never sed/awk). Fix is NOT committed yet.
# ...

# 4. Run tests post-fix
pytest || npm test || cargo test || go test
if [ $? -ne 0 ]; then
  # A previously-passing test is now failing → discard the uncommitted fix
  git checkout -- <specific-files-changed-by-fix>
  # (alternatively: git restore <files> on git 2.23+)
  # Mark finding as "fix attempt failed", escalate to user, move on
  exit
fi

# 5. Tests pass → commit
git add <specific-files>
git commit -m "refactor(audit): <subject> [audit/<finding-id>]"
```

**Critical distinction**:
- `git checkout -- <file>` / `git restore <file>` → discards UNCOMMITTED changes in working tree (use in the protocol above)
- `git reset --hard HEAD` → discards UNCOMMITTED changes, same effect but more dangerous (resets whole tree, not just listed files)
- `git reset --hard HEAD~1` → **REMOVES** the last commit (dangerous — never use in the protocol, only if a fix was already committed and you must undo)
- `git revert HEAD --no-edit` → creates a new revert commit (safest option if the fix was already committed and pushed)

**When to use which revert**:
- Fix failed mid-application, before commit → `git checkout -- <files>` or `git restore <files>`
- Fix was committed, regression found in the SAME audit session → `git reset --hard HEAD~1` (safe, local commit not pushed)
- Fix was committed AND pushed (unusual — the skill should never push, but if the user did) → `git revert HEAD --no-edit` (preserves history)

**Two-attempt rule**: if a fix fails twice, stop. Surface as "requires human review" and move on to the next finding. Do not loop.

**Smallest blast radius first**: order the fix queue by blast radius ascending. This minimizes the chance that a later fix invalidates an earlier one's patch location.
