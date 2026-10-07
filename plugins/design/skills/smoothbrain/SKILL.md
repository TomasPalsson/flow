---
name: smoothbrain
description: "Explains a thing to a smooth brain: a picture page that shows the whole thing on one screen first, then the parts, then how it moves, then the detail for later, in plain words and the project's own nouns. Use when the user types /smoothbrain [topic], or says \"wait what\", \"you lost me\", \"I don't get it\", \"explain like I'm 5\", \"ELI5\", \"big picture\", \"draw me how X works\", or asks for a picture explainer of code, a system, a concept or what just happened. With no topic it re-explains *that*: the thing that lost the user. Not for a polished docs article for expert readers (use design:explainer)."
argument-hint: "[topic, path, or nothing = that]"
user-invocable: true
---

# Smoothbrain

The listener has a smooth brain for this topic: no folds yet. They stopped following. Back up. Show the whole thing first. Then add one fold at a time.

This names the listener, not the output. "Be short" gives clipped fragments. "Smooth brain" asks for fewer words **and** the missing context.

## 1. Find *that*

- A topic: explain that topic.
- A path or repo: read it first. Never explain code you did not read.
- No topic: explain *that*, the thing that lost the user. Go back as far as you need. It is usually more than the last message.

Write the one sentence the reader must leave with. Every part of the page serves that sentence.

## 2. Words

Simplified Technical English (ASD-STE100) sets the register. The project supplies the nouns.

- Read `GLOSSARY.md`, `GLOSSARY-MAP.md`, `CONTEXT.md`, `CLAUDE.md` and the code's own names if they exist. Use those words. Do not invent a name for a thing that has one.
- No glossary file: use the code's own names (types, functions, file names). For a topic outside a repo, use the terms in the vendor's or the field's own docs.
- One word, one meaning. A thing keeps the same name on every label, caption and detail section.
- Sentences: 20 words max for steps, 25 max for descriptions. Active voice. One idea per sentence. Keep the verbs, subjects and articles.
- No noun stacks of more than 3 words.
- Put the meaning of a hard word right after it, in parentheses. Do the same for every acronym.
- Five new terms per page at most. These go in the words card. Show each thing before you give its name. Other hard words get their meaning in parentheses and stay out of the card. Names of values (state names, status codes, file names) are values, not terms: show them in the pictures and the step-through.

## 3. The zoom ladder (the page)

1. **Big picture.** One picture and one sentence fill the first screen. The picture shows the whole thing with every part named. A reader who stops here is still right.
2. **The parts.** 3 to 5 cards. Each card has a small picture, the project noun, and one line on what the part does.
3. **How it moves.** A step-through: the reader presses Next and one event happens per step. Use a real example with real values, in the real order. Group checks that give the same result into one step.
4. **The detail.** Closed sections the reader opens if they want them. Put the real terms, `path:line` references, numbers, edge cases and "why it is built this way" here. Real detail is welcome. Plain words still apply.
5. **Words on this page.** A picture glossary: each term, its icon, and one line. It uses the same spelling as the rest of the page.

Add these when they help: **Where the comparison breaks** (see below), and **Check yourself** (2 or 3 questions with tap-to-show answers).

## 4. Pictures

- Every picture shows the mechanism: the real parts and the real arrows between them. A picture that only decorates gets cut.
- The page must still teach if you delete the text. If it does not, the picture is wrong.
- Concrete before abstract: show the real case with real values first, then name the rule.
- One comparison (an analogy) per idea at most. Say where it stops being true, and do not use it past that point.
- Labels go on the part they name, not in a legend.
- The same thing gets the same shape and colour on every picture.
- Make the interaction show the mechanism. Do not add a control only for fun.

## 5. Build and ship

1. Call the Artifact tool with `action: "quickstart"` and `intent: "other"`. Load `artifact-design` and `artifact-diagramming`.
2. Read `references/page.md` for the page parts, the step-through code and the picture rules.
3. Let the picker assign the drawing style, so the look changes every run: `node <this skill's folder>/../graphics/scripts/pick-style.mjs --mood <2 words for the topic> --kinds diagram,icon-set --project <repo root or cwd>`. Commit to it, or re-roll with `--reroll 2` if it fights the topic. Do not fall back to graph paper and hand lettering. A style the user asks for wins.
4. For a mascot, an object drawing or an icon set, call `design:graphics`. Draw diagrams as inline SVG yourself.
5. Run `node <this skill's folder>/scripts/check.mjs <page.html>` and fix every FAIL.
6. Publish the page and give the link.

The chat reply is three lines: the big-picture sentence, the link, and "Which part do you want deeper?"

## It is working if

- A reader who sees only the first screen can say what the thing does, and is right.
- Every term on the page is in the words card, with the same spelling.
- Project nouns appear. Invented names do not.
- The detail sections have real substance: paths, numbers, edge cases. The top is simple; the page is not shallow.
- Used twice in a row, it goes one step simpler or one fold deeper, as asked. It does not get blunter.
