---
name: verifier-design
description: How to write the exit condition of a loop so that it can fail, cannot be gamed cheaply, and says something true when it passes. Load before choosing --verify.
---

# Verifier design

The verifier is the loop. A weak one turns every other safeguard into theatre: the caps stop a loop that a good verifier would have stopped ten iterations earlier, and the model "finishes" work that was never checked.

## 1. The three tests a verifier must pass before the loop starts

1. **Red now.** Run it. Non-zero? Good. Zero? Either the goal is met (no loop) or the command cannot fail (not a verifier). `flow loop init` enforces this; `--allow-green` exists only for maintenance loops whose goal is "keep it green while doing X".
2. **Green by source, not by check.** Ask: what is the cheapest edit that makes this exit 0? If the answer touches the verifier's own inputs (a fixture the prompt mentions, a threshold in a config the task edits, a grep target the model can type), pick another verifier or move that input out of the task's reach.
3. **Same answer twice.** No network, no clock, no prompts, no dependence on files outside the repo. `flow loop` runs it with `CI=true` and `FLOW_LOOP=1` from the repo root with a timeout; anything that needs a running server must start it inside the command and stop it after.

## 2. Compose, order, bound

```bash
# fastest, most discriminating first; each && narrows
--verify "bun run typecheck && bun test tests/auth && bun run lint"
--verify "cargo build --locked && cargo test -q --test migration"
--verify "uv run pytest -q tests/test_export.py && test -f dist/report.pdf"
--verify "test $(grep -rl 'TODO(loop)' src | wc -l) -eq 0 && npm test"
```

- Put the check that the *current* task moves first; the full suite last. The verifier tail (40 lines) is what the next iteration reads — the first failure should be the relevant one.
- Bound the runtime below `verify_timeout` (default 600 s). A verifier that times out reads as a failure with `verify timed out`, which wedges the loop on the timeout rather than on the work.
- Prefer commands that print a structured summary at the end (test counts, the failing test names). The wedge detector hashes the first 60 lines with hashes and durations masked, so a verifier whose output is stable for the same failure is a verifier whose wedges get caught.

## 3. What the loop checks on top of a green verifier (the tamper veto)

`flow loop check` runs after every iteration and turns a green verifier into `suspect` when any of these hold since the base commit:

| Finding | Detector |
|---|---|
| fewer test files than at init | `git ls-files` + untracked, patterns `*_test.*`, `*.test.*`, `*.spec.*`, `test_*.*`, `tests/`, `__tests__/`, `spec/` |
| a new `.skip(`, `.only(`, `it.todo(`, `xfail`, `@pytest.mark.skip`, `#[ignore]`, `t.Skip(` in a test file | added lines in `git diff <base>` |
| `stopGate: false` or a lowered `max*`/`complexity`/`threshold` in gate config | same regex as `tamper-notice.sh` |
| the verifier string in the contract changed | cksum recorded at init |

A `suspect` run is not fixed inside the loop. The finding is reported verbatim and a human decides — the whole point is that the loop cannot argue itself past this check.

## 4. What the veto does not catch, and what does

- **Hardcoded expected values, assertions weakened in place, golden files rewritten.** Deterministic diff analysers exist for this (`checkwash`, PyPI: 21 named detectors, zero runtime deps, exit 1 = block, designed to run as a Stop hook or a required CI check; self-reported false-positive rate 1.72% on 1,800 commits). Add it to the verifier when the task touches tests: `--verify "checkwash diff <base>..HEAD && npm test"`.
- **Passing the visible suite while failing the hidden one.** Keep one test job the agent's shell cannot reach: CI on a protected branch, or a held-out test directory denied by `permissions.deny` (`Read` deny also blocks `Edit`/`Write` on the same path). Compare the two pass rates; a gap is the reward-hacking signal (SpecBench's metric).
- **Placeholders that compile.** Huntley's observation: "the reward function is compiling code", so expect stubs. A second, planning-shaped loop that greps for `todo!()`, `NotImplemented`, `pass  #`, empty handlers, and files them into the task list is cheaper than a stricter first loop.
- **Mutation-testing gates** (Stryker `thresholds.break`, `mutmut`, `cargo-mutants --in-diff`) measure whether tests kill changes, not whether lines run. Caution from Trail of Bits (April 2026): an agent that writes a regression test *from* a surviving mutant without deciding which behaviour is correct bakes the bug into the suite. If you use mutation testing in a loop, the prompt must say "decide the correct behaviour from the spec before writing the test".

## 5. Verifier catalogue by goal

| Goal | Verifier |
|---|---|
| a failing test passes | `<runner> <that test file>` then `&& <full suite>` |
| type-clean | `tsc --noEmit` / `pyright` / `cargo check` / `go vet ./...` |
| migration complete | `test $(grep -rl '<old api>' src | wc -l) -eq 0 && <suite>` |
| file under a size budget | `test $(wc -l < src/big.ts) -le 400 && <suite>` |
| artefact exists and works | `<build> && test -s dist/x && node dist/x --version` |
| backlog empty | `node -e "const t=require('./.claude/loop/tasks.json');process.exit(t.items.every(i=>i.passes)?0:1)" && <suite>` — the JSON is the model's to edit, so pair it with the suite and the tamper veto |
| docs build | `mkdocs build --strict` / `bun run docs:build` |
| browser flow works | `bunx playwright test tests/e2e/checkout.spec.ts` (start the server inside the command; bound it) |

When no command approximates the goal, the loop is the wrong tool: keep the judgement for a human gate at the end, or split the goal until a command exists.
