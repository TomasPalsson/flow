# 009 ECC borrows — verification evidence

Measured by the orchestrator on macOS (shellcheck 0.11.0, jq 1.7.1, node 26), tree 95eff35.

## Gates

| Gate | Command | Exit | Result |
|---|---|---|---|
| G001 | `bash plugins/flow/hooks/tests/run.sh` | 0 | 1333 passed, 0 failed |
| G002 | whole-branch review 5a95afa..736cea7, 5 lenses (this branch's own review-diff.js), blind re-score ≥ 80 | — | 3 kept (2 defects) → one fix dispatch (1c9abf5, e1cdbe9, a43b1c1, 26b0d8d) → 3-lens re-look CLEAN; `failedLenses: []`, `incomplete: false` |
| G003 | `TEST_ONLY=<f> bash plugins/flow/scripts/tests/run.sh` for each touched file | 0 ×7 | loop 177, workflows 157, agents 100, skill_forge 65, doctor_hygiene 82, install 142, stealth 191 — all 0 failed |

Base before this feature: the hook suite had 7 failures and the scripts static checks 8 (T000, T011 fixed them); test_install.sh had 11 (T012 fixed them). The full scripts suite still carries ~87 pre-existing failures outside this feature — parked as I-001.

## Phase independent tests

| Phase | Result |
|---|---|
| 1 — green baseline and silent failures | test_loop 173/0, test_workflows 157/0 (before the gating fix) |
| 2 — advisory guards | hooks 1333/0, test_agents 100/0, test_skill_forge 65/0 |
| 3 — doctor hygiene | test_doctor_hygiene 80/0 (before the gating fix) |
| 4 — write confinement | test_install 142/0, test_stealth 191/0 |

## NFRs (spec §5)

| NFR | Target | Measured |
|---|---|---|
| Context hook cost | ≤ 80 ms (amendment b) | 40–50 ms, `/usr/bin/time -p` × 4 on a real 3.4 MB transcript |
| Doctor added time | ≤ 500 ms | worktree-hygiene 73 ms + personal-paths 74 ms + reference-docs 0 ms (`FLOW_VERBOSE=1 flow doctor`) |
| Noise | 0 WARNs from the three new checks here | worktree-hygiene PASS, personal-paths PASS, reference-docs PASS |
| Reliability | 0 turns blocked by new code | context-pressure and tamper-notice tests assert rc 0 / advisory; doctor rows are PASS/WARN only |
| Loop stop latency | cap + 5 s | t_loop_run_child_timeout_b1: 3 timeouts at a 1 s cap, test under 20 s |

## Real-data probe

`context-pressure.sh` on a real 3.4 MB session transcript printed `flow: context is ~530k tokens of a ~1000k window. …` — one note, then silent on the same bucket.
