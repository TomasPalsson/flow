# Auditing an eval before trusting it

Load this when a result looks surprising (every case passes, every case fails, a score jumps after a small change) or before you use an existing eval to pick between models, prompts or skills. A broken eval gives confident numbers that point the wrong way, and optimising against it ships nothing.

**A surprising result is an eval bug until cross-checked.** Check it against a second signal before believing it: a different grader on the same outputs, the gold answer run through the grader, a hand read of five raw outputs.

Run the eval once end to end first, or find a recent results file. Many quality discussions are about code that does not currently run.

## What to look at

Read the eval's actual code, config and data, not its README.

- **Task design.** Would two experts agree on pass or fail for the same output? Is anything the grader needs left out of the prompt (filename, format), or is the prompt a recipe that leaves the model nothing to decide? Does each case ship a gold answer that passes the grader? A 0% pass rate across every variant is usually a broken case.
- **Gold provenance.** Re-derive the expected answer for ten sampled cases yourself. Record where each gold came from (written by hand, copied from a model, taken from a dataset). A gold copied from model output measures agreement with that model.
- **Harness.** Does the run use the code and plugin under test, or an installed copy? Can the candidate see that it is graded (paths, names, commit author)? Does a failed run (limit hit, crash) count as a score of zero instead of being left out?
- **Grader.** Feed the grader a wrong answer, an empty answer and an off-topic answer. Any PASS means the grader cannot tell work from nothing. Check for answers that are correct but rejected, and for shortcuts that satisfy the grader without doing the task.
- **Signal.** Is the sample large enough for the change you want to detect, and do repeated runs of the same system agree with each other?

## Burden of proof for model graders

A model grader answers PASS only when it can quote evidence of substance from the material, and FAIL when uncertain. Write that into every criteria string: "FAIL if uncertain" and the exact evidence to quote (a test output line, a diff hunk, a file path). The grader also critiques the eval it just used: it lists assertions a wrong output would still pass, and outcomes no assertion checks. Read those critiques; they find weak assertions faster than reading cases.

## Per-case auditor prompt

For sets too large to read, run one isolated call per case and aggregate the flags. Ask the user before spending on it. Adapt the field names to the eval's schema.

```
You are auditing one case from an evaluation suite. Given the prompt, the reference answer and a description of how the grader decides pass or fail, flag each issue below. Be conservative: flag only when reasonably confident.

PROMPT:
{prompt}

REFERENCE ANSWER:
{gold}

GRADER BEHAVIOUR:
{grader_description}

For each issue answer yes or no, with a one-line reason if yes:
- ambiguous: could two careful experts disagree on the correct answer?
- gold_suspect: does the reference answer look wrong, incomplete or arguable?
- answerable_from_memory: could a model answer without doing the intended work?
- grader_too_strict: would a clearly correct answer be rejected?
- grader_too_lenient: would a clearly wrong answer be accepted?
- trivially_cheatable: is there a shortcut that satisfies the grader without solving the task?

Return JSON: {"case_id": "...", "flags": {"<issue>": {"flagged": bool, "reason": "..."}}, "overall": "ok" | "review" | "broken"}
```

Group the results by flag, show the top issues with example case ids, and report them to the eval's author as observations and suggestions; the author often has context an outsider lacks.

Credit: adapted from anthropics/skills claude-api/shared/evals/eval-audit.md @ dbd4588 (Apache-2.0).
