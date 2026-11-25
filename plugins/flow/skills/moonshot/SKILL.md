---
name: moonshot
description: "Proposes ONE moonshot for an existing repo: the billion-dollars-and-infinite-time version of the project, cool and fun, that the owner would love to show someone and never asked for because in human time it looked too expensive (our own engine, a game, an instrument, something alive or wired to the hardware in the room). Reads the project for what the owner enjoys and the raw material only it has, pitches demo-first, makes rough teasers from real data so the owner picks from things they can look at, writes MOONSHOT.md as 4-6 phases each with a kill check, and seeds phase 1 into /flow:prep. Use when the user asks for a moonshot, 'what would you rebuild with unlimited resources', 'the 10x version', 'the ugliest part of this stack', 'we have tweaked X for months', or 'let it rip'; also when a MOONSHOT.md exists and its current phase shipped. Not for a list of ideas (flow-extras:brainstorm), growing the user's own idea (flow:develop-idea), judging an idea (flow-extras:scrutinize-idea), or a cleanup of one shipped spec (flow:flow-deepen)."
argument-hint: "[the part of the stack to rebuild, or a path]"
user-invocable: true
---

# Moonshot

A moonshot is **the version of this project the owner would be dying to show someone, and never asked for because
in human time it looked too expensive.** The origin case: an app embedding CEF (all of Chromium) spent months on
small tweaks; the move was writing its own renderer. "We wrote our own renderer" is a thing you tell people. "The
agent could always build something like this. It just never suggested it, because in human time it looked too
expensive." Labour is free now: agents can build the engine, the runtime, the game, the instrument, the model
trained on the project's own data, the thing wired to the hardware in the room.

**A billion dollars and infinite time.** That is the premise: pitch what a studio with that budget and no
deadline would build on top of this project, not what fits in a sprint. The billion is the price in people that
kept it unwritten; agents pay it in labour, so no real money is spent and the owner's money rulings still hold.
A pitch a keen person could finish in a month is **timid**: it becomes phase 1 of something bigger. Every card
carries two scenes: **tonight's version** (small, already fun, what the teaser shows) and **the full version**
(the scene a year in, the one that makes a professional in that field jealous). The bet is the full version.

**Cool and fun is the bar, and size serves it.** Scale the spectacle, never the worthiness or the audience: a
bigger show for this owner, not coverage, compliance or strangers. A moonshot the owner reads and thinks "sure, worthy" has failed, however sound. Five
ways it goes lame, all of them a model's default:
- **The worthy one.** Complete coverage of something, verification, auditing, trust, a pipeline that is more
  correct. Sound, earnest, nobody opens it twice.
- **The cleanup.** A slimmer image, a deduplicated helper, a faster build. A chore with a big name.
- **The timid one.** A fun page, a nice feature, a weekend toy. Good, and far too small: it is tonight's version
  of something, so say what.
- **The bundle.** A graph, a twin, an agent loop and a platform stacked together, opening with plumbing.
- **The other product.** Something bigger for strangers (a private reader becomes a public newsroom). It wins with
  a judge and the owner never builds it, because it is homework for people they never mentioned.

So: **one bet, for this owner, whose demo makes them grin.** No scores out of 10 anywhere: ideas rated at the idea
stage lose their lead once built (https://arxiv.org/abs/2506.20803), so the skill shows a teaser and the owner picks.

Six words carry the method; use them in everything you write:
- **the demo**: what the owner sees, hears or touches in the first 30 seconds, written as a scene, not a feature
  list. It is the first line of every card. If the demo is a dashboard, a report, a number going up, or "it is now
  more accurate/complete/reliable", the card is lame: replace it.
- **the grin test**: would the owner show this to a friend tonight, unprompted? Would the friend ask how it works?
  This is the one question every pass asks. Useful is welcome; useful and dull does not pass.
- **raw material**: what this project has that nobody else has: its archive, the owner's own marks and history,
  the machine and hardware it runs on, its local models, its voice, its odd side features. Cool comes from using
  these in a way only this project could, not from a generic idea with the project's name on it.
- **the price that hid it**: why nobody wrote it down ("that is a whole team", "that is a year"). Every card says
  what the full version would have cost in people and years ("a broadcaster's engineering floor", "a games
  studio for three years"). An afternoon is a task; a month is timid; the answer should make you wince.
- **the monkey**: the one assumption that, if false, kills the bet (usually: is it actually fun, or does the hard
  part work at all). Phase 1 tests it. Everything easy is **the pedestal**.
- **the teaser**: a rough slice of the demo, made now, in this session, from the project's real data: a page to
  open, a clip to play, a picture. Showing beats describing; the owner picks from things they can look at.

**Where cool comes from.** The generator works through these lenses; each is a way agent labour turns a project
into a showpiece:
make it **alive** (it moves, updates, reacts while you watch) · make it **physical** (a screen on the wall, a
printer, a speaker, a light, the home server's own hardware) · make it a **toy or a game** (something to play, a
streak, a duel, a puzzle made from the project's own content) · give it a **voice or a character** · **absurd
scale** (all of it at once, every one ever, a wall of them) · a **time machine** (replay any day, run it forward) ·
make the **invisible visible** (what the models are doing, what the data looks like as a place) · the **flex**
(our own engine, model, renderer, format, built from scratch because we can) · **only here** (trained on the
owner's own taste, voice, history).

**The owner's rulings still hold.** Privacy, money, safety, who it is for: honour them. Fun for this owner, not a
launch. If the coolest idea needs a ruling changed, say so on that one card, show it last, do not recommend it.

`${CLAUDE_PLUGIN_ROOT}` is the flow plugin root. Run scripts with `node`, all paths absolute.

## Steps

**0. Where you are.** Run `flow next --json` and note `state` and `stealth.active` (no `flow` on PATH: you can
still write MOONSHOT.md; skip Step 5). MOONSHOT.md sits at the repo root, or at `.specs/MOONSHOT.md` when stealth is
active. If one exists, go to Step 6. Done when you know the state and whether this is a first run or a re-entry.

**1. Read the project for what is fun in it.** Read [`references/recon.md`](references/recon.md) before this
step. Read the owner's docs (README, PROGRESS, plans, rulings, specs, IDEAS) and run
[`scripts/recon.mjs`](scripts/recon.mjs) as
`node ${CLAUDE_PLUGIN_ROOT}/skills/moonshot/scripts/recon.mjs --repo <root> [--focus <path>]`
(`--help` for the flags; do not read its source). When the user named the part, recon still runs, focused on it.
Write the **brief**, half a page, no ideas in it:
- **what is current**: the surface the owner is working on now, what it replaced, and its look (stylesheet path,
  fonts, colour tokens) read from the code, not from design notes;
- what the project is and who uses it, in the owner's words, with the quote;
- **delight signals**: what the owner built that nobody needed (side features, easter eggs, a lab, a custom look,
  anything named "fun"), and what they said they like or hate. This is the taste the cards must hit;
- **raw material**: the archive and its size, the owner's own data (marks, votes, history), the hardware and
  models on hand, existing voices, renderers, feeds, with paths and numbers;
- the rulings, as a list (all honoured);
- 2 to 4 **accepted constraints and priced-out wishes** with receipts (`path:line`), each named as what the
  product cannot do. They are material for the generator, not the required starting point.
Done when the brief has at least 3 delight signals and 5 pieces of raw material with numbers. "No moonshot found"
is not an outcome of this step; every project has raw material.

**2. Generate pitches cold.** Read [`references/candidates.md`](references/candidates.md); it holds the
generator, skeptic and comparison prompts, the card fields and the lame list. Spawn one fresh subagent on the
strongest model with the brief only, no repo access. It writes 12 one-line demos across the lenses, keeps the
5 it would most want to see built, blows each one up to its billion-dollar full version, and writes their cards. No subagent tool in this session: generate in a separate
pass from the brief text alone, and say on the cards that they are not cold. Done when 5 cards came back, each
with both scenes (tonight's version and the full version), a price that makes you wince, and at least two pieces
of raw material by name.

**3. Ground, attack, make teasers, let the user pick.** For each card: open the code and data it names, check the
raw material is really there in the amount claimed, and fetch the primary source of every outside part it leans on.
Mark anything unchecked UNVERIFIED. A thing that does not exist yet is not a reason to drop a card: agents build
it, and it becomes the monkey. Then:
- **Skeptic.** One subagent (`sonnet`) with the cards, your notes and the brief. It may only kill or amend. It
  kills the lame (see the lame list), the false, the bundles and the other products; it amends a card toward the
  bigger and more fun version of itself, never toward the safer one, and sends every timid card back up. No subagent tool: run it as a separate pass and say so.
- **Compare.** A fresh subagent compares the survivors in pairs, both orders, on the grin test. No scores.
- **Teasers.** For the top 2 or 3, make the teaser of tonight's version, and under it on the same page a
  **storyboard** of the full version: three or four still frames in the project's current look, each one scene
  from a year in, captioned with what is happening. About 20 minutes each, from real repo data, written to a
  scratch directory, spending no money and sending nothing outward. A static page, an audio file, an image, a
  terminal recording. Rough is fine; invented content is not. Where you did by hand the part the bet says a
  machine will do (picked the puzzle's groups, wrote the schedule), say so on the teaser: that part is the monkey.
  No teaser possible: say why and describe the scene instead.
Show at most 3 survivors, each as the lines in candidates.md (Presenting survivors), teaser path first. Recommend
the one that won the comparison (no comparison ran: recommend from the teasers and say that is the basis). In a
repeat round, a direction the owner already said they liked is the recommendation unless its teaser flopped; a new
card that came out better is shown as the challenger, with why. A survivor whose teaser played flat stays in the
three only if nothing better exists, and the block says it flopped. If the
teaser of another turned out better than its pitch, say so. A card killed only for being small but that made you
laugh is shown under the three as "build this anyway": a quick win the owner would want, not a moonshot.
End with "Which one should Mr Claude write to MOONSHOT.md?" and stop. Done when the user's reply names one. If the
reply is that all of them are lame, ask which was closest and what was missing, add that sentence to the brief's
delight signals, and run Steps 2-3 once more.

**4. Write MOONSHOT.md.** Read [`references/moonshot-template.md`](references/moonshot-template.md); it holds the
template, the phase rules and, for a bet that replaces a part, the oracle-by-component table. Fill it for the one chosen bet. The other survivors go
under Alternatives, never into the phases. Check it against "Done when" below, then offer, in one line,
`/flow-extras:scrutinize-idea` on MOONSHOT.md as the attack pass (the proposer does not grade itself).

**5. Hand phase 1 to flow.** Only when `state` is `idle` or `no-project`: any other state means a feature or a
prep is already in flight; say so and leave the seed for re-entry. Read
[`references/handoff.md`](references/handoff.md), then the develop-idea seed contract it points to, before writing
anything. Seed phase 1 only, on the user's explicit yes. End the turn with the seed contract's `Next:` line.

**6. Re-entry at a phase boundary.** Read [`references/handoff.md`](references/handoff.md) (section Re-entry). Re-read
MOONSHOT.md from disk, find the phase marked in progress, and check what shipped against that phase's continue/kill
check. Then one of three: continue (append a status line, seed the next phase on a yes), amend (append a dated
Amendment, never rewrite the body), or stop (append the kill with its evidence; a kill is a result, not a failure).

## Never

- **Never bundle bets.** One MOONSHOT.md holds one bet. The default answer bundles about three; a bundle has no
  single monkey, so no phase 1 can kill it, and it grows until it cannot ship.

  | The excuse | Why it fails |
  |---|---|
  | "They reinforce each other" | Then one is the means of the other: keep the one whose demo is best, and the rest become its phases or go to Alternatives |
  | "The user said unlimited resources" | Labour is unlimited; review attention and the user's own time are not |
  | "Leaving it out wastes the idea" | Alternatives keeps it, with the reason it lost |

- **Never pitch the worthy one.** If the honest reaction to the demo is "that is sensible", it is not a moonshot.

  | The excuse | Why it fails |
  |---|---|
  | "It is what the project needs" | Needs go through /flow:prep; the owner asked for the thing they would never have dared to write down |
  | "It is more rigorous / complete / trustworthy" | Nobody shows a friend a completeness guarantee |
  | "The fun version is frivolous" | Frivolous and built beats worthy and shelved; the owner's side features show what they enjoy |

- **Never shrink the bet into a cleanup.** A fix recon can prove today goes under Alternatives as a quick win.

  | The excuse | Why it fails |
  |---|---|
  | "That component does not exist yet" | Agents build it; it becomes the monkey and phase 1 tests it |
  | "A smaller version is more realistic" | The smallest fun version is phase 1, not the bet |
  | "The big version is not credible" | Credibility is phase 1's job; the pitch's job is to say out loud the thing worth a billion |
  | "The owner is one person" | One person with a fleet of agents; pitch what the fleet can build |
  | "It would take a team a year" | That price is the reason nobody wrote it down; that is the point |

- **Never grow the bet into another product.** No new audience, no going public, no service to run for strangers,
  unless the owner's docs already ask for it. Bigger for other people is not cooler for this one.
- **Never rank by a score out of 10, yours or a judge's.** The paired grin test and the teasers rank the cards; the
  owner picks.
- **Never describe when you can show.** A teaser made from real data outranks any paragraph about it.
- **Never pitch from the attractor kit.** A graph, twin, calibrated model, agent loop, dashboard or platform turn
  is what every model proposes for every repo; it earns a place only when its demo passes the grin test on its own.
- **Never cost in people or calendar per task.** No squads, headcount, hires or "3 weeks for X". Size phases as flow
  features. Human-time pricing is the bias that hid the moonshot in the first place.
- **Never start with the pedestal.** Phase 1 is the smallest version that is already fun to use, on real data; its
  kill check is the owner's own reaction. Scaffolding, schema design and plumbing prove nothing.
- **Never seed more than the next phase, write a `D-NN`, or invoke `/flow:prep` yourself.** The router surfaces
  the newest unprepped seed, a decision needs the user's receipt, and prep is user-invoked; handoff.md has the detail.

## Done when

- MOONSHOT.md's first paragraph after the title is the full-version scene, then tonight's version, then the bet
  in one sentence and the price in people that hid it; the phases climb from tonight's version to the full one; the
  raw material it uses is named with paths, every ruling in the brief is listed as honoured, and the file is at
  most about 120 lines.
- The teaser's path is recorded, or "no teaser" with the reason.
- It has 4-6 phases; phase 1 ends with something the owner can play with and a kill check that is their reaction
  plus one number; every phase adds something visible, has a runnable check and a "not this" fence; no phase is
  only plumbing.
- Nothing in it prices work in people or per-task weeks.
- A seed, if written: `prep-lint` printed `OK` and the turn's last line is the seed contract's `Next:` line.
