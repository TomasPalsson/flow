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
- Deploy order: `<first> then <second>; roll back in reverse`. Optional; add it only when the diff changes two deployables (an API and its client, a stack and a service) that must go out in sequence.
- Rollback: `<trigger> -> <step>`. Optional; add one per one-way door. The step is a down migration when the tool has one, otherwise a snapshot restore or a forward fix. Name the recovery even when it is a forward fix; forward-only tools have no down.
- Gate edits: none detected | N listed (each: file:line, kept because <reason>) | UNAVAILABLE: <reason>. Fill it from the gating run of `../no-slop/scripts/slop-check --base <Base>` and the `[skip ci]` grep in `next`'s Gate-relaxation scan. Only NS-09 suppression/test-runner findings, NS-13 findings and `[skip ci]` hits belong here, not slop-check's other findings. `none detected` needs an exit-0 scan with none of those; exit 2 or a missing Base prints `UNAVAILABLE: <reason>`, never `none detected`, because a scan that did not run found nothing only by default.

## Left out

Optional; omit the section when there is nothing to list. Run `flow digest --json` yourself when writing the body (the digest `flow finish off` prints comes later) and list each entry of kind `discovered`, the unfiled defers, with its `NOTES.md` text. The PR is the record that outlives the archive.

## Could be smaller

Optional; omit it when the gating review's `advisory` list is empty. List each `structure` finding there (`file:line`, the restructuring it suggests). They never block; they are the next change's starting point.

## Docs drift

Optional; omit it when the gating review's `advisory` list has no `docs` finding. List each one (the doc `file:line` that is now false, and the diff line that made it so). They never block and are not auto-fixed; the author fixes the doc or leaves it. This is separate from `Could be smaller`, which is about structure.

## Low impact

Optional; omit it when the gating review's `lowImpact` list is empty. List each finding there (`file:line`, the predicate). They are verified real, scored 75, and never block; the reader decides whether to fix them now.

Write the body to a file with the Write tool and open or update the PR with `gh pr create --draft --title "<title>" --body-file <file>` (`gh pr edit <n> --body-file <file>` to change it). The title is the one string `gh` takes on the command line, so keep it plain: no backticks, `$` or double quotes. Other free text never goes inside shell quotes: a backtick or `$(` in a double-quoted `--body` runs as a command. The same holds for commit messages (`git commit -F`).

Describe what changed, not the diff line by line, and link long logs and SHA lists instead of pasting them: the reader can open a link, and a pasted log buries the point.

Before `gh pr create`, run `git diff --stat <base>..HEAD` and check the body against it in both directions. Every concrete claim in the body ("docs only", "no behaviour change", "tests pass") is backed by that diff or by a command already shown. Every material file group in the diff is either mentioned or left out on purpose (generated files, lockfiles). A body written before the last fix round is the usual place these drift apart.

Before opening the PR, read `../no-slop/references/prose-rubric.md` (claims carry a label or their command) and run `../no-slop/scripts/slop-check --prose` on the body. When it reports NP-09 (a perf number with a comparison and no run count), call the Skill tool with "flow-extras:benchmark-checklist" and fix the claim before `gh pr create`; skip quietly if flow-extras is absent.

Credit: adapted from mattpocock/skills `pr` @ f3fc563 (MIT), itself from humanlayer `show-me`.
Credit: adapted from github/spec-kit docs/guides/contract-driven-development.md @ 0443760 (MIT) and addyosmani/agent-skills skills/shipping-and-launch/SKILL.md @ 1be8e34 (MIT).
Credit: adapted from garrytan/gstack document-release/SKILL.md.tmpl @ 5b9b837 (MIT).
