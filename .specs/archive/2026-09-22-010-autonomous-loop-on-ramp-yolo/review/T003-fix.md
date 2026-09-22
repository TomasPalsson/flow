# Fix brief — T003 (one dispatch, all findings)

Your original brief is at `.specs/010-autonomous-loop-on-ramp-yolo/review/T003-brief.md` — every
rule in it still binds, including the files: list. Two independent adversarial reviewers both
returned BLOCK on commit 8b58659 with executed receipts. Fix all of the below in one commit.

Files you may touch — unchanged from the original brief, no others:
  plugins/flow/bin/lib/loop/negcontrol.js
  plugins/flow/bin/lib/loop/init.js
  plugins/flow/scripts/tests/test_loop_negcontrol.sh

Reusable probe fixtures from the reviewer: /Users/tomas/.claude/jobs/97ed1603/tmp/probe.sh .. probe5.sh

## Fatal — each has a reproduced receipt

F1. `negcontrol.js:49` decides the verdict with `if (after.sig === before.sig)` alone. `sig` hashes
    the verifier's TEXT OUTPUT (`verify.js:13-19`); the exit code is never compared. Wrong in both
    directions, both reproduced:
      (a) A verifier that never reads the broken file but prints a PID, a nanosecond timestamp, a
          mktemp path or a run counter ARMS THE LOOP (rc=0). Real test runners print all of these.
      (b) `--verify 'test -s app.txt' --allow-green` — green before the break, red after, prints
          nothing — is REFUSED (rc=4). That is precisely the verifier spec.md §4.1 FR-04 wants.
    Fix: the verdict compares the pair (exit-code class, sig). A change in EITHER is a real change;
    no change in both is `survived`.

F2. `negcontrol.js:17` uses `fs.writeFileSync`, which follows symlinks. A tracked symlink pointing
    outside the repo had its target permanently overwritten; `git checkout` cannot restore it, and
    the refusal message named the link, not the file actually destroyed. Guard with `lstat` and
    refuse a symlink target at exit 3.

F3. No dirty-tree preflight. `design.md:43` mandates one in `negcontrol.js` at exit 3. Reproduced:
    uncommitted work in the target file was silently replaced by HEAD's bytes, because the restore
    is `git checkout -- <file>`. The code notices only AFTER the data is gone (restored=false → 5).
    The guard must run BEFORE anything is written.

F4. No tracked-file preflight. `design.md:112` and `design.md §7` are explicit: a target that names
    no tracked file MUST exit 3 rather than skip. Reproduced: an untracked file was truncated to
    0 bytes unrecoverably; a missing file and a directory each produced a raw Node stack trace at
    `negcontrol.js:35` and exit 1, which breaks design §3's closed set of codes each with a
    one-line reason. Use `git ls-files --error-unmatch`.

F5. No `try/finally` and no signal handler around the break→restore sequence
    (`negcontrol.js:36-39`). FR-05 demands restoration "whether it passed, failed, or was
    interrupted". Reproduced with a verifier that sends SIGTERM to its parent once the file is
    empty: rc=143 and `app.txt` left at 0 bytes forever. Wrap the sequence in `try/finally` AND
    restore on SIGINT/SIGTERM.
    Note the test that claims to cover this does not: `t_negcontrol_restores_tree` only trips
    `runVerify`'s own timeout, and `verify.js:31-35` catches ETIMEDOUT and RETURNS NORMALLY with
    rc 124 — so control reaches the restore on the ordinary path. That test passes with zero
    interruption safety.

## Significant

S6. `test_loop_negcontrol.sh:68`'s assertion named `tree-byte-identical` does not test byte
    identity: `assert_eq "$(cat app.txt)" "the app"` — command substitution strips trailing
    newlines, so `"the app\n\n\n"` passes — and it checks one file, not the tree.
    RULING (recorded in NOTES.md): FR-05 is scoped to TRACKED files. `verify.js:38-39` writes
    `.claude/loop/verify.last` on every run; that predates this feature and is the loop's own
    scratch. Do NOT move `ensureLoopGitignore` to fix it. Assert instead: `git status --porcelain`
    reports no tracked-path change, AND `git hash-object <target>` is unchanged across the call.

S7. Only refusal paths are tested (rc 4 and rc 6). Add tests for:
      - the happy path: a genuine verifier goes red under the break and the loop ARMS (this is what
        let F1(b) ship green);
      - `not-restored` → exit 5, the one code design §3 permits to leave the tree modified;
      - an interrupted control (F5) leaving the target byte-identical;
      - each new exit-3 refusal (symlink, dirty, untracked, missing, directory) — and assert the
        stderr reason names the file, and that NO contract file exists afterwards (FR-11).

## Improvable

I8. `init.js:112` prints "the negative control did not return within its time bound" whenever
    `after.rc === 124`. In the shipped test the control returned in ~1.1s against a 2s bound — the
    VERIFIER timed out, not the control. Two distinct messages: one for a verifier that hung, one
    for the control exceeding 2× verifyTimeout. The operator tunes a different number for each.

## Out of scope — do NOT fix, already recorded in NOTES.md
- The gate is opt-in (`init.js:104`), so nothing in the product runs it yet. Wiring `--yolo` to
  always pass the flag is T004/T006's job.
- Nothing writes the `yolo` / `fail_closed` / `neg_control_file` / `neg_control_at` front-matter
  fields. Folded into T004.

## Acceptance
`TEST_ONLY=test_loop_negcontrol.sh bash plugins/flow/scripts/tests/run.sh` exits 0, and
`TEST_ONLY=test_loop.sh bash plugins/flow/scripts/tests/run.sh` still exits 0. Every new test must
be shown RED against the current HEAD before you make it pass; report those exit codes. Do not tick
the box — the orchestrator re-runs verify: and runs flow tick T003.
