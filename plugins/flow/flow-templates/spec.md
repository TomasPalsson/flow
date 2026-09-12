# Spec: [FEATURE NAME]

**Created**: [YYYY-MM-DD] · **Route**: bounded | oneshot | dispatch

## TL;DR

> Read this block. If it answers your question, stop here.

**Problem**: [1–2 sentences. What is broken or missing, whose problem it is, what it costs them today.]

**Solution**: [1–2 sentences. What the user can do after this ships that they cannot do now.]

**Who it's for**: [Named roles. "Managers who approve requests", not "users".]

**MVP cut line**: everything tagged `MUST` in §4.1 ships. `SHOULD` is v1.1. `MAY` is backlog.

**Key decision**: [The single most consequential decision this spec makes. State it plainly.]

## 1. Context

### 1.1 Problem statement

[2–4 sentences from the user's perspective. Current state, what fails, who feels it.]

**Current workaround**: [How they solve it today. If none, say so.]

### 1.2 Roles

> Every requirement below names one of these roles. A requirement with no role is incomplete.

| Role | What they do | Key characteristic |
|------|--------------|--------------------|
| [Role 1] | [What they do] | [Most relevant trait] |

**Primary actor**: [The role that touches this most.]
**Hidden stakeholders**: [Affected but not interacting — on-call, admins, downstream. Or "None identified."]

## 2. Scope

### 2.1 In scope

- [Capability 1 — a thing the system will do]
- [Capability 2]

### 2.2 Non-goals

> Binding. A change here is an amendment, not an interpretation.

- [What this explicitly does NOT do]
- [The adjacent thing people will assume is included and is not]
- [The scale/tier/platform this does not serve in v1]

## 3. Journeys

> Three paths per journey — happy, error, edge. Given / When / Then, observable outcomes only.

### Journey 1 — [Name] ([role])

| Path | Given | When | Then |
|------|-------|------|------|
| Happy | [precondition] | [action] | [observable outcome] |
| Error | [precondition] | [action that fails] | [what the user sees and what state survives] |
| Edge | [boundary precondition] | [action] | [observable outcome] |

## 4. Requirements

### 4.1 Functional requirements

> No technology names — those live in `design.md`. One requirement, one behavior; split every "and".

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | [Role] MUST [observable behavior] | [How you prove it] |
| FR-02 | SHOULD | [Role] SHOULD [observable behavior] | [How you prove it] |
| FR-03 | MAY | [Role] MAY [observable behavior] | [How you prove it] |

## 5. Non-functional requirements

> Only rows that carry a number. A row with no number is not an NFR, it is an adjective — delete it or quantify it.

| Dimension | Number | How it is measured |
|-----------|--------|--------------------|
| [Latency / throughput / limit] | [p95 < 300 ms] | [The measurement] |

## 6. Launch criteria

> The checklist that decides "shipped". Each line is observable by someone other than the author.

- [ ] [Every MUST in §4.1 has a passing test]
- [ ] [The error path of each journey is exercised]
- [ ] [The NFR numbers in §5 are measured, not assumed]

## 7. Assumptions

| # | Assumption | Confidence | Blast radius if wrong |
|---|------------|-----------|-----------------------|
| A1 | [Stated position taken during discovery] | High / Med / Low | [What breaks] |

## 8. Open questions

> Cap: 3. More than 3 unknowns is not a buildability contract, it is a wishlist with placeholders.

1. [NEEDS CLARIFICATION: question]

## Appendix A — Glossary

| Term | Means |
|------|-------|
| [Domain term] | [Definition, in this project's sense] |
