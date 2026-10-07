---
name: pr-body
description: The shape of a PR body — Summary, Evidence, Merge danger — that next and fix open with before their own required sections
---

# PR body

Three sections, in this order. The caller appends its own required sections after them: `next` appends the `Ruling:` lines; `fix` appends the root cause and the revert-proof exit codes.

## Summary

The smallest view that makes the point. Pick one, rarely two, never all:

- pseudocode of the new behaviour
- a call tree of what now calls what
- a file tree of what moved or appeared
- a mermaid diagram of a flow or state change
- a diff-sketch: a few lines of the change, not the whole diff

## Evidence

Before and after.

- Visual change: a screenshot of each.
- Anything else: the exact test or command you ran, red on the old code, then green on the new, with exit codes.

## Merge danger

- Door: one-way or two-way. One-way means it cannot be undone by reverting (a migration, a published API, deleted data).
- Blast radius: one word (`none`, `module`, `service`, `users`), plus optional ramifications if the word hides something.

Credit: adapted from mattpocock/skills `pr` (MIT), itself from humanlayer `show-me`.
