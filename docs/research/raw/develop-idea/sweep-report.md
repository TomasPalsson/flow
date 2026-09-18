# Pre-spec idea development in AI coding-agent spec pipelines: cited report

## How confidence is marked

- **H**: a checker re-fetched the primary source in this sweep and it matched, often word for word.
- **M**: a primary source that was not re-fetched, but two or more angles agree, or it is on the same page as a claim that was verified.
- **L**: one angle only and not verified, a secondary or practitioner source, or reasoning by this report rather than a finding from a source.
- **DROPPED / CORRECTED**: a checker contradicted the claim, or the angles disagreed and the conflict is settled here.

Coverage: the checkers re-fetched about 20 claims, nearly all of them framework docs and product-discovery sources. Only one of the LLM-ideation papers was verified (Anderson et al.). Read Section 2 with that in mind.

---

## Bottom line

1. **Agent frameworks fall into three groups.**
   - **Interview-first.** GSD, Anthropic's "interview me", grill-me and interview-me assume the user already has an intent and pull it out one question at a time.
   - **Spec-first, no idea stage.** Core spec-kit, Kiro and OpenSpec start at the spec.
   - **Divergent idea stage with its own artifacts.** Only BMAD separates open-ended ideation, a problem-framing brief and the requirements document into three steps.
   - Superpowers sits in between. It diverges on approaches (2-3 options) but not on the problem, and it hands off a design rather than an idea brief.
2. **An interview alone does not fit a user with only a sliver of an idea.** An interview converges on an intent that must already exist. With a sliver, the pipeline first needs a divergent step that the user closes, then a convergent step that fills a small fixed set of fields.
3. **Evidence that "diverge, then converge" gives better ideas with LLMs is indirect.** Evidence that the model harms idea development if it proposes ideas too early, or agrees too much, is stronger and comes from several sources. The main protections are ordering and control:
   - the user states their own version first;
   - the model gives hints rather than finished solutions while ideas are still being generated;
   - the model critiques instead of agreeing;
   - only the user ends the divergent step.
4. **An idea is ready for a spec when it has eight fields:** problem, whose problem (as a situation), current alternative, desired outcome, riskiest assumption, appetite, no-gos, and open rabbit holes. Agent frameworks' hand-off artifacts usually cover problem, user, success and scope. They almost never record the riskiest assumption, the appetite or the current alternative.
5. **The hand-off should be a small file on disk, not a transcript.** It needs:
   - decisions with IDs and rationale;
   - items marked deferred or left to the agent's discretion;
   - open questions;
   - out-of-scope items;
   - rejected options kept in a separate addendum.

   The next stage reads the file and asks only for corrections. It should never re-run the interview.

---

## 1. Frameworks: is there an idea stage separate from the requirements interview, and what does it hand on?

### obra/superpowers `brainstorming`

- **Older version (superpowers-skills v2.2.0).**
  - It triggers "when partner describes any feature or project idea, before writing code or implementation plans". **H**
  - It runs five phases: Understanding (one question at a time about purpose, constraints and success criteria), Exploration (2-3 approaches with trade-offs), Design Presentation (sections of 200-300 words, each followed by "Does this look right so far?"), Worktree Setup, and Planning Handoff to the Writing Plans skill. **H**
  - It lets the user go back to an earlier phase: "Go backward when needed - flexibility > rigid progression." **H** [1]
  - The file names no single output document or schema. **H** [1]
- **Current version (obra/superpowers).**
  - It is a hard gate: no implementation skill, code or scaffolding until the user approves. **H**
  - It writes `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` with the sections architecture, components, data flow, error handling and testing. **H**
  - It reviews its own draft (placeholder scan, consistency check, scope check), then says "Invoke the writing-plans skill… Do NOT invoke any other skill." **H** [2]
- **Settled conflict:** the angles disagreed on whether Superpowers names an output file. Both are right for their version. The older skill names none; the current one writes a dated design doc.
- **Classification (this report's reading, L):** it separates idea from implementation, not idea from requirements. It diverges on how to build, not on what the problem is. The hand-off is a design, with no problem-framing fields.

### get-shit-done (GSD)

- **Intake:** `/gsd-new-project` runs before `/gsd-discuss-phase`. It asks about the idea, starts research agents in parallel, and writes `PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json` and a `research/` directory. **H** [3]
- **DROPPED:** one angle said this step also produces `CLAUDE.md`. The checker found no such file in the file-structure reference of either the archived repo or its successor.
- **How the intake questions:** it asks "until it understands your idea completely (goals, constraints, tech preferences, edge cases)". **M** [4]
- **`/gsd-discuss-phase`:**
  - It has two modes: `discuss` (open questions, one at a time) and `assumptions` (reads the code base, states its assumptions, and asks the user only for corrections). **H**
  - It writes `CONTEXT.md` with numbered decisions (`D-01`, `D-02` …) and opt-out tags: Claude's Discretion, `[informational]`, `[folded]` and `[deferred]`. **H**
  - A "translation gate" in the plan phase checks that every decision appears in the plan's must_haves, truths or body. **H** [3]
  - It also writes `{phase}-DISCUSSION-LOG.md` as an audit trail. **L**, one angle, not re-fetched [4]
- **Design rationale:** GSD's docs present the stage split as a fix for "context rot", with state kept in files and fresh context for each unit of work. **M** [3]
- **Repo note:** `gsd-build/get-shit-done` is now an archived stub that points to `open-gsd/gsd-core`. The cited docs still load but may go stale.
- **Classification (L):** the idea intake and the requirements step are the same command, and the output goes straight to `REQUIREMENTS.md`. The only separate stage is the later per-phase decision capture. GSD has no divergent step.

### BMAD-METHOD

- **Analyst agent ("Mary"):** "market research, competitive analysis, requirements elicitation… translating vague needs into actionable specs." **H**
  - **CORRECTED citation:** that quote is in `skills/bmad-agent-analyst/SKILL.md`, not in the cited `bmad-product-brief/SKILL.md`. Mary's menu (`customize.toml`) links the two files.
- **Product brief (`bmad-product-brief`):**
  - Modes are Create, Update and Validate. Discovery (landscape, comparables, stakes) comes before drafting. **H**
  - The output is `brief.md`: 1-2 pages, with YAML frontmatter (title, status, created, updated). **H**
  - It also writes a `.memlog.md` audit trail and an `addendum.md` for personas, rejected alternatives, technical constraints and sizing. **H** [5]
- **Brief template:** Executive Summary, The Problem, The Solution, What Makes This Difference, Who This Serves, Success Criteria, Scope, Vision. **M** [6]
- **Brainstorming session:** the Analyst guides the user toward "100 or more ideas" and switches creative technique from time to time so ideas do not cluster. The output is a self-contained `brainstorm.html` plus an optional `brainstorm-intent.md` for later skills. Both come before the brief and the PRD. **M** (two angles agree, not re-fetched) [7]
  - One angle calls the brief command `create-project-brief`, an older name. The current skill name is `bmad-product-brief`. **L**
- **Classification (L):** this is the only framework in the set that separates divergent ideation (`brainstorm.html`), a problem-framing brief (`brief.md`) and requirements (PRD).

### GitHub spec-kit

- **Constitution:** `/speckit.constitution` writes `.specify/memory/constitution.md`: principles with rationale, governance rules, a semantic version, and a Sync Impact Report. It records project principles, not an idea. **H** [10]
- **Specify:** `/specify` records "the what and why", not the tech stack. **H** [10]
- **Clarify:** `/speckit.clarify` runs after the spec is written.
  - It scans a fixed list of categories: scope, data model, UX flows, non-functional attributes, integrations, edge cases, constraints, terminology, completion signals.
  - It asks at most 5 questions, each answerable by a 2-5 option multiple choice or a phrase of 5 words or fewer.
  - It writes answers straight into a dated `## Clarifications` section, then updates the spec. **H** [9]
- **Pipeline shape (CORRECTED):** one angle called it "five-stage" and another left out `clarify`. The live reference lists constitution → specify → clarify → plan → checklist → tasks → analyze → implement → converge. **H** [10]
- **Idea Assessment (community extension, optional):** adds intake → research → define → shape → decide for raw ideas, and ends in a go / clarify / kill verdict that feeds `/specify`. **H** (corroborated) [10]
- **Classification:** core spec-kit has no idea stage. Clarification catches under-specified ideas after the spec is written.

### AWS Kiro

- **Stages:** Requirements (EARS: "WHEN [event] THE SYSTEM SHALL [behavior]") → Design → Tasks. **H** [12]
- **Stated fit:** feature specs work best when "you know the behavior of the system you want to build" and are "not ideal for exploratory coding without clear goals". **H** [12]
- **Vibe session:** a free-form "vibe session" can end with "Generate spec", after which the user reviews `requirements.md`, `design.md` and `tasks.md` one at a time. **L-M** [11]
- **Classification:** no idea stage. Kiro says itself that the idea must already be clear before its pipeline starts.

### OpenSpec

- **First artifact:** `proposal.md` has no dependencies. Its sections are Intent, Scope (including what is out of scope) and Approach. Specs and design both depend on it. **M** [13]
- **`/opsx:explore`:** "a no-stakes thinking partner … before any code gets written". It is conversation only and saves no artifact. **M-L** [14]
  - **Settled conflict:** one angle said OpenSpec has no ideation stage, another said it does. Both hold: there is an explore mode, but it leaves no artifact.
- **Workflow style:** "fluid not rigid". Any artifact can be updated at any time, with no phase gates. **L-M** [14]

### Anthropic, Claude Code best practices

- **The interview:** for larger features, ask Claude to "interview me in detail using the AskUserQuestion tool… technical implementation, UI/UX, edge cases, concerns, and tradeoffs… Keep interviewing until we've covered everything, then write a complete spec to SPEC.md". **H** [15]
- **The hand-off:** "start a fresh session to execute it. The new session has clean context focused entirely on implementation, and you have a written spec to reference." **H** [15]
- **What makes a spec useful:** the most useful specs are self-contained. They "name the files and interfaces involved, state what is out of scope, and end with an end-to-end verification step." **H** [15]
- **Related guidance on the same page:** keep modified files and test commands through compaction by saying so in CLAUDE.md, and work in the order Explore → Plan → Implement → Commit. **M** [15]
- **Classification (L):** one angle's headline called this an idea stage. This report treats it as a requirements interview, because the questions it prescribes are about implementation and edge cases. The stage boundary it defines is spec session → implementation session.

### Matt Pocock, `grill-me`

- **How it runs:** in rounds, each covering "every question whose prerequisites you have already settled". It ends when "the frontier is empty". **H** [16]
- **What it leaves behind:** "it writes no files and leaves no workspace behind… the only thing it leaves is a sharper version of the idea, in your head." **H** [16]
- **The failure it names:** "The failure mode is passivity: answering 'agreed, agreed, agreed' for forty questions and coming out with a plan the agent wrote and you nodded at." Also: "A session with no pushback from you is a session you didn't need." **H** [16]
- **Details from other sources:** it proposes a recommended default answer for each question. **M** (two unverified sources agree) [17][18] Sessions last about 45 minutes. **L** [17] It was inspired by Thariq Shihipar's practice of having an agent interview its user. **L** [18]

### Addy Osmani, `interview-me`

- **When it triggers:** a request is missing who, why, a success measure or a binding constraint, or it is "conventional but unspecific". **H** [19]
- **How it runs:**
  - It states a hypothesis with a confidence percentage.
  - It asks one question per turn, with its own guess attached.
  - It probes for things the user thinks they "should want" with "If you didn't have to justify this, what would you actually want?"
  - It stops at about 95% confidence, defined as "Can I predict the user's reaction to the next three questions I would ask?" **H** [19]
- **What it hands on:**
  - A restatement with six fields: Outcome, User, Why now, Success, Constraint, Out of scope. **H**
  - It needs an explicit "yes"; "sounds good" or silence is not enough. **H**
  - It feeds the `spec-driven-development` or `idea-refine` skills. **H** [19]
- **Why "Out of scope" is required:** it targets silent disagreement about what is not being built. **M**, the checker confirmed the substance but not the exact wording [19]
- **Other details:** the result can optionally be saved to `docs/intent/[topic].md`. **M** The skill should not run in CI or autonomous loops. **L-M** [19] Osmani calls grill-me "the reference implementation". **L-M** [20]

### Summary across frameworks (this report's reading, L)

- Only BMAD diverges on the problem.
- Superpowers diverges on the solution.
- The interview skills and GSD converge on an intent that must already exist.
- None of the hand-off artifacts records an **appetite**. None records a **riskiest assumption**. Only BMAD comes near a **current alternative**, through "What Makes This Difference" and the addendum's rejected options.

---

## 2. Evidence on "diverge, then converge" with LLMs

### Does expanding before narrowing give better ideas?

The evidence in this sweep is indirect, and none of it comes from coding agents specifically.

- **Timing matters.** Bringing the LLM in only after a period of human ideation made participants' ideas less similar to the LLM's own. It also raised their sense of autonomy, ownership and creative self-efficacy. Bringing the model in too early "introduces fixed logical paths", which the authors compare to design fixation. **M-L**: two angles describe compatible findings, not re-fetched [23]
- **Deliberate divergence is a design choice, but untested against a baseline.** An ECIS 2024 design-science system split ideation into divergent and convergent phases. Ten expert interviews found it useful, but the paper measures no gain over a converge-only baseline. **L** [29]
- **Removing divergence guardrails caused rushing in the field.** BMAD issue #1249: after a refactor, brainstorming agents felt "in a hurry to finish", and one user wrote "I thought the agents were bullying me to wrap it up". The root cause was the loss of the goal of 100 ideas in 60 minutes, the rule to continue "until the user indicates they want to move to convergent phase", the periodic checkpoints and the exploration gate. All of these were folded into one "[C] Continue - Organize ideas" option. **H** [8]
- **Divergent ability is its own capability.** On LiveIdeaBench, divergent idea generation is "poorly predicted by standard metrics of general intelligence". A strong coding model is not automatically good at this. **L** [28]

### Do sycophancy and early convergence harm idea development?

Yes, and this evidence is more consistent.

- **Homogenization.** Anderson, Shah & Kreminski (Creativity & Cognition 2024, N=36) compared ChatGPT with a creativity-support tool that does not use an LLM.
  - ChatGPT users' ideas were **less semantically distinct from one another** across users, although they produced more ideas with more detail. **H**
  - ChatGPT users felt less personal responsibility for their ideas. **H**
  - The authors attribute this partly to the low "inferential distance" between the model's output and a finished-looking idea. **H** [22]
  - The effect is between users, not within one user's session, and the authors propose ambiguous outputs, cliché alerts and diversity-favouring decoding as countermeasures. **M-L**: from the one angle that also misreported N as 33 [22]
  - "Users felt more creative" was **not confirmed**.
- **Less independent creativity afterwards.** Kumar et al. (CHI 2025, about 1,100 participants): LLM help raised creativity while it was available, but did not carry over to later unassisted tasks. For divergent thinking, earlier LLM exposure sometimes *lowered* originality and diversity. **M**: two angles agree, not re-fetched [21]
- **Sycophancy narrows exploration.** "Invisible Saboteurs" (Bo et al., CHI 2026): when the model agrees with a novice's initial idea, the novice narrows exploration too early and relies on the model more. High-sycophancy versions caused significantly more over-reliance. **M-L** [25]
- **Anchoring to familiar products.** A 2025 review: AI-assisted ideas tend to look like existing products, and AI help during ideation caused fixation in at least one study. Its guidance: offer "hints and not solutions during early ideation", and step in when the human is stuck or saturated. **M-L**, secondary review [24]
- **Homogenization seen at larger scale:**
  - In about 2,200 college-admissions essays, human essays grew the collective pool of ideas 2-8x faster than GPT-4 essays, and the gap persisted after prompt and parameter changes. **L** [27]
  - Groups of LLM agents lose diversity through the interaction structure; deference to a "senior" agent suppresses it most. **L** [26]

### How to keep the model from replacing the user's idea

These are the mechanisms named in the sources. How they fit together is this report's synthesis. **L**

1. **User first, model second.** Record the user's idea in their own words before the model generates anything [23]. That record is also the baseline for checking later whether the idea drifted.
2. **Hints, not solutions, during divergence** [24]. Superpowers offering 2-3 contrasting approaches [1] is a milder version of this.
3. **Guesses belong to convergence, not divergence.** Interview-me and grill-me attach the agent's guess or recommended answer to every question [17][19]. That is efficient for converging on an intent. During divergence it creates exactly the anchoring and homogenization the research describes [22][24].
4. **Build in critique, not agreement** [25]. This includes requiring pushback ("a session with no pushback… you didn't need") [16] and probing for what the user thinks they "should want" [19].
5. **Only the user ends divergence** [8]. Confirmation must be an explicit "yes" [19].

---

## 3. What a raw idea needs before it is ready for a spec

The five frameworks agree closely. The table maps each field to its sources. The last column shows which agent frameworks capture it (the gaps are this report's analysis, L).

| Field | Product-discovery sources | Agent frameworks that capture it |
|---|---|---|
| **Problem, stated without the solution** | Shape Up pitch "Problem" [30] **H**. PR/FAQ problem paragraph [32] **H**. Maurya warns against "innovator bias" and says to "make your case for problems without relying on your solution" [34] **M** | BMAD brief, interview-me Outcome, OpenSpec Intent |
| **Whose problem, as a situation** | Lean Canvas: Customer Segment and Problem come first, because if they are wrong "everything else… falls apart" [34] **M**. Christensen: the job is causal, not demographic; "the customer is rarely buying what the company thinks it's selling" [37] **H**. Job stories use "When [situation]…" instead of a persona [40] **L**. Torres: an opportunity is "an unmet customer need, pain point, or desire" [31] **H** | BMAD "Who This Serves", interview-me User (a persona, not a situation) |
| **Current alternative** | Lean Canvas "Existing Alternatives" [36] **L**. The milkshake's competition is "bananas and bagels" [38] **M**. Forces of Progress: Push, Pull, Anxiety, Habit [39] **M-L**. PR/FAQ internal FAQ covers alternatives [32] **H** | Mostly missing. Only BMAD, partly |
| **Desired outcome / success signal** | Torres's tree root is the outcome [31] **H**. PR/FAQ success assumptions [32] **H** | interview-me Success, BMAD Success Criteria |
| **Riskiest assumption** | PR/FAQ: "What are the top three reasons this product will not succeed?" [32] **H**. Torres's assumption tests [31] **H**. Lean Canvas: rank assumptions by "if this is wrong, does the business die?" [36] **L**. "If you can't name a real person with a real pain, stop here" [35] **L-M** | **Missing everywhere** |
| **Appetite** | Shape Up: "the amount of time we want to spend… as opposed to an estimate", set *before* the solution is designed [30] **M+** | **Missing everywhere** (interview-me's Constraint comes closest) |
| **No-gos** | Shape Up: "anything specifically excluded… to fit the appetite or make the problem tractable" [30] **M+** | interview-me Out of scope, OpenSpec Scope, Anthropic "state what is out of scope" [15] **H** |
| **Rabbit holes / open unknowns** | Shape Up: parts "too unknown, complex, or open-ended to bet on", named before committing [30] **M+** | GSD `[deferred]` tag, partly |

A Shape Up pitch is made of exactly these five ingredients: Problem, Appetite, Solution, Rabbit Holes, No-gos. **H** [30]

**Proposed readiness rule (L, synthesis):** the idea is ready for a spec when:

- all eight fields have values, with "unknown, test by X" allowed for the riskiest assumption and the rabbit holes;
- the user has explicitly said "yes" to the restatement [19];
- the problem and the "whose problem" fields can be stated without naming the solution [34].

Maurya's rule "if you can't name a real person with a real pain, stop here" is the natural way to kill an idea at this stage [35].

---

## 4. Failure modes at the hand-off from ideation to spec, and artifacts that prevent them

| Failure | Evidence | Artifact shape that prevents it |
|---|---|---|
| **Context lost between sessions or after a context reset** | Agents keep no memory across sessions: API calls are stateless and nothing is saved by default [41] **L**. GSD's stated design goal is to stop context rot [3] **M**. Grill-me writes no file, so a later session has nothing to resume from (an inference from [16], **L**) | A file on disk written while the session still has full context [44] **L**. Anthropic: write SPEC.md, then open a fresh session [15] **H** |
| **Re-asking settled questions** | Same mechanism as above [41] **L** | GSD `assumptions` mode: the next stage states what it believes and asks only for corrections [3] **H**. spec-kit writes each answer straight into a dated `## Clarifications` section [9] **H** |
| **Silently re-deciding a settled decision** | "we decided to use Postgres instead of DynamoDB" gets buried, and a fresh model recommends DynamoDB again [45] **L** | Decisions with IDs and rationale: GSD `D-01` [3] **H**; `DEC-001`, `CONSTRAINT-XXX`, `Q-XXX`, annotated rather than rewritten [42] **L**. GSD's translation gate checks every decision lands in the plan [3] **H**. Rejected options go in an addendum (BMAD `addendum.md`) [5] **H** |
| **Locking decisions or scope too early** | BMAD #1249 [8] **H**. Sycophancy narrows exploration [25] **M-L**. Kiro is "not ideal for exploratory coding" [12] **H** | Mark maturity explicitly: GSD `[deferred]` and Claude's Discretion [3] **H**; Shape Up rabbit holes kept separate from no-gos [30] **M+**; Superpowers "go backward when needed" [1] **H**; OpenSpec lets any artifact be updated [14] **L-M** |
| **Dumping the whole conversation into the next stage** | "context dump fallacy": raw conversation adds noise and loses the reasoning behind decisions [45] **L** | A selective artifact: decisions and current state, not the back-and-forth [45] **L**. A typed schema: goal, state, evidence, unresolved questions [43] **L**. Transcripts go to a separate audit log (BMAD `.memlog.md` [5] **H**; GSD `DISCUSSION-LOG.md` [4] **L**) |
| **The agent's plan passed off as the user's** | grill-me's "agreed, agreed, agreed" [16] **H**. Users felt less responsible for ChatGPT-assisted ideas [22] **H** | An explicit "yes" to a restatement of the fields [19] **H**, plus the user's original wording kept verbatim in the artifact (L) |

**Recommended hand-off artifact (L, synthesis of the verified patterns above):** one short idea brief on disk. BMAD's brief is 1-2 pages; Augment suggests 100-200 lines [42]. It holds:

- **Header:** status and date [5].
- **The user's original idea, word for word.**
- **The eight fields from Section 3.**
- **Decisions:** `D-NN`, each with rationale and a tag of settled, deferred or discretion [3].
- **Open questions:** `Q-NN`.
- **Out of scope / no-gos.**
- **Pointers:** to an addendum (rejected options, personas) and to an audit log (the transcript), neither loaded by default [5].

The spec stage then:

1. reads the brief;
2. restates what it takes to be settled and asks only for corrections [3];
3. never re-asks a question the brief already answers;
4. checks that every `D-NN` appears in the spec before it finishes [3].

---

## Corrections and conflicts settled

- **GSD `/gsd-new-project` producing `CLAUDE.md`:** DROPPED as unsupported.
- **BMAD's Analyst quote:** comes from `skills/bmad-agent-analyst/SKILL.md`, not the cited product-brief file.
- **spec-kit's pipeline:** it is not "five-stage", and not specify → plan → tasks → implement. The live docs list nine stages, including clarify, checklist, analyze and converge.
- **Superpowers' output artifact:** the older skill names no file; the current skill writes a dated design doc. Both are correct for their version.
- **Whether OpenSpec has an idea stage:** there is an explore mode, but it saves no artifact.
- **Anderson et al. sample size:** N=36, not 33. "Felt more creative" is unconfirmed.
- **Kumar et al. dates:** the angles gave three dates. arXiv 2410.03703 is the stable identifier, published at CHI 2025.
- **Classification of Anthropic's "interview me":** reclassified from an idea stage to a requirements interview (this report's reading).

## Gaps

- No controlled study in this set shows that "diverge, then converge" gives *better quality* ideas in an LLM or coding-agent pipeline. The support for it is indirect: timing and homogenization studies, and field evidence from BMAD #1249.
- Only one of the nine LLM-ideation papers was re-fetched. The arXiv IDs in [23], [25], [26] and [28] are the kind of detail most prone to citation drift.
- Two topics were not researched: GSD's `questioning` reference, and Osmani's `idea-refine` skill (the likely divergent partner to interview-me).
- Every source on hand-off failures is a secondary practitioner piece. Their patterns match verified primary designs (GSD `D-01`, spec-kit dated clarifications), but no empirical evaluation exists here.

## References

1. obra/superpowers-skills, brainstorming SKILL.md (v2.2.0): https://github.com/obra/superpowers-skills/blob/main/skills/collaboration/brainstorming/SKILL.md
2. obra/superpowers, brainstorming SKILL.md (current): https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md
3. GSD USER-GUIDE.md (archived; successor open-gsd/gsd-core): https://github.com/gsd-build/get-shit-done/blob/main/docs/USER-GUIDE.md
4. GSD COMMANDS.md: https://github.com/gsd-build/get-shit-done/blob/main/docs/COMMANDS.md
5. BMAD bmad-product-brief SKILL.md (+ skills/bmad-agent-analyst/SKILL.md): https://github.com/bmad-code-org/BMAD-METHOD/blob/main/skills/bmad-product-brief/SKILL.md
6. BMAD brief template: https://github.com/bmad-code-org/BMAD-METHOD/blob/main/skills/bmad-product-brief/assets/brief-template.md
7. BMAD, Run a brainstorming session: https://docs.bmad-method.org/how-to/workflows/run-brainstorming-session/
8. BMAD issue #1249: https://github.com/bmad-code-org/BMAD-METHOD/issues/1249
9. spec-kit clarify.md: https://github.com/github/spec-kit/blob/main/templates/commands/clarify.md
10. spec-kit repo, constitution.md and reference docs: https://github.com/github/spec-kit
11. Kiro spec best practices: https://kiro.dev/docs/specs/best-practices/
12. Kiro feature specs: https://kiro.dev/docs/specs/feature-specs/
13. OpenSpec concepts: https://github.com/Fission-AI/OpenSpec/blob/main/docs/concepts.md
14. OpenSpec repo: https://github.com/Fission-AI/OpenSpec
15. Claude Code best practices: https://code.claude.com/docs/en/best-practices
16. Pocock, grill-me: https://www.aihero.dev/skills-grill-me
17. Pocock, "My grill-me skill has gone viral": https://www.aihero.dev/my-grill-me-skill-has-gone-viral
18. mattpocock/skills grill-me SKILL.md: https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md
19. Osmani, interview-me SKILL.md: https://github.com/addyosmani/agent-skills/blob/main/skills/interview-me/SKILL.md
20. Osmani, agent-skills comparison.md: https://github.com/addyosmani/agent-skills/blob/main/docs/comparison.md
21. Kumar et al., CHI 2025: https://arxiv.org/abs/2410.03703
22. Anderson, Shah & Kreminski, C&C 2024: https://arxiv.org/abs/2402.01536
23. AI-assisted ideation timing, CHI 2025: https://arxiv.org/pdf/2502.06197
24. Li et al., LLM-assisted ideation review (2025): https://arxiv.org/abs/2503.00946
25. Bo et al., "Invisible Saboteurs", CHI 2026: https://arxiv.org/pdf/2510.03667
26. Chen et al., "Diversity Collapse in Multi-Agent LLM Systems" (2026): https://arxiv.org/abs/2604.18005
27. Human vs GPT-4 essay homogenization: https://www.sciencedirect.com/science/article/pii/S294988212500091X
28. LiveIdeaBench: https://arxiv.org/abs/2412.17596
29. ECIS 2024, divergent/convergent LLM agent system: https://aisel.aisnet.org/ecis2024/track20_adoption/track20_adoption/13/
30. Shape Up, ch. 6, Write the Pitch: https://basecamp.com/shapeup/1.5-chapter-06
31. Torres, Opportunity Solution Trees: https://www.producttalk.org/opportunity-solution-trees/
32. Working Backwards PR/FAQ: https://workingbackwards.com/resources/working-backwards-pr-faq/
33. Working Backwards PR/FAQ process: https://workingbackwards.com/concepts/working-backwards-pr-faq-process/
34. Maurya, "Reorder your chain of beliefs": https://ashmaurya.com/blog/reorder-your-chain-of-beliefs-with-a-leaner-lean-canvas
35. Maurya, Lean Canvas fill order: https://medium.com/lean-stack/what-is-the-right-fill-order-for-a-lean-canvas-f8071d0c6c8c
36. LeanSpark, Lean Canvas: https://leanspark.ai/leancanvas
37. Christensen on JTBD: https://jobstobedone.org/radio/clay-christensen-on-jobs-to-be-done/
38. Christensen Institute, JTBD: https://www.christenseninstitute.org/theory/jobs-to-be-done/
39. Forces of Progress: https://jobstobedone.org/radio/unpacking-the-progress-making-forces-diagram/
40. Job stories: https://learningloop.io/glossary/job-stories-jtbd
41. Augment, why agents repeat questions: https://www.augmentcode.com/guides/why-ai-agents-repeat-questions
42. Augment, session-end spec update: https://www.augmentcode.com/guides/session-end-spec-update-ai-agents
43. dev.to, Handoff: https://dev.to/shubham399/handoff-give-the-next-ai-agent-the-context-it-actually-needs-pnb
44. O'Reilly Radar, "Your AI agent already forgot half": https://oreillyradar.substack.com/p/your-ai-agent-already-forgot-half
45. MindStudio, context rot and session hand-off: https://www.mindstudio.ai/blog/context-rot-ai-agents-session-handoff-fix