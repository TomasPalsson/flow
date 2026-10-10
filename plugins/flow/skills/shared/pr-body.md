---
name: pr-body
description: The shape of a PR body — Summary, Evidence, Merge danger, and an optional Left out — that next and fix open with before their own required sections
---

# PR body

Three sections, in this order, plus an optional fourth. The caller appends its own required sections after them: `next` appends the `Ruling:` lines; `fix` appends the root cause and the revert-proof exit codes.

## Summary

The smallest view that makes the point. Pick one, rarely two, never all:

- pseudocode of the new behaviour
- a call tree of what now calls what
- a file tree of what moved or appeared
- a mermaid diagram of a flow or state change
- a diff-sketch: a few lines of the change, not the whole diff

Separate core files from generated or mechanical ones. If notes cannot make the PR reviewable, split it.

## Evidence

Before and after.

- Visual change: a screenshot of each.
- Anything else: the exact test or command you ran, red on the old code, then green on the new, with exit codes.

## Merge danger

- Door: one-way or two-way. One-way means it cannot be undone by reverting (a migration, a published API, deleted data).
- Blast radius: one word (`none`, `module`, `service`, `users`), plus optional ramifications if the word hides something.

## Left out

Optional; omit the section when there is nothing to list. Run `flow digest --json` yourself when writing the body (the digest `flow finish off` prints comes later) and list each entry of kind `discovered`, the unfiled defers, with its `NOTES.md` text. The PR is the record that outlives the archive.

## Could be smaller

Optional; omit it when the gating review's `advisory` list is empty. List each `structure` finding there (`file:line`, the restructuring it suggests). They never block; they are the next change's starting point.

Describe what changed, not the diff line by line, and link long logs and SHA lists instead of pasting them: the reader can open a link, and a pasted log buries the point.

Before opening the PR, read `../no-slop/references/prose-rubric.md` (claims carry a label or their command) and run `../no-slop/scripts/slop-check --prose` on the body. When it reports NP-09 (a perf number with a comparison and no run count), call the Skill tool with "flow-extras:benchmark-checklist" and fix the claim before `gh pr create`; skip quietly if flow-extras is absent.

Credit: adapted from mattpocock/skills `pr` @ f3fc563 (MIT), itself from humanlayer `show-me`.
