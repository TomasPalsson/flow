# /flow:moonshot: why the output was lame, and the rewrite (2026-11-25)

Ask: "it hasn't been working well recently for any ideas"; research how others get usable results; evaluate on the
news repo. Flow 0.14.0. Five runs on news, each a subagent following the skill as written, with the user reacting
between them.

## What was wrong

Rounds 1-7 of the forge (file 27) tuned the skill on a judged ambition score: "ship only 9-10", a make-it-a-10 pass,
scope rulings breakable, "feasibility never shrinks a bet", ideas already wanted by the owner excluded. Run as
written on news (a private, single-reader hub) it recommended "Iceland's complete newsroom": read every public
record of the state and report in public. The smaller private version it grew from was the one closer to useful.
The scale also rated the origin case (replace CEF with an own renderer: same app, same users) at about 6.

## The five runs and the user's reactions

| Run | Skill state | Pick for news | User |
|---|---|---|---|
| 0 | as shipped (0.13.1) | public national newsroom from state records | (the complaint that started this) |
| 1 | grounded: rulings as inputs, ordinary-day test, 20-minute probe, no scores | replace the 27B model with a small one trained on its call logs | "I want something cool and fun not these lame ass [ideas]" |
| 2 | cool and fun: demo first, grin test, lame list, raw material, lenses, teasers | site as a TV channel; a Connections puzzle from his news; call in to his radio show | "Tv one sounds good", rerun |
| 3 | same, repeat round | 19:00 bulletin; quiz against the host; scorer as a puppet (drawn in the retired poster look) | "You're still with the old look???? Why?" |
| 4 | + what is current first, look read from the live stylesheet, reference screenshot | Hub TV; The Gallery (control-room wall); Beat the Machine | "these ideas are very good", "aren't confident enough ... a billion dollars and infinite time" |
| 5 | + billion-dollar premise, tonight's version / full version, blow-up pass, storyboards | Hub TV as a station with one viewer; Gallery as a full control room; a league against past selves | "Ok let's merge" |

Lessons, in the order they were learned:
- "Too grand to build" was the wrong reading. The grounded rewrite produced the dullest result of all. The owner's
  word was lame: worthy, earnest, infrastructure.
- Demo-first cards and a banned default kit (coverage, verification, graph, dashboard, platform, a number going up)
  changed the kind of idea at once. Delight signals (what the owner built that nobody needed) and raw material
  (archive, marks, voices, hardware) are what make an idea this project's own.
- Teasers made from real data let the owner react in seconds, and exposed a miss no text would have: the wrong look.
  DESIGN.md described a look a later ruling had retired; the live stylesheet is the source.
- Fun alone came out small. Size is added after fun, as a blow-up pass on an idea already liked, and it scales the
  show for the owner, never the audience or the worthiness. A storyboard carries the full version.

## Research basis (web, 2026-11-25; UNVERIFIED items left out)

- Ideas rated at the idea stage lose their lead when executed: 43 experts built assigned ideas and LLM ideas fell
  more on every measure, flipping the ranking (https://arxiv.org/abs/2506.20803).
- LLM idea pools are less varied than a group's unless pushed (https://arxiv.org/abs/2402.01727); asking for several
  answers with likelihoods widened range 1.6-2.1x (https://arxiv.org/abs/2510.01171); pairwise comparison resolves
  finer than absolute scores (https://arxiv.org/abs/2607.15766).
- Skills people report using show several candidates and let the owner pick, with the owner's rulings as inputs:
  mattpocock improve-codebase-architecture, obra/superpowers brainstorming ("options steer"), gstack office-hours.
- Agent-built rewrites that worked had an oracle before they started: Anthropic's C compiler (GCC), JustHTML port
  (html5lib-tests), FastRender (spec and golden screenshots). Kept in the template for bets that replace a part.
- Bondzio's original post could not be found; the only public trace of the prompt is matteodante/skills PR #2.

## The skill now

Premise: a billion dollars and infinite time, cool and fun, for this owner. Brief: what is current, delight
signals, raw material, rulings, constraints. Generator: three typical pitches set aside, 12 demos across nine
lenses, keep 5, blow each up three times; cards carry tonight's version, the full version, the climb, the price in
people. Skeptic kills the lame, false, bundled, timid and other-product cards and amends up. Paired comparison on
the grin test, no scores. Teasers of tonight's version from real data in the live look, with a storyboard of the
full version; the owner picks. recon.mjs: manifests up to three levels down, data-only directories last, a
priced-out section (12 tests).

## Open

- No run had an Agent tool: the cold generator, independent skeptic and paired comparison ran only as same-model
  fallbacks. A real session with subagents is untested.
- One repo, one owner. Steps 4-6 (MOONSHOT.md, seed, re-entry) not run on the new shape.
- "Never bundle" pulls against the blow-up pass (the full Hub TV absorbs the other two as rooms and programmes).
- No rule yet for staged content in storyboards beyond labelling it drawn.
