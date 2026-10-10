---
name: fix-feedback-loops
description: Ladder for building a red-capable feedback loop when a bug resists a plain failing test, plus minimise, ranked hypotheses and instrumentation rules
---

# Feedback loops for bugs that resist a plain test

A tight pass/fail signal that goes red on this bug is what finds the cause. Bisection, hypotheses and instrumentation only consume it. Without it, reading code is guessing. Spend disproportionate effort here before touching a theory.

**Redact first.** Write `<REDACTED>` in place of any secret in a command, output or captured artifact you show. Keep credentials in env vars, and quote only the lines of a captured artifact that carry the signal. If redacted output is not enough to diagnose, say so and ask.

## The ladder, in order

1. Failing test at whatever seam reaches the bug: unit, integration, e2e.
2. curl or HTTP script against a running dev server.
3. CLI invocation with a fixture input, stdout diffed against a known-good snapshot.
4. Headless browser script that drives the UI and asserts on DOM, console or network. Drive it with real UI actions; a fixture may set preconditions but must not inject the symptom, or the loop proves the fixture rather than the bug. Run it twice with a reset between (close the browser, clear storage, reopen), as `/flow:fix` §1 requires for the frontend category.
5. Replay of a captured trace: save a real request, payload or event log to disk and replay it through the code path in isolation.
6. Throwaway harness: a minimal subset of the system (one service, mocked deps) exercised by one function call.
7. Property or fuzz loop: for "sometimes wrong output", run 1000 random inputs and look for the failure.
8. Bisection harness: if the bug appeared between two known states, automate "boot at state X, check" so `git bisect run` can drive it.
9. Differential loop: the same input through old and new version (or two configs), outputs diffed.
10. HITL script, last resort: when a human must click, copy [`scripts/hitl-loop.template.sh`](scripts/hitl-loop.template.sh) so the loop is still structured and its output comes back to you. A human-driven loop is an extra stop before the §3 gate: say so in one line before you start it.

## Tighten it

- Faster: cache setup, skip unrelated init, narrow the scope.
- Sharper: assert the specific symptom, not "did not crash".
- Deterministic: pin time, seed the RNG, isolate the filesystem, freeze the network.

A 30-second flaky loop is barely better than none; a 2-second deterministic one is a superpower.

## Non-deterministic bugs

Do not chase a clean repro; raise the reproduction rate. Loop the trigger 100 times, parallelise, add stress, narrow timing windows, inject sleeps. A 50% flake is debuggable, 1% is not.

## Done when

You can name **one command** you have **already run once** (show the invocation and its redacted output) that is:

- red-capable: it drives the real bug path and asserts the user's exact symptom, so it can go red on this bug and green once fixed;
- deterministic: same verdict every run (flaky bugs: a pinned, high rate);
- fast: seconds, not minutes;
- agent-runnable: unattended, except through the HITL template.

No such command, no theory. That command becomes the reproduction committed beside the test.

## Minimise

Once red, cut inputs, callers, config, data and steps one at a time, re-running after each cut, keeping only what is load-bearing. Done when removing any remaining element turns the loop green.

## Hypotheses

Write 3-5 ranked hypotheses before testing any. Each must be falsifiable: "If X is the cause, then changing Y makes the bug disappear." If you cannot state the prediction, discard or sharpen it. Probe in rank order without stopping; the ranked list, with the one that held, goes into the §3 gate message, so it adds no stop of its own.

## Instrument

- Every probe maps to one prediction; change one variable at a time.
- Prefer a debugger or REPL over logs, targeted logs over "log everything and grep".
- Tag every debug log `[DEBUG-<4 hex>]` (for example `[DEBUG-a4f2]`) so cleanup is one grep.
- Performance regressions: logs are usually wrong. Take a baseline measurement (timing harness, profiler, query plan), then bisect. Measure first, fix second; vet the baseline and every later number by calling the Skill tool with "flow-extras:benchmark-checklist" (skip quietly when flow-extras is not installed).

## No correct seam is a finding

A correct seam exercises the real bug pattern as it occurs at the call site. If the only seam for a regression test is too shallow (a single-caller test when the bug needs several callers), a test there gives false confidence. Say so at the §3 gate and park the missing seam with `/flow:issue`.

Adapted from mattpocock/skills diagnosing-bugs @ f3fc563 (MIT).
