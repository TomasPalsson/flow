# 14 — Browser and visual verification for unattended loops, 2026

How to give `/flow:loop` a UI goal — "the checkout confirmation renders after payment", "make this page match that target" — and get an exit code an agent cannot argue with. Written 9 September 2026 from a 6-angle research sweep (12 agents, every angle adversarially re-measured, 24 claims struck or downgraded), plus direct probes of `agent-browser` 0.23.4, Playwright, `odiff`, `axe`, Lighthouse and `chrome-devtools-mcp` on this machine, and reads of flow's own `verify.js` and `tamper.js`. Design adjudicated 10 September 2026 across three competing proposals (laziest-that-works, cannot-be-gamed, headline-feature), with the winning claim reproduced end to end before it was scored. Peer document: [`12-loop-engineering-2026.md`](12-loop-engineering-2026.md) — the loop mechanics are settled there and are not repeated here. What it produced in this repo: §10.

**Evidence grades.** **A** — vendor doc or source file read verbatim. **B** — arXiv/peer-reviewed result re-fetched. **C** — practitioner report, single source, not re-verified. **M** — measured on this machine during the sweep, exit codes read from a bare command (never through a pipe). **X** — circulating claim found to be wrong (§11). M is the dominant grade in this document, because almost every browser-tool claim worth having turned out to be false when read from docs and true only when run.

Shell commands marked **(verified locally)** were executed here. Everything else is trivially derivable from one that was.

---

## 0. The one-paragraph version

Nothing in flow's verifier contract breaks on a UI goal. `spawnSync('sh', ['-c', verify])` with exit 0 is the whole contract (A, `bin/lib/loop/verify.js`), and `agent-browser`, `playwright`, `curl` and `node` are already installed — a working UI loop needs **no code change at all**. What breaks is the *command a model naturally writes*, three times over: `agent-browser is visible '#cta'` prints `false` and **exits 0** when the element is present but hidden (M, twice, independently, on 0.23.4); a verify string containing a shell operator stops `sh` from `exec`ing, so the SIGTERM at `verify_timeout` never reaches the script, its trap never runs, and the dev server survives into the next iteration serving the **old build** — a silent wrong verdict, not an error (M); and `curl -s` exits **0** on an HTTP 500 (M). Each of those produces a verifier that *cannot fail*, which is the one failure the loop's whole architecture exists to prevent. And the guard flow believes it already has is not armed for that shape: `init.js` records the verify **script** in the contract but gates the byte hash behind `--target`, so the documented default `--verify 'sh tests/ui/verify.sh'` can be rewritten to `exit 0` and `flow loop check` still answers `verdict: pass`, `tamper: []` (M, reproduced end to end) — two edits to machinery already written close it, and they close assertion deletion, in-place weakening and `playwright test -u` with the same stroke (§10). For the harder half of the goal — "match this target" — the literature is decisive against the obvious design: UI2Code^N measured a pure visual reward scoring **62.0 against the 72.3 SFT baseline it started from** (B), so optimising pixel similarity made the model worse than not optimising, and the gate must be a **conjunction** of structure AND overflow AND pixels, never a weighted scalar. Two things are closed rather than re-litigated: Claude in Chrome cannot be a verifier (no shell entry point, no exit code, and it is switched off entirely under the API-key auth `flow loop run`'s children use — A), and a VLM judge cannot be the exit condition (~61% run-to-run agreement — B — and, the flow-specific reason nobody states, it makes `signatureOf` produce a fresh hash every iteration, disabling flow's own stall and wedge detectors).

---

## 1. Why a UI goal breaks the shell-verifier contract — and why it mostly does not

The contract, read from source (A, `plugins/flow/bin/lib/loop/verify.js`):

```js
const r = spawnSync('sh', ['-c', verify], {
  cwd: toplevel,
  env: Object.assign({}, env, { CI: 'true', FLOW_LOOP: '1' }),
  timeout: t * 1000, encoding: 'utf8',
});
```

Merged stdout+stderr to `.claude/loop/verify.last`; `ETIMEDOUT` → rc 124; `null` → rc 1; `sha1` of the first 60 masked lines is the run signature. That is all of it. A browser is just another subprocess.

**What genuinely differs about a UI goal:**

| Difference | Consequence | Fix |
|---|---|---|
| The check needs a **running server**, so the verifier owns a process tree | `spawnSync`'s timeout SIGTERMs the shell only. A *simple* command is `exec`d and the signal lands on it; a **compound** one (`a && b`, a pipeline) leaves survivors (M: `sh -c 'sleep 41'` left none; `sh -c 'sleep 42 \| cat'` and `sh -c 'true; sleep 43'` both survived) | the verify string is **one simple command**; composition lives inside the script |
| `verify_timeout` is a **soft** bound | `spawnSync` sends SIGTERM and waits — it never escalates to SIGKILL. Against a 3 s timeout a verifier blocked in one `sleep 30` returned at **33 s**; one in a 30 s poll loop at **42 s** (M) | the browser layer must carry its own bound (`globalTimeout`, a poll cap); flow's will not save it |
| Teardown can die mid-handler | At timeout node closes stdio, so an `echo` as the trap's **first** statement dies of SIGPIPE and the rest never runs. Reordered (kill first, print last) both markers appeared (M) | kill, unlink, *then* print |
| Browser CLIs are **query** tools, not assertion tools | `is visible`/`is enabled`/`is checked` print `true`/`false` and exit 0 for both; only a *missing element* exits 1 (M) | compare the value: `test "$(… is visible '#x')" = "true"` |
| The output carries **ports and PIDs** | `signatureOf` masks `[0-9a-f]{7,40}` and `<n>ms\|s`, so it swallows any all-digit run of 7+ chars but **not** 4–6 digits — exactly the range of ports (≤65535) and PIDs (≤99999). Measured: `signatureOf("…:53747") !== signatureOf("…:53755")`, while `signatureOf("x 1234567 y") === signatureOf("x 7654321 y")` (M, verified locally) | never print a port/PID on the success path; mask them in the failure dump |
| The test layer has **binary artefacts** | flow's tamper census counts files by path pattern; a rewritten baseline PNG is invisible to it | prefer a rung with no baseline file at all (§3, §5) |

**What does not differ, and is worth stating so nobody engineers around it:** the exit code, the timeout, the tamper veto, `LEARNINGS.md`, the stall/wedge detectors and the per-iteration prompt are all unchanged. A UI loop is a normal loop with a fussier verifier.

---

## 2. The browser-driver decision table

| Driver | Version measured | Shell entry point | Exit code on a failed assertion | Verdict |
|---|---|---|---|---|
| **Playwright** (`@playwright/test`) | 1.60.0 global here; 1.63.0 npm latest, released 2026-09-04 | `npx playwright test` | **1** on failure, **1** on "No tests found", **1** on a nonexistent spec path (M) | **Best gate.** Owns server boot and teardown via `webServer`; correct in every case tried |
| **agent-browser** (Vercel) | 0.23.4 (2026-03-31); latest 0.37.1 (2026-09-08) | `agent-browser …` | **1** on a missing element and on a nav failure; **0** when the assertion is merely false (M) | **Usable**, only via `test "$(…)" = …`. No install ceremony, no npm project |
| **chrome-devtools-mcp** CLI | 1.9.0 | `chrome-devtools <cmd>` (the `chrome-devtools` bin, not `chrome-devtools-mcp`) | **0** on a throwing `evaluate_script`; **0** on navigating to a dead server; only yargs parse errors exit 1 (M) | **Never a verifier.** Strictly worse than agent-browser — it has no throw idiom to fall back on |
| **Claude in Chrome** | extension ≥ 1.0.36 | **none** | **none** | **Never a verifier.** See below |
| Cypress | — | `cypress run` | exit code is the **number of failing tests** unless `--posix-exit-codes` (A) | usable with the flag; aliases to 0 at multiples of 256 without it |
| browser-use / Stagehand / Midscene | — | CLI exists | requires model credentials and a model call per run (A, Midscene: `MIDSCENE_MODEL_API_KEY` et al.) | **Never a verifier.** Non-deterministic; see §7 |
| Kane CLI (TestMu) | launched 2026-04-29 | `kane --headless` | vendor claims "standard exit codes plug into pipeline control flow" (C, PTI press release) | **Unmeasured.** A claim to test, not to adopt |
| agent-browser-protocol | — | REST/MCP in a Chromium fork | "Action success/failure tracking" listed under *Not yet implemented* (A) | cannot report pass/fail at all |

**The two that can NEVER be unattended verifiers, and why.**

**Claude in Chrome** is the `claude-in-chrome` MCP server invoked *inside a model turn*. There is a `claude --chrome` flag, but no way to get a browser assertion out as a process exit code — and `flow loop run` reads only an integer status. Its own docs settle it three times over: "Browser actions run in a visible Chrome window in real time"; "When Claude encounters a login page or CAPTCHA, it pauses and asks you to handle it manually"; and decisively, "if you authenticate with an API key or a long-lived token from `claude setup-token`, Claude Code keeps Chrome integration off, even when you pass `--chrome`" — which is exactly how `flow loop run`'s fresh `claude -p` children authenticate (A, `code.claude.com/docs/en/chrome`). The GitHub request for a global always-allow setting (anthropics/claude-code#66125) is **closed as not planned**, so the unattended mode has been declined, not merely not-yet-built. Give it to the agent as *eyes inside* an iteration; never as the thing that ends the loop.

**chrome-devtools-mcp** is disqualified on measurement rather than absence of docs. On 1.9.0: `chrome-devtools evaluate_script` with a function that throws printed `Error: cdp-boom` and **exited 0**; `chrome-devtools navigate_page … --url http://localhost:9/nope` printed `Error: net::ERR_CONNECTION_REFUSED` and **exited 0** (M). It is headless and isolated by default and reuses browser state across commands — good for exploration, useless as a gate.

---

## 3. The four rungs of UI verification, cheapest first

Climb only as far as the goal needs. Every rung up costs a dependency, a failure mode, or a cheat class.

| Rung | Check | Command shape | Cost | New cheat class it opens |
|---|---|---|---|---|
| **1. Route health / DOM assertion** | the app answers, the element is there and says the right thing | `curl -sf`, `test "$(agent-browser … get text '#x')" = "…"` | ~0.4 s warm; no npm project | none — nothing to launder |
| **2. Behavioural e2e** | a user flow completes | `npx playwright test --retries=0 --forbid-only -u none` | ~2–4 s + browser launch | `test.skip`, `--pass-with-no-tests`, `page.route().fulfill()` mocking the backend |
| **3. Visual regression vs own baseline** | the page still looks like it did | `npx playwright test` with `toHaveScreenshot`, or `odiff base.png cur.png` | a committed baseline file | **every published browser reward hack** — `-u`, `rm -rf *-snapshots`, `maxDiffPixelRatio: 1`, `cp cur.png base.png` |
| **4. Similarity to an external target** | the build matches a human-supplied design | `ui-score score --target <dir> --serve …` | a target dir, a scoring script, Playwright as a library | threshold widening; scorer monkey-patching — both closable by hashing (§10) |

**Rung 1 is under-used and is the right default.** An accessibility-tree snapshot from `agent-browser snapshot` is byte-reproducible across two loads **and across two fresh sessions** (M, `diff` rc=0 both ways), catches a real text regression with a one-line hunk, is plain text with no timestamps or hex — so `signatureOf` is stable and the wedge detector works — and a full cold cycle costs 1.2–1.3 s. Compare rung 3, where Playwright's own docs say rendering varies by "host OS, version, settings, hardware, power source (battery vs. power adapter), headless mode" and baselines are named per platform (`box-darwin.png`) (A).

**Rung 3 deserves a warning label, not a recommendation.** Playwright's `--update-snapshots` defaults to mode **"missing"** *with no flag at all* (A, `playwright test --help`), so `rm -rf <spec>-snapshots` plus the loop's own next iteration goes green: run 1 exits 1 **and writes the baseline**, run 2 exits 0 (M). The corollary is the design ruling in §10: at rung 1 and 2 there is no baseline file, so every one of those cheats has nothing to point at. That property comes from choosing the lazier rung, not from adding a detector.

**Rung 4 is a different animal from rung 3** and must not be conflated with it. Its target PNG is *human-supplied and predates the loop*; there is no snapshot-update path in the tool at all; and it is hashed. That is why it survives §5 while rung 3 does not.

---

## 4. Determinism: the hardened boot-assert-teardown template

Three research angles each got the teardown wrong in a different way. The failures are worth naming because they all look right:

| Idiom | What actually happens | Grade |
|---|---|---|
| `trap 'kill 0' EXIT` | kills the wrapper too; a script whose last statement is `exit 0` returned **144** | M |
| `trap 'kill -- -$$' EXIT` | the verifier shell is **not** a process-group leader (measured pid 39491, pgid 39382 ≠ 39315), so this is a no-op error: `kill: (-39491) - No such process` | M |
| `kill $SERVER_PID` | kills the wrapper (`npm run`/`vite`/`next`), not the server. Alive before: 2, after: 1 | M |
| `timeout 300 …` | `command -v timeout gtimeout setsid` → **all three missing** on stock macOS; `/bin/sh` is bash 3.2.57 (M, verified locally). Exits 127 — indistinguishable to the loop from "the test command doesn't exist" | M |
| `trap 'echo …; kill …'` | at `verify_timeout` node closes stdio; the `echo` dies of SIGPIPE and the kill never runs. Fix is two words: kill first, and put `PIPE` in the trap list | M |
| a trap plus one long **foreground** command | the trap makes `verify_timeout` unenforceable: bash defers the pending SIGTERM until the current foreground command returns. A 5 s budget overran to **60 s**, an 8 s budget to **155 s+**. `cmd & wait $!` restores the bound exactly | M |
| `set -e` + `! detector` | POSIX exempts `!` from `set -e`; the guard **never fires**. `set -e; ! true; echo REACHED` printed REACHED, exit 0 | M |
| `detector && { exit 1; }` | exempt mid-script (AND-OR list rule, *not* `set -e`), but as the **last** statement its status becomes the script's, so an honest tree exits 1 | M |

Every guard is `if <detector>; then echo …; exit 1; fi`. Nothing else is correct in both directions.

The template that survives all of it (shipped as `templates/ui-verify.sh`, §10):

```sh
#!/bin/sh
# flow loop init "<goal>" --verify "sh tests/ui/verify.sh"
# ONE simple command. No && in the verify string — see §1.
# exit 0 = every assertion passed, 1 = an assertion failed, 2 = the harness broke.
set -eu
SERVE=${SERVE:-"npm run preview -- --port 4173"}
PORT=${PORT:-4173}; HEALTH=${HEALTH:-/}; BOOT=${BOOT:-60}
BASE_URL="http://127.0.0.1:$PORT"; export BASE_URL
LOG=$(mktemp -t ui-verify)

# Refuse a port someone else owns: a server left by a previous timed-out
# iteration serves the OLD build and turns a real failure into a green lie.
if curl -sf -o /dev/null --max-time 2 "$BASE_URL$HEALTH"; then
  echo "ui-verify: refusing — something already answers on $HEALTH"; exit 2
fi

# Own process group as a grandchild. macOS has no setsid; the extra subshell
# stops the shell printing "<pid> Terminated: 15", whose PID signatureOf
# does not mask.
( perl -e 'setpgrp(0,0); exec @ARGV or die $!' -- sh -c "$SERVE" >"$LOG" 2>&1 & echo $! ) > "$LOG.pid"
PG=$(cat "$LOG.pid")
# KILL BEFORE PRINTING — an echo here dies of SIGPIPE at verify_timeout.
# PIPE is in the list for the same reason: node closes the child's pipes as it
# times out, so a teardown that writes first dies mid-kill.
trap 'kill -TERM -$PG 2>/dev/null || true; rm -f "$LOG" "$LOG.pid"' EXIT INT TERM HUP PIPE

i=0
while [ "$i" -lt "$((BOOT * 5))" ]; do
  curl -sf -o /dev/null "$BASE_URL$HEALTH" && break
  kill -0 "$PG" 2>/dev/null || { echo "server died during boot"; tail -20 "$LOG"; exit 2; }
  i=$((i + 1)); sleep 0.2
done
curl -sf -o /dev/null "$BASE_URL$HEALTH" || { echo "not ready in ${BOOT}s"; tail -20 "$LOG"; exit 2; }

# ---- ASSERTIONS -----------------------------------------------------------
# Every line must exit non-zero when the UI is wrong.
# Never `agent-browser wait` — a failing wait costs 60–150 s of the budget.
# Every command here must be individually fast: the trap above defers SIGTERM
# until the current foreground command returns, so one long foreground command
# un-bounds verify_timeout entirely (measured: 155 s under an 8 s budget).
# If you need a slow one, background it and `wait $!`, which restores the bound.
S="flow-ui-$$"
trap 'agent-browser --session "$S" close >/dev/null 2>&1 || true; kill -TERM -$PG 2>/dev/null || true; rm -f "$LOG" "$LOG.pid"' EXIT INT TERM HUP PIPE

# A 0×0 box is the fact that never lies: it catches "present but hidden" and
# "collapsed to nothing" in one check. `is visible` and `get text` both return
# SUCCESS on a display:none element (M), so neither can carry the assertion.
visible() {
  agent-browser --session "$S" --json get box "$1" | node -e \
'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let b;try{b=JSON.parse(s).data||{}}catch{process.exit(2)}process.exit(b.width>0&&b.height>0?0:1)})'
}

agent-browser --session "$S" set viewport 1280 800
agent-browser --session "$S" set media light reduced-motion
agent-browser --session "$S" open "$BASE_URL/"
visible '#confirmation'
test "$(agent-browser --session "$S" get text '#total')" = '$42.00'
# ---------------------------------------------------------------------------
echo "ui-verify: PASS"
```

**Why each line is there.** `perl setpgrp` because macOS has no `setsid` (M). The pre-flight refusal because a leaked server is a *silent wrong verdict*, not an error. `curl -sf` because `curl -s` exits **0** on an HTTP 500 (M, verified locally: `-s` on 404 → 0, `-sf` on 404 → 22, `-sf` on a dead port → 7). No port, PID or elapsed time on the success path, and the failure dump masked with `sed 's/\(127\.0\.0\.1\|localhost\):[0-9]\{2,5\}/\1:PORT/g'`, so two identical failures hash identically and the wedge detector can fire.

**Hermetic knobs, all confirmed working on Playwright 1.63.0 in one config (M):** `viewport`, `deviceScaleFactor: 1`, `colorScheme`, `reducedMotion: 'reduce'`, `locale`, `timezoneId: 'UTC'`, plus `page.clock.setFixedTime`. `globalTimeout` **must** be set — the default is *no timeout* (A) and flow's is soft. Never `waitForLoadState('networkidle')`: Playwright marks it "DISCOURAGED … Don't use this method for testing, rely on web assertions to assess readiness instead" (A), and a dev server with an open HMR socket never goes network-idle at all.

**agent-browser housekeeping (all M on 0.23.4).** `--session "flow-ui-$$"` is mandatory: the default session is machine-global, and `agent-browser close --all` was measured **closing 11 sessions belonging to other processes**. Never use `agent-browser wait` — a failing wait cost 62 s, 152 s and 153 s across three runs, the duration is variable rather than a fixed timeout, and there is no per-command `--timeout` flag outside `--download`. `AGENT_BROWSER_DEFAULT_TIMEOUT` **does** bound it (the same probe returned in 2 s with the env var set) — one angle reported the opposite and was contradicted on re-measurement (§11 defect 25) — but the rule stands on the simpler ground that every other verb fails in under a second, so a verifier never needs `wait` at all. Set `AGENT_BROWSER_IDLE_TIMEOUT_MS=300000` for an overnight loop: 0.23.4's daemon idle timeout is "disabled by default" and a default only arrived in 0.33.1 (A). And never print `agent-browser network requests` from a verifier — it emits an unmasked request clock like `[59012.4]` that `signatureOf`'s masks do not catch, giving a fresh signature every iteration (M).

**One determinism scare that did not survive checking.** A same-second edit-then-screenshot photographing a cached page (HTTP 304) is real — but only against `python3 -m http.server`, whose `Last-Modified` has one-second granularity. Vite sends `Cache-Control: no-cache` plus a **content** ETag and served the fresh page on a same-second edit with no cache-buster (M). The rule is "don't point a visual verifier at `python3 -m http.server`", not "every screenshot verifier needs a freshness assertion". Six consecutive captures of a Google-Fonts page were byte-identical (M) — though every run after the first was warm-cache, so a cold cache is still untested.

---

## 5. Reward hacking in UI loops: cheat → detector

Every row was reproduced with an exit code. This is the register a UI verifier is designed against. **Read row 15 first**: it is the cheapest cheat in the document, it beats the verifier shape this repo currently documents, and un-gating one hash closes it together with rows 3, 4, 10 and 14 (§10).

| # | Cheat | Measured result | Detector | Layer |
|---|---|---|---|---|
| 1 | `agent-browser is visible '#x'` on a hidden element | prints `false`, **exit 0** (M, verified locally) | `test "$(…)" = "true"`; `flow loop init` refusing a green verifier | verifier string |
| 2 | verify string contains `&&`; dev server leaks past `verify_timeout` | next iteration verifies the **old build**, green (M) | one-simple-command rule + process-group trap | verifier string |
| 3 | `rm -rf <spec>-snapshots`, run twice | run 1 exit 1 **and writes the baseline**; run 2 exit 0, **no flag needed** (M) | `-u none`; better, no baseline file (rung ≤ 2) | rung choice |
| 4 | `playwright test -u` | rewrites the baseline; also **generalises** `"Total: $42.00"` into `/Total: \$\d+\.\d+/`, after which \$99.00 passes (M) | `git diff --name-only <base> -- '*-snapshots/*'`; `permissions.deny`; rung ≤ 2 | rung choice |
| 5 | `maxDiffPixelRatio: 1` in the spec **or** in `playwright.config.js` | both exit 0 against a fully-changed screen (M) | the byte hash, **when the knob is in the file the verify string names**; nothing catches it in a separate `playwright.config.js`, and adding that path to `isGateConfigPath` catches nothing either — §11 defect 6 | contract hash |
| 6 | `test.skip(` | **exit 0**, "1 skipped", *even with* `--forbid-only --fail-on-flaky-tests` (M) | flow's `SKIP_RE` already matches `.skip(` (A) — the tamper veto, not the flag | tamper |
| 7 | `--pass-with-no-tests` after deleting the spec | exit 1 → **exit 0** (M) | forbidden-flag grep; `verify_sha` if the flag is in the verify string | tamper |
| 8 | flaky e2e retried to green | a test failing on attempt 1 and passing on attempt 2 prints `1 flaky` and **exits 0** (M) | `--retries=0` — the scaffolded config sets `retries: 2` on CI and flow sets `CI=true` | verifier string |
| 9 | `page.route().fulfill()` faking a 200 while the backend 500s | exit 0 (M) | `test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/order")" = "200"` — the browser cannot intercept it | verifier string |
| 10 | `page.goto('file://…fixture.html')` with the app down | **exit 0** against a *hardened five-check verifier*, backend returning 500 (M) | a script that owns the port and builds the URL itself (rung 4); or a negative control | design |
| 11 | `rm -rf tests/` | flow's census read **2** when the true count was **0**, because `git ls-files` lists the index (M, verified locally) | subtract `git ls-files --deleted` — three lines, every language. **Shipped**; `countTestFiles` now filters the deleted set | tamper (fixed) |
| 12 | ephemeral port defeats the wedge detector | `signatureOf(":53747") !== signatureOf(":53755")` (M, verified locally) | one-line localhost-port mask in `signatureOf`. **Shipped** | loop (fixed) |
| 13 | `curl -s` preflight on a 500 | exit 0 (M, verified locally) | the `-f` is load-bearing | verifier string |
| 14 | assertion weakened **in place** (`= "Order confirmed"` → `= "$(agent-browser get text '#confirmation')"`), deleted outright, or wrapped in `try`/`catch` | invisible to every `tamper.js` detector — nothing inspects assertion *strength* (A) | **closed by Stage 1 for the file the verify string names**: any of these changes its bytes, and the hash does not care what the edit meant. Residue: the same edit in a *second* file that `verify.sh` sources | contract hash |
| 15 | rewrite the whole verify script to `exit 0` | `verdict: pass`, `verify_rc: 0`, `tamper: []` (M, verified locally) — because `init.js` gates `target_sha` behind `--target` while recording `verify_script` regardless, so the file holding every assertion is named and never hashed | un-gate the hash: 2 edits, §10. **This is the cheapest cheat in the document and it beats the documented default** | contract hash (bug) |

**Two things the corpus proved about mitigations, both counter-intuitive.**

Naming the exact forbidden path in the prompt is the measured lever, not more prose: Hack-Verifiable Terminal Bench (arXiv 2608.22103, 2026-08-22) took claude-opus-5 from **30.7% to 0.0%** by escalating from no instruction to an explicit `admin/` prohibition; under a generic warning the L0 rates were claude-opus-5 17.4%, gemini-3.1-pro 59.8%, glm-5.2 25.0%, gpt-5.6-sol 15.9%, kimi-k3 11.8% (B, every figure re-fetched from Table 2). But the curve is **non-monotonic** for gemini (L2 7.0% → L3 16.3%), and the honeypot path was known to the researchers in advance, which flow's is not — so keep the veto. Prompt specificity is a discount on the tamper check, never a replacement (see §11 defect 2).

`permissions.deny` is **not** an OS guarantee. Anthropic's docs: deny rules "don't apply to arbitrary subprocesses that read or write files indirectly, like a Python or Node script that opens files itself" (A). A Node scorer the model writes is exactly such a subprocess. Deny is a first layer; the guard has to be a hash.

---

## 6. The target-matching objective function

The user's headline ask — "creating localhosted stuff to as closely match something as possible" — is the one place where the objective function itself is a design decision rather than a plumbing decision.

**The scalar is disqualified by measurement, not by taste.** UI2Code^N (arXiv 2511.08195v2, 2025-11) ran the ablation: on Design2Code, a **CLIP reward scored 62.0 against the 72.3 SFT baseline it started from**, while a VLM-judge reward reached 74.6 (B, Table 3, re-fetched). Optimising visual similarity alone made the model *worse than not optimising*. Their own conclusion: "purely visual similarity signals are insufficient for capturing the semantic and structural fidelity required in UI-to-code generation, and may even misguide the optimization process."

Design2Code, the canonical benchmark, independently refuses a single number: it matches visual **blocks** first, then scores block-match, text (character-level Sørensen-Dice), position (`1 − max(|dx|,|dy|)` on normalised coordinates) and colour (CIEDE2000) **separately**, and inpaints text boxes out (Telea 2004) before taking CLIP similarity (B). Two cautions carried forward: its CIEDE2000 term scores the colour of matched **text**, not arbitrary element fill — a flow port gets no button-fill checking for free from it; and its full evaluation takes "up to 1 hour" per model on 484 pages against flow's 600 s `verify_timeout` (A), so borrow the decomposition, never the implementation.

**The failure mode, measured.** A hand-built cheat page — three absolutely-positioned divs, no `h1`, `p` or `a` — scored **0.39% pixel mismatch** against the target at 1280, comfortably inside a 0.5% gate. Two proposed anti-degeneracy constraints were then measured and both failed:

| Proposed guard | Result | Verdict |
|---|---|---|
| absolutely-positioned element count ≤ 6 | cheat scored **3**, passed. `position:fixed` and `transform` evade it anyway | useless |
| a second viewport at 480 | caught the *first* cheat at 1.03% — but that is a **denominator artefact**: ~3970 wrong pixels are 1.03% of 384000 and 0.39% of 1024000, the same error. A second cheat page with corrected line-heights scored **0.00% at BOTH 480 and 1280** while still having no `h1`/`p`/`a` | useless |
| **visible-selector structure gate** | the only guard that caught either cheat | **load-bearing** |

So the gate is a conjunction, per viewport, all three required:

| Gate | Check | Stops |
|---|---|---|
| **structure** | every `expect.json.must` entry resolves to ≥ `min` **visible** elements — `getBoundingClientRect` w>0 ∧ h>0, `visibility !== 'hidden'`, `display !== 'none'` — with exact text where given | absolutely-positioned garbage, an `<img src=target.png>` clone, and presence-without-visibility (`.count()` alone passes a `display:none` `<h1>`) |
| **overflow** | `scrollWidth - clientWidth <= 1` | a frozen fixed-width layout |
| **pixel** | in-page per-pixel diff vs `<target>/<w>.png` ≤ `maxMismatchPct` | actual visual distance |

A scalar would let 0.39% pixel fidelity **buy off** a missing `<h1>`. A conjunction cannot.

**Where the target comes from, and the one thing that makes the objective safe.** A target seeded only from a live URL cannot express the common case — "match this Figma export" — so `capture --from-image <png>` is the missing half: one viewport (a mock has one width), resized to width W preserving aspect, and the resulting height *is* `expect.json.height`, so nobody hand-sizes a mock to W×H and gives up. It cannot infer selectors from a PNG, so it must write `must: []` — and `score` must then **refuse an empty `must` with exit 2**. That refusal is what makes a pixel-only objective *structurally un-armable*: the tool will not run as a picture-matcher, which is exactly the configuration UI2Code^N measured as worse than not optimising at all. A single-viewport mock has a ceiling worth stating: it cannot prove the layout reflows, so the structure gates carry all the weight there; hand-capture a second width if reflow matters.

**Three smaller rulings.** (1) The gate is an **absolute threshold, never a monotonic best-so-far ratchet**: flow's contract is binary, so ratchet state must live in a file, any file the loop can reach is model-writable, and "beat the best" has no fixed point, so it never terminates. The trend belongs in the `LEARNINGS.md` entry the prompt already mandates — `score: X% (target Y%)` — where it gates nothing. (2) There is **no `--calibrate` flag**: the plain run prints `[1280] pixel FAIL 41.20% > 2.00%`, and that number is the calibration. But calibrate it correctly — the shipped reference says to set `maxMismatchPct` "just under" the current reading, which for a target-match loop **exits on the first cosmetic improvement**. The reading tells you how far away you *start*; the threshold is the bar you want to clear (typical: read 11%, set 3%). (3) Every threshold quoted anywhere in this document came from a toy page; none is a validated constant.

**A metric that was proposed, measured and rejected.** Mean ΔE2000 is actively misleading: an invisible global +3/255 shift scored a *higher* mean than a visible 100-pixel blowout (M, reproduced twice on different images, effect 3× in the second run). p95 ΔE2000 fails the other way — it passed a fully recoloured button because the defect covered ~5% of the frame, leaving p95 at 0.000 while max was 45.4 (M). And JND-area (% of pixels with ΔE2000 > 2.3), proposed as the fix, has the *same* small-area blindness at its own recommended `--max-area 1.0`: a 100×100 button rendered fully red instead of blue on a 1280×800 page scored `visible_area=0.977% → PASS` while plain `odiff` on the identical pair returned 0.98% and **exit 22, correctly red** (M). 1% of 1280×800 is 10,240 pixels — a whole button, badge or avatar can be arbitrarily wrong and pass. None of these belongs in a gate.

---

## 7. VLM-as-judge: where the line is

A VLM may **triage** a red gate, describe what changed, and prioritise. It may not be the exit condition. Three independent reasons, in increasing order of how specific they are to flow.

**1. The reliability numbers.** VLM judges reach 32–34% exact agreement with human ratings on a 5-point scale, 24–30% of predictions deviate by ≥2 points, ρ = 0.30–0.46 (B, arXiv 2604.25235, 2026-04-28). Rating Roulette measured only **61.3% identical judgments across 3 reruns of the same prompt** on MT-Bench for its best model (Krippendorff α 0.563; Llama-3.1 0.265) (B, 2510.27106). Temperature 0 does not rescue it: T=0.01 gives near-perfect run-to-run consistency at agreement of only ~0.59–0.62 (B, 2603.28304), and a 21-judge survey found reliability ≥ 0.95 coexisting with position bias > 0.10 in two production-deployed judges — reproducible but not valid, which is exactly the failure a loop cannot see (B, 2606.19544).

**2. The benchmark authors refuse it.** VISTA states outright: "To avoid sensitivity to LLM-judge prompting and ordering effects, we combine human annotations, deterministic Playwright tests, CLIP-based similarity, and trajectory analysis" (B, 2605.26144). OSWorld 2.0 constrains model-based checks to "objective binary checklists instead of open-ended grading", caps any single task at 50% model-based, and measured the aggregate contribution at 11.53% (B, 2606.29537 — note the correction in §11 defect 8). VisualWebArena's image reward is SSIM, not a judge (B). WebVoyager's GPT-4V judge, the most-cited example, reached 85.3% agreement / κ=0.70 — fine averaged over 300 benchmark tasks, roughly one wrong verdict in seven as a loop's exit (B, 2401.13919).

**3. The flow-specific reason nobody states.** `signatureOf()` hashes the first 60 masked output lines to detect a wedged loop. A judge that rewords its verdict each iteration produces a fresh signature every time, so flow's **stall and wedge detectors become structurally unable to fire**. A nondeterministic verifier does not merely risk a wrong answer — it disables the safety net, and the loop burns its full iteration and dollar budget on a failure that is not moving.

**The one construction that reaches gate-grade accuracy argues itself out of the job.** Mind2Web 2's Agent-as-a-Judge measured 99.03% correctness per automated leaf node — on rubrics averaging 34 leaf nodes (50 total nodes) built by an LLM pipeline and then refined by **two stages of human validation** (B, 2506.21506). Compounding at 34 leaves gives 0.9903³⁴ ≈ 0.72; at 5 leaves ≈ 0.95. A rubric small enough to be reliable is small enough that you should write those five checks as Playwright assertions instead — which is free, deterministic, and hashable.

A judge is fine as a **post-loop, human-gated report**. Note that `claude -p --image` does not exist (§11 defect 12), so a screenshot reaches a headless judge only by path reference inside the prompt — i.e. a full agent turn per iteration, a cost no source quantifies.

---

## 8. The verifier catalogue for UI goals

Every command here is one a shell can actually run. `$BASE_URL` and `$S` are set by the wrapper in §4.

| Goal | Verifier command |
|---|---|
| the route serves 200 at all | `curl -sf -o /dev/null --max-time 5 "$BASE_URL/checkout"` **(verified locally)** |
| the API is genuinely healthy (browser cannot fake it) | `test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/order")" = "200"` |
| the page contains the expected copy, no browser | `curl -sf "$BASE_URL/" \| grep -q 'Order confirmed'` |
| an element is **visible** (not merely present) | `test "$(agent-browser --session "$S" is visible '#cta')" = "true"` **(verified locally)** |
| an element is **absent or hidden** — no exit code can express this | `test "$(agent-browser --session "$S" is visible '#spinner')" = "false"` |
| an element's text is exact | `test "$(agent-browser --session "$S" get text '#total')" = '$42.00'` |
| an arbitrary DOM predicate | `agent-browser --session "$S" eval "if(!cond) throw new Error('why')"` — a falsy **return** exits 0; only a `throw` exits 1 |
| the accessibility tree still matches a committed baseline | `agent-browser --session "$S" snapshot > /tmp/aria.txt && diff -u tests/ui/checkout.aria.txt /tmp/aria.txt` |
| no uncaught JS errors on the page | `agent-browser --session "$S" errors --json \| node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const e=JSON.parse(s).data.errors;if(e.length){console.error(e.map(x=>x.text).join("\n"));process.exit(1)}})'` — the bare command exits 0 with errors present |
| a user flow completes end to end | `npx playwright test tests/e2e/checkout.spec.ts --retries=0 --forbid-only -u none --reporter=line` |
| the right number of tests actually ran (closes the `test.skip` hole) | `npx playwright test --reporter=json > /tmp/pw.json && node -e 'const s=require("/tmp/pw.json").stats;process.exit(s.expected>=1&&s.skipped===0&&s.unexpected===0?0:1)'` |
| page structure matches an aria template | `npx playwright test tests/ui/aria.spec.ts --retries=0 -u none` (uses `toMatchAriaSnapshot`, available since Playwright **1.49**, not 1.63) |
| no accessibility violations | `npx @axe-core/cli "$BASE_URL/checkout" --exit --tags wcag2a,wcag2aa` — **without `--exit` it reports violations and exits 0** |
| Lighthouse category above a threshold | `npx lighthouse "$BASE_URL/" --only-categories=accessibility --output=json --output-path=/tmp/lh.json --chrome-flags=--headless --quiet && node -e 'process.exit(require("/tmp/lh.json").categories.accessibility.score>=0.9?0:1)'` — the CLI always exits 0 |
| pixel-identical to a committed baseline | `npx odiff-bin base.png cur.png /tmp/d.png --antialiasing --parsable-stdout` — exit 0 match / 22 pixel diff / 21 layout with `--fail-on-layout` |
| an element is visible **and** has non-zero area (the form that survives a driver upgrade) | `agent-browser --session "$S" --json get box '#cta' \| node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let b;try{b=JSON.parse(s).data\|\|{}}catch{process.exit(2)}process.exit(b.width>0&&b.height>0?0:1)})'` |
| the build matches an external target | `sh tests/ui/verify.sh`, whose assertion block calls `plugins/flow/scripts/ui-score score --target .loop-target --url "$BASE_URL" \|\| exit $?` — `ui-score` boots nothing, so something must own the port, and the `\|\| exit $?` forwards its 1-vs-2 distinction |
| seed that target from a design mock rather than a live URL | `plugins/flow/scripts/ui-score capture --target .loop-target --from-image ~/Downloads/pricing@2x.png --viewports 1280` — run once, by a human, never inside `--verify` |
| Cypress project | `npx cypress run --posix-exit-codes --spec cypress/e2e/checkout.cy.js` — the flag is mandatory; the default exit code is the failure *count* |
| the whole thing, composed | `sh tests/ui/verify.sh` — **one simple command**, composition inside the script |

**Flags that are mandatory in a loop, with the reason attached.** `--retries=0` (the scaffolded Playwright config sets `retries: 2` on CI and flow sets `CI=true`; a flaky test retried to green prints `1 flaky` and exits **0** — M). `-u none` (`--update-snapshots` defaults to "missing" with no flag — A). `--forbid-only` (redundant with flow's `SKIP_RE` for `.only(`, and it does **not** catch `test.skip` — M). `--exit` for axe. `--posix-exit-codes` for Cypress. `globalTimeout: 240_000` in the config, because the default is *no timeout*. `webServer.reuseExistingServer: !process.env.CI` — under flow this evaluates **false**, turning a stale server from a silent wrong verdict into a loud "port already used" (M, both branches).

**Flags to forbid**, greppable from the verify string: `-u`, `--update-snapshots` with any mode but `none`, `--pass-with-no-tests`, `--only-changed`.

---

## 9. Vendor and tool landscape, 2026

| Tool | Version / date | Contract facts that matter | Grade |
|---|---|---|---|
| **agent-browser** (Vercel) | 0.23.4 released 2026-03-31 (installed here); latest **0.37.1**, 2026-09-08 | `is`/`get` are queries — false exits 0, missing exits 1. `eval` exits 1 only on `throw`. Diff commands since 0.13.0. A failing `wait` costs 62–153 s, varies run to run, and has no per-command `--timeout` outside `--download`; `AGENT_BROWSER_DEFAULT_TIMEOUT` **does** bound it (152 s → 2 s), and the fix landed in **0.27.2** (2026-06-10) — but never call `wait` in a verifier regardless, since every other verb fails in under a second. Daemon idle timeout default added in **0.33.1** (2026-07-28); 0.23.4's is "disabled by default". `network route --abort/--body` did not intercept across five pattern shapes on 0.23.4 and prints `✓ Done` while doing nothing. `close --all` is machine-wide (11 sessions killed). `get attr` argument order is mis-documented in `--help` | A/M |
| **Playwright** | 1.63.0 npm latest, 2026-09-04; 1.60.0 global here | Exit 1 on failure, on "No tests found", on a bad spec path. `test.skip` exits 0 even with `--forbid-only`. `-u` rewrites baselines **and generalises literals into regexes**. `--update-snapshots` defaults to "missing". `toMatchAriaSnapshot` since **1.49**. `globalTimeout` default: none. Docker image `mcr.microsoft.com/playwright:v1.63.0-noble` is a **multi-arch manifest** (amd64 + arm64 — no Apple-silicon emulation penalty); needs `--ipc=host`; Alpine unsupported | A/M |
| **chrome-devtools-mcp** | 1.9.0 | CLI bin is `chrome-devtools`. Headless + isolated by default, persistent daemon. Exits **0** on a throwing script and on a dead-server navigation | A/M |
| **Claude in Chrome** | extension ≥ 1.0.36 | MCP server `claude-in-chrome`; visible window; pauses for CAPTCHAs; **off under API-key / `setup-token` auth even with `--chrome`**; anthropics/claude-code#66125 closed as not planned | A |
| **odiff** | 4.5.0 | Exit 0 / 21 (layout, with `--fail-on-layout`) / 22 (pixels); exit 1 on a missing file is *undocumented*. `--parsable-stdout` prints `count;percent`, and just `0` on a match — parsing field 2 unguarded yields empty. ~0.19 s. **Not on PATH by default** | A/M |
| **pixelmatch** | 7.2.0 (latest published) | Uses **YIQ**, has no `windowSize`. The GitHub README documents OKLab/HyAB — an **unreleased** version nobody can install. CLI exits 66 on any diff, 64 on bad args; no count/ratio threshold | A/M |
| **@axe-core/cli** | axe-core 4.13.0 | Reports violations and exits **0** without `--exit` | A/M |
| **Lighthouse CLI** | current | Always exits 0; the threshold is the caller's job. `lhci assert` is the packaged form. Assert *accessibility* (stable), not *performance* (timing-derived) | A/M |
| **Cypress** | current | Exit code = number of failing tests unless `--posix-exit-codes`. "No spec files found" = 1 in **both** modes | A |
| **Chromatic** | current | Cleanest hosted exit table: 1 BUILD_HAS_CHANGES, 2 BUILD_HAS_ERRORS, 11 QUOTA, 12 PAYMENT_REQUIRED, **101 GIT_NOT_CLEAN** — an unattended loop with edits in flight wedges on 101 every iteration. Needs a project token, i.e. network | A |
| **Percy** | current | `percy exec` exits 0 when the build fails (open issue #1181, missing-token/credits case); failing on diffs needs `percy build:wait --fail-on-changes` | A/C |
| **Lost Pixel** | sunset announced **2026-04-22** | "We're sunsetting Lost Pixel", team joining Figma. Do not add to any catalogue | A |
| **BackstopJS / resemble.js** | current | `misMatchPercentage` resolves only above 0.01% unless `usePreciseMatching` is set — on a large screenshot that floor is hundreds of pixels | A |
| **dssim / ssimulacra2** | current | dssim outputs `1/SSIM−1`, unbounded, and its maintainer warns "The scale has changed between versions" — a hardcoded threshold silently changes meaning on upgrade. ssimulacra2: −inf..100, 90 = visually lossless, 80 = imperceptible side-by-side | A |
| **ImageMagick `compare`** | not installed here | "returns 2 on error, 0 if the images are similar, or a value between 0 and 1 if they are not similar" — incoherent as an exit-code spec. `-fuzz` affects only the AE metric | A |
| **Kane CLI** (TestMu) | launched 2026-04-29 | Advertises "standard exit codes plug into pipeline control flow", `--headless`, `--agent --headless` NDJSON. Vendor marketing in a press release; **unmeasured** | C |
| **agent-browser-protocol** | pre-release | Freezes JS execution and timers between agent actions (interesting for flake); "Full headless support" **and** "Action success/failure tracking" both listed as not implemented | A |
| **Figma Dev Mode MCP** | current | Official docs now recommend the **remote** server, which "connects directly to Figma's hosted endpoint without requiring the Figma desktop app". Either way: never call it from inside `--verify` — network breaks "same answer twice" | A |
| **DTCG token format** | 2025.10, first stable **2025-10-28** | `$value`/`$type` with aliases; read/written by Figma, Penpot, Sketch, Tokens Studio, Style Dictionary, Terrazzo. A stable shape for the non-pixel half of a target | A |

---

## 10. What this produces in the flow repo

The browser verifier already ships: `references/browser-verifier.md`, `templates/ui-verify.sh`, `scripts/ui-score`, the `target_sha` machinery in `tamper.js`, the localhost-port mask in `signatureOf`. What the adjudication found is that the **documented default is unguarded**, and that three already-shipped files carry bugs that are wrong today. Stage 1 closes the hole and fixes those; Stage 2 ships the capability the user named first; Stage 3 waits for evidence.

**The hole, reproduced before anything else was scored** (M, verified locally):

```
$ flow loop init "ui goal" --verify 'sh tests/ui/verify.sh'
$ grep -E '^(verify_script|target_sha):' .claude/loop/loop.md
verify_script: tests/ui/verify.sh
target_sha:                                  <- empty
$ printf '#!/bin/sh\nexit 0\n' > tests/ui/verify.sh
$ flow loop check --json
{ "verdict": "pass", "verify_rc": 0, ... }       tamper: []
```

`init.js` gates the hash behind the flag — `target_sha: target ? targetSha(toplevel, target, [...]) : ''` — and `tamper.js`'s `targetSha` bails on `if (!target) return ''`. So the file holding **every assertion** is recorded in the contract and never hashed. The documented default UI verifier is gameable in one line, and the fix is two edits to machinery already written.

**Why un-gating that hash is the whole spine.** `findVerifyScript()` already resolves the first whitespace-separated token of the verify string that is an existing file. For `--verify 'sh tests/ui/verify.sh'` that is the script; for `--verify 'npx playwright test tests/e2e/signup.spec.ts --retries=0'` it is **the spec file**. One restructured function therefore covers, transitively, assertion deletion, in-place weakening, try/catch swallowing, a `file://` redirect written into the check, and `playwright test -u` rewriting an inline `toMatchAriaSnapshot` — every one of them changes bytes in a hashed file (§5 rows 3, 4, 10, 14). State the ceiling honestly: it freezes **the one file the verify string names**, not everything that file shells out to. A redirect the model writes into a *second* file that `verify.sh` sources is still invisible. That residue is what Stage 3 exists for.

### Stage 1 — close the hole, fix three shipped bugs (~40 lines, no new files)

| File | Action | What it carries |
|---|---|---|
| `bin/lib/loop/tamper.js` | edit, ~6 lines | Restructure `targetSha` so `extraPaths` are hashed when `target` is empty: `let lines = []`, wrap the directory walk (and its `files === null → 'MISSING'` branch) in `if (target) { … }`, then `if (!lines.length) return '';` before `lines.sort()`. Verified: with no target and one extra path the hash is non-empty and changes on a one-byte edit; with no target and no extras it still returns `''`, so `t_ui_tamper_check_no_target_sha_no_finding` stays green. Also make the finding name the file that changed — `guarded files changed: ${[front.target, front.verify_script].filter(Boolean).join(', ')}` — instead of the hardcoded `target changed: ${front.target}`, which prints an empty path in the no-target case |
| `bin/lib/loop/init.js` | edit, 2 lines + prompt | (1) Drop the ternary: `target_sha: targetSha(toplevel, target, [targetScript, verifyScript])`. (2) **Load-bearing:** `const targetScript = args.target ? uiScorePath() : '';` — `uiScorePath()` returns an **absolute path into the plugin's own `scripts/ui-score`**, so hashing it unconditionally would mark every unrelated loop `suspect` on the next flow plugin update. (3) Interpolate the frozen paths into `DEFAULT_PROMPT`, replacing the abstract "never change the verifier command or gate config" with a line naming them literally: *"These paths are frozen and byte-hashed at init: {frozen}. Editing any of them marks the run suspect; it cannot make the verifier pass."* Omit the line entirely when both are empty. Specificity, not more prose, is what the corpus measured as the lever (§5) |
| `skills/loop/templates/ui-verify.sh` | edit, 3 fixes | **(a)** The shipped example asserts with the two forms its own reference deprecates: `agent-browser get text` on a `display:none` element returns the text and exits 0 (M, measured independently by two checkers), so the template passes on an invisible confirmation banner. Replace with one helper — `visible() { agent-browser --json get box "$1" \| node -e '…process.exit(b.width>0&&b.height>0?0:1)'; }` — preserving the 0/1/2 split (2 when the driver returned no parseable JSON). **(b)** `trap cleanup EXIT INT TERM HUP PIPE` — `spawnSync` closes the child's pipes at timeout, so the first stdout write inside the trap raises SIGPIPE and the teardown dies mid-kill, taking the failure dump with it exactly when it matters. **(c)** Two comment blocks: never call `agent-browser wait` (a failing wait costs 60–150 s of the verify budget), and every command here must be individually fast, because a trap defers SIGTERM until the current foreground command returns — background a genuinely long one and `wait $!` (§4) |
| `scripts/tests/test_loop_core_ui.sh` | edit, one `t_*` | `t_loop_ui_verify_script_rewrite_is_suspect_without_target`: init with `--verify 'sh tests/ui/verify.sh'` and **no** `--target`; assert `target_sha` is non-empty; rewrite the script to `exit 0`; assert `flow loop check --json` reports `suspect` and names `tests/ui/verify.sh`. **This test fails against today's tree** — the transcript above is the reproduction |
| `skills/loop/references/browser-verifier.md` | edit, 4 prose | §4 step 4 is a **false promise** and must be rewritten (below). §2 rung 4 reroutes through the wrapper — `ui-score score` boots nothing, so a bare `--verify 'ui-score score …'` runs against whatever stale server answers the port. §1(b) gains the honest caveat that the one-simple-command rule trades away the timeout bound. §1 gains the `wait` row |
| `skills/loop/references/verifier-design.md` | edit, 2 lines | §2: quote the verify string with **single** quotes — `--verify "… $(cmd) …"` expands in the caller's shell before flow ever sees it, silently baking in a constant that `verify_sha` then freezes. §3 tamper table: add the byte-hash row — *"the target directory, or the script named by the verify string, changed \| sha1 over file bytes recorded at init"* |

**The doc line that teaches the opposite of the design.** `browser-verifier.md` §4 step 4 currently says adding `.loop-target` to `permissions.deny` stops the loop editing the target. Confirmed from the primary source: deny rules cover Claude's built-in file tools and the bash file commands it recognises, and explicitly **do not apply to arbitrary subprocesses that open files themselves** (A). `playwright test -u` is such a subprocess; so is `cp`. The enforcement is `target_sha`; deny is a speed bump on the honest path.

### Stage 2 — the capability the user named first (~90 lines, all inside existing files)

"Creating localhosted stuff to as closely match something as possible" is the headline request, and `ui-score` today can only seed a target **from a live URL it can reach**. A Figma export is the common case and is currently unreachable; hand-sizing a mock to exactly W×H is how the feature dies at first contact.

| File | Action | What it carries |
|---|---|---|
| `scripts/ui-score` | edit, 4 changes | **(1)** `capture --from-image <png>`, mutually exclusive with `--url`, exactly one required. Exactly **one** viewport (a mock has one width); more is exit 2. Resize to width W preserving aspect with `Image.LANCZOS` (handles 2× Figma exports); the resulting height *is* `expect.json.height`, printed so the human sees where it came from. Writes `<dir>/<W>.png` and, only if absent, `expect.json` with `must: []` plus the warning that `must` is empty. **(2)** `score` refuses an empty `must` with **exit 2**: *"a pixel-only target is not a verifier; add the 3–5 selectors that define this page"*. Mandatory companion to (1), and it is what makes a pixel-only objective **structurally un-armable** — the single most important property in this area, because a scalar visual objective has been measured to make models produce *worse* pages than not optimising at all (§6). **(3)** Reclassify the baseline/render **size mismatch** from exit 1 to exit 2: under a forced `set viewport` the render is W×H by construction, so a size mismatch can only mean a broken target, never a broken page. **(4)** A `curl -sf -o /dev/null --max-time 10 <url>` preflight before the first `open` in `score`, exit 2 on non-2xx — measured: a 500 page has an `<h1>`, so the **structure gate passes against a dead app** and only the pixel gate fails, reporting exit 1, the harness-vs-gate confusion this file's own docstring forbids (§1c of the reference) |
| `scripts/tests/test_ui_score.sh` | edit, 4 `t_*` | empty `must` → rc 2; `--from-image` sizes a 2560×3284 mock to exactly 1280 wide with `expect.json.height == 1642` and `must == []`; two viewports → rc 2; a served 500 → rc 2, not 1. Plus a third run in `t_uis_score_repeated_runs_are_byte_identical` — that test is load-bearing for the wedge detector, not tidiness: any timestamp, temp path or trend line leaking into stdout silently disables wedge detection for every UI loop |
| `skills/loop/templates/ui-verify.sh` | edit, 2 lines | `FLOW_UI_SCORE=${FLOW_UI_SCORE:-plugins/flow/scripts/ui-score}` in the config block, and a commented variant (b) in the assertion region: `"$FLOW_UI_SCORE" score --target .loop-target --url "$BASE_URL" \|\| exit $?`. The `\|\| exit $?` is required, not decorative — it forwards ui-score's 1-vs-2 distinction instead of collapsing both into this script's own 1, and it is what makes the rerouted rung 4 executable |
| `skills/loop/references/browser-verifier.md` | edit, §4 only | **The calibration ruling is a real bug in shipped prose.** Step 3 says set `maxMismatchPct` *"just under"* the current reading — which, for a target-match loop, exits on the first cosmetic improvement. The reading tells you how far away you **start**; `maxMismatchPct` is the bar you actually want to clear (typical: read 11%, set 3%). Plus one line on the `--from-image` ceiling (a single-viewport mock cannot prove the layout reflows, so the structure gates carry all the weight there; hand-capture a second width if reflow matters) and the explicit **no-ratchet** ruling (§6), with the trend recorded in the `LEARNINGS.md` entry the prompt already mandates, where it gates nothing |

### Stage 3 — deferred until something is caught lying

A **negative control** — deliberately break the app, re-run, require the verifier to go red — is the only mechanism in the corpus that proves a green is *caused by* the app, and the gap is real rather than hypothetical: a `file://` fixture redirect was measured surviving a fully hardened five-check verifier (exit 0, `VERIFIER GREEN`, on a broken app). But the un-gated hash closes that same redirect whenever it is written into the file the verify string names, which is the normal case. Ship it the first time a real loop produces a green run whose verifier was demonstrably not reading the app: a stale server that outlived a timeout, a redirect in a second file that `verify.sh` sources, or an in-app stub. The load-bearing detail to keep from the design that proposed it — require the sabotaged run to exit **exactly 1**, not merely non-zero, or a harness break scores as proof of life.

### Dropped, with the measurement that killed each

| Dropped | Why |
|---|---|
| The negative control's full apparatus (~100 lines: `negctl.js`, a contract key, a `--negative-control` flag, tick/check/reasons/help wiring, a human-authored `break.patch` per loop) | The largest bill in the panel, for a class the un-gated hash already partly closes. Its `--allow-unfrozen` escape hatch is a hole by construction that gets `--force`d the first time it is inconvenient |
| An in-viewport bounding-box gate in `ui-score` (free — the box is already fetched for the visibility gate) | Motivation is measured and good: the absolutely-positioned cheat scored 0.59% at 1280 and 0.84% at 480, only **1.4× apart**, so one `maxMismatchPct` can pass both viewports while the page overflows the narrow one. Add it the first time a layout bug actually survives scoring at both viewports; the `ponytail:` comment already in `ui-score` names exactly this upgrade path |
| `BROWSER_GATE_RE` + `SKIP_RE`/`isTestPath` extensions for playwright/cypress/vitest/percy configs | Regex-only and cheap, but `gateWeakened()` has three measured defects that must be fixed in the same commit or the extension makes things **worse**: a newly-added `maxDiffPixelRatio: 1` returns **false** (the key must exist in both the removed and added lines); `0.01 → 0.05` returns **false** (`KV_RE` is integer-only); and a legitimate **tightening**, `maxWarnings 5 → 1`, returns **true** — a false-positive generator that gets the veto disabled by the first honest user who hits it. Today no shipped verifier path routes through a browser runner config |
| An ANSI strip in `signatureOf` (one line) | Its premise — that Playwright and agent-browser leak escapes into `verify.last` despite `CI=true`, desynchronising the wedge signature — was **contradicted by measurement**: two runs of the same failing spec through flow's own `runVerify` with `--reporter=line` produced identical signatures. Add it if a real browser loop is ever seen with `wedge_streak` stuck at 0 while visibly repeating one failure. Untested for parallel workers, retries, or the default list/html reporter, which is where it would show up first |
| Init-time refusal of a browser verifier with nothing frozen | Once `target_sha` is un-gated, any browser verifier that names a script **is** frozen automatically. The refusal only fires on an inline browser verify string with no script file — rare |
| `inferTargetFromVerify` (grep `--target` out of the verify string) | Redundant once the hash is un-gated, and it does nothing for the documented default `--verify 'sh tests/ui/verify.sh'` — the exact case reproduced as broken above |
| A shared library between `templates/ui-verify.sh` (shell) and `scripts/ui-score` (Python) | Different rungs. A shared abstraction for two call sites is precisely what the ladder exists to refuse |
| Deleting `ui-score` | Written, tested (10 `t_*` functions), deps present, and Stage 2 extends it. Revisit only if dogfooding shows no real loop ever reaches rung 4 — then keep §4 of the reference as prose and drop ~250 lines |
| A VLM judge anywhere in the exit path | §7. Never revisit for the exit path |

### Acceptance, in the order it should run

```
TEST_ONLY=test_loop_core_ui.sh plugins/flow/scripts/tests/run.sh   # Stage 1
TEST_ONLY=test_loop.sh         plugins/flow/scripts/tests/run.sh   # no regression
plugins/flow/scripts/tests/run.sh                                  # whole suite
TEST_ONLY=test_ui_score.sh     plugins/flow/scripts/tests/run.sh   # Stage 2
```

Plus three hand-checks that fail on today's tree and must pass after: `target_sha` is a 40-hex sha after an init with a verify script and **no** `--target`; rewriting that script to `exit 0` makes `check` report `suspect` rather than `pass`; and a **non-UI** loop (`--verify 'false'`, no `--target`) still writes **both** `target_script` and `target_sha` empty — the regression guard that stops a plugin update marking every unrelated loop suspect.

---

## 11. Citation defects found while checking (do not repeat)

Every item below was struck or downgraded by an adversarial re-check that re-ran the command or re-fetched the source.

1. **Anthropic's long-running-Claude run did not use a differential oracle as its exit.** The "0.1% accuracy" figure was a *target stated in the instructions*, not a machine-checked stop condition, and it did not end the run — the loop was `/ralph-loop --max-iterations 20` ending on the model's own "DONE" incantation, and the page concedes the result "doesn't match the reference CLASS implementation to an acceptable accuracy in every regime". It is a counter-example to model-decided exits, not evidence for a numeric oracle.
2. **"Gemini-class models resisted every instruction level" is contradicted by the paper's own table.** gemini-3.1-pro: ablation 47.7%, L0 59.8%, L1 52.3%, **L2 7.0%**, L3 16.3% — L2 cut it ~85%, and the curve is *non-monotonic*, with maximal specificity scoring worse than L2. The conclusion (keep the veto) survives; this evidence for it does not.
3. **A trap emitting `exit 124` does not give the loop a distinguishable timeout code.** `verify.js` maps `r.error.code === 'ETIMEDOUT'` to 124 *unconditionally, before consulting `r.status`*. The trap's value is killing the server, nothing more.
4. **`verify_timeout` is not a hard kill.** `spawnSync` sends SIGTERM and waits; it never escalates to SIGKILL. Measured 33 s and 42 s returns against a 3 s timeout. Any claim that flow bounds a hanging browser verifier is false — the browser layer must bound itself.
5. **`set -e` is not why `detector && { exit 1; }` misfires.** POSIX exempts every command of an AND-OR list except the last, measured identically with and without `set -e`. The real trap is *position*: as the last statement the list's status becomes the script's. The corrective advice (always `if`/`then`/`fi`) stands; the stated mechanism does not.
6. **Adding `playwright.config.*` to `isGateConfigPath` catches none of the four weakenings it was proposed for.** Re-implemented `gateWeakened()` verbatim: `retries: 3` → false, `fullyParallel: false` → false, raised `expect.timeout` → false, `forbidOnly: false` → false. Only a pre-existing `max*` integer key fires.
7. **`toMatchAriaSnapshot` is not a Playwright 1.63 feature.** It shipped in **1.49**. The claim was sourced to a third-party 1.63 release blog. flow does not need a bleeding-edge pin to recommend aria snapshots.
8. **OSWorld 2.0's 11.53% is a measured aggregate, not a cap.** The stated cap is "no task relies on it for more than 50%" — far weaker than "capped at ~11%". And "prioritises functional checks over environment state and artifacts" inverts the preposition: the paper says checks *over* (i.e. on) concrete environment states, not instead of them.
9. **The "consistency-bias paradox" is reported for two production-deployed judges, not the 21-judge cohort.** The κ range 0.376–0.511 was not visible in the source opened.
10. **Rating Roulette does not say sampling can be disabled "without degrading performance".** The paper says the opposite: "there is a degradation in performance if run without sampling", framed as a trade-off against self-reliability.
11. **"Visual fidelity is a poor proxy for interaction realization" is not a UI2App quote.** The real sentence is stronger and should be used instead: "the leader on visual fidelity (VFS) places fourth on IIS, 5.2× behind the IIS leader."
12. **`claude -p --image` does not exist.** `claude -p "…" --image /tmp/x.png` → `error: unknown option '--image'`. A screenshot reaches a headless judge only by path reference in the prompt.
13. **Mind2Web 2's compounding uses the wrong denominator.** 50 is the *total* node count; the paper reports **34 leaf nodes** on average. 0.9903³⁴ ≈ 0.72, not 0.61. And 99.03% is 7 errors in 720 sampled nodes — a pooled rate, not a per-trial independent probability, so the exponentiation is rhetorical either way.
14. **JND-area is not "the metric that actually discriminated".** At its own recommended `--max-area 1.0` it false-greens a 100×100 fully-recoloured button on a 1280×800 page (`visible_area=0.977% → PASS`) that plain `odiff` catches at exit 22. It has the same small-area blindness it was proposed to fix.
15. **A second viewport is not the anti-degeneracy constraint.** A cheat page with corrected line-heights scored **0.00% at both 480 and 1280** with no `h1`/`p`/`a`. The first cheat's 1.03%-vs-0.39% split was a denominator artefact on the same ~3970 wrong pixels; an independently built cheat page scored 0.59% at 1280 and 0.84% at 480 — **1.4× apart**, close enough that one threshold passes both. The structure gate is what catches these, at every viewport.
16. **The stale-cache 304 false green is `python3 -m http.server`-specific.** Vite sends `Cache-Control: no-cache` plus a content ETag and served fresh content on a same-second edit. The rule is "don't verify against `python3 -m http.server`", not "instrument every app with a build id".
17. **`curl -sf` does not catch the `file://` fixture cheat** in the shape it was recommended: the hardened verifier *starts the app itself*, so the preflight passes and the fixture cheat exits 0 with the backend returning 500. The preflight catches the different case where nothing ever starts.
18. **BSD grep on macOS does support `\s` in `-E` patterns** on this machine (`grep (BSD grep, GNU compatible) 2.6.0-FreeBSD`). Whatever silently failed, it was not `\s`. `[[:space:]]` remains harmless and more portable.
19. **`agent-browser close --all` "can exit 1"** did not reproduce; the phantom-session registration it was blamed on did not appear in a later listing. The *destructive scope* half is confirmed and is the reason to avoid it: one call closed **11 sessions** across every process that had ever created one.
20. **`agent-browser`'s relative `--baseline` resolution is stateful, not simply cwd-blind.** The same relative name from the same directory succeeded before a daemon respawn and failed after. Worse than "it ignores cwd", and the practical rule (always absolute) is unchanged.
21. **The reward-hacking "write access to both implementation and verification code" quote is misattributed.** It is in arXiv 2603.07084 (Countdown-Code), not in SpecBench (2605.21384) or 2604.15149 — and 2604.15149 is *not* EvilGenie, it is "LLMs Gaming Verifiers". EvilGenie is 2511.21654.
22. **mini-swe-agent's defaults contradict the "step limit 250 / 128" figure**: `step_limit: int = 0` (unlimited), `wall_time_limit_seconds: 0`, `cost_limit: float = 3.0`. The 250/128 number was also cited to arXiv 2601.22129, which is SWE-Replay and contains no mini-swe-agent limits.
23. **Factory Missions' `validation-state.json`, `fulfills`, `successState` and `discoveredIssues` are not in the primary post.** They come solely from an unofficial mitmweb prompt capture, and that capture shows assertion states are pass/fail/**BLOCKED**, not binary. The primary source carries only the case-study numbers (16.5 h, 6 milestones, 185 runs).
24. **Unsupported numbers to drop entirely:** Design2Code's GPT-4o per-metric scores (93.0/98.2/85.5/84.1/90.4) and its CLIP human-correlation coefficient (0.4929) — neither is in the sources cited for them; ImageMagick being "~6× slower per the odiff benchmark" (no benchmark was cited or opened); Figma Dev Mode pricing and the "6-call Starter limit"; browser-use's `--model` requirement as sourced; Aider's "3 reflections"; "retries can mask 1 in 7 failing tests" (the real figure in that literature is a *prevalence* rate — ~1 in 7 tests are flaky at some point — not a masking rate). The measured fact is better anyway: a flaky-then-passing Playwright run with `retries: 1` prints `1 flaky` and **exits 0**.

25. **`AGENT_BROWSER_DEFAULT_TIMEOUT` does bound a failing `wait`.** One angle reported the env var making no difference (152 s vs 153 s); an independent probe measured the *same* command returning in **2 s** with it set. Both angles reached the same rule — never call `wait` in a verifier — but only one of them reached it honestly. Ship the rule, not the disproof.
26. **The ANSI-escape wedge-desynchronisation premise is false as stated.** The claim was that Playwright and agent-browser leak escapes into `verify.last` despite `CI=true`, so identical failures hash differently. Two runs of the same failing spec through flow's own `runVerify` with `--reporter=line` produced **identical signatures**. Untested for parallel workers, retries, or the default list/html reporter — which is where it would show up first, if it shows up at all.
27. **`gateWeakened()` fires on a legitimate tightening.** Beyond the four false negatives in defect 6, `maxWarnings: 5 → 1` — strictly stricter — returns **true**. A tamper detector that flags honest work is a detector the first annoyed user disables, so any extension of `isGateConfigPath` must fix the direction check in the same commit.
28. **Our own `browser-verifier.md` §4 step 4 is a false promise.** "Add `.loop-target` to `permissions.deny` so the loop cannot edit the target it is scored against" — deny rules cover Claude's built-in file tools and the bash file commands it recognises, and explicitly do not apply to subprocesses that open files themselves (A). `playwright test -u` is one; `cp` is one. Deny is a speed bump on the honest path; the enforcement is the byte hash.
29. **Our own `browser-verifier.md` §4 step 3 calibrates the wrong way.** "Set `maxMismatchPct` just under the current reading" makes a target-match loop exit on its first cosmetic improvement. The reading is where you *start*; the threshold is the bar you want to clear.
30. **`inferTargetFromVerify` — grepping `--target` out of the verify string — solves nothing.** It does not fire on the documented default `--verify 'sh tests/ui/verify.sh'`, which is the exact shape reproduced as broken in §10, and it is redundant against every other shape once the hash is un-gated.

---

## 12. Sources (primary)

- **Local source, read verbatim 2026-09-09:** `plugins/flow/bin/lib/loop/{verify,tamper,contract,init}.js`; `plugins/flow/skills/loop/{SKILL.md,references/verifier-design.md}`; `plugins/web/skills/website-cloner/{SKILL.md,scripts/clone-extract.mjs}`.
- **Local measurement, this machine (Darwin 25.4.0, `/bin/sh` = bash 3.2.57, node v26.8.1):** agent-browser 0.23.4, Playwright 1.60.0 global / 1.63.0 npm latest, chrome-devtools-mcp 1.9.0, odiff 4.5.0, pixelmatch 7.2.0, axe-core 4.13.0, Lighthouse, `curl`, `perl`, `python3`. No `timeout`, `gtimeout` or `setsid`.
- code.claude.com/docs/en/{chrome, permissions, agent-sdk/agent-loop} — read 2026-09-08/09. anthropics/claude-code#66125 (closed as not planned).
- playwright.dev/docs/{test-cli, test-configuration, test-timeouts, test-snapshots, test-webserver, docker, aria-snapshots, api/class-page, api/class-locatorassertions}. github.com/vercel-labs/agent-browser (README, CHANGELOG). ChromeDevTools/chrome-devtools-mcp `docs/cli.md`. docs.cypress.io/app/references/command-line. chromatic.com/docs/cli. browserstack.com/docs/percy/references/commands + percy/cli#1181. github.com/{dmtrKovalenko/odiff, mapbox/pixelmatch, garris/BackstopJS, kornelski/dssim, cloudinary/ssimulacra2, theredsix/agent-browser-protocol}. lost-pixel.com/blog/lost-pixel-team-is-joining-figma (2026-04-22). developers.figma.com/docs/figma-mcp-server. w3.org/community/design-tokens/2025/10/28 (DTCG 2025.10). legacy.imagemagick.org/script/compare.php.
- **arXiv, re-fetched:** 2608.22103 (Hack-Verifiable Terminal Bench, 2026-08-22), 2511.08195v2 (UI2Code^N), 2403.03163 (Design2Code), 2605.26144 (VISTA), 2606.29537 (OSWorld 2.0), 2401.13649 (VisualWebArena), 2401.13919 (WebVoyager), 2506.21506 (Mind2Web 2), 2604.25235 (VLM judges rank but cannot score), 2510.27106 (Rating Roulette), 2606.19544 (Reliability without Validity), 2603.28304 (temperature in LLM-as-a-judge), 2510.08783 (MLLM as a UI Judge), 2603.26648 (Vision2Web), 2607.01728 (Beyond Pixel Diffs), 2607.06306 (UI2App), 2604.19750 (VF-Coder), 2606.28430 (Building to the Test), 2601.05777 (EET), 2601.22129 (SWE-Replay), 2603.07084 (Countdown-Code), 2511.21654 (EvilGenie).
- **Harness docs:** docs.openhands.dev/sdk/guides/agent-stuck-detector; github.com/SWE-agent/mini-swe-agent `agents/default.py`; jules.google/docs/changelog/2026-01-26-1; factory.ai/news/missions-architecture; docs.github.com/copilot/…/customize-the-agent-firewall; claude.com/blog/getting-started-with-loops.
