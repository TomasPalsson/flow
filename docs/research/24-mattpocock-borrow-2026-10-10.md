# mattpocock/skills borrow review, round 2 — 2026-10-10

Source: https://github.com/mattpocock/skills at 49dd158 (MIT). The first review was on 2026-10-07 at f3fc563 ([`22-aihero-skills-borrow-2026-10-07.md`](22-aihero-skills-borrow-2026-10-07.md)). Since then upstream changed only the wizard template (49dd158), retro loading writing-for-agents (8267225) and the README.

This round used the rubric in [`23-pstack-rubric.md`](23-pstack-rubric.md), including B7 Fit, scored from the user's repo profile, and the rule the user set on 2026-10-09: judge on fit and benefit, never skip for cost.

## How it was scored

1. Four Opus reviewers scored all 38 skills plus the repo-level docs and scripts (45 rows) on layers A, B (B1-B7) and D.
2. Four Opus skeptics checked each slice (15 corrections).
3. One Opus judge wrote layers C and E and a merit build list (69 ideas).
4. Six Opus skeptics re-checked every build-list verdict. 36 were judged good.
5. They were built in 12 file-disjoint lanes, then a serial cross-cutting lane and a leftovers slice. Each slice had a Sonnet developer, an Opus adversary and a fix round.

## Per-skill verdicts

| Skill | Verdict | Gap | Lev | Mech | Port | Fit | Fit fact | Why |
|---|---|---|---|---|---|---|---|---|
| tdd | SKIP | 1 | 2 | 1 | 5 | 4 | B7=4: Claude Code builds with .specs/ in about 11 repos, and each flow task runs RED/GREEN, so tests get written most weeks. B1=1 because flow already carries a | B1=1. developer-block.md:53-60 and the RED hard gate already carry the substance. Two small tricks (SDK-style mock interfaces, seams noted as catches/misses) are logged in Layer D. |
| to-spec | SKIP | 1 | 2 | 1 | 1 | 3 | B7=3: the user writes specs in about 11 repos but never hands work to a tracker; flow forbids it ('NEVER hand off to GitHub issues', spec/SKILL.md:110). B1=1: f | B1=1 and B5=1. flow:spec already turns context into a spec in one turn with stated positions. Three tricks are logged: highest/fewest seam, test prior art, prototype-snippet exception. |
| to-tickets | MERGE | 3 | 3 | 2 | 3 | 4 | B7=4: every oneshot/dispatch build drafts a TASKS.md, .specs/ exists in about 11 repos, and the typical stack is a full-stack Next.js/Vite UI over an API, where | B1=3 and the new piece is small: about three sentences. Add the vertical-slice, prefactor-first and one-fresh-context rules to next §Drafting, re-cut the TASKS.md template example into vertical phases |
| implement | SKIP | 0 | 0 | 0 | 3 | 4 | B7=4: the user builds most weeks. B1=0: next §Building (next/SKILL.md:48-61) plus the per-task execution prompt (next/execution-prompt.md:29-48) do all of this, | B1=0 and B2=0. next/SKILL.md:48-61 and the test-changed script already cover the loop, with mechanical gates. |
| implement-spec | SKIP | 1 | 2 | 2 | 2 | 3 | B7=3: dispatch builds with parallel [P] waves happen, but the user is solo on one feature branch with no integration-branch/merger habit (all PR bases are main) | B1=1. build-slices.js and next §Building already schedule a dependency graph with proven disjointness. Frontier-over-barrier is a deliberate design difference, not a gap, for a solo user on one branch |
| code-review | MERGE | 3 | 3 | 2 | 5 | 4 | B7=4: CLAUDE.md exists in about 25 of the user's repos, and flow init writes REVIEW.md into every repo it sets up (bin/lib/lessons/02-init.js:13), yet flow's re | B1=3 and the new piece is small. Add a 'standards' lens, or pass CLAUDE.md and REVIEW.md to every lens through the existing reviewMd argument: findings cite file + rule, a documented rule overrides th |
| pr | SKIP | 1 | 1 | 1 | 5 | 4 | B7=4: the user opens many self-merged PRs, and flow's next and fix open one per feature or bug. B1=1: the skill already landed as shared/pr-body.md, which has S | B1=1, already adopted as shared/pr-body.md on 10-07. The one leftover, a component-tree option, is logged as a trick. |
| diagnosing-bugs | SKIP | 1 | 2 | 2 | 5 | 5 | B7=5: /flow:fix runs on bugs most weeks across every stack. B1=1: fix/feedback-loops.md is a near-verbatim adaptation ('Adapted from mattpocock/skills diagnosin | B1=1, already borrowed whole into fix/feedback-loops.md. The forced-mutation diff check is logged as a trick for lesson and fix. |
| prototype | MERGE | 2 | 3 | 2 | 4 | 3 | B7=3: Next.js/Vite UIs are most of the user's work, and as a consultancy (p5.is, Icelandic clients) they have non-developers who could drive a logic demo. Agent | B1=2 and each new piece is small. Add an 'in-app' mode to design:showcase (?variant= on the real route, production-gated switcher, losers moved to a throwaway branch). Give prep's spike route a logic- |
| codebase-design | MERGE | 2 | 3 | 1 | 5 | 3 | flow builds run in about 11 repos with .specs/. The user's Python agents (Bedrock, AgentCore, MCP) and Next.js apps all have the 'true external' and 'remote but | B1=2 and the new piece is small. Fold into flow-deepen/references/detection-heuristics.md: (1) the deletion test as a filter; (2) the two-adapter rule beside the existing single-implementation filter; |
| domain-modeling | SKIP | 1 | 2 | 1 | 5 | 1 | A find over ~/Desktop/Projects (45 repos, depth 4) on 2026-10-10 found no CONTEXT.md, no GLOSSARY.md and no docs/adr in any repo, even though grill-with-docs is | B7 is 1: the user never keeps glossaries or ADRs. B1 is 1 because flow-extras/grill-with-docs already carries this text. One trick (checking user claims against the code) is logged for prep. |
| improve-codebase-architecture | MERGE | 2 | 3 | 1 | 4 | 3 | The user's Next.js, Vite and Python-agent repos grow through flow builds. flow-deepen already handles spec-scoped deepening. No repo has .out-of-scope/ or docs/ | B1=2 and the missing piece is small: rejection memory. In flow-deepen Phase 5, a 'no' or a dropped candidate with a durable reason gets a Ruling line in the spec's NOTES.md (or LEDGER.md), and Phase 1 |
| grill-with-docs | SKIP | 0 | 1 | 0 | 3 | 2 | The user has flow-extras grill-with-docs installed, but no repo has the CONTEXT.md or ADRs it would create. Gap=0: the fused local copy already contains both ha | B1=0: the local grill-with-docs already holds both halves verbatim. The only lesson is compose by name rather than copy, logged as a trick. |
| research | MERGE | 2 | 2 | 1 | 5 | 4 | The user keeps numbered research notes in flow/docs/research/ (01 to 23, this review among them) and runs research-sweep. B4=4: 'Write the findings to a single  | B1=2 and the new piece is small. Give research-sweep (a) source code, local docs and installed packages as allowed primary sources beside the web, and (b) an optional out path, defaulting to the repo' |
| triage | SKIP | 3 | 1 | 2 | 2 | 1 | The user works solo and merges their own PRs. Sampled PRs on flow, news and worklog have zero reviews and zero comments. There is no external contributor stream a | B7 is 1: there is no incoming issue or PR stream. Two tricks survive: concept-not-keyword dedupe for flow:issue, and 'a deferral is not a rejection' for the borrow rubric. |
| wayfinder | MERGE | 3 | 2 | 2 | 3 | 2 | The user is a solo consultant who starts new client and personal projects. The .specs/ directories in about 11 repos are per-feature, and nothing shows multi-se | B7=2 and B2=2 rule out a new skill. B1=3 with a small new piece: when prep's split signal fires, sort each Open line with the fog-or-ticket test (sharp questions become their own prep, the rest go und |
| setup-matt-pocock-skills | SKIP | 1 | 1 | 2 | 2 | 1 | Solo, with no triage labels and no tracker config to keep: flow:issue already picks gh or .specs/ISSUES.md on each call. Gap=1 and Leverage=1: the repo setup fl | B7 is 1: no tracker or label vocabulary to configure, and flow init covers repo setup. |
| ask-matt | SKIP | 2 | 1 | 0 | 2 | 2 | The user wrote and maintains their own skill set and invokes most of it by name. Flow's position comes from `flow next`, not from a human-read map. Leverage=1: mo | B2 is 1: a prose router over another set does not change outcomes for a user whose build state is computed by `flow next`. The read-the-skill-first rule is logged as a trick. |
| retro (+ upstream 8267225) | MERGE | 2 | 3 | 2 | 5 | 4 | The user leans heavily on flow and lesson --retro. `flow init` writes REVIEW.md into repos (bin/flow:2140), and ads-seo has one. Yet grep finds no reader of REV | B1=2, two small pieces with real outcome effect. (a) Put the no-op test inline at lesson:31 (one sentence, since flow cannot depend on flow-extras): 'does it change behaviour versus the default; settl |
| wizard (+ upstream 49dd158) | ADOPT | 4 | 3 | 4 | 5 | 3 | CI runs in 11 repos, with Terraform/SST on AWS and Next.js .env files, where double-quoted dotenv values are the common style. The local wizard exists (tooling) | B1>=4 for the diff, B2=3 (the bugs hit any re-run over a quoted .env and any terminal where tput fails), B5=5. Copy 49dd158's template.sh changes into the local template, keep the attribution line, ad |
| grilling | SKIP | 0 | 3 | 1 | 5 | 3 | B7=3: heavy Claude Code + flow use, .specs/ in ~11 repos, so plan interviews happen regularly; not most weeks for an already-specced build. | B1=0: already merged into grill-with-docs on 10-07; the un-anchored one-at-a-time mode stays in grill-me and prep by the user's own design, not for cost. |
| grill-me | SKIP | 1 | 1 | 0 | 5 | 3 | B7=3: the user grills plans regularly (prep, grill-me, grill-with-docs all exist and are used). | B1=1 and B2=1: flow-extras grill-me is a deliberate design choice (recommend only after the user answers); the alias pattern is logged as a trick. |
| handoff | SKIP | 2 | 2 | 1 | 4 | 3 | B7=3: worktrees everywhere and heavy Claude Code use mean many fresh sessions, but flow builds already resume from disk; only non-flow multi-session work (resea | B1=2 with no small new piece worth a home: PROGRESS.md 'Now' + 'resume:' (flow-templates/PROGRESS.md:6-8) and session-context.sh already hand state to the next session; the suggested-skills idea is al |
| teach | ADAPT | 3 | 3 | 1 | 4 | 4 | B7=4: the fit profile (surveyed ~/Desktop/Projects only) misses this, but ~/Desktop/School holds current university course folders (Hugb, Raunkerfi, TSAM, Tölvu | B1=3, B2=3, B7=4 (active university study), but B3 is low and it should reuse the user's teacher pedagogy and design skills rather than its own prose: keep the workspace state (MISSION, learning recor |
| to-questionnaire | MERGE | 4 | 2 | 1 | 5 | 3 | B7=3: profile 'Solo developer and consultancy (p5.is)... Icelandic content and clients'; client-held facts block specs some weeks, though no repo shows a questi | B1=4 but B2=2: the new piece is small and belongs where open questions appear. When a spec Open Question is owned by someone other than the user, offer to write it as a questionnaire using this templa |
| wait-what | SKIP | 1 | 2 | 0 | 5 | 3 | B7=3: the user shipped design:smoothbrain on 10-09 for exactly the 'you lost me' moment, so it happens. | B1=1: design/skills/smoothbrain/SKILL.md:3,24,28 already owns 'wait what' with the same register and glossary lookup. |
| writing-for-agents | MERGE | 1 | 3 | 1 | 5 | 4 | B7=4: profile 'CLAUDE.md in ~25' repos and 'Heavy Claude Code + flow use'; the user edits skills and steering files most weeks. | B1=1 for the reference itself, but upstream's 10-09 change exposes one small real gap: lesson --retro judges No-ops and Steering bloat without the definition. Add one pointer line, read before judging |
| git-guardrails-claude-code | SKIP | 0 | 1 | 4 | 4 | 4 | B7=4: heavy Claude Code use with worktrees everywhere; destructive git is a weekly risk. But the user self-merges and pushes every PR, so upstream's blanket 'gi | B1=0: plugins/flow/hooks/git-guard.sh covers every pattern and the bypasses upstream left open. |
| migrate-to-shoehorn | SKIP | 2 | 1 | 1 | 4 | 2 | B7=2: TS test files with `as` casts exist in the user's own repos (finance 34, news 7, ads-seo 5, TerminalWebsite 5 by grep), but half the work is Python/Rust a | B2=1: the payoff is cosmetic test typing; no-slop NS-09 (rubric.md:29) already surfaces the casts. |
| scaffold-exercises | SKIP | 5 | 0 | 3 | 0 | 0 | B7=0: no repo in the profile is an AI Hero course; `pnpm ai-hero-cli internal lint` (:8) is the author's private tool. | B7=0: the user has no course-exercise repo; the skill only works with the author's private CLI. |
| setup-pre-commit | SKIP | 3 | 2 | 4 | 3 | 2 | B7=2: CI in 11 repos and most commits are Claude's own, gated by stop-gate; only 3 checkouts have .husky (TerminalWebsite, a copy of it, and the LibreChat fork) | B2=2 with no small new piece: format-lint.sh, stop-gate.sh and CI already gate the commits that matter for a solo developer whose commits are mostly Claude's. |
| chief-of-staff | SKIP | 1 | 2 | 0 | 4 | 3 | The user runs long orchestration sessions most weeks (Workflows, ultracode, overkill; CLAUDE.md 'Delegation' and 'Workflows' sections), so the situation happens | B1 = 1. flow already has the fleet posture (ultracode:14) and the environment-improvement ladder (lesson). The one new piece, an improvement hunt on every message, conflicts with the no-nudge-noise ru |
| claude-handoff | MERGE | 3 | 2 | 2 | 5 | 3 | Heavy Claude Code use with worktrees everywhere, and the global CLAUDE.md carries 'Compact instructions', so the user does hit long sessions they want to contin | B1 is 3: flow covers builds but not other conversations, and the new piece is small, so it merges rather than standing alone. Re-judged from the 10-07 skip: that skip only holds for flow builds. The C |
| loop-me | SKIP | 3 | 1 | 1 | 4 | 2 | The user does build personal automations (worklog, the slack-watch poller, weekly alpha-hunt, a morning skill, the news pipeline), but builds them one by one. T | B2 = 1: the skill designs personal automations and does not touch flow's build, fix or review path. Fit is only 2. The two reusable rules, push right and brief, are logged as tricks for flow's unatten |
| setup-ts-deep-modules | MERGE | 2 | 3 | 5 | 4 | 3 | /home/tomas/Desktop/Projects/finance/.dependency-cruiser.cjs already runs depcruise in `lint` (finance/package.json:10). Its rule app-features-isolated-home (li | B1 is 2: flow's design.md already demands enforcement configs and pattern-not-pairwise rules, so only the template and the bite-proof are new. Fit is evidenced: finance hit the exact pairwise problem. |
| writing-beats | SKIP | 2 | 1 | 1 | 5 | 1 | No blog, article or posts directory in any of the 45 repos (find over ~/Desktop/Projects returned none). The user's prose is PR bodies, docs, explainer pages an | B7 = 1: the user does not write long-form articles. The grounding idea is logged as a trick for smoothbrain and the prose rubric. |
| writing-fragments | SKIP | 2 | 1 | 1 | 5 | 1 | No article or newsletter writing anywhere in the profile, and no repo holds a fragments or drafts pile. | B7 = 1: there is no article practice to feed. B2 = 1 for flow's build, fix and review. |
| writing-shape | SKIP | 2 | 1 | 1 | 5 | 1 | No long-form writing in the profile. The user's written output is PR bodies and docs, and those are already scored by flow's prose rubric. | B7 = 1 (no articles). The format-choice and gap-naming tricks are logged for the prose rubric. |
| wizard template fixes (upstream 49dd158) | ADOPT | 5 | 3 | 4 | 5 | 3 | The wizard exists for human-only steps such as dashboards, secrets and cutovers. The user wires AWS, SST, Terraform and CI secrets across 11 CI repos, and hand- | B1 5, B2 3, B5 5. These are bug fixes to a file flow already ships, landing verbatim. |
| scripts/sync-plugin-version.mjs (+ link-skills.sh, list-skills.sh) | ADOPT | 4 | 3 | 5 | 4 | 5 | Every PR in the flow repo touches plugins/*. The memory bump-plugin-version.md records a real miss: #16 merged unbumped and needed a fix PR (#17). The rule now  | B1 4, B2 3, B5 4, B7 5: a mechanism that replaces a prose memory the user already had to enforce by hand. link-skills.sh is skipped (marketplace install). |
| .agents/invocation.md | MERGE | 2 | 2 | 3 | 5 | 4 | The user has 66+ skills across seven plugins. docs/decisions.md:19 records '39 of 66 descriptions were being dropped' from the listing budget, and only plugins/ | B1 2: flow already has the rule for commands. The new, small pieces are (a) auditing slash-only skills to free listing budget and (b) 'Call the Skill tool with' wording at cross-skill pointers. |
| .out-of-scope note: retro always loads writing-for-agents (upstream 8267225) | MERGE | 3 | 2 | 1 | 5 | 3 | The user runs /lesson and --retro, which flow borrowed from upstream retro on 10-07, and flow-extras ships writing-for-agents.md. | B1 3 with a one-line new piece: --retro should read writing-for-agents before judging the No-ops and Steering bloat candidates. |
| .agents/writing-docs.md | SKIP | 3 | 1 | 1 | 4 | 2 | Solo author who publishes plugins mainly for their own machines. There is no audience asking questions and no docs site per skill. | B2 1 and B7 2: no audience for per-skill docs pages. The 'It's working if' rule is logged as a trick for verify-skill and skill-forge. |
| SCOPE.md + .out-of-scope/ ledger | SKIP | 4 | 1 | 1 | 4 | 1 | Solo, with no outside issue reporters (sampled PRs have zero comments), so there is no stream of requests to triage. | B7 1 (no external requesters). flow already has docs/decisions.md and the two-sightings rule. |
| README.md + CLAUDE.md/AGENTS.md + GLOSSARY.md (repo conventions) | SKIP | 3 | 1 | 1 | 4 | 2 | The user maintains one marketplace repo (flow) with seven plugins. A beta bucket and a promotion process matter little to a solo author who can edit directly. | B2 1: flow's router is computed, not written, so the router-sync rule is already structural. The rest is house style for a public catalog. |

## Built

| ID | Idea | Where |
|---|---|---|
| P01 | Wizard template fixes: tput-clear fallback under set -e, decode or re-ask double-quoted .env values, write_env sets $KEY via printf -v, and every stage inside run_wizard  | plugins/tooling/skills/wizard/template.sh |
| P02 | Plugin version drift check: plugin.json version equals marketplace.json version, and a plugin with changed files has a version above main's | new plugins/flow/scripts/version-drift |
| P03 | Block every whole-tree `git checkout` discard, not only `checkout -- .` | plugins/flow/hooks/git-guard.sh:76 (checkout case of gg_rule_git) |
| P04 | Repo standards as a review predicate at gating: reviewers read REVIEW.md and the repo CLAUDE.md and cite file + rule for each violation; a documented rule overrides the b | plugins/flow/skills/next/SKILL.md:74 (gating step 2) |
| P05 | Standards belong to the reviewer, not the implementer: stop pointing implementing sessions at REVIEW.md | plugins/flow/flow-templates/CLAUDE.project.md:30 |
| P06 | Refuse an empty diff in review-package, and stop build-slices treating a failed package as a clean review | plugins/flow/scripts/review-package (after :86) |
| P07 | Smell baseline for the advisory structure lens: Feature Envy, Shotgun Surgery, Divergent Change, Message Chains and Refused Bequest, each a labelled judgement call that a | plugins/flow/agents/adversary.md:37 (structure lens bullet) |
| P08 | Vertical slices, prefactor first, and one fresh context per task in TASKS.md drafting | plugins/flow/skills/spec/SKILL.md:66 |
| P09 | Score TASKS.md vertical integrity with spec-judge's existing issue-breakdown mode at /flow:spec's dispatch judge step | plugins/flow/skills/spec/SKILL.md §5 (Judge) |
| P10 | Highest seam, fewest seams, each with a 'catches / misses' note | plugins/flow/skills/spec/references/question-bank.md:39 (category 8 row) |
| P11 | Name test prior art in the task brief | plugins/flow/scripts/task-brief (new '## Prior art' section after '## Tests' at :164) |
| P13 | SDK-style boundary interfaces: one function per external operation, so each mock returns one shape | plugins/flow/skills/no-slop/references/developer-block.md:58-60 |
| P16 | Logic-demo output form for prep's spike route: a pure, liftable reducer module with a thin HTML shell and one tab per scenario (happy path, tricky edge, should-be-illegal | plugins/flow/skills/prep/SKILL.md:42 (spike definition) and :98 (prototype pointer) |
| P17 | Whole-page variants on the real route behind ?variant=, with a dev-only switcher (arrow keys, not while an input has focus) and losing variants kept on a throwaway branch | plugins/design/skills/impeccable/reference/live.md (new short section) |
| P18 | flow-deepen heuristics: the deletion test, the ratio heuristic demoted to a hint, and the dependency category deciding how each deepening task's characterization test rea | plugins/flow/skills/flow-deepen/references/detection-heuristics.md:14 (ratio row), Family  |
| P19 | Replace, don't layer tests, reconciled with flow-deepen's monotonic-test guard and the developer block's no-delete rule | plugins/flow/skills/flow-deepen/references/detection-heuristics.md:50,65,85,113 |
| P20 | Rejection memory for flow-deepen: a durable 'no' is recorded where Phase 1 already looks, and deferrals are never recorded | plugins/flow/skills/flow-deepen/SKILL.md:41 (note the writer) and :97 (Phase 5 edits handl |
| P21 | Design it twice, constrained: 3 parallel subagents on one interface, each under a different constraint, then one opinionated pick or hybrid | plugins/flow/skills/spec/references/design.md:36 (Decisions) |
| P22 | State each deepening win as a call-site number; ban 'easier to maintain' and 'cleaner' | plugins/flow/skills/flow-deepen/SKILL.md:66 (Phase 3 'Win') |
| P23 | research-sweep: local code, installed packages and local docs count as primary sources, and each claim traces to the source that owns it | plugins/flow/workflows/research-sweep.js:42-46 (claim schema), :79-82 (angle prompt), :89- |
| P24 | Dedupe issues by domain concept, not wording, and say where you looked | plugins/flow/skills/issue/SKILL.md:79-85 |
| P25 | A durable issue's evidence names the enclosing symbol as well as path:line | plugins/flow/skills/issue/SKILL.md:29 (Evidence row) and :68 (example entry) |
| P26 | Prep split signal: the fog-or-ticket test decides which Open lines become their own prep; fact-only Open lines are resolved from the tree, not asked | plugins/flow/skills/prep/SKILL.md:105-107 (rule 6) |
| P27 | Check user claims against the code during prep | plugins/flow/skills/prep/SKILL.md Step 1 (:57-62) and rule 5 (:101-104) |
| P28 | In anything a human reads, the name wraps the id ('Tag filter chip (T004)'), never bare id lists | plugins/flow/bin/lib/router.js:589-591 (building) and :606-613 (gating) |
| P29 | A deferral is not a rejection: remove cost as a SKIP trigger from the borrow rubric | docs/research/23-pstack-rubric.md:36 (SKIP rule) and :25 (B6 row) |
| P30 | lesson --retro judges no-ops with the run-to-settle test, not just a label | plugins/flow/skills/lesson/SKILL.md:31 |
| P31 | Questionnaire for spec Open Questions owned by a third party: interview the user only about the recipient and what is needed back; questions ordered most-important-first, | plugins/flow/flow-templates/spec.md:103 |
| P32 | Ship a dependency-cruiser template for design.md row 4: $1 back-reference sibling isolation, depth decides privacy, merge into an existing config and never overwrite it,  | plugins/flow/skills/spec/references/design.md:33 (row 4) and the CONFIRMATION field of the |
| P34 | User-invoked handoff skill for non-flow conversations: write a redacted summary file outside the repo that points to artifacts by path, names the skills the next agent sh | new plugins/flow-extras/skills/handoff/SKILL.md |
| P35 | Slash-only audit: human-only skills get disable-model-invocation and a one-line human description; where both a slash name and auto-trigger are wanted, use a zero-load al | docs/decisions.md:19 |
| P36 | Write model-side cross-skill dependencies as 'Call the Skill tool with "<name>"' | plugins/flow/skills/no-slop/SKILL.md:63, plus other model-side 'load <skill>' instructions |
| P37 | Smoothbrain grounding: a grounded-concept ledger (a part, step or detail section leans only on concepts the page has already shown, or that the reader brought) | plugins/design/skills/smoothbrain/SKILL.md §3 (after :36-42, zoom ladder) and §'It is work |
| P38 | Prose rubric: 'name the gap or cut': never invent an example, number or case to fill a missing one | plugins/flow/skills/no-slop/references/prose-rubric.md (new NP-13 in table A, grader mappi |
| P40 | Read a skill's SKILL.md (or the tool's source) before calling it a duplicate or a gap; a name match is not evidence | plugins/flow-extras/skills/claude-improver/SKILL.md:87 (Phase 2 duplication check) |
| P42 | Record the upstream SHA in borrowed-file attribution lines, and re-diff borrowed files at each borrow review | every attribution line found by `grep -rnE -i '(adapted/borrowed/credit).*(mattpocock/skil |

## Judged not good

- P12 Prototype-snippet exception to 'no code in specs': Flipped to false: it duplicates what flow already has.
- P14 Prove the forced mutation landed before trusting a red: Flipped to false.
- P15 Component tree option in the PR summary for UI changes: Flipped to false.
- P33 After adding a boundary or lint rule, add a CLAUDE.md pointer to the README that explains it: The rejection holds and is confirmed.
- P39 'It's working if' signals must be checkable in the user's own work without opening SKILL.md, and a description: FLIPPED to false.
- P41 Multiple-choice options have equal length and the correct position varies: FLIPPED to false.
- P43 Adopt tdd, to-spec, implement and implement-spec as skills: Unchanged.
- P44 Frontier scheduling instead of wave barriers: Kept false and corrected the citation: the wave-then-stop rule is at next/SKILL.md:50, not :53.
- P45 Integration-branch fallback for migrate batches that cannot stay green: Unchanged.
- P46 Report standards and spec findings separately and never re-rank across axes: Kept false and fixed the reasoning.
- P47 Re-adopt the pr and diagnosing-bugs skills: Unchanged.
- P48 codebase-design vocabulary skill and improve-codebase-architecture HTML report as standalone skills: Kept false.
- P49 domain-modeling skill (glossary and ADR upkeep) and the three-test ADR gate: Confirmed, no change.
- P50 One shared grilling primitive loaded by name by grill-me, grill-with-docs and prep: Confirmed, no change.
- P51 triage and setup-matt-pocock-skills (labels, tracker configuration, incoming-issue triage): Confirmed, no change.
- P52 wayfinder as a skill, including claim-before-work, create-then-wire and native GitHub blocked_by: Confirmed, no change.
- P53 ask-matt router and the phase-boundary decision tree (continue before /clear): Confirmed, no change.
- P54 Frame the problem, show it, then fan out subagents: Verdict kept, reason replaced.
- P55 Upstream handoff skill (productivity) and next/SKILL.md `claude --bg` offer: Confirmed, no change.
- P56 wait-what skill (STE re-pitch): Confirmed duplicate, no change.
- P57 git-guardrails skill as a whole, plus its pipe-a-payload hook test: Confirmed, no change.
- P58 migrate-to-shoehorn / fromAny in tests: Confirmed, no change.
- P59 scaffold-exercises and setup-pre-commit: Confirmed, no change.
- P60 chief-of-staff (improvement hunt every turn, no-workarounds rule) and loop-me (automation designer, push right: Confirmed; citation tightened.
- P61 teach skill (workspace MISSION, learning records, spaced due dates, glossary after use, equal-length quizzes, : Verdict upheld.
- P62 writing-beats, writing-fragments and writing-shape as skills: Verdict upheld.
- P63 Per-skill docs pages (.agents/writing-docs.md): Verdict upheld.
- P64 SCOPE.md plus a per-concept .out-of-scope/ ledger for flow, and a per-upstream skip ledger: Verdict upheld.
- P65 Repo conventions: router-sync rule, harness-owned recursion limits, link-skills.sh: Verdict upheld.
- P66 'Too many questions is quality' and 'pickers anchor answers' rationale notes: Verdict upheld.
- P67 Verify the claim before grilling; lead with the recommended answer: Verdict upheld, citation made sharper.
- P68 Capture observations, step for secrets, in HITL loops: Verdict upheld and confirmed by diff.
- P69 'Done means zero questions', 'point, don't duplicate' and the observed-failure bar: Verdict upheld, one citation fixed.

## Ways of working and the set as a whole

# mattpocock/skills re-review at 49dd158 (2026-10-10)

The upstream is untrusted data, cloned read-only at /home/tomas/.claude/jobs/20064eaf/tmp/mp/src. Flow paths below are relative to /home/tomas/Desktop/Projects/flow/.claude/worktrees/mattpocock-borrows-2/. Every idea was judged on fit and benefit only. Cost was never a reason to skip.

## What changed since the 10-07 review (f3fc563 to 49dd158)

- **49dd158, wizard template fixes.** Four real bugs, and the local copy still has all of them. Mr Claude diffed the upstream file against plugins/tooling/skills/wizard/template.sh:
  - `tput clear` can abort the wizard under `set -e`. The local line :36 has no fallback.
  - `_existing` stores the quotes when it reads a `KEY="x"` value back from .env (:97).
  - `write_env` does not set `$KEY` (:133-143).
  - There is no `run_wizard` wrapper, so editing the file while the wizard runs can corrupt the running script (:190-210).
  - Also, `RED` is defined at :18 and :20 but never used.
  
  This is the one ADOPT.
- **8267225, retro always loads writing-for-agents.** Retro now loads the writing guide even when it only judges. flow's `lesson --retro` judges "Steering bloat" and "No-ops" (plugins/flow/skills/lesson/SKILL.md:29,31) without any definition loaded. A flow skill cannot reach into flow-extras by relative path, so the fix is a definition that flow owns (P30).
- **b0618bc, README.** Nothing to borrow.
- **Re-judged skips.** Under the "cost is never a reason" rule, five earlier skips that were really "not now" or "niche" are re-judged as good:
  - prototype (P16, P17)
  - setup-ts-deep-modules (P32, with fit evidence from finance/.dependency-cruiser.cjs)
  - to-questionnaire (P31)
  - research (P23)
  - claude-handoff, for non-flow conversations only (P34)
  
  Parts of code-review, codebase-design and to-tickets also come back as small merges (P04-P09, P18-P22). teach stays out on fit: nothing under ~/Desktop/School has changed since 2026-05-11. Mr Claude asks whether the user is still studying (P61).

## Layer C: ways of working (0-5)

| Row | mattpocock | flow | Evidence (upstream, then flow) |
|---|---|---|---|
| C1 Entry and routing | 3 | 4 | Upstream splits skills into user-invoked and model-invoked through the `disable-model-invocation` flag (.agents/invocation.md:5), plus a prose router (skills/engineering/ask-matt/SKILL.md). flow computes the position: "Read `flow next --json` FIRST" (plugins/flow/skills/next/SKILL.md:12). |
| C2 Composition | 4 | 3 | Upstream defines one grilling primitive and loads it by name, so grill-with-docs is a single line (grill-with-docs/SKILL.md:7). Cross-skill calls are written as "Call the Skill tool with" (invocation.md:16-20). flow has three interview texts (flow-extras grill-me, grill-with-docs, flow prep). writing-for-agents lives in flow-extras, where flow cannot load it, and no file in plugins/flow/skills references it. |
| C3 Verification culture | 2 | 5 | Upstream's "done" is the agent saying so. The one exception is the pass, fail, pass check in setup-ts-deep-modules/SKILL.md:79-87. flow has the RED hard gate, PASS-<sha>, the blind re-score in review-diff.js:67-78, and the lesson red-then-green rule (lesson/SKILL.md:88-95). |
| C4 Delegation and context | 3 | 4 | Upstream: frontier scheduling (implement-spec/SKILL.md:13,34) and design-it-twice with constrained subagents (codebase-design/DESIGN-IT-TWICE.md:21-28). flow hands each developer only the brief path (next/SKILL.md:53), and its workflows use JSON schemas (build-slices.js). |
| C5 Learning loop | 3 | 4 | Upstream has retro, an observed-failure bar (SCOPE.md:9) and a rejection ledger (.out-of-scope/). flow has the lesson ladder with red-then-green and an adversary. But flow-deepen reads `.out-of-scope/` (flow-deepen/SKILL.md:41) and nothing ever writes it. |
| C6 Human contact | 3 | 4 | Upstream: frontier rounds, where a bare "yes" accepts the recommendation (grilling/SKILL.md:8,24-28), and the HITL wizard. flow states its stop count, and `--finish` pre-approves gates when the user is leaving (next/SKILL.md:103,112). |
| C7 Long runs | 2 | 5 | Upstream has no caps and no resume. `claude --bg` handoff is beta (in-progress/claude-handoff). flow's loop has caps, a negative control and `--yolo` (loop/SKILL.md:20-30), and position is recomputed from disk. |
| C8 Writing quality | 4 | 4 | Upstream: writing-for-agents, the format rules in writing-shape/SKILL.md:57-67, and to-questionnaire. flow: NP-01 to NP-12 checked by `slop-check --prose` (plugins/flow/skills/no-slop/references/prose-rubric.md:20-36). |
| C9 Personalisation | 2 | 2 | Upstream's setup skill configures a tracker and labels only. flow's per-project knobs are thresholds and autoApprove only. |
| C10 Maintenance | 3 | 4 | Upstream: changesets and `sync-plugin-version.mjs --check` (scripts/sync-plugin-version.mjs:22-27). flow has script and hook suites, but the version-bump rule lives in a prose memory and has been missed before (#16, fixed in #17). test_marketplace.sh has no version-equality check (grep finds only :69), and the borrowed wizard template went stale. |
| **Total** | **29** | **39** | |

No row has upstream ahead by 2 or more. Its best row is C2, ahead by 1. The fixes that row points to are small: name the Skill tool at cross-skill pointers (P36), and give flow its own definitions instead of paths into flow-extras (P30). Merging the three interview texts is ruled out, because grill-me and prep differ on purpose (P50).

## Layer E: the whole set

**1. Thesis.** Upstream's belief is that small prose skills sharing one vocabulary, each defined once and composed by name, make agents better engineers. Examples of that vocabulary are seam, deep module, tracer bullet, frontier, and deferral versus rejection. The vocabulary half is right, and flow has absorbed most of it. The "prose is enough" half is wrong for long runs. Upstream has no gate, no cap and no proof, and flow beats it on every mechanism row (C3, C7, C10). Verdict: borrow vocabulary and small rules. Take none of the control flow.

**2. Overlap map.**

| Upstream piece | Flow piece | State |
|---|---|---|
| diagnosing-bugs | fix + fix/feedback-loops.md | absorbed on 10-07. The forced-mutation proof is still missing (P14). |
| tdd, mocking | no-slop developer-block.md:56-60 | absorbed. SDK-style mock shaping is missing (P13). |
| to-spec | flow:spec, question-bank, design.md | covered. Three tricks remain (P10-P12). |
| to-tickets | next §Drafting (expand, migrate, contract) | partial. There is no vertical-slice or prefactor rule, and the template example is layered (P08, P09). |
| implement, implement-spec | next §Building, build-slices.js | covered. Frontier over barrier is rejected on purpose. |
| code-review | review-diff.js, next/review.md, adversary.md | partial. No lens checks the repo's own standards, and `reviewMd` has no caller (P04-P07). |
| pr | shared/pr-body.md | absorbed. A component-tree option is missing (P15). |
| prototype | design:showcase (mocked shell), impeccable live (element HMR), prep spike (answer only) | partial. There is no whole-page variant switcher on the real route and no liftable logic demo (P16, P17). |
| codebase-design, improve-codebase-architecture | flow-deepen | partial. Missing: the deletion test, the 2-adapter rule, dependency categories, rejection memory, and design-it-twice (P18-P22). |
| research | research-sweep.js | partial. Web only, and the result is text in chat (P23). |
| wayfinder | prep split signal (prep/SKILL.md:106-107) | partial. Missing the fog-or-ticket test and background fact lookups (P26). |
| triage | flow:issue | partial. Dedupe is by keyword only (P24, P25). |
| retro, writing-for-agents | lesson --retro, skill-improver/references/writing-for-agents.md | partial. The definitions are not reachable from flow (P30). |
| grilling, grill-me, grill-with-docs | flow-extras grill-*, prep | covered. The differences are deliberate. |
| git-guardrails | hooks/git-guard.sh | stronger in flow, apart from one gap: plain `git checkout .` (P03). |
| wizard | tooling/wizard | stale (P01). |
| setup-ts-deep-modules | spec/references/design.md:33 asks for config, ships none | gap (P32). |
| to-questionnaire | spec Open Questions (spec/SKILL.md:21) | gap for questions owned by a third party (P31). |
| claude-handoff | PROGRESS.md, next --finish | covered for flow builds. Gap for non-flow conversations (P34). |
| sync-plugin-version.mjs | prose memory bump-plugin-version | gap (P02). |
| teach, writing-*, loop-me, chief-of-staff, triage, setup, scaffold, shoehorn | none | no fit. |

**3. Gaps and where each belongs.**
- **flow plugin.** Most of the list lives here:
  - code-review standards and the REVIEW.md wiring (P04-P07)
  - vertical slicing plus the existing slice judge (P08, P09)
  - spec tricks (P10-P12)
  - developer block (P13) and lesson (P14, P30)
  - pr-body (P15) and prep (P16, P26, P27)
  - flow-deepen (P18-P22) and research-sweep (P23)
  - issue (P24, P25)
  - the questionnaire under spec (P31) and the depcruise template under spec (P32)
  - git-guard (P03) and the version test (P02)
- **design plugin:** whole-page variants on the real route as a note in impeccable live (P17), and grounding rules for smoothbrain (P37).
- **flow-extras:** the handoff skill for non-flow conversations (P34), the slash-only audit (P35), and verify-skill and skill-forge wording (P39, P40).
- **tooling:** the wizard fixes (P01) and the agent-evals multiple-choice rule (P41).
- **docs/research:** the deferral-is-not-rejection rule (P29) and the upstream SHA for borrowed files (P42).

Nothing upstream justifies a new flow skill. teach would be the only candidate, and only if the user is studying again.

## Merit build list (summary)

**Good, 42 items.**

- **Automatic checks or hooks:** P01 wizard fixes, P02 version drift test, P03 `git checkout .` block, P06 empty-diff refusal.
- **Review:** P04 standards lens with REVIEW.md, P05 REVIEW.md pointer moves to reviewers (needs a user ruling), P07 smell names.
- **Planning and spec:** P08 vertical slices, P09 wire the slice judge, P10 seams, P11 test prior art, P12 prototype snippet.
- **Build and fix:** P13 SDK mocks, P14 forced-mutation proof, P15 component tree.
- **Prototyping:** P16 logic demo, P17 real-route variants.
- **flow-deepen:** P18 heuristics, P19 replace-don't-layer, P20 rejection memory, P21 design it twice, P22 named wins.
- **Research, issue and prep:** P23 research-sweep, P24 and P25 issue, P26 and P27 prep.
- **Output and docs:** P28 names wrap ids, P29 rubric rule, P30 retro definitions, P31 questionnaire, P32 depcruise template.
- **flow-extras, design and tooling wording:** P34 handoff, P35 slash-only audit, P36 Skill-tool wording, P37 smoothbrain grounding, P38 prose rows, P39 verify-skill and skill-forge, P40 read before recommending, P41 MC option lengths, P42 borrowed-file SHA.

**Not good:** P33 and P43 to P69, each with its reason in the items.

**Rulings needed from the user:**
- P05: should implementers stop being pointed at REVIEW.md?
- P35: which skills should become slash-only?
- P61: is the user still studying (teach)?

