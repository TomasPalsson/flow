# Acceptance — Delegate skill

Run at d17e12c on 2026-11-11. Every command is run from `.specs/010-delegate-skill/verify/` and is a plain grep on a log, with no pipe, so the exit code is the grep's own.

Logs: `acceptance-prose.log` is `TEST_ONLY=test_delegate_prose.sh bash plugins/flow/scripts/tests/run.sh` (the runner itself exits 1 on 5 shellcheck failures that are in `baseline-tests.txt`; the log holds 41 `ok   delegate` lines and 0 `FAIL` lines naming delegate). `full-suite-head.log` is the full `Test:` command at d17e12c: 5886 passed, 182 failed, and no FAIL line that is absent from `baseline-tests.txt`.

| Criterion | Command | Exit | Showed |
|---|---|---|---|
| FR-01 stay inline | `grep -q '^  ok   delegate keeps an edit shorter than its brief in the main session' acceptance-prose.log` | 0 | the stay-inline rules are written in SKILL.md (4 assertions in t_delegate_stay_inline_cases, all ok) |
| FR-02 pin model | `grep -q '^  ok   delegate forbids Fable with no condition attached' acceptance-prose.log` | 0 | pin model on every spawn, a worker is never Fable with no condition, never a fork (4 assertions, all ok) |
| FR-03 model ladder | `grep -q '^  ok   delegate re-runs a failed Haiku check on Sonnet' acceptance-prose.log` | 0 | Haiku row, Sonnet row, Opus conditions and the Haiku fallback (7 assertions, all ok) |
| FR-04 brief template | `grep -q '^  ok   delegate brief template has Tools allowed:' acceptance-prose.log` | 0 | the six brief fields are present (6 assertions, all ok) |
| FR-05 report format | `grep -q '^  ok   delegate verifies by re-running the acceptance command' acceptance-prose.log` | 0 | verdict, files changed, failing output only, 15 lines, verify by re-run (5 assertions, all ok) |
| FR-06 wave cap | `grep -q '^  ok   delegate does not contradict its own four-worker cap' acceptance-prose.log` | 0 | two to four workers, one worker for overlap, no polling, more than four is a Workflow (6 assertions, all ok) |
| FR-07 short and lints | `grep -q '^  ok   delegate collides with no other flow skill' acceptance-prose.log` | 0 | SKILL.md exists at 63 lines, frontmatter lint exits 0, no collision pair names it (6 assertions, all ok) |
| FR-08 listed in docs | `grep -q '^  ok   delegate docs: plugins.md lists delegate' acceptance-prose.log` | 0 | plugins.md counts 14 and lists delegate, README names it (3 assertions, all ok) |
| FR-09 eval waiver | `grep -q '^  ok   every flow skill has a case or a NO-EVAL.txt waiver' full-suite-head.log` | 0 | the eval coverage test passes with the delegate waiver line |

Not proven by any row: that a session which loads the skill then delegates less or pins a cheaper model. The prose test proves the rules are written down, and nothing else.
