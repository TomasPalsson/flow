# flow eval suite

`plugins/flow/evals/` measures the code Claude writes under the flow plugin
against the `no-slop` rubric (`plugins/flow/skills/no-slop/references/rubric.md`),
plus whether the right skill fires and whether flow's invariants hold. Run it
with `claude plugin eval` directly, or via `flow eval` (`plugins/flow/bin/lib/eval.js`),
which pins models, writes `evals/ledger.jsonl`, and prints a per-tag summary.

## Tiers (tags)

Every case carries exactly one primary tag from `plugins/flow/bin/lib/eval/contract.js`'s
`TAGS`, plus `needs-bash` when it grants the `Bash` tool:

| Tag | What it measures | Arms scored |
|---|---|---|
| `quality` | The code Claude writes under the plugin: reuse, abstraction, guards, comments, scope, test quality — one case per rubric row family, graders lifted from the rubric's grader-mapping table, plus six harder `quality-hard-*` cases with the trap moved further from the obvious spot: `far-helper` (the reusable helper lives several files away from the call site), `typed-guard` (a guard on a field a validating `__post_init__` already guarantees), `flag-temptation` (a mode flag on a two-call-site function vs. a second small function), `test-bites` (a test-first test that must actually be able to fail), `style-drift` (match the edited file's own style, not the project's usual one), `scope-creep` (touch nothing beyond the one reported fix in a file full of tempting cleanup) | with-plugin vs. no-plugin baseline (delta is the point) |
| `routing` | The right skill fires for a plain-language request, and the wrong ones don't; two negative cases prove nothing fires when nothing should | `tool_used` graders are `arm: with-only` — a plugin-fired indicator, not part of the baseline-vs-plugin score |
| `invariant` | A promise the plugin makes holds regardless of the specific skill: reproduce before fixing, never weaken a test to make it pass, don't claim completion without having verified | both, unless the check only makes sense with the plugin |
| `pipeline` | The full `/flow:spec` → `/flow:next` pipeline end to end on a fixture, graded on the artifacts and code it produces, not just whether a skill fired: `flow-feature` (`/flow:spec --unattended` then `/flow:next --unattended` repeatedly, unattended build, graded on the route being stated and a real regression test written for the new properties — not a fixed `.specs/` artifact path, since the route it takes decides whether one exists at all), `fix-bug` (patches a bug, graded on the patched source and a mutation post-check that re-introduces the bug to prove the new test bites), `far-helper` (the same unattended pipeline on a repo whose slug helper is called `to_kebab` and lives in `app/support/` — found by its package or its body, never by its name), `spec-first-turn` (its one batched discovery turn states the route and offers every pre-answered position in the same message), `spec-only` (`/flow:spec --unattended` in one shot — no resumed transcript, since the route's approval gate never scales down — graded on what it writes or says and that it never lands the change itself), `prep-first-turn` (first turn asks exactly one hypothesis-led question; writing `PREP.md` before that question is prep's designed behaviour and must not count against it), `prep-resume-seed` (a bare `/flow:prep` with a `/flow:develop-idea` seed PREP.md on disk resumes that seed instead of asking for the idea) | `--ablation none`, one run each; the pipeline output itself is the point |
| `xhard` | The hardest tier, aimed at the full flow pipeline (prep → spec → next → build waves → phase tests → gates → PASS → verify, plus one `/flow:next --finish` run), run with `--ablation none`: every case stacks two or more traps, grades behaviour with hidden tests the model never sees (`hidden/`, run by `postcheck.sh`), and ships a `solution.sh` that `scripts/case-selfcheck` uses to prove the case can be passed and that the untouched scaffold fails it. | both, unless the case says otherwise |
| `needs-bash` | Secondary tag on any case that grants the `Bash` tool; skipped with a notice when `socat` is absent | — |

## Case shape

Each case is one directory `evals/<tier>-<slug>/` with:

- `case.yaml` — `schema_version`, `name`, `tags`, `runs`, `context.scaffold_script`,
  `execution.prompt` / `execution.max_turns` (≤ 200) / `execution.timeout_seconds`
  (≤ 3600, default 300 — a top-level `timeout_seconds` is silently ignored) /
  `execution.allowed_tools`, and an inline `graders:` list (at least one; the CLI
  rejects zero). `execution.env` takes `EVAL_*` keys only.
- `scaffold.sh` — an executable bash script the CLI runs (with `--scaffold`) to
  build a small fixture repo before the case starts. A `.git` only when the case
  needs one (the pipeline cases, and `routing-qa`'s feature branch). The sandbox
  masks `/bin/git` (as of claude 2.1.284), and flow's router cannot work without
  it: every state reads `scan-failed`, so a git-dependent case cannot pass under
  `claude plugin eval` as it stands. No shared fixture library — every case owns its own file, even
  when two scaffolds look similar. Plant nothing a model can fix by reading when
  the case is about routing: an obvious bug invites a direct fix instead of the skill.

`claude plugin eval` reads `case.yaml` itself; nothing here re-implements grading —
see `plugins/flow/bin/lib/eval.js`'s comment for that decision.

## Post-checks

A case may ship an executable `postcheck.sh` (bash, `set -u`), run once per run
after `claude plugin eval` returns, cwd'd into that run's workspace with
`EVAL_CASE`/`EVAL_RUN`/`EVAL_TRACE`/`EVAL_PLUGIN_ROOT` set and a 120s timeout;
exit 0 passes, non-zero fails, and a case counts as passed only if its grader
score clears the threshold *and* every run's post-check passed, too (`flow eval`
prints `postcheck <case> <pass>/<total>`). The standard shape for a quality
case is `slop-check --all-lines --files <path>...` (no git needed; every line
of each listed file counts as added) `--strict`, run against the file(s) the
task should touch.

## Self-check

`plugins/flow/scripts/case-selfcheck [--root <evals-dir>] [--keep] [<case-name>...]`
(python3 + PyYAML) proves an `xhard-*` case is winnable and not a no-op. With no
names it checks every `xhard-*` directory under the root (default: this `evals/`).
Per case, first failure wins:

1. Shape: `case.yaml` parses, `schema_version` is `"1.1"`, `name` matches the dir,
   tags are in `TAGS`, `scaffold.sh` is executable, graders and `execution.prompt`
   are non-empty, `postcheck.sh` (if any) is executable.
2. A case is gradeable when it has a `file_exists` grader, a `regex` grader over
   `{source: file}`, or a `postcheck.sh`. A gradeable case must ship an executable
   `solution.sh`; a routing-only case just gets shape + scaffold checks.
3. Pristine: scaffold into a fresh tmp dir and evaluate the file graders and
   `postcheck.sh`. If they all pass, the case cannot tell a no-op from a fix and
   fails, unless the case dir holds a one-line `selfcheck-pristine-passes` file
   giving the reason a no-op is legal (e.g. a "must stop at the gate" case).
4. Solution: scaffold again, run `solution.sh` (cwd = the tree, `CASE_DIR` and
   `EVAL_PLUGIN_ROOT` set), then every file grader and `postcheck.sh` must pass.

`llm`, `tool_used`, and trace-targeted regex graders are skipped and counted.
`solution.sh` is the reference fix a model would have to reach; `hidden/` holds the
tests the model never sees, which `postcheck.sh` copies in and runs. Output is one
`PASS`/`FAIL` line per case and a `case-selfcheck: <p> passed, <f> failed` summary;
exit 0 iff nothing failed. `--keep` leaves the tmp dirs in place.

### Live mode

`claude plugin eval` masks `/bin/git` in its sandbox, so pipeline cases die at
`scan-failed` there. `case-selfcheck --live [--model M] [--judge-model J] [--runs N]
[-j N] [--out <dir>] [--keep] [--ledger] [<case>...]` runs the cases headless
outside it, in throwaway trees (default: every `xhard-*`; models default to
`DEFAULT_MODELS`; `-j` caps at 8). Per run: scaffold (real `HOME`, so auth works),
`claude -p <execution.prompt>` in the tree with this checkout's plugins and
`<plugin>/bin` first on `PATH` (so `flow` is this checkout's CLI), capped by
`execution.timeout_seconds` (the whole process group is killed), then every grader
(`regex` over the trace or a file, `tool_used`, `llm` via a headless judge call,
`file_exists`) and `postcheck.sh`. A run passes iff score is 1 and postcheck is ok.
Output: a `LIVE <case> score=.. post=.. turns=.. cost=$.. <secs>s` line per run with
an indented line per failed grader, then a summary; `<out>/results.json` and each
`<out>/<case>/run-<k>/trace.jsonl` are kept, the trees only with `--keep`.
`--ledger` appends one `xhard` line to `evals/ledger.jsonl`. Exit 0 iff every run
passed, 1 otherwise, 2 on setup errors. It spends real money.

## Adding a case

1. Pick the tier and a `<tier>-<slug>` name that doesn't collide with an existing one.
2. `mkdir plugins/flow/evals/<tier>-<slug> && cd` it.
3. Write `scaffold.sh` (`chmod +x`) that builds just enough fixture for the prompt
   to have something concrete to act on — an empty workspace makes Claude explore
   and bail instead of routing or writing code.
4. Write `case.yaml`: `schema_version: "1.1"`, the tags, `runs`, `execution.prompt`,
   `execution.max_turns`, `execution.allowed_tools`, and `graders:`. For a `quality`
   case, pick the grader type from the rubric's grader-mapping table (regex over
   `{source: file, path}` where the table says regex; at most one `llm` grader per
   case; `arm: with-only` on any `tool_used` grader).
5. `TEST_ONLY=test_evals.sh bash plugins/flow/scripts/tests/run.sh` checks the shape
   (schema_version, tags subset of `TAGS`, executable scaffold, at least one grader);
   add the new case name to `EV_REQUIRED_CASES` in `scripts/tests/test_evals.sh` if
   it is one of the cases the spec names as required.
6. Dry-run just that case: `claude plugin eval plugins/flow --case '<tier>-<slug>' --trust-plugin --no-publish --runs 1 --scaffold --allow-tools Write Edit --json /tmp/case.json`.

## Running the suite

```sh
# whole suite, pinned models, cost-capped, ledger line appended
flow eval

# one tag only, cheaper
flow eval --tag quality --runs 2

# raw CLI, no ledger, useful while authoring a case
claude plugin eval plugins/flow --case 'quality-*' --trust-plugin --no-publish \
  --runs 1 --ablation none --scaffold --allow-tools Write Edit \
  --max-cost-usd 6 --json /tmp/q.json
```

`--scaffold` runs the case's `scaffold.sh` as you; only pass it for case files you
authored. `--allow-tools` is an operator grant that applies to every case in one
invocation and OVERRIDES each case's own `execution.allowed_tools` rather than
narrowing it — measured on `routing-loop`: under a tier-wide `--allow-tools Write
Edit Bash` it ran the suite itself with Bash and scored 3/3 without the loop skill
ever firing, while the same case run alone with no grant scored 3/3 correctly. So
`flow eval` runs each selected case in its own `claude plugin eval` invocation and
grants only the gated tools (`Write`, `Edit`, `Bash`) that case's own
`allowed_tools` names. `--trust-plugin` skips the first-run trust prompt.

## Cost

Per the spec's performance budget: a full run (`-j 4`, 3 runs, ~30 cases,
with/without ablation) targets ≤ 15 minutes and ≤ $25; a `quality`-only loop
verifier (`--runs 2`, `--ablation none`) targets ≤ 6 minutes and ≤ $8. Above $40 for
a full run, drop `--runs` to 2 before dropping cases. `evals/ledger.jsonl` is
committed (one JSON line per run: sha, model, per-tag score, delta, cost);
`evals/results/` is gitignored — prune it yourself.
