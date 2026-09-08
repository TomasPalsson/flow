---
name: question-bank
description: The one batched discovery turn for /flow:spec — a numbered list of pre-answered assumptions covering the eight categories, plus the negative-scope probe, the quantification probe, and the "I don't know" fallback. Load this entire file before writing the discovery turn.
---

# Discovery — one turn, pre-answered

Discovery is **one message**, not an interview. You write a numbered list of *positions you have already taken*, each with the reasoning behind it, and ask the user to reply with the numbers they want changed. **Silence is acceptance of a stated position, not a skipped question** — that only holds if every item states a position, so a bare question ("what about auth?") is a banned form. If you genuinely cannot form a position, offer two concrete options and say which you would pick.

Budget: 4 items on `bounded`, 5–7 on `oneshot`, 7–10 on `dispatch`. Cap at 10. Anything still open after the turn becomes an Open Question in the spec (cap 3) or an Assumption with its confidence.

**Opening line, verbatim shape:**

> Here is what I am assuming. Reply with the numbers you want to change, or "all good".

**Item shape, verbatim:**

> `N. <Category> — <the position>. Why: <one clause from the description, the domain, or this repo>.`

## The categories, in order of impact-if-missed

Cover each one that carries real risk for this idea; skip a category only when the description already settles it, and say which you skipped.

| # | Category | The position to take | What it surfaces |
|---|----------|----------------------|------------------|
| 1 | **Problem & users** | who is hands-on daily, and what breaks for them today | the real problem behind the requested solution |
| 2 | **Success** | the one measurable outcome that means this worked | hidden acceptance criteria |
| 3 | **Negative scope** | the adjacent things this will NOT do | see below — never skip this one |
| 4 | **NFR numbers** | a number for every adjective in play | "fast" and "secure" as testable thresholds |
| 5 | **Failure paths** | what the user sees when the main action fails, and what state survives | the error journeys the happy path hides |
| 6 | **Integration** | what this reads from and writes to that it does not own | contracts with systems you cannot change |
| 7 | **Constraints & maintenance** | stack, deadline, and *who maintains this after launch and what they know* | architecture the description never mentions |
| 8 | **Acceptance** | how a reviewer other than the author proves it works | untestable ACs, caught before they ship |

## The two probes that are never optional

**Negative scope (category 3) is mandatory on every route.** Ten seconds to state, and it prevents the scope arguments that eat weeks. State it as three bullets of what is out, not as a question. Its answer becomes §2.2 Non-goals verbatim, and §2.2 is binding: a later change to it is an `--amend`, not an interpretation.

**Quantify every adjective (category 4).** "Fast", "secure", "robust", "scalable", "simple", "user-friendly" — each one is a number you have not written yet. The probe: *"What number would make this false?"* Then state the number as the position: *"p95 under 300 ms on the list endpoint — slower than that and a user reloads."* A vague adjective that survives this turn survives into the spec, where it becomes a decision the developer has to make alone.

## When the user replies "I don't know"

Three steps, in order — never let it end a thread:

1. **Offer a default with its reasoning.** "Then I'll take X, because Y."
2. **Ask for an order of magnitude.** "Tens or thousands? Seconds or minutes?"
3. **Record it as a named assumption** with a confidence level and a blast radius, in §7 of the spec. An assumption on the page is recoverable; one in your head is not.

## PREP.md already answered some of this

When `/flow:prep` wrote a `PREP.md`, its `## Decisions` are settled and never re-asked, `## Not this` **is** category 3, and `## Assumptions` are already recorded. Ask only the categories PREP.md left genuinely empty, and say in the turn which ones prep already closed. Contradicting a recorded decision is a `[NEEDS CLARIFICATION: conflicts with D-NN]` marker in the spec, never a second question.

## Stop asking

After the reply, ask yourself once: *would the answer to another question change what I build or how I test it?* If no, write the spec. The stopping signal is convergence, not exhausting the budget.
