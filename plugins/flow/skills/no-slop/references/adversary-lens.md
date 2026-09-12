---
name: no-slop-adversary-lens
description: The `slop` review lens for an adversary agent — inputs, the evidence rule, the do-not-flag list, and the output contract. Load when an adversary is asked to review a slice or branch diff for AI slop.
---

# The `slop` lens

You are not the author. You have the brief, the diff, the developer's report, and the repository at head. Your job is to find slop the developer could not see from inside the diff, and to prove each finding.

## Inputs, in this order

1. `scripts/slop-check --base <base> --json` output. It is advisory input, not a verdict: confirm or dismiss each mechanical finding by reading the line.
2. The developer report's **search receipt** (NS-27). If absent and the slice adds a symbol: finding, `block`.
3. The brief. Every added symbol must trace to a sentence in it (NS-24).
4. The diff, then the surrounding file for each hunk (NS-25), then the repo for each new function (NS-20, NS-21).

## The evidence rule

A finding without a receipt is not a finding. A receipt is `path:line` plus the command or file that proves it:

- NS-20: the existing helper's `path:line` and the `rg`/`ast-grep` command that finds it.
- NS-21: the count of call sites (`rg -n '\bname\('` output) showing fewer than three.
- NS-22: the type annotation, constructor, or prior check (`path:line`) that already guarantees the value.
- NS-23: the comment and the line it restates, quoted together.
- NS-24: the added symbol and the sentence of the brief it was supposed to trace to, with "none".
- NS-26: the assertion and the change to the implementation that would not make it fail.

If you cannot produce the receipt, the most you may say is PLAUSIBLE, and PLAUSIBLE never blocks. Ten reviewers once unanimously endorsed a defect that did not exist; one empirical test killed it. Be the test.

## Do not flag

- Pre-existing issues on lines the diff did not add.
- Anything a configured linter or formatter already reports, or that `slop-check` reported and the developer justified on the same line.
- Style preferences with no surrounding-file evidence.
- Guards at real boundaries; broad catches in entry points that log.
- Three similar lines that have not reached the Rule of Three.
- "Could be simpler" with no concrete shorter form you can write in the finding.

False positives erode trust faster than a missed advisory. If you are not certain, do not flag.

## Output contract

```
LENS: slop
BLUF: <clean | N blocking findings, M advisories>

## Findings (severity-sorted)
1. [block] NS-20 reuse-missed — src/posts.py:12 re-implements slugify
   receipt: src/text.py:4 `def slugify`; `rg -n 'def slugify' src/` → 1 hit
   fix: `from .text import slugify`; delete lines 12-15
2. [advise] NS-05 docstring-on-trivial — src/posts.py:20 (from slop-check, confirmed)

## Dismissed mechanical findings
- NS-08 src/cli.py:40 print( — CLI output path, not a leftover
```

One fix line per finding, concrete enough that a developer with only the brief can apply it. Never edit code yourself.
