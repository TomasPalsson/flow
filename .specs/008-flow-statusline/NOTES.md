# Notes — 008 Flow statusline

Discovered: FR-03 and §4.2 demanded a "wave number" the router does not publish — `result.wave` is `{ ids, parallel }` with no ordinal, so T001 inferred `wave.ids.length`, which is the task count and renders 1, 1, 2, 1 across this very build — fold into T001 (found in its own review, pre-tick)

Discovered: design.md §5 listed `isTTY` as a colour input, so T002 gated ANSI on it — but Claude Code always pipes a status line command's stdout, so FR-04's human-gate colour would never once have rendered. Verified: piped output carried zero escape sequences before the fix, and the operator's own existing status line proves the harness renders the ANSI it is handed — fold into T002 (found in its own review, pre-tick)

Discovered: §5's "render latency p95 < 100 ms" is unmeetable by any Node CLI — bare `node -e ''` is 56 ms median here. Measured 113 ms median / 129 ms p95 warm and 134 ms median / 186 ms max cold, against a router at 5100 ms — fold into T002 (number corrected, code unchanged)

Ruling: 2026-09-10 — colour is on unless `--no-color` or `NO_COLOR` says otherwise, never gated on `isTTY`. A status line is always piped; a tty test silences the one signal the feature exists to show.

Ruling: 2026-09-10 — the §5 render-latency bar is p95 < 300 ms, Claude Code's own throttle interval, not 100 ms. The binding proof of FR-13 is the 10 s router stub, not the millisecond count: the number says the render is cheap, the stub says it never waits.

Ruling: 2026-09-10 — the `building` badge shows the wave's task IDs (`▸ T001`, `▸ T003 +1`) instead of an index. Rejected adding a wave ordinal to `router.js`: that file is shared with the whole harness and is outside this feature's blast radius, and the IDs answer "what is running right now" better than an index would. Spec §4.2, FR-03, Journey 1 and B3 amended to match.
