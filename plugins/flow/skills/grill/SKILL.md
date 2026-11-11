---
name: grill
description: "Grilling session with no question limit: maps a plan or idea as a design tree, asks every open decision in rounds, and explains each question in plain words (what it decides, the options, what each one costs, how hard it is to undo) so the user makes an educated choice. Challenges the plan against CONTEXT.md and the code, and updates CONTEXT.md and ADRs inline. Triggers: /flow:grill, \"grill me and explain the options\". Not for the short one-question-per-turn interview that writes PREP.md (use /flow:prep)."
disable-model-invocation: true
argument-hint: "<plan or idea, or nothing = the plan in this conversation>"
---

<what-to-do>

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Map the plan as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask now without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question, explain it (see **Explain every question**), and give your recommended answer. Then wait for my answers before the next round.

There is no cap on the number of questions or rounds. When a frontier holds more than three questions, ask the three that unblock the most, and say how many wait for the next round.

Format a round like so:

```
**Q1. <the question, in plain words>**

<One or two short sentences: what this decides, and what waits on it.>

**A. <name>** ⭐ recommended
<What happens if you pick it: one real example with real values.>
Cost: <one short line>
Undo: <easy or hard, in a few words>

**B. <name>**
<the same three lines>

Why A: <one reason>

---

**Q2. <the question, in plain words>**
...
```

Keep each question light, so a round does not overwhelm:

- One blank line between blocks. No paragraphs: every line is one short sentence.
- Three lines per option, no more. Keep the one number or name that matters, and leave the rest out.
- No inline code formatting (backticks) in a question. Write names and paths as plain text.
- The rest of the detail (paths, more numbers, edge cases) waits until I ask: I reply `more` with a question number.

Word each question so "yes" accepts your recommended answer.

Each round I answer reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier after each answer set and ask the next round. A question whose answer depends on another question still open in this round belongs to a later round, not this one.

Facts are your job, decisions are mine. If a question can be answered by exploring the codebase, explore the codebase instead of asking. When a frontier question needs a fact from the environment (filesystem, tools, etc.) that is not quick to read yourself, dispatch a subagent to find it. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the subagent to report; ask the rest of the frontier now.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until I confirm we have reached a shared understanding.

Rounds-over-the-frontier approach adapted from the `grilling` skill in mattpocock/skills @ f3fc563 (MIT).

</what-to-do>

<explain-every-question>

## Explain every question

A decision I do not understand is your decision with my name on it. Before I answer, I must be able to say what I am choosing and what each answer costs. A question that only an expert could answer is not ready to ask: explain it first.

### What each question carries

- **What this decides**, and what waits on it, in one or two short sentences.
- **Every real option**, not only the one you recommend. For each: what happens in this project if I pick it, what it costs, and how hard it is to undo.
- **Your recommendation and one reason.** When you are not sure, say what fact is missing.

Read the code first so the options are true. An option that describes code you did not read is a guess: say so, or go and read it.

### Words

Simplified Technical English (ASD-STE100, the controlled English of aircraft maintenance manuals) sets the register. The project supplies the nouns.

- Use the words in `CONTEXT.md` and the code's own names (types, functions, file names). Do not invent a name for a thing that has one.
- One word, one meaning. A thing keeps the same name in every question and every round.
- Sentences: 20 words max for a step, 25 max for a description. Active voice. One idea per sentence. Keep the verbs, subjects and articles: short does not mean clipped.
- No noun stacks of more than 3 words.
- Put the meaning of a hard word right after it, in parentheses. Do the same for every acronym, the first time it shows in a round.
- Concrete before abstract. Show the real case with real values first ("a user saves twice and gets two rows"), then name the rule ("so the save is not idempotent (safe to repeat)").
- Show a thing before you give its name.
- One comparison (an analogy) per idea at most. Say where it stops being true, and do not use it past that point.
- Check ideas, not only words. An option can lean on an idea I do not have even when no hard word is in sight. Explain that idea in one or two sentences above the options, or ask about it in an earlier round.
- Plain is not shallow. Each option keeps the fact that decides it (a real number, a real name). When I reply `more`, give the real paths, numbers and edge cases in the same plain words.

### When I do not follow

- I answer `?` with a question number, or say "you lost me": explain that question again one step simpler, with a different example. Do not repeat the same words louder. This is not an answer; the question stays open.
- The thing is a system with many moving parts and words are not enough: offer a picture page with `/design:smoothbrain <topic>` (needs the design plugin), then come back to the question.
- I say "you pick" or "whatever you think": say in one sentence what your recommendation commits me to, and get a yes to that sentence. A choice I waved through without that sentence is still open.

</explain-every-question>

<supporting-info>

## Domain awareness

During codebase exploration, also look for existing documentation:

### File structure

The trees below show the default layout. A repo that already keeps its ADRs elsewhere keeps them there (see ADR-FORMAT.md).

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily — only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. For ADRs, follow the match-the-existing-convention rule in [ADR-FORMAT.md](./ADR-FORMAT.md): continue the repo's ADR directory and numbering, and use `docs/adr/` only when none exists.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

</supporting-info>

Credit: the explanation rules come from this repo's `design:smoothbrain` skill (plugins/design/skills/smoothbrain/SKILL.md).
