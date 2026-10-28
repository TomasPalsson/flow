# /flow:moonshot: skill-forge build and evals (2026-10-27)

Ask: a skill after Kevin Bondzio's "Moonshot prompt" (screenshot from the user): "What would be an absolute
moonshot to improve [X]? Assume unlimited dev resources and 12 months... Let it rip", then "Write it to
MOONSHOT.md", then go through the 4-6 phases. Their case: an app embedding CEF; months of small tweaks went
nowhere; the moonshot was replacing CEF with their own renderer on Blitz. "The agent could always build something
like this. It just never suggested it, because in human time it looked too expensive." Built with skill-forge.
User rulings: lives in `flow` (it writes seed PREP.md files), phases hand off to flow one at a time, full forge.

## What Claude does without the skill (baseline, 3 Sonnet runs + 6 cold attractor runs)

| Repo | Model | Shape | Bets bundled |
|---|---|---|---|
| aws-exam (baseline) | sonnet | knowledge graph, learner twin, labs, factory, tutor, sync, cohorts | 7 |
| news (baseline) | sonnet | claim graph, atlas, council, scoreboard, platform | 5+ |
| ads-seo (baseline, "ugliest part") | sonnet | typed SDK, outcome ladder, morphology, causal engine, simulator, multi-client | 6 |
| TerminalWebsite | sonnet | real WASM Linux VM per visitor | 1 |
| hitataekni | opus | equipment digital twin + ops platform | 4 |
| terraform | sonnet | typed intent compiler + reconciler agent | 3 |
| ads-seo | opus | causal self-improving engine + simulator | 3 |
| news | sonnet | public self-auditing knowledge graph + API | 1 |
| aws-exam | opus | diagnostic tutor + graph + generator + real-score loop | 3 |

- Ambition is not missing: every run is large and repo-grounded. "Be bold" would be a no-op.
- The attractor for current Claude models is not the literature's hivemind list (Rust, microservices, k8s: 0/9)
  but a kit: graph (5/9), twin/simulator (5), Bayesian/calibration (4), agent loop (5), platform turn (6).
- Failures: bundles (~3 bets), human-team pricing ("five squads of 3-5", hires), quarter-shaped overlapping phases,
  infrastructure-first phase 1, 350-520 lines, no route to execution, users the owner never mentioned.

## Research basis (`.skill-forge/moonshot/`, 9 research files, 25 key claims cross-checked: 18 confirmed, 7 weakened, 0 fabricated)

- Every successful agent-driven port had an executable oracle: Ladybird LibJS (byte-identical lockstep, ~25k lines,
  ~2 weeks), Bun Zig->Rust (11 days to merge, ~$165k API-priced, 19 known regressions, stable ~14 weeks later),
  Anthropic's C compiler (GCC as oracle). vinext passed its tests and still had 24 validated security findings.
- Monkey first (Teller, X): phase 1 tests the killing assumption; the pedestal is rewarded and makes quitting costly.
- LLM judges rank ideas near chance (53.3% vs 56.1% human agreement, Si et al.); generate several, attack with a
  kill-or-amend pass, human picks one.
- Flow router: with no feature holding a spec, `flow next` shows the newest PREP-only dir and ignores `.current`
  (router.js `findPrepWithoutSpec`), so only the next phase is seeded; one moonshot phase = one flow feature.

## The skill

`plugins/flow/skills/moonshot/`: SKILL.md (Process, 6 steps, two human gates: pick one bet, yes to seed),
references recon / candidates / moonshot-template / handoff, `scripts/recon.mjs` (git churn and fix share by
directory, stall signature, aged workarounds by blame, dependency size vs import sites, large files; 11 node tests).
Leading words: accepted constraint, deletion list, 10x test, the monkey, oracle. Eval case `routing-moonshot`.

## Evals (with skill vs baseline, blind, both orders, Opus comparator)

| Round | With-skill wins | Ambition (with / base) | Credibility | Surprise | One bet |
|---|---|---|---|---|---|
| 1 | 5/6 | 6-7, 4-5, 1-2 / 9 | 7-8 / 3-4 | 3-8 / 4-6 | 3/3 vs 0/3 |
| 2 | 6/6 (5 clear, 1 huge) | 8, 7, 7 / 9 | 7-8 / 3-4 | 6-8 / 4-6 | 3/3 vs 0/3 |

- Round 1 regression: evidence-first target finding on 1-2-month-old repos shrank the bets into cleanups (news: dedupe
  `_http.py`; ads-seo: "no moonshot found", missing the NO_DATA ruling). Fix: the 10x test, "never shrink the bet to
  fit the evidence", rulings and stated limits as signal family 1, a skeptic kill rule for tasks.
- Round 2 bets: aws-exam "discrimination factory" (render verified items from cited discriminations, not 1,556
  frozen texts); news "house models" (replace the single 27B model behind `llm.py` call site by call site);
  ads-seo "give the loop a sensor" (a validated intent ladder instead of NO_DATA).
- Round 2's comparator prompt added the owner's ask ("an ABSOLUTE moonshot, not a cleanup").
- skill-judge: 107/120 both iterations (no critical issues).

## Rounds 3-7 (2026-10-28): "go all out", anchored ambition scale

The user wanted ambition 10 ("go nuts, all out"). Comparator scale: 10 = the project becomes a different, far
bigger thing nothing does today; 8 = a huge change in a known direction; 6 = a big upgrade of one part.

| Round | Change | Ambition with skill (6 comparisons) | Baseline | Wins |
|---|---|---|---|---|
| 3 | feasibility never shrinks a bet; only gate = cheap phase-1 kill test; north star 10x floor | 8 x6 | 7-8 | 6/6 |
| 4 | audience cap lifted when reach is the bet; web prior art = known direction; push x3 | 9,8,8,8,8,8 | 7-8 | 6/6 |
| 5 | Opus runner; category-level constraint in the brief | 8.5,8,9,9,8,8 | 7 | 6/6 |
| 6 | make-it-a-10 pass (fresh rater names what holds it below 10) | 9 x6 | 7-8 | 6/6 |
| 7 | owner scope rulings may be broken (safety/money/data stay hard); 10 pass up to 3 rounds | 9,8,9,9,9,9 | 6-7.5 | 6/6 |

Round 7 bets: aws-exam "Architect Kernel" (a deterministic rule kernel generates, answers and grades items; the
bank becomes a legacy oracle); news a primary-source wire (GH Archive, CT logs, BGP, HF Hub, EDGAR) that beats the
press with re-runnable receipts; ads-seo "The Front Door" (Iceland's free first stop for legal problems, grading
every enquiry and steering spend by it). The in-skill rater reached raw 10 on two of them; nested runs discount
self-ratings by one because they have no subagent tool. Credibility 5-7 vs baseline 3-4. skill-judge 108 raw
(capped 95 on a linter false MISSING for `${CLAUDE_PLUGIN_ROOT}`, fixed with a relative link).

## Open

- No nested eval run had an Agent tool, so the cold generator and separate skeptic only ran as the documented
  same-model fallback; the main-session subagent path is untested.
- Steps 5-6 (seed and re-entry) not run end to end; trigger rate not measured.
