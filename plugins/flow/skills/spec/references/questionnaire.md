# Questionnaire for an Open Question someone else owns

Used once, at spec close, when an Open Question's `owner:` is not the user (see `SKILL.md` §6 step 6). The recipient holds knowledge the user lacks; the document pulls it out of them. Nothing is written until the user says yes.

## Interview the send, not the subject

The user can always answer two things about the send, so ask only those, in one exchange:

1. **Who is it going to?** Role, expertise, relationship to the user. This fixes tone and how much context the document carries.
2. **What do you need back?** The decisions or facts the user cannot settle alone. This is the list every question must cover.

Do not quiz the user on the subject itself: if they could answer it, it would not be an Open Question.

## Write it

Write `.specs/<NNN-slug>/questionnaire-<owner>.md` (owner lowercased, spaces to `-`) using the template below, then report the path. Done when every item named in step 2 has a question. Order questions most-important-first, because async means there may be only one pass. Group under `##` themes once there are more than a handful. Each question is one idea with an answer stub directly beneath; add a one-line "why this matters" only where the question could be misread.

An Icelandic recipient: if `icelandic-professor` is installed, run it over the finished document before offering it. If it is not installed, skip this quietly and write in plain Icelandic.

Answers come back through `/flow:spec --amend`, which turns each answered question into a resolved position in the spec and clears its `[NEEDS CLARIFICATION]` marker.

```markdown
# <Questionnaire title>

**Purpose:** why this exists and the decision riding on it.
**From:** <the user> · **To:** <recipient> · **How your answers will be used:** <where they go>

## Context
One paragraph for a reader who was not in the user's head.

## How to answer
Deadline and rough effort. Partial answers and "I don't know" are useful: flag what you are unsure of rather than skipping it.

## <Theme>
### <One question, one idea>
_Why this matters: <only where needed>_

>

## Anything else?
Anything we did not ask that we should know?
```

Credit: adapted from mattpocock/skills skills/productivity/to-questionnaire/SKILL.md @ 49dd158 (MIT).
