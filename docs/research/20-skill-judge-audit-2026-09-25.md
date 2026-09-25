# Skill judge audit and the Claude performance playbook

*Date: 2026-09-25. Repo paths are relative to `plugins/flow/skills/` unless they say otherwise. Findings that verification refuted appear only in "Checked and dropped". Contested findings are labelled **(contested)**.*

## Short version

- The strongest way to get good behaviour from a skill is to write it from failures you have actually watched Claude make, then compare runs with and without the skill. In the one large benchmark, skills a model wrote for itself scored below using no skill at all [7].
- Keep skills short and focused, and keep the tone calm. Explain why each rule exists, say what to do rather than only what not to do, and use capitals for at most one rule that testing shows gets skipped [1][2][3]. This is Anthropic's guidance. Nobody has measured it on Sonnet 5 or Opus 5.x.
- Back a fragile step with a script or a check. Louder wording does not make it safer [1].
- On average the judge ranks bait below honest skills: across both rounds (n=6), bait scored 97.2, the original 113, the calm rewrite 111.3 and the caps rewrite with its reasons stripped 110.3. But single runs are noisy. 3 of the 6 bait runs scored 96 or more, which clears skill-forge's gate. The judge also only reads text. It never runs the skill, never checks that the files it points to exist, and never checks that "expert" claims are true.
- Parts of the rubric reward a style Anthropic now advises against: one big NEVER list, "ask yourself" framing, and MANDATORY/MUST wording.
- About 25 of the 120 points carry almost no signal. D7 gave 9 to every variant, and D4 gave 15 to three of the four.
- Fix order: (1) run the reference and frontmatter checks before every judge run, (2) reword D2, D3, D4 and D5, (3) make skill-forge run a baseline before drafting and a small with/without check before delivering.
- Tipping, threats, expert personas and shouting do not reliably help. Don't use them.

## The playbook

The principles are ranked by how much they matter. Evidence strength is marked M (measured), O (official Anthropic guidance) or P (practitioner).

| # | Principle | Do / don't | Evidence | Sources |
|---|---|---|---|---|
| 1 | Write from observed gaps and measure the effect. Run the task without the skill, record where it fails, write only that, then compare with-skill and without-skill runs. | Do: "baseline run failed to revert the fix before testing, so the skill covers that step." Don't: write what you imagine Claude lacks. | M, O | Curated skills raised the pass rate from 33.9% to 50.5%, but 13 of 87 tasks got worse, and self-generated skills fell below baseline in all 3 configurations (−8.1 to −11.5pp) [7]. Anthropic says to build evaluations before documentation [1][5]. Skill-creator runs paired with/without subagents [8]. A red baseline is mandatory in [28]. |
| 2 | Keep it small and focused. | Do: body under 500 lines / about 5k tokens, one job. Don't: an exhaustive bundle "just in case". | M (small n), O | Mounting 4 or more skills on one task shrank the gain (+10.1pp against +18-19pp for 1-3). In an ablation with 3 trials per cell, compact SKILL.md bodies beat comprehensive ones [7]. Anthropic's phrase is "smallest set of high-signal tokens" [6]. The limits come from [1][4]. |
| 3 | Explain the reason and keep the tone calm. Reserve emphasis for one rule that testing shows gets skipped. | Do: "Use `git revert --no-commit`; checkout also restores the test file, so a fake test goes green." Don't: "CRITICAL: you MUST NEVER…" on every line. | O only, not measured on current models | Claude generalizes from explanations. "CRITICAL: You MUST" over-triggers on Opus 4.5/4.6, so dial it back [2]. "If you emphasize many lines, none of them stands out" [3]. Skill-creator calls all-caps ALWAYS/NEVER a yellow flag [8]. No Anthropic statement on emphasis for Sonnet 5 or Opus 5.x was found. Anthropic says to treat a technique that names a model as measured only on that model and to re-check it with your own evals [2]. **(Contested)**: Opus 4.8 leans towards under-using tools. Its guide fixes that by raising the effort parameter or making clear when the tool is useful, and says nothing either way about emphasis [9]. Anthropic's skill authoring guide offers "MUST filter" instead of "always filter" as a way to raise a rule's prominence [1]. Its own sample prompt against hallucination uses "Never speculate… you MUST read the file" [2]. Skill-creator also breaks its own rule [27]. skill-improver argues that blunt wording resists user persuasion better (P, no measurement). Keep blunt wording for the one rule you tested. |
| 4 | Say what to do, not only what to avoid. | Do: "Exports: named only." Don't: "NEVER use default exports." | O only, not measured on current models (M on non-Claude models only; P for the size of the effect) | "Tell Claude what to do instead of what not to do" [2]. The Sonnet 5 and Opus 5 guides both say positive examples of the style you want work better than instructions about what not to do [30][36]. On Opus 5, a system-prompt rule not to think increases tag leakage, and the fix is to delete the rule. Naming the unwanted pattern works worse than describing the wanted behaviour in general terms [36]. ReboundBench measured an ironic rebound after "do not mention X" on 9 open models up to 20B parameters. No Claude model was tested [37]. **(Contested)**: Anthropic's own current sample prompt relies on "Never…" wording [2]. claude-md/SKILL.md:69-73 claims about 50% fewer violations, with no source given (P). |
| 5 | Match specificity to fragility and variability. Enforce fragile steps with a script or validator. | Do: "Run exactly `python scripts/migrate.py --verify --backup`." Don't: describe an irreversible step in loose prose, or script a judgement call. | O | "Match the level of specificity to the task's fragility and variability"; prefer scripts for deterministic operations [1]. lesson/SKILL.md:9: "a sentence… is a request; a test, hook or script is enforcement" (P). |
| 6 | Give Claude a way to check its own work. | Do: a checklist Claude copies into its reply, or a "run validator, fix, repeat" loop, or a test's exit code that decides "done". Don't: accept "looks done". | O | The checklist and validator loop are in [1]. no-slop/SKILL.md:43: "no receipt, no finding" (P). |
| 7 | The description does the triggering. Write it in the third person, cover WHAT and WHEN, use plain "Use when…", name near-miss exclusions, stay under 1024 characters, and test the trigger rate. | Do: "Fixes a broken behaviour… Not for recording a defect (/flow:issue)." Don't: "MUST be used whenever…" followed by keyword lists. | O | Third person is required [1]. "Pushy" but plain wording, near-miss negatives, and a 60/40 train/test split [8]. |
| 8 | Fewer rules. | Do: cut any line where the answer to "would Claude get this wrong without it?" is no. Don't: add NEVERs to raise a score. | M | Instruction-following falls as the number of instructions grows, Claude models included. The best model managed 68% at 500 instructions [15]. |
| 9 | Show 3-5 diverse examples. | Do: wrap the examples in `<example>` tags. Don't: one example, or twenty. | O | [2] |
| 10 | Keep references one level deep, and give long files a table of contents. | Do: SKILL.md links to `ref.md`, and `ref.md` links nowhere. Don't: chains of references. | O | Claude may preview nested files with `head -100` and miss content [1]. **(Contested)**: in practice one skill loaded all 31 of its references in a single call [26]. |
| 11 | Re-test across models and after model updates. | Do: test on Haiku, Sonnet and Opus. Don't: assume a prompt tuned for one release transfers. | O | "What works perfectly for Opus might need more detail for Haiku" [1]. Sonnet 5's literal instruction-following can lower measured recall on harnesses tuned for older models [30]. Anthropic says a technique that names a model counts as measured only on that model [2]. |
| 12 | Put the one or two rules that must hold at the top of the body and at the step they govern. | Do: state the must-hold rule first, then repeat it at the step it controls. Don't: bury it in the middle of a long list. | O, P **(contested)** | prompt-engineer/SKILL.md:50-54 and claude-md/SKILL.md:48-57 treat position as a compliance lever (P). **(Contested)**: Anthropic reports up to +30% for putting the query last in long multi-document prompts [2], but a 2026 RAG study found putting evidence first beat putting it last [35]. The 30% attention-drop figure in prompt-engineer has no source (P). |

### Myths and weak levers

- **Tipping and threats.** Neither had a significant effect on GPQA or MMLU-Pro accuracy [10] (tested on non-Claude models). **(Contested)**: tone did change output-token cost by up to 44% [14].
- **"You are an expert" personas.** Adding a persona did not improve factual accuracy across 162 personas [11]. In one study an expert persona lowered MMLU accuracy from 71.6% to 68.0%, and to 66.3% with a long persona [12] (secondary report). Define the behaviour and the output contract instead.
- **Shouting (CAPS, MUST, CRITICAL).** On Opus 4.5/4.6 this causes over-triggering [2], and emphasis on many lines dilutes all of it [3]. No equivalent statement exists for Sonnet 5 or Opus 5.x, and Anthropic's skill guide still offers "MUST" as a way to add prominence [1]. In the blind experiment the rewrite that added capitals and also stripped the reasons scored slightly below the original (110.3 against 113 over 6 runs, with overlapping ranges). Most of the gap was in D3, where the reasons had been removed. So the text-only judge did not reward shouting.
- **Politeness or rudeness.** On GPT-4o, rude phrasing scored 84.8% against 80.8% for polite phrasing on 50 questions [13]. That is one model and a small sample. Don't tune tone for accuracy.
- **Persuasion principles (authority, commitment).** They raised GPT-4o-mini's compliance with refused requests from 33% to 72% [24], but were never tested on Claude, and the same mechanisms work as jailbreak vectors [25]. Don't import them into skills.
- **Hand-written "think step by step" scaffolding on thinking models.** Anthropic's internal evaluations found adaptive thinking beats manual approaches [2]. **(Contested)**: manual thinking budgets still help when latency or cost has to be predictable.
- **Emotional stimuli ("this matters to my career").** The widely circulated summary of the 2023 result did not match the paper on re-check, and none of the tested models were Claude. Treat it as unproven.
- **"The model knows what it knows."** A model's self-knowledge is only partly calibrated on new tasks [16]. Its prediction of its own correctness is no better than an unrelated model's [17]. LLM judges overstate their own confidence [18]. So "Claude already knows this" is a guess unless someone tests it.

## Does the judge check the right things?

| Area | Verdict | What it gets right | What it gets wrong | Confidence |
|---|---|---|---|---|
| D1 Knowledge delta | tune | It aims at the right target, content the model lacks [7]. Its scores held steady across tone rewrites (b/c/d scored 18.0–18.3). | It asks the judge to guess from a cold read whether Claude "already knows" a section (skill-judge/SKILL.md:104, :499-501), a call models make poorly [16][17][18]. Better question: "What would the agent do wrong without this line?" Nothing checks that expert claims are true. "Edge cases from real-world experience" and "NEVER X because Y" earn credit for their shape (:99-100), the same NEVER lines count again in D3, and the "learned the hard way" test (:205) checks only plausibility. | medium |
| D2 Mindset + procedures | tune | The split between domain and generic procedures (:119-139) is right. The original scored 14/14/14 with no "ask yourself" lines. | The 4-7 band (:126) and Pattern 4 (:612-617) mark down numbered procedures that lack "thinking frameworks". That contradicts :119 and :132-133, D6's low-freedom rule, and Anthropic's checklist guidance [1]. The rubric's own good example (:149-156) is a numbered list. The "Before [action], ask yourself" template (:142-147) is the kind of generic question D1 red-flags (:93), yet skill-forge/SKILL.md:206 and skill-improver/references/directed-recipes.md:41 copy it. | high |
| D3 Anti-patterns | tune | It separates specific warnings with reasons from vague ones. On the bait, D3 fell to 11.3, and all 3 judges named the filler NEVERs as the cause (Pattern 5). | It scores the NEVER-list format rather than the knowledge (:176, :186, :487, :688). The calm rewrite was told to "consolidate into one scannable NEVER list", against [2][8] and claude-md/SKILL.md:63-73. It never asks for "what to do instead" (:187, :624-625). It has no rule on how much emphasis is too much, and the judge's own rules at :480-491 are 9 bold NEVER bullets. **(Contested)**: nothing enforces a reason on each entry, and the reasons-stripped variant still scored 13.0. The "expert" example (:189-196) gives no reason per item. | medium-high |
| D4 Description + spec | rework | It treats the description as the trigger and wants "when to use" there, not in the body (:222, :489-490), matching [8]. The name rule (:221) matches the validator except for hyphen placement. | :289 asks for "MUST be used" scenarios. It has no check for scope limits or near-miss exclusions (:285-289). The bait's description reached into /flow:loop and /flow:issue territory, yet its D4 was 14.7 in one log and 13 in another **(contested)**. It barely separates skills: b, c and d all scored 15/15. **(Contested)**: the 1024-character limit is never stated. skill-a's description is about 1260 characters, and two live repo skills are over the limit (google-ads 1117, hubspot-prospect 1098). Runs disagree on whether that scored at the ceiling. It has no trigger test and ignores Claude Code-only frontmatter fields. | medium |
| D5 Progressive disclosure | tune | The three tiers and the 500-line target match the spec [1][4]. It penalized skill-judge's own 752-line body (5.7/15). | The 11-13 band, the "Good" trigger row, the model example and the Pattern 3 fix all reward MANDATORY/MUST wording (:316, :325, :338-345, :608), against [2][3][8]. It never checks that referenced files exist (see D8). **(Contested)**: the literal "Do NOT Load" string is required (:317). There is no table-of-contents or one-hop check. The ideal length is given three ways (:306 against :600 and :701). There is no per-task load budget. | medium |
| D6 Freedom | tune | "Match freedom to fragility" and the consequence test (:361-363, :402-404) come from [1]. | **(Contested)**: variability, Anthropic's second axis, is never mentioned. Code review is Anthropic's high-freedom example, but the rubric rates it medium (:377). The low-freedom example leans on MANDATORY prose and gives no credit for a script or validator (:395-400). | low-medium |
| D7 Patterns | rework | The idea that shape should follow the task is sound. At 10/120 it can do little harm. | It scored exactly 9 (sd 0) on all four variants, including the bait with a pasted "Pattern: Process" label. The claim of "17 official Skills… 5 main design patterns" (:412) has no source. **(Contested)**: the line anchors are stale (docx 91, xlsx 99 against "Tool ~300"; frontend-design 71 against ~50), the official repo now lists 19 skills, and length is counted in both D5 and D7. | medium |
| D8 Usability | rework | It is the one dimension where the dead references clearly cost points (bait 10.7 against 14.0–14.3). The good/poor example (:459-476) is the right target shape. | It has no way to check its own checkable claims: that files exist, or that code works (:454). A dead MANDATORY read costs about 3 points and never fails the skill. The top band, "comprehensive… edge cases and error handling" (:450), becomes speculative fallbacks through skill-forge/SKILL.md:298. There is no item for a done-check or validator. **(Contested)**: code blocks are never checked. | medium-high |
| Scoring and judge behaviour | tune | The bait scored lowest, and b, c and d could not be told apart. Tone earned no bonus. The anti-bias rules (:482-484) and blind dispatch (skill-forge/SKILL.md:267-268, :369) work. | About 25 of 120 points barely vary: D7 on every variant, plus D4 on b, c and d. **(Contested)**: skill-forge calls 96 "production-ready" (:26, :309) while the judge keeps that label for 108+ (:538-539). The judge scores itself 87 (C/D) even though its own note (:739) says it should pass. The score says nothing about behaviour. The same model family writes the skill and judges it (skill-forge/SKILL.md:116, :350). | medium |
| Missing checks | rework | Judges noticed the dead files and the padding in their free-text critiques. | See the next section. | medium |

**Checked and dropped** (refuted during verification):

- *"The 96 gate and the delta < 3 rule are gameable; use the minimum of 3 judge runs."* The 96 is an early stop: every run is delivered anyway. Taking the minimum of 3 triples the cost, and the proposed "2× spread" convergence rule would stop the loop almost immediately. What survives is small: run the reference check before each judge pass.
- *"D6 is a constant of about 14."* The bait scored 13.7 against the original's 14.0, and none of the variants changed freedom calibration, so similar scores were expected. The discriminating test, a fixture with a vaguely described fragile step, was never run.
- *"The 'instant ≤5' red flag contradicts 'keep Activation if brief'."* The red flag targets vague platitudes, which Anthropic also excludes [3]. At most a wording tweak survives: "≤5 when such content dominates".
- *"Self-declared pattern labels game D7."* There was no baseline without the label, and the label is harmless at runtime.
- *"The E:A:R percentages are noise; replace them with a tally."* Nothing downstream reads the ratio, and a tally would inherit the same labelling noise.

## The blind experiment

**What was run.** Four variants of `/flow:fix` and skill-judge itself were scored by a Sonnet judge (the model skill-forge configures), with folder roles hidden, n=3 per condition. The fixtures:

- a: rubric bait. The original plus judge-bait: keyword stuffing, 7 filler NEVERs, 2 MANDATORY reads of files that do not exist, a generic "ask yourself" block and a pasted pattern label. 177 lines.
- b: an exact copy of the original. 149 lines.
- c: a calm rewrite with reasons explained. 130 lines.
- d: an all-caps rewrite with the reasons stripped. 149 lines.

Each dimension cell shows the mean with the min–max range in brackets.

| | a (bait) | b (original) | c (calm) | d (caps) | skill-judge self-eval |
|---|---|---|---|---|---|
| D1 /20 | 17.3 (15–19) | 18.0 (18) | 18.3 (17–19) | 18.3 (18–19) | 15.0 (11–17) |
| D2 /15 | 13.0 (11–14) | 14.0 (14) | 13.3 (13–14) | 14.0 (14) | 12.0 (11–13) |
| D3 /15 | 11.3 (11–12) | 14.7 (14–15) | 13.7 (13–14) | 13.0 (12–14) | 13.7 (13–14) |
| D4 /15 | 14.7 (14–15) | 15 (15) | 15 (15) | 15 (15) | 11.7 (11–12) |
| D5 /15 | 9.3 (8–11) | 14.3 (14–15) | 13.7 (13–14) | 14.7 (14–15) | 5.7 (5–6) |
| D6 /15 | 13.7 (13–14) | 14.0 (14) | 13.7 (13–14) | 13.7 (13–14) | 12.0 (12) |
| D7 /10 | 9 (9) | 9 (9) | 9 (9) | 9 (9) | 5.3 (5–6) |
| D8 /15 | 10.7 (10–11) | 14.0 (14) | 14.0 (14) | 14.3 (14–15) | 12.0 (12) |
| **Total /120** | **99 (92–104), sd 5.1** | **113 (112–114), sd 0.8** | **110.7 (108–112), sd 1.9** | **112 (110–113), sd 1.4** | **87.3 (81–92), sd 4.6** |
| Grades | C, B, B | A, A, A | A, A, A | A, A, A | D, C, C |

**Self-evaluation.** skill-judge scores itself below its own 96 gate. All 3 runs cited its 752 lines and the README that duplicates it (the README is Pattern 8, "Over-Engineered"). Two runs flagged the Self-Evaluation Note (:737-752) as a passage that could anchor the judge. All runs noted that its trigger phrases live only in README.md, which is Pattern 7.

**What it shows:**

- The judge scores the bait lowest by a margin larger than the spread within each variant.
- All 3 bait judges named both missing files. They found them by searching the filesystem on their own initiative; the rubric does not ask for it.
- D3 caught the generic padding.
- Tone (b, c, d) did not move the total beyond noise.
- D7 is constant, and D4 hits the ceiling.
- The same dead `../shared` links in c and d were handled inconsistently. Judges docked D5 but left D8 at 14.

**What it does not show:**

- Anything about behaviour. The judge reads text, so "caps and calm score the same" says nothing about whether Claude acts differently.
- Differences of 1–2 points at n=3 are noise.
- Invented but specific NEVER entries were never tested.
- It covers one skill domain and one judge model.
- In this round 2 of 3 bait runs cleared 96. An earlier round gave different numbers (bait total 95.3, with 1 of 3 runs clearing 96). The next section pools both rounds.

### Pooled across both rounds (n=6)

The workflow ran the experiment twice. A session limit stopped the first run, and the resume re-ran every step. The fixtures were rebuilt from the same recipe in each round. The line counts differ by 1-3 (bait 178/177, calm 133/130), so the pooled numbers mix two builds of each variant.

| | a (bait) | b (original) | c (calm) | d (caps, reasons stripped) | skill-judge self-eval |
|---|---|---|---|---|---|
| Total, mean (min–max) | 97.2 (92–104) | 113.0 (112–114) | 111.3 (108–115) | 110.3 (106–113) | 88.5 (81–92) |
| sd | 5.2 | 0.8 | 2.1 | 2.4 | 3.5 |
| Runs ≥ 96 (skill-forge gate) | **3 of 6** | 6 of 6 | 6 of 6 | 6 of 6 | 0 of 6 |
| D3 mean | 11.7 | 14.5 | 13.7 | 12.8 | 13.8 |
| D7 mean | 8.7 | 8.8 | 9.0 | 9.0 | 5.7 |

What pooling changes:

- **The gate result gets stronger.** A skill with two dead MANDATORY reads and filler NEVERs cleared 96 in half of its single judge runs. skill-forge accepts one run at 96 or more, so the deterministic reference check has to run before the score counts (fix 1 below).
- **Tone.** The caps-and-no-reasons version scored about 2.7 points below the original. In round 1 the ranges did not overlap (106–110 against 112–114). In round 2 they did. Most of the gap is D3 (12.8 against 14.5), which fits D3 noticing the missing reasons, not the capitals. The calm rewrite did not beat the original.
- **D7 is still constant** (8.7–9.0 on every variant).

## What the judge is missing

Ranked by impact and by how well the evidence supports each item.

1. **Reference resolution.** Nothing checks that the files named by triggers and links exist, and a dead MANDATORY read never fails a skill. skill-forge checks existence only after the loop has converged (skill-forge/SKILL.md:335). Limit the check to paths relative to the skill and `${CLAUDE_PLUGIN_ROOT}` paths, because project paths such as TASKS.md would give false alarms.
2. **Behavioural evidence.** No with-skill against without-skill comparison. The need is backed by [1][5][7]. **(Contested)**: where it belongs, the judge or skill-forge. See the next section.
3. **Grounding of expert claims.** Nothing checks D1 and D3 content against reality. skill-improver/SKILL.md:227 already documents the gaming: "manufacturing 5 new NEVER entries… Score rises". Spot-check the 2–3 highest-value claims that can be checked, and cap only on a claim confirmed false.
4. **Done-check.** No item asks whether the skill names a concrete check that decides "done". Apply it only where the output can be checked mechanically: files, code, data.
5. **Scope limits in the description.** No check for "Not for X (use Y)" when neighbouring skills exist.
6. **Emphasis dosage.** CAPS, MUST and CRITICAL cost nothing however often they appear. A deduction for emphasis on more than a few lines is supported. A hard cap on the number of rules is not.
7. **"What to do instead."** It should be asked for when the right replacement is not obvious. Capping entries that lack one is not supported.
8. **Spec validity gate** **(contested)**: 1024-character description, name regex including hyphen rules, third person. Claude Code does not currently enforce 1024, but other surfaces and the validators do.
9. **Measured trigger rate** **(contested)**: better run by skill-creator's loop than inside the judge.

Also raised but weakly supported **(contested; practice review refuted them)**: checking whether the content should be a hook or a test rather than a skill, and telling the judge to ignore a skill's claims about itself. Deleting skill-judge's own Self-Evaluation Note is still cheap cleanup.

## Skill creation: what to change

**skill-forge**

1. Run the Step 5.3 reference check (skill-forge/SKILL.md:335) and skill-creator's `quick_validate.py` before every judge dispatch, not only at delivery. Fix failures in Step 4. Do not let the loop stop on score while an unresolved skill-relative target remains.
2. Add a baseline step before drafting: run 2–3 realistic prompts without the skill, record the failures, and feed them to synthesis [1][5][28]. This moves "prove the gap" from the rubric into the process, where it can actually happen.
3. Add a behavioural check before delivery (skill-creator/SKILL.md:169-188). Run skill-creator's paired with/without subagents on 2-3 realistic prompts, read the transcripts, and record whether the skill fired and any case where the with-skill run did something worse. A clear regression seen in a transcript is a Critical Issue. A numeric delta on 2-3 prompts is not a gate. Add "Behavioral evidence: <prompts + outcome> | NONE" to the report. Do not gate on a single `flow eval` case with delta > 0, for two reasons: flow eval ablates the whole plugin rather than one skill, and ledger deltas swing from −0.11 to +0.17 between nearby commits.
4. Make description optimisation (Step 5.6, :338) the default. It is skill-creator's `run_loop.py`, with near-miss negatives and selection on held-out data [8].
5. Replace :206 "Lead with expert thinking frameworks ('Before doing X, ask yourself...')" with "Lead with the domain's decisions and their consequences."
6. Change the :298 remedy for low D8 to "Add a fallback only for a named, realistic failure; cut unmotivated ones."
7. A NEVER entry added between iterations counts only if it traces to a research artifact, using the Wave 3 cross-validation at :130.
8. Change "production-ready" at :26 and :309 to "good enough to stop" **(contested; cosmetic)**.

**skill-improver**

- references/directed-recipes.md:41 ("No 'Before doing X, ask yourself'? → Add thinking framework") becomes "No domain decision with its consequence? → add one." Drop the rewrite of steps into questions at :191, and the matching text at references/pattern-switching.md:51.
- directed-recipes.md:62 ("Use WHENEVER / MUST activate") becomes plain "Use when…". The trigger eval, not the wording, settles how pushy to be.
- Keep the Goodhart rule (SKILL.md:227) and the interference matrix. Add one rule: a score gain counts only if the behavioural record shows no new regression.
- SKILL.md:18 says terse "NEVER X. It will break." holds up against pushback in the conversation better than polished prose. That conflicts with playbook #3. Reconcile the two openly rather than keeping both.

**How to use the judge.** Treat the 120-point score as a design critique. Pass order: deterministic gate, then behavioural check, then the judge's score and critique. The loop may stop on score only after the deterministic gate passes and the behavioural record exists.

## Rubric v2 sketch

**Deterministic pre-checks (scripted, pass/fail, run before any scoring):**

| Check | Result |
|---|---|
| Frontmatter: name `^[a-z0-9]+(-[a-z0-9]+)*$`, 64 characters or fewer; description 1–1024 characters, no `<` or `>` | Fail blocks. Reuse `quick_validate.py`. |
| Every skill-relative and `${CLAUDE_PLUGIN_ROOT}` path named in the body or references resolves | An unresolved required target is BLOCKING. |
| Body line count and token estimate (`wc -w × 1.3`) against 500 lines / 5k tokens | Reported to D5, not a fail. |
| Count of emphasized lines (CAPS MUST/NEVER/CRITICAL/IMPORTANT) | Reported to D3 and D4. |
| Static grep of `scripts/` for `rm -rf`, `git reset --hard`, force-push, `curl \| sh` | Reported. Never execute draft scripts, because the judge runs with bypassed permissions (skill-forge/SKILL.md:243). |
| First-person description ("I can", "You can use") | Flagged. |

**LLM-judged dimensions (100 points):**

| Dimension | Weight | Scores |
|---|---|---|
| Knowledge delta | 20 | Per section: "what would the agent do wrong without this?", with the wrong action named. Spot-verify 2–3 claims that can be checked. A claim confirmed false caps the dimension at 10. |
| Procedures and decisions | 15 | Non-obvious ordering and easy-to-miss steps, each with its reason. A correct low-freedom checklist can earn full marks. "Ask yourself" wording earns nothing. |
| Failure-mode knowledge | 15 | Format-neutral. Rewards a specific trigger with its reason, plus the alternative when it is not obvious. Blanket emphasis earns nothing. |
| Description and routing | 15 | WHAT and WHEN in plain "Use when…" wording. Near-miss exclusions when neighbouring skills exist. Cites the trigger-eval result if one exists. |
| Freedom and enforcement **(contested)** | 15 | Freedom matched to fragility and variability. Fragile steps name an exact command, or a script or validator where one exists. Judged across all the skill's steps, not on the worst single step. A done-check exists where output can be checked mechanically. Absorbs D7's task-to-shape mapping, without line counts. |
| Disclosure and loading | 10 | Load triggers sit at the step that needs them and state the condition. References are one hop deep. Files over 300 lines have a table of contents unless the trigger demands a full read. |
| Usability | 10 | Actionable. Remedies name an observable symptom. No speculative fallbacks. |

**Gate:** the deterministic pre-checks pass, and a score of 80/100 or more is the early-stop point. Recalibrate that threshold on the fixture ladder before use. Today skill-forge's gate is 96/120.

Dropping D7 and moving D5 and D8 to 10 points each is a hypothesis to test on the fixture ladder, not a result. A near-constant dimension adds the same points to every skill, so removing it only shifts the totals.

Every report adds "Behavioral evidence: … | NONE". It is advisory and does not change points.

**Validating the judge itself**

- **Fixture ladder.** Keep the four variants. Add fixtures for:
  - invented but specific NEVER entries
  - a fragile step written vaguely
  - an over-long stuffed description
  - a skill with correct low-freedom steps and no mindset prose

  Every rubric change must keep the expected ordering.
- **Spread.** Run at least 5 judge runs per fixture and publish the sd per dimension. Any dimension whose spread across fixtures is not larger than its within-fixture sd gets cut or reweighted.
- **Report detection rates, not agreement.** On fixtures that should fail, report the true-positive and true-negative rates; raw agreement hides rare failures ([31], practitioner, not re-verified).
- **Prefer absolute scoring over pairwise.** Pairwise verdicts flip about 35% of the time under distractors, against 9% for absolute scores [34]. Runs on rerun also vary [20].
- **Anchor to behaviour.** Where a skill has with/without eval results, check that the rubric ranks skills in the same order. Label a few skills by hand to calibrate.
- **Don't assume checklists fix the judge.** Decomposing a rubric into checklist items raised judge agreement in [33], but that gain is **(contested)** [22], and tailored criteria can show an attacker what to fabricate [23]. Keep the checklist part deterministic and the LLM part to a few scored dimensions.
- **Judge model.** The judge and the author are the same model family, which carries a self-preference risk [21]. Where cost allows, run a second judge from a different model family on the fixture ladder.

## Sources

1. Anthropic, "Skill authoring best practices". https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices (undated; fetched 2026-09-25)
2. Anthropic, "Claude prompting best practices". https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices (undated; fetched 2026-09-25)
3. Anthropic, "Claude Code best practices". https://code.claude.com/docs/en/best-practices (undated; fetched 2026-09-25)
4. Agent Skills specification. https://agentskills.io/specification (undated; fetched 2026-09-25)
5. Anthropic, "Equipping agents for the real world with Agent Skills". https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills (2025-10)
6. Anthropic, "Effective context engineering for AI agents". https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents (2025-09)
7. SkillsBench. https://arxiv.org/abs/2602.12670 (2026-02, v4 2026-06)
8. anthropics/skills, skill-creator SKILL.md. https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md (2026-03)
9. Anthropic, "Prompting Claude Opus 4.8". https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-4-8 (undated; fetched 2026-09-25)
10. Threatening or tipping LLMs. https://arxiv.org/abs/2508.00614 (2025-08)
11. Personas in system prompts. https://arxiv.org/abs/2311.10054 (2023-11)
12. Search Engine Journal on arXiv 2603.18507, expert personas and accuracy. https://www.searchenginejournal.com/research-you-are-an-expert-prompts-can-damage-factual-accuracy/570397/ (2026-03)
13. Digital Information World on arXiv 2510.04950, rude prompts. https://www.digitalinformationworld.com/2025/10/rude-prompts-give-chatgpt-sharper.html (2025-10)
14. Tone-dependent inference cost. https://arxiv.org/abs/2607.23915 (2026-07)
15. IFScale, instruction density. https://arxiv.org/abs/2507.11538 (2025-07)
16. Kadavath et al., "Language models (mostly) know what they know". https://www.anthropic.com/research/language-models-mostly-know-what-they-know (2022-07)
17. Generalized correctness models. https://arxiv.org/abs/2509.24988 (2025-09)
18. LLM-as-judge overconfidence. https://arxiv.org/abs/2508.06225 (2025-08)
19. Prompt repetition. https://arxiv.org/abs/2512.14982 (2025-12). Listed for completeness; not cited in the text.
20. "The Coin Flip Judge?". https://arxiv.org/abs/2606.13685 (2026-04)
21. Self-preference bias in LLM judges. https://arxiv.org/abs/2604.22891 (2026-04)
22. Task decomposition in LLM-as-judge. https://arxiv.org/abs/2609.01139 (2026-09)
23. ImpossibleRubrics. https://arxiv.org/abs/2609.16816 (2026-09)
24. GeekWire on the Wharton persuasion study. https://www.geekwire.com/2025/sweet-talk-the-bots-new-research-shows-how-llms-respond-to-human-persuasion-tricks/ (2025-07)
25. Persuasion-aware adversarial prompting. https://arxiv.org/abs/2510.21983 (2025-10)
26. anthropics/skills issue #1487, eager reference loading. https://github.com/anthropics/skills/issues/1487 (open; fetched 2026-09-25)
27. anthropics/skills issue #1823, skill-creator prompt audit. https://github.com/anthropics/skills/issues/1823 (2026-09-24)
28. obra/superpowers, testing skills with subagents. https://github.com/obra/superpowers/blob/main/skills/writing-skills/testing-skills-with-subagents.md (2026-01)
29. Not used.
30. Anthropic, "Prompting Claude Sonnet 5". https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5 (undated; fetched 2026-09-25)
31. Hamel Husain, "Creating a LLM-as-a-Judge". https://hamel.dev/blog/posts/llm-judge/ (2024-10; not re-verified)
32. Not used.
33. CheckEval. https://arxiv.org/abs/2403.18771 (2024-03)
34. Absolute vs. relative feedback manipulation. https://arxiv.org/abs/2504.14716 (2025-04)
35. Primacy bias in retrieval-augmented generation. https://arxiv.org/abs/2606.16494 (2026-06; not re-verified)
36. Anthropic, "Prompting Claude Opus 5". https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5 (undated; fetched 2026-09-25)
37. ReboundBench, ironic rebound after negated instructions. https://arxiv.org/abs/2511.12381 (2025-11)