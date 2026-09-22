# G002 fix brief — three verified branch-review findings (spec 010, --yolo on-ramp)

Base: 6df8760. Repo: /Users/tomas/Desktop/Projects/flow. Fix all three in this one job.
Commit message describes the change (e.g. `fix(loop): ...`). Never edit, skip or weaken an existing
assertion to go green; changing a test's *invocation* to satisfy a new requirement is fine and must be
said in the commit body.

## Files you may touch (nothing else)
- plugins/flow/bin/lib/loop/init.js
- plugins/flow/skills/loop/references/yolo-bootstrap.md
- plugins/flow/skills/loop/SKILL.md (only if its Step 0 text quotes the old `&&` recipe or says --neg-control-file is optional under --yolo)
- plugins/flow/scripts/tests/test_loop_yolo.sh
- plugins/flow/scripts/tests/test_loop_negcontrol.sh

## F1 (fatal) — the documented verifier recipe can never pass the negative control
yolo-bootstrap.md §3 (~line 63) composes `node -e "<every item passes>" && <scoped test command>`.
At init every item is `passes:false`, so the gate clause exits 1 and `&&` short-circuits: the scoped
tests never run, before AND after the break the rc (1) and output (empty) match, `runNegControl`
(negcontrol.js ~184, `rcChanged || outputChanged`) returns `survived`, and init refuses (exit 4).
Repro: a git repo with `.claude/loop/tasks.json` `{"items":[{"files":["app.js"],"passes":false}]}`,
tracked app.js + test_app.js, verify = the §3 template, `flow loop init "g" --verify "$V" --neg-control-file app.js --yolo` → exit 4.
Fix: change the recipe so the scoped tests ALWAYS run and the command fails if either clause fails,
scoped tests first, e.g.
  `<scoped test command>; t=$?; node -e "...every(i=>i.passes)?0:1" && exit $t`
Update the prose below it to explain why (the control must see the test clause's output change).
Test: add `t_negcontrol_yolo_recipe_arms` in test_loop_negcontrol.sh that builds exactly the repro
above with the NEW recipe (a real test_app.js that fails when app.js is broken) and asserts init does
NOT exit 4 (it arms or proceeds past the gate). Optional but good: a companion asserting the OLD `&&`
form exits 4, documenting why.

## F2 (fatal) — --yolo arms with no negative control
init.js:117 `if (!args.negControlFile) return 0;` — so `flow loop init "g" --verify true --allow-green --yolo`
arms an unattended run on a verifier that can never fail. spec.md:17 and FR-04: the control is the
mandatory gate for --yolo. Fix: when `args.yolo` and no `args.negControlFile`, refuse before
writeContract with a one-line stderr reason naming `--neg-control-file` and a non-zero exit; use exit 3
(the "nothing was touched / input rejected" code the gate already uses). No contract file may be written.
Test: `t_yolo_requires_neg_control` in test_loop_yolo.sh: `--yolo` without `--neg-control-file` → rc 3,
stderr names `--neg-control-file`, no `.claude/loop/loop.md`.
The existing yolo tests (t_yolo_default_caps, t_yolo_explicit_cap_kept, t_yolo_child_argv) call
`--yolo --verify false` with no control and will now fail. Change their fixture/invocation so they arm
legitimately: a tracked file plus a verifier that is red and whose output changes when that file is
broken (e.g. `--verify 'cat src.txt; exit 1'` with tracked src.txt, `--neg-control-file src.txt`), and
keep every existing assertion byte-identical. Read how negcontrol.js breaks the file first so the
fixture really arms.

## F3 (significant) — neg_control_file / neg_control_at never written
design.md lines 31-32: `neg_control_file` (repo-relative path | '') and `neg_control_at`
(ISO-8601 UTC | '', when the control last passed) belong in the contract front via buildInitFront.
Only yolo/fail_closed are written (init.js ~212). Fix: write both; set them only when the gate ran and
passed (red-then-restored); '' otherwise. Keep it minimal — e.g. runNegControlGate records the pass
on `args` or returns it, and buildInitFront reads it. Note buildInitFront is called relative to the gate
at init.js ~289-295; check the order.
Test: in test_loop_yolo.sh (or negcontrol), after a successful arm with a control, loop.md has
`neg_control_file: <path>` and a non-empty ISO `neg_control_at`; without --yolo and without a control,
both are empty.

## Acceptance (run all, paste real counts)
TEST_ONLY=test_loop_yolo.sh bash plugins/flow/scripts/tests/run.sh
TEST_ONLY=test_loop_negcontrol.sh bash plugins/flow/scripts/tests/run.sh
TEST_ONLY=test_loop.sh bash plugins/flow/scripts/tests/run.sh
TEST_ONLY=test_loop_docs.sh bash plugins/flow/scripts/tests/run.sh
TEST_ONLY=test_loop_failclosed.sh bash plugins/flow/scripts/tests/run.sh
TEST_ONLY=test_next.sh bash plugins/flow/scripts/tests/run.sh
All exit 0, 0 failed. Write each new test first and show it red before the fix.
