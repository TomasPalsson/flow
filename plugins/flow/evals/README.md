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
| `quality` | The code Claude writes under the plugin: reuse, abstraction, guards, comments, scope, test quality — one case per rubric row family, graders lifted from the rubric's grader-mapping table | with-plugin vs. no-plugin baseline (delta is the point) |
| `routing` | The right skill fires for a plain-language request, and the wrong ones don't; two negative cases prove nothing fires when nothing should | `tool_used` graders are `arm: with-only` — a plugin-fired indicator, not part of the baseline-vs-plugin score |
| `invariant` | A promise the plugin makes holds regardless of the specific skill: reproduce before fixing, never weaken a test to make it pass, don't claim completion without having verified | both, unless the check only makes sense with the plugin |
| `pipeline` | The full `/flow:spec` → `/flow:next` pipeline end to end on a fixture, graded on the artifacts and code it produces, not just whether a skill fired: `flow-feature` (`/flow:spec --unattended` then `/flow:next --unattended` repeatedly, unattended build, graded on the route being stated and a real regression test written for the new properties — not a fixed `.specs/` artifact path, since the route it takes decides whether one exists at all), `fix-bug` (patches a bug, graded on the patched source), `spec-first-turn` (its one batched discovery turn states the route and offers every pre-answered position in the same message), `spec-only` (`/flow:spec --unattended` in one shot — no resumed transcript, since the route's approval gate never scales down — graded on what it writes or says and that it never lands the change itself), `prep-first-turn` (first turn asks exactly one hypothesis-led question; writing `PREP.md` before that question is prep's designed behaviour and must not count against it) | `--ablation none`, one run each; the pipeline output itself is the point |
| `needs-bash` | Secondary tag on any case that grants the `Bash` tool; skipped with a notice when `socat` is absent (this machine has no `socat`) | — |

## Case shape

Each case is one directory `evals/<tier>-<slug>/` with:

- `case.yaml` — `schema_version`, `name`, `tags`, `runs`, `context.scaffold_script`,
  `execution.prompt` / `execution.max_turns` / `execution.allowed_tools`, and an
  inline `graders:` list (at least one; the CLI rejects zero).
- `scaffold.sh` — an executable bash script the CLI runs (with `--scaffold`) to
  build a small fixture repo before the case starts. No `.git` (the session-context
  hook stays quiet), no shared fixture library — every case owns its own file, even
  when two scaffolds look similar.

`claude plugin eval` reads `case.yaml` itself; nothing here re-implements grading —
see `plugins/flow/bin/lib/eval.js`'s comment for that decision.

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
authored. `--allow-tools Write Edit` (and `Bash` for `needs-bash` cases) grants the
gated tools the fixtures need. `--trust-plugin` skips the first-run trust prompt.

## Cost

Per the spec's performance budget: a full run (`-j 4`, 3 runs, ~30 cases,
with/without ablation) targets ≤ 15 minutes and ≤ $25; a `quality`-only loop
verifier (`--runs 2`, `--ablation none`) targets ≤ 6 minutes and ≤ $8. Above $40 for
a full run, drop `--runs` to 2 before dropping cases. `evals/ledger.jsonl` is
committed (one JSON line per run: sha, model, per-tag score, delta, cost);
`evals/results/` is gitignored — prune it yourself.
