# Optimisation loop — one iteration

You are one fresh iteration of an unattended loop. The verifier is `flow eval --tag pipeline --tag quality --tag routing --runs 1 --threshold 0.9`; it decides when the loop stops, not you. Your job in this iteration: make the flow pipeline produce less slop and route better, by editing the pipeline's own skill text, then stop.

## Read first, in this order
1. `plugins/flow/evals/ledger.jsonl` — the last three lines: which tags scored what.
2. The newest `plugins/flow/evals/results/<ts>/aggregate-result.json` — for every case whose `aggregates.score < 1`, read each failed grader's `explanation`, and the case's `case.yaml` to see what it demands.
3. `plugins/flow/skills/no-slop/references/rubric.md` — the rows the failed graders map to.
4. `.specs/007-plugin-eval-suite-and-optimisation-loop/loop-log.md` — what earlier iterations changed and what it did to the score. Append your own entry at the end of this iteration.

## Pick one cause, fix it at the root
Choose the single failed grader with the highest (cases affected × severity) and trace it to the skill text that should have prevented it. Typical roots:
- a skill did not fire on natural phrasing → its `description` in `plugins/flow/skills/<name>/SKILL.md` (add the phrasing the case used, keep under 1024 chars, keep the "Not for" clause); v2 hub skills are `spec`, `next`, `issue`, `fix`, `prep`, `loop`, `qa`, `audit`, `scrutinize-idea`;
- the pipeline wrote code that re-implemented a helper → `plugins/flow/skills/no-slop/references/developer-block.md` (the search step), `plugins/flow/scripts/task-brief` (is the block reaching the brief?), `plugins/flow/workflows/build-slices.js` implement prompt, `plugins/flow/skills/next/execution-prompt.md` GREEN;
- prep or spec asked several questions, picked silently, wrote artifacts before the one batched offer, or stopped without stating its route and positions → `plugins/flow/skills/prep/SKILL.md`, `plugins/flow/skills/spec/SKILL.md`;
- a spec carried implementation leaks or invented requirements → `plugins/flow/skills/spec/SKILL.md` and its references;
- a build skipped Red or weakened a test, or `/flow:next` did not build → `plugins/flow/skills/next/execution-prompt.md`, `plugins/flow/skills/next/SKILL.md`.

## Rules
- Edit ONLY files under `plugins/flow/skills/`, `plugins/flow/scripts/task-brief`, `plugins/flow/workflows/`. Never touch `plugins/flow/evals/` (tamper-protected), `plugins/flow/bin/`, or tests.
- One root cause per iteration. A change must be one paragraph or one description edit; if you cannot state in one sentence which grader it will flip, do not make it.
- Structural constraints over adjectives: numbers, formats, "exactly one", never "be concise".
- Keep every skill's `description` under 1024 characters and every SKILL.md under 300 lines.
- Run `bash plugins/flow/scripts/tests/run.sh` before committing; one known failure (`skills-lint reports no MISSING under commands/ (deployed HOME)`) is pre-existing. Any other failure: fix or revert your change.
- Commit with a message `loop(pipeline): <grader> — <one-line cause> — <file>` and the trailers `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` / `Claude-Session: https://claude.ai/code/session_011TmKgQT3m82ePt7cj8acCz`.
- Append to `loop-log.md`: iteration number, the grader targeted, the file and the change in one line, the hypothesis of the score effect. The verifier fills in the actual effect on the next line via the ledger.

Then stop. Do not run the eval yourself; the verifier does.
