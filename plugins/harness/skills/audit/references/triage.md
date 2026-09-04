---
name: audit-triage
description: Triage framework for ranking and filtering audit findings. Fowler tech debt quadrant, hot-spot analysis (Tornhill), P0-P3 tiers, when NOT to refactor. Load before Phase 2 prioritization.
---

# Triage — What to Fix, What to Leave

**The most common audit failure is treating all debt as equal. Most debt should NOT be fixed.**

This reference is loaded at Phase 2 (dedup + prioritize) and at Phase 3 (user gate). The triage framework decides what gets surfaced and what stays in the backlog.

## The Core Formula

```
Priority = (Business Impact × Technical Risk) / Fix Cost
```

- **Business Impact**: how much revenue, velocity, reliability, or compliance risk does this debt create right now?
- **Technical Risk**: probability × severity of failure if left in place
- **Fix Cost**: fully-loaded cost — implementation + testing + coordination + rollout risk

**High-priority**: high impact, high risk, low cost — emergency.
**Leave alone**: low impact, low risk, high cost — NPL-negative. The fix costs more than the problem.

## Hot-Spot Analysis (Tornhill Method) — The Entry Point

Adam Tornhill's core insight: **Complexity is only a problem where there is ALSO high change frequency.**

A beautifully-written, rarely-touched file is low priority. A messy, frequently-changed file is where debt costs real money.

```
              Low churn              High churn
             ┌──────────────────┬──────────────────┐
 Low         │                  │                  │
 complexity  │  OK              │  Active,         │
             │  (leave)         │  healthy         │
             ├──────────────────┼──────────────────┤
 High        │  Frozen debt     │  HOT-SPOT        │
 complexity  │  (leave unless   │  ← AUDIT HERE    │
             │   touching)      │                  │
             └──────────────────┴──────────────────┘
```

**The audit script computes this**: `score = churn × LOC` per file, ranked. The top-N become the Phase 1 focus. Agents audit hot-spots FIRST, low-churn files get only a passing look.

### Temporal Coupling (Tornhill's second insight)

Two files that always change together but have no import relationship are a hidden coupling the static analyzer will miss. Git history reveals this; grep does not.

Recon emits temporal coupling pairs. When Phase 1 agents see a coupling pair, they should investigate BOTH files together — they likely represent a shared concept awaiting extraction.

## Fowler's Tech Debt Quadrant

Classify each finding. The quadrant drives how it's presented and whether it survives prioritization.

|                  | **Reckless**                       | **Prudent**                              |
|------------------|------------------------------------|------------------------------------------|
| **Deliberate**   | "We don't have time for design"    | "Must ship now, fix consequences later"  |
| **Inadvertent**  | "What's layering?"                 | "Now we know how we should have done it" |

Only **Deliberate-Prudent** is Ward Cunningham's original debt metaphor. The other three are different problems — each demands a specific audit response:

- **Deliberate-Prudent** → present at Gate 1 as `major` or `critical` depending on the production impact. These are the findings the team already knows about. Fix if the original "pay back promptly" promise was broken.
- **Reckless-Deliberate** → negligence. Present as `critical` with full failure scenario if production impact is reachable. Skip entirely if impact is absent (negligence on dead code is not debt).
- **Reckless-Inadvertent** → skill gap. Present as `minor` or `major` depending on blast radius, with `body` framed educationally. Always `propose-only` — do not auto-fix, because the pattern likely repeats across the codebase and needs human pattern-level decision.
- **Inadvertent-Prudent** → learning. Usually the biggest category. Do NOT fix reflexively. Rule: if the file is in the hot-spot top-10 AND a specific change is planned that this debt will impede → surface as `major`. Otherwise → drop to `findings-backlog.json` with reason "learning debt, no pending change".

Cunningham himself regretted that the metaphor was appropriated for all kinds of code quality failure. Most "technical debt" in audit reports is not debt at all — it's Inadvertent-Prudent learning that should go to backlog, not to the primary report.

## P0-P3 Prioritization Tiers (industry practice)

Once findings pass dedup and confidence gates, classify by impact tier:

| Tier | Definition | Budget priority |
|------|------------|-----------------|
| **P0 — Reliability risk** | Actively causing or likely to cause production incidents (live secrets, exploited CVE, reachable null crash, SQL injection) | Always shown, bypasses budget |
| **P1 — Velocity blocker** | Makes common changes take 2-5x longer (divergent change on hot-spots, wrong abstraction in hot path) | Shown within budget, high rank |
| **P2 — Compounding interest** | Growing debt in hot-spots (temporal coupling, shotgun surgery pattern) | Shown within budget, medium rank |
| **P3 — Cosmetic** | No material impact on reliability or velocity (minor smells, style beyond formatter) | Dropped to backlog by default |

**Failure mode of immature teams**: spending 60% of refactoring time on P3 because it's visible and easy, while P1 and P2 compound. Do NOT surface P3 to the user unless they explicitly ask for the backlog.

*Note: this tier model is industry practice across multiple consulting frameworks. The specific labels are conventional severity mappings, not owned by any one firm.*

## When NOT to Refactor (Fowler's conditions, 2018 edition)

Drop findings that would violate any of these:

1. **Adding functionality and the code works** — do not refactor first if speculative. Only refactor when structure actively impedes the addition.
2. **Code is close to a rewrite** — if the system is being replaced within 6-12 months, refactoring investment doesn't recover.
3. **Deadline is hard** — imperfect shipped code beats perfect unreleased code. Record in backlog, defer.
4. **No test coverage** — refactoring without tests is restructuring. The first investment before structural refactoring is **characterization tests** (Feathers, Working Effectively with Legacy Code, 2004). Audit agents should flag "no tests for this file" as a separate finding, not attempt to refactor.
5. **Code in a dead zone** — stable, low-churn, minimal business impact. The NPL of fixing is negative.

## The NPL-Negative Debt Argument

Net present value of fixing debt is negative when:
1. Code is stable and rarely touched (low churn)
2. Domain it covers is shrinking or deprecated
3. Fix cost exceeds projected maintenance cost over product lifetime
4. Refactoring introduces risk greater than the risk of leaving it

Martin Fowler: "You should not fix all technical debt at once and you should not fix it just because it's there." The question is always **what is the cost of NOT fixing it?** If the answer is close to zero, leave it.

At Phase 2, filter out findings where recon shows `churn < 2 commits in 6 months` AND the file is not a known entry point. These are frozen debt. Move them to `findings-backlog.json` with the reason "low churn — NPL-negative".

## Rules Experts Break — Don't Flag as Debt

Do NOT flag these as findings unless they have a concrete failure scenario:

### DRY violations before the Rule of Three
Sandi Metz, 2016: "Duplication is far cheaper than the wrong abstraction."

Do NOT surface duplication findings until THREE instances appear AND at least one is in a hot-spot. Two instances could be coincidence — the third gives enough signal to find the real abstraction. Before that, extraction creates coupling that's more expensive to undo than the duplication.

### SRP over-application ("pulverized code")
A class that handles 15 behaviors for the SAME stakeholder has ONE reason to change. Do not flag it as SRP violation.

Ousterhout's counter: over-applying SRP produces **shallow modules** — interface complexity ≈ implementation complexity. Shallow modules have near-zero value. Deep modules (small interface, significant behavior) are what you want. A 50-line function that implements a well-defined abstraction is BETTER than five 10-line functions requiring cross-referencing to understand.

Only flag SRP violations when you can identify MULTIPLE ACTORS (stakeholders) causing the class to change.

### OCP / DIP as "add interfaces everywhere"
`UserRepository` interface with exactly one implementation `UserRepositoryImpl`, never mocked, never swapped at runtime — is **noise**, not design. Drop from findings.

Only flag missing abstraction when substitution is actually needed (external I/O boundary, multiple real implementations, tests that need fakes).

### Naming verbosity
Martin: long explanatory names are always better. Practitioners: in tight algorithmic code, `i`, `j`, `n` carry convention-based meaning. `customerPaymentProcessingServiceImpl` is worse than `paymentService`.

Ousterhout's rule: names should be **precise, not verbose**. Do not flag naming unless the name is misleading OR the reader cannot predict behavior from it.

### Function length
Martin: 5-10 lines. Ousterhout: deep functions (small interface, rich implementation) are the goal.

Do NOT flag long functions by line count alone. Only flag when the function is doing MULTIPLE things — the variable is "can the function be given a name that fully captures its contract?"

## Fowler Smell Catalog — Ranked by Practitioner Impact

### Tier 1 (flag at Phase 1, include in Phase 2 budget)

- **Divergent Change** — one class changes for multiple unrelated reasons (SRP violation with git-observable signature)
- **Shotgun Surgery** — one logical change requires touching many classes (temporal coupling signal)
- **Feature Envy** — method uses data from another class more than its own (classic wrong decomposition)
- **Data Clumps** — same 3-4 fields always appear together across multiple classes (extract value object)
- **Primitive Obsession** — domain concepts as raw primitives; validation duplicated at use sites

### Tier 2 (flag when in hot-spots)

- **Inappropriate Intimacy** — class A reaches into class B's private details
- **Message Chains** — `a.getB().getC().getD().doSomething()` — Law of Demeter violation
- **Middle Man** — class that only delegates
- **Parallel Inheritance Hierarchies** — adding a subclass of X forces adding a subclass of Y

### Tier 3 (flag only with failure scenario)

- **Long Parameter List** (>4 args) — signals missing abstraction, but flag only if callers are actually confused
- **Refused Bequest** — subclass ignores inherited methods; LSP violation
- **Speculative Generality** — hooks for plugin systems that have no plugins (YAGNI)
- **Temporary Field** — instance variable only set in some paths

### Never flag as a smell

- Comments explaining WHY (business rationale, algorithmic choice, workaround)
- Long functions that are deep modules (Ousterhout)
- Duplication before the Rule of Three
- Interface with one implementation that's actually mocked in tests

## Context-Aware Filtering

At Phase 2, additionally drop findings that:
- Touch code with an explanatory comment (`// intentional — see RFC-4xxx`)
- Touch code flagged `//nolint`, `# noqa`, `// audit-ignore`
- Are in test files (tests should have their own audit dimension — `category: tests`)
- Duplicate a finding from a previous audit run that the user dropped (check `findings-backlog.json` of prior runs if any)

## Summary Table — What to Present vs Drop

| Finding type | Present if | Drop if |
|--------------|------------|---------|
| Live secret, exploited CVE | Always (bypasses budget) | Never |
| Correctness bug with failure scenario | Hot-spot OR high impact | Low-churn file with no impact |
| Security vulnerability with concrete path | Always | Dev-dep only, no exploitability |
| Performance issue with latency impact | Hot-spot OR user-facing | Theoretical, no measurement |
| Design smell | Tier 1 in hot-spots | Tier 3 outside hot-spots |
| Style / naming | (dropped unless misleading) | Any formatter-catchable |
| Test gap | Hot-spot uncovered file | Low-churn or test files |
| Architectural finding | Always — as discussion item | Never auto-fix |
