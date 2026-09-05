---
name: spec-template
description: Canonical spec.md output template for the flow-spec skill. Three size variants (Small/Medium/Large) controlled by HTML conditional markers. Every section structurally prevents one or more anti-patterns from the wave-1 catalog. Load this entire file before drafting the spec in Phase 3.
---

# Spec-Forge Output Template

Fill placeholders in `[SQUARE BRACKETS]` from discovery answers. Honor `<!-- SIZE: X only -->` markers — include the section only for the matching size variant. Do not leave a placeholder unfilled in a section the size variant includes; either fill it from discovery, mark it as a named assumption in Section 7.2, or list it as an Open Question in Section 8.

---

```markdown
# Spec: [FEATURE NAME]

> **One-sentence summary**: [What this does and for whom, in plain language. No jargon. Max 20 words.]

**Status**: Draft | In Review | Approved
**Size**: Small | Medium | Large
**Author**: [Name or role]
**Created**: [DATE]
**Last updated**: [DATE]
**Version**: 1.0

---

## TL;DR

> Read this block. If it answers your question, stop here.

**Problem**: [1–2 sentences. What is broken or missing? Whose problem is it? What does it cost them today?]

**Solution**: [1–2 sentences. What this spec describes. What the user can do after it ships that they cannot do now.]

**Who it's for**: [Named user roles. Specific. "Managers who need to approve requests" not "users".]

**Non-goals (v1)**: [3–5 bullets minimum. What this explicitly does NOT do. Binding.]
- [Non-goal 1]
- [Non-goal 2]
- [Non-goal 3]

**MVP cut line**: Everything in Section 4 tagged `MUST` ships for v1. `SHOULD` items are v1.1 candidates. `MAY` items are backlog.

**Key decision**: [The single most consequential architectural or product decision this spec makes. State it plainly.]

---

## 1. Context

### 1.1 Problem Statement

[2–4 sentences. Current state, what's failing, who feels the pain. Write from the user's perspective, not the business's.]

**Current workaround**: [How users solve this today. If none, state that.]

**Business rationale**: [Why this matters now. 1–2 sentences. Not a business case — just the motivating reason.]

### 1.2 User Roles

> Every requirement must name one of these roles. If a requirement cannot be attributed to a role, it is incomplete.

| Role | Description | Volume (approx.) | Key characteristic |
|------|-------------|------------------|--------------------|
| [Role 1] | [What they do] | [How many] | [Most relevant trait] |
| [Role 2] | [What they do] | [How many] | [Trait] |

**Primary actor**: [The role who interacts most with this feature.]

**Hidden stakeholders**: [Roles affected but not interacting directly — downstream consumers, admins, compliance, on-call. If none: "None identified."]

<!-- SIZE: medium and large only -->
### 1.3 Prior Art & Alternatives Considered

| Option | Status | Why rejected / why not this |
|--------|--------|-----------------------------|
| [Option 1] | Rejected | [Reason] |
| [Current approach] | Selected | [Reason this was chosen] |
<!-- END SIZE: medium and large only -->

---

## 2. Scope

### 2.1 In Scope

[Bulleted list. Be specific. If a feature requires judgment about whether it's in or out, name it explicitly.]
- [In-scope item 1]
- [In-scope item 2]

### 2.2 Out of Scope (Non-Goals)

> Binding. If a stakeholder asks for one of these, point them here.

- **[Non-goal 1]**: [Brief reason or "deferred to v2"]
- **[Non-goal 2]**: [Brief reason or "separate initiative"]
- **[Non-goal 3]**: [Brief reason]

### 2.3 Adjacent Systems

| System | Relationship | Constraint |
|--------|-------------|------------|
| [System 1] | Reads from | [What must remain stable] |
| [System 2] | Writes to | [Contract that must not break] |

---

## 3. User Journeys

> Three-path coverage rule: every journey must specify happy path, primary error path, and at least one edge case.

### Journey 1 — [Name] (Priority: P1)

**Actor**: [Role from Section 1.2]
**Starting condition**: [System state when this journey begins]
**Goal**: [What the actor wants. One sentence.]

**Happy path**:
1. [Step 1 — actor action or system event]
2. [Step 2]
3. [Final state]

**Error path — [specific failure condition]**:
1. [What triggers the error]
2. [What the system does]
3. [What the actor sees / can do next]

**Edge cases**:
- [Edge case 1]: [What happens]
- [Edge case 2]: [What happens]

**Acceptance criteria**:

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-001 | [precondition] | [actor action] | [observable outcome — specific, measurable] | MUST |
| AC-002 | [precondition] | [action] | [outcome] | MUST |
| AC-003 | [error precondition] | [error trigger] | [system error response — named message or behavior] | MUST |

---

### Journey 2 — [Name] (Priority: P2)

[Same structure as Journey 1.]

---

[Additional journeys follow the same structure. P3+ may have abbreviated error paths.]

---

## 4. Functional Requirements

> Every requirement: named actor, observable behavior, testable outcome. No implementation detail. No vague adjectives. MUST/SHOULD/MAY discipline.

### 4.1 Core Requirements

| ID | Actor | Requirement | Priority | Acceptance Link |
|----|-------|-------------|----------|-----------------|
| FR-001 | [Role] | MUST [observable behavior with specific outcome] | MUST | AC-001 |
| FR-002 | [Role] | MUST [observable behavior] | MUST | AC-002 |
| FR-003 | [Role] | SHOULD [behavior] | SHOULD | AC-010 |
| FR-004 | System | MUST [system-initiated behavior with trigger and observable outcome] | MUST | AC-003 |

<!-- SIZE: medium and large only -->
### 4.2 Data Requirements

> Logical entities, not schemas. No column names. "Persists across sessions" not "stored in PostgreSQL".

| Entity | Description | Key attributes (logical) | Relationships |
|--------|-------------|--------------------------|---------------|
| [Entity 1] | [What it represents] | [Attribute 1, Attribute 2] | [Relates to Entity 2 via...] |

**Data retention**: [How long is this data kept? What triggers deletion? If unknown, document as assumption.]

**Data sensitivity**: [Encryption at rest? In transit? PII classification?]
<!-- END SIZE: medium and large only -->

<!-- SIZE: large only -->
### 4.3 Integration Requirements

| Integration | Direction | Data | Failure behavior | Contract owner |
|-------------|-----------|------|-----------------|----------------|
| [System A] | Inbound | [What data arrives] | [What this system does if A is unreachable] | [Team/contact] |
| [System B] | Outbound | [What is sent] | [Retry policy? Dead letter?] | [Team/contact] |
<!-- END SIZE: large only -->

---

## 5. Non-Functional Requirements

> Mandatory. Every NFR must be SMART: Specific (names component and actor), Measurable (numeric), Achievable, Relevant, Time-bound (load condition or environment).

### 5.1 Performance

| Metric | Target | Condition | Measurement method |
|--------|--------|-----------|-------------------|
| [Operation] response time | [Xms at pYY] | [Under Z concurrent users] | [Lighthouse / load test / APM] |
| [Page/operation] load time | [threshold] | [on N connection] | [method] |

**Performance budget decision**: [At what degradation point does this become a defect vs. a known limitation?]

### 5.2 Security

**Authentication**: [Named mechanism. "JWT via existing auth service" or "standalone username/password with bcrypt". Not "TBD".]

**Authorization**: [Which roles can do what. Reference Section 1.2. Any role not listed is implicitly denied.]

| Action | Allowed roles | Denied behavior |
|--------|---------------|-----------------|
| [Action 1] | [Role 1, Role 2] | [403 response, or specific behavior] |

**Data protection**: [Encryption at rest? In transit? Which fields are PII?]

**Threat surface**: [Highest-risk attack vector. At minimum: injection, auth bypass, or data exposure.]

### 5.3 Reliability & Availability

**Uptime target**: [X% per month, or "no formal SLA for v1 — best effort"]
**Graceful degradation**: [If this feature is unavailable, what does the user see? What must NOT happen?]
**Recovery behavior**: [After failure, does the system self-recover? Is data preserved?]

### 5.4 Error Handling

| Error condition | Actor-visible behavior | System behavior | Recovery path |
|----------------|----------------------|-----------------|---------------|
| [Input validation failure] | [Specific error message text or pattern] | [What the system logs/does] | [User can...] |
| [Dependency failure] | [What the user sees] | [Retry? Fail open? Fail closed?] | [User action] |
| [Auth failure] | [Message shown] | [Session invalidated? Rate limited?] | [User redirected to...] |
| [Resource exhaustion] | [Message shown] | [Rate limit response] | [Retry-after header? Backoff?] |

<!-- SIZE: medium and large only -->
### 5.5 Scalability

**Concurrency target**: [N simultaneous users/requests for this feature at launch]
**Growth assumption**: [Expected growth rate, and at what scale should this be re-evaluated?]
**Bottleneck hypothesis**: [Where will this break first?]

### 5.6 Observability

**Required logging**: [What events must be logged for debugging? Structured or unstructured?]
**Required metrics**: [What counters/gauges/histograms must exist? What dashboard?]
**Alerting threshold**: [At what metric value should an alert fire? Who receives it?]
<!-- END SIZE: medium and large only -->

<!-- SIZE: medium and large only -->
### 5.7 Accessibility

**Standard**: [WCAG 2.1 AA minimum, or "not required for v1 — document decision rationale"]
**Screen reader**: [Supported? Which? Key interaction model.]
**Keyboard navigation**: [All core flows navigable without mouse?]
**Contrast / sizing**: [Any specific requirements beyond standard WCAG?]

### 5.8 Browser / Platform Support

| Platform | Support level | Notes |
|----------|--------------|-------|
| [Browser/OS/device] | Full | |
| [Browser/OS/device] | Degraded | [What degrades] |
| [Browser/OS/device] | Not supported | [Why] |
<!-- END SIZE: medium and large only -->

<!-- SIZE: large only -->
### 5.9 Compliance

**Applicable frameworks**: [GDPR, HIPAA, PCI-DSS, SOC 2, CCPA — or "none identified"]
**Data residency**: [Where must data be stored or processed?]
**Audit requirements**: [What events must be immutably logged for compliance?]
<!-- END SIZE: large only -->

---

## 6. Success Criteria

### 6.1 Launch Criteria (go/no-go)

> All true before v1 ships. Binary pass/fail.

- [ ] All AC-NNN pass in staging
- [ ] Performance: [specific operation] meets [target] under [load condition] in load test
- [ ] Security: [auth flow] reviewed, [vulnerability class] validated absent
- [ ] Error states: all error paths in Section 5.4 produce correct user-visible messages

### 6.2 Post-Launch Health Metrics

> Measured in first 30 days. Don't block launch; trigger review if missed.

| Metric | Target | Measurement | Review trigger |
|--------|--------|-------------|----------------|
| [Adoption metric] | [X users/day or X% of target] | [Analytics event] | [If below Y at day 30] |
| [Quality metric] | [Error rate < X%] | [APM / error tracking] | [If above Y] |
| [Business metric] | [Support ticket reduction, conversion rate, etc.] | [Source] | [If not trending toward target] |

### 6.3 What "Failure" Looks Like

> [1–3 sentences. In what scenario does this ship on time, pass all ACs, but still fail the real need? What assumption would have to be wrong for that to happen?]

---

## 7. Constraints & Assumptions

### 7.1 Technical Constraints

| Constraint | Rationale | Impact on design |
|-----------|-----------|-----------------|
| [Must use existing auth service] | [No budget for standalone auth] | [Inherits its user model] |
| [Deployed to X cloud/region] | [Data residency] | [Limits service selection] |

### 7.2 Assumptions

| ID | Assumption | Confidence | Owner | How to validate |
|----|-----------|------------|-------|-----------------|
| A-001 | [Stated assumption] | High / Medium / Low | [Role] | [How it would be confirmed or refuted] |
| A-002 | [Stated assumption] | Medium | [Role] | [Validation method] |

**Validated assumptions**: [List any assumptions that were tested with users or data before this spec was written.]

### 7.3 Dependencies

| Dependency | Type | Owner | Status | Risk if delayed |
|-----------|------|-------|--------|-----------------|
| [System/API/team] | Blocking / Informational | [Owner] | [Available / In progress / TBD] | [Impact] |

---

## 8. Open Questions

> Maximum 3. Each has an owner and resolution deadline. A spec with more than 3 is premature.

| ID | Question | Impact if unresolved | Owner | Deadline |
|----|---------|----------------------|-------|----------|
| Q-001 | [Specific question] | [What breaks if this isn't answered] | [Name/role] | [Date] |
| Q-002 | [Specific question] | [Impact] | [Name/role] | [Date] |

---

<!-- SIZE: medium and large only -->
## 9. Revision History

| Version | Date | Author | Changes | Reason |
|---------|------|--------|---------|--------|
| 1.0 | [DATE] | [Author] | Initial draft | |

---
<!-- END SIZE: medium and large only -->

## Appendix

### A. Glossary

| Term | Definition in this spec |
|------|-------------------------|
| [Term 1] | [Precise definition] |
| [Term 2] | [Precise definition] |

<!-- SIZE: medium and large only -->
### B. Mockups / Wireframes

> Low-fidelity only. If no mockups exist, state: "No mockups — behavior is fully specified by acceptance criteria in Section 3."

[Embed or link mockups here. Caption each with the journey it illustrates.]

### C. Reference Documents

| Document | What it answers | Link |
|----------|----------------|------|
| [Constitution.md] | Stack, patterns, architectural principles | [path] |
| [Prior spec / ADR] | [What decision it records] | [link] |
<!-- END SIZE: medium and large only -->
```

---

## Size Variant Quick Reference

**Small (30–80 lines)** — CLI tool, single endpoint, sub-1-week effort. Includes: TL;DR, 1.1 Problem, 1.2 Roles (no Prior Art), 2.1–2.3 Scope, 3 Journeys (1–3, may have abbreviated error paths), 4.1 Core FRs only, 5.1–5.4 NFRs only (Performance, Security, Reliability, Error Handling), 6 Success Criteria, 7.1–7.3 Constraints, 8 Open Questions, Appendix A Glossary.

**Medium (100–250 lines)** — Web feature, mobile screen, 1–8 weeks. Includes everything in Small PLUS: 1.3 Prior Art, 4.2 Data Requirements, 5.5 Scalability, 5.6 Observability, 5.7 Accessibility, 5.8 Browser Support, 9 Revision History, Appendix B Mockups, Appendix C References.

**Large (300–600 lines)** — Multi-service platform, cross-team, >8 weeks. Includes everything in Medium PLUS: 4.3 Integration Requirements, 5.9 Compliance. Stakeholder authority (DRI) named in 1.2. If a Large spec exceeds 8 distinct user journeys, decompose into sub-specs with a parent integration spec.

---

## Anti-Pattern Defense Map

| AP | Defended by section |
|---|---|
| AP-01 Fog of Adjectives | 5.1–5.9 SMART NFRs; 4.1 "no vague adjectives" rule |
| AP-02 Implementation Leak | 4.1 "no technology names"; 4.2 logical entities |
| AP-03 Wishlist | TL;DR MVP cut line; 4.1 MUST/SHOULD/MAY |
| AP-04 Happy Path Only | 3 three-path journey structure; 5.4 Error Handling |
| AP-05 Missing Actors | 1.2 Roles table; every FR names an actor |
| AP-06 NFR Graveyard | 5.1–5.9 mandatory NFR sub-sections |
| AP-07 Spec Rot | Last-updated header; 9 Revision History |
| AP-08 Wall of Text | TL;DR block; progressive disclosure |
| AP-09 Untestable ACs | Given/When/Then table per journey |
| AP-10 Design by Committee | 1.2 hidden stakeholders + DRI for L tier |
| AP-11 Anchored Spec | 7.2 Assumptions table with validation method |
| AP-12 Ivory Tower | 7.1 Technical Constraints with rationale |
| AP-13 Vague Scope | 2.2 Non-Goals as binding first-class section |
| AP-14 Discovery Bypass | 6.3 "What failure looks like"; pre-spec discovery |
| AP-15 Tense Chaos | MUST/SHOULD/MAY discipline; Appendix A Glossary |
| AP-16 Micromanagement | Logical-only data model; no algorithmic detail in FRs |
