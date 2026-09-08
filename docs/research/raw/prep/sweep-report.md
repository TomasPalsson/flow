# Designing `/flow:prep` — Research Report

**Scope:** six angles, 60 claims, of which 26 were re-fetched and verified against primary sources. Confidence tags per claim: **[VERIFIED]** = quoted text re-fetched and matched verbatim; **[PARTIAL]** = source real and substance correct, but the quotation or a detail drifted; **[UNVERIFIED]** = source located and plausible, content not independently re-fetched in this pass; **[CORRECTED]** = claim as originally stated is wrong, corrected text given; **[DO NOT CITE]** = load-bearing error, would mislead a design decision.

---

## 1. Prior art: how existing frameworks do the pre-spec step

The finding that matters for `/flow:prep`: six independently-built frameworks converged on the same three levers — **serial questioning, a hard question budget, and a decisions artifact (not a transcript) handed forward**.

### obra/superpowers `brainstorming`
Source: https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md

- **[VERIFIED]** Serial cadence, verbatim: *"Only one question per message - if a topic needs more exploration, break it into multiple questions."*
- **[VERIFIED]** Three-path classification runs *before* any design work: **Spike** (*"a feasibility question ... whose output is an answer, not code you keep"*), **Bounded** (*"a well-scoped change to code that already exists in this repo"*), **Architectural** (*"new projects, new subsystems, changes that restructure how components fit together or alter interfaces others depend on"*).
- **[VERIFIED]** Scope gate, verbatim: *"YAGNI ruthlessly - remove unnecessary features from every approach and design"* and *"The gate is the approval, not the design's length. Present, then stop until you hear yes."*
- **[VERIFIED]** Hand-off is a hard chaining rule, not advice: *"Architectural: the ONLY skill you invoke after brainstorming is writing-plans — never frontend-design, mcp-builder, or any other implementation skill."* Bounded work verbatim skips plan docs (*"after approval, implementation proceeds directly through the normal development workflow; no plan document"*); spikes terminate in *"a reported recommendation."*
- **[VERIFIED]** Also verbatim: *"Don't propose unrelated refactoring. Stay focused on what serves the current goal."*
- **[PARTIAL]** The pre-handoff self-review pass is real (placeholder scan, internal-consistency pass, scope check — *"focused enough for a single implementation plan"* is verbatim, as is *"Fix any issues inline. No need to re-review — just fix and move on."*). But the quoted ambiguity-check phrase *"resolves interpretations into explicit requirements"* **is fabricated**. Actual text: *"Ambiguity check: Could any requirement be interpreted two different ways? If so, pick one and make it explicit."* Substance identical; do not quote the former.
- **[VERIFIED]** Decomposition happens upstream, not downstream: *"If the project is too large for a single spec, help the user decompose into sub-projects... Each sub-project gets its own spec → plan → implementation cycle."*

### superpowers `writing-plans` (the consumer)
Source: https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md

- **[VERIFIED]** The plan writer trusts the upstream artifact rather than re-interviewing: it copies *"the spec's project-wide requirements — version floors, dependency limits, naming and copy rules, platform requirements — one line each, with exact values copied verbatim from the spec"* into a **Global Constraints** block.
- **[VERIFIED]** Re-scoping is explicitly not the plan writer's job: if the spec spans multiple subsystems, *"it should have been broken into sub-project specs during brainstorming."*
- **[PARTIAL]** The no-placeholder ban is real (`"TBD"`, `"TODO"`, `"Similar to Task N"`, steps that say what to do without showing how) but the commonly-circulated one-line quote splices non-adjacent bullets and drops two intervening items. Cite as a list, not a sentence.

### get-shit-done (gsd) `discuss-phase` → CONTEXT.md
Sources: https://github.com/gsd-build/get-shit-done/blob/main/commands/gsd/discuss-phase.md, https://raw.githubusercontent.com/open-gsd/gsd-core/next/docs/reference/context-md.md, https://raw.githubusercontent.com/open-gsd/gsd-core/next/docs/how-to/discuss-a-phase.md

- **[VERIFIED]** The purpose statement, verbatim: *"Extract implementation decisions that downstream agents need — researcher and planner will use CONTEXT.md to know what to investigate and what choices are locked."*
- **[VERIFIED]** The consumption contract, verbatim: *"When you run /gsd-plan-phase next, the planner reads CONTEXT.md to know which decisions are locked. It will not re-ask questions already answered here."* This single sentence is the clearest statement in any of the six frameworks of what a prep artifact is *for*.
- **[PARTIAL]** The claim that discuss-phase loads PROJECT.md/REQUIREMENTS.md/STATE.md to avoid re-litigating settled points, identifies phase-specific "gray areas" (layout/density for visual work; response format/error handling for APIs), and can derive *"a minimal CONTEXT.md"* straight from the roadmap goal — the substance is described in the docs but these specific phrasings were **not found verbatim**. Treat as paraphrase.
- **[CORRECTED]** CONTEXT.md schema: **7 blocks, not "six/eight"** — `<domain>`, optional `<spec_lock>`, `<decisions>` (IDs like `D-01`, `D4-01`, `D-INFRA-01`), `<canonical_refs>`, `<code_context>`, `<specifics>`, `<deferred>`. And critically: **CONTEXT.md carries no YAML frontmatter.** The source explicitly says so — *"CONTEXT.md carries no YAML frontmatter. Metadata is inline at the top of the body."* The `Gathered` date and `Status: Ready for planning` are inline bold-text lines.
- **[UNVERIFIED]** The three-way partition reported by a third-party walkthrough (https://docs.bswen.com/blog/2026-04-21-gsd-discuss-phase-workflow/): **Decisions** (`D-01`, *"MUST be implemented exactly as specified"*), **Deferred Ideas** (*"MUST NOT appear in plans"*), and **Claude's Discretion** (planner free to judge — empty-state copy, ordering, breakpoints). Secondary source, not re-fetched. **This is the single most transferable idea in the whole report** and is worth verifying against gsd-core primary docs before adopting.
- **[UNVERIFIED]** gsd-core also ships an **assumptions mode** (`workflow.discuss_mode`) that inverts the interview: read PROJECT.md + codebase first, emit assumptions *with codebase evidence and a confidence level*, and let the user only confirm/correct/expand — then *"Writes CONTEXT.md from confirmed assumptions"* in the identical schema, so downstream agents consume it *"identically regardless of which mode produced it."* Source: https://www.opengsd.net/docs/v1/user-guide (secondary).

### github/spec-kit `/speckit.clarify`
Source: https://raw.githubusercontent.com/github/spec-kit/main/templates/commands/clarify.md

- **[VERIFIED]** Hard budget, verbatim: *"Present EXACTLY ONE question at a time"* and *"Maximum of 5 total questions across the whole session."*
- **[VERIFIED]** Answerability filter: only ambiguities resolvable by 2–5 mutually exclusive options or a `<=5 words` short answer qualify. Verbatim exclusion: questions *"already answered, trivial stylistic preferences, or plan-level execution details (unless blocking correctness)."*
- **[VERIFIED]** Append-only decision log: *"Append a bullet line immediately after acceptance: `- Q: <question> → A: <final answer>`"*, under a `## Clarifications` section with a `### Session YYYY-MM-DD` subheading, saved by **atomic overwrite after each single integration** rather than batched at the end — partial progress survives a dropped session.
- **[VERIFIED]** Answers are *routed back into the spec body*, not left as a log: *"Functional ambiguity → Update or add a bullet in Functional Requirements... Data shape/entities → Update Data Model... Non-functional constraint → Add/modify measurable criteria in Success Criteria > Measurable Outcomes... Edge case / negative flow → Add a new bullet under Edge Cases / Error Handling"*, plus the anti-staleness rule *"If the clarification invalidates an earlier ambiguous statement, replace that statement instead of duplicating; leave no obsolete contradictory text."*
- **[CORRECTED]** The scan taxonomy has **10 categories, not 8**: Functional Scope & Behavior; Domain & Data Model; Interaction & UX Flow; Non-Functional Quality Attributes; Integration & External Dependencies; Edge Cases & Failure Handling; Constraints & Tradeoffs; **Terminology & Consistency**; **Completion Signals**; **Misc / Placeholders**. The circulating label "Terminology & Completion Signals" does not exist in the source.
- **[VERIFIED]** `spec-template.md` marks open questions **inline at the point of use**, not in a central list: `System MUST authenticate users via [NEEDS CLARIFICATION: auth method not specified - email/password, SSO, OAuth?]`. Resolved-vs-unresolved is encoded as marker-present vs marker-removed. Scope fences live as assumption bullets (e.g. *"Mobile support is out of scope for v1"*) — **[CORRECTED]** these are *not* individually dated; the template carries one date at the top.
- **[VERIFIED]** `spec-driven.md` philosophy: *"Specifications don't serve code—code serves specifications"* / *"Code becomes its expression in a particular language and framework."* Anti-guessing rule: *"Don't guess: If the prompt doesn't specify something, mark it."* Simplicity gate: *"Maximum 3 projects for initial implementation"*, *"Additional projects require documented justification"*, and a checklist item *"No speculative or 'might need' features."*
- **[UNVERIFIED]** `/speckit.constitution` scopes itself narrowly (*"This command's own work is limited to updating the project constitution itself"*; refuses feature/code/deploy requests) and stores principles at `.specify/memory/constitution.md`. Not re-fetched.

### BMAD-METHOD, Kiro, OpenSpec
- **[UNVERIFIED]** BMAD runs an Analyst persona ("Mary") through Brainstorming → Market Research → Competitor Analysis to a `project-brief.md` that PM/Architect agents consume; `party-mode` is a *separate*, roster-driven multi-persona roundtable (config merged from four TOML layers, named `party_groups`, four run modes, a preloaded five-lens "Code Review Crew"). Discovery here is **composable**, not a fixed interview script — the opposite pole from spec-kit's 5-question cap. Sources: https://github.com/bmad-code-org/BMAD-METHOD, https://tessl.io/registry/skills/github/bmad-code-org/BMAD-METHOD/bmad-party-mode.
- **[UNVERIFIED]** Kiro gates requirements-first: `requirements.md` in EARS form — *"WHEN [condition/event] THE SYSTEM SHALL [expected behavior]"* — with human approval between Requirements → Design → Tasks. Source: https://kiro.dev/docs/specs/feature-specs/.
- **[UNVERIFIED]** OpenSpec forces scope declaration before code: `proposal.md` states *"Intent, scope, and approach at a high level"*, and delta specs are marked **ADDED / MODIFIED / REMOVED Requirements** so a proposal that outgrows its declaration shows up as a visible mismatch in review. `openspec/specs/` (current truth) is kept separate from `openspec/changes/` (proposed deltas) so drift is detectable rather than silent. Sources: https://github.com/Fission-AI/OpenSpec/blob/main/docs/concepts.md, .../workflows.md.

---

## 2. Why agents "go ham," and what actually stops it

### Anthropic's own guidance (all **[VERIFIED]** verbatim from https://code.claude.com/docs/en/best-practices)

- The interview-then-spec workflow is Anthropic's *documented recommendation*, which is direct validation for `/flow:prep` existing at all: *"For larger features, have Claude interview you first. Start with a minimal prompt and ask Claude to interview you using the AskUserQuestion tool... Keep interviewing until we've covered everything, then write a complete spec to SPEC.md."*
- The artifact shape is specified: *"The most useful specs are self-contained: they name the files and interfaces involved, state what is out of scope, and end with an end-to-end verification step that proves the feature works."* — negative scope plus a verification step, named explicitly.
- Adversarial review is itself a documented cause of gold-plating: *"A reviewer prompted to find gaps will usually report some, even when the work is sound, because that is what it was asked to do. Chasing every finding leads to over-engineering: extra abstraction layers, defensive code, and tests for cases that can't happen. Tell the reviewer to flag only gaps that affect correctness or the stated requirements, and treat the rest as optional."*
- Plan mode as separation of concerns: *"Letting Claude jump straight to coding can produce code that solves the wrong problem. Use plan mode to separate exploration from execution."* With the escape hatch: skip planning when *"you could describe the diff in one sentence."*
- Named failure patterns: **"the infinite exploration"** (unscoped "investigate X" → hundreds of files read, context filled) and **"the trust-then-verify gap"** (plausible implementations that miss edge cases). Fixes prescribed: scope investigations narrowly; always supply verification.

### Empirical grounding

- **[VERIFIED]** *Overeager Coding Agents: Measuring Out-of-Scope Actions on Benign Tasks* (arXiv 2605.18583). Removing an explicit consent/scope declaration from the prompt raised Claude Code's measured overeager rate from **0.0% to 17.1%** on paired scenarios. Permissive frameworks (Claude Code, Codex CLI, Gemini CLI) showed 5.4–27.7% overeager rates vs 0.2–4.5% for ask-to-continue OpenHands. **[PARTIAL]** the McNemar p-value (2.4×10⁻⁴) was not independently re-derived. This is the strongest available evidence that *an explicit scope fence in the prompt is not decoration* — it is the difference between 0% and 17%.
- **[VERIFIED]** *Building to the Test: Coding Agents Deliver What You Check, Not What You Requested* (arXiv 2606.28430). Agents score near-perfectly against visible/oracle tests while leaving unrequested-but-implied functionality absent — they optimize toward the visible check, not the request. Implication for prep: the artifact must carry the *verification criterion*, or the spec step will invent one and the build step will optimize to it.
- **[UNVERIFIED]** *Towards Understanding Sycophancy in Language Models* (arXiv 2310.13548, ICLR 2024, Anthropic co-authored): five SOTA assistants produce sycophantic responses across four free-form generation tasks; both human raters and preference models sometimes prefer convincingly-written sycophantic responses over correct ones. Root-cause evidence for why an agent accepts the user's framing rather than challenging scope.
- **[UNVERIFIED]** *Sycophancy to subterfuge* (arXiv 2406.10162, Anthropic): a model trained to be sycophantic generalizes without further training to specification-gaming including reward tampering. Links agreement-seeking to gaming the success criteria.
- **[UNVERIFIED]** AskUserQuestion design rationale (https://claude.com/blog/seeing-like-an-agent, 2026-04-10): plain-text clarifying questions were slow to answer, so the tool became a structured interrupt that Claude *"seemed to like calling"* and is *"particularly prompted"* to invoke during plan mode.

**Design consequence:** the three mitigations with actual evidence behind them are (a) an explicit scope/consent declaration in the prompt, (b) a stated out-of-scope list carried into the downstream artifact, and (c) a concrete verification criterion. Vague "be concise" or "don't over-engineer" instructions have no comparable evidence.

---

## 3. Requirements-elicitation interview technique

- **[VERIFIED]** **Serial beats batched, empirically.** Nosek, Sriram & Umansky, *"Presenting Survey Items One at a Time Compared to All at Once Decreases Missing Data without Sacrificing Validity"*, PLoS ONE 2012 (https://pmc.ncbi.nlm.nih.gov/articles/PMC3355147/). One-at-a-time cut missing data roughly in half (completion 68% → 79.2% in one experiment), preserved internal consistency and criterion validity, and was modestly *faster*. This is the closest empirical support for the one-question-per-turn rule, though it is survey methodology, not interviewing.
- **[UNVERIFIED, and it cuts the other way]** Practitioner counter-evidence: Laura Brandenburg (Bridging the Gap, https://www.bridging-the-gap.com/what-questions-do-i-ask-during-requirements-elicitation/) explicitly avoids delivering a prepared list *"one-by-one"*, preferring core questions that open discussion so remaining questions get answered indirectly — and warns that repeated literal "why" questioning (naive five-whys) triggers stakeholder defensiveness. **Do not present serial questioning as unambiguously optimal**; the honest position is that serial helps *data quality* while feeling worse to a human at high question counts.
- **[VERIFIED]** **Stopping rule has an empirical anchor.** Guest, Bunce & Johnson, *"How Many Interviews Are Enough?"*, Field Methods 18(1):59–82, 2006. Code saturation by interview 12; ~80% of eventual codes present by interview 6. Grounds the "would the next answer change what I build?" convergence heuristic — and suggests a prep budget in the 6–12 question range, not 50.
- **[VERIFIED]** **Question typology is a real research object.** Zaremba & Liaskos, *"Towards a Typology of Questions for Requirements Elicitation Interviews"*, IEEE RE 2021, pp. 384–389 (https://www.yorku.ca/liaskos/Papers/RE2021/RE2021.pdf). Separates question **content**, **style**, and **objective** as independent dimensions — the academic basis for distinguishing leading vs neutral and open vs closed. (IEEE Xplore is JS-rendered/paywalled; verified via the York mirror.)
- **[CORRECTED]** **JTBD.** The HBR article is *"Marketing Malpractice: The Cause and the Cure"*, December 2005, by **Clayton M. Christensen, Scott Cook, AND Taddy Hall** — three authors; Hall is routinely omitted. The core framing (*"When people find themselves needing to get a job done, they essentially hire products to do that job for them"*) and the milkshake/commute example are confirmed in the article. **The "18-hour on-site observation" detail could not be sourced to this article** and appears only in later retellings — drop it or attribute it elsewhere.
- **[UNVERIFIED]** Bob Moesta's "Switch" interview operationalizes JTBD as a timeline reconstruction of the switching moment with push/pull/anxiety/habit "Four Forces" (https://therewiredgroup.com/case-studies/milkshakes/).
- **[UNVERIFIED]** **Quantifying adjectives.** Karl Wiegers, *"Writing Quality Requirements"* (1999, https://www.processimpact.com/articles/qualreqs.pdf) and the companion "words to avoid" list (https://www.oir.caltech.edu/twiki_oir/pub/Keck/NGAO/SystemsEngineeringGroup/Wiegers_Words_to_Avoid_Requirements.pdf): strike *friendly, easy, simple, rapid, efficient, user-friendly, intuitive* and replace with measurable criteria; every requirement must be verifiable, or whether it was implemented correctly becomes a matter of opinion rather than fact.
- **[UNVERIFIED]** **EARS** (Mavin et al., Rolls-Royce, IEEE RE'09, https://alistairmavin.com/ears/): keyword templates — *"While \<precondition\>, when \<trigger\>, the \<system\> shall \<response\>"* — as the conversion mechanism from interview answer to unambiguous requirement.
- **[UNVERIFIED]** **Negative requirements** are a distinct, commonly-omitted category; omitting them raises risk of faults surfacing in test or production (https://arxiv.org/pdf/2503.13958). This is the literature backing for a *"what should this NOT do"* probe.
- **[UNVERIFIED]** Follow-up question generation research (Shen, Singhal, Breaux, https://arxiv.org/pdf/2507.02858): good follow-ups must be clear, relevant to what was just said, and informative enough to surface tacit knowledge — the rationale for probing off the previous answer rather than from a fixed list.

---

## 4. The "grill me" prompt: origin and exact text

Author: **Matt Pocock** (TypeScript educator). All PRIMARY claims below were re-fetched.

- **[VERIFIED]** Repo `mattpocock/skills` — *"Skills for Real Engineers. Straight from my .agents directory."* — created **2026-02-03T11:15:53Z**, ~256K stars (live count drifts by the minute). https://api.github.com/repos/mattpocock/skills
- **[VERIFIED]** The original prompt text, from Pocock's own retrospective (https://www.aihero.dev/my-grill-me-skill-has-gone-viral), grepped from raw page HTML:

  > *"Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree resolving dependencies between decisions one by one. If a question can be answered by exploring the code base, explore the code base instead."*

  Plus the later addition, verbatim from the transcript: *"And the new thing that I added recently was for each question, provide your recommended answer."* — i.e. the recommend-an-answer behavior is a *speed* optimization Pocock bolted on after the fact, not part of the original.
- **[VERIFIED]** Current published `grill-me/SKILL.md` is a thin dispatcher: frontmatter `name: grill-me`, `description: "A relentless interview to sharpen a plan or design."`, `disable-model-invocation: true`, body: *"Call the Skill tool with \"grilling\"."* https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md
- **[VERIFIED via 3 independent mirrors]** Pocock on X: *"My 'grill-me' skill went viral. mattpocock/skills is up to 9K stars. Quote tweets of it are doing numbers. It's the most useful skill I've written, and I use it even outside of coding."* (x.com returned 402 to direct fetch; text corroborated across the X snippet, a LinkedIn repost, and a daily.dev mirror.)
- **[VERIFIED]** **What fails**, from https://www.aihero.dev/skills-grill-me, quoted from raw HTML:
  - Passivity is the top failure: answering "agreed, agreed, agreed" — the page distinguishes *"a session that turns an idea into decisions from one that produces confident nonsense."*
  - **Ungrillable questions** are the scope-balloon mechanism: *"Talking your way through an ungrillable question is where sessions balloon. The agent keeps rephrasing, you keep guessing, and the scope grows to fill the uncertainty."* Interaction-*feel* questions belong in a prototype, not an interview.
  - ~200 questions is the split signal: FAQ entry *"It asked me two hundred questions. What went wrong? Usually the scope was too large. Ask the agent to break the work into smaller pieces..."*
  - Three-tool family: **grill-me** (stateless, no repo), **grill-with-docs** (reads codebase, maintains CONTEXT.md), **wayfinder** (multi-session).

**Variants [UNVERIFIED — URLs return 200, content not diffed]:**
- Addy Osmani's `interview-me` (https://github.com/addyosmani/agent-skills/blob/main/skills/interview-me/SKILL.md): targets ~95% confidence in user intent via state-a-hypothesis-with-a-confidence-percentage → one question at a time *paired with a guessed answer* → probe sophistication-signaling answers ("scalable", "clean architecture") with *"If you didn't have to justify this to anyone, what would you actually want?"* → restate as Outcome/User/Why now/Success/Constraint/Out of scope → require explicit confirmation, not silence or "sounds good". Stopping rule: *"Can I predict the user's reaction to the next three questions I would ask?"*
- usirin gist (https://gist.github.com/usirin/0f01923f7b2126b0cce817f9f8d97788, 2026-03-18): depth-first decision-tree traversal, codebase research first, rotation through feasibility/dependencies/edge-cases/alternatives/scope/ordering/failure-modes, **checkpoint summary of resolved decisions and open branches every 5–8 exchanges**.
- A practitioner post frames grilling as an antidote to sycophancy — *"Plan mode assumes your idea is already sound and your only problem is execution. Most of the time, that assumption is wrong"* — and reports it fails when users leave the session, prototype mid-grill, or truncate the transcript (destroying decision rationale). **Note: this URL has a malformed-looking double-`engineering` path segment; verify before citing.**

---

## 5. Hand-off design

Three pipelines, three answers to "what does the spec step read":

| Framework | Artifact | Resolved | Unresolved | Scope fence | Discretion |
|---|---|---|---|---|---|
| spec-kit | spec.md itself | `- Q: … → A: …` log **plus** answer routed into the relevant spec section | `[NEEDS CLARIFICATION: …]` inline at point of use | Assumption bullets ("out of scope for v1") | — |
| superpowers | `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` | Architecture/Components/Data flow/Error handling/Testing, self-reviewed for placeholders | none permitted (ambiguity resolved before handoff) | YAGNI pass + sub-project decomposition | — |
| gsd | `{phase}-CONTEXT.md` | `<decisions>` with `D-NN` IDs | resolved before write | `<deferred>` | "Claude's Discretion" |

**Design lessons, ranked by confidence:**

1. **[VERIFIED]** *Route, don't just log.* spec-kit's biggest structural idea is that the clarify answer both appends to a log **and** rewrites the affected spec section, with an explicit prohibition on leaving contradictory text behind. A prep artifact that is only a Q&A transcript makes the spec writer re-derive; a prep artifact that is pre-sorted into the spec's own section names does not.
2. **[VERIFIED]** *Foreclose re-delegation.* Both superpowers (*"Do NOT invoke any other skill. writing-plans is the next step."*) and gsd (*"It will not re-ask questions already answered here."*) state the handoff as a prohibition on the downstream step, not just a description. The instruction that prevents re-interviewing lives in the **consumer**, not the producer.
3. **[VERIFIED]** *Save atomically per answer.* spec-kit's atomic-overwrite-after-each-integration means a dropped session loses one answer, not the whole interview. For a long grill, this is the difference between resumable and not.
4. **[UNVERIFIED but highest design value]** *Three-way partition, not two.* gsd's Decisions / Deferred / **Claude's Discretion** split tells the spec writer not only what is locked and what is forbidden, but where it is *authorized to decide alone*. Without that third bucket the spec writer either re-asks or silently guesses. Verify against gsd-core primary docs before adopting.
5. **[UNVERIFIED]** *Confidence-tagged assumptions are a real alternative to questions.* gsd's assumptions mode reads the codebase, emits assumptions with evidence and confidence, and asks only for confirm/correct/expand — producing the identical downstream schema. This is the structural form of "silence is acceptance," and it directly implements the grill-me rule *"If a question can be answered by exploring the code base, explore the code base instead."*
6. **[VERIFIED]** *Stable IDs.* `D-01` / `FR-006` / `Q:` lines give the spec and the eventual review something to cite. gsd supports phase-prefixed and alphanumeric variants (`D4-01`, `D-INFRA-01`).

---

## 6. Claude Code mechanics for chaining prep → spec

All from official docs, all re-fetched 2026-09-07.

- **[VERIFIED]** `disable-model-invocation: true` (https://code.claude.com/docs/en/skills) — *"Set to true to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with /name. Also prevents the skill from being preloaded into subagents."* User can invoke; Claude cannot. **Correct setting for `/flow:prep`**, which should never fire on its own mid-task.
- **[VERIFIED — AND THE ORIGINAL RESEARCH CONTAINED A REVERSED CLAIM HERE]** `context: fork` in a **skill's** frontmatter runs the skill in an isolated subagent: *"The skill content becomes the prompt that drives the subagent. It won't have access to your conversation history."* Default is background; `background: false` makes it block and return inline.
  - **[DO NOT CITE]** One claim in the source research asserted that a `context: fork` subagent *"fully inherits parent conversation state... seeing the same system prompt, tools, model, and message history."* **This is false for the skill field.** That behavior belongs to a *separate* fork **subagent type** (invoked via the Agent tool, or manually via `/subtask`, formerly `/fork`), described under "Fork the current conversation" on the sub-agents page — which explicitly disclaims any `context: fork` frontmatter field for subagents. If a design rationale reads "use `context: fork` so prep inherits everything," it is backwards.
  - Design consequence: `context: fork` on prep would **cut prep off from the conversation that motivated it** — usually wrong for an interview skill, since the user's opening description lives in that history. It is right only if prep receives everything it needs via `$ARGUMENTS`.
- **[VERIFIED]** Argument passing (https://code.claude.com/docs/en/slash-commands): `$ARGUMENTS` (full string as typed), indexed `$0`/`$1` with shell-style quoting, named `$name` declared via an `arguments:` frontmatter list, `argument-hint` for autocomplete. If a skill declares no placeholder, Claude Code **appends a line `ARGUMENTS: <raw input>`** to the end of the skill content automatically.
- **[VERIFIED]** **Skill stacking is a native chaining path**: typing two skill invocations back-to-back in one message loads both and passes trailing text as `$ARGUMENTS` to each. Before v2.1.199 only the first loaded; now Claude Code expands the first skill plus up to five more. So `/flow:prep /flow:spec <desc>` is mechanically supported — though for prep this is likely undesirable, since spec should not start until prep's artifact exists.
- **[VERIFIED]** **There is no frontmatter directive for one skill to invoke or read from another.** The closest documented mechanism is dynamic shell injection: `` !`command` `` runs before the skill content is sent to Claude and substitutes output as plain text. *"Substitution runs once over the original file... is not re-scanned for further placeholders."* So a spec skill can do `` !`cat .flow/prep/CONTEXT.md` `` to preload prep's artifact deterministically — the artifact file is the interface.
- **[VERIFIED]** `allowed-tools` grants permission for listed tools *"during the turn that invokes this skill... The grant clears when you send your next message."* The docs' own example pairs it with `disable-model-invocation: true`.
- **[VERIFIED]** AskUserQuestion (https://code.claude.com/docs/en/tools-reference): multiple-choice with an "Other" row / notes field for free text; free-text answers relayed with neutral wording including requests to wait or explain first; optional `askUserQuestionTimeout` (60s/5m/10m) auto-resolves an unanswered question so Claude proceeds on its own judgment; no permission prompt. **The timeout is effectively a built-in "silence is acceptance" mechanism** — relevant if prep wants unanswered assumptions to default rather than block.
- **[VERIFIED]** Sub-agent `skills:` frontmatter **preloads full skill content** at startup; it controls preloading, not access (subagents can still discover and invoke skills via the Skill tool). Docs call it *"the inverse of `context: fork`"*. Skills with `disable-model-invocation: true` **cannot be preloaded this way** — so a manual-only prep skill cannot be injected into a subagent by that route. To block a subagent from skills entirely, omit `Skill` from `tools` or add it to `disallowedTools`.
- **[VERIFIED]** Plugin agent frontmatter fields (https://code.claude.com/docs/en/plugins-reference): `name`, `description`, `model`, `effort`, `maxTurns`, `tools`, `disallowedTools`, `skills`, `memory`, `background`, `isolation` (only valid value `"worktree"`). Boolean fields accept `yes/no/on/off/1/0` in any case besides `true/false`. `plugin.json` `skills` and `commands` accept a string or array of paths.
- **[UNVERIFIED]** Third-party rationale for forking a step-by-step skill: an isolated context makes it harder for the agent to shortcut or skip steps, because there is no accumulated history to rationalize against (https://www.ranketai.com/en/blog/explainer-claude-code-skills-fork-subagents-2026-03-31). This is consistent with the *actual* (isolating) semantics of `context: fork`.

---

## 7. Synthesis: what the evidence says `/flow:prep` should be

**Mechanics**
- `disable-model-invocation: true` — manual-only. [VERIFIED support]
- **Do not** use `context: fork` unless prep gets its full brief via `$ARGUMENTS`; forking severs the conversation history that motivates the interview. [VERIFIED]
- Interface to `/flow:spec` is a **file on disk**, read by the spec skill via `` !`cat …` `` injection, since no skill-to-skill call exists. [VERIFIED]
- Use AskUserQuestion for the option-shaped turns; free text still routes through the Other row. Consider `askUserQuestionTimeout` only if defaulting-on-silence is wanted. [VERIFIED]

**Interview behavior**
- One question per turn. [VERIFIED cadence support from PLoS ONE 2012 + spec-kit + superpowers; **but** flag the practitioner counter-evidence — serial at high volume is what makes grill sessions feel punishing.]
- Recommend an answer with each question (Pocock's own later addition; Osmani's "paired guessed answer"). [VERIFIED for Pocock]
- Explore the codebase instead of asking whenever the answer is discoverable — this is in the original grill-me text and is the whole premise of gsd's assumptions mode. [VERIFIED / UNVERIFIED respectively]
- Budget: the saturation literature points at **6–12** substantive questions, spec-kit hard-caps at **5**, and Pocock treats **~200** as proof the scope was too big. A cap in the 5–12 range with an explicit "scope too large — split it" escape is the defensible design. [VERIFIED]
- Refuse **ungrillable** questions (interaction feel, aesthetics) — route to a prototype. This is the documented scope-balloon mechanism. [VERIFIED]
- Checkpoint every 5–8 exchanges with resolved-vs-open. [UNVERIFIED, usirin gist]
- Guard against sycophantic assent: Osmani's explicit-confirmation rule (silence and "sounds good" don't count) addresses the top reported failure. [UNVERIFIED / VERIFIED-failure-mode]

**The artifact**
- Three buckets, not two: **Decisions (locked, ID'd)** / **Deferred (must not appear)** / **Discretion (spec writer decides alone)**. [UNVERIFIED-but-high-value]
- Plus: assumptions with confidence + codebase evidence; an explicit out-of-scope list (0% → 17.1% evidence); one verification criterion (building-to-the-test evidence); and each answer pre-routed to the spec section it belongs in.
- Write atomically after each answer, not at the end. [VERIFIED]
- Put the anti-re-interview instruction in **`/flow:spec`**, not `/flow:prep`. [VERIFIED pattern from both superpowers and gsd]

---

## 8. Errata — do not propagate these

1. `context: fork` does **not** inherit parent conversation history; it isolates from it. The inheriting thing is a different feature (fork subagent type / `/subtask`).
2. spec-kit's clarify taxonomy has **10** categories; "Terminology & Completion Signals" is an invented label for two separate real ones, and "Misc / Placeholders" was dropped.
3. gsd CONTEXT.md has **7** blocks and **no YAML frontmatter** — the source says so explicitly.
4. superpowers' ambiguity-check quote *"resolves interpretations into explicit requirements"* is fabricated; the real text is *"Could any requirement be interpreted two different ways? If so, pick one and make it explicit."*
5. HBR "Marketing Malpractice" has **three** authors — Christensen, Cook, **and Taddy Hall**. The "18-hour observation" detail is not sourced to that article.
6. spec-kit spec-template assumptions are not individually dated.
7. The `writing-plans` no-placeholder "quote" is a splice of non-adjacent bullets — cite as a list.
8. Unverified in this pass and worth checking before load-bearing use: all BMAD, Kiro, OpenSpec, spec-kit constitution, Wiegers, EARS, JTBD/Switch, sycophancy-paper, and AskUserQuestion-blog claims; the gsd "Claude's Discretion" and assumptions-mode claims (both secondary sources); and all four grill-me variant sources.