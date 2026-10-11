# Famous skill repos borrow review — 2026-10-10

Eight of the most-starred agent-skill repos, picked by a scout (4 search angles, star counts read with `gh`, ranked by fame x new ideas for this user), reviewed with the borrow rubric in [`23-pstack-rubric.md`](23-pstack-rubric.md): B7 Fit from the user profile, and cost never a reason to skip.

| Repo | Stars (2026-10-10) | Rows scored | ADOPT | ADAPT | MERGE | SKIP | Candidate ideas |
|---|---|---|---|---|---|---|---|
| obra/superpowers | 297k | 51 | 0 | 4 | 19 | 28 | 37 |
| github/spec-kit | 141k | 113 | 0 | 1 | 13 | 99 | 32 |
| garrytan/gstack | 136k | 84 | 3 | 3 | 29 | 49 | 47 |
| addyosmani/agent-skills | 104k | 67 | 0 | 2 | 23 | 42 | 50 |
| anthropics/claude-plugins-official | 38k | 159 | 5 | 11 | 32 | 111 | 62 |
| Fission-AI/OpenSpec | 72k | 108 | 0 | 3 | 21 | 84 | 30 |
| vercel-labs/agent-skills | 32k | 55 | 7 | 2 | 16 | 30 | 46 |
| anthropics/skills | 180k | 95 | 1 | 7 | 16 | 71 | 42 |

## Method

- Per repo: a mapper split it into review slices; one Opus reviewer per slice scored layers A, B (B1-B7) and D; one Opus skeptic per slice corrected the scores; one Opus judge wrote layers C and E and candidate build items. 98 agents.
- One merge agent folded 346 candidates from the eight repos into 248 items; six Opus skeptics re-checked every verdict. 192 were judged good.
- A planner cut the good items into 14 file-disjoint lanes plus a serial lane (40 slices). Each slice: Sonnet developer, Opus adversary, one fix round. Then an integration slice and a split of `build-slices.js` into a parent and a per-task child workflow (`build-slices-task.js`) to stay under the size guard, proven identical by a 165-call differential and a live probe of nested `workflow()`.

## Built

190 of 192 good items are built. Skipped on purpose:

- F85 Deterministic spawn order so Workflow resume replays from the journal: needs a live kill-and-resume probe of the Workflow journal before the spawn order is rewritten.
- F86 Record tokens and duration per subagent in build-slices results, shown on demand in digest: the Workflow agent() result exposes no token or duration data.

| ID | Idea | Sources | Where |
|---|---|---|---|
| F01 | flow tick runs the task's verify: and refuses to tick on non-zero | obra_superpowers skills/executing-plans/scripts/task-done:39-51 (OBR01); flow gap plugins/ | plugins/flow/bin/lib/tick.js |
| F02 | Zero tests executed is red at the gate: check-all reports executed/skipped counts, the PASS table gains Executed plus a 'Not checked:' line, and a missing fixture fails instead of skipping | garrytan_gstack ship/sections/tests.md.tmpl:41-53, review/gate-integrity.md:146-156 (GAR01 | plugins/flow/skills/shared/scripts/check-all (JSON fields only) |
| F03 | Capture a gate's exit code before any pipe, tail or parser | github_spec-kit .github/workflows/bug-test.md:244-246 (GIT08); garrytan_gstack health/SKIL | plugins/flow/skills/shared/verification.md |
| F04 | Record the Test: baseline at Base for every spec, and call a red gate pre-existing only with that baseline (or a Base rerun) as proof | obra_superpowers skills/using-git-worktrees/SKILL.md:121-130,167 (OBR14); garrytan_gstack  | plugins/flow/skills/next/SKILL.md:46 and :72 (Gates step 1) |
| F05 | Free text to git and gh goes through a file or a quoted heredoc (git commit -F, gh --body-file), never shell interpolation | github_spec-kit extensions/git/commands/speckit.git.commit.md:36 (GIT13); garrytan_gstack  | plugins/flow/skills/next/SKILL.md:57 |
| F06 | Guard denies `git worktree remove --force/-f` and plus-refspec pushes (+main, +HEAD:main) | obra_superpowers skills/finishing-a-development-branch/SKILL.md:159-201,221-222 (OBR04); g | plugins/flow/hooks/git-guard.sh (sub list :52 |
| F07 | Ask tier: data-destroying infra CLIs and shell obfuscation get permissionDecision ask | garrytan_gstack careful/bin/check-careful.sh:81-110,223-352 (GAR07) | new plugins/flow/hooks/infra-guard.sh registered in plugins/flow/hooks/hooks.jso |
| F09 | QA never stashes or checks out the user's tree | garrytan_gstack qa-only/SKILL.md.tmpl:204-208 (GAR09) | plugins/flow/skills/qa/SKILL.md:13-20 and :326-330 |
| F10 | QA findings separate Observed from Hypothesis, and a ship-blocker is replayed before it is called confirmed | garrytan_gstack qa-only/sections/reporting.md:10-23,39-49, qa-only/sections/exploratory.md | plugins/flow/skills/qa/SKILL.md:149-156 (Step 3 report) |
| F11 | Functional contract map for non-browser QA (API, CLI, jobs, webhooks) | garrytan_gstack qa/sections/system-functional.md:40-45 (GAR11) | new plugins/flow/skills/qa/references/functional-contracts.md |
| F12 | flow:qa --fix mode routed through flow:fix with a self-regulating stop rule | garrytan_gstack qa/SKILL.md.tmpl:242-249 (GAR13) | plugins/flow/skills/qa/SKILL.md (new --fix section after Step 4a) |
| F13 | Browser content is untrusted data, prefer an isolated profile, and mutating actions on non-LOCAL hosts need one explicit question (LOCAL includes *.pc) | addyosmani_agent-skills skills/browser-testing-with-devtools/SKILL.md:62-90 (ADD23); garry | plugins/flow/skills/shared/claude-in-chrome-reference.md |
| F14 | Error, stack trace and CI log text is untrusted: suggested commands are surfaced, never executed | addyosmani_agent-skills skills/debugging-and-error-recovery/SKILL.md:670-677 (ADD33) | plugins/flow/skills/fix/SKILL.md §0 step 2 (near :23) and plugins/flow/agents/tr |
| F15 | Redact URLs and secrets before persisting captured issue or bug text; a failed dedupe search is a failure, not 'no duplicates' | github_spec-kit extensions/assess/commands/speckit.assess.intake.md:72,76 (GIT14); garryta | new plugins/flow/scripts/redact (extracted from handoff.sh redact |
| F16 | Secrets never pass through chat: route capture to hidden entry into a gitignored 0600 file, verify by pattern without printing, send a token check only to its own host, unset env keys that shadow the  | anthropics_claude-plugins-official mcp-tunnels/commands/create-docker-mcp-tunnel.md:72-77, | new plugins/flow/skills/shared/secrets.md |
| F17 | Sanitize outgoing web-search queries: no client hostnames, IPs, internal paths, identifiers or secrets | garrytan_gstack investigate/SKILL.md.tmpl:176,192, office-hours/SKILL.md.tmpl:175-179 (GAR | plugins/flow/workflows/research-sweep.js (the decompose prompt at :69-70 and the |
| F18 | Frontmatter lint: strict-YAML parse, name kebab-case <=64 and == dir, description 1-1024 chars, unique names, agent name == filename and model in an allowed set; skill-judge Step 0(b) calls it | addyosmani_agent-skills scripts/lib/skill-lint.js:197-323,391-396 (ADD10); anthropics_clau | new plugins/flow/scripts/skills-lint-frontmatter.py |
| F19 | Retarget the frontend-design:frontend-design calls to flow's own design plugin and test that every cross-plugin skill call resolves in the marketplace | anthropics_claude-plugins-official plugins/frontend-design/skills/frontend-design/SKILL.md | plugins/flow-extras/skills/brainstorm/SKILL.md |
| F20 | Orphan check: every references/* and scripts/* file in a skill is mentioned from its SKILL.md or from a file that SKILL.md reaches | vercel-labs_agent-skills react-native-skills/SKILL.md:44-101, react-best-practices/SKILL.m | the stdlib helper from F18 (skills-lint --orphans) |
| F22 | Dead-path check for CLAUDE.md, .claude/rules and PROGRESS.md Ruling lines | anthropics_claude-plugins-official claude-md-management/skills/claude-md-improver/referenc | the stdlib helper from F18 (--claude-md mode) |
| F23 | Pairwise skill-description collision report (warn-only, on demand) | addyosmani_agent-skills scripts/run-evals.js:372-387 (ADD11) | the stdlib helper from F18 (skills-lint --collisions) |
| F24 | flow doctor warns on duplicate bare skill names across installed on-disk sources | addyosmani_agent-skills docs/comparison.md:119, docs/getting-started.md:47 (ADD12) | plugins/flow/bin/lib/doctor-hygiene.js |
| F25 | Two small deterministic lints: chat residue left at the tail of a shipped prompt, and ((n++)) in a set -e bash script. The CLAUDE_ENV_FILE capture and the plugin MCP tool-name note are dropped. | anthropics_claude-plugins-official plugin-dev/agents/plugin-validator.md:184 (residue: 'Ex | plugins/flow/scripts/skills-lint (residue tail check) or a sibling check run by  |
| F26 | Shared-paragraph parity rule in skills-lint | Fission-AI_OpenSpec skills/README.md:17-19 (FIS06) | plugins/flow/scripts/skills-lint (or a sibling script that plugins/flow/scripts/ |
| F27 | Skill descriptions name situations and triggers, not a workflow summary; skill-judge D4 checks it | obra_superpowers skills/writing-skills/SKILL.md:150-158 (OBR22); addyosmani_agent-skills d | plugins/flow-extras/skills/skill-judge/SKILL.md D4 checklist (:181-189); plugins |
| F28 | Match instruction form to failure type; no nuance clauses (replaces the blanket negation rule) | obra_superpowers skills/writing-skills/SKILL.md:461-476, docs/superpowers/specs/2026-06-10 | plugins/flow-extras/skills/skill-improver/references/writing-for-agents.md:73 (r |
| F29 | Micro-test wording with a no-guidance control that must fail first | obra_superpowers skills/writing-skills/SKILL.md:577-587, docs/superpowers/specs/2026-06-10 | plugins/flow-extras/skills/skill-forge/SKILL.md Step 4 (refinement of a NEVER or |
| F30 | Meta-test the miss before editing a skill | obra_superpowers skills/writing-skills/testing-skills-with-subagents.md:240-265 (OBR21) | plugins/flow-extras/skills/skill-forge/SKILL.md Step 4 (new row or subsection be |
| F31 | skill-forge authoring rules: run scripts with --help instead of reading source, scripts print the step they cannot do, a 'What X does NOT have' section, a script I/O contract consistent with lesson's  | anthropics_skills docx/SKILL.md:21, pptx/SKILL.md:31, webapp-testing/SKILL.md:14,85, docx/ | plugins/flow-extras/skills/skill-forge/SKILL.md 2c/2d; plugins/flow-extras/skill |
| F32 | Trigger-rate eval plus a held-out, blinded description optimiser in skill-improver | anthropics_claude-plugins-official skill-creator/scripts/run_eval.py:51-64,80-83,128-155,2 | new plugins/flow-extras/skills/skill-improver/scripts/trigger-eval and optimise- |
| F33 | Eval case authoring rules: near-miss negatives that name the skill that should not win, messy user-worded prompts, seed-anchored synthesis, simple one-step asks never trigger, iterate on top-K varianc | anthropics_claude-plugins-official skill-creator/SKILL.md:348-358,396-400 (ANT27); addyosm | plugins/flow/evals/README.md 'Adding a case' (:100-116) and Cost; plugins/flow/s |
| F34 | Eval fixture rules: realistic fixtures, scaffold sanity assertions, enforce the existing scaffold guard, decision-only prompts | obra_superpowers docs/superpowers/specs/2026-07-06-sdd-plan-scoped-workspace-eval-results. | plugins/flow/evals/README.md Case shape / scaffold convention (:32-38); plugins/ |
| F35 | llm graders carry the burden of proof and critique the eval; an eval-audit reference in agent-evals | anthropics_claude-plugins-official skill-creator/agents/grader.md:9,39-40,68-79,96-99 (ANT | plugins/flow/scripts/case-selfcheck JUDGE_SYSTEM (:386) and its live output; plu |
| F36 | Per-grader discrimination classes and spread in flow eval's summary | anthropics_claude-plugins-official skill-creator/agents/analyzer.md:214-218, scripts/aggre | plugins/flow/bin/lib/eval.js tagRollup/printSummary; its unit tests under plugin |
| F37 | Known-negative probe for llm graders in case-selfcheck --live | anthropics_skills claude-api/shared/evals/eval-audit.md:179 (ANT07); flow gap: plugins/flo | plugins/flow/scripts/case-selfcheck (new --probe-judges flag |
| F38 | Errored eval runs are excluded from means and listed; unmeasured cost is null, never $0 | anthropics_skills claude-api/shared/evals/build-eval.md:112-114,230, evals/report/SCHEMA.m | plugins/flow/scripts/case-selfcheck (live_run_one |
| F39 | Record a grader hash per eval case in ledger lines and mark history rows where graders changed | vercel-labs_agent-skills vercel-optimize/lib/gates/index.mjs:44-45 (VER23); anthropics_ski | plugins/flow/bin/lib/eval/contract.js ledgerLine (owner: orchestrator); plugins/ |
| F40 | loop --metric: optional holdout veto and a confirm re-measure for keeps near the noise bar | anthropics_skills claude-api/shared/evals/eval-hillclimb.md:205-207,227-229, eval-audit.md | plugins/flow/bin/lib/loop/metric.js (metricStep |
| F41 | Metric-loop pivot note: bucket the remaining failures before another content change; each commit states a prediction and a falsifier | anthropics_skills claude-api/shared/evals/eval-hillclimb.md:41,233,241,269,271,279-295, co | plugins/flow/bin/lib/loop/metric.js metricNote (PIVOT_AFTER branch); skills/loop |
| F42 | Blind pairwise A/B with an order swap as skill-improver's evidence for behaviour prompts that have no scorer | anthropics_claude-plugins-official skill-creator/agents/comparator.md:3-9,37-58,196, agent | plugins/flow-extras/skills/skill-improver/SKILL.md Step 2f item 4 (one short par |
| F43 | skill-improver: 'no finding means no edit' as a valid outcome, and a code helper rewritten in 2+ eval transcripts becomes a bundled script | anthropics_skills claude-api/shared/prompt-audit.md:14,187-201, skill-creator/SKILL.md:300 | plugins/flow-extras/skills/skill-improver/SKILL.md Step 2b (budget) and Step 2f  |
| F44 | Stacked-pressure variant of the reproduce-first eval for /flow:fix | obra_superpowers skills/writing-skills/testing-skills-with-subagents.md:98-102,128-140,267 | plugins/flow/evals/invariant-reproduce-first-pressure/ (new: case.yaml |
| F45 | Historical-fix replay as an eval case type for /flow:fix | github_spec-kit .github/workflows/bug-test.md:257-280 (GIT05) | plugins/flow/scripts/case-selfcheck --live (a --replay <repo>@<fix-sha> mode) or |
| F46 | flow eval --changed: pick the cases affected by changed skills and the shared refs they link | github_spec-kit CONTRIBUTING.md:356-388 (GIT17). Flow partial coverage: plugins/flow-extra | plugins/flow/bin/lib/eval.js arg parsing plus plugins/flow/bin/lib/eval/cases.js |
| F47 | Every flow skill has an eval disposition: a selecting case, or an explicit 'no eval: reason' | github_spec-kit design/mcp.md:241-243 (GIT18). Flow partial coverage: plugins/flow/scripts | plugins/flow/scripts/tests/test_evals.sh (new t_evals_every_skill_has_dispositio |
| F48 | lesson --retro mining: a deterministic jsonl extractor feeds compact candidate rows; only real human turns count as corrections; detection for skills that should have fired | obra_superpowers skills/diagnosing-superpowers/references/context-safety.md:8-21, SKILL.md | plugins/flow/scripts/lesson-mine (new |
| F50 | Artifact review page for subjective skill evals with feedback carried across iterations | anthropics_skills skill-creator/eval-viewer/generate_review.py:213-247,361-378, skill-crea | plugins/flow-extras/skills/skill-improver/SKILL.md (optional step |
| F51 | Scoped re-review per finding after each fix round (FIX_BASE..HEAD, ADDRESSED/NOT_ADDRESSED, newBreakage, outOfScope) | obra_superpowers skills/subagent-driven-development/re-review-prompt.md:55-62,82-100, docs | plugins/flow/workflows/build-slices.js:241-279 |
| F52 | Fix-ladder triage: contract-misread findings fix the plan first, doubt-theater stop, and at the cap classify findings known-open / load-bearing (blocks the wave) or re-cut an oversize task | obra_superpowers docs/superpowers/specs/2026-07-15-sdd-fix-loop-redesign-design.md:82-97 ( | plugins/flow/workflows/build-slices.js:281-357 |
| F53 | Implementer may reject a finding with a receipt (path:line, command, or no-callers grep) | obra_superpowers skills/receiving-code-review/SKILL.md:67-98 (OBR10) | plugins/flow/skills/next/review.md §Fix ladder |
| F54 | Fix-round ledger lines in NOTES.md so a /clear mid-ladder resumes at the right round | obra_superpowers skills/subagent-driven-development/SKILL.md:144-145,405-406 (OBR15) | plugins/flow/skills/next/review.md §Fix ladder (inline mode) |
| F55 | Test moves and fix rounds must preserve the collected test-case set, not just the count | github_spec-kit design/cli.md:328-333 (GIT04); vercel-labs_agent-skills vercel-optimize/sc | plugins/flow/skills/flow-deepen/references/detection-heuristics.md:75 |
| F56 | cannotVerify slot for diff-only reviewers, checked by the orchestrator before tick | obra_superpowers skills/subagent-driven-development/task-reviewer-prompt.md:111-113,167-16 | plugins/flow/skills/next/review.md:27 |
| F58 | DONE_WITH_CONCERNS developer status with concerns[] passed to adversaries | obra_superpowers skills/subagent-driven-development/implementer-prompt.md:142,151-153 (OBR | plugins/flow/agents/developer.md:31-38 output contract |
| F59 | build-slices long-run discipline: carry earlier waves' gaps into later briefs, re-run verify instead of trusting it, per-wave breaker on runnable tasks | anthropics_claude-plugins-official code-modernization/workflows/uplift-migrate.js:154-166, | plugins/flow/workflows/build-slices.js |
| F60 | Deferred minors reach the whole-branch reviewer via '- Minor:' NOTES lines and digest | obra_superpowers skills/subagent-driven-development/SKILL.md:361-365, executing-plans/SKIL | plugins/flow/workflows/build-slices.js:107-117 |
| F61 | Tag unattended Assumptions mechanical / taste / challenge. A challenge keeps the user's stated direction and is not applied. The digest shows taste and challenge. | garrytan_gstack autoplan/SKILL.md.tmpl:78-95, ETHOS.md:138-147 (GAR19) | plugins/flow/skills/next/SKILL.md:122 (--unattended row) and §Finish rule 9 (lin |
| F62 | Reviewer severity clauses: grade by effect even where the spec is silent; a defect the plan mandates still blocks; new warnings in the test run are findings | obra_superpowers skills/executing-plans/SKILL.md:265-270, requesting-code-review/code-revi | plugins/flow/agents/adversary.md:65 (calibration guard) and :33 (correctness) |
| F63 | Adversary lens additions: trace enum siblings and loosened acceptance to every consumer; renamed negative assertions; user-facing strings and existing comments the change made false; blame and log of  | garrytan_gstack review/checklist.md:63-69,76,79,98-101, review/specialists/testing.md:66-7 | plugins/flow/agents/adversary.md:36 (cross-file: enum siblings |
| F64 | Security lens names LLM output as untrusted input and lists the checks for agent features | garrytan_gstack review/checklist.md:52-56,61 (GAR15); addyosmani_agent-skills agents/secur | plugins/flow/agents/adversary.md:34 (security) |
| F65 | Security predicates: trust follows whoever wrote a value; deletes on a computed path are confined; never disable the control that flagged you; surface outbound endpoints copied from docs | addyosmani_agent-skills skills/security-and-hardening/SKILL.md:25,117, references/security | plugins/flow/agents/adversary.md:34 (security; same edit as F64 and F66) |
| F66 | Sibling-path gate parity: when a guard is added to one handler, check its peers on the same resource | anthropics_claude-plugins-official plugins/security-guidance/hooks/review_api.py:83-85 (AN | plugins/flow/agents/adversary.md:34 (security; same edit as F64 and F65) |
| F68 | Silent-failure hunting: name what each added catch, fallback or default could hide; flag production fallbacks to mock or stub data; CONFIRMED needs a run | anthropics_claude-plugins-official plugins/pr-review-toolkit/agents/silent-failure-hunter. | plugins/flow/agents/adversary.md:33 (correctness bullet) |
| F69 | Executed mutation canary in review: break one load-bearing line in a scratch copy outside the repo, run the covering test, keep the red log | addyosmani_agent-skills skills/code-review-and-quality/SKILL.md:164 (ADD09); anthropics_cl | plugins/flow/agents/adversary.md:35 (gaming) |
| F70 | Developer test rules: wait on a condition with a timeout, mocks shaped like the real data, no production methods that only tests call | obra_superpowers skills/systematic-debugging/condition-based-waiting.md:60-80, test-driven | plugins/flow/skills/no-slop/references/developer-block.md:53-63 (Tests paragraph |
| F71 | Three named claims when reviewing a fix (TARGETED, NO_NEW_VULNERABILITY, BEHAVIOUR_UNCHANGED) plus an untested flag; any change in which inputs are accepted counts as a behaviour change | anthropics_claude-plugins-official plugins/claude-security/agents/patch-verifier.md:38-46, | plugins/flow/skills/fix/SKILL.md:108-111 (§5 review) |
| F72 | Tag each finding as on a line the diff touched or not; drop flaws that predate the change into Discovered lines; process-only CLAUDE.md rules are not findings | anthropics_claude-plugins-official plugins/claude-security/agents/scan-verifier.md:34, wor | plugins/flow/scripts/review-package (new --anchors output) |
| F73 | Refutation panel for security findings in review-diff (reachability, impact, defenses lenses; 2-of-3 TRUE_POSITIVE keeps; HIGH confidence only when unanimous; the panel can only lower severity) | anthropics_claude-plugins-official @ a9fd216: plugins/claude-security/agents/scan-verifier | plugins/flow/workflows/review-diff.js (Score phase split: lens=security -> Panel |
| F74 | Blind scorer in review-diff: Score sees the claim (predicate, location, failing input), not the finder's evidence or lens; a 100 says how it was verified; one fresh retry for a rejected finding | anthropics_skills skills/claude-api/shared/managed-agents-quickstarts/bug-hunter.md:61 ('g | plugins/flow/workflows/review-diff.js:118-128 |
| F75 | Mechanical receipt check: the cited file exists (at head or in the diff), the line is in range, and an optional verbatim quote appears near the cited line; a failed check dismisses the finding whateve | vercel-labs_agent-skills skills/vercel-optimize/lib/verify-claim.mjs:14-18 (never throws;  | new plugins/flow/scripts/receipt-check (+ tests in plugins/flow/scripts/tests) |
| F76 | Review lenses report which diff files they read; a zero-finding lens that skipped changed files is 'incomplete', not CLEAN; recall framing only where a scorer filters; the gating step must act on inco | garrytan_gstack codex/sections/review-mode.md.tmpl:139-173 (GAR27); github_spec-kit .githu | plugins/flow/workflows/review-diff.js (package step returns files[] |
| F77 | Normalised dedupe key with corroboration (lenses[]) in review-diff | vercel-labs_agent-skills skills/vercel-optimize/lib/dedup-recs.mjs:204-216 (normalizeFixTe | plugins/flow/workflows/review-diff.js:49-52 |
| F78 | Decide review-diff's 75 anchor vs the keep>=80 rule ('verified real, low impact' is always dropped) | anthropics_claude-plugins-official plugins/code-review/commands/code-review.md:20-26 (ANT5 | plugins/flow/workflows/review-diff.js:118-146 |
| F79 | Untrusted fence with marker stripping for agent-derived strings placed into later prompts | anthropics_claude-plugins-official plugins/code-modernization/workflows/harden-scan.js:32- | plugins/flow/workflows/review-diff.js:124 (and the F73 panel prompt) |
| F80 | PLAUSIBLE findings name the next evidence step, not a fix | vercel-labs_agent-skills skills/vercel-optimize/references/scoring.md:151, lib/observation | plugins/flow/agents/adversary.md:54 |
| F81 | A review that cannot spawn a fresh reviewer (nested subagent) never self-reviews; it stops and reports 'review not run: nested', and no PASS is written | addyosmani_agent-skills skills/doubt-driven-development/SKILL.md:44-47 (preferred path: su | plugins/flow/skills/next/review.md (after :8) |
| F82 | Advisory docs lens in review-diff: README/CLAUDE.md claims the diff made false (paths, counts, commands, renamed entities) are listed in the PR body | garrytan_gstack review/SKILL.md.tmpl:225-230, document-release/SKILL.md.tmpl:156-159, rele | plugins/flow/workflows/review-diff.js:59 |
| F83 | workflow-lint rules: no pre-judging phrases in review prompts; no haiku on judgment agents | obra_superpowers skills/subagent-driven-development/SKILL.md:339-344 (OBR09), docs/superpo | plugins/flow/scripts/workflow-lint (new rules 10-11) |
| F84 | Workflow preflight: missing or invalid args return {started:false, reason, next} before any agent runs, and the repo root is absolute and checked | anthropics_claude-plugins-official plugins/claude-security/workflows/scan.js:5-15 (bare in | plugins/flow/workflows/review-diff.js:54-74 |
| F87 | Ancestor-guard the review range | obra_superpowers skills/subagent-driven-development/scripts/review-package:25-28 (OBR11) | plugins/flow/scripts/review-package:88-93 |
| F88 | Spec-wide constraints reach every brief: design.md ## Constraints appended by task-brief, and field constraints carried in the task's Contract block | obra_superpowers docs/superpowers/specs/2026-06-10-strict-cost-sdd-design.md:97-103 (OBR12 | plugins/flow/skills/spec/references/design.md (Sections table and Contract block |
| F89 | Brief rules: state breadth ('every call site of X') and name a Follow exemplar file | garrytan_gstack model-overlays/sonnet-5.md:3-7, plan-ceo-review/SKILL.md.tmpl:151-152 (GAR | plugins/flow/skills/next/SKILL.md:46 §Drafting |
| F90 | ## Review focus block in TASKS.md, linted, handed to the whole-branch reviewer and to the named task's brief | obra_superpowers skills/writing-plans/SKILL.md:77-87,173-174 (OBR13) | plugins/flow/flow-templates/TASKS.md |
| F91 | Batch identical small edits into one task; a mechanical check that every files: entry was touched | obra_superpowers skills/subagent-driven-development/SKILL.md:223-229, task-reviewer-prompt | plugins/flow/skills/next/SKILL.md:46 §Drafting |
| F92 | Requirement coverage lint: every spec FR id appears in ## Behaviors, every cited id exists, every Behaviors row names an existing task | github_spec-kit templates/commands/analyze.md:110-112,141-144,176-177 (GIT01); Fission-AI_ | plugins/flow/scripts/flow-lint |
| F93 | Acceptance and contract edits after approval need an Amendment or Ruling: FR ids cannot vanish, FR rows cannot silently change, and a branch edit to spec/design cannot justify drifted code | garrytan_gstack review/gate-integrity.md:77-85, ship/sections/plan-completion.md.tmpl:41-4 | plugins/flow/scripts/flow-lint |
| F94 | An open question that decides the breakdown carries a 'blocks: tasks' marker, and lint refuses a TASKS.md over an unresolved one | Fission-AI_OpenSpec schemas/spec-driven/schema.yaml:182-187,205-207 (FIS05); garrytan_gsta | plugins/flow/flow-templates/spec.md:100-104 |
| F95 | Marker-vs-disk lint for Design:, Behaviour-preserving and Parity | Fission-AI_OpenSpec docs/examples.md:150 (FIS07) | plugins/flow/scripts/flow-lint (header rules near :851) |
| F96 | Split signal in spec discovery plus a split map artifact from prep | Fission-AI_OpenSpec docs/writing-specs.md:69 (FIS22); addyosmani_agent-skills skills/spec- | plugins/flow/skills/spec/SKILL.md §2 discovery |
| F97 | WARN on oversized tasks whose description joins two actions (verb-object and verb-object) | addyosmani_agent-skills skills/planning-and-task-breakdown/SKILL.md:133-141 (ADD28; the ci | plugins/flow/scripts/flow-lint (rule beside phase-no-goal at :354; help text at  |
| F98 | No generic explore/investigate tasks; discovery positions about current behaviour are marked observed (path:line) or assumed | Fission-AI_OpenSpec skills/openspec-propose/SKILL.md:120-122 (FIS18) | plugins/flow/scripts/flow-lint |
| F99 | Living current-truth behaviours file merged deterministically from archived ## Behaviors rows | Fission-AI_OpenSpec docs/concepts.md:46-50,378,393, openspec/specs/openspec-conventions/sp | new plugins/flow/scripts/spec-merge (+ scripts/tests/test_spec_merge.sh) |
| F100 | Spec discovery cites prior Behaviors rows whose tasks touched the footprint | Fission-AI_OpenSpec skills/openspec-sync-specs/SKILL.md, docs-lab/reference/schemas/spec-d | plugins/flow/skills/spec/SKILL.md:54 (extend the Archived Rulings paragraph) |
| F102 | flow archive subcommand with move guards | Fission-AI_OpenSpec skills/openspec-bulk-archive-change/SKILL.md:232,244, openspec-archive | new plugins/flow/bin/lib/archive.js |
| F103 | --amend coherence: check design.md Contracts and Behaviors against the amendment before re-planning | Fission-AI_OpenSpec skills/openspec-update-change/SKILL.md:69,108, openspec/changes/add-up | plugins/flow/skills/spec/SKILL.md §7 (:91-100) |
| F104 | Removal and rename criteria are proven by exercising the old entry point, never by a missing grep match | Fission-AI_OpenSpec skills/openspec-verify-change/SKILL.md:103-117 (FIS04) | plugins/flow/skills/next/SKILL.md:75 (Gates step 3) |
| F105 | Cold-reader pass: a fresh agent holding only spec.md lists the builder questions a wrong guess would change | obra_superpowers skills/brainstorming/builder-check-prompt.md:7-22, SKILL.md:165-177 (OBR0 | plugins/flow/skills/spec/SKILL.md §5 (:77) |
| F106 | Discovery states the one case that must never break; it becomes the P0 Behavior | Fission-AI_OpenSpec docs/writing-specs.md:49, docs/reviewing-changes.md:71 (FIS09) | plugins/flow/skills/spec/references/question-bank.md (standing items near :34-43 |
| F107 | Spec-or-not test for requirement lines | Fission-AI_OpenSpec schemas/spec-driven/schema.yaml:71-72 (FIS19) | plugins/flow/flow-templates/spec.md:69 |
| F108 | Never fabricate content to satisfy lint or the judge; use the explicit none marker | Fission-AI_OpenSpec schemas/spec-driven/schema.yaml:36-42 (FIS20) | plugins/flow/skills/spec/SKILL.md §6 step 2 (:84) |
| F110 | Spec pieces: revert-history grep on the footprint, distribution channel position, distinct LLM failure modes. (The fewest-files alternative is dropped as a duplicate.) | garrytan_gstack plan-eng-review/sections/review-sections.md.tmpl:75-76 (revert grep), :326 | plugins/flow/skills/spec/SKILL.md §3 (after :54); plugins/flow/skills/spec/refer |
| F111 | Spec template UI state table (loading, empty, error, success, partial), only when a journey has a screen | garrytan_gstack plan-design-review/sections/review-sections.md.tmpl:46-55 (GAR18) | plugins/flow/flow-templates/spec.md §3 Journeys; plugins/flow/scripts/tests/test |
| F112 | 'Ask first' boundary tier in the spec template; a task that needs one returns BLOCKED | addyosmani_agent-skills skills/spec-driven-development/SKILL.md:110-113 (ADD29) | plugins/flow/flow-templates/spec.md (new §2.3 Ask first); plugins/flow/scripts/t |
| F113 | At least one acceptance check external to the agent-written suite | addyosmani_agent-skills skills/constraint-driven-development/SKILL.md:218-224 (ADD31) | plugins/flow/skills/spec/references/question-bank.md row 8 (:39); plugins/flow/f |
| F114 | Optional no_claim field on a task line: what green does not prove and which mocks stand in | garrytan_gstack spec/SKILL.md.tmpl:359, review/specialists/testing.md:105-108 (GAR17) | plugins/flow/scripts/flow-lint (known keys at :547 and usage at :21); plugins/fl |
| F116 | Rubric totals computed by a script, not by hand | garrytan_gstack health/SKILL.md.tmpl:192-205 (GAR40) | plugins/flow/skills/spec-judge/SKILL.md Step 4 (:448-451); plugins/flow-extras/s |
| F117 | plan-review rules: lens agreement never overrides a PREP D-NN; plan findings quote path:line; adjudicator states its own position before reading findings; artifact value test in the daily-usefulness l | garrytan_gstack autoplan/SKILL.md.tmpl:90-95 (user direction stands unless approved), plan | plugins/flow/workflows/plan-review.js (args |
| F118 | Show repo, worktree and branch context where the user sees it, without per-question prefixes | garrytan_gstack plan-devex-review/sections/review-sections.md.tmpl:270 ('Re-ground every q | plugins/flow/bin/lib/statusline.js render; plugins/flow/scripts/tests/test_statu |
| F119 | prep interview probes: the 'if you didn't have to justify it' probe on convention-signalling answers, and a one-clause reason beside any low-confidence word | addyosmani_agent-skills skills/interview-me/SKILL.md:51 (reason beside low confidence), :8 | plugins/flow/skills/prep/SKILL.md Step 3 rules 2 and 4 (:92-110); plugins/flow/s |
| F120 | A hedged reply is not approval | addyosmani_agent-skills .claude/commands/build.md:33 (ADD16) | plugins/flow/skills/next/SKILL.md :34 (unapproved) and :38 (unverified); plugins |
| F121 | Clean baseline before the first autonomous wave | addyosmani_agent-skills .claude/commands/build.md:32 (ADD17) | plugins/flow/bin/lib/finish.js cmdOn (:69) |
| F124 | User hand-edits to TASKS.md, PREP.md and NOTES.md are decisions, never reverted | Fission-AI_OpenSpec .agents/skills/draft-openspec-docs/SKILL.md:31 (FIS17) | plugins/flow/skills/next/SKILL.md NEVER list (:142-156) |
| F125 | flow:next reached casually in a repo with no flow state answers the request normally | Fission-AI_OpenSpec skills/openspec-propose/SKILL.md:36-39 (FIS21) | plugins/flow/skills/next/SKILL.md:29 and :156 |
| F128 | flow subcommands reject unknown flags with exit 2 (closest-slug suggestion dropped) | github_spec-kit docs/reference/presets.md:108-114, artifacts.md:226-241 (GIT19); Fission-A | plugins/flow/bin/flow (per-subcommand argv parsing) |
| F129 | flow publish dedupes by feature-scoped task id with a width-proof regex | github_spec-kit extensions/github/commands/speckit.github.taskstoissues.md:67 (GIT23) | plugins/flow/bin/lib/publish.js:40 |
| F130 | Project-declared extra gates (gates: [{name, cmd}]) in flow.config.json | github_spec-kit docs/reference/workflows.md:339-369,289-303 (GIT03) | plugins/flow/skills/shared/scripts/check-all (detectGates) |
| F131 | Redacted secrets scan as a CI gate step and in the audit playbook; dependency scan left out of the blocking gate | addyosmani_agent-skills .claude/commands/constraints.md:21, skills/constraint-driven-devel | plugins/flow/flow-templates/gates.yml.tmpl |
| F132 | detect-project's Python test_cmd uses the same resolution as check-all | github_spec-kit AGENTS.md:61-66, CONTRIBUTING.md:270-276 (GIT07) | plugins/flow/skills/shared/scripts/detect-project (detectPythonCommands :210-222 |
| F133 | Transliterate Icelandic and other non-ASCII letters in the new-spec slug | github_spec-kit scripts/bash/create-new-feature.sh:182-214,302-304 (GIT06); flow plugins/f | plugins/flow/scripts/new-spec slugify() and its usage text; plugins/flow/scripts |
| F134 | Size-guard feedback says split along a cohesive phase, never by line count alone | github_spec-kit design/cli.md:99-113 (GIT15); flow plugins/flow/hooks/size_guard.py:276-29 | plugins/flow/hooks/size_guard.py:327-331; plugins/flow/hooks/tests/test_quality. |
| F135 | Wider gate-relaxation detection: CI-config escapes in tamper-notice, suppressions and test-env sniffing in slop-check, and the same scan over Base..HEAD at gating | garrytan_gstack review/gate-integrity.md:87-126 (GAR03); addyosmani_agent-skills skills/co | plugins/flow/hooks/tamper-notice.sh (gate-config class); plugins/flow/skills/no- |
| F136 | 'Gate edits:' line in the PR body; UNAVAILABLE never prints as none | garrytan_gstack review/SKILL.md.tmpl:462-468, ship/sections/pr-body.md.tmpl:71-75, ship/SK | plugins/flow/skills/shared/pr-body.md (under ## Merge danger) |
| F137 | Direction-aware threshold diff: flag only loosening | addyosmani_agent-skills skills/constraint-driven-development/references/floor-guard.md:419 | plugins/flow/bin/lib/loop/tamper.js (THRESHOLD_KEY_RE |
| F138 | Guards distinguish 'could not run' (exit 2) from clean | addyosmani_agent-skills skills/constraint-driven-development/references/floor-guard.md:322 | plugins/flow/skills/no-slop/scripts/slop_diff.py |
| F141 | On-demand debug log of each hook's decision | addyosmani_agent-skills hooks/sdd-cache-pre.sh:27-34 (ADD39); flow plugins/flow/hooks/lib/ | plugins/flow/hooks/lib/hookout.sh (hook_ok |
| F142 | Edit-time security sink hook (PostToolUse Edit/Write), silent unless matched | anthropics_claude-plugins-official plugins/security-guidance/hooks/patterns.py:72-133,343- | new plugins/flow/hooks/security-patterns.sh (+ a python helper if needed) |
| F143 | Warning outcome sweep: fixed vs unresolved security-pattern hits, shown in flow digest | anthropics_claude-plugins-official security-guidance/hooks/security_reminder_hook.py:383-4 | plugins/flow/hooks/security-patterns.sh (append the hit to a state file); plugin |
| F144 | Keep an unconsumed turn stamp when a turn aborts before Stop | anthropics_claude-plugins-official security-guidance/hooks/security_reminder_hook.py:519-6 | plugins/flow/hooks/turn-stamp.sh |
| F147 | Under --unattended, /flow:fix stops when two causes remain equally supported | github_spec-kit .github/workflows/bug-fix.md:161-166 (GIT10) | plugins/flow/skills/fix/SKILL.md:79 and the §3 'Ending the turn' list (:159-164) |
| F148 | Debugging recipes: per-boundary logging, stack and inputs to stderr before a dangerous call, diff against a working sibling, three coupling-revealing failed fixes means an architecture question | obra_superpowers skills/systematic-debugging/SKILL.md:70-106,124-141,191-212, root-cause-t | plugins/flow/skills/fix/feedback-loops.md:56-61 |
| F149 | Two-way PR body vs diff check before gh pr create | github_spec-kit .github/workflows/pr-assess.md:118-141 (GIT11) | plugins/flow/skills/shared/pr-body.md:44 |
| F150 | Deploy order and rollback line in Merge danger; migrations have a tested down path | github_spec-kit docs/guides/contract-driven-development.md:241-258 (GIT20); addyosmani_age | plugins/flow/skills/shared/pr-body.md:29-32 only |
| F153 | babysit never pushes an empty commit to retrigger CI | Fission-AI_OpenSpec .agents/skills/release-openspec/SKILL.md:26,125 (FIS23) | plugins/flow-extras/skills/babysit/SKILL.md:66 |
| F154 | A clean exit is not a clean result: stamp artifacts before/after, a check that failed to start is 'not run', fresh read-only eyes judge UI screenshots on the next path | anthropics_skills xlsx/scripts/recalc.py:172-212, docx/scripts/accept_changes.py:76-80, cl | plugins/flow/skills/shared/verification.md:65 |
| F155 | Deploy verdict ladder: merge is not deploy, a 200 is not the live revision | garrytan_gstack land-and-deploy/SKILL.md.tmpl:436-447, canary/SKILL.md.tmpl:164-175 (GAR42 | plugins/flow/agents/claim-check.md:19; plugins/aws/skills/sst/references/deploym |
| F156 | Stream long commands: background with tee, follow with Monitor for banners, prompts and errors, state expected counts | anthropics_claude-plugins-official cwc-makers/skills/m5-onboard/SKILL.md:45-54, mcp-tunnel | plugins/flow/skills/shared/verification.md Step 2 (after :33) |
| F157 | Three missing a11y checks (skip link, 200% text resize, autocomplete on personal-data inputs) and a 320px reflow viewport in the Full verification tier | addyosmani_agent-skills references/accessibility-checklist.md:21,37,46, skills/frontend-ui | plugins/flow/skills/qa/references/qa-checklists.md (Accessibility Checklist |
| F158 | A parity gate must show it can go red when its command filters output, and its inputs must include at least one case outside the existing fixtures | anthropics_claude-plugins-official plugins/code-modernization/scripts/compare.py:338-372 ( | plugins/flow/skills/next/SKILL.md:46 (Parity sentences) |
| F159 | start-dev-server wrap mode: start the server, wait for the port, run a command, always kill the server's process group, exit with the command's code | anthropics_skills webapp-testing/scripts/with_server.py:63-102 (ANT25) | plugins/flow/skills/shared/scripts/start-dev-server |
| F160 | Version receipt for third-party API calls a repo has not used before, read from the installed package | addyosmani_agent-skills skills/source-driven-development/SKILL.md:281-304,386-420 (ADD01,  | plugins/flow/skills/no-slop/references/developer-block.md (after :36) |
| F162 | Developer agent: a 'Didn't touch' report item, and no repeat of a clean run on unchanged code | addyosmani_agent-skills skills/git-workflow-and-versioning/SKILL.md:191-209, skills/increm | plugins/flow/agents/developer.md:29-37 (Output contract) |
| F163 | Anti-narrowing: dropping or narrowing stated behaviour means BLOCKED; the narrowest reading applies only where the spec is silent | Fission-AI_OpenSpec skills/openspec-apply-change/SKILL.md:118,190-191 (FIS12) | plugins/flow/agents/developer.md:13 and Forbidden moves (:16-21) |
| F164 | research-sweep counts an angle as researched only when its search returned; failed angles appear as NOT COVERED in Gaps; claim-check treats a failed command as not checked, never as a contradiction | anthropics_skills claude-api/shared/managed-agents-quickstarts/watchlist-scanner.md:67 (AN | plugins/flow/workflows/research-sweep.js:86-120 |
| F165 | research-sweep always plans one disconfirming angle and writes an 'Evidence against' section | github_spec-kit extensions/assess/commands/speckit.assess.research.md:80-93 (GIT09) | plugins/flow/workflows/research-sweep.js:68-72 |
| F166 | research-sweep fetch discipline: each WebFetch asks for verbatim text about the claim, a paraphrased answer leaves the claim unconfirmed, and the checker upgrades SECONDARY citations to the primary so | anthropics_skills claude-api/shared/live-sources.md:16-23, managed-agents-onboarding-from- | plugins/flow/workflows/research-sweep.js:54-62 (CHECK_SCHEMA) |
| F167 | Check document claims: slop-check --prose --claims verifies paths, path:line ranges and backticked snippets; claim-check gains a doc mode for commands and counts, with a verified-how column | vercel-labs_agent-skills vercel-optimize/references/verification.md:28,31,60-62, lib/sanit | plugins/flow/skills/no-slop/scripts/slop_prose.py and slop-check (--claims flag) |
| F168 | Prose rubric additions: timeless docs, retrievability (the fact the reader returns for comes first), open questions asked inline rather than in a closing checklist, and minimizers 'easy'/'simply' (not | addyosmani_agent-skills references/definition-of-done.md:650, skills/documentation-and-adr | plugins/flow/skills/no-slop/references/prose-rubric.md (new NP-14 to NP-17 |
| F169 | benchmark-checklist rules: clock boundaries, missing metric is N/A (never 0), compare like coverage only, a change inside noise is reverted, attempt ledger, frozen-original randomized differential, ge | garrytan_gstack plan-devex-review/SKILL.md.tmpl:255-261, benchmark/SKILL.md.tmpl:95,138, h | plugins/flow-extras/skills/benchmark-checklist/SKILL.md: Step 3 question 4 (:25 |
| F170 | audit coverage: a Scanned/Skipped ledger for top-level dirs that a script checks against git ls-files, a lens that finds nothing records 'not scanned' or what it checked, a second-look pass per lens f | anthropics_claude-plugins-official code-modernization/workflows/harden-scan.js:161-168,222 | plugins/flow-extras/skills/audit/SKILL.md Phase 0 (:121 plan.md gets Scanned and |
| F171 | audit tests lens: a mechanical prefilter (tests with no assertion, near-duplicates), a retirement card before any test deletion, and a typecheck/build proof in a scratch worktree before removing produ | garrytan_gstack test-audit/SKILL.md.tmpl:72-103,139-140 (GAR31) | plugins/flow-extras/skills/audit/references/orchestration.md tests-agent line (: |
| F172 | audit playbook additions: per-item promise chaining and start-early/await-late (TS, and asyncio via TaskGroup/create_task), cheap condition before await, optimizePackageImports and literal dynamic imp | vercel-labs_agent-skills react-best-practices/rules/server-parallel-nested-fetching.md:28- | plugins/flow-extras/skills/audit/references/language-playbooks.md TypeScript Ant |
| F173 | Server Actions are public endpoints (auth inside every action), and module scope is process-wide memory shared across requests (Next.js and Python handlers) | vercel-labs_agent-skills react-best-practices/rules/server-auth-actions.md:12-14,54-93, se | Server Action auth: plugins/flow-extras/skills/audit/references/security-playboo |
| F174 | pentest report rules: a complete/partial/not-assessed header, a 'What was not examined, and why' section, supported findings separate from a labeled hypothesis appendix, a blind challenger that takes  | garrytan_gstack cso/SKILL.md.tmpl:97,129-135,148, cso/sections/audit-phases.md.tmpl:17,60- | plugins/tooling/skills/pentest/SKILL.md:205-224 (anchors |
| F175 | pentest checks: in-memory rate limiters on serverless and multi-instance, trust-proxy hop count, repo .claude/skills, hooks and CLAUDE.md as a trust boundary (supply chain), agent file tools confined  | addyosmani_agent-skills skills/security-and-hardening/SKILL.md:123, references/hardening-p | plugins/tooling/skills/pentest/references/cloud-and-iam.md §5 Serverless (:225 |
| F176 | MCP tool-contract rules in tool-design.md: conservative annotations (never readOnlyHint on an exec tool), a structured confirmation_required result (--json never implies force), retryable vs terminal  | github_spec-kit design/mcp.md:322-345,360-382, design/shared.md:256-271 (GIT16); anthropic | plugins/tooling/skills/agent-architecture/references/tool-design.md (new section |
| F177 | tooling:mcp-server skill for what flow lacks: server hygiene (logs to stderr on stdio, 127.0.0.1 bind with Origin validation, or the user's 0.0.0.0 LAN rule with a *.pc allowlist plus auth), Claude au | anthropics_claude-plugins-official mcp-server-dev/skills/build-mcp-server/references/elici | new plugins/tooling/skills/mcp-server/ (SKILL.md |
| F178 | MCP server eval method in agent-evals: blind question authoring, closed-data answers, NOT_FOUND, tool feedback, a fixed harness | anthropics_skills mcp-builder/reference/evaluation.md:146-151,197,206,314-325, scripts/eva | new plugins/tooling/skills/agent-evals/references/mcp-server-evals.md and script |
| F179 | Version-claims ledger for version-sensitive skills (rows: claim, where, verified date, re-verify command), with a lint that fails when the anchored claim text is no longer in the cited file | anthropics_claude-plugins-official mcp-server-dev/skills/build-mcp-server/references/versi | new plugins/flow/scripts/version-ledger-lint (wired into flow tests) |
| F180 | Agent anti-patterns: count model-call sites and move deterministic steps back to code, no checker loop for one-question-at-a-time Q&A agents, cache-invalidator grep signals plus a standing cache-hit t | anthropics_skills claude-api/shared/prompt-audit.md:181-182, managed-agents-multiagent.md: | agent-architecture/references/anti-pattern-gallery.md:16-18 (extend the existing |
| F181 | Session spend analyzer with cache-break detection for Claude Code transcripts | anthropics_claude-plugins-official plugins/session-report/skills/session-report/analyze-se | plugins/flow-extras/skills/ultracode/scripts/analyze-sessions.mjs |
| F182 | AgentCore build rules: viability walk, probe turn after deploy, an entry_point field in run logs, metadata-only logs of external calls, an induced-failure check on telemetry. Mid-turn harness text nev | anthropics_skills skills/claude-api/shared/managed-agents-onboarding.md:46 (silent viabili | plugins/aws/skills/strands-agentcore/SKILL.md Production Checklist (:305-314); r |
| F183 | version-audit checks Claude model IDs against the live catalog and classifies each file before a rename | anthropics_skills skills/claude-api/shared/models.md:3 (only exact IDs; WebFetch the live  | plugins/tooling/skills/version-audit/SKILL.md (new 'Claude model IDs' section) + |
| F184 | version-audit major-bump mode: writes a flow spec of hops with a T000 baseline, a pilot unit and a delta catalog limited to APIs the code actually uses | anthropics_claude-plugins-official plugins/code-modernization/agents/version-delta-analyst | plugins/tooling/skills/version-audit/SKILL.md (new 'Major upgrade plan' section  |
| F185 | SST: the agent deploys only to the personal stage, and discovery never deploys | vercel-labs_agent-skills skills/deploy-to-vercel/SKILL.md:11,51 (preview unless the user a | plugins/aws/skills/sst/SKILL.md :53 |
| F186 | Check that the active AWS account matches the repo's intended account before reads or plans | vercel-labs_agent-skills skills/vercel-optimize/references/data-collection.md:65 (stop on  | plugins/flow/skills/shared/aws-context.md (new step 4 after :23; new output fiel |
| F187 | Handoff provenance markers and a 'Verify first' group | garrytan_gstack context-save/SKILL.md.tmpl:87-104 (Open. prefix; markers path run/read/ass | plugins/flow-extras/skills/handoff/SKILL.md §1 (:13-17) |
| F188 | Small method rules, each with its own home: restate the final agreement; draft the most-unknowns section first; measure each fix by its own attribution line; six-item handoff summary; scratch checks a | anthropics_skills skills/claude-api/shared/evals/build-eval.md:13 (restate after rounds),5 | flow-extras/skills/grill-me/SKILL.md (end); flow/skills/spec/SKILL.md (spec.md d |
| F189 | ultracode spec gate: unit and agent count stated, distinct finding kind per agent, a mechanical check that every standing order reaches every rendered prompt, four-point plan read | anthropics_skills skills/claude-api/shared/managed-agents-multiagent.md:322; performance-t | plugins/flow-extras/skills/ultracode/SKILL.md Phase 1 (:41-46) and Phase 2; new  |
| F190 | find-skills recommends only items fetched this conversation and drops matches it would have to caveat | anthropics_skills skills/academy-guide/SKILL.md:63-65 (a caveat is the match failing),72-7 | plugins/flow-extras/skills/find-skills/SKILL.md Step 4 (:66-72) |
| F191 | Borrow-rubric reviewer safety and fit rules: no git transports or project code on cloned repos; isolated Python; trust only goes down; list the source's layout assumptions against the fit profile | garrytan_gstack deslop-shared-libs/SKILL.md.tmpl:55-58 (no git transports incl. ls-remote; | docs/research/23-pstack-rubric.md 'Rules for the reviewer' (:80-85) and the B5 r |
| F193 | grill-with-docs continues the repo's existing ADR convention | addyosmani_agent-skills skills/documentation-and-adrs/SKILL.md:36-44 (ADD38) | plugins/flow-extras/skills/grill-with-docs/ADR-FORMAT.md:3-5 and grill-with-docs |
| F194 | Credit lines for earlier and new borrows (superpowers, spec-kit) with the sha they were actually taken from | obra_superpowers skills/subagent-driven-development/SKILL.md:19-26 (Ruling relay), scripts | plugins/flow/skills/next/SKILL.md (Building steps 1 and 5) |
| F195 | Design SHIP gate also needs a minimum per-dimension score, reported beside the composite | garrytan_gstack plan-design-review/sections/review-sections.md.tmpl:170-173 (GAR23) | plugins/design/skills/design/SKILL.md:247-252 (Phase 6 step 5) and design/evalua |
| F196 | design:polish fix loop: per-finding pathspec commit, before/after pair, console baseline, risk meter with cap, verified/best-effort/reverted status | garrytan_gstack design-review/SKILL.md.tmpl:206-274 (GAR24) | plugins/design/skills/polish/SKILL.md (new '## Fix loop' section after :47 'Poli |
| F197 | vary: SAFE vs RISK summary of the built direction (drop the swap-the-headline test: already covered) | garrytan_gstack design-consultation/sections/proposal-and-preview.md.tmpl:70-81 (GAR25); d | plugins/design/skills/vary/SKILL.md Step 5 / final report (after :171); design p |
| F198 | Design template-chrome detectors (WARN) plus positive craft rules: one verb per action, refine-don't-add, self-genericity probe at direction stage, CSS specificity note | anthropics_skills skills/frontend-design/SKILL.md:30,43,53,55,59,67 (Apache-2.0), canvas-d | plugins/design/skills/vary/scripts/check.mjs (+ check.test.mjs fixtures) |
| F199 | Explainer and smoothbrain pages: every inline <script> must parse (catches a literal </script> in embedded code or JSON) | anthropics_claude-plugins-official plugins/project-artifact/SKILL.md:172-176, code-moderni | plugins/design/skills/smoothbrain/scripts/check.mjs (before :16) + check.test.mj |
| F201 | smoothbrain: optional Know/Fuzzy/Unknown marking that builds a follow-up request for only the gaps | anthropics_claude-plugins-official plugins/playground/skills/playground/templates/concept- | plugins/design/skills/smoothbrain/SKILL.md §5 |
| F202 | Code facts stay inside what was read: check.mjs --repo flags code identifiers on the page that do not exist in the repo | anthropics_claude-plugins-official plugins/code-modernization/commands/modernize-map.md:29 | plugins/design/skills/smoothbrain/scripts/check.mjs (+ check.test.mjs) |
| F203 | impeccable optimize: identify the framework first; 'not measured' unless tool data, with a source per value; React Compiler caveat; replace the blanket memo/useMemo advice | addyosmani_agent-skills agents/web-performance-auditor.md:41-55 (MIT); vercel-labs_agent-s | plugins/design/skills/impeccable/reference/optimize.md:1-20 and :153-161; design |
| F204 | Refresh and prune the react-performance.csv port: add the missing upstream rules, drop the stale useLatest row, delete the unmeasured JS micro-opts | vercel-labs_agent-skills skills/react-best-practices/rules/*.md (72 rule files, @ 063bee9, | plugins/design/skills/ui-ux-pro-max/data/react-performance.csv; design plugin.js |
| F205 | Wrong-theme flash (pre-hydration theme script) named in design anti-patterns; the react/jsx-no-leaked-render half is dropped | vercel-labs_agent-skills react-best-practices/rules/rendering-hydration-no-flicker.md:53-8 | plugins/design/skills/design/references/anti-patterns.md |
| F206 | React form of NS-32: explicit variant components instead of boolean mode props | vercel-labs_agent-skills composition-patterns/rules/patterns-explicit-variants.md:14-38, a | plugins/flow/skills/no-slop/references/rubric.md:20 (NS-32 row |
| F207 | React view-transitions reference for ui-animation | vercel-labs_agent-skills react-view-transitions/references/implementation.md:18-30,158-166 | new plugins/design/skills/ui-animation/references/react-view-transitions.md + on |
| F208 | Pinned web-interface-guidelines checklist in impeccable audit | vercel-labs_agent-skills web-design-guidelines/SKILL.md:23-29 (VER25: upstream fetches com | plugins/design/skills/impeccable/reference/audit.md |
| F209 | Animation principles: store state truth and derive visuals; pad fixed-size lists to constant slots | vercel-labs_agent-skills react-native-skills/rules/state-ground-truth.md:10-13,33-48, reac | plugins/design/skills/ui-animation/references/decision-framework.md (state rule  |
| F210 | Sandboxed HOME and XDG per CLI verification scenario with before/after capture | Fission-AI_OpenSpec openspec/changes/add-qa-smoke-harness/specs/developer-qa-workflow/spec | plugins/flow-extras/skills/verify-skill/references/skill-template.md:18-19 (## L |
| F211 | Readiness poll for generated verify skills: connection refused and 5xx mean starting, 2xx-4xx mean answering, timeout reports could-not-verify | vercel-labs_agent-skills deploy-to-vercel/resources/deploy.sh:261-293 (VER32) | plugins/flow-extras/skills/verify-skill/references/skill-template.md:19 (Ready w |
| F241 | Fresh run dir and rejecting stale outputs from another sha | vercel-labs_agent-skills skills/vercel-optimize/scripts/prepare-investigation-brief.mjs:21 | plugins/flow/scripts/review-package (+ a case in plugins/flow/scripts/tests/test |
| F247 | skill-judge pre-check: a skill that live-fetches its rules or output format from a mutable URL | vercel-labs_agent-skills skills/web-design-guidelines/SKILL.md:23-29 ('Fetch fresh guideli | plugins/flow-extras/skills/skill-judge/SKILL.md Step 0 (Deterministic Pre-Checks |

## Judged not good (56)

- F08 Secrets via env, never argv: guard Bash commands carrying --token/--password/--secret with a literal value: The benefit claim is wrong for Claude Code, and this fails on benefit, not cost.
- F21 README skill-catalog freshness check: The premise is wrong.
- F49 lesson scope guard: defer the bug-fix or feature half of a request to the right command: Flipped.
- F57 Required declined: [{behaviour, reason}] slot in adversary verdicts, becoming Rulings at the whole-branch review: Flipped: it duplicates and conflicts with other items.
- F67 Idempotency-key predicates in the correctness lens: Fails B7 Fit, which gates everything.
- F101 A fixed bug becomes a behaviour row: Flipped to SKIP on gap and leverage, not cost.
- F109 Interpretation check: list 2-3 readings; if one makes it trivial, the hard reading is probably meant: FLIPPED.
- F115 Read-the-section self-check for load-on-demand spec references: FLIPPED.
- F122 Before ending an unattended turn, read the last paragraph and do any promised work: This duplicates a mechanism flow already has, and that mechanism is stronger than the proposed prose.
- F123 One simple command per Bash call in unattended runs so permission grants match: It conflicts with flow's own required commands.
- F126 Inject router state into the skill with a failure sentinel and an allowed-tools grant: The benefit is one Bash round-trip per turn, which is cosmetic (B2 about 1).
- F127 Written contract for flow next/lint --json, a failure null-shape, and one resolver for the text Next: line and JSON next: Most of this already exists.
- F139 Opt-in fail-closed polarity for boundary hooks: Flipped.
- F140 Hook hygiene tests: timeout budget, unquoted heredocs, valid envelope with jq off PATH: Flipped: all three reasons are refuted or already covered.
- F145 asyncRewake hooks with if: command filters for expensive checks: Flipped to false.
- F146 Edit scope lock during fix §4: Flipped to false.
- F151 Tag each PR change [BLOCKS] or [TUNE]: Flipped to false.
- F152 Loop resume notes at-least-once side effects: Flipped to false.
- F161 Explorer reports end with 5-10 must-read files the orchestrator then reads itself: Flipped: no fit and a duplicate.
- F192 Path-scoped rule file for plugin edits in the flow repo: Flipped on gap (B1), not cost.
- F200 Paste-back prompt of non-default choices plus named presets for showcase mockups: Wrong target, and it duplicates what showcase already has.
- F212 Visual companion server for brainstorming: Coverage confirmed.
- F213 Always-on bootstrap or second router (using-superpowers 1%-invoke, persona/phase commands, session-start router hook): Coverage confirmed.
- F214 Persuasion principles and validate-every-layer defense in depth: Coverage confirmed.
- F215 Team and bot machinery: finish-branch menu, bug-bundle export, gh-aw label-gated CI agents, Greptile triage, land-and-de: B7 fit is 0-1, from the borrow-fit-profile: solo developer, self-merged PRs with zero reviews, no review bots, every base is main (no stacks), and no canaries, flags or package releases.
- F216 Multi-host ports and customisation stacks (Gemini/Codex/Copilot adapters, preset/extension/overlay stacks, 40-agent inte: B7 fit is 0-1.
- F217 Pre-flight interface rows between tasks: Upheld, with sharper citations.
- F218 Per-assertion test deletion gate: Upheld.
- F219 Constitution or CONSTRAINTS.md file with its own command or interview: Upheld.
- F220 Contradicts/unrequested converge gap types with justify-or-remove tasks: Upheld.
- F221 Weak evidence caps the go verdict in scrutinize-idea: Upheld, but the coverage is partial, not identical.
- F222 Skill retirement via a one-line deprecation that keeps working: Upheld on fit.
- F223 Boil the Ocean / Lake Score completeness doctrine: Upheld.
- F224 Cross-model review panels (Codex, OpenAI, Gemini outside voices) and $D image design: Upheld on fit.
- F225 One-question-per-decision reviews, plan-tune preferences and an out-of-repo decisions store: Upheld.
- F226 Reorder task briefs so contract and verify come last: Upheld.
- F227 Measure-and-hold metric ratchet as a standing gate: Upheld.
- F228 Exceptions with an expiry date: Upheld.
- F229 Blind repro-test writer for fix: The verdict holds, but the reason given was the weaker one.
- F230 sdd-cache doc cache hook and simplify-ignore protected blocks: The old reason relied on 'cheap', which is a cost argument and does not count as a SKIP reason.
- F231 Lens-labelled idea variations: Confirmed.
- F232 Hook alternatives: hookify rule files, LLM prompt hooks, log-only first period for new blocking hooks: Confirmed.
- F233 keep-waiting.sh sleep loop to hold the turn during a workflow: Confirmed.
- F234 Plugin scaffolding, MCP bundling in plugins, plugin-settings pattern: Confirmed, fit 1.
- F235 Output styles, receipts reports, eval-viewer local UI, legacy modernization commands, math and maker plugins: Confirmed.
- F236 Route replies by intent; ask again on an unmatched reply: The old reason was partly wrong.
- F237 Verifier blind to the project's steering rules: Confirmed.
- F238 Vendor whole upstream skills (react-best-practices, composition-patterns, react-native-skills, Vercel deploy skills, cla: Confirmed.
- F239 Structured abstain in research-sweep angles and explorer: Duplicate, confirmed.
- F240 Canary run before every fan-out: The old reason ('not justified' to add a round) was a cost argument and does not count.
- F242 Rule examples extracted as eval fixtures; load-check signature in README: Kept as SKIP.
- F243 Generated AGENTS.md monolith and byte-reproducible skill archives: Kept as SKIP on fit (B7 <= 1).
- F244 Lie-detector weighting of evidence over form in spec-judge: Kept as SKIP, with a sharper reason.
- F245 Per-detector budget caps and usage-weighted static findings in audit triage: Kept as SKIP; the reason is corrected.
- F246 Version-guard banner per rule and per-kind abstain lists in adversary lenses: Kept as SKIP, but the old reason leaned on an unverified pointer ('belongs to F160'), which is not on main; it must stand on its own.
- F248 Upstream anti-tricks: pushy descriptions, avoid testing upfront, kill whatever holds the port, any non-Skill first tool : Kept as SKIP.

## Each repo as a whole (layers C and E)

### obra/superpowers

# obra/superpowers @ bb92a77 vs flow (main 6ac0f44): whole-set judgement (Layers C and E)

Mr Claude read the superpowers README (400 lines), docs/testing.md, hooks/hooks.json, scripts/bump-version.sh and the skill index (15 skills, 3,828 SKILL.md lines; `wc -l skills/*/SKILL.md`). Mr Claude also re-opened the flow files behind each claim. The three skeptic-checked slices are applied with their corrections: visual-companion moves to SKIP, "approval covers what was shown" is already enforced, receiving-code-review goes to MERGE at B7=3, Lift-drill stays SKIP on gap, the git-guard `worktree remove --force` hole is real, and the feedback-loops line numbers are fixed. Two gaps were re-checked by hand. `plugins/flow/bin/lib/tick.js` runs only git and never the task's `verify:` (:14-23, :97). `grep worktree plugins/flow/hooks/git-guard.sh` finds nothing.

#### Layer C: ways of working (0-5)

| Row | superpowers | flow | Evidence |
|---|---|---|---|
| C1 Entry and routing | 3 | 5 | SP: a SessionStart bootstrap and the model's own guess ("even a 1% chance ... you ABSOLUTELY MUST invoke", skills/using-superpowers/SKILL.md:11; hooks/hooks.json matcher `startup\|clear\|compact`). flow: a disk router state table (plugins/flow/skills/next/SKILL.md:30-36), two doors (plugins/flow/README.md:9), and 11 `routing-*` eval cases (plugins/flow/evals/). |
| C2 Composition | 3 | 4 | SP: skills point to each other by name, but SDD (568 lines) and writing-skills (681) restate shared rules inline. flow: shared/ (pr-body.md, verification.md) plus one developer-block and review.md referenced from next, fix and build-slices (plugins/flow/skills/next/SKILL.md:56). |
| C3 Verification | 3 | 5 | SP: mostly prose (verification-before-completion). The only runnable check is executing-plans/scripts/task-done:39-51 (records completion only on exit 0). flow: "The agent's report is never the gate — its exit code is" (next/SKILL.md:55), PASS-<sha> tables with integer exits (:76), stop-gate.sh. One SP mechanism is better: tick does not run verify (tick.js). |
| C4 Delegation and context | 4 | 4 | SP: task-brief and report files, a ledger, a scoped re-review (re-review-prompt.md:55-62), and a cannot-verify verdict. flow: brief-path-only dispatch (next/SKILL.md:53), schema'd Workflow agents, a developer agent with no Agent tool. But flow re-runs three full lenses over base..HEAD every fix round (build-slices.js:265-278). |
| C5 Learning loop | 4 | 4 | SP: tests its own prose on agents (baseline vs with-skill, stacked pressure, micro-tests against a no-guidance control; writing-skills/SKILL.md:461-476, :577-587), and diagnosing-superpowers mines sessions. flow: the lesson ladder's deterministic rungs, red-then-green, and `--retro` over jsonl (lesson/SKILL.md:13-22), but no behavioural red step on the Skill rung and no pressure eval cases. |
| C6 Human contact | 4 | 5 | SP: four stop classes, everything else ledgered as `Ruling:` (SDD SKILL.md:19-31), and a typed "discard" (finishing:138-146). flow: a HARD GATE on approval, CHK checkpoints, finish mode, autoApprove in config (next/SKILL.md:34-35). |
| C7 Long runs | 3 | 5 | SP: "a couple hours at a time" in one session (README "How it works"), with ledger resume. flow: `flow loop run` over fresh `claude -p` with iteration, minute, dollar and stall caps, `--worktree` (loop/SKILL.md:95), finish-gate.sh, and a router that recomputes from disk after /clear or a crash. |
| C8 Writing quality | 2 | 4 | SP: the PR follows "the repo's PR template" (finishing-a-development-branch/SKILL.md:123), with no prose rubric. flow: prose-rubric NP-01..13 and `slop-check --prose` before every PR (no-slop/SKILL.md:61-63; shared/pr-body.md:44). |
| C9 Personalisation | 2 | 3 | SP: "User instructions ... take precedence over skills" (using-superpowers/SKILL.md:65), no config. flow: `.claude/flow.config.json` autoApprove, REVIEW.md, stealth. |
| C10 Maintenance | 4 | 4 | SP: bump-version.sh `--check/--audit` drift (scripts/bump-version.sh:1-10), per-harness tests/, lint-shell, a quorum eval lab, release notes that retire commands (RELEASE-NOTES.md:348). flow: version-drift, hooks/tests (19 suites), scripts/tests, skills-lint, workflow-lint, eval ledger. |
| **Total** | **32/50** | **43/50** | |

No row has superpowers ahead of flow by 2 or more. Superpowers does lead inside three rows, and every build item below comes from those three:
- **C3:** recording a task as done only when its test passes.
- **C4:** a scoped re-review, cannot-verify items, and constraints written into every brief.
- **C5:** behavioural testing of the instruction text itself, and safety rules for reading session logs.

#### Layer E: the set as a product

**1. Thesis.** "Process is mandatory, the written artifact is the handoff, and every rule is tested on agents under pressure before it ships." The handoff half is right, and flow already took it (brief, review-package, Base-before-dispatch, rulings; docs/research/11-flow-redesign-2026.md:66-68). The enforcement half is weaker than flow's. Almost every superpowers rule is prose plus a rationalization table, while flow puts the same rules into hooks, lint and exit codes. The testing half is where superpowers is strongest. Its specs pre-register a kill gate, always run a no-guidance control arm, publish null results, and keep a list of ideas that were tried and declined (docs/superpowers/specs/2026-06-10-positive-instruction-redesign-design.md:125-178). Verdict: **partly right. Take the experiment culture, not the enforcement-by-prose.**

**2. Overlap map.**

| superpowers | flow counterpart | Who is ahead |
|---|---|---|
| brainstorming | prep / spec / develop-idea | flow (route plus enforced gate); SP has the builder check |
| using-git-worktrees | loop `--worktree`, native EnterWorktree, doctor-hygiene | even; SP records a test baseline at Base |
| writing-plans | next §Drafting + flow-lint | flow (one-line grammar, lint waves); SP has the Review Focus block |
| executing-plans + task-done | next inline route + flow tick | SP on tick-runs-verify; flow on everything else |
| subagent-driven-development | next §Building + build-slices.js | flow (parallel disjoint waves, lenses, blind re-score); SP on scoped re-review and cap adjudication |
| requesting / receiving code review | next/review.md, adversary.md, review-diff | flow on mechanism; SP on declined-to-judge, spec-silence, and verifying a finding before acting on it |
| TDD, verification-before-completion | execution-prompt.md, NS-28, claim-check, stop-gate | flow |
| systematic-debugging + techniques | fix + fix/feedback-loops.md | flow on mechanism; SP has 4 small instrument and hypothesis tricks |
| writing-skills, testing-skills-with-subagents | skill-forge, skill-improver, skill-judge, lesson Skill rung | **SP** (form-to-failure, micro-test with control, pressure tests) |
| diagnosing-superpowers | lesson `--retro` | SP on jsonl safety, human-turn typing, missed-trigger detection |
| finishing-a-development-branch | Ship state, babysit, git-guard | flow, except the unguarded `worktree remove --force` |
| visual companion server | prep's ungrillable→prototype route, design:showcase | flow already covers it (prep/SKILL.md:98-100) |
| using-superpowers bootstrap | router + session-context.sh | flow |
| only flow | flow loop, finish mode, stop-gate, no-slop, evals harness, version-drift | flow |
| only SP | 15-harness ports, scrubbed bug bundles, commercial telemetry | n/a (wrong fit) |

**3. Should flow fill the gaps?**
- **Yes, in flow:**
  - tick runs verify (bin)
  - scoped re-review and three-way cap adjudication (build-slices.js, review.md)
  - builder-check questions (spec §5)
  - reviewer clauses: cannot-verify, declined-to-judge, spec silence, plan-mandated defect, test noise (review.md, adversary.md)
  - a Constraints block in briefs (task-brief)
  - a Base test baseline (generalising T000)
  - deny `git worktree remove --force` (git-guard.sh)
  - retro safety and missed-trigger detection (lesson)
  - eval fixture rules and a pressure eval case (evals)
- **Yes, in flow-extras:** the form-to-failure / prohibition classification, no-nuance clauses and micro-test-with-control (skill-improver writing-for-agents.md, skill-forge §5, skill-judge D4 after a micro-test).
- **Possibly, in tooling:** micro-test recipe material belongs in agent-evals as a reference.
- **No:** the multi-harness ports, the visual companion server, the 1%-invoke bootstrap (it conflicts with no-nudge-noise), persuasion-principles, defense-in-depth's every-layer rule (it conflicts with NS-22, no-slop/references/rubric.md:28), and the finish-branch menu and contributor docs (the user works solo and self-merges).

**Attribution.** `grep -rn superpowers plugins` finds only no-slop/references/evidence.md:24. Yet next/SKILL.md:52 (never HEAD~1) and the Ruling relay come from superpowers (docs/research/11:66). Credit lines citing `@ bb92a77` are owed; see OBR30.

Highest value first: OBR01, OBR02, OBR04, OBR05, OBR18, OBR19, OBR06, OBR12, OBR23, OBR03.

### github/spec-kit

# github/spec-kit judged against flow (main 6ac0f44), Layers C and E

Spec-kit upstream HEAD: `0443760`. All spec-kit paths are relative to `/home/tomas/.claude/jobs/20064eaf/tmp/repos/github_spec-kit/`. All flow paths are relative to `/home/tomas/Desktop/Projects/flow/.claude/worktrees/famous-borrows/plugins/`. The skeptic corrections from the four slices are applied: converge's contradicts/unrequested types become SKIP (NS-24), assess.decide becomes SKIP (scrutinize-idea:43,54,88-89), existing-projects gets B1 1, the venv rule is already in check-all, and the Terraform-only gate gap is narrowed.

#### Layer C: ways of working (0-5 each)

| Code | spec-kit | flow | Evidence |
|---|---|---|---|
| C1 Entry and routing | 3 | 5 | spec-kit: the user picks commands from a linear chain one at a time ("Invoke each `/speckit-*` skill ... one at a time", README.md:63-66), and the bug and assess processes are separate entry points. flow: one router. `flow next --json` names the single next action, recomputed from disk (flow/skills/next/SKILL.md description), and `/flow:spec` is the only door in. |
| C2 Composition | 2 | 4 | spec-kit: about 35 lines of hook boilerplate are copied into every command (templates/commands/specify.md:21-54 is roughly clarify.md:21-54). Path safety and the URL policy are repeated in each assess command. flow: shared references are written once and pointed to (flow/skills/shared/{pr-body,verification,issue-refs,project-detection}.md, shared/scripts/check-all). |
| C3 Verification culture | 2 | 5 | spec-kit: implement ticks its own boxes ("mark the task off as [X]", templates/commands/implement.md:169). analyze and converge are LLM reads, and only the bash prerequisite scripts and the workflow.yml gates fail loudly. flow: `flow tick` is the only writer of `[x]` and records a sha (flow/skills/next/SKILL.md:57), converge re-runs each criterion's command and records the exit code (:75), and claim-check plus an independent spec-judge also check. |
| C4 Delegation and context | 1 | 5 | spec-kit: implement runs in one agent, and `[P]` only means "continue with successful tasks" (implement.md:165-166). There are no briefs and no fresh contexts. flow: fresh developer subagents for each task, a complete brief, and the build-slices workflow (flow/skills/next/SKILL.md, flow/workflows/). |
| C5 Learning loop | 2 | 4 | spec-kit: the one real loop is CI replay of historical fixes (.github/workflows/bug-test.md:257-280). It has no mistake-to-guardrail path. flow: `/flow:lesson` climbs a ladder to a hook, lint or test (flow/skills/lesson), and there are 40+ eval cases (flow/evals/). |
| C6 Human contact | 3 | 5 | spec-kit: a human runs and reviews each step, and the gh-aw workflows are label-gated by maintainers. flow: fix counts its stops truthfully (flow/skills/fix/SKILL.md:75-79), and `--unattended` resolves decisions but never evidence (flow/skills/next/SKILL.md:122). |
| C7 Long runs | 3 | 4 | spec-kit: the workflow engine's resume replays finished steps instead of re-running them (docs/reference/workflows.md:78-92), and it has checkpoint-before-side-effect ordering (workflows/ARCHITECTURE.md:661-665). flow: `flow loop --worktree` runs overnight, gives status and resumes (flow/skills/loop/SKILL.md:95), and the router recovers from disk after /clear or a crash. |
| C8 Writing quality | 2 | 4 | spec-kit: only the gh-aw pr-assess checks the PR body against the diff (.github/workflows/pr-assess.md:118-141), and it has no prose rubric. flow: the PR body has to pass `slop-check --prose` and the prose rubric (flow/skills/shared/pr-body.md:44). |
| C9 Personalisation | 5 | 2 | spec-kit: presets, extensions and overlays by anchor id, plus 40 agent integrations (docs/reference/workflows.md:166-240, scripts/bash/common.sh:512-942). flow: `.claude/flow.config.json` plus editing at the source (flow/bin/flow:1216 CONFIG_SCHEMA). |
| C10 Maintenance | 4 | 3 | spec-kit: a CI version-bump guard (extensions/EXTENSION-DEVELOPMENT-GUIDE.md:631-637), an every-leaf inventory test (design/mcp.md:241-243), node-ID preservation on test moves (design/cli.md:328-333), and a retirement pattern (templates/commands/taskstoissues.md:10-16). flow: version-drift, skills-lint and test_marketplace.sh, but no retirement pattern. Flow also has no credit line for any spec-kit borrow (a grep for spec-kit or speckit under plugins/ finds nothing). |
| **Total** | **27** | **41** | |

Only one row has spec-kit ahead by 2 or more: C9 Personalisation. It fails B7. The customisation stack exists for downstream teams, and the user is flow's only upstream and edits templates directly (borrow-fit-profile: solo, self-merged). So C9 brings no change. On C10 spec-kit is ahead by 1, and three small items come from that row (GIT04, GIT19, GIT31).

#### Layer E: spec-kit as a product

**1. Thesis.** "Specify what and why before how, then carry that spec through plan, tasks, implement and converge, with templates as the guardrails." This is half right. The front half (separate intent from design, mark unknowns, cap clarifications, keep requirements traceable by id) is right, and flow took it in reports 02, 10, 13 and 14. The back half relies on the model grading itself. implement ticks its own boxes, and even the "mandatory" hooks only ask the model to print EXECUTE_COMMAND and then run it (specify.md:53 admits that "emitting the block alone does not run the hook"). Spec-kit's own converge rule, "completion claims are not evidence" (converge.md:147-148), is the right stance, but nothing enforces it. Verdict: the thesis is right on artifacts and weak on proof, and flow is now ahead wherever proof matters.

**2. Overlap.**

| spec-kit | flow | Status |
|---|---|---|
| constitution | CLAUDE.md, claude-md, REVIEW.md | covered; a separate file would duplicate CLAUDE.md |
| specify, clarify, checklist | /flow:spec, question-bank.md, spec-judge | covered and stronger (an independent judge and a computed route) |
| plan + plan-template | spec/references/design.md:59-67, research-sweep | covered, already borrowed |
| tasks | TASKS.md grammar + flow-lint | covered; **gap:** nothing checks requirement-id coverage (GIT01) |
| analyze | none as a check | **gap:** the id join is still prose (next/SKILL.md:46) |
| implement | /flow:next + build-slices | flow ahead |
| converge | next/SKILL.md:75 + NS-24 slop lens | covered |
| bug assess/fix/test | /flow:fix | covered (14-fix report); flow ahead on reproduce-first |
| assess intake → decide | develop-idea, scrutinize-idea, research-sweep | covered; **small gap:** no disconfirming research angle (GIT09) |
| workflow engine + gates | Workflow tool + router gates | covered; the user's rule keeps human gates out of workflows |
| presets, extensions, bundles, 40 integrations, catalogs, MCP server | none | nothing in flow; it fails fit |
| gh-aw label workflows | none | nothing in flow; it fails fit (no CI on flow, no maintainers) |
| design/*.md engineering docs | agent-architecture tool-design.md, flow-deepen | **small gaps:** MCP annotations and consent (GIT17), test-move node IDs (GIT04) |
| create-new-feature.sh | flow/scripts/new-spec | **gap:** the LC_ALL=C slug drops Icelandic letters (new-spec:46-53, GIT06) |

**3. Should flow fill the gaps?**
- **Customisation layer (presets, overlays, bundles, integrations).** No. The user is upstream and works solo, so it fails B7, and adding it would be a speculative feature.
- **The id-coverage check from analyze.** Yes, in flow (flow-lint). This is the largest real gap. The template already issues FR-01 ids (flow/flow-templates/spec.md:73-75) and the Drafting rule asks for coverage by id, but flow-lint's only Behaviors rule is "no ## Behaviors section" (flow/scripts/flow-lint:599).
- **Honesty rules from the gh-aw and assess prompts.** Yes, each as a small MERGE in flow: exit code before pipes, partial coverage means inconclusive, PR body against diff, evidence-against, and an unattended fix stopping when two causes are tied.
- **Engineering-doc rules.** Yes, split two ways. MCP annotations and consent go in tooling (agent-architecture), because the user builds MCP and Strands agents. Test-move node IDs and splitting by phase rather than line count go in flow (flow-deepen, size-guard).
- **Per-repo declared gates.** Yes, in flow (check-all + CONFIG_SCHEMA). check-all detects only node, python, rust and go (check-all:622-626). The user's terraform repo was confirmed to get no gates; per-spec G### rows are the only workaround today.
- **Historical-fix replay eval.** Yes, in flow/evals. It measures /flow:fix against the user's real bugs instead of toy cases.

Net: no ADOPT. There are about 25 small MERGEs and tricks, listed below. Six of them carry steal 3: GIT01, GIT02, GIT03, GIT04, GIT05 and GIT32 (credit lines, rubric maintenance rule).

### garrytan/gstack

# garrytan/gstack vs flow: whole-set verdict (Layers C and E)

Upstream reviewed: garrytan/gstack @ 5b9b837 (2026-10-10). Mr Claude read README.md (784 lines), ETHOS.md (196), ARCHITECTURE.md (template-system section), CLAUDE.md (sections on testing, eval blame, decision memory and routing), and the skeptic-corrected slice scorings for plan-front-end, review-ship-qa, safety-ops-retro and design-docs-meta. All corrections are applied: devex B1 is 3, the test-coverage audit is SKIP, "Never auto-close partial work" has steal 0, "Missing coverage is never clean" has steal 0-1, codex B5 is 3, qa-only B7 is 3, canary is a rubric gap, and the fix:150 scope quote is used.

#### Layer C: ways of working (0-5 each)

| Row | gstack | flow | Evidence |
|---|---|---|---|
| C1 Entry and routing | 3 | 4 | gstack has 38 slash commands in a fixed sprint order (README.md:275-283), plus proactive skill suggestions you can turn off (SKILL.md.tmpl:49,109). flow computes one route (spec/SKILL.md:26-30), and `flow next --json` decides each turn from disk (next/SKILL.md:12). |
| C2 Composition | 5 | 4 | gstack builds every SKILL.md from .tmpl files through resolvers: {{PREAMBLE}}, {{QA_*}}, {{TEST_VALUE_BAR}}, {{SHARED_LIBS_RUBRIC}} (ARCHITECTURE.md:314-397). Carved sections carry a self-check that the agent read the section before acting on it (spec/SKILL.md.tmpl:491-498). flow points to shared references by name (plugins/flow/skills/shared/*, no-slop references), but nothing renders them and nothing checks they were read. |
| C3 Verification culture | 4 | 4 | gstack records an evidence ledger with tests_ran (ship/sections/tests.md.tmpl:24-53), a gate-integrity catalog (review/gate-integrity.md:77-126), and checks the JSON a child returns on its last line (plan-completion.md.tmpl:34-39). Its outside voice is Codex. flow has PASS-<sha> with integer exits (next/SKILL.md:75-76), claim-check (bin/lib/lint.js:34-43), blind re-scoring (review-diff.js:59-148), and a router `lying` state (router.js:554-558). gstack is ahead on zero-run detection and on catching edits to acceptance criteria. |
| C4 Delegation and context | 3 | 4 | gstack's review army and child sections use strict last-line JSON, but every invocation reruns the reviews (ship has 21 steps). flow uses task-brief, fresh developer subagents and pinned lens sets (review.md:23; build-slices.js). |
| C5 Learning loop | 2 | 5 | gstack stores learnings as prose in JSONL (/learn, decisions.jsonl at CLAUDE.md:555-578). flow's lesson ladder turns a mistake into a hook, test or lint rule (lesson/SKILL.md:69-97). |
| C6 Human contact | 2 | 4 | gstack asks one AskUserQuestion per decision, and plan-devex alone has 20-45 forcing questions (README.md:291). flow runs one batched turn (spec/SKILL.md:56) and records Assumptions under --unattended (next/SKILL.md:122). gstack's one useful idea here is the Mechanical/Taste/Challenge split (autoplan/SKILL.md.tmpl:78-95). |
| C7 Long runs | 3 | 4 | gstack runs 10-15 parallel sprints through Conductor (README.md:505-511), plus autoplan and context-save/restore. flow has finish/loop and a router that recomputes from disk, so a crash or /clear self-heals (next/SKILL.md:12,105). |
| C8 Writing quality | 3 | 4 | gstack has a writing-style section (CLAUDE.md:191) and good/bad pairs in office-hours. flow runs no-slop's prose rubric and slop-check on the PR body (shared/pr-body.md:44). |
| C9 Personalisation | 4 | 3 | gstack has multi-host install, per-model overlays, gstack-config and plan-tune (README.md:106-200). flow has .claude/flow.config.json (spec/SKILL.md:42,66). The user's fit for this row is low: they use Claude only and prefers variety over taste memory. |
| C10 Maintenance | 5 | 4 | gstack has 1019 test files, paid evals selected by diff and checked against tiers (CLAUDE.md:36-46), and a blame protocol that needs proof on base before calling a failure pre-existing (CLAUDE.md:430-443). flow has scripts/tests (about 40 suites), doctor drift checks (doctor-hygiene.js:330-361), version-drift and skills-lint. |
| **Total** | **34** | **40** | No row has gstack 2 or more points ahead. C2, C9 and C10 are each +1 for gstack. C2's self-check and C10's blame protocol are logged as items. |

#### Layer E: the whole set as a product

**1. Thesis.** "One person ships like a team of twenty by role-playing the team" (README.md:3-27). Each role is a slash command run in sprint order, and per ETHOS.md:35-61 completeness is always worth the cost ("Boil the Ocean"). Verdict: **half right.** The working part is the honesty machinery added since the pstack round. A missing check is never a pass, a child's green is a claim to recheck, test counts must be positive, and relaxed gates are disclosed to the human. flow already shares that culture and can take the specific mechanisms. The wrong part for this user is the team simulation. CEO, eng-manager, designer and devex reviews each amend the plan through dozens of questions. A Codex/OpenAI outside voice is required for "full" reviews. The YC funnel and Boil the Ocean contradict their CLAUDE.md rule "Minimum code that solves the problem."

**2. Overlap map.**
- office-hours, plan-ceo/eng/design/devex-review and autoplan map to flow:prep, flow:spec plus design.md, plan-review.js and spec-judge. flow is leaner. gstack has small rule pieces flow lacks.
- review, the specialists and review-army map to next/review.md plus review-diff.js plus agents/adversary.md. flow is close to parity. gstack's gate-integrity and enum/rename tracing are new.
- ship maps to next Gates/Ship/Finish plus pr-body.md. gstack adds tests_ran, ACCEPTANCE_EDITED and a Gate edits line.
- qa and qa-only map to flow:qa. gstack is ahead on functional (non-browser) contracts and report wording. flow:qa has a real defect: `git stash` at qa/SKILL.md:16,329.
- investigate maps to flow:fix, where flow is stronger. careful, freeze and guard map to hooks/git-guard.sh, which misses plus-refspec force and has no ask tier. Nothing in flow is a scope lock.
- cso maps to tooling:pentest. gstack's evidence rules are new.
- health, benchmark and test-audit map to Gates, benchmark-checklist and audit, and gstack has small rules to add.
- design-consultation, design-shotgun and design-html map to design, vary, showcase and impeccable. Only the tricks are worth taking. design-review maps to design:polish, and its fix-loop discipline is new.
- document-release maps to doctor referenceDocsDrift, which covers flow's own docs only. There is no docs lens for user repos.
- context-save and context-restore map to flow-extras:handoff plus PROGRESS.md. Provenance markers are new.
- learn, retro and plan-tune map to lesson, where flow is stronger.
- Nothing in flow matches: canary, land-and-deploy, landing-report, Greptile triage, browse/scrape/pair-agent, make-pdf and the codex panel.

**3. Should flow fill the gaps?**
- **Yes, in flow** (mechanisms, all small): tests_ran/ZERO-RUN, an ACCEPTANCE_EDITED lint rule, wider tamper patterns plus a Gate edits line, git-guard plus-refspec and an ask tier, exit code read before display, the qa stash fix, a functional-contracts reference, the LOOK/ACT rule, adversary lens additions, an advisory docs lens, taste/challenge Assumption tags, and the plan-review adjudicator rules.
- **Yes, in flow-extras or tooling:** handoff provenance, the audit retirement card, benchmark and agent-evals rules, pentest evidence rules.
- **Yes, in design:** fix-loop discipline for polish, lowest-pass scoring, the swap-headline test and SAFE/RISK for vary.
- **No:** post-deploy canary and land-and-deploy (the user self-merges, and B7 is 2 at most; only the verdict-ladder sentence is worth having), the review-bot and team pieces, the codex panel, the browser runtime, and the decision store kept outside the repo.

Net verdict: **SKIP gstack as a set and as skills. MERGE about 40 small rules and mechanisms** into the existing flow, flow-extras, tooling and design files listed below. The single defect to fix first is flow:qa's bare `git stash`.

### addyosmani/agent-skills

# addyosmani/agent-skills @ 1be8e34, judged as a whole against flow (main 6ac0f44)

Mr Claude read the upstream README.md (408 lines), AGENTS.md, CLAUDE.md, docs/comparison.md, the start of docs/advanced-per-agent-configuration.md, evals/skill-impact.md, .claude/commands/build.md and .github/workflows/test-plugin-install.yml. The three skeptic-checked slice reports were applied with their corrections:
- source-driven gap goes from 4 to 3, still ADAPT;
- run-evals goes from ADAPT to MERGE;
- the context-engineering SKIP is rescored to B2=1;
- "rotate before purge" and "Rule of 500" are dropped as already covered;
- the two migration rollback tricks are merged;
- /constraints is narrowed to a scanner step that points at commands flow already has.

Flow does not credit addyosmani anywhere yet (`grep -rn addyosmani plugins` returns nothing), so the rubric has no upstream-drift items to raise.

#### Layer C: ways of working (0-5)

| Row | agent-skills | flow | Evidence |
|---|---|---|---|
| C1 Entry and routing | 3 | 5 | Upstream has nine phase commands plus a prose meta-router: "Determine if any skill applies (even 1% chance)" (AGENTS.md:51), with the phase table at README.md:24-36. Flow uses a router computed from disk: "Read `flow next --json` FIRST, every turn… the router recomputes from disk" (plugins/flow/skills/next/SKILL.md:12). |
| C2 Composition | 4 | 4 | Upstream writes shared rules once in references/ and says "Do not restate that guidance here, link to it" (AGENTS.md:92, CLAUDE.md:60). Flow does the same with plugins/flow/skills/shared/ (pr-body.md, verification.md, e2e-testing.md) and the no-slop references. Level. |
| C3 Verification culture | 2 | 5 | Upstream's "Verification is non-negotiable" (README.md:345) is a checklist the author ticks. Its only executed guard is floor-guard. Flow has PASS-<sha>.md, exit-code gates, the adversary's blinding rules (plugins/flow/agents/adversary.md:25) and the gaming lens (:35). |
| C4 Delegation and context | 2 | 5 | Upstream: "the user (or a slash command) is the orchestrator. Personas do not invoke other personas" (AGENTS.md:78). Its only fan-out is /ship (:80). Flow has generated briefs (plugins/flow/scripts/task-brief), review-package, and saved workflows (build-slices, review-diff). |
| C5 Learning loop | 2 | 5 | Upstream keeps an append-only ledger of rejected skill changes (evals/skill-impact.md:1-3) and does not mine sessions. Flow's /lesson walks a ladder from unrepresentable state down to a CLAUDE.md line, and `--retro` mines sessions (plugins/flow/skills/lesson/SKILL.md:3,15). |
| C6 Human contact | 3 | 4 | Upstream checkpoints every phase (docs/comparison.md:94) and does not count a hedged reply as approval (.claude/commands/build.md:34). Flow routes by irreversibles and asks only what it cannot answer itself (plugins/flow/skills/spec/SKILL.md:3,8). Its unapproved gate opens on "the user's 'approved'" with no rule for hedged replies (next/SKILL.md:34). That is the one narrow spot where upstream is ahead. |
| C7 Long runs | 1 | 5 | Upstream's `/build auto` is one approval followed by a single session, with no resume (build.md:10-12,27-34). Flow has fresh-session loops with caps and `--worktree`, resumable through `flow loop status` (plugins/flow/skills/loop/SKILL.md:95), and a router that self-heals (next/SKILL.md:12). |
| C8 Writing quality | 2 | 4 | Upstream covers ADR and docs content only (documentation-and-adrs) and has no rule for replies or PR prose. Flow has the no-slop prose rubric NP-01..NP-03 (plugins/flow/skills/no-slop/references/prose-rubric.md:22-24) and plugins/flow/skills/shared/pr-body.md. |
| C9 Personalisation | 3 | 3 | Upstream gives per-host adapter files and keeps vendor fields under `metadata` (docs/advanced-per-agent-configuration.md:1-20). Flow uses `.claude/flow.config.json` toggles (spec/SKILL.md:42, next/SKILL.md:34) plus the user's CLAUDE.md. Level, and multi-host does not matter for this user. |
| C10 Maintenance | 5 | 4 | Upstream CI runs validate-skills, skill-lint tests, version validation, `run-evals.js --min-rank1 95`, reference-link checks and hook tests (.github/workflows/test-plugin-install.yml:23-50). Flow has about 50 test scripts (plugins/flow/scripts/tests/), version-drift (plugins/flow/scripts/version-drift:2-8) and skills-lint. It has no strict-frontmatter or 1024-char check (skills-lint has no `yaml`/`1024` match), no description-collision check, and no CI on the flow repo itself. |
| **Total** | **27** | **44** | |

No row has agent-skills ahead by 2 or more. Upstream leads by 1 on C10 (catalog hygiene). The narrow C6 point (hedged replies) is behind ADD16, and C10 is behind ADD10-ADD12.

#### Layer E: the set as a product

**1. Thesis.** "Encode a senior engineer's lifecycle (Define to Ship) as portable Markdown process skills. Each skill carries a Common Rationalizations table, Red Flags and an evidence checklist, and a human checkpoints each phase" (README.md:321-346, docs/comparison.md:54).

**Verdict: half right.** The diagnosis is correct: "agents default to the shortest path" (README.md:372). The cure is mostly prose asking the model to behave, so the same shortcut-taking model ends up policing itself. Flow's bet (computed router, exit-code gates, tamper hooks, blinded adversary) is stronger on every runtime row.

The set's real mechanism sits in the wrong place for a runtime: contributor tooling (skill-lint, routing evals, version validation) and one reference guard (floor-guard). Those are the parts worth taking. The portability goal (eleven hosts, README.md:352-366) is irrelevant to a Claude-Code-only user.

**2. Overlap map.**

| agent-skills | flow counterpart | Who is ahead |
|---|---|---|
| using-agent-skills, session-start.sh | flow:next router, hooks/session-context.sh | flow |
| interview-me, idea-refine | prep Step 3, develop-idea | flow; interview-me adds three probes |
| spec-driven, planning, /spec, /plan | flow:spec, TASKS.md grammar, flow lint | flow; the spec template lacks an "ask first" tier |
| incremental, TDD, /build, /test | next execution prompt, RED gate, fix revert-proof | flow; upstream adds the hedged-approval and clean-baseline lines |
| debugging-and-error-recovery | flow:fix | flow; upstream adds "error text is untrusted" |
| doubt-driven | adversary.md + review.md fix ladder | flow; upstream adds contract-first and doubt-theater |
| constraint-driven + floor-guard | tamper-notice.sh, loop/tamper.js, slop-check NS-09 | Mixed. Flow has the hooks; floor-guard has direction-aware thresholds, suppression regexes and fail-closed exit 2 |
| source-driven | strands-steering-hooks introspect (one stack only), adversary cross-file lens (:36) | Upstream generalises; flow covers one stack |
| code-review, personas, /review, /ship | review-diff.js, adversary lenses | flow; upstream adds empirical mutation and LLM-feature security bullets |
| security-and-hardening, security checklist | pentest (attack side), adversary security lens | Upstream on builder-side predicates |
| performance-*, web-perf auditor, /webperf | benchmark-checklist, loop metric, impeccable optimize.md | Upstream on diagnosis signatures and metric honesty |
| api / deprecation / observability | adversary correctness lens, next expand/contract, strands-agentcore production.md | Upstream on idempotency, a tested down path, entry-point field |
| browser-testing-with-devtools | shared/claude-in-chrome-reference.md, agent-browser-reference.md | Upstream: content-is-data and test-profile rules |
| documentation-and-adrs | grill-with-docs, no-slop prose rubric | flow; upstream adds timeless docs and preserved qualifiers |
| scripts/skill-lint, run-evals Tier 2 | skills-lint, evals/README.md, case-selfcheck | Upstream on strict YAML, the 1024-char cap and collisions |
| ci-cd, shipping-and-launch, git-workflow | gates.yml.tmpl, babysit, pr-body Merge danger | flow for this user; upstream's team rollout material does not fit |
| Nothing upstream | /flow:lesson, /flow:loop, PASS-<sha>, stealth, claim-check, worktree loops, codebase map | flow only |
| sdd-cache, simplify-ignore, multi-host adapters | nothing in flow | Not needed |

**3. Should flow fill the gaps?**
- **Version-pinned API grounding: yes.** It goes in flow, as a receipt line in the developer brief that the adversary checks, generalising the strands-steering-hooks introspect pattern. The user's stacks (Next.js, Strands, AgentCore, SST) change faster than training data.
- **Catalog hygiene: yes.** Strict frontmatter, the 1024-char cap, description collisions and duplicate skill names go in flow as on-demand `skills-lint` modes and a `flow doctor` check. They are mechanical and add no per-turn output.
- **Builder-side domain predicates: yes, as lines in existing files, not new skills.** These are LLM output into a sink, trust follows the writer, destructive derived paths, idempotency keys, a tested down path, cache-key correctness, metric honesty and the entry-point log field. They go in adversary.md lenses (flow), benchmark-checklist (flow-extras), pentest (tooling), impeccable (design) and strands-agentcore (aws).
- **Tamper detectors: yes.** Flow gets the suppression patterns, direction-aware thresholds and fail-closed exit 2 from floor-guard.
- **CONSTRAINTS.md, personas, phase commands, rollout/canary/flag process, sdd-cache, simplify-ignore, multi-host adapters: no.** Each is either already covered or does not fit a solo, self-merging, Claude-Code-only user.

Credit lines read `addyosmani/agent-skills <path> @ 1be8e34 (MIT)`.

### anthropics/claude-plugins-official

# anthropics/claude-plugins-official vs flow: whole-set judgement (Layers C and E)

Upstream: `/home/tomas/.claude/jobs/20064eaf/tmp/repos/anthropics_claude-plugins-official` @ **a9fd216**. Every new credit line should cite this SHA. No flow file credits this repo yet, so no upstream diffs need checking. Flow paths below are relative to `plugins/` in the famous-borrows worktree (main 6ac0f44). The four skeptic-checked slices are folded in with their corrections applied:

- uplift-deltas.js is ADAPT, not ADOPT.
- build-mcp-server is ADAPT with gap 3.
- build-mcp-app fit is 3 (LibreTest/mcp-apps-server depends on ext-apps ^1.7.4).
- playground gap is 2, because impeccable live mode covers code surfaces.
- trace_rules gap is 2, because the converge pass at next/SKILL.md:75 covers most of it.
- The canary is already reasoned about in review.md:25 and adversary.md:20. Only the *executed* canary is new.
- quick_validate portability is 4, and 7 descriptions are over 1024, not 5.
- `!` injection needs `allowed-tools: Bash(...)`, or the skill refuses to run.
- explanatory-output-style is SKIP on leverage, not on fit.

#### What the repo is

The README describes a curated marketplace, not a method (README.md:1-11): "Internal plugins developed and maintained by Anthropic" plus 14 `external_plugins`. It holds 40 internal plugins, and 12 of them are LSP wrappers. The README's only rules are structural: name slugs cannot change and `renames` handles migration (README.md:46-58), and there are skill-bundle entries with `strict:false` (README.md:60-90). Quality varies a lot between plugins. code-modernization, claude-security, security-guidance and skill-creator are engineered, with scripts, workflows and test suites (`plugins/security-guidance/tests/`, `plugins/code-modernization/tests/*.test.ts`). plugin-dev, hookify, feature-dev, pr-review-toolkit and commit-commands are mostly prose and have drifted.

#### Layer C: ways of working (0-5)

| Row | Repo | flow | Evidence (repo / flow) | Repo ahead by 2+? |
|---|---|---|---|---|
| C1 Entry and routing | 2 | 4 | **Repo:** about 40 plugins of flat slash commands, plus agent descriptions packed with "use proactively" examples (pr-review-toolkit/agents/code-simplifier.md:3-38). Nothing routes, and nothing holds state. **flow:** "Read `flow next --json` FIRST, every turn" (flow/skills/next/SKILL.md:12). | no |
| C2 Composition | 1 | 3 | **Repo:** the 0-100 confidence rubric is copied three times with different wording (feature-dev/agents/code-reviewer.md:33-39, pr-review-toolkit/agents/code-reviewer.md:35-41, code-review/commands/code-review.md:20-26). code-simplifier ships word for word in two plugins. silent-failure-hunter still names another repo's Sentry helpers (:123-128). **flow:** shared/ references and adversary lenses referenced by name. | no |
| C3 Verification culture | 3 | 4 | **Repo:** strong only in the best plugins. proof_pack.py parses runner output (proof_pack.py:15-18). claude-security keeps a finding only after a three-lens panel tallied in code (scan.js:143-144, README.md:58-62). Most plugins are prose plus self-scored confidence. **flow:** the developer's report is never the gate, and the verify is re-run (next/SKILL.md:55); the converge pass runs every AC (next:75). But PASS records exit codes only (next:76), and one blind scorer decides each finding (review-diff.js:117-130). | no (the best plugins are ahead by about 1) |
| C4 Delegation and context | 4 | 4 | **Repo:** packets with a script-checked output (modernize-map.md:290-305), and script-mined transcripts that the model never reads raw (receipts SKILL.md:41-48). **flow:** the developer gets only the brief path (next:53), and workflows return schema-typed results. lesson --retro still sends one subagent through each raw jsonl (lesson/SKILL.md:19-22). | no |
| C5 Learning loop | 2 | 4 | **Repo:** hookify turns corrections into rule files, but its warn path goes to systemMessage, which the model never sees (rule_engine.py:88-91). revise-claude-md produces prose only. skill-creator measures skills, which is a real strength. **flow:** the lesson ladder, red then green, with an adversary (lesson/SKILL.md:69-99). | no |
| C6 Human contact | 3 | 4 | **Repo:** explicit phase gates such as "DO NOT START WITHOUT USER APPROVAL" (feature-dev.md:89), but none of them is tied to risk. claude-security asks through pop-ups. **flow:** one batched pre-answered discovery turn (spec), and `--finish` pre-approval (next/SKILL.md:103,112). | no |
| C7 Long runs | 3 | 4 | **Repo:** ralph-loop's single `<promise>`. code-modernization has deterministic spawn order for journal replay (extract-rules.js:43-58), gap lists that can be passed straight back in (uplift-migrate.js:415-419), and per-batch breakers (:337-358). **flow:** loop caps plus a negative control (loop/SKILL.md:22), and the router recomputes from disk. build-slices pulls tasks in completion order (build-slices.js:316-337). | no |
| C8 Writing quality | 2 | 4 | **Repo:** nothing controls the prose it produces beyond skill-creator's description advice (improve_description.py:127-132). **flow:** no-slop prose rubric checked by `slop-check --prose`. | no |
| C9 Personalisation | 3 | 2 | **Repo:** per-project `.claude/<plugin>.local.md` settings (plugin-dev plugin-settings), and hookify rule files a user writes without code. **flow:** thresholds and autoApprove only. | no (+1) |
| C10 Maintenance | 3 | 4 | **Repo:** CI runs validate-frontmatter, validate-plugins and a Claude policy scan with a verdict cache (.github/workflows/scan-plugins.yml:1-21). But validate-frontmatter.ts only checks that name and description exist (:110-152), with no length check. plugin-dev's own validators fail its own agents. READMEs drift from commands (the code-review README says 4 agents, the command runs 5). **flow:** hook and script suites, `claude plugin validate` (test_marketplace.sh:182), skills-lint, version-drift. But flow has 7 descriptions over 1024 characters and 2 dangling `frontend-design:frontend-design` calls (flow-extras/skills/brainstorm/SKILL.md:28, design/skills/explainer/SKILL.md:16), and nothing catches either. | no |

**Totals:** repo 26, flow 37. The repo beats flow by 2 or more on no row. Its best plugins (code-modernization, claude-security, security-guidance, skill-creator) would score 5 on C3 and 4 on C7. The borrowable value is in those plugins, not in how the set works as a whole.

#### Layer E: the set as a product

**1. Thesis.** As a whole, the set has none. It is a directory, and the README sets only packaging rules. The four engineered plugins share one belief: *a verdict is computed in code from evidence that a different pass failed to refute, never taken from the author's opinion*.
- "Modernization fails quietly, so the proof is built from evidence a script can check" (code-modernization README.md:53).
- "A finding reaches the report only after independent verifiers fail to disprove it" (claude-security README.md:58-62).
- Measure trigger rate on a held-out set, not on vibes (skill-creator run_loop.py:24-44).

**Verdict: right.** It is flow's own thesis taken one step further. flow re-runs verifies but still records exit codes, and still lets one scorer decide each finding. The prose half of the set argues the opposite: hook-development and migration.md push LLM prompt hooks over deterministic ones. flow correctly rejects that (lesson/SKILL.md:9).

**2. Overlap map.**

| Repo piece | flow piece | Who is ahead |
|---|---|---|
| modernize-verify / proof_pack / trace_rules | next gating, converge pass, PASS-<sha> (next:55,75,76) | repo on parsing evidence (executed counts, executed canary). flow on everything else |
| claude-security scan, scan-verifier, patch-verifier; security-guidance review_api | review-diff security lens (review-diff.js:59, adversary.md security lens), audit, pentest | repo: refutation panel, PREDATES_CHANGE, attacker equals victim, diff-anchor tagging |
| security-guidance pattern hook | nothing at edit time | repo |
| uplift / version-delta-analyst / uplift-deltas.js | version-audit (flags a major and stops) | repo, as an ADAPT |
| uplift-migrate.js / extract-rules.js | build-slices.js | repo on resume and carrying gaps between waves |
| skill-creator trigger evals, grader, analyzer | skill-improver, skill-forge, skill-judge, flow eval (routing cases at runs:1) | repo on measuring triggers. flow on authoring |
| plugin-dev (validators, skills) | skills-lint, test_marketplace.sh, skill-judge Step 0(b) (model-run, :384-390) | flow, except for a scripted frontmatter check |
| mcp-server-dev | agent-architecture (tool shaping), aws:strands-agentcore (transport and deploy, SKILL.md:28-42,131-156) | repo on auth, Origin, elicitation, annotations, apps |
| pr-review-toolkit, code-review, feature-dev | adversary plus review-diff, spec plus next, explorer | flow, except the silent-failure (errors) lens and some correctness-lens lines |
| hookify, claude-md-management | lesson ladder, flow-extras claude-md | flow, except the CLAUDE.md path-currency check |
| ralph-loop, commit-commands | flow:loop, next PR step | flow |
| receipts, session-report, project-artifact | digest, PROGRESS.md | repo on mining transcripts with a script and on honest reporting. Team reports do not fit |
| playground | design:showcase, impeccable live (live.md:118-153) | even, except paste-back prompts for non-code pages |
| Repo has nothing | lesson ladder, router, no-slop prose, loop caps | flow |
| flow has nothing (no fit) | legacy estate modernization, SME rule review, math proof, hardware makers, output styles, tunnels | repo, with no fit |

**3. Should flow fill the gaps?**

Yes, for these:
- **Edit-time security sink hook.** Home: flow hooks. It prints nothing unless a match fires.
- **Refutation panel and PREDATES_CHANGE in review-diff.** Home: flow. The user's self-merged PRs get no other review.
- **Executed-count and executed-canary gating.** Home: flow next and check-all.
- **Trigger-rate evals for skill descriptions.** Home: flow-extras skill-improver, on top of flow eval.
- **Frontmatter lint.** Home: flow skills-lint. CI-grade, and 7 descriptions are already over the limit.
- **MCP server-side guidance.** Home: tooling, as a new mcp-server skill linked to strands-agentcore. The user has MCP servers in opengym, diagrammer, Agentcore-test, ads-seo and LibreTest.
- **Major-bump mode.** Home: tooling version-audit.
- **Script-first transcript mining for lesson --retro.** Home: flow bin.
- **Session spend analyzer.** Home: tooling agent-architecture.

No, for these:
- Team and PR-comment machinery: code-review posting and the prior-PR-comments lens (fit 0-1).
- Plugin scaffolding (rare in a stable marketplace).
- hookify (lesson already writes tested hooks).
- Output styles (per-turn noise, low leverage).
- receipts (made for showing a manager).
- Legacy modernization and the math plugins (fit 0-1).

#### Side findings on flow (not borrows)

- The 2 calls to `frontend-design:frontend-design` point at a skill no flow plugin ships, and test_plugin_refs.sh does not catch them.
- 7 SKILL.md descriptions are over 1024 characters: design, vary, flow-deepen, google-ads, hubspot-prospect, strands-steering-hooks and prompt-injection-tester. 7 frontmatters fail strict YAML because they contain unquoted colons.
- review-diff anchors 0/25/50/75/100 with keep at 80 or above (review-diff.js:60,115-130). So every "75 = verified real, low impact" finding is silently dismissed. Confirm this is intended.


### Fission-AI/OpenSpec

# Fission-AI/OpenSpec vs flow: whole-set verdict (Layers C and E)

Upstream: `/home/tomas/.claude/jobs/20064eaf/tmp/repos/Fission-AI_OpenSpec` @ `9111a76`. Flow: worktree `famous-borrows` (main 6ac0f44). No flow file credits OpenSpec yet (`grep -rni openspec plugins` finds nothing), so there is no upstream diff to run. Each borrow's credit line should record `OpenSpec @ 9111a76`.

The skeptic corrections are applied:
- **sync-specs** stays a MERGE. It is the deliberately cheaper half of report 19's item #5 (`docs/research/19-flow-standards-review-2026-09-24.md:103,153`).
- **specs-sync-skill** and **parallel-merge-plan** are folded into the living-spec ADAPT.
- **Verifier blind to steering rules** is now a SKIP. `review.md:12` enforces REVIEW.md and CLAUDE.md on purpose.
- **"One behaviour per requirement"** is already covered by `flow-templates/spec.md:69` and `spec-judge/SKILL.md:237`.
- **"Never score skipped as passing"** is already covered by `next/SKILL.md:55,75`.
- **"Two passes then stop"** is already covered by `next/review.md:60,62`.
- **Anti-narrowing** must be reconciled with `agents/developer.md:13`.
- **Bare --amend** should trigger `workflows/plan-review.js:58` with a consistency lens, not a new hand-written sweep.
- **The JSON contract** lands in `docs/reference/`.
- **The flow-lint OK-line citation** moves to `flow-lint:958-960`.

#### Layer C: ways of working (0-5)

| Row | OpenSpec | flow | Evidence |
|---|---|---|---|
| C1 Entry and routing | 4 | 5 | OpenSpec has a two-command core plus a situation-indexed docs home (`docs/README.md:16-36`). In flow, one router names one verb per turn (`plugins/flow/skills/next/SKILL.md:9,12`). |
| C2 Composition | 4 | 4 | OpenSpec generates its skill text from one source and parity-tests it (`skills/README.md:17-19`), but its docs restate update-vs-new in three places (`workflows.md:418`, `opsx.md:231`, `editing-changes.md:71`). Flow has `skills/shared/` references, but it copies the vertical-slice paragraph into `spec/SKILL.md:66` and `next/SKILL.md:46` with no drift check (`skills-lint` has no parity rule). |
| C3 Verification | 2 | 5 | OpenSpec's verify is model self-report and "Does not block archive" (`docs/commands.md:406`, `docs/workflows.md:374`). Flow re-runs each `verify:` and gates on its exit code (`next/SKILL.md:55`), records the integer exit codes in acceptance.md (`:75`), writes PASS-<sha> (`:76`) and runs claim-check (`:109`). |
| C4 Delegation | 1 | 5 | OpenSpec's method has no subagents. Flow sends one fresh developer per task, handed only the brief path (`next/SKILL.md:52-53`). |
| C5 Learning loop | 1 | 4 | OpenSpec turns problems into prose TODOs and product-feedback logs. Flow has the `/flow:lesson` ladder. |
| C6 Human contact | 3 | 5 | OpenSpec says "no approval gate" (`docs/editing-changes.md:3`), though propose stops for review. Flow has a counted gate manifest and a hard `unapproved` gate (`spec/SKILL.md:86`, `next/SKILL.md:34`). |
| C7 Long runs | 2 | 5 | OpenSpec resumes from the first unchecked task (`docs/faq.md:93`). Flow has `--finish`, a disk-derived router and a finish-gate hook (`next/SKILL.md:105-112`). |
| C8 Writing quality | 4 | 4 | OpenSpec has strong spec prose and page architecture (`docs/writing-specs.md`, `docs-lab/README.md:43-53,212-219`). Flow has the no-slop prose rubric (`no-slop/references/prose-rubric.md`), which works at sentence level and has no retrievability or page-ownership rows. |
| C9 Personalisation | 5 | 3 | OpenSpec has config context and rules plus forkable schemas (`docs/customization.md`). This is the one row where OpenSpec leads by 2, but it is team-shaped and fails B7: the user edits flow directly. |
| C10 Maintenance | 4 | 4 | OpenSpec dogfoods 36 capability specs under `openspec/specs/`, has docs-claims tests (`test/skills-docs-claims.test.ts`, `test/vocabulary-sweep.test.ts`) and audits its agent contract with a known-inconsistencies list (`docs/agent-contract.md:3,139`). Flow has `scripts/tests/run.sh`, `skills-lint`, `workflow-lint` and `version-drift`. |

OpenSpec totals 30/50 and flow 44/50. No row where OpenSpec leads by 2 or more also fits the user.

#### Layer E: the set as a product

**Thesis.** "Agree first, then build confidently" (`docs/overview.md:5`), with specs as current truth kept up to date by deltas that merge on archive (`docs/overview.md:13-21`, `docs/concepts.md:46-50`).

- **The agreement half is right**, and flow does it more strictly. Flow has a computed route, one batched discovery turn, and a hard approval gate that `--amend` clears (`spec/SKILL.md:36-52,97`).
- **The "enablers, not gates" half is wrong for this user.** OpenSpec's verify is advisory and archive does not check it (`docs/commands.md:406`). Flow's exit-code gates are the stronger design.
- **The current-truth half is the one idea flow lacks.** Flow archives with a plain `git mv` (`next/SKILL.md:86`) and remembers only `Ruling:` lines (`spec/SKILL.md:54`). Its own standards review still marks S20 FAIL and lists a `.specs/SPEC.md` as top-5 change #5 (`docs/research/19-flow-standards-review-2026-09-24.md:103,153`).

**Overlap map.**

| OpenSpec | flow | Who is ahead |
|---|---|---|
| explore | develop-idea, prep | flow |
| propose, new, ff, continue | /flow:spec (route, artifacts), new-spec, router drafting | flow |
| apply | /flow:next §Building | flow is stricter |
| verify | converge pass, PASS file, claim-check | flow is stronger |
| update | `--amend` | OpenSpec has a coherence pass; flow is append-only bookkeeping |
| archive | `git mv` + LEDGER | OpenSpec merges into living specs and has idempotent naming guards |
| sync-specs | none | OpenSpec |
| onboard | flow tutorial | equal |
| bulk-archive, stores, worksets, schemas, profiles | none | team-only |
| agent-contract.md | `docs/reference/agents-and-commands.md:10` (prose) | OpenSpec has a contract and tests |
| docs-lab and maintainer doc skills | no-slop, claim-check | OpenSpec is better at page architecture and doc fact-check |

**Should flow fill the gaps?**

1. **Living spec: yes, in flow, as an ADAPT.** A deterministic script folds each archived feature's `## Behaviors` rows into one current-truth file, and spec §3 cites the rows that touch the footprint. Merge order is fixed and the merge is idempotent. A base fingerprint guards each row. Deleting a row needs an opt-in marker. Rows enter only from archived features, never by backfill. The user's ~11 `.specs/` repos hit this on every follow-up feature.
2. **Archive edge cases: yes, in flow.** Guard against `git mv` nesting into an existing target, never stack a second date prefix, and compute the target name once. Today flow's archive step has the nesting hazard.
3. **Amend coherence: yes, in flow.** Fold in a two-way coherence check, a planning-only rule and the intent-change test.
4. **Lint mechanisms: yes, in flow.** Add shared-paragraph parity, marker-vs-disk checks, orphan-task and uncovered-behavior checks, `ac-vanished`, and a blocking open question before TASKS.md.
5. **Doc fact-check: yes, as a claim-check doc mode.** It reports how each fact was verified, keeps rejected findings, and stops after two non-converging passes. The user ships READMEs and research reports with path:line claims.
6. **Team, schema, store, release, onboarding and bulk-archive: no.** These fail B7 for a solo, self-merging user with every PR based on main.

**Net:** no ADOPT. One ADAPT (living spec plus the archive guards), about a dozen MERGEs into existing flow files, and a handful of tricks. Everything else is a SKIP on fit or gap. Covered already (no build): skipped-as-passing (`next/SKILL.md:55,75`), the two-pass stall rule (`review.md:62`), one behavior per requirement (`spec.md:69`), lookup-failure-is-not-empty (`next/SKILL.md:22`), the issue-body-is-data rule (`shared/issue-refs.md:37-40`), and delete-by-list in stealth (`bin/lib/stealth-move.js:63,76`).


### vercel-labs/agent-skills

# vercel-labs/agent-skills vs flow (Layers C and E)

Upstream short SHA for every credit line: **063bee9**. Corrections from the skeptic pass are applied throughout. The biggest one: flow already ships a 44-row condensed port of react-best-practices at `plugins/design/skills/ui-ux-pro-max/data/react-performance.csv:2-45`. That port includes the stale `useLatest Hook` name at csv:45 and `Hydration No Flicker` at csv:29. Server Action auth is already covered in one line at `plugins/design/skills/ui-ux-pro-max/data/stacks/nextjs.csv:53` ("Server Actions are public endpoints"). So vendoring react-best-practices as a second copy is not on the list. The right move is to refresh the existing port.

#### What the set is

Eight skills, listed in `skills/`:
- react-best-practices, composition-patterns, react-native-skills and react-view-transitions are rule catalogs: one rule per file, an impact level, and an Incorrect/Correct pair.
- web-design-guidelines and writing-guidelines are thin shims that WebFetch their rules from GitHub on every run.
- deploy-to-vercel and vercel-cli-with-tokens are deploy skills.
- vercel-optimize is a script pipeline in which the LLM is one untrusted stage.

The README has drifted from what is on disk. `README.md:97` lists `react-native-guidelines` and `README.md:160` lists `vercel-deploy-claimable`, and neither directory exists. `deploy-to-vercel` and `vercel-cli-with-tokens` are not in the README at all. Built `.zip` files are committed next to the skills.

#### Layer C: ways of working (vercel / flow, 0-5)

| Row | vercel | flow | Evidence |
|---|---|---|---|
| C1 Entry and routing | 2 | 4 | vercel: the model picks a skill from its description alone, and the README index names skills that do not exist (`README.md:97`, `:160` vs `ls skills/`). flow: one router, `flow next --json` (`plugins/flow/bin/lib/router.js`), with `/flow:spec` as the only door in. |
| C2 Composition | 2 | 4 | vercel: deploy-to-vercel and vercel-cli-with-tokens repeat the same `.vercel/` and preview-default text (`deploy-to-vercel/SKILL.md:45-51` vs `vercel-cli-with-tokens/SKILL.md:222-230`), and `deploy.sh` and `deploy-codex.sh` are near-identical. flow: shared references are written once (`plugins/flow/skills/shared/verification.md`, `aws-context.md`), and one no-slop rubric serves three consumers. |
| C3 Verification culture | 3 | 4 | vercel is split. vercel-optimize has a no-LLM claim verifier that re-greps every file, snippet and count (`vercel-optimize/lib/verify-claim.mjs:134-151`). But the deploy skills forbid fetching the deployed URL (`deploy-to-vercel/SKILL.md:266`), and the catalog validator's `label.includes('correct')` also matches "Incorrect" (`packages/react-best-practices-build/src/validate.ts:45-51`). flow: CONFIRMED needs an executed receipt (`plugins/flow/agents/adversary.md:54`) and review-diff re-scores findings blind, but receipts are checked LLM-over-LLM (`review-diff.js:49-52`, Score prompt). **Sub-gap:** for the mechanical receipt check alone, vercel-optimize scores 5 and flow 4. |
| C4 Delegation and context | 3 | 4 | vercel: only vercel-optimize delegates, through script-generated briefs ("the brief is the whole prompt", `vercel-optimize/SKILL.md:209`) and a manifest-checked collector. flow: Workflow schemas (`build-slices.js:64-83`), failedLenses, and `task-brief`/`review-package` scripts. |
| C5 Learning loop | 1 | 5 | vercel: no mechanism. Its drift went unfixed (`react-native-skills/SKILL.md:44-101` misses three rule files, and `SKILL.md:130` still says useLatest). flow: the `/flow:lesson` ladder with `lesson-record` and tests (`plugins/flow/scripts/tests/test_lesson.sh`). |
| C6 Human contact | 3 | 4 | vercel: deploy asks before any git push and asks for the team once (`deploy-to-vercel/SKILL.md:35,59-63`), and optimize has a stop-and-ask per blocker code. flow: one batched discovery turn, BLOCKED from developers, and human gates kept outside workflows. |
| C7 Long runs | 1 | 4 | vercel: nothing runs unattended or resumes. flow: `/flow:loop` and `next` recompute position from disk, so they survive /clear, crashes and compaction. |
| C8 Writing quality | 3 | 4 | vercel: writing-guidelines is a fetched house style (`writing-guidelines/SKILL.md:23-29`), and optimize has `references/voice.md` plus sanitizers. flow: `no-slop` prose rubric with `slop_prose.py`. |
| C9 Personalisation | 1 | 3 | vercel: rules are fetched live from Vercel's repo and cannot be overridden. flow: `.claude/flow.config.json` keys (`git-guard.sh:22`), user CLAUDE.md, and design skills that put user style first. |
| C10 Maintenance | 3 | 4 | vercel: a frontmatter and uniqueness gate in CI (`scripts/build-discovery-index.mjs:56-64,145-147`), and a generated-docs freshness check for optimize (`scripts/check-docs-fresh.mjs:19-41`). But CI runs for react-best-practices only, all 139 test-case ruleIds are empty, and the README has drifted. flow: script tests, `skills-lint` for dead links only (`plugins/flow/scripts/skills-lint:1-50`), `version-drift`, `workflow-lint`. **flow has no frontmatter, orphan-reference or README-catalog check.** |
| **Total** | **22** | **40** | No row has vercel ahead of flow by 2 or more. The candidate changes come from specific mechanisms (the C3 receipt check and the C10 gates), not from a better way of working overall. |

#### Layer E: the set as a product

**1. Thesis.** The set has two beliefs, and they do not meet.
- (a) The catalogs: an agent writes better code when it has impact-ranked, example-backed rules that load on demand.
- (b) vercel-optimize: the LLM writes, and scripts decide and verify. Gates choose what to look at, the brief is the whole prompt, and a verifier re-greps every claim. As `verification.md:17` puts it, "the LLM is not asked to judge whether its own output is correct".

Verdict: (b) is right, and it is the strongest idea in the repo. It is the one place vercel's mechanism beats flow's. (a) is right about the content, and the rule writing (labelled before/after pairs, "when NOT to use" clauses) is good. But the catalogs carry no procedure, no gates and no verification. Their own build pipeline has a no-op check and committed drift, and the deploy skills actively forbid checking the result. Overall the set is a knowledge library, not a way of working.

**2. Overlap map.**

| vercel piece | flow piece | Coverage |
|---|---|---|
| react-best-practices (70 rules) | `design/skills/ui-ux-pro-max/data/react-performance.csv:2-45` (44 rows) | About 44 of 70 rules. Missing: module-state leak, dedup-props, hoist-static-io, the cache Object.is trap, no-inline-components, the compiler caveat. Stale: csv:45 useLatest. ui-ux-pro-max skips non-UI performance work (`SKILL.md:42`), so server rules never reach backend or security passes. |
| Server Action auth rule | `ui-ux-pro-max/data/stacks/nextjs.csv:53` | One line, inside a design skill. Nothing in pentest or the audit playbook. |
| async-*/bundle-* | `flow-extras/skills/audit/references/language-playbooks.md:18-32` (gather), `:622` (barrel one-liner) | Partial. |
| composition-patterns | `flow/skills/no-slop/references/rubric.md:20` NS-32 | Generic boolean-mode rule, with no React form. |
| react-view-transitions | `design/skills/impeccable/reference/overdrive.md:51`, `animate.md:40,67` | Names the API only. No React/Next mechanics and no silent-no-op list. `ui-animation/SKILL.md:10-20` has no row for it. |
| web-design-guidelines | `design/skills/impeccable/reference/audit.md` | Mostly covered. |
| writing-guidelines | `no-slop/references/prose-rubric.md` + `scripts/slop_prose.py` | Mostly covered. Minimizer words are missing (only "simply" inside the NP-06 pattern, `slop_prose.py:21`). |
| react-native-skills | `design/skills/mobile-design` | Covered enough. Fit 1. |
| deploy-to-vercel, vercel-cli-with-tokens, vercel-optimize domain content | `aws/skills/sst` | Fit 0-1: the user deploys with SST/AWS, not Vercel. |
| vercel-optimize verify-claim | `flow/agents/adversary.md:54` receipts, review-diff blind Score | **Gap.** No script checks that a cited path:line exists or that a quoted line is really there. |
| build-discovery-index frontmatter gate | `flow/scripts/skills-lint` (dead links only) | **Gap.** |
| check-docs-fresh | none | **Gap** (README skill tables). |
| dedup-recs | `review-diff.js:49-52` (40-char predicate key) | Weaker in flow. |
| flow lesson ladder, loop, router, spec gate | nothing | vercel has nothing here. |

**3. Should flow fill the gaps?**
- **Mechanical receipt check: yes, in flow.** Add a new `plugins/flow/scripts/receipt-check`, called from review-diff between Find and Score. Run the same core as an advisory `slop-check --prose --claims` pass. This is the top borrow.
- **skills-lint frontmatter, orphan and README-catalog checks: yes, in flow** (they guard flow's own repo).
- **React/Next correctness and security: yes.**
  - Refresh the existing csv port in design (do not vendor a second copy).
  - Put Server Action auth and the module-state leak in tooling/pentest and the flow-extras audit playbook, where backend passes will see them.
- **View transitions: yes, a small on-demand reference in design:ui-animation.**
- **AWS-side lessons: yes, in aws/shared.** These are account-scope verification, read-only probes and a preview-stage default.
- **Vercel deploy and optimize content, RN rules, the AGENTS.md monolith: no.** They fail fit.

#### Candidate build items
VER01-VER33 are judged good. VER34-VER46 are recorded as not worth doing, each with a reason. Every credit line is `vercel-labs/agent-skills @ 063bee9`. Every PR that touches plugins/* bumps that plugin in both plugin.json and marketplace.json.

### anthropics/skills

# anthropics/skills against flow: whole-set review (Layers C and E)

Upstream was read at `dbd4588`, from `/home/tomas/.claude/jobs/20064eaf/tmp/repos/anthropics_skills`. It has 19 skills under `skills/`, the Agent Skills spec pointer and a template. The marketplace ships two plugins, `document-skills` and `example-skills` (`.claude-plugin/marketplace.json`). The README calls the set "for demonstration and educational purposes only" (README.md:24) and "inspiration for your own skills" (README.md:18). The user already has every one of these skills installed as `anthropic-skills:*`, so a borrow means taking ideas and mechanisms into flow. It never means copying files. The only flow file that mentions upstream is a find-skills pointer (plugins/flow-extras/skills/find-skills/SKILL.md:50), so the upstream-diff rule yields no items.

The skeptic corrections are applied below:
- The research-sweep defect sits in synthPrompt and the log count. `filter(Boolean)` is not the cause.
- benchmark-checklist Q4 already diffs against the old code. Only the frozen-original randomized harness is new.
- skills-lint already resolves path references, so the change extends skills-lint instead of adding a new test.
- `case-selfcheck --live` already runs llm graders, so the known-negatives check belongs there.
- verifier-design.md:49 already describes a held-out set, but only in prose. It is not wired into `--metric`.
- Fit for eval-audit and eval-hillclimb drops from 5 to 4.
- For local MCP servers, the bind stays at 127.0.0.1.
- The truncated-count trick is already in flow.
- The fresh-eyes screenshot check already exists in fix/SKILL.md:47,107.
- The schemas row and the aggregate_benchmark row move to B1=1.
- The analyzer classes must exclude `arm: with-only` graders and need runs >= 3.

#### Layer C: ways of working (0-5)

| Code | anthropics/skills | flow | Evidence |
|---|---|---|---|
| C1 Entry and routing | 3 | 4 | Upstream: claude-api is a router whose subcommand table sends each verb to one guide, with the order "Do not summarize the guide - execute it" (skills/claude-api/SKILL.md:59-61). Its description carries a provider-skip grep (:6). The other 18 skills are reached only through description matching. flow computes position from disk: "Read `flow next --json` FIRST, every turn" (plugins/flow/skills/next/SKILL.md:12). |
| C2 Composition | 3 | 4 | Upstream: claude-api's `shared/` files are single sources (platform-availability.md and live-sources.md are referenced, never restated). But `scripts/office/` is copied into docx, pptx and xlsx (`ls skills/*/scripts/office` shows three copies). flow: `plugins/flow/skills/shared/` holds verification.md, pr-body.md and aws-context.md, all referenced by name. |
| C3 Verification culture | 3 | 5 | Upstream has the best verification ideas of any set reviewed: a prover that gets only the claim and writes a failing test (claude-api/shared/managed-agents-quickstarts/bug-hunter.md:61), a frozen-original differential check (performance-tuner.md:57,62), a no-op stamp check (xlsx/scripts/recalc.py:172-212) and fresh-eyes render QA (pptx/SKILL.md:206). Almost all of it is prose that nothing enforces. flow has the RED gate, PASS-<sha>, the blind re-score phase (plugins/flow/workflows/review-diff.js:118-126), lesson red-then-green (plugins/flow/skills/lesson/SKILL.md:88-90) and case-selfcheck oracle and null runs (plugins/flow/evals/README.md:88-91). |
| C4 Delegation and context | 4 | 3 | Upstream blinds its checkers on purpose. The prover sees only the claim, the perf checker gets no claimed number (performance-tuner.md:72), the hill-climb analyzer reads train traces only and the proposer sees scores only (evals/eval-hillclimb.md:205-207), and the optimiser history is stripped of test keys (skill-creator/scripts/run_loop.py:194-198). flow's scorer is handed the finder's whole finding: `'Finding: ' + JSON.stringify(f)` (review-diff.js:121). research-sweep logs `researched usable.length of angles.length` (plugins/flow/workflows/research-sweep.js:108), which counts research:null angles as researched, and its gaps come only from unknowns and queriesRun (:115). Upstream leads by 1. That is below the 2-point bar, but the two concrete defects are worth fixing. |
| C5 Learning loop | 3 | 4 | Upstream: eval-hillclimb turns failures into categorised stalls (eval-hillclimb.md:279-295). skill-creator says to bundle the helper script that every run keeps writing (skill-creator/SKILL.md:304), and feedback.json carries across iterations (eval-viewer/generate_review.py:213-247). It has no guardrail ladder. flow's lesson ladder puts the most deterministic rung first, writes it red then green and has an adversary try to bypass it (lesson/SKILL.md:88-90). |
| C6 Human contact | 4 | 4 | Upstream: "a proposal followed by files in the same turn is not a proposal" (managed-agents-onboarding-from-url.md:80); "`--yes`, which is the user's approval, not yours" (:198, managed-agents-onboarding.md:66); "propose, don't interrogate" (managed-agents-onboarding.md:19); and prompt-audit states its assumptions instead of asking (claude-api/SKILL.md:60). flow states its stop count and has `--finish` for when the user is leaving (next/SKILL.md, flags). |
| C7 Long runs | 2 | 5 | Upstream's runners keep a resume key and a failure sidecar (evals/build-eval.md:112-114), but no skill has caps, a negative control or crash recovery. flow loop has caps, negcontrol and tamper, and `--yolo` arms an unattended run (plugins/flow/skills/loop/SKILL.md:20-22). Position is recomputed from disk. |
| C8 Writing quality | 3 | 4 | Upstream's newer skills are calibrated: "The model knows the API; these are the footguns" (docx/SKILL.md:21), and discernment-nudge treats silence as the default. The older art skills lean on CAPS and praise. flow has NP-01 to NP-12 with `slop-check --prose` (plugins/flow/skills/no-slop/references/prose-rubric.md:20-22). |
| C9 Personalisation | 2 | 2 | Upstream: brand-guidelines and theme-factory can only be customised by forking. flow: per-project thresholds and autoApprove only. |
| C10 Maintenance | 1 | 4 | Upstream has no tests and no CI (find shows no test files and there is no `.github/`). The prose layout has drifted from aggregate_benchmark.py, and the delta sign flip was reproduced. mcp-builder still defaults to a retired model, `claude-3-7-sonnet-20250219` (mcp-builder/scripts/evaluation.py:223,324). The marketplace version is a static 1.0.0. flow has script and hook suites, test_plugin_refs.sh runs skills-lint (plugins/flow/scripts/skills-lint:1-12), and contract.js holds the eval schema. |
| **Total** | **28** | **39** | No row has upstream ahead by 2 or more. C4 is the only row upstream wins, by 1. |

#### Layer E: the whole set as a product

**1. Thesis.** The set's belief is that a skill is a measurable hypothesis and that checking must be blind. You run with and without the skill, select on held-out data, give the checker only the claim, and treat a surprising number as a bug. The rest of the set is reference material that Anthropic keeps current. The belief is right, and it is the same one behind flow eval and loop `--metric`. The difference is where it lives. Upstream writes its best verification ideas as prose prompts for hosted Managed Agents or claude.ai, and nothing runs them, tests them or checks them against drift. Its own scripts have drifted (C10=1). Flow has the opposite profile: strong on mechanism, weaker on blinding. **Verdict: take the blinding and measurement methods and wire each one into a flow script or workflow. Take no files.**

**2. Overlap map.**

| Upstream | Flow counterpart | Gap |
|---|---|---|
| skill-creator loop (with/without, grader, comparator, analyzer) | flow eval with/without arms over 3 runs; skill-improver Step 2f (plugins/flow-extras/skills/skill-improver/SKILL.md:120-128); skill-forge behavioural check (skill-forge/SKILL.md:351) | Flow lacks per-grader discrimination classes, blind pairwise scoring for unscored skills, and grader self-critique |
| run_eval.py / run_loop.py description optimiser | Flow only defers to it: "if the skill-creator skill's run_loop.py is available" (skill-forge/SKILL.md:357). skill-judge wants a measured trigger rate (skill-judge/SKILL.md:189), but nothing in flow produces one | Real gap |
| quick_validate.py | skills-lint checks path references only (skills-lint:2); test_commands.sh checks only that the name and description keys exist | Real gap: 5 descriptions over 1024 characters and 7 SKILL.md files that fail yaml.safe_load |
| claude-api evals/ (eval-audit, eval-hillclimb, build-eval) | loop --metric keeps a change only when it beats the best by more than the init noise (plugins/flow/bin/lib/loop/metric.js:66-67,202); a held-out set exists in prose only (loop/references/verifier-design.md:49); case-selfcheck --live (evals/README.md:88-91) | Flow lacks a holdout gate in code, n>=2 near the bar, judge known-negatives, an errored-run sidecar and stall categorisation |
| bug-hunter / watchlist / deep-researcher quickstarts | review-diff.js, research-sweep.js, flow-extras audit | Flow lacks claim-only scoring, recall framing, a lines-read receipt, failed angles named as not covered, and citation upgrade |
| performance-tuner | benchmark-checklist Q2-Q6 (flow-extras/skills/benchmark-checklist/SKILL.md:23-27) | Flow lacks a frozen-original randomized differential check, a geomean that includes the candidate's worst shape, and a blind re-measure |
| prompt-audit / cost-optimization / prompt-caching / agent-design | tooling agent-architecture references; flow-extras skill-improver and claude-md | Flow lacks the keep list, "finds nothing, changes nothing", a model-call-site count, and invalidator grep signals |
| mcp-builder | agent-architecture/references/tool-design.md | Flow lacks MCP server hygiene lines and an MCP eval method (the user maintains about 6 MCP servers) |
| frontend-design / theme-factory | design:vary roll, check.mjs and the evaluator | Covered. Only a few tells are worth adding as detectors |
| webapp-testing | shared/verification.md, start-dev-server, verify-skill | Covered, except the wrap-and-kill mode |
| doc-coauthoring | spec-judge; plan-review.js lenses (plugins/flow/workflows/plan-review.js:58) | Flow lacks a cold-reader question-and-answer test |
| docx/pptx/xlsx/pdf, Managed Agents, art, brand, comms, GIF, academy | none | Fit 0-1: skip |

Flow has things upstream lacks entirely: a router-computed position, hooks as gates, a lesson ladder, unattended loops with tamper and negcontrol checks, fleet workflows with schemas, and a prose linter.

**3. Should flow fill the gaps?**
- **Yes, in flow:**
  - research-sweep should name not-covered angles.
  - review-diff should score blind on the claim alone, with recall framing and a lines-read receipt.
  - loop --metric should get a holdout gate and n>=2 near the bar.
  - flow eval should get grader discrimination classes, an errored-run sidecar and judge known-negatives.
  - skills-lint should get a `--frontmatter` mode and cover all plugins.
  - The verification and verifier-design references should gain the stamp check, fresh eyes on the next/spec path, and the rule that a check which failed to start does not count.
- **Yes, in flow-extras:**
  - skill-improver should get trigger-eval plus the run_loop optimiser, credited @ dbd4588, a blind pairwise check with order swap, and the keep list.
  - benchmark-checklist should get the differential harness and a blind re-measure.
  - audit should get a second-look pass and exact-cover line-count slices.
  - ultracode should state its plan, agent count and cost up front, and grep that each rule reached every agent.
- **Yes, in tooling:**
  - agent-architecture should get MCP hygiene and the call-site, cache and tool-promotion anti-patterns.
  - agent-evals should get an eval-audit reference and an MCP eval method.
  - version-audit should flag stale Claude model IDs.
  - wizard should get the secret-handling tricks.
- **No:**
  - Vendoring claude-api or the office skills would fork a moving upstream the user already installs.
  - The Managed Agents docs, art, brand, comms and academy skills do not fit.
  - The report viewer schema stays upstream.
  - The anti-tricks stay out: pushy descriptions, "avoid testing upfront", killing whatever holds the port, and treating any first tool other than Skill or Read as a miss.



## Verification

- Scripts suite (`bash plugins/flow/scripts/tests/run.sh`): 6089 passed, 11 failed after the version bump. The 11 are the same failures main has (install/doctor fixtures, `workflows-and-cli.md` help text, the I-005 loop test, two `check-all` gate-record tests).
- Hooks suite (`bash plugins/flow/hooks/tests/run.sh`): 1641 passed, 0 failed.
- `build-slices.js` split: 832 lines after the lanes, 253 + 397 (`build-slices-task.js`) after. A stub differential recorded 165 agent calls on 5 scenarios before and after; `result.json` was byte-identical. A live probe confirmed the real Workflow runtime runs a child by absolute `scriptPath`, passes args, returns its value, and throws on a missing file (build-slices turns that into `incomplete`, never a silent success).
- The orchestrator restored the three lenses inside F51's scoped re-review (gaming and slop had dropped out).
- Not run: live evals of the new behaviour (they need a release), a live `/flow:next --finish` on a CI repo, the wizard pty test on macOS.

## Eval context

The old-vs-new live comparison was run before this round (old 702895a vs new 6ac0f44, 32 shared xhard cases, 2 runs each): passed 47 -> 49 of 64, post-checks 48 -> 53 of 64, mean score 0.977 -> 0.971. Two regressions it exposed were fixed in this branch (prep rule 5 kept rule 2's hypothesis; `/flow:next` never self-schedules a re-run). The `flow eval` half was cut off by a usage limit and is being re-run. This round's ideas are not in either measured version; measuring them needs a third arm after merge.
