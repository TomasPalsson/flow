# Spec-Driven Development for Coding Agents: State of Play, September 2026

## TL;DR

- SDD tools proliferated in late 2025 (Spec Kit, Kiro, OpenSpec, BMAD, Tessl) as a reaction to "vibe coding" drift, but by mid-to-late 2026 practitioner sentiment has cooled: an active "Ask HN: What Happened to Spec-Driven Development?" thread (2026) argues the dedicated tools have "fallen off" while the underlying complaint — agents deviating from requirements — is unresolved. (SECONDARY/PRIMARY mixed, contested)
- The most-cited framework for talking about SDD rigor is Birgitta Böckeler's three levels — **spec-first** (spec used once, then discarded), **spec-anchored** (spec kept alive as a living document, e.g. tests enforce sync), **spec-as-source** (only the spec is human-edited; code is fully generated) — published on martinfowler.com, Oct 15 2025. She found Kiro's "simplest" workflow turned a small bug fix into 4 user stories / 16 acceptance criteria, and flagged that AI agents frequently ignore detailed spec instructions even with large context windows. (PRIMARY, standard reference point — not itself contested, though its judgments are opinions)
- Kent Beck's critique (echoed and amplified by Martin Fowler, Jan 8 2026 Fragments post): SDD's "write the whole spec first" framing wrongly assumes you won't learn anything during implementation that should change the spec — this is the central intellectual objection to spec-first rigor, rooted in XP's feedback value. (PRIMARY practitioner opinion, but from two of the field's most credentialed voices — treat as "contested, high-authority")
- Anthropic's own current guidance (Claude Code docs, "Best practices," 2026) does NOT prescribe heavyweight spec-driven development by default. It recommends a lightweight four-phase loop (explore → plan → implement → commit), explicitly says "if you could describe the diff in one sentence, skip the plan," and only recommends writing a full spec ("have Claude interview you... write a complete spec to SPEC.md") for larger features — plus an explicit warning against over-specified CLAUDE.md files. This is the closest thing to an official Anthropic position and it is deliberately proportional, not maximalist. (PRIMARY, standard/consensus within Anthropic's own product)
- Named failure modes practitioners converge on: **spec drift** (spec and code diverge invisibly, no linter/CI catches it, and it's worse under agents because hundreds of lines/minute get generated off a stale spec), **requirements/spec theater** (verbose markdown nobody reads, "review the code, not the docs"), **over-specification degrading compliance** (rule-of-thumb ceiling around 150–200 standing instructions before agents start ignoring them), and **agents inventing unrequested features** absent a spec to anchor against. (SECONDARY, multiple independent sources converge — "standard" observation, though the 150-200 number is explicitly a rule of thumb not a measured guarantee)
- Hard outcome evidence specifically isolating "spec-first vs iterative prompting" (e.g., an RCT or controlled benchmark) was **not found** in this research — most "evidence" is either (a) general vibe-coding failure-rate stats (e.g., claims of ~45% vulnerability rates, 20-30% of sprint capacity spent fixing AI-heavy codebases, 8,000+ of 10,000 AI-built startups needing rescue engineering by mid-2026) used to argue for *some* discipline, not for SDD specifically, or (b) vendor/tool marketing claims. Treat all outcome numbers as SECONDARY, sourced from marketing-adjacent blogs (Security Boulevard/ISHIR/Autonoma), not verified primary studies.
- What has converged as a practical 2026 default for a solo developer is **not** a heavyweight Kiro/Spec-Kit-style three-document pipeline but a lightweight, proportional pattern: AGENTS.md/CLAUDE.md for durable repo context (kept short — "the auto-generated, everything-included agent file is a failure mode wearing a diligence costume"), a single throwaway SPEC.md or plan produced via an interview/plan-mode step for anything nontrivial, TDD-style verification loops, and adversarial/fresh-context review — i.e., "spec-anchored where it's cheap, spec-first (disposable) for most tasks, full ceremony only for genuinely large/ambiguous features." (Synthesis across PRIMARY Anthropic docs + SECONDARY practitioner consensus)
- AGENTS.md itself is the one piece of this whole ecosystem that has cleanly "won": donated to the Linux Foundation's Agentic AI Foundation (Dec 2025), 60,000+ adopting open-source projects, 20+ compatible tools as of Dec 2025 — it's infrastructure/convention, not a methodology, so it sits outside the spec-first/iterative debate entirely. (PRIMARY, from agents.md and secondary corroboration, standard/consensus)

## Findings

1. **Claim**: Spec-Driven Development (SDD) makes an executable, version-controlled specification — not the code — the source of truth, with code treated as a generated/verifiable artifact.
   **Evidence**: GitHub's own spec-kit methodology doc states "Specifications don't serve code—code serves specifications," structured as Specification → Implementation Plan → Code Generation → Feedback Integration, with `[NEEDS CLARIFICATION]` markers required for ambiguity.
   **Source**: https://github.com/github/spec-kit/blob/main/spec-driven.md (undated, current as of fetch Sept 2026)
   **PRIMARY** | Standard/consensus (this is the canonical definition most other sources cite)

2. **Claim**: Spec-Kit's granularity guidance: keep primary docs high-level/readable; push algorithmic/technical detail into a separate `implementation-details/` folder; forbid speculative features not traceable to a concrete user story; use "constitutional gates" to justify complexity.
   **Evidence**: Same spec-driven.md document, "Specification Detail Prescriptions" section.
   **Source**: https://github.com/github/spec-kit/blob/main/spec-driven.md
   **PRIMARY** | Standard/consensus for that specific tool

3. **Claim**: AWS Kiro structures specs as three files — requirements.md (EARS format: "WHEN [condition] THEN the system SHALL [behavior]"), design.md (architecture, sequence diagrams), tasks.md (discrete implementation steps) — across a 4-phase Requirements → Design → Tasks → Implementation flow, offered in both Requirements-First and Design-First variants.
   **Evidence**: Kiro's own docs; best-practices page recommends "multiple focused specs per repository rather than one monolithic spec" and running deep requirement analysis only for complex/compliance-sensitive features.
   **Source**: https://kiro.dev/docs/specs/ and https://kiro.dev/docs/specs/best-practices/
   **PRIMARY** | Standard for Kiro's own prescription

4. **Claim**: In practice Kiro's "simplest" spec workflow can be disproportionate for small work — a small bug fix expanded into 4 user stories and 16 acceptance criteria.
   **Evidence**: Böckeler's hands-on evaluation.
   **Source**: https://www.martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html (Oct 15, 2025)
   **PRIMARY** (Böckeler's own reported experience) | One practitioner's opinion, but widely cited as representative

5. **Claim**: OpenSpec (Fission AI) is deliberately lightweight — plain Markdown, no special syntax, 5 commands, "delta tracking" (every change is a scoped diff against a source-of-truth spec stored under `openspec/changes/`), explicitly brownfield-friendly, and marketed against "requirements live only in chat history."
   **Evidence**: OpenSpec's own README/site; a typical change is ~250 lines of markdown across proposal/specs/tasks.
   **Source**: https://github.com/Fission-AI/OpenSpec
   **PRIMARY** | Standard for that tool; the "predictability without ceremony" framing is a vendor claim (opinion), not verified outcome data

6. **Claim**: BMAD Method (Breakthrough Method for Agile AI-Driven Development / "Build More Architect Dreams") structures work through specialized agent personas (Analyst, PM, Architect, Scrum Master, Dev, QA, UX) across Analysis → Planning → Solutioning → Implementation, breaking a one-page PRD into atomic story files so each step gets focused context ("context engineering").
   **Evidence**: Multiple secondary summaries converge on this structure; original repo not directly fetched in this pass.
   **Source**: https://www.augmentcode.com/guides/bmad-method-ai-development, https://dev.to/extinctsion/bmad-the-agile-framework-that-makes-ai-actually-predictable-5fe7
   **SECONDARY** | Standard description, not independently verified against BMAD's own repo in this pass (gap — see below)

7. **Claim**: Tessl pursues the most ambitious end of the spectrum — "spec-as-source": specs are the only human-edited artifact, generated code is marked auto-generated and not meant for manual edits, plus a "Spec Registry" distributing authoritative specs for third-party dependencies/APIs.
   **Evidence**: Tessl's own blog announcements.
   **Source**: https://tessl.io/blog/tessl-launches-spec-driven-framework-and-registry, https://tessl.io/blog/how-tessls-products-pioneer-spec-driven-development
   **PRIMARY** (vendor's own claims) | This is Tessl's stated aspiration; Böckeler's independent evaluation (finding 12) is more skeptical of its practicality

8. **Claim**: AGENTS.md is a plain-Markdown, no-required-fields convention for giving coding agents build/test/style/security context, distinct from README (for humans). Formalized as an open spec Aug 2025, led by OpenAI with Google/Cursor/Factory participation; donated to the Linux Foundation's Agentic AI Foundation Dec 2025; 60,000+ adopting projects and 20+ compatible tools (Codex, Jules, Gemini CLI, Cursor, Aider, Devin, Windsurf, Amp, Zed, Warp, GitHub Copilot, Factory, +10 more) as of Dec 2025.
   **Evidence**: agents.md site and corroborating search results.
   **Source**: https://agents.md/ , https://github.com/agentsmd/agents.md
   **PRIMARY** | Standard/consensus — this is the one convention in the space with near-universal, uncontested adoption

9. **Claim**: Practitioner rule of thumb: frontier models reliably follow on the order of 150–200 "standing instructions" before compliance degrades; an exhaustive, everything-included AGENTS.md/CLAUDE.md is therefore "a failure mode wearing a diligence costume" — files should stay lean, structured WHAT/WHY/HOW, and progressively disclosed.
   **Evidence**: Cited across multiple governance/config-smell analyses of agent config files.
   **Source**: surfaced via search of arXiv "Configuration Smells in AGENTS.md Files" (arxiv.org/pdf/2606.15828) and related governance pieces (not independently fetched/verified in full — search-snippet level) [UNVERIFIED: independent check found the "~150-200 instructions" figure real but traceable to Kyle/Humanlayer (humanlayer.dev/blog/writing-a-good-claude-md), not to this arXiv paper — full text of arxiv.org/pdf/2606.15828 contains neither the number nor the "diligence costume" phrase. See Source check section.]
   **SECONDARY**, explicitly flagged by the source itself as "a rule of thumb, not a model guarantee" | Standard observation, low-confidence exact number

10. **Claim**: Anthropic's own Claude Code "Best practices" doc (current, 2026) prescribes a proportional, NOT maximal, planning discipline: 4-phase loop (Explore → Plan → Implement → Commit) via Plan Mode; explicit guidance "if you could describe the diff in one sentence, skip the plan"; for CLAUDE.md, "keep it concise... bloated CLAUDE.md files cause Claude to ignore your actual instructions"; for larger features, recommends having Claude interview the user via AskUserQuestion and writing a throwaway SPEC.md, then starting a **fresh session** to execute against it, because "the most useful specs are self-contained: they name the files and interfaces involved, state what is out of scope, and end with an end-to-end verification step."
   **Evidence**: Direct doc content, quoted verbatim above.
   **Source**: https://code.claude.com/docs/en/best-practices (redirected from anthropic.com/engineering/claude-code-best-practices)
   **PRIMARY** | Standard/consensus — this is Anthropic's official current position and it's explicitly proportional/anti-overkill

11. **Claim**: Anthropic also warns against "over-engineering via review": a reviewer subagent prompted to find gaps "will usually report some, even when the work is sound... chasing every finding leads to over-engineering: extra abstraction layers, defensive code, tests for cases that can't happen." Tell reviewers to flag only correctness/requirement gaps.
    **Evidence**: Same doc, "Add an adversarial review step" section — directly relevant to "spec-judge fatigue."
    **Source**: https://code.claude.com/docs/en/best-practices
    **PRIMARY** | Standard/consensus (Anthropic's explicit warning)

12. **Claim**: obra/superpowers (Jesse Vincent) is a Claude Code skills framework enforcing brainstorm → git-worktree → plan (2–5 min tasks with complete specs) → execute (subagent per task, two-stage spec-compliance + code-quality review) → TDD RED-GREEN-REFACTOR → code review → branch completion. Tasks are written specific enough that "an enthusiastic junior engineer with poor taste, no judgement, no project context, and an aversion to testing" could follow them. Added to Anthropic's official plugin marketplace in early 2026.
    **Evidence**: Project's own README/marketplace listings.
    **Source**: https://github.com/obra/superpowers/
    **PRIMARY** | One practitioner's methodology, increasingly adopted (per marketplace inclusion) — leans toward "standard" within the Claude Code power-user community but is still one author's opinionated framework

13. **Claim**: GSD / "get-shit-done" (TÂCHES) — original repo archived; continues as "GSD Core" (open-gsd/gsd-core) — implements a 5-step loop per milestone (Discuss → Plan → Execute → Verify → Ship), running heavy research/planning/execution in fresh-context subagents (each starting with a clean 200k-token window) specifically to fight "context rot," with persistent STATE.md/CONTEXT.md artifacts across sessions.
    **Evidence**: Project README (GSD Core).
    **Source**: https://github.com/open-gsd/gsd-core (also https://github.com/gsd-build/get-shit-done, archived)
    **PRIMARY** | One practitioner's framework, not independently validated by outcome data

14. **Claim**: The central intellectual critique of spec-first SDD: Kent Beck argues descriptions of SDD "emphasize writing the whole specification before implementation," encoding "the (to me bizarre) assumption that you aren't going to learn anything during implementation that would change the specification." Martin Fowler agrees, tying it to XP's core value of feedback, and cites a colleague ("Unmesh"): "the real capability—our ability to respond to change—comes not from how fast we can produce code, but from how deeply we understand the system."
    **Evidence**: Direct fragment content.
    **Source**: https://martinfowler.com/fragments/2026-01-08.html (Jan 8, 2026)
    **PRIMARY** | Contested — this is the strongest counter-position in the field, from two highly credentialed voices, directly opposed to the Spec-Kit/Kiro "write it all upfront" framing

15. **Claim**: Böckeler's three-level taxonomy (spec-first / spec-anchored / spec-as-source) is now the standard vocabulary practitioners use to avoid conflating different tools' very different levels of ambition — most existing SDD tools (Kiro, Spec-Kit) are actually spec-first only (spec discarded post-feature), despite aspiring to more; only Tessl targets spec-as-source.
    **Evidence**: Böckeler's article, corroborated by multiple secondary summaries (codemyspec.com, martinelli.ch, rushis.com) that treat this taxonomy as the reference framework.
    **Source**: https://www.martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html (Oct 15, 2025)
    **PRIMARY** | Standard/consensus reference framework (widely adopted vocabulary), though the underlying value judgments remain her opinion

16. **Claim**: Spec drift is the sharpest named failure mode: when spec is a separate document, code changes and spec updates diverge, "no linter, no CI" catches it, and agent-speed code generation (hundreds of lines/minute) accelerates the damage versus human-speed divergence.
    **Evidence**: Multiple governance-focused sources converge on this description.
    **Source**: https://www.truefoundry.com/blog/spec-driven-development-ai-agents ; https://www.kinde.com/learn/ai-for-software-engineering/ai-devops/spec-drift-the-hidden-problem-ai-can-help-fix/ ; arxiv.org/pdf/2606.27045 ("The Spec Growth Engine")
    **SECONDARY** (blog-level sources; arXiv paper not independently fetched in full — title/abstract-level only) | Standard/consensus observation across independent sources

17. **Claim**: "Ask HN: What Happened to Spec-Driven Development?" (2026 thread) — original poster observes dedicated SDD tools (Kiro, Spec-Kit) "faded" while the underlying complaint (agents deviating from requirements) persists; top comment argues SDD fundamentally lacks what makes programming languages work — a universal, deterministic mapping from spec to implementation, so code remains the only reliable source of truth ("the spec is not comprehensive enough to guarantee one specific implementation"); another commenter argues models simply got good enough that lightweight `plan.md` + verification loops replaced formal SDD tooling; a third warns that without specs, agents now silently "invent features."
    **Evidence**: HN thread content as fetched.
    **Source**: https://news.ycombinator.com/item?id=49182353
    **SECONDARY** (crowd-sourced commentary, individually unverifiable authorship/credentials) | Contested — represents the "SDD tooling is declining" position directly, itself disputed within the thread

18. **Claim**: A second HN thread, "Spec-Driven Development: The Waterfall Strikes Back" (Nov 2025), argues SDD reintroduces classic waterfall failure: since agents rarely nail the spec on the first attempt, "the purpose of Big Design Up Front" is defeated by the need for constant spec rework; one commenter: "the tiniest feature you want to add requires extremely complex manipulation of the spec" as projects grow; specs risk calcifying "into something immutable in stakeholders' minds" while reality diverges underneath.
    **Evidence**: Thread content as fetched.
    **Source**: https://news.ycombinator.com/item?id=45935763 (Nov 2025)
    **SECONDARY** | One practitioner-community's opinion, but a well-articulated and frequently echoed critique — contested vs. the pro-SDD camp

19. **Claim**: "Requirements theater" critique (Scott Logic, cited secondhand): engineers ended up "running through the commands just to generate code and read the code rather than the docs," buried in "a sea of markdown documents" — SDD ceremony without enforcement/verification degenerates into performative documentation that inevitably drifts.
    **Evidence**: As reported by codemyspec.com's synthesis article.
    **Source**: https://codemyspec.com/blog/spec-driven-development
    **SECONDARY** (this is a third-party blog summarizing Scott Logic's critique — original Scott Logic post not independently fetched, gap noted below) | One practitioner's opinion, echoed by several others (converging toward "standard" critique)

20. **Claim**: Yuval Yeret's reframing: SDD is progress only if the spec becomes "a higher-level programming language for intent" maintained near execution time by engineers-with-agents — not a PM-authored, backlog-stage artifact. He explicitly warns that forcing spec-driven activity into a traditional Scrum "big spec up front, then implement" pattern recreates requirements theater and that "having PMs write specs... makes very little sense" and disempowers teams; specs should sit close to the actual sprint work, not in backlog refinement.
    **Evidence**: Direct article content.
    **Source**: https://yuvalyeret.com/blog/is-spec-driven-development-a-step-forward-or-back-for-product-development/
    **PRIMARY** (his own stated argument) | One practitioner's opinion, but a nuanced middle position (neither pure pro- nor anti-SDD)

21. **Claim**: Vibe-coding-failure statistics cited to motivate discipline (used across marketing-adjacent pieces, NOT SDD-specific outcome data): ~45% vulnerability rate and "19% slower" claims for vibe-coded output [UNVERIFIED: these two figures do not appear in the cited Security Boulevard article — the article's own security figures are "88% had row-level security disabled" and "10.3% critical externally-visible failures." The 45% figure traces to Veracode's LLM security-benchmark research and the 19%-slower figure to the METR study of experienced developers; both are real numbers from real studies but were misattributed to this citation. See Source check section.]; Autonoma's April 2026 research reportedly found teams spending 20–30% of sprint capacity fixing bugs ~90 days after first vibe-coded ship; an "early 2026" estimate that 8,000+ of ~10,000 startups that built production apps with AI coding tools by end of 2025 needed partial rebuilds/rescue engineering by mid-2026, at $50K–$500K per project; Gartner is cited predicting >40% of agentic AI projects cancelled by end of 2027 for cost/value/risk reasons.
    **Evidence**: Aggregated in vendor/marketing blog posts; original Autonoma report and the underlying Gartner citation were not independently located/fetched.
    **Source**: https://securityboulevard.com/2026/07/spec-driven-development-vs-vibe-coding-the-enterprise-framework-for-scaling-ai-software-delivery-and-proving-its-roi/ (and similar syndicated pieces)
    **SECONDARY**, unverified primary source (gap — flagged explicitly below) | These numbers should be treated skeptically; they support "some discipline beats none" broadly, not "SDD specifically beats iterative prompting"

22. **Claim**: LLM-as-judge literature (general, not spec-specific): LLM judges don't suffer human-style fatigue degradation, but they do exhibit "false acceptance" — accepting specs/outputs that don't match actual intent — especially under complex, multi-faceted rubrics; research is trending from single-shot "LLM-as-judge" toward "Agent-as-judge" (hierarchical, per-component reasoning) partly to address this cognitive-overload-analog on complex specs.
    **Evidence**: Cross-referenced arXiv abstracts.
    **Source**: https://arxiv.org/pdf/2510.24367 (LLM-as-a-Judge for Software Engineering), https://arxiv.org/pdf/2601.05111 (Agent-as-a-Judge)
    **SECONDARY** (abstract/search-snippet level, papers not fully read) | Standard/consensus in the eval-research literature, but only indirectly about "spec-judge fatigue" as the research question asked — treat as adjacent, not direct, evidence

23. **Claim**: No dedicated RCT-style or matched-cohort study directly comparing "spec-first development with a coding agent" vs. "iterative/vibe prompting with the same agent" on a controlled task set was found in this research pass. All outcome claims located are either vendor marketing, single-practitioner anecdotes, or general AI-coding failure-rate statistics not isolated to the SDD variable.
    **Evidence**: Absence across 17 web searches and 10 fetched pages.
    **Source**: N/A (negative finding)
    **N/A** | This is a genuine evidence gap, not a claim — flagged explicitly in Gaps section

## Concrete practices / configs (copy-pasteable, this week)

These are the practices that converge across Anthropic's own docs, OpenSpec, and the HN "what happened" critique as the pragmatic 2026 default for a solo dev — proportional rather than maximal:

1. **Keep a short AGENTS.md / CLAUDE.md** (the two are largely interoperable conventions now). Per Anthropic's own doc, include only: bash commands the agent can't guess, non-default code-style rules, testing instructions, repo etiquette (branch/PR conventions), architectural decisions, env-var quirks, and known gotchas. Explicitly exclude: anything derivable from reading the code, boilerplate "write clean code" platitudes, and information that changes often. Test: "would removing this line cause a mistake?" If not, cut it. Source: https://code.claude.com/docs/en/best-practices

2. **For a task you can describe as a one-sentence diff, skip planning entirely.** Just prompt directly. Reserve Plan Mode / spec-writing for multi-file changes, unfamiliar code, or genuine uncertainty about approach. Source: same, Anthropic best-practices.

3. **For anything bigger, use a throwaway SPEC.md, not a permanent 3-document pipeline.** Concretely: `"I want to build [X]. Interview me in detail using the AskUserQuestion tool... keep interviewing until we've covered everything, then write a complete spec to SPEC.md."` Then start a **fresh session** to implement against it — this mirrors OpenSpec's "explore → propose → apply → archive" loop and GSD's "fresh-context subagent per phase" pattern, applied minimally without installing a separate framework. Source: Anthropic best-practices; corroborated by OpenSpec (github.com/Fission-AI/OpenSpec) and GSD Core (github.com/open-gsd/gsd-core).

4. **Make the spec self-contained and falsifiable**: name the files/interfaces involved, state what's explicitly out of scope, and end with an end-to-end verification step. This is Anthropic's own definition of "the most useful spec" and it directly answers Böckeler's "false precision" critique (agents ignoring vague detailed prose) by making the spec checkable rather than merely descriptive.

5. **Give the agent something that produces pass/fail, not "looks done."** Tests, a build, a lint pass, a screenshot diff. This is Anthropic's single strongest lever ("the difference between a session you watch and one you walk away from") and it's the mechanism that actually prevents spec drift in practice — the spec's claims get continuously checked against reality instead of trusted.

6. **If using an adversarial/reviewer subagent against the spec, explicitly instruct it to flag only correctness/requirement gaps, not style nitpicks** — otherwise you get the "spec-judge fatigue" failure mode (endless low-value findings, over-engineering churn). Anthropic's own explicit warning: "chasing every finding leads to over-engineering."

7. **If you want a heavier, opinionated methodology instead of assembling this yourself**: obra/superpowers (github.com/obra/superpowers) is the most-adopted (added to Anthropic's official plugin marketplace) drop-in Claude Code skill set that encodes brainstorm → plan → TDD → review as auto-triggering skills, without requiring you to hand-roll the loop above.

8. **Avoid the specific anti-patterns named across sources**: (a) one monolithic spec for a whole project — Kiro's own docs recommend multiple small, focused specs per repo; (b) a spec maintained in a separate location from code with no CI/test enforcement — this is the exact recipe for invisible spec drift; (c) an "everything-included" AGENTS.md past ~150-200 standing instructions, treated by multiple sources as the point where compliance degrades.

## Disagreements and open questions

- **Fixed-upfront vs. living/evolving spec** — the field's deepest unresolved split. Spec-Kit/Kiro's native mode is spec-first (write it, use it once). Kent Beck/Martin Fowler argue this is philosophically wrong because it denies you'll learn things during implementation that should change the spec. OpenSpec and Böckeler's "spec-anchored" tier try to split the difference (spec persists but is expected to be revised via structured deltas). No consensus on which default is right for a solo dev; Anthropic's own guidance implicitly sides with Beck/Fowler by defaulting to lightweight, throwaway specs and treating heavy planning as the exception, not the rule.
- **Is spec-first tooling actually declining, or just maturing past its hype phase?** The 2026 "Ask HN: What Happened to SDD?" thread frames dedicated SDD *tools* as fading while the *problem* they addressed persists — one camp says models got good enough that formal SDD tooling is now unnecessary overhead (lightweight plan.md + verification loops suffice); another camp says specs remain necessary precisely because agents now silently invent unrequested features. This is unresolved and actively debated as of the most recent sources found (2026, undated more precisely than "2026").
- **Whether SDD is "waterfall in disguise."** Contested directly: the HN "Waterfall Strikes Back" thread and Scott Logic's "requirements theater" critique say yes for tools without enforcement; Yuval Yeret and GitHub's own spec-kit docs say the accusation only holds if you literally hand specs to a PM/backlog process rather than keeping them live and close to execution.
- **No controlled outcome evidence found.** Every claim of "SDD improves outcomes X%" traced back to either vendor marketing (Tessl, Kiro-adjacent), general vibe-coding failure statistics not isolated to the SDD variable, or single-practitioner testimony. This is a genuine gap — see Gaps below.
- **Spec granularity has no agreed unit.** Kiro pushes EARS-format acceptance criteria (can balloon to 16+ criteria for a small fix, per Böckeler); OpenSpec/GSD/Anthropic push toward a single ~1-2 page throwaway document; Spec-Kit pushes structured multi-file (spec.md/plan.md/tasks.md/constitution.md) with checklists. Practitioners have not converged on a standard; the closest thing to consensus is "match rigor to task size and stakes," which is a heuristic, not a specific granularity.
- **BMAD's underlying repo/docs were not independently fetched** in this pass — the summary here rests on secondary sources; if BMAD's own documentation differs materially from these summaries, that would need correction.
- **The exact "150-200 standing instructions" ceiling** is repeatedly cited but self-described as a rule of thumb; no primary measurement study was independently verified for it in this pass.

## Gaps

- Could not independently fetch/verify BMAD-Method's own GitHub repo/docs (relied on secondary summaries from augmentcode.com and dev.to).
- Could not locate or fetch a controlled study (RCT, matched-cohort benchmark, or similar) directly isolating "spec-first vs. iterative prompting" as the treatment variable on a fixed task set with a fixed agent/model — this is the single biggest evidentiary hole in the "does spec-first improve outcomes" question. Everything found was either anecdotal, vendor-marketed, or measuring "any-discipline vs. no-discipline" rather than "spec-first specifically."
- The Autonoma "20-30% sprint capacity" statistic and the "8,000 of 10,000 startups needed rescue engineering" statistic were both encountered only inside syndicated marketing/blog content (Security Boulevard, ISHIR, MindStudio-style posts); the original Autonoma report and the specific "early 2026 estimate" source were not located or independently fetched, so these numbers carry low confidence and should not be repeated as hard facts without further sourcing.
- Scott Logic's original "requirements theater" post was not independently fetched (only reached via a third-party synthesis at codemyspec.com).
- The arXiv papers on spec drift ("The Spec Growth Engine," 2606.27045), AGENTS.md config smells (2606.15828), and LLM-as-judge for software engineering (2510.24367) were read only via search-result abstracts/snippets, not fetched and read in full — their claims here should be treated as headline-level, not deeply verified.
- Did not find a clear, single canonical source stating what specifically constitutes the 2026 "converged default" — that synthesis in the TL;DR and Concrete Practices sections is this report's own inference from triangulating Anthropic's official docs, OpenSpec's design philosophy, and the HN critique threads, not a single source making that claim explicitly.
- Tessl's real-world adoption/outcome data (beyond its own launch-announcement claims) was not found — its "spec-as-source" ambition remains largely unverified by independent practitioner reports in the sources gathered here.

## Sources

1. https://github.com/github/spec-kit/blob/main/spec-driven.md — GitHub Spec Kit methodology doc (PRIMARY)
2. https://github.com/github/spec-kit — Spec Kit repo
3. https://kiro.dev/docs/specs/ — Kiro Specs overview (PRIMARY)
4. https://kiro.dev/docs/specs/best-practices/ — Kiro best practices (PRIMARY)
5. https://kiro.dev/docs/specs/feature-specs/ — Kiro Feature Specs
6. https://github.com/Fission-AI/OpenSpec — OpenSpec repo (PRIMARY)
7. https://agents.md/ — AGENTS.md official site (PRIMARY)
8. https://github.com/agentsmd/agents.md — AGENTS.md repo
9. https://martinfowler.com/fragments/2026-01-08.html — Fowler on Beck's SDD critique, Jan 8 2026 (PRIMARY)
10. https://www.martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html — Böckeler, "Understanding Spec-Driven-Development: Kiro, spec-kit, and Tessl," Oct 15 2025 (PRIMARY)
11. https://github.com/obra/superpowers/ — obra/superpowers repo (PRIMARY)
12. https://github.com/gsd-build/get-shit-done — original GSD repo (archived)
13. https://github.com/open-gsd/gsd-core — GSD Core (successor) (PRIMARY)
14. https://news.ycombinator.com/item?id=49182353 — "Ask HN: What Happened to Spec-Driven Development?" (SECONDARY/crowd)
15. https://news.ycombinator.com/item?id=45935763 — "Spec-Driven Development: The Waterfall Strikes Back" HN thread (SECONDARY/crowd)
16. https://code.claude.com/docs/en/best-practices — Anthropic Claude Code best practices, current 2026 (PRIMARY)
17. https://tessl.io/blog/tessl-launches-spec-driven-framework-and-registry — Tessl launch announcement (PRIMARY, vendor)
18. https://tessl.io/blog/how-tessls-products-pioneer-spec-driven-development — Tessl blog (PRIMARY, vendor)
19. https://codemyspec.com/blog/spec-driven-development — synthesis article, three-rigor-levels framing + Scott Logic critique (SECONDARY)
20. https://yuvalyeret.com/blog/is-spec-driven-development-a-step-forward-or-back-for-product-development/ — Yeret's PM-perspective critique (PRIMARY, his own opinion)
21. https://www.augmentcode.com/guides/bmad-method-ai-development — BMAD summary (SECONDARY)
22. https://dev.to/extinctsion/bmad-the-agile-framework-that-makes-ai-actually-predictable-5fe7 — BMAD summary (SECONDARY)
23. https://www.truefoundry.com/blog/spec-driven-development-ai-agents — spec drift discussion (SECONDARY)
24. https://www.kinde.com/learn/ai-for-software-engineering/ai-devops/spec-drift-the-hidden-problem-ai-can-help-fix/ — spec drift (SECONDARY)
25. https://arxiv.org/pdf/2606.27045 — "The Spec Growth Engine" (arXiv, abstract-level only)
26. https://arxiv.org/pdf/2606.15828 — "Configuration Smells in AGENTS.md Files" (arXiv, abstract-level only)
27. https://arxiv.org/pdf/2510.24367 — "LLM-as-a-Judge for Software Engineering" (arXiv, abstract-level only)
28. https://arxiv.org/pdf/2601.05111 — "Agent-as-a-Judge" (arXiv, abstract-level only)
29. https://securityboulevard.com/2026/07/spec-driven-development-vs-vibe-coding-the-enterprise-framework-for-scaling-ai-software-delivery-and-proving-its-roi/ — vibe-coding failure stats (SECONDARY, marketing-adjacent, low confidence)
30. https://www.mindstudio.ai/blog/vibe-coding-vs-spec-driven-development — vibe-coding vs SDD framing (SECONDARY)
31. https://dev.to/krlz/spec-driven-development-in-2026-what-it-is-the-tooling-and-how-teams-actually-use-it-2fk2 — 2026 tooling landscape overview (SECONDARY)

## Source check (independent)

Six of the report's most load-bearing claims (numeric, quoted, or attributed to named people/orgs) were independently checked against their cited sources on 2026-09-04. Verdicts: 4 CONFIRMED, 1 MISATTRIBUTED, 1 PARTIAL/MISATTRIBUTED (mixed — see below).

1. **Finding 4** (Böckeler / Kiro small bug fix → 4 user stories, 16 acceptance criteria) — **CONFIRMED**.
   Fetched https://www.martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html directly. Exact quote: *"When I asked Kiro to fix a small bug [...] it quickly became clear that the workflow was like using a sledgehammer to crack a nut. The requirements document turned this small bug into 4 'user stories' with a total of 16 acceptance criteria."* Article dated Oct 15, 2025, matching the report's citation. The three-level taxonomy (spec-first / spec-anchored / spec-as-source) is also confirmed verbatim in the same article (Finding 15's underlying claim).

2. **Finding 8** (AGENTS.md: donated to Linux Foundation's Agentic AI Foundation Dec 2025; 60,000+ adopting projects; 20+ compatible tools) — **CONFIRMED**.
   agents.md itself confirms "60k+ open-source projects" and 20+ listed compatible tools, and states it is "stewarded by the Agentic AI Foundation under the Linux Foundation" but does not itself print a date. A follow-up WebSearch confirmed the date independently: the Linux Foundation's own press release and TechCrunch (techcrunch.com/2025/12/09/openai-anthropic-and-block-join-new-linux-foundation-effort-to-standardize-the-ai-agent-era/) both report the Agentic AI Foundation was announced **Dec 9, 2025**, with AGENTS.md (OpenAI), MCP (Anthropic), and goose (Block) as its three founding donated projects, and put adoption at "more than 60,000 open source projects." All figures in the report check out.

3. **Finding 9** (frontier models reliably follow ~150-200 "standing instructions"; sourced to arXiv "Configuration Smells in AGENTS.md Files," arxiv.org/pdf/2606.15828; "failure mode wearing a diligence costume" phrase) — **MISATTRIBUTED**.
   Fetched the actual arXiv PDF (2606.15828) in full: it does not contain the "150-200" figure, any numeric instruction-following ceiling, or the phrase "a failure mode wearing a diligence costume." The 150-200 figure is real and traceable via WebSearch to Kyle at Humanlayer, https://humanlayer.dev/blog/writing-a-good-claude-md — exact quote confirmed by fetch: *"Frontier thinking LLMs can follow ~150-200 instructions with reasonable consistency."* — presented as approximate guidance, consistent with the report's "rule of thumb, not a guarantee" framing. But that Humanlayer post also does not contain the "diligence costume" phrase; that exact wording could not be traced to any source via WebSearch (results returned only unrelated "costume" content) and may be the report-writer's own paraphrase rather than a quote. The report's own inline flag ("not independently fetched/verified in full — search-snippet level") correctly signaled the risk here; the number is sound but the citation is wrong.

4. **Finding 10** (Anthropic Claude Code best-practices doc: 4-phase Explore→Plan→Implement→Commit loop; "if you could describe the diff in one sentence, skip the plan"; CLAUDE.md conciseness guidance; SPEC.md/AskUserQuestion interview + fresh-session pattern; "most useful specs are self-contained" language) — **CONFIRMED**.
   Fetched https://code.claude.com/docs/en/best-practices directly; every quoted phrase in the report matches the live page verbatim, including: *"If you could describe the diff in one sentence, skip the plan,"* *"Bloated CLAUDE.md files cause Claude to ignore your actual instructions!"*, the AskUserQuestion interview prompt template, and *"The most useful specs are self-contained: they name the files and interfaces involved, state what is out of scope, and end with an end-to-end verification step."*

5. **Finding 11** (same doc's adversarial-review warning: reviewers "will usually report some [gaps], even when the work is sound," and "chasing every finding leads to over-engineering") — **CONFIRMED** (checked as a byproduct of the Finding 10 fetch).
   Exact live-page text: *"A reviewer prompted to find gaps will usually report some, even when the work is sound, because that is what it was asked to do. Chasing every finding leads to over-engineering: extra abstraction layers, defensive code, and tests for cases that can't happen."* Matches the report's paraphrase/quote closely.

6. **Finding 14** (Kent Beck's critique of SDD's "write the whole spec first" assumption, amplified by Martin Fowler with a quote from "Unmesh," Jan 8 2026 Fragments post) — **CONFIRMED**.
   Fetched https://martinfowler.com/fragments/2026-01-08.html directly, dated Jan 8, 2026 as cited. Exact Beck quote: *"The descriptions of Spec-Driven development that I have seen emphasize writing the whole specification before implementation. This encodes the (to me bizarre) assumption that you aren't going to learn anything during implementation that would change the specification."* Exact Unmesh quote: *"...the real capability—our ability to respond to change—comes not from how fast we can produce code, but from how deeply we understand the system we are shaping."*

7. **Finding 21** (vibe-coding failure stats: ~45% vulnerability rate, "19% slower," Autonoma's 20-30% sprint-capacity figure, 8,000+/10,000 startups needing rescue engineering, Gartner >40% agentic-AI-project cancellation by 2027) — **PARTIAL / MISATTRIBUTED** (mixed within one citation).
   Fetched the cited Security Boulevard article directly. Three of the five sub-claims are confirmed verbatim there: the Autonoma 20-30% sprint-capacity figure (*"Autonoma's April 2026 research found teams spending 20 to 30 percent of sprint capacity just fixing bugs in AI-heavy codebases"*), the 8,000+/10,000 startups rescue-engineering estimate at $50K-$500K/project, and the Gartner >40%-by-2027 cancellation prediction. However, the "~45% vulnerability rate" and "19% slower" figures do **not** appear in this article at all — its own security numbers are different (88% had row-level security disabled; 10.3% had critical externally-visible failures). A follow-up WebSearch found both figures are real but come from different, unrelated studies: ~45% traces to Veracode's LLM code-security benchmark research, and "19% slower" traces to the METR study of experienced open-source developers using AI tools. The report bundled numbers from at least three distinct sources under a single citation, misattributing two of them to the Security Boulevard piece.

**Overall reliability assessment**: This report is well above average for a synthesis piece — most PRIMARY-tagged claims (Böckeler, Anthropic docs, Fowler/Beck, AGENTS.md/Linux Foundation) check out verbatim on direct fetch, and the report's own hedging language (flagging "rule of thumb," "search-snippet level," "not independently fetched in full") consistently and correctly predicted exactly where the two real problems were: (a) the arXiv citation for the 150-200 instruction figure is wrong (real claim, wrong source — the true source, Humanlayer, was never surfaced), and (b) the vibe-coding statistics paragraph conflates multiple distinct studies (Veracode, METR, Autonoma, an unnamed "early 2026" analysis, Gartner) under one blog-post citation, with two of five numbers not actually present in the cited piece. Both problems sit in sections the report itself already flagged as lowest-confidence (SECONDARY, marketing-adjacent, "gap — see below"), so a careful reader following the report's own confidence labels would not have been misled about *which* claims to trust less — but a reader who copy-pasted the citations without following that guidance would end up citing the wrong source in both cases. The PRIMARY/official-doc backbone of the report (Anthropic's own guidance, Böckeler's taxonomy, Beck/Fowler's critique, AGENTS.md's governance facts) is solid and safe to build a recommendation on as-is.
