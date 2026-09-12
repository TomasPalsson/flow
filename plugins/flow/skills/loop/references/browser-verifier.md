---
name: browser-verifier
description: How to write a --verify command that drives a real browser against a real localhost build — the query-vs-assertion trap, the one-simple-command rule, and the ladder from curl to a target-match score. Load when the loop's goal is a UI behaviour or a visual target.
---

# Browser verifier — a check that can actually fail

A verifier that boots a browser has three extra ways to lie beyond the ones in `verifier-design.md`. Each trap below was measured against `agent-browser` 0.23.4 on a real localhost page; none of it is theoretical.

## 1. Three traps, each one a verifier that cannot fail

### (a) Queries are not assertions

`agent-browser`'s `is` and `get count` subcommands report "could I look?", not "was it true?". Their exit code is not the answer.

| Command | Prints | Exit |
|---|---|---|
| `agent-browser is visible '#present-and-shown'` | `true` | 0 |
| `agent-browser is visible '#present-but-hidden'` | `false` | **0** |
| `agent-browser is visible '#absent'` | error | 1 |
| `agent-browser get count '#absent'` | `0` | **0** |

`--verify "agent-browser is visible '#modal'"` passes whether the modal is open or closed. The exit code is the trap; the printed value is the fact. Always compare it:

```bash
test "$(agent-browser is visible '#modal')" = "true"
```

A hidden element does not fail `is visible` reliably in every driver version — the fact that never lies is a 0×0 bounding box:

```bash
agent-browser --json get box '#modal'   # {"success":true,"data":{"width":0,"height":0,...}}
```

`width>0 && height>0` catches "present but hidden" the same way it catches "collapsed to nothing" — one check, two failure modes.

### (b) The verify string must be one simple command

`flow loop` runs the verifier as `sh -c '<verify>'` under a `timeout`. With `a && b`, `sh -c` never `exec`s into the final command — it stays a parent shepherding a child. When the timeout fires, `SIGTERM` lands on the `sh -c` wrapper, not on the browser test it spawned; the test (and the dev server it started) leaks past the deadline and serves the *next* iteration's screenshot. A verifier that boots anything is one simple command — a script, not a chain:

```bash
--verify "sh tests/ui/verify.sh"
```

`tests/ui/verify.sh` (copy from `templates/ui-verify.sh`) does the composing internally, with its own trap on `EXIT` to kill the server it started. Pure, non-server commands (`tsc`, a test runner) are the one case where `&&` is still correct — see `verifier-design.md` §2.

### (c) `curl -s` exits 0 on a 500

`curl -s -o /dev/null "$URL"` is green for a 500 Internal Server Error; the `-f` flag is what turns an HTTP error into a non-zero exit:

```bash
curl -sf -o /dev/null "$URL"
```

The same distinction matters at every rung above curl: "the app crashed on boot" and "the assertion failed" are different facts, and a verifier that reports both as one red line trains the model to guess. `ui-score` (§4) draws this line with exit codes: **exit 2 = harness broke** (app not up, no baseline, missing tool) vs **exit 1 = a gate failed** (the app is up and wrong). Never report a harness break as a gate failure — the model cannot fix a server that never started.

## 2. The ladder — climb only as far as the goal needs

| Rung | Goal | Command |
|---|---|---|
| 1 | route is alive | `curl -sf -o /dev/null "$URL"` |
| 2 | one element/behaviour | `sh tests/ui/verify.sh` (copy `templates/ui-verify.sh`) |
| 3 | a full user flow | the project's own e2e runner if one exists; if it is Playwright, `--retries=0 --forbid-only` are mandatory — the scaffolded config sets `retries: 2` on CI, `flow loop` sets `CI=true`, and a flaky test would pass on retry and teach the loop nothing |
| 4 | matches a visual target | `sh tests/ui/verify.sh` (§4) — `ui-score score` never boots a server itself; run it through the wrapper (variant (b) in `templates/ui-verify.sh`), never as a bare `--verify` string, or it scores whatever stale process already owns the port |

Stop at the first rung that states the goal. Rung 4 is expensive to calibrate (§4) and should not be reached for "the button works".

## 3. Determinism checklist

The wedge detector sha1s the verifier's output; anything that varies run-to-run for the *same* failure defeats it.

| Requirement | Why |
|---|---|
| Fixed viewport (`agent-browser set viewport W H`) | layout reflows change every downstream measurement |
| `agent-browser set media light reduced-motion` | animation frames make screenshots and timing non-deterministic |
| Production build, not the dev server | HMR overlays, source-map banners, and websocket-reconnect UI paint over the real page |
| Poll with `curl -sf`, never `sleep` | a fixed sleep is either too short (flaky) or too long (wastes the verify budget) on every machine that isn't the one it was tuned on |
| Refuse to run if the port is already busy | a stale server from a killed previous iteration answers instead of the current build, and the verifier "passes" against yesterday's code |
| Trap-kill the process group on exit | a lone `kill $PID` misses children the server forked; `kill -- -$$` targets the *script's own* pgid, which is usually inherited from its parent and not `$$` — it measures as a no-op (`kill: (-$$) - No such process`). Instead background the server under `set -m` so its own pid becomes its own pgid, capture `SERVE_PID=$!`, and `kill -TERM -"$SERVE_PID"` — see `templates/ui-verify.sh` |
| Stub external network | a flaky third party turns the loop's wedge detector against the wrong thing |
| No timings, temp paths, or random ids in the output | the same failure must hash to the same signature — see §1(a)'s harness note in `verifier-design.md` §2 |

## 4. Matching a visual target — the frozen `ui-score` CLI

```
plugins/flow/scripts/ui-score capture --target <dir> --url <url> [--viewports 1280,480] [--height 900]
plugins/flow/scripts/ui-score capture --target <dir> --from-image <png> --viewports <W>
plugins/flow/scripts/ui-score score   --target <dir> --url <url>
```

`score` is a **conjunction of gates** — structure, then pixels, per viewport — never a weighted average. A scalar score lets pixel fidelity buy off a missing `<h1>`: a hand-built cheat page of absolutely-positioned divs, no real DOM structure at all, was measured scoring 0.00% pixel mismatch against its target. Pixels alone are not a verifier; optimising visual similarity as the only signal has been measured to make models produce *worse* pages than not optimising for it at all, because the model finds the shortest path to matching colours, not to matching structure.

Human setup, once, out of band (never inside `--verify`):

1. `plugins/flow/scripts/ui-score capture --target .loop-target --url http://localhost:3000` — screenshots each viewport and seeds `expect.json`.
   - Starting from a design mock instead of a live build: `plugins/flow/scripts/ui-score capture --target .loop-target --from-image design.png --viewports 900` (exactly one width — a mock has one). It resizes to that width, prints the height that came from the mock's own aspect ratio, and always seeds `expect.json` with an empty `must` list — a PNG cannot tell you its selectors, so step 2 below is not optional and `score` refuses to run until you've done it. Ceiling: a single-viewport mock cannot prove the layout reflows; hand-capture a second width if reflow matters.
2. Trim `expect.json`'s `must` list to the 3–5 selectors that define "this page, not a picture of it" (a nav, the primary heading, the CTA — not every `<div>` `capture` found).
3. Run `plugins/flow/scripts/ui-score score --target .loop-target --url http://localhost:3000` once against the current page to read the actual mismatch percentage. That reading tells you how far away the page **starts**, not the bar to set — `maxMismatchPct` is the bar you actually want to clear. Set it below the reading (typical: read 11%, set 3%). There is no `--calibrate` flag and no baseline-update path.
4. `.loop-target` in `permissions.deny` (`Read`, which also blocks `Edit`/`Write`) stops Claude's own file tools from touching the target — it does **not** stop a subprocess that opens files itself, which is exactly how `cp` and `playwright test -u` overwrite a baseline. Add it as a first layer, but the actual enforcement is the byte hash `loop init --target` records next (step 5); that hash is what `flow loop check` re-verifies every iteration, `permissions.deny` is not.
5. `flow loop init "<goal>" --target .loop-target --verify "sh tests/ui/verify.sh"` — copy `templates/ui-verify.sh`, uncomment its variant (b) assertion (`"$FLOW_UI_SCORE" score --target .loop-target --url "$BASE_URL" || exit $?`). `loop init`'s own `--target` (distinct from the `--target` inside `ui-score`'s own args) byte-freezes the directory into the contract's `target_sha`; omit it and the baseline PNGs and `expect.json` have no tamper protection at all.

### What the hashes do *not* cover — the honest ceiling

`target_sha` freezes the target directory and the script the verify string names; `env_sha` freezes `ui-verify.sh`'s boot config, and only for a `--target` loop. Nothing freezes **what that boot command transitively runs**. The template's default `SERVE` is `npm run preview`, so rewriting `package.json`'s `preview` script — or any file the real server reads — re-points the whole verification at a different process while every hashed file stays byte-identical. The same hole exists one level down for anything `verify.sh` shells out to.

That residue is what a held-out check is for: CI on a protected branch the agent's shell cannot reach, compared against the loop's own green. A hash chain that tried to follow every subprocess would be a package manager, not a verifier.

## 5. Anti-patterns — never

- An LLM/VLM judging the exit condition — a nondeterministic verifier disables flow's own wedge detector, which sha1s the output.
- Any "accept the current render" or baseline-update path — there is no way to launder a bad page into the new target from inside the loop.
- Asserting against a fixture file instead of the running app — the fixture drifts from the code and the verifier stops meaning anything.
- Widening `maxMismatchPct` (or any mismatch budget) instead of fixing the page.
- Treating `maxMismatchPct`, or any gate, as a best-so-far ratchet ("pass if better than last run") instead of the absolute threshold frozen inside the hashed target. A ratchet needs state; any file the loop can reach is model-writable; and "beat the best" has no fixed point, so it never terminates. The trend belongs in the `LEARNINGS.md` entry the loop prompt already mandates, where it gates nothing.
- A bare `sleep` waiting for the server or the page to settle.
- A hardcoded port — it collides with whatever else is running and makes "port already busy" a false positive.

ponytail: no `scrollWidth` overflow gate here — it would need `agent-browser eval`, one more surface to keep deterministic. Scoring at two viewports (§4) already catches the layouts that overflow; add the eval-based gate only if a real bug slips through both viewports.
