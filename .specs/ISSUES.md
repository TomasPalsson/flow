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
