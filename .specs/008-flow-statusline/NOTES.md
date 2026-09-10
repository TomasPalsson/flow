# Notes — 008 Flow statusline

Discovered: FR-03 and §4.2 demanded a "wave number" the router does not publish — `result.wave` is `{ ids, parallel }` with no ordinal, so T001 inferred `wave.ids.length`, which is the task count and renders 1, 1, 2, 1 across this very build — fold into T001 (found in its own review, pre-tick)

Ruling: 2026-09-10 — the `building` badge shows the wave's task IDs (`▸ T001`, `▸ T003 +1`) instead of an index. Rejected adding a wave ordinal to `router.js`: that file is shared with the whole harness and is outside this feature's blast radius, and the IDs answer "what is running right now" better than an index would. Spec §4.2, FR-03, Journey 1 and B3 amended to match.
