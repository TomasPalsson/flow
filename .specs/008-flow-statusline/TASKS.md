# Tasks — Flow statusline
Approved: 2026-09-10 by user
Spec: spec.md · Design: design.md · Base: bf6b270 · Route: dispatch · Test: `plugins/flow/scripts/tests/run.sh`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given the §4.1 FR-01 fixture stdin, when the line renders, then the model segment is exactly `Opus 5 \| ✨ MAX \| 📊 ctx 34%` (FR-01) | T001 | t_statusline_model_segment |
| B2 (P0) | Given a cache entry for any of the 21 state names, when the line renders, then the slug and that state's §4.2 glyph and label appear (FR-02) | T001 | t_statusline_all_states |
| B3 (P0) | Given a cache entry at row 6, when the line renders, then the running task IDs appear — `▸ T001` for one, `▸ T003 +1` for two (FR-03) | T001 | t_statusline_wave |
| B4 (P0) | Given the §4.2 table, when the `✋` set is compared to the router's `human_gate` set, then they are equal (FR-04) | T003 | t_statusline_human_gate_parity |
| B5 (P0) | Given a `.specs/` tree, when the line renders 50 times, then the tree is byte-identical including `.next-call-count` (FR-05) | T003 | t_statusline_never_writes |
| B6 (P0) | Given a cwd with no `.specs/`, when the line renders, then only the model segment is printed and the exit code is 0 (FR-06) | T002 | t_statusline_no_project |
| B7 (P0) | Given a missing binary, malformed stdin, an unreadable cache or a throwing router, when the line renders, then the exit code is 0 and the model segment is printed (FR-07) | T002 | t_statusline_never_fails |
| B8 (P0) | Given a fixture HOME, when `--install` runs, then `statusLine` is merged, the other keys are untouched and a backup path is printed (FR-08) | T002 | t_statusline_install |
| B9 (P0) | Given a fixture HOME whose settings do not parse, or already carry a `statusLine`, when `--install` runs, then nothing is written and the exit code is 1 (FR-08) | T002 | t_statusline_install_refuses |
| B10 (P0) | Given a fixture HOME, when `--print` runs, then valid JSON is emitted and HOME is byte-identical (FR-09) | T002 | t_statusline_print |
| B11 (P1) | Given a settings file naming a status line command that does not resolve, when doctor runs, then the `statusline` check does not report PASS (FR-10) | T002 | t_statusline_doctor |
| B12 (P2) | Given `--no-color` or `NO_COLOR=1`, when the line renders, then it contains no escape sequences (FR-11) | T001 | t_statusline_no_color |
| B13 (P0) | Given the slug `002-cross-worktree-spec-numbers-zellij-pane`, when the line renders, then the segment is ≤ 40 chars and still ends in the full badge (FR-12) | T001 | t_statusline_elide |
| B14 (P0) | Given a router stubbed to sleep 10 s, when the line renders, then it still returns, inside the §5 budget (FR-13) | T003 | t_statusline_never_waits |
| B15 (P0) | Given a state change, when a later render happens with no command typed, then the badge is current within one cache period (FR-14) | T003 | t_statusline_refreshes |
| B16 (P0) | Given ten renders fired back to back against a cold cache, when they run, then at most one refresh child is alive (FR-15) | T003 | t_statusline_one_refresh |
| B17 (P0) | Given a cache entry older than 60 s, when the line renders, then the segment carries a trailing `~` (FR-16) | T001 | t_statusline_stale_marker |

## Phase 1 — The render and the cache format
Goal: every state and every cache age has exactly one rendering, testable from a literal object with no repo, no router and no subprocess.
Independent test: `node -e "require('./plugins/flow/bin/lib/statusline.js')"` plus the T003 unit assertions — green with `bin/flow` untouched.
- [x] T001 Badge table, tones, elision, cache read/write, and the render functions (B1, B2, B3, B12, B13, B17) — files: plugins/flow/bin/lib/statusline.js — verify: `node -e "const s=require('./plugins/flow/bin/lib/statusline.js'); const r=require('./plugins/flow/bin/lib/router.js'); const missing=Object.keys(r.STATE_NO).filter(k=>!s.BADGES[k]); if(missing.length) throw new Error('no badge for: '+missing); for(const f of ['renderLine','modelSegment','flowSegment','elide','cachePath','readCache','writeCache']) if(typeof s[f]!=='function') throw new Error(f+' missing'); const src=require('fs').readFileSync('./plugins/flow/bin/lib/statusline.js','utf8'); if(/require\(.(child_process|.*router).\)/.test(src)) throw new Error('layer 1 must not import router or child_process'); console.log('ok')"` — done: e7f7288

## Phase 2 — The subcommand and the refresh child
Goal: `flow statusline` is wired, never waits, never fails, holds one lock, and can install itself into the user's settings on request.
Independent test: `plugins/flow/bin/flow statusline --print` — valid JSON, with no `.specs/` in the cwd.
- [x] T002 `statusline` subcommand, `--refresh` with the pid lock, `--install`, `--print`, `--no-color`, and the `statusline` doctor check (B6, B7, B8, B9, B10, B11) — files: plugins/flow/bin/flow — verify: `plugins/flow/bin/flow statusline --print` — after: T001 — done: 8771971

## Phase 3 — Proof and docs
Goal: a reviewer other than the author can prove every MUST, including the two that only a hostile fixture can prove — that a render never waits, and that ten renders never become ten routers.
Independent test: `TEST_ONLY=test_statusline.sh plugins/flow/scripts/tests/run.sh` — green.
- [x] T003 Fixture-driven tests: all 21 states, the `✋`/`human_gate` parity assertion, the four fault injections, the three install paths, the zero-writes tree hash, the 10 s-stub latency assertion, and the single-refresh lock assertion (B4, B5, B14, B15, B16) — files: plugins/flow/scripts/tests/test_statusline.sh — verify: `TEST_ONLY=test_statusline.sh plugins/flow/scripts/tests/run.sh` — after: T002 — done: eaf333b
- [x] T004 [P] Document the subcommand, the cache and its staleness marker in the plugin README and the CLI reference — files: plugins/flow/README.md, docs/reference/workflows-and-cli.md — verify: `grep -q "flow statusline" plugins/flow/README.md docs/reference/workflows-and-cli.md` — after: T002 — done: e670855
- [ ] CHK001 human-verify the installed line reads correctly at a real human gate and the refresh never stalls the terminal — files: .specs/008-flow-statusline/verify/CHK001.md — verify: human: user installs it, drives one build turn to an unapproved or checkpoint state, and confirms the `✋` badge and slug are legible and that typing never lags — after: T003

## Gates
- [ ] G001 project gates clean — files: . — verify: `flow check --fix`
- [ ] G002 branch review clean — files: . — verify: `test -f PASS-$(git rev-parse --short HEAD).md`
- [ ] G003 full harness suite green — files: . — verify: `plugins/flow/scripts/tests/run.sh`
