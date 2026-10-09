# Issues

## I-001 — the full scripts suite is red at base: ~96 failures unrelated to any in-flight spec
Found: 2026-09-19 · during 009-ecc-borrows · severity: major
Evidence: plugins/flow/scripts/tests/test_commands.sh:72 (asserts on commands/aside.md, but plugins/flow/commands/ no longer exists — deleted in spec 004); plugins/flow/scripts/tests/test_eval_cli.sh:300 and :368 (eval CLI ledger/exit-code tests fail on this machine); full-run log at base 5a95afa: 107 FAIL lines, 11 of them in test_install.sh from the TMPDIR trailing slash that 009's T012 fixes
Problem: `bash plugins/flow/scripts/tests/run.sh` cannot go green, so no spec can use the whole suite as a gate and a new regression hides among old ones
Whose: internal: the build — every spec's G00N gate and every `verify:` that runs a whole test file
Today: specs gate on the test files they touch (009's G003) and ignore the rest
Verify: `bash plugins/flow/scripts/tests/run.sh` exits 0 on a macOS machine with TMPDIR ending in '/'
Status: open

## I-002 — a blank or unparseable started_at silently disables a loop's max-minutes cap
Found: 2026-09-19 · during 009-ecc-borrows (gating review of 736cea7..d467d04, cross-file lens, blind score 90) · severity: major
Evidence: plugins/flow/bin/lib/loop/tick.js:62 (`(now - Date.parse(front.started_at)) / 60000 >= maxMinutes` — NaN compares false, so 'time' never fires); plugins/flow/bin/lib/loop/contract.js:80-86 (corruptReason checks iteration, max_iterations and verify, never started_at); 009's driver.js childTimeoutMs already guards its own copy of the arithmetic (a43b1c1)
Problem: a loop contract whose started_at is blank or garbled is not treated as corrupt, and its wall-clock budget stops being enforced without any log line
Whose: the loop operator who leaves `flow loop run` unattended with --max-minutes as the cost bound
Today: nothing stops it but max_iterations (default 30), which can run far past the minutes asked for
Verify: a test that blanks started_at in an active contract and asserts the loop either self-disarms as corrupt (preferred: corruptReason rejects a non-parseable started_at, fixing tick.js and driver.js at once) or stops with stop_reason time once max_minutes elapse
Status: open

## I-003 — eval scaffolds tell the candidate it is being graded
Found: 2026-10-09 · during the pstack borrow review (docs/research/23-pstack-borrow-2026-10-09.md) · severity: minor
Evidence: plugins/flow/evals/pipeline-fix-bug/scaffold.sh:18 sets `git config user.name "eval-scaffold"`; 40 files under plugins/flow/evals carry it (`grep -rln eval-scaffold plugins/flow/evals`); plugins/tooling/skills/agent-evals/SKILL.md now states the meta-word ban this breaks
Problem: a candidate that can see `eval` in its commit author knows it is being graded and may behave differently, so the suite measures test-taking, not normal behaviour
Whose: internal: anyone reading `flow eval` scores as evidence a skill change helped
Today: scores are taken at face value
Verify: `grep -rlnE 'eval|judge|rubric|benchmark|candidate' plugins/flow/evals/*/scaffold.sh` shows no candidate-visible identity, path or prompt with those words, and the suite's pass rates are re-baselined
Status: open — identities neutral (Dev <dev@example.com>) and case-selfcheck scan landed; live re-baseline of pass rates pending

## I-004 — skills-lint reports two dead references in plugins/flow/evals/README.md
Found: 2026-10-09 · during the pstack borrow review · severity: minor
Evidence: `node plugins/flow/bin/flow skills-lint plugins/flow` → `MISSING plugins/flow/evals/README.md:20 scripts/case-selfcheck` and `:114 scripts/tests/test_evals.sh`; same output on main at 702895a
Problem: the README links resolve against the wrong base directory, so skills-lint is never fully clean for the flow plugin
Whose: internal: skills-lint as a gate
Today: the two lines are ignored by hand
Verify: `node plugins/flow/bin/flow skills-lint plugins/flow | grep -c MISSING` prints 0
Status: open

## I-005 — loop negative-control test t_negcontrol_pid_output_refuses fails on main since 2026-10-09 midday
Found: 2026-10-09 · during the pstack borrow review · severity: minor
Evidence: `TEST_ONLY=test_loop_negcontrol.sh bash plugins/flow/scripts/tests/run.sh` → `FAIL t_negcontrol_pid_output_refuses names-reason`, `99 passed, 1 failed`, on main at 702895a and on worktree-pstack-borrows (which changes no loop code); the rc assertion (4) passes, only the "only its exit code can be trusted" message check fails; the same test passed in a full-suite run earlier the same day on the same machine
Problem: the reason text for a verifier whose output carries a PID is not printed (or differs) under some environment condition, so the suite has a time- or environment-dependent failure
Whose: internal: the scripts suite as a gate; loop operators reading why arming was refused
Today: ignored as pre-existing
Verify: the test passes on three consecutive runs, and the refusal names the reason whenever rc is 4
Status: open

## I-006 — bin/lib/router.js is 682 lines, over the 400-line size guard
Found: 2026-10-09 · during the pstack borrow round 2 · severity: minor
Evidence: `wc -l plugins/flow/bin/lib/router.js` → 682 on main at 702895a; size-guard.sh blocks every edit to it ("file is 692 lines (max 400)") — the round-2 claim-check gate was moved into lib/lint.js `withClaimCheck` to keep router.js at its old size
Problem: any change to the router trips the size guard, so fixes there get pushed into other modules or need the escape hatch
Whose: internal: anyone changing `flow next` routing
Today: edits route around it
Verify: router.js under 400 lines after a split (e.g. feature resolution and lint runner into their own modules) with test_next.sh unchanged and green
Status: open
