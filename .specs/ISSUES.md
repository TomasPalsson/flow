# Issues

## I-001 — the full scripts suite is red at base: ~96 failures unrelated to any in-flight spec
Found: 2026-09-19 · during 009-ecc-borrows · severity: major
Evidence: plugins/flow/scripts/tests/test_commands.sh:72 (asserts on commands/aside.md, but plugins/flow/commands/ no longer exists — deleted in spec 004); plugins/flow/scripts/tests/test_eval_cli.sh:300 and :368 (eval CLI ledger/exit-code tests fail on this machine); full-run log at base 5a95afa: 107 FAIL lines, 11 of them in test_install.sh from the TMPDIR trailing slash that 009's T012 fixes
Problem: `bash plugins/flow/scripts/tests/run.sh` cannot go green, so no spec can use the whole suite as a gate and a new regression hides among old ones
Whose: internal: the build — every spec's G00N gate and every `verify:` that runs a whole test file
Today: specs gate on the test files they touch (009's G003) and ignore the rest
Verify: `bash plugins/flow/scripts/tests/run.sh` exits 0 on a macOS machine with TMPDIR ending in '/'
Status: open
