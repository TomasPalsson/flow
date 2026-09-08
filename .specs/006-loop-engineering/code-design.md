# Code design — spec 006 loop engineering

## Contract for this slice — Slice 1

Read `.specs/006-loop-engineering/spec.md` IN FULL first; K-A through K-L are binding and this slice implements all of them except the hook file itself. Also read `plugins/flow/bin/lib/tutorial.js` (the module pattern: `run(argv, ...)` export, TutorialError-style error class, zero deps) and the `computeNext`, `cmdInit`, `cmdDoctor` and dispatch sections of `plugins/flow/bin/flow` before editing it.

Module shape (`plugins/flow/bin/lib/loop.js`):
- `module.exports = { run(argv, cwd, env), parseContract, tick, tamperCheck, runVerify }` — the named helpers are exported for tests only.
- `run` returns an integer exit code and writes to `process.stdout`/`process.stderr`; never calls `process.exit`.
- Contract I/O: `readContract(dir)` → `{ front: {key: value}, body: string, corrupt: <why>|null }`; `writeContract(dir, front, body)` atomic (tmp + rename), keys in K-B order, unknown keys preserved after them.
- Verifier: `runVerify(toplevel, verify, timeoutSec)` → `{ rc, output, sig }` using `spawnSync('sh', ['-c', verify], { cwd, env: {...env, CI:'true', FLOW_LOOP:'1'}, timeout: timeoutSec*1000 })`; on timeout rc 124 and the message appended; writes `verify.last`.
- Tamper: `tamperCheck(toplevel, front)` → array of strings (empty = clean) per K-F; `countTestFiles(toplevel)` uses `git ls-files` plus `git ls-files --others --exclude-standard`.
- Fingerprint: `fingerprint(toplevel)` → string from `git rev-parse HEAD`, cksum-equivalent (use `crypto.createHash('sha1')`) of `git status --porcelain` and of `git diff`.
- `tick(toplevel, opts)` implements K-H and returns `{ action: 'allow'|'continue'|'finish', reason, status, iteration }`; `--hook` prints `JSON.stringify({decision:'block', reason})` for continue/finish and nothing for allow.
- `runDriver(toplevel, front, body, flags)` implements K-I; `claude` is resolved from `env.PATH` (tests put a fake `claude` first on PATH); `--dry-run` prints and returns 0.
- Log: `appendLog(dir, fields)` writes K-E lines.
- `bin/flow` deltas: `else if (cmd === 'loop') process.exit(require('./lib/loop.js').run(rest, process.cwd(), process.env));` plus help text; doctor lines and `computeNext` branch per K-L; `.gitignore` lines in `cmdInit` (append only if absent).

Exit codes: init 0/1; check 0 pass /1 fail /2 suspect; tick 0 always; run 0 done / 1 stopped / 2 suspect; status 0 (3 = no contract); stop 0; log 0.

Test conventions: see `plugins/flow/scripts/tests/test_cli.sh` for `cli_in <dir> <home> <args...>`; create fixtures with `tmp_repo`; use `test -f done.txt`-style verifiers; for the fake `claude`, write an executable script into a temp bin dir and prepend it to PATH via `env PATH=...`.

## Contract for this slice — Slice 2

Read `.specs/006-loop-engineering/spec.md` §K-K in full, `plugins/flow/hooks/lib/hookout.sh` (public API only: `hook_skip_if_off`, `hook_project_dir`, `hook_field`, `have`), one existing small hook (`plugins/flow/hooks/turn-stamp.sh`) and `plugins/flow/hooks/tests/lib.sh`. Do NOT modify hookout.sh or any existing hook.

`loop-gate.sh` is a pass-through: it decides nothing. Shape:
```
#!/usr/bin/env bash
# loop-gate.sh — Stop hook. Passes `flow loop tick --hook` through. See spec 006 K-K.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
. "$HERE/lib/hookout.sh"
hook_skip_if_off
dir=$(hook_project_dir)
[ -f "$dir/.claude/loop/loop.md" ] || exit 0
flow_bin=${CC_FLOW_BIN:-}
if [ -z "$flow_bin" ]; then have node || exit 0; flow_bin="node $HERE/../bin/flow"; fi
sid=$(hook_field .session_id)
out=$(cd "$dir" && $flow_bin loop tick --hook --session "$sid" 2>/dev/null) || exit 0
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
```
(`$flow_bin` is intentionally word-split so `CC_FLOW_BIN` may carry `node path` or a single script path; quote `$dir`.) In `hooks.json`, add to the existing `Stop` group's `hooks` array, after `stop-gate.sh`: `{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/loop-gate.sh","timeout":660,"statusMessage":"flow: loop tick…"}`. Keep the JSON valid (the suite may parse it).

## Contract for this slice — Slice 3

Read `.specs/006-loop-engineering/spec.md` in full, the shipped `plugins/flow/bin/lib/loop.js --help` text (run `node plugins/flow/bin/flow loop --help` and each subcommand's `--help`), `plugins/flow/hooks/loop-gate.sh`, the current `docs/reference/workflows-and-cli.md`, `docs/reference/hooks.md`, `plugins/flow/skills/fix/SKILL.md`, `plugins/flow/skills/fix/execution-prompt.md`, `plugins/flow/README.md`. Prose only; no code changes. Every command you document must exist in the shipped `--help` (a test greps for the subcommand names). Keep the tone of the existing reference docs (terse, tables). The fix skill keeps its structure; only the execution section and the completion-promise wording change, and every `ralph` mention goes.
