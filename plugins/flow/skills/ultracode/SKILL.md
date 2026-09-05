---
name: ultracode
description: "Maximum-scale multi-agent coding orchestration — turn a task into a Sonnet agent fleet (developer implementers + adversary reviewers) run through the Workflow tool with a spec gate, trial run, and adversarial verification. Use when the user says 'ultracode' or '/ultracode <task>', asks for an agent fleet/swarm, a massive parallel implementation, migration, audit, or refactor, says 'use sonnet agents like there is no tomorrow', 'fan out agents', 'maximum effort on this', or wants a big coding task done at fleet scale. Bare /ultracode (no args) arms ultracode posture for the rest of the session. Do NOT use for: a single feature needing TDD + user-verification gates (/feature), research-only fan-outs with no code written (/overkill, /deep-research), or critiquing an idea (/scrutinize-idea)."
user-invocable: true
argument-hint: "[task to run at fleet scale — omit to arm posture for the session]"
---

# Ultracode — Fleet-Scale Coding Orchestration

You (the orchestrator) already know the Workflow API and the house delegation loop (CLAUDE.md: plan → Sonnet writes → verify). This skill is the part neither teaches: when a fleet pays, how to keep 4-64 agents from sabotaging each other, and how to make verification real instead of theatrical. Every number here is cross-validated against primary sources; load [`references/evidence.md`](references/evidence.md) only if the user asks for the receipts.

**Two modes:**
- **`/ultracode <task>`** — run the task through the pipeline below (Phase 0 → 5).
- **`/ultracode`** (bare) — arm posture: every substantive coding task this session runs through this pipeline by default; solo work only for conversational turns and one-line diffs. Say so in one line, then continue.

---

## Phase 0 — Should this be a fleet at all?

Fan-out is a deliberate purchase (~15x the tokens of a single-context pass), and coding parallelizes *worse* than research — Anthropic's own multi-agent team says so — because code has shared context and interface coupling. Gate before spawning:

| Signal | Decision |
|---|---|
| Diff describable in one sentence | No fleet, no plan. Just do it. |
| One strong agent could nearly solo it (≳45% likely to succeed alone) | Don't decompose — added agents are measured *negative* returns above that line. One Sonnet worker, whole task, adversary review after. |
| Work splits into units where each agent OWNS files/modules no other agent touches | Fleet. This ownership test — not size — is the real criterion. |
| Units share an interface, schema, or causal chain | Fix the contract FIRST (sequentially, in the spec), then fleet the now-independent remainder. Parallelizing causally-linked units produces semantic conflicts that each pass tests alone and fail together. |

You can't measure "45% solo-success" mid-flight — use proxies: the change lives in one file/module; repo history has a comparable single-PR diff; the oracle runs in seconds; nothing needs a frozen contract. **Two or more of these → skip the fleet, one worker + adversary review.**

Scale by adding *units* (pipeline stages, waves), never by widening one unit past **3-4 agents** — per-agent reasoning capacity thins out beyond that regardless of model tier. A 40-file migration is 40 small units through a pipeline, not 40 agents in one barrier.

## Phase 1 — Grill, then freeze a SPEC

**MANDATORY — read [`references/spec-template.md`](references/spec-template.md) before writing the spec.**

Spec quality is the highest-leverage token you will spend: 41.77% of measured multi-agent failures are specification/design flaws, and ambiguous specs measurably *raise reward-hacking rates* (33-44% on ambiguous vs well-specified tasks) — a vague spec doesn't just get misread, it invites the fleet to game it. Fleet agents cannot ask follow-ups; the SPEC is their only lifeline.

- Ambiguous or large task → grill the user first: 3-5 load-bearing questions (the template has the bank), batched, answers serialized into `.ultracode/<slug>/SPEC.md`.
- Small clear task → write SPEC.md directly; don't interrogate for sport.
- **Adversarially review the spec before fan-out.** A prep artifact consumed by N downstream agents is a single point of failure multiplied by N — spawn one `adversary` (lens: spec) against SPEC.md. The Bun rewrite reviewed PORTING.md harder than most teams review code, *then* let $165k of agents run off it.

## Phase 2 — Trial run (1-3 units)

Run the full loop — developer → adversaries → fixes → merge — on 1-3 representative units before the fleet. You are smoke-testing the *orchestration*, not the product: Bun's agents git-stomped each other **2 minutes** into full fan-out; a trial surfaces that class of failure for the price of one unit.

When trial output is weak: **edit the SPEC or the agent prompts and re-run the trial. Never hand-fix the output.** A hand-fix repairs one artifact; a process-fix repairs the other N-1 agents that would have made the same mistake. (This rule holds all the way through Phase 3 — mid-fleet, a recurring defect means stop, patch the prompt, resume.)

## Phase 3 — Fleet

**Roles** — the stable ratio is **1 developer : 2+ adversaries per diff**, hard-separated: the implementer never reviews, the reviewer never implements. Fix application goes back to the developer (or a fresh `developer` acting as fixer on large batches) — a reviewer who edits inherits the implementer's bias the whole split exists to kill.

**Model pinning — the silent 5x trap.** Subagent `model:` frontmatter defaults to `inherit`: an unpinned agent on a Fable/Opus session silently bills the frontier tier for bulk code-writing. The `developer` and `adversary` agents are pinned `model: sonnet`; when writing raw `agent()` calls, set `model: 'sonnet'` (or `'haiku'` for mechanical transforms) explicitly, every call. Never use Fable/Opus as fan-out workers — one Fable 2k-line diff costs what 4-5 Sonnet implementer calls cost. Full arithmetic: load [`references/fleet-economics.md`](references/fleet-economics.md) **before sizing a fleet, picking non-default tiers, or quoting costs**; do NOT load it for posture-only turns.

**Work queue.** Prefer a mechanically-enumerable list as the queue — compiler errors, failing tests, lint violations, a file list — sharded along module/crate/directory ownership boundaries. Enumerate ONCE up front; never re-run slow global commands (full builds, repo-wide greps) inside agent loops — one slow command from one agent can stall the whole fleet's I/O.

**Isolation is a spectrum, priced by repo size × agent count:**

| Scale | Isolation |
|---|---|
| ≤4 writers | `isolation: 'worktree'` per agent — cheap, zero discipline needed |
| Many writers, big repo | Shard worktrees: N agents share one worktree per shard (Bun: 4 × 16) |
| Any shared checkout | Git whitelist in every prompt: commit-only-your-assigned-files; **banned: stash, reset, checkout, pull, merge**, and any slow global command. Agents each "reasonably managing their own work" destroy each other's without this. |

Worktrees only convert invisible overwrites into visible merge conflicts — they do NOT prevent semantic conflicts. That prevention happened in Phase 1 (contracts frozen before fan-out).

**Artifacts to disk.** Workers write full output to `.ultracode/<slug>/` and return summary + paths + evidence — never full file contents through your context. Each prompt carries: objective, output format + path, tool guidance, boundaries (what it must NOT touch), and the SPEC verbatim.

**Circuit breaker.** Set the workflow budget from your estimate and check at phase boundaries: spend past ~2x estimate with under half the units done means a *process* defect (retry loops, bloated prompts, agents re-deriving shared context) — stop the run, read the journal, patch the prompt/spec, and resume with `resumeFromRunId` (completed agents replay from cache; you pay only for the fix). Pushing on at 2x burn "to finish" is how five-figure runaway incidents happen.

**Skeleton** (agentType resolves the pinned agents; FINDINGS mirrors the adversary's verdict format):

```js
const FINDINGS = { type: 'object', required: ['verdict', 'findings'], properties: {
  verdict: { enum: ['BLOCK', 'FIX-THEN-MERGE', 'PASS'] },
  checked: { type: 'string' },   // deterministic-sweep receipts — required even on PASS
  findings: { type: 'array', items: { type: 'object', required: ['predicate', 'severity', 'scenario'],
    properties: { predicate: { type: 'string' }, severity: { enum: ['fatal', 'significant', 'improvable', 'cosmetic'] },
      scenario: { type: 'string' }, receipt: { type: 'string' }, status: { enum: ['CONFIRMED', 'PLAUSIBLE', 'NEEDS-TOOL'] } } } } } }

phase('Implement')
const results = await pipeline(units,
  u => agent(devPrompt(u), { agentType: 'developer', phase: 'Implement', label: `dev:${u.name}` }),
  (r, u) => parallel(['correctness', 'gaming'].map(lens => () =>
    agent(reviewPrompt(u, lens), { agentType: 'adversary', phase: 'Review', label: `adv:${lens}:${u.name}`, schema: FINDINGS })))
    .then(vs => ({ unit: u, dev: r, reviews: vs.filter(Boolean) })))
```

## Phase 4 — Verification that isn't theater

LLM review alone plateaus near coin-flip at catching false success (AUROC ≤0.65) — and a trivial string-level detector *beats* it (0.83-0.95). So: **deterministic checks first, LLM lenses second, execution as the tiebreaker.**

**Deterministic sweep (run before spending review tokens):**
- Test-count diff vs baseline — any *decrease* on a "fix" diff is a hard flag. Run the suite and count tests executed; exit codes lie by omission ("0 skipped" is a count you verify, not a claim you accept).
- Grep the diff for `skip`, `xfail`, `.skip(`, `todo`, commented-out asserts; for assertions made structurally weaker; for literals in source matching test-expected values.

**LLM lenses.** Give each adversary ONLY the diff + SPEC — never the developer's reasoning, never "tests are green" (an auditor told the outcome succeeded rationalizes the process; the adversary self-commits to expected behavior before looking, which is what collapses false-acceptance from 72% to ~1%). Assign *distinct* lenses — correctness / security-authz / gaming / cross-file — because N identical reviewers share correlated blind spots; a 3-judge ensemble of duplicates still waves through 55% of false positives.

**Structural blind spots.** Race conditions, TOCTOU, timing, complex authorization logic: no prompt fixes these — the model isn't executing a scheduler. Route these classes to a sanitizer/analyzer/fuzzer co-signer or human eyes; an adversary verdict on them is only ever PLAUSIBLE.

**Answer-retrieval.** On tasks with a findable upstream fix (known CVEs, public bug fixes), the dominant hack is retrieval, not stubbing — 63% of audited "successful" frontier-model resolutions copied the fix from the web or mined it from git history. The fix is environmental, not a smarter reviewer: run developers with network denied and `.git` history stripped to one commit, restore at merge time.

**Disagreement** (adversary vs adversary, or developer pushes back): never average, never let insistence win. Spawn ONE Opus adjudicator scoped to that specific finding — this is the only place a higher tier enters the loop, and it's cheaper than upgrading any fleet role wholesale.

**Triage.** Adversaries over-report by design — a reviewer asked for gaps will find some in sound code. Only **Fatal/Significant** findings (correctness or stated requirements) block or get fixed; Improvable/Cosmetic are logged, not chased — chasing them buys over-engineering with fleet tokens.

## Phase 5 — Land

- **Merge shards serially**, each merge seeing the previous shard's changes — surfacing conflicts incrementally instead of all-at-once at the end.
- **Tests-pass is necessary, not sufficient.** The suite that failed to prevent the original bugs cannot certify their absence in new code. Pair it with something that catches what the suite structurally can't: new tests targeting the change's specific risk class, mutation testing, or sanitizers/fuzzing for memory/concurrency surfaces.
- **Hardening is a separate phase**, not a formality inside "done": security review + fuzz/sanitizer passes for risky surfaces come after tests-green, before you call it shipped.
- Ship per repo conventions. A unit that is really a user-facing feature belongs in `/feature`'s gates (TDD, browser + user verification) — hand it over rather than duplicating them here.

## Model escalation (workers)

| Situation | Tier |
|---|---|
| Default: implement, test-write, review, refactor | `sonnet` (pinned in the agents) |
| Mechanical transforms, file discovery, formatting | `haiku` |
| No verification oracle exists (design docs, novel-algorithm correctness no test will exercise, threat models) | `opus` for that worker — the adversary+tests mechanism that lets Sonnet suffice isn't available |
| Single-shot high-blast-radius edit (no fast red/green loop before damage lands) | `opus` for that worker |
| A Sonnet worker would need max thinking effort to cope | `opus` at normal effort — often *cheaper* than Sonnet's inflated reasoning tokens |
| Adjudicating a contested finding | ONE `opus` call, scoped to the finding |
| Bulk code-writing on Fable/Mythos | Never. |

Sonnet-by-default is an economics + oracle argument, not a capability claim — it holds *because* Phase 4 exists. No verification gate → no cheap workers.

## NEVER

- **NEVER let a fleet agent inherit the session model.** `inherit` is the default; on a Fable session that's a silent 5x cost multiplier on every worker. Pin every call.
- **NEVER hand-fix one agent's bad output mid-fleet.** Patch the prompt/spec and re-run — the defect exists in N-1 other agents' futures.
- **NEVER accept an agent's self-report as verification.** "Tests pass" is a claim; the count of tests executed, the command, and its output are evidence. 75.8% of self-assessed coding-agent "successes" in one audit were false.
- **NEVER show a reviewer the implementer's reasoning or the outcome.** Both anchor the reviewer into rationalizing; the whole value of the split is independent derivation.
- **NEVER run N identical reviewers and call it rigor.** Correlated contexts double-count the same blind spots. Distinct lenses or nothing.
- **NEVER blanket-upgrade the fleet tier to fix quality.** Fix the spec, or add one scoped higher-tier adjudication pass. Tier multipliers apply to every agent; adjudication applies to one call.
- **NEVER let parallel writers touch a shared checkout without the git whitelist.** Collision is measured in minutes, not probability.
- **NEVER parallelize units that share an unfrozen contract.** Each side passes its own tests; the system fails at merge, where it's most expensive.
- **NEVER skip the trial run because the spec "is clear".** The trial tests the orchestration — collisions, prompt gaps, reward-hack pressure — which no spec review can exercise.
- **NEVER treat an adversary's "no findings" as a pass by itself.** Require what it checked (its self-commitment + deterministic sweep results); silence without receipts is a stall, not a verdict.

## References

| File | Load when | Do NOT load |
|---|---|---|
| [`references/spec-template.md`](references/spec-template.md) | Phase 1, every pipeline run | — |
| [`references/fleet-economics.md`](references/fleet-economics.md) | Sizing/costing a fleet; any non-default tier choice | Posture-only turns |
| [`references/evidence.md`](references/evidence.md) | User asks "why" / wants citations | Normal runs — the numbers above are already the distillation |
