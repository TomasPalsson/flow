---
name: no-slop
description: "Stop AI slop in the code Claude writes: no re-implemented helpers, no premature abstractions, no guards on impossible states, no comments that restate code, no unrequested scope, no test slop. Parts: a verbatim developer block for briefs, a `slop` adversary lens, and `scripts/slop-check`. Use WHENEVER you are about to add or change code in an existing repo — 'add a property/field/method/endpoint to X', 'implement X in file Y', including when the request names the exact file to edit — a brief for a developer agent (spec, next, fix, build-slices, ultracode) — search the repo for an existing helper first, whenever an adversary reviews a diff, whenever the user says slop, duplicate code, reinvented the wheel, over-engineered, too defensive, comment noise, scope creep, 'keep it minimal', 'this looks AI-generated', or asks how to make Claude write cleaner code. Do NOT use for whole-repo debt sweeps (/audit), post-merge deepening (/flow-deepen), or fixing a specific bug (/fix)."
---

# no-slop

Slop is not one thing. It is a cluster of tells that share one root: the model writes each function as a fresh local optimum, without the repo's existing helpers, conventions, or guarantees in view. GitClear's 211M-line data has copy/paste share up from 8.3% to 12.3% and block duplication up 81%; the strongest stylometric tell of LLM code is comment density. This skill puts the missing context in front of the writer before it writes, gives the reviewer a way to see outside the diff, and makes every rule a PASS/FAIL row a grader can score.

Three consumers, one rubric:

| Consumer | Reads | Produces |
|---|---|---|
| Developer agent (writes one slice) | [`references/developer-block.md`](references/developer-block.md), pasted into its brief | code plus a one-line search receipt and a `slop-check` run |
| Adversary agent (`slop` lens) | [`references/adversary-lens.md`](references/adversary-lens.md) | receipted findings, severity-sorted |
| Eval suite / hook / human | [`references/rubric.md`](references/rubric.md), `scripts/slop-check` | PASS/FAIL per NS row |

## The two rules that are not the same rule

1. **An existing helper is reused. Always.** Re-implementing something the repo, the stdlib, or an already-imported library provides is a defect (NS-20), and no tool catches it after the fact: semantic clone detectors lose 9 to 43% F1 under rewrites. The only mitigation is to **search before writing** and to leave a receipt.
2. **A new helper is extracted at the third similar block**, or in a measured hot path, never at the second (NS-21). Three similar lines beat a premature abstraction.

Conflate them and the rule becomes either useless ("only two instances, fine") or hostile ("never repeat anything"). State both, side by side, every time.

## Before writing (developer protocol)

1. Read the brief. List every symbol you intend to add.
2. For each: at least three searches across the whole repo, never one word — the verb, two synonyms (slug: kebab, dash, hyphen; format: render, label; validate: check, verify), the library you would import, the error string; plus a look inside any `utils`/`support`/`helpers`/`lib` package. `rg -in '\b(slug|kebab|hyphen)\b'`; `rg -n '^(from|import) .*slug'`; for shape, `ast-grep run -p 'def $N($A: str) -> str: $$$' -l python`; with an LSP tool, workspace symbols for each term.
3. Write the receipt line: `searched: slug, slugify, kebab, import slugify; found: src/text.py:4`. If found, import it. If nothing, write the function.
4. Before each guard: name who guarantees the value (type, constructor, prior check, boundary). Only a boundary earns the guard.
5. Before each comment: WHY, one short line, or nothing. Never WHAT, never the task or the caller.
6. Match the three functions above and below the insertion point.
7. Run `scripts/slop-check --base <base>`; fix or justify each line in the report.

**MANDATORY when assembling a brief for a developer**: paste [`references/developer-block.md`](references/developer-block.md) whole. Do not paraphrase it. Do NOT load `adversary-lens.md` or `rubric.md` for this; the developer needs only the pasted block. The first paragraph is Anthropic's own countermeasure for Opus 4.5/4.6 over-engineering; the search step is what moved the reuse case from 0 of 3 to 3 of 3 in this repo's eval.

## Reviewing (adversary protocol)

**MANDATORY — READ ENTIRE FILE** before reviewing: [`references/adversary-lens.md`](references/adversary-lens.md). Do NOT load `developer-block.md` here; the adversary reviews, it does not write.

The lens runs **per slice**, beside `correctness` and `gaming`, not only at branch level: a clone introduced in slice 1 is built on by slice 2, and by branch review it has callers. It takes the `slop-check --json` output as advisory input, confirms or dismisses each line, then does what the script cannot: check the search receipt against the repo, count call sites of every new abstraction, trace each guard to its guarantee, read comments against their lines, and trace every added symbol to a sentence of the brief.

The evidence rule: no receipt, no finding. `path:line` plus the command that proves it. Ten reviewers once unanimously endorsed a defect that did not exist; one empirical test killed it. Same-model self-review silently endorses about a third of its own drift, so the adversary is a separate pass with its own searches, never "look again".

## The mechanical layer: `scripts/slop-check`

```
scripts/slop-check [--base <ref>] [--head <ref>] [--json] [--strict] [--no-tools] [--files <path>...]
```

Stdlib Python (`slop-check` plus the diff/hunk machinery in `slop_diff.py` and the optional-tool adapters in `slop_tools.py`, both beside it), scoped to **added lines only** (a one-line edit in a legacy file must not re-report the file). Always advisory: exit 0 unless `--strict`. Checks NS-03 to NS-10, NS-13, NS-15, NS-16 on its own in under a second; with `uvx ruff`, `npx tsc`, and `npx jscpd` present it adds NS-11, NS-12 and NS-01 (new clones versus the base ref, identifiers normalised, `--min-tokens 15` because agent-written functions are short). Missing tools are skipped silently. A purpose-built tool in this niche self-reports 36.7% false positives, which is why this layer never blocks; the lens confirms.

What it cannot see, by measurement: comments that restate code (near-zero recall for any token heuristic), guards on already-guaranteed values, premature abstractions, semantic reinvention. Those are lens rows.

## The rubric

**Load [`references/rubric.md`](references/rubric.md)** when scoring a diff, when writing an eval grader, or when someone asks "is this slop?". Every row is a PASS condition, a detector, a severity, and a false-positive guard. Rows NS-01 to NS-16 are mechanical; NS-20 to NS-29 are lens or pipeline. The "What is not slop" list is binding: boundaries keep their guards, entry points keep their broad catch, public APIs keep their docstrings, three similar lines stay three lines.

## Wiring it into a pipeline

One-time, for whoever integrates the skill: **load [`references/integration-seams.md`](references/integration-seams.md)** only when wiring `no-slop` into a brief assembler, a lens table, a hook, or an eval suite. Do NOT load it for a developer, adversary, or grader invocation.

## NEVER

- **NEVER merge the two duplication rules.** Missed reuse is zero-tolerance; new abstraction is Rule of Three.
- **NEVER let the developer skip the receipt** on a slice that adds a symbol. The receipt is the only artifact that proves the search happened.
- **NEVER let the adversary flag without `path:line` and a command.** PLAUSIBLE never blocks.
- **NEVER make the mechanical layer block.** A third of its findings can be legitimate; blocking teaches the developer to justify around it.
- **NEVER ban comments outright.** One short WHY line for a hidden constraint is the thing TDD's Red phase exists to preserve. Ban WHAT, ban task references, ban paragraphs.
- **NEVER tighten the function-length guard to catch slop.** Length grows from padding; catch the padding.
- **NEVER treat coverage as the test oracle.** LLM oracles capture what the code does, not what it should; Red must fail for real, and mutation score is the ground truth where Bash is available.
- **NEVER paraphrase the developer block.** Its first paragraph is vendor text; the measured effect belongs to the exact wording.
