# cursor/pstack borrow review — 2026-10-09

Source: https://github.com/cursor/plugins/tree/main/pstack (pstack 0.15.15, by poteto, MIT). Cloned to a temp dir, never run. Every SKILL.md, playbook, reference, agent, script and guide page was read in full: 51 skills (24 of them one-rule principles), 23 playbooks, 2 agents, the benny automation pack, the 11-page guide, and the orch, watch-pr and check-plan tools.

Scoring sheet: [`23-pstack-rubric.md`](23-pstack-rubric.md). It is reusable for the next outside set. It adds four layers to skill-judge's craft score: idea value (B), ways of working (C), a clever-tricks log (D) and the whole set as a product (E).

## How it was scored

1. Eight Opus reviewers each scored one slice of pstack on layers A, B and D, opening the flow file before claiming "flow already has this".
2. Eight Opus skeptics (adversary agents), one per slice, tried to break each review. They made 48 corrections: wrong flow line numbers, missed flow coverage, verdicts that did not follow the rubric's thresholds, and overstated mechanism scores. The tables below show each correction in the "Skeptic note" column.
3. One Opus judge scored the whole set against flow on layers C and E.

## Verdict in one paragraph

pstack and flow believe the same thing: trust comes from verification, not from speed, so write less and prove more. They differ in how they carry that belief. pstack carries it mostly as prose the model is asked to follow (24 one-rule principle skills, 23 playbooks copied into a todo list). flow carries it as checks the model cannot skip (Stop-hook gates, PASS-<sha> files, revert proofs, loop negative controls). On the ten ways-of-working rows the totals are close: pstack 37/50, flow 39/50. flow wins verification (+2) and self-maintenance (+2). pstack wins writing quality (+2) and personalisation (+2). pstack also owns three things flow lacked entirely: life after a PR opens (babysit, review-bot triage, a tested PR watcher), vetting a measured number before reporting it, and "observe, don't ask" (a fork you can settle by running something is not the human's question). Most of the rest is either already in flow in a stronger form, or locked to Cursor (custom modes, a Grok+Opus model panel, Cursor-team-kit skills, Graphite stacks).

## Verdict counts

| Verdict | Count | Meaning |
|---|---|---|
| ADOPT | 3 | benchmark-checklist, create-verification-skill, bugbot-triage reference |
| ADAPT | 13 | hillclimb, prototype, eval, babysit, watch-pr, why, unslop, technical-writing, benny repro-and-fix, build-the-lever, morning audit, plan-through-code, pin-behaviour-first |
| MERGE | 33 | a piece folds into an existing flow skill |
| SKIP | 50 | flow already covers it, or it is host-locked or team-process shaped |

99 rows in all. Counts are before skeptic corrections; the skeptics moved several verdicts (for example prototype ADAPT to MERGE, two guide SKIPs to MERGE), noted in the tables.

## cursor-team-kit, the companion plugin

Added on request after the pstack review: https://github.com/cursor/plugins/tree/main/cursor-team-kit (18 skills, 2 agents, 2 rules; pstack depends on its deslop, control-ui and control-cli). Same method: three Opus reviewers, three Opus skeptics (17 corrections over 22 rows), one whole-set judge. It was scored against flow *including* the pstack borrows above, so nothing is counted twice.

Verdict: the kit is a set of short task checklists (fix-ci, new-branch-and-pr, get-pr-comments, deslop, check-compiler-errors). Most are prose a model already follows, and flow covers them with scripts and gates: babysit and pr-watch cover the CI loop, next §Ship covers branching and PRs, no-slop covers deslop, check-all and the Stop gate cover compiler errors. 0 of its 47 logged tricks scored 4 or more on the steal scale. The few pieces worth taking are listed under "Landed".

## Fit check: does it match how the user works?

The user pointed out that some of these skills do not fit their work. So a seventh idea-value question was added to the rubric, **B7 Fit**, scored from an evidence profile of their own repos (45 git repos under `~/Desktop/Projects`, surveyed read-only), and B7 <= 1 now means SKIP whatever the other scores say.

The profile, in short:

- Solo. PRs are opened and merged by the same person. Sampled PRs on flow, news and worklog have zero reviews and zero comments. No review bots.
- No stacked PRs: every PR's base is main.
- CI in 11 repos (opengym, worklog, ads-seo, a client repo, TerminalWebsite and others); flow, finance, news and terraform have none.
- Mostly Next.js and Vite UIs, Python agents on AWS, Terraform and SST, two Rust CLIs. No TUI libraries anywhere. Some real performance work (news pipeline, finance budgets).

What the fit check changed:

| Item | Fit | Change |
|---|---|---|
| babysit: review-bot triage, review-thread answering, stack ordering | 0 to 1 | Removed. babysit now drives CI failures and merge conflicts on one or several independent PRs, and stops for the user if a PR ever has review threads. |
| babysit: CI and conflicts | 3 | Kept, and strengthened from the kit (failing-check links, `--log-failed`, lockfile and conflict-marker checks, a 60-minute default cap). |
| lesson --retro reading PR review comments | 0 | Removed. Reverts, fixup commits and workaround comments stay. |
| Kit: CLI/TUI driver (control-cli, tmux) | 1 | Skipped. None of the user's projects uses a TUI library. |
| Kit: exhaustive-switch lint | unknown | Skipped. Needs typed linting in TS repos; not shown in the profile. |
| Kit: pr-review-canvas, weekly-review, what-did-i-get-done | 1 | Skipped. Team review and team reporting. |
| pstack: shipping, autopilot, orchestrate, orch store, benny | 0 to 1 | Already skipped; the fit check confirms it (no stacks, no team, no Slack triage). |
| verify-skill, benchmark-checklist, prose rubric, Attention digest | 3 to 5 | Kept: many UI apps, real perf work, Claude-written PR bodies, unattended flow runs. |

The profile is saved as a memory (`borrow-fit-profile`) so the next borrow review scores fit from the start.

## Landed

Built as 12 slices. Each went to a Sonnet developer with a written spec, then to a separate Opus adversary that ran the tests itself, then got one fix round. The three new skills also went through skill-forge: a baseline run without the skill, a cold skill-judge loop to 96/120 or more, and a behaviour check against the baseline.

### New skills (flow-extras)

| Skill | From | What it does | Judge | Behaviour check |
|---|---|---|---|---|
| `babysit` | pstack babysit playbook, watch-pr, kit fix-ci / loop-on-ci / fix-merge-conflicts | Drives one or several open PRs through red CI and merge conflicts. `scripts/pr-watch` is a gh-only poller with a tested `decide()` policy; it prefers the PR with work to do, prints failing-check links, defaults to a 60-minute cap. Never merges, never readies an unattended PR, never force-pushes. Lockfiles are regenerated, and `git diff --check` plus a conflict-marker grep must be clean before a push. Stops for the user if a PR has review threads. | 103/120 (after the fit trim) | baseline failures fixed, no regression |
| `verify-skill` | pstack create- and maintain-verification-skill | Writes a project-local `.claude/skills/verify-<project>/SKILL.md` with a feature map (path, reset, states, evidence per feature) and runs it once before calling it done; maintain mode lands at most one PR of proven corrections. | 104/120 | baseline failures fixed, no regression |
| `benchmark-checklist` | pstack benchmark-checklist, explain-the-number, perf-issue mantra ladder | Before a measured number is reported: what limits it, warm vs cold, errors, repeated runs with range, end-to-end relevance, same-method baseline; verdict faster / slower / no difference / inconclusive. | 102/120 | baseline failures fixed, no regression |

### Changes to existing flow pieces

| Where | Change | From |
|---|---|---|
| `flow/skills/no-slop/references/prose-rubric.md`, `scripts/slop-check --prose`, `scripts/slop_prose.py` | Prose rubric NP-01.. for PR bodies and docs: claims carry measured / inferred / guess or their command, count claims carry the command that regenerates them, AI-tell words, stacked hedges, throat-clearing, long sentences. `--prose` checks the script-detectable rows, skips code fences, advisory unless `--strict`. No dash or colon ban. | unslop, technical-writing, poteto-mode reply rules, why epistemics |
| `flow/skills/shared/pr-body.md` | Run `slop-check --prose` on the body; separate core from generated files, split a PR that notes cannot make reviewable. | unslop; kit make-pr-easy-to-review |
| `flow digest` (`bin/lib/digest.js`), `flow finish off`, loop `done` row | An Attention list for the human after an unattended run: unfiled deferred defects, then assumptions, then rulings, each with its `NOTES.md:<line>`. Prints nothing when there is nothing. | show-me-your-work morning audit |
| `flow/skills/lesson/SKILL.md` | `--retro` also reads reverts, fixup commits and workaround comments; a class counts only when seen twice; new top rung "make it unrepresentable". | correct, reflect |
| `flow/skills/spec/references/question-bank.md` | Settle an empirical fork with a scratch probe before the discovery turn and quote the result; bigger probes are prep spikes. | poteto-mode observe-before-ask |
| `flow/agents/claim-check.md` | A change claim is run at the merge base (temporary worktree) and at HEAD; new INCONCLUSIVE verdict. | kit verify-this |
| `flow/agents/adversary.md` | Cross-file lens: "look where grep stops". New opt-in `structure` lens (did the diff move complexity or remove it), accepted by review-diff only through `args.lenses`. | blast-radius; kit thermo-nuclear review |
| `flow/workflows/review-diff.js` | Returns `dismissed: [{finding, reason}]` for every unique finding not kept, including "scorer failed; not scored". | interrogate lead-judgment |
| `flow/workflows/research-sweep.js` | Confidence words tied to evidence tiers ("confirmed" only with a primary source read this run). | why epistemics |
| `flow/bin/lib/doctor-hygiene.js` | Squash-merged worktrees are now recognised (`git cherry`, then a whole-branch patch-id match that writes no git objects). | worktree-cleanup |
| `flow/skills/fix/feedback-loops.md` | Perf line points to benchmark-checklist, which carries the perf-fix order (don't do it, do it once, do it less, ...). | perf-issue |
| `flow/skills/no-slop/references/rubric.md` NS-09 | A lint suppression is fine only for a style-only or wrong rule. | comment-sicko |
| `tooling/skills/agent-evals/SKILL.md` | Nothing a candidate sees may say it is graded; grade chain-following from files it opened, not its claims. | eval playbook |
| `flow-extras/skills/ultracode/SKILL.md` | Script before fleet. | build-the-lever |

### Bugs in flow found along the way

- `shared/scripts/start-dev-server --kill` without `--port` killed the server it had just started (it found the port after spawning, then killed whatever was on it). The post-spawn kill is removed; a test starts a real server and checks it survives.
- `shared/verification.md` step 5 deleted the verify screenshots, while flow's own rule says a claim with no artefact on disk does not count. Evidence now moves to `<Feature>/verify/`.

## Skipped, and why

- poteto-mode as a mode, its 23-playbook router and the 24 principle skills: flow's `flow next` router and its checks already carry the same rules in a form the model cannot skip; a principle library adds reading, not enforcement. Three small pieces were taken (above).
- bug-fix, tdd, feature, refactoring, investigation, how, swarm, figure-it-out: flow fix, spec, next, flow-deepen, explorer and research-sweep cover them, mostly with more mechanism.
- shipping, autopilot-full/-stack, orchestrate and the orch store, multi-phase-plan, benny: team process, Graphite stacks and Slack triage; fit 0 to 1.
- arena, interrogate's model panel, setup-pstack: built around a multi-vendor model panel; flow pins Anthropic models on purpose.
- hillclimb (a metric loop): useful, but no current task needs it. Recorded for later.
- why as a skill: MCP-heavy design archaeology; only its confidence tiers were taken.
- automate-me, recall, teach, bro, make-bot-ui: covered by claude-md, PROGRESS.md, smoothbrain and the ELI5 style, or Cursor-only.
- Kit: fix-ci, loop-on-ci, get-pr-comments, new-branch-and-pr, review-and-ship, ci-watcher (babysit and next §Ship cover them), deslop (no-slop), check-compiler-errors (check-all and the Stop gate), run-smoke-tests and control-ui (e2e-testing, agent-browser, verify-skill), control-cli (fit 1), pr-review-canvas, weekly-review, what-did-i-get-done (team), the exhaustive-switch rule (fit unknown).

## Filed

- I-003 in `.specs/ISSUES.md`: 40 eval scaffold files set the git author to "eval-scaffold", which tells the candidate it is graded.
- I-004: two dead references in `plugins/flow/evals/README.md` (pre-existing on main).

## Verification

- Full scripts suite (`bash plugins/flow/scripts/tests/run.sh`):
  - main at session start: 3435 passed, 10 failed;
  - this branch: 3509 passed, 11 failed.
- The 11 failures are the same 10 that main had at session start (install, doctor and docs tests), plus `t_negcontrol_pid_output_refuses`. That test began failing on main too during the day, with no loop code changed here (I-005).
- New and touched test files, each run on its own:
  - test_no_slop 77/0
  - test_workflows 129/0
  - test_doctor_hygiene 33/0
  - test_agents 52/0
  - test_lesson 87/0
  - test_plugin_refs 26/0
  - test_marketplace 155/0
  - babysit `test_pr_watch.py` 49 OK
- Red before green for each bug:
  - the start-dev-server self-kill;
  - multi-commit squash detection;
  - review-diff losing or inventing scores for failed scorers;
  - slop-check --prose reading a list as one sentence;
  - pr-watch letting a waiting PR block a red one. The reviewer reproduced this one; the fixer's new tests were not shown red.
- One test change is an exception, not a weakening: `test_plugin_refs.sh` documents verify-skill's target-project path `.claude/skills/verify-` beside the existing pr-reviewer exception.
- `skills-lint`:
  - tooling and flow-extras: 0 MISSING;
  - flow: 2 MISSING, both pre-existing on main (I-004).
- The three new skills' behaviour checks are simulated walkthroughs. No real PR, app or benchmark was driven, so their first real use is the live test.

## Appendix A: pstack ways of working and the set as a product
### 1. Layer C: ways of working

| Row | pstack | flow | Evidence (pstack, then flow) | pstack +2? |
|---|---|---|---|---|
| C1 Entry and routing | 3 | 4 | pstack has one router of 23 playbooks, and the model matches the task by its own guess (pstack/skills/poteto-mode/SKILL.md:119-147). Almost every other skill is slash-only with `disable-model-invocation: true` (how/SKILL.md:4, interrogate/SKILL.md:4). Its onboarding guide is good (docs/guide/02-poteto-mode.md:40-59). flow computes position from disk: "Read `flow next --json` FIRST, every turn" (plugins/flow/skills/next/SKILL.md:12). flow's newcomer docs are thin: a 108-line README, with no "how to ask" or pitfalls page. | no |
| C2 Composition | 4 | 4 | pstack writes each principle once and names it: "Read the leaf skill in full for any principle you apply" (poteto-mode/SKILL.md:40), with one reply contract shared by every playbook (:113). But the forge-resolution paragraph is copied into 6 playbooks (shipping.md:7, babysit.md:7, ...). flow keeps shared refs in plugins/flow/skills/shared/ (pr-body.md, verification.md) and pastes the no-slop developer block verbatim (no-slop/SKILL.md:35). flow has some copied wording too (agents/developer.md:19). | no |
| C3 Verification culture | 3 | 5 | pstack says "'Inconclusive' or wrong-surface is not a pass" (bug-fix.md:10) and "CI green is not a verdict" (shipping.md:7). Its one coded mechanism is the verdict ledger keyed by PR and head SHA (scripts/orch/store.ts:1358-1371). The rest is prose. flow has the revert proof (plugins/flow/skills/fix/SKILL.md:85), the loop negative control (loop/SKILL.md:24), "The agent's report is never the gate" (next/SKILL.md:55), PASS-<sha> files with integer exit codes (:74), and blind re-scoring (workflows/review-diff.js:67-74). | no (flow +2) |
| C4 Delegation and context | 4 | 4 | pstack's fresh subagent gets "consolidated scope, meaning the original brief, every later directive, and the prior agent's report" (poteto-mode/SKILL.md:99). Its 9-field brief means "missing field = refuse to spawn" (orchestrate.md:38-56). flow hands the developer "only the brief path" (next/SKILL.md:53), and its workflows use JSON schemas (build-slices.js:29-40). Each flow fix round is already a fresh agent (build-slices.js:226-234). The only missing piece is carrying earlier rounds' findings forward. | no |
| C5 Learning loop | 3 | 4 | pstack mines more widely. /correct reads "commits, reverts, review comments", counts a class only once it has happened twice, and ranks architecture and types above tests (docs/guide/09-make-it-yours.md:35-48). It is all prose: correct/SKILL.md is 32 lines with no script. flow builds better: the test→hook→script→skill→CLAUDE.md ladder (lesson/SKILL.md:53-59), red-then-green (:66-71), an adversary bypass (:75) and lesson-record. But --retro reads only "this conversation, or a named session log" (:15). | no |
| C6 Human contact | 4 | 4 | pstack: "Just do it" for reversible work, "Always pause for irreversible writes", plus session overrides (poteto-mode/SKILL.md:81-89). Its observe-before-ask rule is new: if a fork is "a fact you could observe by running something", prototype it instead of asking (:20). flow states the route without asking (spec/SKILL.md:44), counts its stops truthfully, "This run will stop for you N times" (:84), and under --unattended/--finish "resolves decisions, never evidence" (next/SKILL.md:117). flow never readies an unattended PR (:149). pstack lets agents merge (autopilot-full). | no |
| C7 Long runs | 4 | 4 | pstack: a durable orch store with stale-pid lock takeover (store.ts:368-441), crash recovery that reattaches by PR and branch (orchestrate.md:101), a watch-pr poller with tests, and pause-safely plus session-pickup. It wins on multi-PR programs and the post-PR phase. flow: fresh-session loops "capped at 240 minutes and 40 iterations", with a tamper veto (loop/SKILL.md:25), a negative control before arming (:24), and --finish backed by finish-gate.sh (next/SKILL.md:97-108). flow wins on caps and anti-gaming. | no |
| C8 Writing quality | 5 | 3 | pstack: unslop has 33 rules with "stable ids that other skills cite" (unslop/SKILL.md:18). technical-writing covers docs, RFCs, PR bodies and commits. The reply rules require "Every claim carries its evidence or its label... Measured, inferred, or guess" (poteto-mode/SKILL.md:111). The epistemics tiers tie confidence words to citations (why/references/epistemics.md:61-95). flow: no-slop covers code only (no-slop/SKILL.md:3). pr-body.md fixes the PR's shape, not its prose. Prose rules exist only per skill (design/skills/smoothbrain/SKILL.md:29; flow-extras/skills/pr-reviewer/SKILL.md:297). | **yes (+2)** |
| C9 Personalisation | 4 | 2 | pstack: /setup-pstack writes per-role model lines, with `auto` and `inherit-parent`, which "override these defaults" (poteto-mode/SKILL.md:95). /automate-me drafts a `<you>-mode` from your own transcripts (09-make-it-yours.md:7-21). flow pins models in agent frontmatter (plugins/flow/agents/explorer.md:5 `model: haiku`) and in workflow JS (review-diff.js:113). Its per-project knobs are thresholds and autoApprove only (README.md:56). | **yes (+2)** |
| C10 Maintenance | 3 | 5 | pstack: orch has 634 lines of tests (orch.test.ts:184-580) and watch-pr has truth-table tests. But check-plan.mjs has no test, devDependencies are `latest` (scripts/package.json:11-12), the SKILL validator is optional (reflect/SKILL.md:64), and worktree-audit.sh is macOS-only and untested. flow: hook and script suites (README.md:85), skills-lint, workflow-lint, `flow doctor`, 67 eval cases, and the version-bump rule. | no (flow +2) |
| **Total** | **37** | **39** | | |

**Where pstack leads by 2 or more:**
- **C8, writing quality.** This is a real candidate change. The part worth taking is the evidence label and a rubric that a script can check. The dash and colon bans are style, not substance.
- **C9, personalisation.** This needs a ruling first. Most of pstack's lead is choosing among a Grok and Opus model panel. That does not port to Claude Code, and it conflicts with the user's rule "Pin `model` ... on every fleet call; never let a worker inherit the session model" (~/.claude/CLAUDE.md, Delegation). `/automate-me` (a personal mode mined from history) is the one part that ports. It is low leverage.

**Where flow leads by 2:** C3 and C10. On C5 and C7 the two sides have different strengths, so neither is simply better.

### 2. Layer E: the set as a product

### 2.1 Thesis

pstack's belief: **go deep before going fast. An agent that carries rigorous principles and verifies its own work can be trusted, so you can run many of them in parallel ("fearless parallelism"). Use several model families so they check each other** (pstack/README.md:5-11).

**Verdict: half right.**
- **Right:** trust comes from verification, not from throughput, and "write less, but higher quality code" (README.md:7). That is flow's own thesis.
- **Weak:** pstack carries rigor mostly as prose the model is asked to follow. It reads the principle leaf files, copies playbook steps into a todo list (poteto-mode/SKILL.md:121), and names principles in its reply (:15). flow's thesis is the stronger form: "give the agent a check it can run, and make the check impossible to skip" (README.md:17).
- **Host-locked:** the multi-model half needs Cursor's model panel.

pstack is ahead of flow in three places:
- the prose it writes;
- the life of a PR after it opens (babysit, bot triage, watch-pr);
- "observe, don't ask": a fork you can settle by running something is not the human's question.

### 2.2 Overlap map

| pstack piece | flow piece | Gap side |
|---|---|---|
| poteto-mode router + 23 playbooks | flow next state machine; spec / fix / loop doors | flow stronger (deterministic) |
| bug-fix, tdd | fix (repro test, revert proof) | flow stronger |
| feature, architect, multi-phase-plan | spec + next + design.md + build-slices | flow stronger. architect's parallel design exploration is not in flow. |
| refactoring | flow-deepen (characterization test as `verify:`) | flow stronger. Only the rename sweep is new. |
| perf-issue, benchmark-checklist | fix/feedback-loops.md:61 (baseline before bisect) | **pstack** (vetting a number before you report it) |
| hillclimb | loop (verifier is pass/fail) | **pstack** (loop has no metric mode) |
| prototype / observe-before-ask | prep `spike` route, spec "never ask what you could answer" (spec/SKILL.md:8) | small **pstack** gap (run the probe, quote the result) |
| interrogate, comment-sicko | review-diff, adversary lenses, no-slop lens | flow stronger. Its review keeps no dismissed-finding list (audit and the slop lens already have one). |
| unslop, technical-writing, reply rules | no-slop (code), shared/pr-body.md | **pstack** |
| no-comments | no-slop NS-23 / NS-15 | even |
| create- / maintain-verification-skill | shared/verification.md, start-dev-server, agent-browser | **pstack** (per-project generated verify skill with a feature map) |
| show-me-your-work (decision TSV + Attention digest) | NOTES.md Ruling/Discovered, lesson-record, loop LEARNINGS | small **pstack** gap (no evidence field, no morning digest) |
| reflect, correct, automate-me | lesson (+ --retro), claude-improver (git churn) | flow builds better, pstack mines wider |
| babysit, bugbot-triage, watch-pr | nothing after `shipped` (`Next: gh pr view --web`, next/SKILL.md:41) | **pstack** |
| shipping, autopilot-full/stack, orchestrate, orch store | none | pstack. Team, Graphite and Cursor-Projects shaped. |
| autonomous-run, pause-safely, session-pickup | loop fresh, --finish + finish-gate, router self-heal | flow stronger. pause-safely's clean exit under the Stop hooks is unstated. |
| worktree-cleanup | doctor-hygiene.js | small **pstack** gap (squash-merged worktrees are never flagged safe, doctor-hygiene.js:100) |
| why, how, recall, teach, bro | research-sweep, explorer, smoothbrain | **pstack** on design-rationale archaeology and confidence wording |
| blast-radius | adversary, qa Q1, spec "Blast radius if wrong" | flow covers most of it |
| 24 principle leaves | no-slop rubric, CLAUDE.md, mechanisms | different approach. flow encodes rules as checks. |
| setup-pstack model roles | pinned frontmatter + workflow JS | pstack (conflicts with a user rule) |
| benny automation (Slack triage→repro→fix) | issue + fix | pstack, team-process shaped |
| *(none)* | Stop-hook gates, git-guard, tamper notice, `flow tick` lying detector, PASS-<sha>, loop caps and negative control, blind re-score, lesson red-green plus adversary, stealth, route computation plus gate manifest, skills-lint / workflow-lint / doctor | **flow only** |

### 2.3 Should flow fill each pstack-only gap?

| Gap | Fill it? | Home |
|---|---|---|
| Prose rubric with evidence labels | **Yes.** It is mechanical and runs only on artifacts (PR body, docs), never per turn. | flow (no-slop) |
| Post-PR babysit + review-bot triage + PR watcher | **Yes.** It is the largest missing lifecycle phase. It must never merge or ready a PR. | flow-extras first (promote to flow if used) |
| Benchmark vetting | **Yes**, on demand only. | flow-extras, with a pointer from flow fix |
| Generated project verify skill | **Yes.** It lowers the cost of every browser `verify:`. | flow-extras (generator); flow shared/verification.md consumes it |
| Observe-before-ask probe | **Yes**, as a small step. | flow (spec question bank) |
| End-of-run Attention digest | **Yes**, generated by a script at `finish off` and loop `done`. | flow (bin/lib/finish.js, loop) |
| Wider lesson mining (reverts, PR comments, seen twice) | **Yes.** | flow (lesson --retro) |
| Hillclimb metric loop | Later. Only when a real metric task appears; adding it now is speculative. | flow (loop --metric) |
| Squash-merge-aware worktree prune | Yes, small. | flow (doctor-hygiene.js) |
| Design archaeology (why) + epistemics tiers | Tiers yes, inside research-sweep. A full `why` skill, no: it is MCP-heavy. | flow (workflows/research-sweep.js synth prompt) |
| Model-role config | **No**, unless the user changes the rule. It contradicts "pin model on every fleet call". | none |
| Personal mode from transcripts (automate-me) | Maybe, as an optional pass in claude-md audit. Low leverage. | flow-extras (claude-md) |
| Multi-PR orchestration, autopilot, orch store, benny | **No.** Team process, Graphite and Cursor-locked, and against the minimum-surface rule. | none |
| Principle library as steering vocabulary | **No.** flow turns rules into checks. Only the "Distinct from" habit is worth noting, in skill-forge. | none |

### 3. Top 8 changes to flow, ranked by leverage

All eight follow the user's rules:
- nothing prints on every turn;
- each one is a mechanism, or a small edit to an existing step;
- no new always-on surface.

1. **Prose rubric with a checker.**
   - **Files:** new `plugins/flow/skills/no-slop/references/prose-rubric.md`; a `--prose <file>` mode in `plugins/flow/skills/no-slop/scripts/slop-check`; one pointer line in `plugins/flow/skills/shared/pr-body.md`.
   - **What:** reuse smoothbrain's sentence rule (design/skills/smoothbrain/SKILL.md:29). Add the evidence label (measured / inferred / guess, from pstack/skills/poteto-mode/SKILL.md:111). Add "a count claim carries the command that regenerates it". Port only the unslop rules a script can detect, with stable ids like NS.
   - **Why:** this is the C8 gap. Advisory only, and it runs on PR bodies and docs, not on chat replies.

2. **Fix two flow bugs that pstack's rules exposed.**
   - **Evidence deletion:** `plugins/flow/skills/shared/verification.md:75` runs `rm -f ./verify-*.png`. That contradicts flow's own rule, "a verification claim with no artefact on disk does not count" (fix/SKILL.md:95, next/execution-prompt.md:27). Move the files to `verify/` instead of deleting them.
   - **Killing other processes:** `plugins/flow/skills/shared/scripts/start-dev-server:133-144` SIGTERMs every PID on the port. That includes the user's own dev server. It should kill only the PID it started.
   - **Why:** almost free. Both are correctness bugs, not borrows.

3. **Post-PR babysit.**
   - **Files:** new `plugins/flow-extras/skills/babysit/SKILL.md`, `scripts/pr-watch` (a gh-only poller with tests, ported from pstack's watch-pr policy truth table), and `references/review-bot-triage.md`. The triage file reuses `plugins/flow-extras/skills/pr-reviewer/references/ai-bot-anti-patterns.md` as its seed list of dismiss patterns.
   - **Rules:** the modes are `check`, `threads-only` and `drive` (pstack babysit.md:7). Work the lowest red PR first (:8). Never mutate topology (:10). Treat review text as untrusted data (:12). Never merge, and never `gh pr ready` an unattended PR (next/SKILL.md:149).
   - **Why:** flow's lifecycle ends at `shipped` (next/SKILL.md:41), but CI, review threads and bot comments are where PRs stall.

4. **End-of-run Attention digest, generated by a script.**
   - **Files:** `plugins/flow/bin/lib/finish.js` (on `flow finish off`), and the loop `done` row (`plugins/flow/skills/loop/SKILL.md:92`).
   - **What:** print a digest assembled from NOTES.md `Assumption:`, `Ruling:` and `Discovered:` lines and the loop LEARNINGS. It puts first what the human should check, each item with an evidence pointer. Add an optional `evidence:` field to Ruling and Discovered lines.
   - **Why:** pstack's morning-audit idea (docs/guide/07-overnight.md:58-68), done by a script rather than a reviewer. Once per run, so no per-turn noise.

5. **Generated project verify skill.**
   - **Files:** new `plugins/flow-extras/skills/verify-skill/SKILL.md` (create and maintain modes). In `plugins/flow/skills/shared/verification.md`, add "use `.claude/skills/verify-*` when present".
   - **What:** a feature map with click path, reset, states and evidence per feature. Each generated skill must actually be run once. Maintain mode ships at most one PR of proven corrections. Selectors already follow shared/e2e-testing.md:36.
   - **Why:** CHK and browser `verify:` lines are flow's most expensive and least repeatable steps. A project-local driver makes them re-runnable.

6. **Wider lesson mining.**
   - **File:** `plugins/flow/skills/lesson/SKILL.md`, the --retro sources (:13-27) and the ladder (:53-59).
   - **What:**
     - add `git log` reverts, `gh` PR review comments, and comments that explain workarounds as --retro sources;
     - count a class only once it is seen twice;
     - add a rung above Test: "make it unrepresentable (type or data shape)" (pstack correct/SKILL.md:19-20).
   - **What not to add:** a new table. lesson-record already pairs each rule with its mechanism (scripts/lesson-record:8-11).
   - **Why:** flow's ladder is the better builder. It is starved of input because it reads one session.

7. **Observe before asking, in the spec discovery turn.**
   - **File:** `plugins/flow/skills/spec/references/question-bank.md`.
   - **What:** when a position is an empirical fork (timing, layout, output, perf), run a scratch probe first and quote its result as the reasoning for the pre-answered position. If the probe cannot settle it, it stays a numbered position for the human.
   - **Why:** flow already says "never ask a question you could answer" (spec/SKILL.md:8). This extends "answer by reading" to "answer by running", and turns guesses into measured assumptions. The prep `spike` route (prep/SKILL.md:42) remains the path for bigger questions.

8. **Benchmark vetting, on demand.**
   - **Files:** new `plugins/flow-extras/skills/benchmark-checklist/SKILL.md`; one pointer line in `plugins/flow/skills/fix/feedback-loops.md:61`.
   - **What:** before reporting a number, check what limits it, warm vs cold, errors, repeated runs and range, and end-to-end relevance. The verdict is faster, slower, no difference, or inconclusive. Put one primary number in the PR body (pstack benchmark-checklist:31-34).
   - **Why:** a faked speedup passes every flow gate today, because gates check exit codes, not whether a number means anything.

**Smaller fixes worth queueing (each one or two lines):**
- **pause-safely exit path:** document it in `next/SKILL.md`. Run `flow finish off`, then make a wip commit, which stop-gate.sh may block on a red tree. This is plausible but untested.
- **Squash-merge detection** in `bin/lib/doctor-hygiene.js:100`, via `gh pr` state or patch-id.
- **Epistemics tiers** in the synth prompt of `workflows/research-sweep.js:109`.
- **Carry earlier rounds' findings** into fix rounds in `workflows/build-slices.js:226-234`.
- **A dismissed-with-reason list** in the `workflows/review-diff.js` return value, copying the slop lens's "Dismissed" section.
- **Eval scaffold identity:** scaffolds set `user.name "eval-scaffold"` in 40 files (e.g. `evals/pipeline-fix-bug/scaffold.sh:17-18`). That leaks the eval to the candidate (pstack's observer-effect rule, 09-make-it-yours.md:90).

**Where flow is already better, so nothing should be borrowed:**
- verification mechanics (C3);
- caps and anti-gaming in long runs;
- the lesson builder;
- self-tests (C10);
- the deterministic router;
- never merging unattended.

pstack's principle library, its multi-model panel and its orchestration stack would add surface without adding any check.
## Appendix B: every pstack piece, scored

Columns: rubric Layer A craft, then Layer B 0-5 (Gap, Leverage, Mechanism, Evidence, Portability, Cost). B7 Fit was added after this pass; see "Fit check".

### poteto-mode and its core playbooks

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| poteto-mode (SKILL.md) | 74/120 | 2 | 3 | 1 | 1 | 1 | 2 | MERGE | Before asking, it sorts the question: "If the answer is a fact you could observe by running something (behavior, timing, layout, output, perf, even whether an eval separates), it is not the human's to answer" (SKILL.md:2 | It is a Cursor mode (`mode: true`, `reminder:` frontmatter, SKILL.md:5-8) whose reminder fires on every new task, which is per-turn noise under the user's no-nudge rule. It wants every reply to name the principles it app | Flow already says not to ask what it can answer by reading. The new part is only answering by running.; Mostly covered. Each fix round in build-slices is already a fresh agent() call given the brief path, the current diff and the current findings. Only the earlier |
| Investigation playbook | 21/50 | 1 | 2 | 0 | 2 | 2 | 4 | SKIP | Pushback on the premise is part of the deliverable: "For 'are we sure?' answers, include your real judgment with reasons. Push back if the premise is wrong" (investigation.md:14). | B3=0: nothing runs. The playbook is four prose steps that delegate to skills outside the slice. The 'throughput checkpoint: n/a' line (investigation.md:8) is ceremony. |  |
| Bug fix playbook | 32/50 | 1 | 2 | 1 | 3 | 2 | 4 | SKIP | "Belt-and-suspenders that 'might help' is a hypothesis, not a fix. It does not ship. When evidence refutes a hypothesis, revert what it motivated" (bug-fix.md:5). The user is asked to reproduce only after the agent has d | It is weaker than flow:fix. The red-before-fix ordering is optional ('Skip it when the test would be expensive', bug-fix.md:11), and nothing proves the test bites. Flow reverts the fix and demands red (fix/SKILL.md:85). |  |
| Perf issue playbook | 33/50 | 4 | 2 | 1 | 4 | 3 | 4 | MERGE | "1. Don't do it. Stop work whose result nothing uses rather than cheapening it. 2. Do it, but don't do it again. 3. Do it less ... When an earlier mantra meets the target, stop" (perf-issue.md:8-16). The reply contract i | Measurement integrity is all prose. There is no harness, no noise rule and no N-runs rule in this file; it points to benchmark-checklist instead. 'Capture a baseline trace via the matching control skill' (perf-issue.md:5 | 3, verdict MERGE (unchanged, but only valid once B1 is 3) |
| Hillclimb playbook | 39/50 | 3 | 3 | 2 | 4 | 4 | 3 | ADAPT | The stop predicate "pairs a target with a floor on attempts so a lucky early win can't end the run" (hillclimb.md:7). The harness must be shown sensitive before it is frozen, and "make it print its error count and a coun | Every guard is prose. Nothing stops an agent from editing the frozen harness, while flow's loop cksums its verifier (loop/SKILL.md:104). The defaults assume a grok model (hillclimb.md:12). The show-me-your-work and bench |  |
| Runtime forensics playbook | 26/50 | 4 | 1 | 1 | 3 | 2 | 4 | SKIP | "Prove the mechanism before believing it. Inject instrumentation via CDP eval on the running process, or hotfix the live code without reloading" (runtime-forensics.md:7). | B2=1 because the deliverable is a diagnosis with no fix (runtime-forensics.md:3), and live leak or spin hunts are rare in flow's build/fix/review runs. The tooling is CDP and control-ui. |  |
| Trace forensics playbook | 29/50 | 4 | 1 | 1 | 3 | 4 | 4 | SKIP | "Dump the trace or heap snapshot into sqlite, one row per sample, frame, or node. Reach the queryable shape before you read" (trace-forensics.md:8). "A frame with no source mapping is not yet a diagnosis" (trace-forensic | B2=1. Profiling artifacts handed over after the fact almost never come up in flow's work. The flow:fix description explicitly excludes 'open-ended exploration or profiling with no fix target' (fix/SKILL.md:3). |  |
| Feature playbook | 26/50 | 1 | 2 | 1 | 2 | 1 | 2 | SKIP | "A dimension that genuinely does not apply (single file, no fan-out) keeps its item with `n/a: <reason>` rather than being dropped" (feature.md:7). "Code-coupled work ... goes to a single owner ... Parent-level fan-out i | The checkpoint is a todo list, not a lint. Flow computes waves and proves file disjointness mechanically (flow-lint:24). The mandatory multi-model arena and architect/interrogate depend on non-Anthropic panels (B5=1) and |  |
| Refactoring playbook | 34/50 | 2 | 2 | 1 | 3 | 4 | 4 | MERGE | "Type check and lint are not a pin" (refactoring.md:7). "Spot-check every rename against the actual files. Renames silently miss usages in strings, prose, and back-references" (refactoring.md:11). "If the diff does not l | The rules are prose with no gate. 'Reader-load delta' has no measure, so the revert test in step 7 is the agent's own judgment. | Two of the three are already in flow-deepen in a stronger form. Only the rename sweep is new. |
| Prototype playbook | 31/50 | 3 | 3 | 1 | 3 | 4 | 4 | ADAPT | "No decision means no prototype" (prototype.md:7). Behavioural forks are in scope too: "For a behavioral or timing decision, the smallest script that exercises the question" (prototype.md:9). "The observation is the test | Carried by prose alone. 'Verify on the matching surface ... via the control skill' (prototype.md:11) is Cursor-bound for the visual branch, though design:showcase already covers that branch. | Partly covered. B1=2, so MERGE into prep/spec |
| Visual parity playbook | 30/50 | 2 | 1 | 1 | 3 | 3 | 4 | SKIP | "no harness modifications, no baseline tampering, no component restructuring to make a diff pass. If the baseline looks wrong, stop and ask, don't edit it" (visual-parity.md:6). | B2=1: pixel-exact styling migrations are rare. Flow's browser-verifier already bans laundering a baseline (browser-verifier.md:111). |  |
| Authoring a skill playbook | 19/50 | 0 | 1 | 1 | 1 | 1 | 5 | SKIP | "When in doubt, delete. Keep only prose that changes a decision. Tell it to do the thing and skip the reason" (authoring-a-skill.md:10). | B5=1: it depends on "Cursor's built-in for authoring SKILL.md files" (authoring-a-skill.md:5). The validation in step 2 is a weaker version of skills-lint, which flow already runs. |  |
| Eval playbook | 38/50 | 3 | 3 | 2 | 4 | 3 | 3 | ADAPT | "No `eval`, `test`, `judge`, `experiment`, `rubric`, `score`, `compare`, `benchmark`, `candidate`, or `arena` in any directory, file, or prompt the candidate sees" (eval.md:7). "Don't ask the candidate to list which skil | The blinding is a prose checklist. A banned-word scan is trivially scriptable and is not provided. Candidates and the judge are meant to be different model families (eval.md:20-21), which does not map onto Anthropic-only |  |
| check-plan.mjs | n/a | 2 | 2 | 5 | 4 | 3 | 5 | MERGE | It fails loudly: "process.exit(problems.length ? 1 : 0)" (check-plan.mjs:185), with `${file}:${line}: message` per problem (check-plan.mjs:39). Each human/live check must name its artifact and its pass condition: "lane $ | Most of the schema is one author's template: exactly ten lanes on a swarm model (check-plan.mjs:7,141), `/loop 1h` (check-plan.mjs:20), and the review gate must contain the words screenshot, video and operator (check-pla |  |
| bootstrap.ts | n/a | 3 | 1 | 5 | 1 | 4 | 5 | SKIP | "createHash('sha256').update(readFileSync(...'package.json')).update('\0').update(readFileSync(...'bun.lock'))" (bootstrap.ts:15-21) as an install stamp, then re-exec with inherited stdio (bootstrap.ts:53-60). | B2=1: flow deliberately ships no-dependency scripts, so it has no install problem to solve. Re-exec on first run doubles the startup time and hides the install output unless the install fails. |  |
| poteto-agent | 16/50 | 1 | 1 | 1 | 0 | 2 | 2 | SKIP | "Substituting `generalPurpose` skips that read and drifts" (poteto-agent.md:3). The description warns the orchestrator off the obvious substitute. | B4=0: it produces nothing to re-read, only a pointer. `is_background: true` (poteto-agent.md:4) is Cursor frontmatter. Loading the whole mode into every delegate is the opposite of flow's minimal-brief design (next/SKILL |  |

### Long-run playbooks and PR tools

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| orchestrate (playbook) | 89/120 | 3 | 2 | 4 | 4 | 2 | 2 | MERGE | Completions are queue events, not interrupts (orchestrate.md:9). Standing orders are pasted verbatim into every spawn and every resume, and 'When you catch yourself restating an instruction, append the line before you ac | Host-locked: workers are 'Always environment: "cloud"' Cursor agents (:17), the frontier is computed from gt only (:79, store.ts:1106), the verifier must be 'a different model family' (:17), and restarts are described as | The different-model-family verifier is at orchestrate.md:87, and it is conditional. It applies only to 'units whose verification is expensive, judgment-laden, o |
| multi-phase-plan (playbook) | 70/120 | 2 | 2 | 3 | 3 | 1 | 1 | SKIP | The tick prompt is silent unless something changed: 'post a short status message... only when the audit found a tracked change that no earlier status message reported... If the audit found none, end the turn with no repl | Ten live lanes on 'grok-4.7-xhigh-fast' (:13) per PR, control-ui/control-cli from cursor-team-kit (:15), and cloud VMs per lane (:71). It needs a non-Anthropic model panel and costs a great deal on every PR. The verifica |  |
| autopilot-full (playbook) | 67/120 | 3 | 2 | 2 | 3 | 1 | 1 | SKIP | Merge prep checks 'that git merge-tree of the head against current trunk is clean' and 'that no path in git diff --name-only $(git merge-base HEAD origin/main) origin/main is a path the PR changes or a path that decides  | It is built on Cursor cloud agents (:6), the swarm skill, Bugbot and Origin, and it lets agents merge. That conflicts with flow's stance that an unattended PR stays draft (next/SKILL.md:117). Mechanism is prose apart fro |  |
| autopilot-stack (playbook) | 66/120 | 3 | 1 | 2 | 3 | 1 | 1 | SKIP | 'Single writer on topology, parallel writers on builds. Owners push only their own branches and report the tip, current base, and intended parent. The root is the only topology writer' (autopilot-stack.md:10). It applies | Stacked PR chains through cloud owners are a team-at-scale process. Base-branch stacks are a workflow the user does not run in flow. The forge-resolution paragraph is copied verbatim from four other playbooks (:5). |  |
| autonomous-run (playbook) | 34/50 | 1 | 2 | 1 | 2 | 4 | 4 | SKIP | 'Each iteration makes the smallest change the evidence justifies... commits if it advanced, discards changes that didn't help' (autonomous-run.md:7). 'never relax the predicate to declare victory' (:11). | The model decides when the predicate is met, which is exactly what flow:loop refuses (loop/SKILL.md:102). 'A plateau is not a stop, so keep going' (:11) has no cap, which conflicts with flow's 'Never raise a cap to get p |  |
| babysit (playbook) | 89/120 | 4 | 3 | 4 | 3 | 3 | 3 | ADAPT | CI triage: 'Flake or infrastructure earns one fresh build, never a job retry. One retry only. An identical second failure means it was never flake... A failure in code the diff never touches means a stale base, so check  | About 40% of the text is Origin-forge branching (:7, :12-20) that the user does not have. It depends on /loop dynamic mode and the bun watch-pr binary. The Bugbot-specific pass counting (github.ts:333-347) keys on Cursor |  |
| shipping (playbook) | 78/120 | 4 | 1 | 2 | 3 | 2 | 3 | SKIP | 'Record the verdict head SHA, base SHA, and stable git patch-id... A rebase or base retarget rewrites SHAs and can silently invalidate a verdict without touching a check' (shipping.md:9). 'A verified PR sitting above an  | Each PR gets its own verifier as a Cursor cloud agent with control-ui (:7). The merge mechanics are prose, and no script computes the patch-id comparison. Flow never merges; the user lands PRs. |  |
| session-pickup (playbook) | 31/50 | 1 | 2 | 1 | 1 | 3 | 5 | SKIP | It does not glob across ~/.cursor/projects/*/ because 'that crosses workspace boundaries and reads private chats from unrelated projects' (session-pickup.md:5). It parses a long transcript in a subagent and keeps only th | Prose only, with Cursor transcript paths. flow does this better with a router that never needs a transcript (next/SKILL.md:12, :139: 'A plan you remember from before a /clear is a rumor; the disk is the state'). |  |
| pause-safely (playbook) | 32/50 | 2 | 2 | 1 | 3 | 5 | 5 | MERGE | 'This is explicit only. On "keep going", "going to bed, keep going", or "don't stop", do not pause' (pause-safely.md:3). 'Take no irreversible action to pause. No PR and no push unless you already had one out' (:6). The  | No mechanism. The resume note duplicates what flow's router already derives from disk. | partial, and more than stated: flow/skills/next/SKILL.md:97-108 (--finish) together with plugins/flow/hooks/finish-gate.sh already turn the user's 'keep going, ; MERGE still holds, but the paragraph is not the whole job. It must also say how the pause gets past flow's two Stop hooks. First, if FINISH.md is armed, the pau |
| worktree-cleanup (playbook) + worktree-audit.sh | 37/50 | 2 | 2 | 4 | 3 | 3 | 5 | MERGE | 'Squash-merged branches are not ancestors of main, so PR state is the real signal; merge-base only catches fast-forward/rebase merges' (worktree-audit.sh:40-41). flow's doctor-hygiene.js:101 has exactly that blind spot.  | Bug: worktree-audit.sh:77 buckets any branch with a PR as safe ('[ "$pr" != "-" ]'), including a CLOSED-unmerged PR with unpushed commits ahead. Linux breaks on stat -f and date -r. The transcript scan reads ~/.cursor/pr | The ancestry test is at doctor-hygiene.js:100. Its effect is not an 'unmerged' report. A squash-merged clean worktree just never gets the 'merged and clean ...  |
| opening-a-pr (playbook) | 72/120 | 2 | 2 | 1 | 1 | 3 | 4 | MERGE | '## Scope always names what the PR covers and what it deliberately leaves out' (opening-a-pr.md:19). 'If the body would make the squash commit longer than about 40 lines, cut the body' (:13). 'Do not paste full SHAs, swa | 'Open every PR ready, never as a draft' (:32) is the opposite of flow's rule that a PR stays draft until verified (fix/SKILL.md:98, next/SKILL.md:149), and flow's rule is safer. Mechanism is prose only. The forge paragra |  |
| bugbot-triage (reference) | 88/120 | 4 | 3 | 2 | 3 | 4 | 4 | ADOPT | 'When in doubt, ask. Skipping a noisy code-quality comment is cheap; skipping a real data or security bug is not' (bugbot-triage.md:13). The confidence ladder: 'Use strong only when the pattern is narrow, repeatedly veri | It is prose and pattern data, with no script. It only matters if a review bot comments. Some patterns are product-specific to Cursor's UI work. | There is still no triage of incoming comments, so B1=4 and ADOPT hold. But the row missed flow-extras/skills/pr-reviewer/references/ai-bot-anti-patterns.md, whi |
| orch CLI (scripts/orch/orch.ts + store.ts) - mechanism | n/a | 3 | 1 | 5 | 5 | 2 | 3 | SKIP | 'ledger check' returns NOT-VERIFIED with exit 2 when no row matches the current PR and SHA (store.ts:1358-1371), so a new head voids verification mechanically. The status 'changed:' line diffs against a summary JSON embe | The frontier shells out to 'gt log short' and 'gt info' only (store.ts:1075, :1109) and keeps a hard-coded list of Graphite status strings (:970-994) that will rot. It needs bun and commander (orch.ts:3, :20-26). It only |  |
| watch-pr (scripts/watch-pr: policy.ts, github.ts, cli.ts) - mechanism | n/a | 4 | 3 | 5 | 4 | 3 | 4 | ADAPT | Distinct exit codes let a /loop or Monitor wake act on the class without parsing text (policy.ts:311-336). Tier-major ordering: 'scans stacks tier-major so an upstack conflict outranks frontier CI' (policy.test.ts:154, p | It needs bun plus commander through bootstrap.ts (watch-pr:2-5), while flow's CLI is node. The queued-stack mode assumes stacks. '--status-only' always exits 0 (cli.ts:129), so check mode cannot gate on its exit code. Th |  |

### Understanding skills

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| why | 95/120. | 4 | 3 | 2 | 4 | 3 | 2 | ADAPT | Gap 4: no flow skill asks 'why does this exist' before changing it; the closest is fix/SKILL.md:55 ('ten lines you want verbatim'). Evidence 4: synthesizer-prompt.md:101 'Bulleted list of what was actually searched, so t | Cost 2: seven investigators plus a synthesizer every time, with skipping allowed only on 'explicit, written justification' (why/SKILL.md:116) and inline answers 'only after confirming all seven available category searche | databricks.md:7-8 holds templated placeholders, not one company's tables. B5 3 still stands on the Cursor mcps/ discovery and the MCP-heavy source set, but drop; Also list research-sweep's existing verification layer. Every claim is tagged PRIMARY/SECONDARY, and a Check phase refetches the 4 most load-bearing claims and  |
| blast-radius | 92/120. | 2 | 3 | 2 | 4 | 3 | 4 | MERGE | Evidence 4: blast-radius/SKILL.md:37 'Prove the one fact. Write a script or test that runs the real code, run it, and paste what happened', and :46 hands back 'The cheapest test or repro that catches the real bug, includ | Gap 2: flow's adversary already holds the load-bearing-assumption attack and executed-receipt rule (adversary.md:33, :45); what is new is the where-grep-stops list, the five-rung ladder, and a separate Cleared list. Mech | Also covered by: qa's pre-assessment question 1 'Blast radius — If this breaks, what else breaks? Map the dependency chain', qa's code-analysis agent reading ca |
| how | 80/120. | 1 | 2 | 1 | 2 | 2 | 3 | SKIP | explorer-prompt.md:30 'I couldn't determine how X connects to Y is better than making something up' and the 'Open Questions' section (:51) give the explainer an honest gap list; flow's explorer has dead_ends (explorer.md | Gap 1 because flow's explorer agent plus smoothbrain already split reading from explaining, and flow's explorer is stricter: 'Every line carries a path:line receipt you opened this run. No receipt, no line' (explorer.md: |  |
| recall | 83/120. | 3 | 1 | 1 | 3 | 3 | 3 | SKIP | recall/SKILL.md:18 'State the scope back. Never quietly turn "all" into "recent N".' :19 'The raw transcripts stay in the subagents. The main thread gets only their findings.' :21 checks surfaced PRs and branches against | Leverage 1: flow keeps position on disk (next/SKILL.md:12, PROGRESS.md), so rebuilding it from transcripts rarely changes how a build, fix or review turns out; it helps the human more than the run. Mechanism 1: prose, no |  |
| teach | 35/50 | 1 | 1 | 0 | 1 | 3 | 2 | SKIP | teach/SKILL.md:17 'For anything with three or more moving parts, do not draw one diagram with all of them at once. Draw a short series instead, where each diagram redraws the last and adds a single part'. Smoothbrain's s | Gap 1: smoothbrain already does big-picture-first in project nouns, step by step. Mechanism 0: all prose; smoothbrain at least has scripts/check.mjs (smoothbrain/SKILL.md:60). Cost 2: every teach runs how and why underne | That misreads teach:14. It keeps why narrow by default and allows one sub-skill for a small change, so cost is closer to 3. The SKIP verdict is unchanged becaus; 2. Smoothbrain builds an Artifact HTML page with a still step-through stage. teach is a paced chat explanation that lets the person respond and that blends in w |
| bro | 14/50 | 2 | 1 | 0 | 0 | 5 | 5 | SKIP | Portability 5 and cost 5: bro/SKILL.md:7 'Restate your last message. Stop using jargon and speak coherently.' Nothing host-specific, nothing runs unless typed, no per-turn output. | Mechanism 0: one sentence of prose, no check. Evidence 0: produces nothing a reviewer can re-read beyond the reply. Leverage 1: does not change the outcome of any build, fix or review. The user can just type the sentence |  |

### Design and build skills

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| architect | 89/120 | 3 | 3 | 2 | 3 | 2 | 2 | MERGE | The red flags are written for an agent as the reader. design-red-flags.md:53-57 says 'Two or more places list the same items... An agent that sees one list updates only that one. Keep one list and derive the others... ma | It is tied to Cursor and to a model panel: SKILL.md:33 says 'use claude-opus-5-5-xhigh and grok-4.7-xhigh-fast' and reads pstack-models.mdc. Every phase points to another pstack skill, so it does not work alone. Phase C  |  |
| arena | 77/120 | 3 | 2 | 2 | 3 | 3 | 1 | SKIP | Only the picker sees the rubric: SKILL.md:27 says 'The rubric is the picker's tool in Phase D. Candidates only see the task.' The spread of results is read as a signal: SKILL.md:61 says 'When N candidates wildly diverge, | The cross-family judge needs Grok or another non-Anthropic model (SKILL.md:41); Claude Code only offers Claude tiers. It costs N full artifacts plus a judge plus the parent reading all of them (B6=1). Each step is prose  |  |
| swarm | 71/120 | 1 | 2 | 2 | 3 | 2 | 3 | SKIP | The race rule is declared before spawning: SKILL.md:23 says 'declare first pass, rank all, or best-of before spawning.' Results without provenance are rejected: SKILL.md:40 says 'Drop a result that does not record the SH | It is tied to Cursor: SKILL.md:30 uses subagent_type generalPurpose and environment 'cloud', and SKILL.md:25 defaults to grok-4.7. It adds nothing that flow's Workflow scripts with JSON schemas do not already do better.  |  |
| figure-it-out | 73/120 | 1 | 2 | 1 | 3 | 2 | 3 | SKIP | SKILL.md:29 says 'Build the verification harness before the work, with the baseline captured from the pre-change state, so the check reads as "old value vs new value".' SKILL.md:41 says 'When something passes too easily, | The skill is mostly prose that defers to other skills: SKILL.md:13 says to read poteto-mode first, and SKILL.md:19-51 points to about 8 principle skills. 'Rigor is gates and artifacts' (SKILL.md:21) is stated, but nothin |  |
| tdd | 75/120 | 0 | 1 | 1 | 3 | 5 | 5 | SKIP | SKILL.md:26 gives a usable definition of a bad test: 'one that mostly tests mocks, encodes current implementation details, depends on timing... or would be deleted immediately after proving the fix.' The final response m | It gives an exit flow deliberately closes. SKILL.md:11 says 'skip adding a new test and use the closest useful verification instead', while fix/SKILL.md:136 says 'NEVER fix before the reproduction is a committed test tha |  |
| benchmark-checklist | 99/120 | 5 | 3 | 2 | 4 | 4 | 5 | ADOPT | SKILL.md:23 bounds the possible gain: 'Removing a piece that takes 10% of the run can make the run at most about 11% faster. A result past a limit means the run measured something other than the work.' SKILL.md:27 asks w | It is a prose checklist with no script, so nothing forces five interleaved runs or an error count. Links to ../principle-explain-the-number and to the Perf issue and Hillclimb playbooks (SKILL.md:9,38-39) would be dead l |  |
| show-me-your-work | 91/120 | 2 | 3 | 3 | 5 | 3 | 3 | MERGE | Every row needs a pointer as evidence: SKILL.md:21 says 'commit SHA, PR number, file:line, or an artifact... Never a paragraph.' The log is corrected, not rewritten: SKILL.md:63 says 'Correct the log, not the story. The  | The cross-model review (SKILL.md:67) needs a non-Claude family. The transcript path is Cursor's agent-transcripts/ (SKILL.md:57). The 'Attention' section at the end of every reply works against the user's no-noise rule u | Partial. The review missed plugins/flow/scripts/lesson-record. It is a script that writes Ruling lines in a fixed format ('- Ruling: <what> — <mechanism> — <cos |
| create-verification-skill | 99/120 | 4 | 4 | 3 | 4 | 4 | 4 | ADOPT | Cleanup must not destroy the evidence: SKILL.md:31 says 'Cleanup removes instances and scratch state, never the evidence... Never kill by process name; kill what you started.' SKILL.md:40 says 'A cleanup that eats the pr | The paths are hard-coded to .cursor/skills/verify-<app>/ (SKILL.md:9,25). The 'Prove' step is a rule the model must follow; no script checks that the generated sections exist. It assumes a drivable surface; for a pure li | Flow already has the rule that evidence must survive. fix/SKILL.md:95 says 'a verification claim with no artefact on disk does not count'. next/SKILL.md:65 and  |
| maintain-verification-skill | 86/120 | 5 | 2 | 2 | 4 | 4 | 3 | MERGE | SKILL.md:21 separates doc drift from product bugs: 'a behavior the map describes that the app no longer does is either doc drift (fix the map) or a product regression (report it, don't paper over it in docs).' SKILL.md:3 | It is only useful once create-verification-skill exists. One serial live pass over every feature is slow. Most of the method sits in one dense paragraph (SKILL.md:33) with no checklist or script. Its target path is .curs | No rubric verdict fits these scores. Either re-score B1 to 3, on the condition that the verify-skill generator is adopted (the gap is then small), and keep MERG |

### Review and writing skills

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| interrogate | 87/120. | 2 | 3 | 1 | 2 | 2 | 2 | MERGE | lead-judgment.md:58 'The "Dismissed" section is not busywork. It's a trust mechanism. Showing the user what you rejected and why lets them override your judgment'. flow's review-diff.js:118-121 only logs a count of dropp | The core idea, adversarial signal from model diversity (SKILL.md:9), rests on a non-Anthropic model panel (SKILL.md:41 `grok-4.7-xhigh-fast`) and a Cursor rules file (SKILL.md:36), so it does not port to a Claude-only se | Flow already has this pattern in two places. Only review-diff.js lacks it. Steal 3, and lands_in should reuse the existing shape: copy audit's backlog or the sl |
| no-comments | 32/50 | 3 | 2 | 1 | 2 | 2 | 3 | MERGE | Line 23: 'Constraint comments say `do not remove` ... Offer the cheapest in-scope type, runtime, test, or CI lint. Wait for interactive approval. Unattended and eval require caller pre-approval. If approved, encode then  | Prose only. The comment-deletion pass mostly duplicates NS-23 and the developer block. Line 20 cannot be read in one pass. It routes through skills flow lacks (/how, /why, /architect, principle-fix-root-causes at line 22 | rubric.md:34 (NS-23), :36 (NS-15), :28 (NS-09); developer-block.md:43 ('Comments: default to none'). The claims are right but every line number is out of range. |
| Comment Sicko (agent) | 33/50 | 2 | 2 | 1 | 2 | 3 | 3 | MERGE | Line 17 separates comments explaining a vendor's quirk from comments explaining our own code: 'Surprises in our own code are meat. Kill them and mark the exact symbol `MUST KILL` for rename, extract, type, or rearchitect | Line 22 ('When I am not sure a keep clause applies, the comment dies') contradicts flow's deliberate ruling at no-slop/SKILL.md:69, which keeps one-line WHY comments. The persona line (line 10) is per-run noise against t | rubric.md:34 (NS-23) and rubric.md:60 ('## F. What is not slop (do not flag)') |
| unslop | 78/120. | 4 | 3 | 1 | 1 | 4 | 4 | ADAPT | Line 61: 'if the sentence could appear unchanged in another project's docs, it says nothing about this one. Cut it.' This is a one-line test that catches generic filler. Line 67 (rule 33) targets the clipped agent style: | Prose only, with no checker, though about a third of the rows are regexable. The absolute em-dash and parenthesis ban (line 36: 'no parentheses, no en dashes') is house style, not a slop tell. The description fails as a  | NS-07 is at rubric.md:37 and NS-04 at rubric.md:47. Flow also has a scoped prose rule that covers unslop rules 28, 29 and 33 (one idea per sentence, active voic |
| technical-writing | 85/120. | 4 | 3 | 1 | 2 | 4 | 4 | ADAPT | Line 96: 'Make every count or tree claim true at the commit that lands it, and include the command that regenerates it.' This turns a prose claim into a re-runnable artifact (B4) and fits flow's evidence culture (docs/re | No mechanism: it relies entirely on the model reading 106 lines and obeying. Lines 30-47 restate public Diátaxis material Claude largely knows. Line 96 ('Indent code snippets with tabs') is Cursor-repo house style. Model |  |
| typescript-best-practices | 87/120. | 3 | 2 | 1 | 1 | 3 | 3 | MERGE | patterns.md:94 gives a concrete rule for when to strengthen a type: 'Strengthen when the loose type forces a lie at a use site. The tells are `!`, `arr[0] as T`, and a "should never happen" throw'. This is greppable, and | Language-specific in a language-agnostic plugin. Prose only, though the useful rows are existing lint rules (@typescript-eslint/switch-exhaustiveness-check, no-non-null-assertion, consistent-type-assertions) that a scrip | rubric.md:27 (NS-22) |

### Meta skills and automations

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| reflect | 88/120 | 2 | 3 | 2 | 3 | 3 | 3 | MERGE | The synthesizer's filter is the real value. It accepts a learning only if it routes to a skill the session actually used: "only accept findings that route to a skill, tool, or MCP the parent actually invoked... If neithe | Four high-reasoning subagents per run, one of them a Grok model (SKILL.md:37-39), is a model panel flow cannot use. Every lesson lands as skill prose. Its own step 4 admits mechanisms are better and pushes them to a vagu |  |
| correct | 89/120 | 2 | 3 | 3 | 3 | 5 | 4 | MERGE | There is a rung above flow's ladder: "Eliminate it with architecture. Give each piece of state one owner and each task one supported way. Hide internals so the wrong import fails. Replace hand-synced lists with one sourc | It is prose only, with no sites script, no recorder and no adversary pass. Flow's lesson is stronger on mechanism: lesson-sites, lesson-record and the adversary step (lesson/SKILL.md:41-85). The exception rule ("Exceptio | It does have a per-correction entry. Remove this criticism; the real gap is that the per-correction path has no recorder or adversary step.; 1 |
| automate-me | 80/120 | 3 | 2 | 1 | 2 | 3 | 3 | MERGE | Update mode is cheap and incremental: "Step 1 mines only history since the skill was last edited (`git log -1 --format=%cI <path>`)" (:23). It requires consensus across slices: "Patterns seen in 2+ slices are high-confid | The output is more prose that nothing enforces, which runs against the user's 'mechanism over prose' rule. Its own evaluation admits "A `create-skill`-style test/iterate benchmark loop isn't useful here. Vibe-check with  |  |
| setup-pstack | 78/120 | 2 | 1 | 3 | 2 | 1 | 4 | SKIP | It never writes an unverified value: "Never write a real slug you have not confirmed is available" (:14), re-checked in the validate step (:35). Re-runs clean up after themselves: "A line whose role is not in step 5... i | It is host-locked to Cursor's .mdc rules and to a mixed Grok/Opus panel (:48-65). Claude Code already carries model and effort in agent frontmatter, and the user's rule pins models per call, so a per-role override file a |  |
| poteto-help | 88/120 | 3 | 1 | 1 | 1 | 2 | 4 | SKIP | A help question does not start the work: "For a help question, don't start the work. The user asked how, and a pstack run spends real tokens, so let them send the prompt" (:9). The map defers to its targets: "Read the fi | It does not change a build, fix or review outcome. It routes a newcomer around a 30-skill catalog that flow deliberately avoids with a two-door surface (flow/README.md:9). The content is pstack-specific, and much of it i |  |
| make-bot-ui | 83/120 | 5 | 1 | 2 | 2 | 0 | 4 | SKIP | It checks the endpoint before announcing it: "Before you tell the user that the UI is live, probe once with a harmless payload. Use an action that the prompt ignores" (:70-71). It keeps the secret out of the browser and  | It is entirely Cursor-locked: `update_state` routines (:15), `SendToUser type: secret-request` (:44), Grok Bot wake turns (:107). It has nothing to do with flow's build, fix or review loop. Without the Cursor runtime the |  |
| benny: triage-issue-reports | 93/120 | 3 | 2 | 3 | 3 | 1 | 3 | MERGE | Graded dedupe with an action per grade: "Confident duplicate... Possibly related... Weak resemblance... No match" (:160-163), and "For a possible match, link it in the verdict as uncertain and create nothing" (:167). "A  | It needs Slack channels, triage identities, a tracker adapter and Cursor automations (configuration.example.yaml:7-46), which is team infrastructure a single-user flow does not have. Its safety rules are long, model-enfo |  |
| benny: reproduce-and-fix-issues | 97/120 | 3 | 3 | 3 | 4 | 2 | 2 | ADAPT | The repro definition: "1. Name the correct final state. 2. Name the broken final state. 3. Reach the point where they diverge... 5. Reset enough state to make the second attempt independent. 6. Repeat" (:171-179). The me | Slack coordinate freezing, operations threads, status emoji and marker waits (:34-124) are team-bot machinery with no flow analogue. Everything runs as model prose, with no script checking that two recordings exist. The  | control-adapter.md:141-151 (environment translation), :68 (arranging a precondition is not permission to inject the symptom), :83 (inspection is read-only), :15; flow's fix does have a UI path: frontend category reproduces by browser at the standard tier, and the feedback-loops ladder includes a headless browser script t |
| benny: setup-benny + pack bootstrap (README, FOR_AGENTS.md, templates) | 84/120 | 4 | 1 | 3 | 3 | 0 | 2 | SKIP | User-owned files live outside the pack: "Keep user-owned configuration, feature maps, and routing maps outside the destination. Never overwrite them" (:28) and "Pack refreshes may update source-managed files after confli | It is entirely Cursor Automations, Slack and project-plugin plumbing ("Never build or open a Cursor protocol deep link", :246). It is a team process with no flow job to do, and FOR_AGENTS.md repeats setup-benny almost li |  |

### The 24 principle skills

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| principle-test-behavior-not-implementation | 45/50 | 2 | 3 | 2 | 2 | 5 | 5 | MERGE | The undefined test is a single decision rule a lens can apply per test: 'ask whether it would still pass if every function it imports returned `undefined`' (line 11). Two shapes flow lacks: 'Constant pin ... `expect(LIMI | Prose only; nothing runs the undefined check (it could be a stub-imports mutation run). Jest matcher vocabulary; flow's users write pytest too. | plugins/flow/agents/adversary.md:35 (gaming lens). The file is only 70 lines, so :73 does not exist. The coverage claim and the MERGE verdict still hold. |
| principle-build-the-lever | 39/50 | 3 | 4 | 2 | 4 | 5 | 4 | ADAPT | 'A deterministic lever beats fan-out. If the tool can process every unit in one pass, run it yourself. Don't fan out delegates to hand-apply what a script can do.' (line 16) is a real gap in ultracode, whose fleet test ( | Pure prose; no check that a lever exists. 'Apply to any non-trivial work' (description) risks scripts for two-edit changes, against the user's minimum-code rule. |  |
| principle-attack-the-premise | 36/50 | 3 | 3 | 1 | 3 | 5 | 5 | MERGE | 'The premise is the one sentence that every failed fix assumed.' (line 14) and 'Do not start the next fix before the premise is written down' (line 20) turn a vague 'step back' into an artifact. 'If the census is even ac | Mechanism 1: prose; the census-as-script is asked for but nothing checks it. Over-specialised to actor imbalance (line 17 rotate/randomise roles). |  |
| principle-explain-the-number | 42/50 | 2 | 3 | 1 | 3 | 5 | 5 | MERGE | 'A run that went wrong still prints a plausible number' (line 11) is exactly the user's recorded failure (memory: usage limit zeroes later runs). 'Ask "why not double?" ... A guess from reading the code is not a limiter. | No mechanism; perf side depends on pstack's benchmark-checklist. Eval half largely duplicates agent-evals Decision 3. |  |
| principle-make-operations-idempotent | 30/50 | 2 | 2 | 1 | 1 | 5 | 5 | MERGE | 'What happens if the previous run crashed at every possible point?' (line 21) and 'If any answer is "it depends on what state was left behind," the operation needs a reconciliation step' (line 24). | Prose; evidence 1 because it produces no artifact. Patterns are standard. | plugins/flow/agents/adversary.md:33 (correctness lens, whose edge inputs are 'empty, boundary, unicode, concurrent-ish sequences'). Rerun and crash-halfway are  |
| principle-model-the-domain | 34/50 | 2 | 2 | 0 | 1 | 5 | 5 | MERGE | 'Execution order is not ownership.' (line 19) — names temporal decomposition. Balance line 24 keeps it compatible with no-slop's Rule of Three. | Mechanism 0: nothing checks it. Overlaps foundational-thinking and type-system-discipline. |  |
| principle-type-system-discipline | 38/50 | 2 | 2 | 1 | 1 | 5 | 4 | MERGE | Test: 'Can I write a comment explaining when this combination of fields is valid? If yes, the type is too loose.' (line 26). Example `{ completed: boolean; completedAt?: Date }` (line 15) is a concrete, recognisable smel | Language survey bloat (lines 15-20); prose only. |  |
| principle-exhaust-the-design-space | 30/50 | 2 | 2 | 0 | 2 | 5 | 3 | MERGE | 'A second flavor of the first shape does not count.' (line 11) — sharpens design.md's 'rejected <option>' field, which today can be a strawman. | Prototyping 2-3 builds is expensive; no mechanism or comparison artifact. |  |
| principle-encode-lessons-in-structure | 35/50 | 1 | 3 | 1 | 1 | 4 | 5 | SKIP | 'agents copy whatever the surrounding code already does and a weaker guard becomes the next template' (line 19), with an order flow's ladder lacks at the top: unrepresentable state, then lint/banned API, then canonical h | Prose with no scripts; 'brain note' layer (line 25) depends on pstack's memory skills. | lesson/SKILL.md:9 ('A sentence in CLAUDE.md is a request; a test, hook or script is enforcement'), :53-59 (rung ladder table), :42 (lesson-sites), :80 (lesson-r |
| principle-fix-root-causes | 29/50 | 0 | 2 | 0 | 1 | 5 | 5 | SKIP | 'When something "fails after restart," suspect stale persistent state first: config files, caches, lock files' (line 23). | Gap 0 because /flow:fix enforces every bullet with commands and exit codes; this is the prose version. |  |
| principle-prove-it-works | 27/50 | 0 | 2 | 0 | 2 | 5 | 5 | SKIP | Line 16's observation-method suspicion is a real debugging move. | Flow already mechanises this with a dedicated agent and Stop gates; pstack has only prose here. |  |
| principle-boundary-discipline | 27/50 | 1 | 2 | 0 | 1 | 5 | 5 | SKIP | 'Do not re-export transport, storage, framework, or wire types through the public surface' (line 23). | Mostly what the vendor text in no-slop already says. |  |
| principle-laziness-protocol | 27/50 | 1 | 2 | 0 | 0 | 5 | 5 | SKIP | 'If a task asks you to pass a new signal through types, schemas, pipelines ... stop and look for a more direct path' (line 15). | Evidence 0: produces nothing checkable. |  |
| principle-minimize-reader-load | 32/50 | 1 | 2 | 0 | 1 | 5 | 5 | SKIP | 'Can a new reader answer "where does X come from?" and "what can change X?" in under 30 seconds?' (line 23). | flow-deepen already has the same theory plus grep detectors. |  |
| principle-separate-before-serializing-shared-state | 35/50 | 1 | 1 | 0 | 1 | 5 | 5 | SKIP | 'Two workers writing their own `lastX` field into one `state.json` is still shared mutation. `indexer-state.json` + `metrics-state.json` is not.' (line 15). 'Treat "we need a lock" as a design smell' (line 16). | Agent-level half fully covered by flow; code-level half rarely matters to flow's users. |  |
| principle-sequence-verifiable-units | 27/50 | 0 | 2 | 0 | 2 | 5 | 5 | SKIP | 'Rebase onto clean trunk first so every check measures against the real baseline' (line 13). | Flow enforces it with tick/Stop hooks; this is prose. |  |
| principle-guard-the-context-window | 17/50 | 0 | 1 | 0 | 0 | 5 | 5 | SKIP | 'Keep frequently used content inline ... not in separate files that cost a read each time' (line 15) is a fair counterweight to progressive disclosure. | No knowledge delta. |  |
| principle-never-block-on-the-human | 22/50 | 1 | 1 | 0 | 0 | 3 | 5 | SKIP | 'Product direction comes from the human. Execution should not block.' (line 20). | Conflicts with the user's global rule 'Surface assumptions. When multiple interpretations exist, ask' (~/.claude/CLAUDE.md); portability 3 for that reason. |  |
| principle-migrate-callers-then-delete-legacy-apis | 26/50 | 1 | 2 | 0 | 1 | 5 | 5 | SKIP | 'delete tests that only protect pre-refactor implementation details' (line 15). | Covered by a mechanised NS row. |  |
| principle-outcome-oriented-execution | 22/50 | 1 | 1 | 0 | 0 | 4 | 5 | SKIP | 'Declare where temporary breakage is acceptable' (line 19). | Cuts against flow's green-per-task model; no mechanism. |  |
| principle-subtract-before-you-add | 20/50 | 1 | 1 | 0 | 0 | 5 | 5 | SKIP | 'When a reference has no novel content, delete it rather than leaving a stub' (line 21). | No knowledge delta over the user's rules. |  |
| principle-foundational-thinking | 21/50 | 2 | 1 | 0 | 0 | 5 | 5 | SKIP | 'Ask "does every subsequent phase benefit from this existing?"' (line 17) as the scaffold test. | Duplicates model-the-domain, separate-before-serializing and subtract-before-you-add. |  |
| principle-experience-first | 18/50 | 2 | 1 | 0 | 0 | 5 | 5 | SKIP | 'The engineer who maintains the code next is a user too' (line 17). | No knowledge delta. |  |
| principle-redesign-from-first-principles | 16/50 | 1 | 1 | 0 | 0 | 5 | 5 | SKIP | 'Propagate the change through every reference: types, docs, examples, rationale sections' (line 13). | Prose only; can justify big rewrites against the user's surgical-changes rule. |  |
| principle library mechanism (24 leaves + inline index in poteto-mode) | n/a | 3 | 2 | 1 | 2 | 4 | 3 | SKIP | 'A principle citation with no decision behind it is the tell that it name-dropped instead of applying' (docs/guide/08-principles.md:27); 'Cite only principles whose leaf SKILL.md you read this session' (poteto-mode SKILL | poteto-mode SKILL.md:15 makes every reply name its principles — per-turn output the user's no-nudge-noise rule forbids. Nothing checks the citation or the read. 24 extra skill dirs, most of which (per rows above) restate | MERGE. With B1=3, B2=2 and B6=3, no SKIP condition in the rubric is met (B1<=1, B2<=1, or B6<=1 with B2<4). B1 is in 2-3 and the new pieces the row keeps are sm; Only 3 of the 24 leaves have such a line (build-the-lever:23, attack-the-premise:23, explain-the-number:23). The overlap the reviewer found elsewhere (foundatio |

### Ideas taught only in the guide

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Prompt anatomy (goal, done check, proof, known facts, constraints; leave out the how and your theory) | 31/50 | 3 | 2 | 0 | 0 | 5 | 5 | MERGE | 'A stated guess narrows the search to wherever you pointed. Let the agent restate the problem before you share your hunch.' (02:59). That is a real anchoring failure mode. Also the 60k-row example prompt carrying all fiv | Prose aimed at the human, with no mechanism (B3=0, because nothing checks a prompt). It partly restates flow spec's intake. Its value is documentation, not behaviour. |  |
| Restate the issue before touching code | 36/50 | 3 | 3 | 1 | 2 | 5 | 5 | MERGE | 'A misreading shows up in the restatement, before any code exists. Correct it there, and it costs you one message instead of one wrong fix.' (02:67) | Unconditional, it would add a stop to every fix. It needs a trigger: input that is a thread or prose, with no trace and no failing command. |  |
| Overnight contract and loop iteration shape | 38/50 | 1 | 3 | 1 | 2 | 3 | 4 | SKIP | 'The escape hatch lets it stop at a genuine dead end and write up why, which beats eight hours of creative goal reinterpretation.' (07:36) and 'a duration is not a finish condition' (07:118). | The finish condition is a sentence the model judges; flow's is a command the harness runs. It is tied to Cursor's /loop (07:35) and Cursor Projects (07:94). |  |
| Earn trust before the loop (four preconditions) | 33/50 | 2 | 2 | 1 | 1 | 5 | 5 | SKIP | It frames autonomy as something earned in stages: watched session first, unattended second. | Prose with no gate (B3=1). Flow already maps 'watched first' onto the session vs fresh shapes. | MERGE. The rubric allows SKIP only for B1<=1, or B2<=1, or B6<=1 with B2<4, and none of these holds at B1=2, B2=2, B6=5. B1 of 2-3 with a small new piece is MER |
| Decision log plus morning audit with an Attention section | 40/50 | 3 | 3 | 2 | 4 | 3 | 4 | ADAPT | 'Each row records the time, phase, decision, reason, an evidence pointer, and the result, in a TSV' (07:60). It is structured and re-readable (B4=4), and 'Read that section first, then the log rows it points at' (07:68)  | The 'different model family' (07:68) does not port; a fresh adversary on Sonnet or Opus is the flow equivalent. A TSV duplicates NOTES.md Assumptions and Rulings, so flow should rank the existing trail rather than add a  |  |
| Plan through code: prototypes settle open questions; don't adversarially review an abstract plan | 39/50 | 3 | 3 | 1 | 2 | 5 | 4 | ADAPT | 'Point adversarial review at a plan with no code behind it and the reviewers invent theoretical risks and edge cases that will never happen. Let prototypes settle the questions, then review what got built.' (04:89). This | Taken absolutely, it would drop pre-build review of irreversibles (migrations, public contracts), which flow's spec treats as a route driver (plugins/flow/skills/spec/SKILL.md:33). Prototyping UI is cheap, but prototypin |  |
| Pin behaviour before structure moves; parity 'bugs included' | 41/50 | 4 | 3 | 3 | 4 | 5 | 4 | ADAPT | 'record the current output first and prove it's unchanged after.' (05:21). 'bugs included keeps the migration from quietly fixing things on the way, which would make the old and new output impossible to compare.' (04:117 | There is no tooling; flow would have to define the capture step (fixture plus a `diff` command) itself. It only applies to refactor and migration intents. | 1. In pstack the idea is carried only by a prompt the user types ('record the current output first and prove it's unchanged after', 05-build-and-clean.md:21; 't |
| Write the README or tutorial first for shared APIs | 34/50 | 3 | 2 | 1 | 2 | 5 | 4 | MERGE | 'The doc also becomes a concrete target the agent checks its own work against.' (04:99) | Only relevant to shared or library code. A tutorial snippet is not executed unless someone makes it a doctest. |  |
| Agent-friendly control CLI traits | 36/50 | 2 | 2 | 1 | 2 | 5 | 5 | MERGE | 'Error messages that say what to do instead.' and 'A --dry-run option on anything destructive.' (06:78-80). These are the habits that make a script usable by agents. | Restates general CLI best practice; tooling:node-cli-builder covers CLI UX. |  |
| Automation line: every stage can stop the line, every stage hands over evidence | 35/50 | 4 | 2 | 1 | 3 | 2 | 2 | SKIP | 'Every stage can stop the line... Each of those outcomes is useful, because it keeps bad work from reaching the next stage' (07:113). | Host-locked to Cursor automations and Slack (07:116). A team-process feature the user didn't ask for; speculative by the user's rules. | B1 should be 2. The row's own flow_cover and verdict_reason say /flow:fix already carries the stop-the-line stages: triage at fix/SKILL.md:40, a committed red t |
| Model-role config and cost knobs | 30/50 | 2 | 1 | 2 | 1 | 1 | 4 | SKIP | 'For a panel role the value is a list, and one subagent runs per entry, so the list length sets the panel size.' (01:29). That is a neat single knob. | Built for Grok and Opus panels (README.md:30). 'Start a new chat. The model rule applies to new sessions' (01:39) is a Cursor rule-file mechanic. |  |
| /poteto-help: answer plus a prompt to send, never runs | 33/50 | 3 | 2 | 1 | 1 | 5 | 5 | MERGE | 'It doesn't start the work, because a pstack run spends real tokens, so you send the prompt when you're ready.' (README.md:26) | Low leverage for one user who wrote flow. Mostly useful for newcomers. |  |
| 'new task' re-match and worktree-per-agent hygiene | 30/50 | 1 | 2 | 1 | 1 | 3 | 5 | SKIP | Worktree cleanup that 'deletes only what that evidence clears and pauses for your call on anything holding uncommitted work' (02:115). | 'new task' patches a problem flow avoids structurally (no sticky mode, state on disk). |  |
| Start small; add a skill or check the second time a failure appears | 42/50 | 2 | 3 | 2 | 3 | 5 | 4 | MERGE | 'keeps a table in the agent instruction file that pairs each rule with what enforces it, so a rule that nothing enforces shows up as a repeat' (09:48). '[it] proves each new check fails on a real past mistake' (09:48). | pstack's architecture rung (09:37) sits above anything /lesson can do in one pass. It is heavier, and in practice it is a refactor. | plugins/flow/skills/lesson/SKILL.md is 98 lines on this worktree and on main (`git show main:...\| wc -l` = 98), so every cited line above 98 does not exist. The |

## Clever-tricks log (steal score 4 and up)

| Trick | Where | What | Why it works | Steal | Lands in |
|---|---|---|---|---|---|
| Observe before you ask | pstack/skills/poteto-mode/SKILL.md:20 | Before asking a 'which approach' question, classify it. If running something could answer it (behaviour, timing, layout, perf, whether an eval separates), run a sketch and let the result decide. Only  | It stops the agent from spending a human turn on a fact it could have measured, and stops the human from guessing at an empirical question. | 4 | plugins/flow/skills/spec/SKILL.md (discovery turn) |
| Meta-word ban in eval candidates | pstack/skills/poteto-mode/playbooks/eval.md:7-11 | No eval, test, judge, rubric, score, compare, benchmark, candidate or arena in any path, file or prompt a candidate sees. Prompts read like organic user requests. | Eval-aware candidates behave differently, so the measured skill effect is contaminated. | 4 | plugins/flow/scripts/case-selfcheck |
| Grade chain from file reads | pstack/skills/poteto-mode/playbooks/eval.md:9,22 | Never ask a candidate which skills it applied. Grade chain-following from the files its transcript shows it opened and from the shape of the code. | Self-report rewards models that name-drop skills they never read. | 4 | plugins/flow/evals/README.md (trace-targeted graders) |
| Look where grep stops | pstack/skills/blast-radius/SKILL.md:35 | List the breakage that a symbol search cannot see: the library's own source at the pinned version and any local patch, lifecycle timing (microtasks, teardown), JSON returned by an API, DB columns, wir | The cross-file lens greps call sites (adversary.md:36), so it misses consumers coupled through data rather than symbols, which is where the expensive regressions come from. | 4 | plugins/flow/agents/adversary.md (cross-file lens) |
| Cleanup keeps the proof | pstack/skills/create-verification-skill/SKILL.md:31,40 | Teardown removes instances and scratch state but never the evidence, and the prove step fails if the evidence is missing after cleanup. | flow's verification.md:75 deletes its own screenshots ('rm -f ./verify-*.png'), so the proof is gone by review time. | 4 | plugins/flow/skills/shared/verification.md:71-77 |
| Kill only what you started | pstack/skills/create-verification-skill/SKILL.md:31 | Never kill processes by name. Tear down only the instances this run launched. | pkill node also kills the user's own dev servers and sessions. | 4 | plugins/flow/skills/shared/verification.md:23-27 |
| Dismissed list as trust record | pstack/skills/interrogate/references/lead-judgment.md:58 | The verdict lists every rejected finding with a one-line reason, so the user can overrule the filter. | A silent threshold drop hides a reviewer that discarded a real bug. review-diff.js:118-121 returns only a count of dropped findings. | 4 | plugins/flow/workflows/review-diff.js (return dropped findings with score and reason) |
| Grade suppressions by rule | pstack/agents/comment-sicko.md:18,24 | Keep an eslint-disable or ts-ignore only when its rule is style-only or faulty. A suppression of a correctness or safety rule is a defect regardless of its reason comment. | flow's NS-09 accepts any same-line reason (slop-check:150-158) and does not scan eslint-disable, noqa or pylint: disable at all (slop-check:55-56). | 4 | plugins/flow/skills/no-slop/scripts/slop-check (extend NS-09 regexes) + rubric.md:100 |
| Script before fleet | pstack/skills/principle-build-the-lever/SKILL.md:16 | If one deterministic tool can process every unit in one pass, run it yourself instead of fanning out agents to hand-apply edits. | Stops paying for a fleet, and its drift, on mechanical migrations a codemod does identically. | 4 | plugins/flow-extras/skills/ultracode/SKILL.md:26 |

9 tricks scored 4 or more, out of 264 logged (duplicates across reviewers dropped).

## Appendix C: cursor-team-kit as a whole

### 1. Layer C: ways of working

| Row | kit | flow | Evidence (kit, then flow) | kit +2? |
|---|---|---|---|---|
| C1 Entry and routing | 2 | 4 | 18 flat slash skills with no router (kit/README.md:100-119). Three "CI is failing" entries overlap: fix-ci, loop-on-ci and the ci-watcher agent. deslop:3, check-compiler-errors:3 and run-smoke-tests:3 have no "use when" line. Flow reads its position from disk (`flow next --json`, plugins/flow/skills/next/SKILL.md:12), and babysit has a mode table (flow-extras/skills/babysit/SKILL.md:15-19). | no |
| C2 Composition | 3 | 4 | verify-this names control-cli and control-ui as its surfaces (verify-this/SKILL.md:31-32), and the thermo agent loads the skill as its rubric (agents/thermo-nuclear-code-quality-review.md:12). But "gh pr checks is the source of truth" is copied into fix-ci:23, loop-on-ci:12,44 and ci-watcher:20. Flow keeps rules in shared/*.md (pr-body.md, verification.md). | no |
| C3 Verification culture | 2 | 5 | verify-this has sound epistemics: a falsifiable claim, baseline vs treatment, and three verdicts (verify-this/SKILL.md:21-26,55-57). Nothing runs it, though, and the verdict is self-reported. The only hard check in the kit is the tree-hash compare (make-pr-easy-to-review/SKILL.md:25,38-44). Flow has the revert proof (fix/SKILL.md:85), PASS-<sha>, blind re-scoring (workflows/review-diff.js:73-78), claim-check re-execution (agents/claim-check.md:19) and receipts that cap any finding without one at PLAUSIBLE (agents/adversary.md:45). | no (flow +3) |
| C4 Delegation and context | 2 | 4 | ci-watcher runs as a background cheap model (ci-watcher.md:4-5). The thermo parent gathers the diff before spawning. review-and-ship says only "parallel subagents for larger diffs" (:16), with no brief. Flow uses diff-path packaging, JSON schemas and pinned agent types (review-diff.js:56,78). | no |
| C5 Learning loop | 2 | 4 | workflow-from-chats mines 7 days of chats with confidence tiers (:12,29-32), but its output is prose (a skill, rule or doc, :34-39). Flow runs a test → hook → script → skill → CLAUDE.md ladder with red-green and an adversary pass. --retro now also reads repo history and requires two sightings (lesson/SKILL.md:24-26). | no |
| C6 Human contact | 3 | 4 | The kit asks before rewriting history (make-pr:20) and before storing sensitive artifacts (verify-this:51), and forbids pushing during a conflict (fix-merge-conflicts:26). The CI loops have no ask or stop rule. Flow: babysit never merges and never undrafts a PR (babysit/SKILL.md:60), and lesson writes nothing before the user picks (:28). | no |
| C7 Long runs | 1 | 4 | "repeat until green" has no time or push cap (fix-ci:17, loop-on-ci:20). Flow: pr-watch has `--max-minutes`, `--max-waves` and exit 3 (babysit/SKILL.md:21,44), and loop is capped at 240 min / 40 iterations. | no |
| C8 Writing quality | 2 | 4 | Two prose controls: "TL;DR that matches the actual diff" (make-pr:50) and a 1-3 sentence summary cap (deslop:22). Flow has pr-body.md, which routes the body through prose-rubric.md and `slop-check --prose` (shared/pr-body.md:32). | no |
| C9 Personalisation | 3 | 2 | workflow-from-chats builds the user's own preferences into skills or rules (:34-39). Flow pins models in frontmatter and workflow JS, and its per-project knobs are thresholds only. This is the only row where the kit leads, by 1. whole.md already ruled the leverage low. | no (+1) |
| C10 Maintenance | 1 | 5 | There are no tests, not even for pr-review-canvas/renderer.js. run-smoke-tests hard-codes another repo's `npm run smoketest-no-compile` (:29), which breaks the kit's own rule against that (control-ui:108). Flow ships hook and script suites, `test_pr_watch.py`, skills-lint, workflow-lint and `flow doctor`. | no (flow +4) |
| **Total** | **21** | **40** | | |

**No row has the kit ahead by 2 or more, so the kit gives no reason to change how flow works.** Its best row, C9, is the same automate-me idea already ruled low leverage for pstack.

### 2. Layer E: the set as a product

### 2.1 Thesis

**The kit's belief:** the expensive moments sit between "code written" and "merged": CI, conflicts, review comments, PR legibility and proving the change works. A team should share short, integration-free prompts for each moment (kit/README.md:88).

**Verdict: right about which moments matter, weak in how it carries them.**
- **Right:** verification as baseline vs treatment with an honest INCONCLUSIVE (verify-this:55-57) is the correct epistemics.
- **Weak:** every one of these moments is carried as prose, with no caps, no tests and no gate.
- **Already absorbed:** pstack held the machinery for the same moments (watch-pr, create-verification-skill, benchmark-checklist), and flow has already taken that machinery. What the kit adds on top is thin, concrete gh, tmux and git know-how. It brings no new way of working.

### 2.2 Overlap map

| kit piece | flow piece | Which side has the gap |
|---|---|---|
| fix-ci, loop-on-ci, ci-watcher agent | flow-extras/skills/babysit (pr-watch, `fix-ci` / `rerun-flake` actions, wave and time caps, flake rule §3) | flow is stronger. Missing: `--log-failed`, the check `link` (pr-watch fetches only `name,bucket`, pr-watch:94), and running the wait in the background |
| get-pr-comments | babysit `answer-threads` / `triage-bot` plus references/review-bot-triage.md | flow is stronger |
| fix-merge-conflicts | babysit §4 (merge the base in, never force-push) | small **kit** gap: regenerate lockfiles rather than hand-merging them, and a conflict-marker check before push |
| new-branch-and-pr, review-and-ship | next §Ship, shared/pr-body.md, review-diff | flow is stronger |
| make-pr-easy-to-review | shared/pr-body.md; git-guard denies `push --force` (hooks/git-guard.sh:33,74) | small **kit** gap: separate core files from generated or mechanical ones, and recommend splitting when the PR is too large. The tree-hash trick has nowhere to land, because flow never rewrites a pushed branch |
| pr-review-canvas | design/skills/explainer, flow-extras/skills/pr-reviewer | covered. The canvas is tied to Cursor's in-app browser (SKILL.md:160) |
| verify-this | fix revert proof, claim-check, benchmark-checklist (same-way baseline and an inconclusive verdict, :18,23), verification.md:77 (before/after screenshots kept) | narrow **kit** gap: baseline and treatment for claims that are neither a number nor a bug, plus INCONCLUSIVE in claim-check |
| control-cli | verify-skill template "Drive: … PTY/tmux" (references/skill-template.md:26), and the built-in `run` skill | **kit** gap: no wait-for-pattern driving recipe or helper in flow |
| control-ui | web/agent-browser, shared/agent-browser-reference.md, verify-skill | flow covers it |
| run-smoke-tests | shared/e2e-testing.md, fix/SKILL.md:51, verify-skill | flow covers it |
| check-compiler-errors | shared/scripts/check-all, stop-gate, TYPECHECK_CMD (project-detection.md:67) | flow is stronger (a gate, not a request) |
| deslop | no-slop rubric (NS-03, NS-09, NS-22 at rubric.md:26-28) plus slop-check | flow is stronger |
| thermo-nuclear skill and agent | review-diff lenses, adversary, NS-17 complexity growth, size-guard hook | small **kit** gap: a "did complexity move or get deleted / code judo" lens. Its 1k-line rule is weaker than size-guard |
| workflow-from-chats | lesson --retro (repo history, two sightings), claude-improver:209 (conflicting evidence) | flow builds better. Small **kit** gap: a contradicted tier and a `--since` window |
| what-did-i-get-done, weekly-review | worklog (installed separately; not verified working on this machine) | none needed (B2 = 1) |
| no-inline-imports rule | ruff PL / PLC0415 via `flow init` (bin/flow:1586), NS-25 | covered for Python. JS/TS gap is low value |
| typescript-exhaustive-switch rule | flow init eslint thresholds (bin/flow:1559-1577) | small **kit** gap, if the project's eslint config is type-aware |
| *(none)* | stop-gate, git-guard, PASS-<sha>, loop caps, blind re-score, lesson ladder, babysit caps, `test_pr_watch.py`, prose `slop-check` | **only flow has these** |

### 2.3 Should flow fill each kit-only gap?

| Gap | Fill it? | Home |
|---|---|---|
| CLI/TUI driving recipe (wait for a pattern, then send keys) | **Yes.** B7 is about 3, because the user builds CLIs. It loads on demand only. Fix the kit's two bugs when porting: `NODE_OPTIONS=… tmux new-session` does not reach the CLI when a tmux server is already running (use `new-session -e`), and the snippet calls capture-pane with no wait (control-cli:41-44,51). | flow (shared reference plus a helper script) |
| pr-watch blind spots (`link`, `--log-failed`, background wait) | **Yes.** It makes the newly borrowed babysit actually able to deliver the "run URLs" its final report requires (§6). | flow-extras (babysit) |
| Lockfile regeneration plus conflict-marker check | **Yes, small.** B7 is about 2: 20 of 49 repos have lockfiles, and parallel worktree PRs happen. | flow-extras (babysit §4) |
| Baseline/treatment and INCONCLUSIVE for general claims | **Yes, small.** Numbers are already covered by benchmark-checklist and bugs by the revert proof. | flow (agents/claim-check.md) |
| Structure lens ("did complexity move or get deleted") | **Yes, opt-in only.** It must not become a default lens, because that adds a sixth agent to every review. | flow (agents/adversary.md) |
| Exhaustive switch for TS | **Maybe.** Only when typescript-eslint and type-aware config are detected. | flow (bin/flow eslint thresholds) |
| Core vs mechanical split line in PR bodies | **Yes, one line.** | flow (shared/pr-body.md Summary) |
| History cleanup with the tree-hash check | **No.** Flow never rewrites pushed history, and git-guard plus babysit forbid force-pushes. | none |
| pr-review-canvas, weekly-review, what-did-i-get-done, deslop, check-compiler-errors, run-smoke-tests, control-ui, fix-ci, loop-on-ci, get-pr-comments, new-branch-and-pr, review-and-ship | **No.** Flow covers each one, as mapped in 2.2. | none |

### 3. Top changes to flow, ranked by leverage (6)

None of these adds per-turn output or a new top-level skill. Each one is a script change, or a short edit to a step that already exists.

1. **Close pr-watch's CI blind spots.**
   - **Files:** `plugins/flow-extras/skills/babysit/scripts/pr-watch` (plus a case in `test_pr_watch.py`) and `plugins/flow-extras/skills/babysit/SKILL.md` §2-3.
   - **What:**
     - Fetch `name,bucket,link` in the `gh pr checks` call (pr-watch:94) and print the failing check's link.
     - In §3, name `gh run view <run-id> --log-failed` as the way to read the log.
     - In §2, say to run `drive` reads with Bash `run_in_background`. The 60-minute wait exceeds the 10-minute foreground cap, and polling should be done by a script, not by a background model as in kit/agents/ci-watcher.md:4-5.
   - **Why:** babysit's report must list "run URLs" (§6), but pr-watch never fetches them. Without these changes a foreground `drive` read is killed at 10 minutes.

2. **A CLI/TUI driving reference with a wait-for-pattern helper.**
   - **Files:** new `plugins/flow/skills/shared/cli-driving.md` and new `plugins/flow/skills/shared/scripts/tui-drive` (tmux: start with `-e` env, `send` one action, then `wait-for <regex> --timeout`, `capture` to a transcript file, kill only its own session), with a test. Add one pointer each in `plugins/flow/skills/shared/verification.md` Step 2 (:25) and `plugins/flow-extras/skills/verify-skill/references/skill-template.md:26`.
   - **What:** take the kit's harness loop (control-cli:20-27): one action at a time, then wait for a concrete pattern.
   - **Why:** flow has no driver for interactive CLIs, and the user builds them. It replaces sleep-and-hope with a check that times out loudly. It is loaded only when the verify surface is a terminal.

3. **Conflict resolution that a check can catch.**
   - **File:** `plugins/flow-extras/skills/babysit/SKILL.md` §4.
   - **What:**
     - Regenerate lockfiles with the package manager (`bun install`, `uv lock` and so on), never hand-merge them (from fix-merge-conflicts:17).
     - Run `git diff --check` and `git grep -n '^<<<<<<< '` before the push. A non-zero result blocks the push.
   - **Why:** a hand-merged lockfile, or a stray conflict marker, is the usual way a "resolved" conflict breaks CI on the next wave.

4. **Baseline/treatment in claim-check.**
   - **File:** `plugins/flow/agents/claim-check.md`, Protocol steps 1-2 (:18-19) and verdicts (:22-25).
   - **What:**
     - When a claim is about a change ("X now does Y"), restate it falsifiably (condition, metric, threshold) at the existing narrowest-reading point (:29).
     - Run the same command at the merge base and at HEAD, and print `baseline= treatment=`.
     - Add INCONCLUSIVE for "no valid baseline, or the environment differs" (verify-this:21-24,57).
   - **Why:** today claim-check confirms "it works" at HEAD only. Numbers already go to benchmark-checklist and bug claims to the revert proof, so this covers what is left, with no new skill.

5. **An opt-in `structure` lens for the adversary.**
   - **Files:** `plugins/flow/agents/adversary.md` Lenses (:31-37); allow it in `plugins/flow/workflows/review-diff.js:56` through `args.lenses` only, not as a default.
   - **What:** ask "did the diff move complexity or delete it?" and "is there a restructuring that makes branches disappear?" (thermo SKILL.md:11,75). Findings fall under the existing receipt rule (:45), so a finding with no executed receipt stays PLAUSIBLE.
   - **Why:** NS-17 and size-guard catch growth by the numbers. Nothing in flow asks whether a simpler shape existed. Opt-in keeps the default review cost unchanged.

6. **Exhaustive switch as lint, not as an always-on rule.**
   - **File:** `plugins/flow/bin/flow:1559-1577` (eslint thresholdContent).
   - **What:** add `@typescript-eslint/switch-exhaustiveness-check` only when typescript-eslint is installed and the config is type-aware (the rule needs type information). Otherwise skip it silently.
   - **Why:** this turns kit/rules/typescript-exhaustive-switch.mdc, an always-in-context prose rule, into a check. It has the lowest leverage of the six, because B7 depends on how many of the user's TS repos use typed linting.

**Smaller, one line each:**
- **shared/pr-body.md Summary:** "separate core files from generated or mechanical ones; if notes cannot make it reviewable, split the PR" (make-pr:51,59).
- **lesson/SKILL.md --retro (:15-26):** add a `--since <days>` window, and a "contradicted" tier that asks the user, as claude-improver:209 already does.
- **pr-watch default:** make `--max-minutes 0` mean "no limit" only under `--once`. Right now the 60-minute cap exists only as prose in SKILL.md:21.

**Where flow, with the pstack borrows, already covers the kit, so nothing should be copied:**
- **CI and PR follow-up:** fix-ci, loop-on-ci, ci-watcher, get-pr-comments and review-and-ship are covered by babysit (with pr-watch, its tests and caps), next §Ship and review-diff.
- **Code quality:** deslop is covered by no-slop plus `slop-check`, and check-compiler-errors by check-all and stop-gate.
- **UI and smoke testing:** run-smoke-tests and control-ui are covered by e2e-testing.md, agent-browser and verify-skill.
- **Numbers:** verify-this's performance and memory half is covered by benchmark-checklist.
- **Not borrowed at all:** pr-review-canvas (Cursor-bound), weekly-review and what-did-i-get-done (B2 = 1), the tree-hash history rewrite (flow never force-pushes), and no-inline-imports (ruff PLC0415 already fires for Python).
## Appendix D: every cursor-team-kit piece, scored

### CI and PR skills

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| fix-ci | 17/50 | 1 | 1 | 1 | 1 | 5 | 5 | SKIP | Names gh pr checks as the source of truth (fix-ci/SKILL.md:23), which pr-watch already follows. | 'Fix one actionable failure at a time' (fix-ci/SKILL.md:21) contradicts the better rule in babysit, 'Batch every known fix into one push, since each push restarts CI' (babysit/SKILL.md:46). 'Repeat until green' (:17) has |  |
| loop-on-ci | 69/120 | 1 | 2 | 2 | 2 | 5 | 5 | SKIP | Gives the exact log command 'gh run view <run-id> --log-failed' (loop-on-ci/SKILL.md:35), which babysit lacks (babysit/SKILL.md:50 says only 'Read the failing job's log'). States why gh pr checks beats gh run list: it 'i | No cap on the loop ('repeat until green', :20). Flake handling is one line of prose (:43) where babysit has a counted rerun flag in the script. Guardrails restate defaults flow enforces by hook. |  |
| fix-merge-conflicts | 57/120 | 2 | 2 | 1 | 2 | 5 | 5 | MERGE | 'Regenerate lockfiles with package manager tools instead of hand-editing' (fix-merge-conflicts/SKILL.md:19) prevents the commonest bad merge. 'Do not leave conflict markers in any file' (:24) is worth making mechanical. | Marker rule is prose; 'git diff --check' or a grep for '^<<<<<<< ' would make it a check. 'Prefer preserving both sides when safe' (:16) is a judgment call with no test of 'safe'. | MERGE holds only once B7 >= 2 is shown from the user's repos: how often does a flow PR hit a lockfile conflict? Without that profile fact the verdict does not f; fix-merge-conflicts/SKILL.md:17. Line 19 is 'Stage resolved files and summarize key decisions'. |
| get-pr-comments | 7/50 | 1 | 1 | 0 | 1 | 5 | 5 | SKIP | Asks for open questions to be listed apart (get-pr-comments/SKILL.md:23). | No command at all, no resolved/outdated filtering, no bot vs human split, no untrusted-text warning; B3=0 because it is four steps of prose a model does by default. |  |
| new-branch-and-pr | 11/50 | 0 | 1 | 0 | 1 | 5 | 5 | SKIP | Nothing flow lacks. | 'Complete implementation and tests' (new-branch-and-pr/SKILL.md:16) is the whole build process in four words; 'test notes' is weaker than flow's exit-code evidence. |  |
| review-and-ship | 56/120 | 1 | 1 | 1 | 2 | 5 | 4 | SKIP | 'Use gh pr checks instead of GitHub Actions-only commands when judging PR readiness' (review-and-ship/SKILL.md:35), already true in pr-watch:94. | 'user intent from recent relevant chats if useful' (:14) is Cursor-chat-history-specific and vague. Self-review by the author with no blind re-score; 'decide whether to add them or document the gap' (:15) lets the model  |  |
| make-pr-easy-to-review | 85/120 | 3 | 2 | 3 | 3 | 3 | 4 | MERGE | Tree-identity proof: capture 'ORIGINAL_TREE=$(git rev-parse origin/<headRefName>^{tree})' (make-pr-easy-to-review/SKILL.md:25) and compare after rewrite, 'Do not push if the tree changed unintentionally' (:44). Turns a ' | History rewrite clashes with flow's harness (force push denied) and with flow-built PRs, whose commits are already one per task. Dependency-order commit grouping (:28-34) is advice, not checked. | B1=3 with a small new piece does fit MERGE, but B7 has to be scored first. The force-push conflict noted under B5 (git-guard GG_BIG denies push --force, plugins |
| pr-review-canvas | 83/120 | 3 | 2 | 3 | 3 | 3 | 3 | SKIP | Script-safe embedding: 'Patch strings can contain </script>' so it writes patches with jq and injects with json.dumps(...).replace('<','\\u003c')... (pr-review-canvas/SKILL.md:105-133). Moved-code detection: 3+ consecuti | Cursor-bound: 'navigate the in-app browser' (:160). Fixed dark theme only (styles.css:1-13), which breaks the Artifact light/dark contract. The fixed-port rationale, that a background python buffers its startup line (:16 | With the scores as given (B1=3, B2=2, B6=3), no SKIP condition fires either: B1 is not <= 1, B2 is not <= 1, and B6 is not <= 1. So SKIP is not derived from the |
| ci-watcher (agent) | 16/50 | 1 | 1 | 2 | 2 | 2 | 4 | SKIP | Keeps the wait off the main thread: 'model: fast', 'is_background: true' (ci-watcher.md:4-5). Returns 'relevant failure links' (:3,28), which pr-watch does not fetch (it asks only for name,bucket at pr-watch:94) even tho | 'model: fast' and 'is_background' are Cursor frontmatter. A model that polls is costlier and less reliable than flow's script. 'Use proactively' (:3) invites unasked background work. |  |

### Quality and verification skills

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| deslop | Tiny | 0 | 1 | 0 | 1 | 5 | 5 | SKIP | It acts on the branch diff, not the whole file (deslop/SKILL.md:8). The 'keep behavior unchanged unless fixing a clear bug' guardrail (:20) is right. | Prose only: there is no detector, no false-positive list and no receipt rule. 'Abnormal for trusted code paths' (:13) leaves the boundary undefined; flow's NS-22 guard names it (user input, network, file, env). It is wea | NS-03 is at rubric.md:26, NS-22 at :27 and NS-09 at :28. Lines :24-25 are the table header. The coverage claim holds. |
| thermo-nuclear-code-quality-review (skill) | Scored | 3 | 3 | 1 | 1 | 4 | 3 | MERGE | - The ambition framing: 'Look for opportunities to reframe the change so that whole branches, helpers, modes, conditionals, or layers disappear entirely' (:29). - The 'refactors that move code around but fail to reduce t | - Prose only. The one checkable rule (the 1k-line crossing, :34) is already a hook in flow, and stricter. - There is no receipt or evidence rule, so findings are opinion. That breaks flow's 'no receipt, no finding' (no-s |  |
| thermo-nuclear-code-quality-review (agent) | Tiny | 1 | 1 | 1 | 1 | 2 | 4 | SKIP | The labelled-section handoff ('### Git / diff output', '### Changed file contents', :8) keeps raw git output out of the main thread. 'Do not spawn nested subagents unless ... explicitly asks' (:19). | A pure wrapper around the skill, with Cursor Task subagent types. Its fallback rubric (:13) duplicates the skill. |  |
| check-compiler-errors | Tiny | 0 | 1 | 0 | 1 | 5 | 5 | SKIP | 'Re-run checks until clean or blocked' gives a clear stop condition (:17). | Prose that restates what any agent does. No mechanism and no command discovery. | TYPECHECK_CMD is defined at plugins/flow/skills/shared/project-detection.md:67 and :80, and consumed at verification.md:12. verification.md has no line 169. The |
| run-smoke-tests | Scored | 1 | 1 | 0 | 2 | 3 | 5 | SKIP | 'Quarantine tests only when explicitly requested and documented' (:36). | Hard-codes another repo's npm scripts (:23-29). That contradicts the kit's own rule 'Do not hard-code ... script paths from another repository' (control-ui/SKILL.md:108). Prose only. |  |
| verify-this | Scored | 2 | 3 | 2 | 4 | 5 | 4 | MERGE | - 'Restate the claim in falsifiable form: condition, metric, and threshold' (:21). - 'Capture treatment from the changed state with the same command, data, warmup, and environment' (:24). - 'INCONCLUSIVE: no valid baseli | - The artifacts go to /tmp/verify-this/<claim-slug>/ (:42), which is not durable and conflicts with flow's `<Feature>/verify/` (verification.md:234). - There is no script, so the verdict is still self-reported. - The pri | verification.md has only 79 lines. The evidence rule is at verification.md:77, and that same line already moves `./bug-before.png` and `./bug-after.png` into `<; 3 |
| control-cli | Scored | 3 | 3 | 2 | 3 | 5 | 5 | ADAPT | - 'Wait for a concrete screen pattern or prompt before the next action' (:25) and 'Prefer deterministic waits over sleeps. If you must sleep, explain why' (:105). - 'Capture the current screen before interacting' (:23).  | - Prose plus snippets, with no reusable script. The PTY sample uses a fixed 30s deadline and breaks after the first send (:77-87), so it is a toy. - The Chrome-DevTools profiling step (:54) is vague. - Nothing forces the | The port-0 idea is sound, but the kit's snippet is broken. `NODE_OPTIONS=... tmux new-session -d ...` does not reach the CLI when a tmux server is already runni |
| control-ui | Scored | 1 | 2 | 1 | 3 | 4 | 5 | SKIP | - 'If no page matches, list available page titles and URLs instead of guessing' (:100). The CDP sample throws after printing the candidates (:61-66). - 'Avoid coordinate clicks unless a fresh screenshot was captured imme | - Playwright snippets duplicate what agent-browser does in one command. - 'Do not store screenshots ... unless the user explicitly agrees' (:107) is the opposite default to flow's evidence-on-disk rule. - Prose only. |  |

### Reporting skills, rules and README

| Piece | Craft | Gap | Lev | Mech | Evid | Port | Cost | Verdict | Good | Bad | Skeptic note |
|---|---|---|---|---|---|---|---|---|---|---|---|
| what-did-i-get-done | About | 2 | 1 | 1 | 2 | 4 | 4 | SKIP | It prints the date range it actually used (:18), so a vague 'last week' cannot hide a wrong window. It describes changes by function and does not guess why they were made (:25), which keeps fabricated motivation out of s | Prose only, with no command, so author email, timezone and branch scope are left to the model. It overlaps the user's worklog/Tempo tool. It does not change the outcome of any build, fix or review. | Nothing in flow or the installed skills on this machine covers this. Commit 311c7ea removed the worklog skill from tooling, and it is now installed separately w |
| weekly-review | About | 2 | 1 | 1 | 2 | 4 | 4 | SKIP | The classification is hedged as 'likely' (:19-21) and 'Base claims only on commit history and diffs' (:26). It stops and asks when git user.email is missing (:27) and does not guess the author. | The classification is guesswork from commit messages when Conventional Commit prefixes (fix:/chore:/feat:, which flow commits already use) would make it deterministic. It is a near-copy of what-did-i-get-done. It is a re | Same problem as what-did-i-get-done: the worklog skill is not present on this machine and its coverage is unverified. flow has only the forwarding hook. The new |
| workflow-from-chats | About | 2 | 2 | 1 | 2 | 3 | 3 | MERGE | The 'Contradicted: ... ask the user before writing files' tier (:32) catches the case lesson's two-sightings rule misses: two sightings that point opposite ways. It treats subagent transcripts as evidence but cites only  | Prose only, with no transcript-listing script and no structured output. Its artifact choice stops at skill, rule or doc and never reaches a test or hook, which is weaker than lesson's rung ladder. It runs no adversary an | flow-extras already handles conflicting evidence, though only conflicts between swarm agents, not across a user's sessions. claude-improver/SKILL.md:209 says to |
| no-inline-imports (rule) | 16/50 | 4 | 1 | 0 | 0 | 3 | 3 | SKIP | It allows inline imports only with a documented reason (:8). That 'exception needs a written reason' shape is a good pattern for any lint carve-out. | Mechanism 0: an always-on prose line where a lint rule exists (ruff PLC0415). In Claude Code it would land as a CLAUDE.md line on the user's 40-line global budget. The leverage is cosmetic. | Python is covered, and this was checked by running ruff. flow init's ruff threshold file selects "PL" (plugins/flow/bin/flow:1586), and with ruff 0.16.2 that se; 2 |
| typescript-exhaustive-switch (rule) | 26/50 | 3 | 2 | 3 | 3 | 4 | 4 | MERGE | It turns a review judgement into a compile error. Once the `never` default exists, tsc fails the build on a new variant, so the check is mechanical even though the rule text is prose. | Delivered as always-on prose. The enforceable form is @typescript-eslint/switch-exhaustiveness-check, which needs typed linting, and flow's eslint thresholds cannot assume typescript-eslint is installed. The flow CLI its |  |

## Clever-tricks log (steal score 4 and up)

| Trick | Where | What | Why it works | Steal | Lands in |
|---|---|---|---|---|---|

0 tricks scored 4 or more, out of 47 logged (duplicates across reviewers dropped).
