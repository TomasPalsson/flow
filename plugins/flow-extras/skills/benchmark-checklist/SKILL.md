---
name: benchmark-checklist
description: "Vet a measured number before reporting or acting on it: a speedup, regression, latency, throughput or p95 claim, a before/after in a PR body, or a choice between two libraries or configs based on a run. Names what limits the number, checks warm vs cold, errors, repeated runs with range, end-to-end relevance and a same-way baseline, then gives a verdict (faster, slower, no difference, inconclusive). Also holds the order to try performance fixes in. Not for finding why code is slow with no number yet (use /flow:fix) and not for eval-score significance (use agent-evals)."
---

# Benchmark checklist

A run that went wrong still prints a plausible number: failed requests are fast, a cache skips the work, a side was left on defaults, noise looks like signal. The checklist exists so the number you report is one you can explain. Answer each question with evidence from a run, not from reading the code.

## Step 1: Write the claim

Write the sentence you expect to ship before you measure, with metric, direction and size: "export takes 30% less time at p50 on the 60k-row dataset". "33% faster" is ambiguous (time down 33% is throughput up 50%), so name the metric. The questions below test that sentence, and it cannot quietly drift to fit whatever comes out.

A quick ballpark the user asked for needs one run plus questions 4 and 7, and the report says it is one run. A choice between options is never a ballpark.

## Step 2: Record the conditions

Write down, before running: baseline and candidate commit SHAs, build mode (release, not debug), input size and shape, harness and flags, machine. Check `uptime` and `nproc`; if the machine is busy and you cannot stop the load, interleave the sides so both see the same noise, and say so. These go in the report so a reviewer can re-run it.

## Step 3: Ask the seven questions

1. **Why not double?** Name the limiter: a core, a lock, disk, network, or the load generator itself. Get it from a profile or counters (`top`, `pidstat`, `node --cpu-prof`, `py-spy`, `perf`, `strace -c`) taken in a run you do not report, since profilers slow the work. A change that did not move the number is explained by its limiter, so find it before calling the change useless.
2. **Was it tuned and measured the same way?** Both sides get the same build, flags, pools, data and versions, and the same warm or cold caches. Right after a restart, caches and JIT are cold and the baseline is penalised; a repeated identical query measures only cache hits, so report hit ratio and miss latency separately. If one side runs on defaults, you compared configurations, so tune it first. If you cannot, pick no winner. If the baseline does not have the feature, there is no ratio: measure the added work and the end-to-end wait against an absolute budget ("search adds 40 ms p50, budget 50 ms") and say the baseline lacks it.
3. **Did it break limits?** Do the arithmetic: bytes per second against disk and network bandwidth, and time saved against the time the changed piece took. Removing a piece that is 10% of the run makes it at most about 11% faster. A result past a limit means the run measured something other than the work.
4. **Did it error?** Count failures and non-success responses, and check outputs are correct, not just present (run the test suite or diff outputs against the old code). For a rewrite, keep the frozen original and run a randomized differential against it, including degenerate inputs. For a cache, test cache key correctness: inputs that differ in any field that changes the result must not share a key. Rejections are fast and timeouts slow, so errors skew both ways. If the script does not count errors, add the count.
5. **Does it reproduce?** Run each side at least 5 times, alternating A, B, A, B so warmup and drift favour neither. Report median and range. A gap smaller than the run-to-run spread is no measurable difference, and a change inside the noise is reverted, since it adds code for no proven gain. Re-measure the winner blind: have the harness label sides A and B so the reading does not know which is the candidate. A p95 needs hundreds of samples per side; one request is one sample. For close calls use a rank-sum test or the harness statistics. Use a load tool (`wrk`, `hey`, `k6`) with a warmup phase and fixed duration and concurrency, not a loop of `curl`.
6. **Does it matter end to end?** Next to a micro result, measure the path a user waits on with realistic data sizes and concurrency, and report the micro result as a share of the whole. Check other representative inputs (small, large, nested) for regressions and report the geomean across input shapes plus the worst shape, since a mean can hide one shape that got much slower, and memory, startup or size cost of the change. A laptop result is preliminary; say what a staging or canary measurement would settle.
7. **Did the work happen?** Confirm the timed region did the work: the request reached the server, rows were written, the generator was iterated, the promise awaited, the result used. Lazy code and timeouts produce numbers for work that never happened.

## Step 4: Report

- Lead with the verdict: faster, slower, no measurable difference, or inconclusive. Call it inconclusive when you cannot name the limiter, a side ran untuned, or questions 4 and 7 went unchecked, and name the gap.
- A metric that was not collected is N/A, never 0. Compare only like coverage: the same inputs and the same set of runs on both sides, and a metric one side lacks is dropped from the ratio. Say where the clock starts and stops (process start, first request, after warmup). A projection ("at 10x load") is a range with its assumptions, not a point.
- Give one primary number with unit, run count, range, limiter, and the command that regenerates it: "p50 41 ms to 33 ms, median of 7 runs per side, range 32 to 35 ms, bound by JSON parsing on one core; `./bench.sh --runs 7`". A PR body carries that one number; the runs and limiter evidence go in a linked artifact or notes file.

## Step 5: Order to try fixes in

When the number says the code is slow, try these cheapest first and stop at the first that meets the target, since an earlier rung removes work and a later one only speeds it up:

1. Don't do it: stop work whose result nothing uses.
2. Do it, but not again: cache or reuse.
3. Do it less.
4. Do it later.
5. Do it when they're not looking: off the user's path.
6. Do it concurrently.
7. Do it cheaper.

Measure each attempt with Steps 1 to 4 before trying the next, and keep an attempt ledger (change, number, kept or reverted) in the notes file, so a reverted idea is not tried twice.

## Eval scores

For an eval score, the same questions hold (did every trial do the task, does the gap hold across trials). Sample size, paired tests and intervals live in the `agent-evals` skill (Decision 3); use it there instead of repeating them here.

Credit: adapted from cursor/plugins pstack skills/benchmark-checklist, principle-explain-the-number and poteto-mode/playbooks/perf-issue.md @ ccb5507 (MIT).
Credit: adapted from garrytan/gstack plan-devex-review/SKILL.md.tmpl, benchmark/SKILL.md.tmpl and health/SKILL.md.tmpl @ 5b9b837 (MIT).
Credit: adapted from addyosmani/agent-skills skills/performance-optimization/SKILL.md (and its optimization patterns reference) @ 1be8e34 (MIT).
Credit: adapted from vercel-labs/agent-skills vercel-optimize/references/doctrine.md @ 063bee9 (MIT).
Credit: adapted from anthropics/skills managed-agents-quickstarts/performance-tuner.md @ dbd4588 (Apache-2.0).
Credit: adapted from anthropics/claude-plugins-official project-artifact/SKILL.md and receipts/SKILL.md @ a9fd216 (Apache-2.0).
