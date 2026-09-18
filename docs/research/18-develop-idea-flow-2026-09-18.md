# `/flow:develop-idea` → `/flow:prep` — wiring a sliver into the interview (2026-09-18)

Synthesis of a five-angle research sweep (`raw/develop-idea/sweep-report.md`, 45 references, about 20
claims re-fetched and verified) plus an in-tree read of `skills/develop-idea/SKILL.md`, `skills/prep/SKILL.md`
and `skills/spec/SKILL.md`. Builds on `13-flow-prep-2026-09-07.md` (the prep design), cited, not repeated.
**PRIMARY** = the raw report's **H** marks (re-fetched and matched) or an in-tree path read for this doc;
**SECONDARY** = the raw report's **M** marks (a primary source not re-fetched, or two angles agreeing);
**UNVERIFIED** = the raw report's **L** / **M-L** marks (one angle, a secondary source, or the raw report's
own synthesis). Citations point at the raw report's numbered references (`[N]`) or an in-tree path.

## 1. BLUF

1. **A sliver needs a divergent stage the user closes, before prep's convergent interview.** An interview
   converges on an intent that must already exist (UNVERIFIED — the raw report's own reading, bottom line
   point 2). "I don't know what it is yet or who it's for" has no intent to converge on.
2. **Only BMAD, of the nine frameworks and skills surveyed, separates problem-divergence from
   requirements** (UNVERIFIED — the raw report's classification, §1 summary; BMAD's brainstorm → brief →
   PRD artifacts themselves are PRIMARY/SECONDARY [5][7]). Interview-first tools (grill-me, interview-me,
   GSD, Anthropic's "interview me") and spec-first tools (spec-kit, Kiro, OpenSpec) assume the idea
   already exists.
3. **Guesses belong to convergence, not divergence.** interview-me attaches its own guess to every
   question (PRIMARY [19]) and grill-me a recommended default (SECONDARY [17][18]). Ideas formed with a
   model's finished-looking output were less distinct across users and less owned by them (PRIMARY [22]),
   and AI help early in ideation anchored people on familiar products (UNVERIFIED [24]); the step from
   there to "no guesses while diverging" is the raw report's synthesis (UNVERIFIED, §2). That is why
   `develop-idea` and `prep` stay two skills: opposite postures on the same axis.
4. **An idea is ready for a spec when it has eight fields**: problem, whose problem, current alternative,
   desired outcome, riskiest assumption, appetite, no-gos, rabbit holes. Each field has its own source in
   raw §3 (Shape Up's pitch ingredients are PRIMARY [30]; PR/FAQ's "top three reasons this will not
   succeed" is PRIMARY [32]). The readiness rule itself, and the finding that no agent framework in the
   set records appetite or a riskiest assumption, are the raw report's own reading (UNVERIFIED). flow's
   seed PREP.md carries both.
5. **The hand-off is a small file on disk with the user's verbatim words, not a transcript.** Sessions
   keep no memory by default (UNVERIFIED [41]), and flow ends every `/flow:next` turn with a `/clear`
   recommendation (PRIMARY, in-tree: `skills/next/SKILL.md:3,12`), so a conversation-only hand-off would
   not survive here. Keeping the user's own words is the raw report's synthesis of [22] and [23]
   (UNVERIFIED, §2 point 1).
6. **flow already had both halves and no wire between them.** `develop-idea/SKILL.md`'s "Know when to hand
   off" pointed at `/flow:spec` and nowhere else in flow (PRIMARY, in-tree); `prep/SKILL.md` Step 0 and
   `spec/SKILL.md` §0 both stopped a sliver with three questions and named no tool that grows one.
7. **The fix reuses prep's own template, lint and router state — zero new router state.** A seed PREP.md
   is a normal `Questions: 0 of 12` file; `flow next --json` already routes any such file to
   `prep-interviewing` → `/flow:prep` (PRIMARY, in-tree `bin/lib/router.js` `prepState`; confirmed by
   hand-building one seed, linting it OK and routing it).

## 2. What flow had

The wall sat in three places, and none of them named a way through. `develop-idea/SKILL.md`'s "Know when to
hand off" routed every bullet to a chat skill (`scrutinize-idea`, `grill-me`, `brainstorm`) or straight to
`/flow:spec`; "software to build here, decisions still open" had no bullet, so it either hit `/flow:spec`'s
own guard early or stayed a transcript a `/clear` would erase. `prep/SKILL.md` Step 0's empty-idea rule
("ask for it… nothing below runs on an invented problem statement") had no branch for a user who *can't*
answer yet — it could only ask again. `spec/SKILL.md` §0 carried the identical gap: "ask for (1) the
problem, (2) whose, (3) what they do today instead — and stop," with no name to give someone with none of
the three. All three guards are right to stop and ask — a problem stated through its solution isn't ready
(SECONDARY [34]) — but repeating the same convergent question is not a divergent stage.

## 3. The design

**The seed PREP.md.** `/flow:develop-idea` ends its divergent stage — on the user's explicit yes to a
restatement, never on the model's call — by writing a `.specs/NNN-<slug>/PREP.md` shaped exactly like one
`/flow:prep` writes before its first question: same template, same lint, same
`Questions: 0 of 12 · Route: dispatch · Status: interviewing` header, plus one line under Gathered —
`Seed: "<user's words>" — user, via /flow:develop-idea`. `prep-lint` accepts that extra line unchanged, and
a seed is just a PREP.md at `Questions: 0`, which `flow next --json` already resolves to
`prep-interviewing` → `/flow:prep`. The rules live in `skills/develop-idea/references/flow-seed.md`, loaded
only when a seed is about to be written.

**Field mapping.** The eight fields from raw §3 each land in one slot:

| Field | PREP.md slot |
|---|---|
| The user's sliver, verbatim | `Seed:` line under Gathered |
| Problem, without the solution | `A-01` |
| Whose problem, as a situation | `A-02` |
| Current alternative | `A-03` |
| Desired outcome / success signal | `A-04` |
| Riskiest assumption | `A-05`, `confidence: low` unless there's evidence |
| Appetite | `A-06` |
| No-gos | `## Not this` |
| Rabbit holes / open unknowns | `## Open`, max 3 |

Every `A-NN` is `unconfirmed` — a hypothesis for prep to confirm or correct, never a locked decision: only
an explicit yes locks (PRIMARY [19]), and "agreed, agreed, agreed" is grill-me's own named failure (PRIMARY
[16]). `## Decisions`, `## Discretion` and `## Verify` stay empty, and only the user ends the divergent
stage (PRIMARY [8]: BMAD's brainstorm continued "until the user indicates they want to move to convergent
phase" until a refactor dropped the rule). An unreached field is written `unknown — prep asks`.

**The prep changes.** Four narrow additions to `prep/SKILL.md`: (1) a bare `/flow:prep` first looks for an
unfinished interview, including a seed, before asking for an idea (more than one → list and ask); (2) the
ratchet starts at the first answer, so a `Questions: 0` file's provisional `Route:` is re-derived, never a
verdict; (3) a seed's `unconfirmed` `A-NN` lines and pre-filled `## Not this` are read back as one block with
one ask ("reply with what's wrong, or 'right'"), counted as Q1, never re-asked open — the shape of GSD's
assumptions mode, which asks only for corrections (PRIMARY [3]). The first eval run showed why the "one
block" wording matters: told only to "read back" the seed, one of two runs asked three separate
confirm-or-correct questions in one message; (4) the `Seed:` line survives every rewrite.
`prep-template.md` documents the line.

**The guards.** `spec/SKILL.md` §0 and `prep/SKILL.md`'s empty-idea rule each gained one sentence naming
`/flow:develop-idea` in the stop message, never invoking it: `develop-idea` is a live conversation, and
`/flow:spec`'s guard also holds under `--unattended`; the interface between these skills is a file on disk
(in-tree: `13-flow-prep-2026-09-07.md` §1 point 7).

**The evals.** `routing-develop-idea` checks a sliver with no clear problem or user routes to
`develop-idea` and to no other hub skill; `pipeline-prep-resume-seed` checks a bare `/flow:prep` against a
seed PREP.md resumes it instead of asking for the idea. `develop-idea` was added to every existing hub
case's `no-other-hub-skill` negative list.

## 4. Rejected

- **Merging `develop-idea` into `prep`.** Opposite postures on one axis: `develop-idea` names gaps and never
  fills them with its own vision (in-tree, discipline 5); `prep` states a hypothesis with every question
  (in-tree, rule 2). Offering hints rather than solutions early is a review's recommendation (UNVERIFIED
  [24]). One skill holding both postures needs a mode switch mid-session — a worse interface than two
  skills and a file.
- **A new `IDEA.md` file type plus router state.** A second artifact for one hand-off, when a seed at
  `Questions: 0` is already a shape the router and `prep-lint` handle. The raw report recommends a small
  file the next stage reads and only asks corrections about (UNVERIFIED synthesis, raw §4), which a seed
  already is.
- **No file at all, hand off by conversation.** A transcript hand-off loses the reasoning behind decisions
  and invites re-asking (UNVERIFIED [41][45]), and flow's `/clear` after every turn would erase it.
- **A checklist interview to fill all eight fields.** BMAD issue #1249: once its divergence guardrails were
  folded into one "Continue" option, a user wrote "I thought the agents were bullying me to wrap it up"
  (PRIMARY [8]). An unreached field is written `unknown — prep asks`, not interrogated into existence.

## 5. Gaps

From the raw report's own Gaps section: no controlled study shows "diverge, then converge" gives *better*
ideas in an LLM pipeline, only indirect support; only one of nine LLM-ideation papers was re-fetched, and
several arXiv IDs carry drift risk; GSD's `questioning` reference and Osmani's `idea-refine` skill were
never researched; every hand-off-failure source is a secondary practitioner piece, not an empirical
evaluation.

Specific to this wiring, measured on 2026-09-18 (claude-sonnet-5, haiku judge):

- `routing-develop-idea` 3/3 with the plugin (0/3 without); `routing-spec`, `routing-prep` and
  `routing-scrutinize-idea` still 1/1 with `develop-idea` in their negative lists.
- `pipeline-prep-resume-seed`, five rounds: (1) 1/2 — "read back" had no shape, and one run asked
  three separate confirm-or-correct questions; (2) after the one-block rule, 2 of 3 runs did the
  read-back, but a tangled judge prompt scored all three FAIL; (3) with a simpler judge, 0/3 for a real
  reason — the fixture had no `Seed:` line and the resume rule never said how prep recognises a seed, so
  every run fell back to one question per line; (4) with the `Seed:` line named as the marker, in the
  fixture, and the read-back made rule 1's one exception: 3/3; (5) 3/3 again, with a file check that
  the `Seed:` line survives prep's rewrite.
- develop-idea's Commit stage, played by Sonnet agents in scratch repos against the real skill files:
  software + "yes" wrote a lint-clean seed that `flow next` routes to `/flow:prep` (2/2); an essay idea
  wrote no seed (1/1); "sounds good" wrote a seed on the first prose (1/1 wrong) and wrote nothing on
  the yes-gate prose (3/3 right).

Still owed: one real `/flow:develop-idea` → seed → `/flow:prep` session with a human, not an agent
playing the user.

## References

Full list of 45 in `raw/develop-idea/sweep-report.md`. Cited here: [3] GSD user guide (`discuss-phase`
assumptions mode, `D-NN`); [5] BMAD `bmad-product-brief`; [7] BMAD brainstorming session; [8] BMAD issue
#1249 (rushing failure); [16] Pocock `grill-me` (passivity failure); [17][18] Pocock on grill-me's
recommended answers; [19] Osmani `interview-me` (hypothesis per question, explicit-yes rule); [22]
Anderson, Shah & Kreminski, C&C 2024 (homogenization, reduced ownership); [23] AI-assisted ideation timing,
CHI 2025; [24] Li et al., ideation review 2025 (hints not solutions, anchoring); [30] Shape Up, "Write the
Pitch"; [32] Working Backwards PR/FAQ; [34] Maurya (problem stated without the solution); [41] Augment
(stateless sessions); [45] MindStudio (context-dump fallacy).

In-tree: `skills/develop-idea/SKILL.md` ("Know when to hand off", discipline 5),
`skills/develop-idea/references/flow-seed.md`, `skills/prep/SKILL.md` (Step 0, the ratchet paragraph,
Step 2), `skills/prep/references/prep-template.md`, `skills/spec/SKILL.md` (§0), `skills/next/SKILL.md`,
`bin/lib/router.js` (`prepState`), `evals/routing-develop-idea/`, `evals/pipeline-prep-resume-seed/`,
`docs/research/13-flow-prep-2026-09-07.md`.
