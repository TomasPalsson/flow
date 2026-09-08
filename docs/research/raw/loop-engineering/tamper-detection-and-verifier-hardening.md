# Tamper Detection and Verifier Hardening

Research for the "loop engineering" skill. Scope: checkwash, tdd-guard, Claude
Code-native anti-tamper patterns, mutation testing in agent loops, and
deterministic-verifier design. Excludes reward-hacking benchmark papers, Ralph
loop variants, /goal docs, and cost figures per instruction.

## Executive Summary

Two purpose-built tools exist for catching an agent that fakes a green build
by editing the *verification layer* instead of fixing the bug:

- **checkwash** (PyPI `checkwash`, `github.com/taipei49314/checkwash`) is a
  deterministic, offline, zero-LLM Python static analyzer of git diffs. It
  has 21 named detectors plus one derived rule, ships as a pip package or a
  single `.pyz`, and is meant to run as a required GitHub status check (not
  merely "installed") or as a Claude Code `Stop` hook. It is explicitly
  alpha and self-reports its own false-positive rate (1.72% on a 1,800-commit
  corpus) rather than claiming completeness.
- **tdd-guard** (`github.com/nizos/tdd-guard`) is the opposite architecture:
  a `PreToolUse` hook that calls an LLM (Claude, via the Agent SDK or the
  Anthropic API) to judge whether an `Edit`/`Write`/`MultiEdit` is consistent
  with Red-Green-Refactor TDD discipline — test-first, minimal
  implementation, no premature or over-implementation. It is judgment-based,
  not pattern-based, and its changelog is a running record of the false
  positives that judgment approach produces.

Claude Code's own permission system provides the substrate both tools sit on:
`permissions.deny` rules on `Read`/`Edit` paths, and `PreToolUse` hooks that
return exit code 2 or a `permissionDecision: "deny"` JSON payload — hook
decisions do **not** bypass deny rules, and deny rules are evaluated
deny-then-ask-then-allow regardless of what a hook says. Anthropic's own docs
do not describe a "held-out test suite for agents" pattern by name; that
pattern is assembled from permissions primitives (a `Read` deny rule on
`tests/**` also blocks `Edit`/`Write` on the same path) plus GitHub-side
CODEOWNERS and required status checks — none of which alone stop an agent
with unrestricted shell access, a limit every source below states plainly.

Mutation testing (Stryker, mutmut, cargo-mutants, pitest) supplies a second,
orthogonal signal — does the test suite actually kill semantic changes, not
just execute lines — and the emerging risk (Trail of Bits, April 2026) is
agents writing *new* tests directly from a surviving mutant without
verifying the mutant's behavior was a bug and not the spec, permanently
baking incorrect behavior into the regression suite as "expected."

## 1. checkwash

Sources: `https://pypi.org/pypi/checkwash/json` (PyPI JSON API, package
`checkwash` v0.3.2, author `taipei49314`), README at
`https://raw.githubusercontent.com/taipei49314/checkwash/main/README.md`,
`SPEC.md`, `THREATMODEL.md`, `docs/enterprise.md`, `docs/adversarial-catalog-2026-09.md`,
and source at `src/checkwash/{cli.py,hooks.py,detectors/__init__.py}` in the
same repo, all fetched directly (not through search synthesis, which
returned inconsistent detector/test counts on a first pass — see "Planted
instructions" below for why raw fetches were treated as ground truth here).

### What it is

> "**Check whether a code change weakens your tests.** A test can pass
> after it stops checking something useful. checkwash reads your Git diff
> and flags known patterns such as deleted assertions, skipped tests,
> relaxed expectations, and CI checks that stop failing." — README

> "**Runs locally. No LLM. No network during analysis. Never executes your
> code.**" — README

PyPI metadata (`pypi.org/pypi/checkwash/json`): summary "Flags known
patterns of weakened tests and CI checks in a Git diff.", `requires_python
>=3.11`, `requires_dist: ["pytest>=8; extra == \"dev\""]` (i.e. **zero
runtime dependencies** — pytest is dev-only), license Apache-2.0, keywords
`ai-agent, ci, code-review, reward-hacking, test-tampering`.

> "Alpha pre-release. 21 detectors, 1463 tests in the current source tree.
> Zero runtime dependencies." — README

### Detector list (all 21, verbatim from `SPEC.md` §4 "Rule IDs (frozen)")

| Rule ID | Trigger (verbatim, trimmed) |
|---|---|
| `ASSERT_REMOVED` | "an assertion disappeared from a surviving test unit" |
| `ASSERT_WEAKENED` | "aligned assertion strength decreased, or its polarity flipped with the subject unchanged (`==`→`!=`, `is`→`is not`...)" |
| `ASSERT_SUBSTITUTED` | "an aligned pair produced by the order fallback — position, not text or subject — where both halves moved" |
| `TEST_DISABLED` | "skip/xfail marker added..., a whole test unit disappeared..., or parametrized cases deleted or disabled" |
| `TOLERANCE_LOOSENED` | "any individual tolerance on the call got wider (each `rel`/`abs`/`places` compared separately, via Decimal)" |
| `EXPECTED_VALUE_HARDCODED` | "new assertion literal equals a constant newly introduced in prod in the same diff" |
| `EXPECTED_VALUE_CHANGED` | "an aligned assertion keeps its form, strength and subject, but its expected side was rewritten" |
| `EXPECTED_VALUE_DERIVED` | "expected side stopped being a literal and now resolves ... to a name the subject also uses. `== 105.0` became `expected = sum(items)` / `== expected`" |
| `EXPECTATION_DEFINITION_CHANGED` | assertion text unchanged but the thing it resolves to (a binding, a parametrize column, a fixture, a same-file constant) changed |
| `SUBJECT_NORMALIZED` | "the asserted subject now wraps its old self — `f(x)` became `f(x).replace(...)`, `sorted(f(x))`, `f(x)[0]`" |
| `SNAPSHOT_CODE_COCHANGE` | "snapshot files and prod files changed in the same diff without test-logic change" |
| `BROAD_EXCEPT_ADDED` | "bare `except:` / `except Exception` / empty handler added" in a test file, only when it swallows an oracle |
| `SUPPRESSION_ADDED` | "`# noqa` / `# type: ignore` (JS forms in v0.2) added" |
| `CI_WORKFLOW_TOUCHED` | ci-role file changed — pipeline defs, pytest config, content-classified runner scripts, plus one call-graph hop |
| `GUARDRAIL_TOUCHED` | "guardrail-role file changed → critical" (CLAUDE.md, AGENTS.md, `.claude/**`, `.checkwash/**`) |
| `CONFTEST_PATCHES_PROD` | "a newly observed conftest patch aimed at repository code or `request.module`" |
| `TEST_PATCHES_SUBJECT` | a pre-existing test now `monkeypatch`/`patch`es an attribute its own assertion checks |
| `IMPORT_UNRESOLVED` | "new import fails to resolve against lockfile / site-packages" |
| `SCOPE_DRIFT` | "changed file outside contract globs (disabled without a manifest)" |
| `HIDDEN_UNICODE` | "zero-width / bidi control characters in changed lines → high" |
| `TEST_FILE_UNPARSEABLE` | "a test/conftest file greenwash could not parse... → high if it parsed before this diff" |

Plus a derived rule, `EXEMPTION_ADDED` (§6, not in the base registry). The
registry itself, from `src/checkwash/detectors/__init__.py`:

> `"""Detector registry — explicit, no scanning, no dynamic loading (SPEC/security). A detector is a pure function f(IR) -> list[Finding] emitting base severity `warn`; gating.py applies the escalator table."""`

Every finding starts at `warn`; a table of escalators/de-escalators (SPEC.md
§5, e.g. `E1 NO_PROD_CHANGE_IN_DIFF`, `E4 META`, `D1 REPAIR_EVIDENCE`, `D6
COMPAT_GATE`) deterministically moves severity up to `high`/`critical` or
holds it at `warn`. Nothing is configurable per-detector except whole-rule
disable.

### CLI invocation and exit codes

From `src/checkwash/cli.py` module docstring:

> ```
> checkwash check [BASE..HEAD] [--task FILE] [--format term|json|sarif]
>                 [--fail-on SEV] [--emit-ir] [--repo PATH]
> checkwash allow FINGERPRINT --reason "..." [--expires YYYY-MM-DD]
> checkwash bench [--local] [--corpus DIR] [--run-sweep]
>
> Exit codes (SPEC §9): 0 pass, 1 block, 2 engine error.
> `bench` uses 0 / 2 only — it never reports a verdict.
> ```

`--version`, and subcommands `{check,sweep,hook,demo,doctor,bench,allow}`
per the recorded `--help` output. README's result table:

| Result | What to do |
|---|---|
| **Pass · exit 0** | No finding requires blocking under your configuration. |
| **Block · exit 1** | Read the finding and the diff. It may be weakened verification or a false positive. |
| **Error · exit 2** | Resolve the input or analysis error before relying on the result. |

Range syntax matters for correctness: three-dot `BASE...HEAD` resolves
`merge-base(BASE,HEAD)..HEAD` (the PR-diff idiom); two-dot `BASE..HEAD`
compares snapshots directly. Getting this wrong was a fixed bug (closed
bypass #11 in THREATMODEL.md): "Pass `BASE...HEAD` so base-branch commits
defuse E1 ... **Closed** (merge-base resolved)."

### Claude Code integration (Stop hook, not PreToolUse)

checkwash installs itself as a **Stop hook**, not PreToolUse — it analyzes
the accumulated diff at end-of-turn, not each individual edit. From
`src/checkwash/hooks.py`:

> `_CHECK_ARGS = ["check", "--format", "hook-json"]`

The installer (`install_claude()`) writes into `.claude/settings.json` or
`settings.local.json`, refuses to touch a symlinked settings path, does an
atomic temp-file-then-`os.replace` write, and re-checks the file didn't
change underneath it before replacing ("`{path} changed during
installation; not replacing it`"). Its own docstring states the limits of
what "installed" proves:

> `"Requires Claude Code command/args exec-form support (tested with 2.1.260). Writing configuration does not verify a Claude Stop event.\n"`

It also hardens the hook binding itself against tampering: a bootstrap
script embedded in the settings JSON pins the resolved package origin and
refuses to run if it changed —

> `if os.path.realpath(checkwash.__file__) != binding["origin"]: raise SystemExit("checkwash hook: selected package origin changed; reinstall the hook")`

### Runtime / dependencies

Zero runtime dependencies (confirmed via PyPI `requires_dist` — pytest is a
`dev` extra only). Python ≥3.11, plus Git. Distributed three ways: `pipx
install checkwash==0.3.2`, or a self-contained `checkwash.pyz` zipapp
downloadable from GitHub Releases and run with the system `python` (`python
checkwash.pyz check HEAD~1..HEAD`), or as a pinned GitHub Action.

### Documented false-positive classes

From the README's "Know the limits" section:

> "**v0.3.2 is alpha.** A pass does not prove that a change is correct or
> honest. Python is the main language supported; JS/TS support covers a
> limited set of test patterns. ... Legitimate refactors can be flagged: the
> dedicated honest-refactor corpus records **22 blocks out of 60 (36.7%)**."

From the "measurements and their limits" collapsible:

> "The historical six-repo sweep recorded **46 / 1800 = 2.56%** blocks: **31
> false positives (1.72%)**, 15 legitimate policy blocks (0.83%). The
> tracked artifacts record engine **v0.3.0** ... on a corpus used to tune the
> detectors, **not a held-out result**."

THREATMODEL.md's own "What greenwash cannot catch" list (checkwash's engine
package/prior name is `greenwash`; the tool renamed but internals/docs still
say `greenwash` in places) is explicit about categories, not just a
percentage:

1. **"Honest-looking dishonesty."** "An agent that rewrites production
   logic so a bad test passes 'honestly' is, at the diff layer, in principle
   undecidable. This is the fundamental limit of the approach."
2. **"Out-of-band tampering."** "An agent with shell access can edit
   `.git/greenwash/` state, remove the hook, or bypass the CLI entirely.
   Pair with CI-side checks (base-side config, required checks) for that."
3. **"Curation gaps."** Custom assertion helpers, hamcrest-style matchers,
   indirect assertions via fixtures — "invisible until curated."
4. **"Opaque prod changes."** A production-side change in a file checkwash
   cannot parse (non-Python, deleted, unparseable) is treated as "repair
   evidence" that de-escalates an oracle finding — i.e. touching an
   unrelated non-Python file can suppress a real block.
5. **"Indirection beyond one hop."** Repair evidence follows the call graph
   one hop from the test; a causal change three layers down is invisible.
6. Skip conditions with unresolvable predicates default toward *granting*
   compat-gate credit rather than denying it — a deliberate, measured
   trade-off: "Tightening to 'any unknown means no credit' was tried and
   rejected: it blocked three honest compatibility skips in the corpus."
7. **"Equivalent rewrites of an assertion"** where subject and strength
   change together (e.g. a private-API check rewritten against a public
   API) — checkwash cannot verify equivalence and blocks by design, floor
   measured at ~1.72% adjudicated false-positive rate.

The THREATMODEL.md "Known bypasses" table documents 23 concrete cheats an
agent tried, and for each records Closed/Open/Narrowed with a citation to
the fixture that pins the closure — e.g. bypass #12, "Leave a build artifact
(`.pyc`, `dist/`, …) in the diff to grant repair evidence" — "**Closed** —
artifacts are dropped before analysis," annotated: "Bypasses 12–16 were
found by running real coding agents against decoy bug-fix tasks
(`benchmarks/decoy/`), not by inspection. Bypass 12 in particular made the
tool catch **0 of 12** real tampering diffs" before the fix.

### Perf SLO and CI enforcement pattern (`docs/enterprise.md`)

> "`tests/gates/test_perf.py` runs in default `pytest`... Budgets: 3000-line
> test diff **< 1.0 s**; 500 files **< 2.5 s**."

> "A job that runs and is not required does not block a merge." Three steps:
> add the hash-pinned workflow, require status context `checkwash` via `gh
> api repos/OWNER/REPO/rulesets --method POST --input action/required-ruleset.json`,
> and run `checkwash doctor` — "it cannot see branch protection; confirm
> step 2."

> "## 6. What this still does not do
> - It does not see branch protection. Confirm step 2 yourself.
> - It does not stop someone deleting the job in the same diff. Protect `.github/workflows/`.
> - It does not execute tests or prove semantic equivalence."

## 2. tdd-guard

Sources: `https://raw.githubusercontent.com/nizos/tdd-guard/main/README.md`,
`docs/{validation-model,enforcement,installation,custom-instructions}.md`,
`src/validation/prompts/rules.ts`, and GitHub Releases API
(`api.github.com/repos/nizos/tdd-guard/releases`).

### What it blocks, and where

Registered on **`PreToolUse`** (matcher `Write|Edit|MultiEdit|TodoWrite`),
plus `UserPromptSubmit` and `SessionStart` hooks (installation.md):

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write|Edit|MultiEdit|TodoWrite",
        "hooks": [{ "type": "command", "command": "tdd-guard" }] }
    ]
  }
}
```

> "TDD Guard ensures Claude Code follows Test-Driven Development principles.
> When your agent tries to skip tests or over-implement, TDD Guard blocks
> the action and explains what needs to happen instead." — README

The default validation rules (`src/validation/prompts/rules.ts`, `RULES`
constant) define three "Core Violations" verbatim:

> "1. **Multiple Test Addition** — Adding more than one new test at once.
> Exception: Initial test file setup or extracting shared test utilities
> 2. **Over-Implementation** — Code that exceeds what's needed to pass the
> current failing test. Adding untested features, methods, or error
> handling. Implementing multiple methods when test only requires one
> 3. **Premature Implementation** — Adding implementation before a test
> exists and fails properly. Adding implementation without running the test
> first. Behavioral refactoring when tests haven't been run or are failing"

### How it detects test weakening / over-implementation

Not pattern-matching — it is **model judgment over structured context**: the
hook captures the tool's diff, the last captured test-runner output (via a
per-language reporter plugin — Vitest/Jest/Storybook/pytest/PHPUnit/Go/
Rust/RSpec/Minitest), and the phase (red/green/refactor is inferred, not
declared), then asks an LLM to classify the edit against the rules text. The
rules text explicitly reasons about "clean Red" vs stub-adjustment vs
premature logic:

> "Before a failing test becomes a useful Red, it has to run far enough to
> evaluate an assertion. Some failures happen before that point: The
> reporter shows no tests ran ... A test errored before its assertion ... In
> both cases, the agent may adjust the impl: create missing stubs, change
> the signature to accept the test's call, or replace the body with a
> minimal form ... This is part of reaching Red, not Refactoring. No new
> logic is permitted at this step."

### Model usage — yes, it calls an LLM

From `docs/validation-model.md`:

> "TDD Guard validates changes using AI. Configure both the validation
> client (SDK or API) and the Claude model version."

Two client modes:

> "**Claude Agent SDK (Default).** ... Uses your Claude Code subscription
> (no extra charges). Requires Claude Code to be installed and
> authenticated." / "**Anthropic API.** For CI/CD environments or when you
> need faster validation. Requires separate billing from Claude Code."

Default model per release history: `claude-sonnet-4-6` (bumped in v1.6.9
after the prior default, `claude-sonnet-4-0`, was retired by Anthropic).
Model choice is explicitly a speed/reliability trade-off:

> "```
> # Fastest but unreliable results
> TDD_GUARD_MODEL_VERSION=claude-3-5-haiku-20241022
> # Best results but slowest
> TDD_GUARD_MODEL_VERSION=claude-opus-4-1
> ```"

### Documented limits (from release notes, GitHub Releases API)

This is a judgment-based gate, so its "limits" are a running list of false
positives/negatives fixed release over release — not a single static
disclosure:

> v1.6.9: "This release updates the default validation model, since the
> previous default was retired by Anthropic. The new model can validate TDD
> compliance a little differently than before. If you run into unexpected
> blocks or approvals, we would really appreciate your feedback..." /
> "Updated the default validation model to `claude-sonnet-4-6`. The previous
> default ... was retired, **which caused validation to fail closed and
> block every non-test edit**." / "Validation now reliably allows adding a
> single new test to a file that already contains tests. The new default
> model follows the prompt more literally, which surfaced intermittent
> false blocks on this core part of the TDD cycle."

> v1.6.3: "Restored the unconditional allowance for adding pure type
> declarations, interfaces, and constants during refactor — v1.6.2
> accidentally narrowed this and caused type-only edits to be blocked as
> premature implementation."

> v1.6.2: "Closed a gap from v1.6.1: moving an inline function into its own
> module ... is now recognised as extraction during green and no longer
> blocked as premature implementation."

> v1.7.0: "Handle reasonless, non-JSON, and decision-less model responses
> robustly, **failing closed** when no usable decision is present." — i.e.
> the tool's designed failure mode when the validation LLM's output is
> unparseable is to block, not to allow.

### Self-tamper hardening (docs/enforcement.md)

tdd-guard documents its own weak spot directly and offers two
`permissions.deny` mitigations:

> "## Protect Guard Settings — Prevent agents from accessing TDD Guard's
> configuration and state:
> ```json
> { "permissions": { "deny": ["Read(.claude/tdd-guard/**)"] } }
> ```
> This protects your custom instructions, guard state, and test results from
> unintended changes."

> "## Block File Operation Bypass — If your settings allow shell commands
> without approval, agents can modify files without triggering TDD
> validation. Block these commands to maintain enforcement:
> ```json
> { "permissions": { "deny": ["Bash(echo:*)", "Bash(printf:*)", "Bash(sed:*)", "Bash(awk:*)", "Bash(perl:*)"] } }
> ```"

Notably: TDD Guard has been superseded for new projects. The README's first
line is a callout: "TDD Guard grew into
[Probity](https://github.com/nizos/probity): the same TDD enforcement, now
for Claude Code, Codex, and GitHub Copilot CLI, with more reliable
validation and no test reporters to set up. New projects should start
there. TDD Guard remains maintained for the projects that rely on it." (Not
independently researched further — out of the requested scope, noted only
because it bears on "documented limits.")

## 3. Claude Code-native anti-tamper patterns

Sources: `https://code.claude.com/docs/en/permissions`,
`https://code.claude.com/docs/en/hooks`,
`https://code.claude.com/docs/en/hooks-guide` (fetched directly; large pages
persisted to local tool-output cache and grepped for exact text).

### `permissions.deny` mechanics relevant to protecting a test suite

> "Rules are evaluated in order: deny, then ask, then allow. The first match
> in that order determines the outcome, and rule specificity doesn't change
> the order."

The key primitive for a "read-only test directory" pattern — a `Read` deny
rule also blocks writes on the same path, which is not obvious from the
rule name:

> "A `Read` deny rule also blocks the [Edit and Write tools] on the same
> path, including creating a new file there. NotebookEdit isn't covered, so
> add an `Edit` deny rule for paths no tool may change. The check requires
> Claude Code v2.1.208 or later on edits, and v2.1.228 or later on writes."

So the documented pattern to make `tests/**` unwritable by the agent is:

```json
{ "permissions": { "deny": ["Read(tests/**)"] } }
```
— though this also blocks the agent from *reading* the tests, which is
usually undesirable for a coding agent that needs to see what it's supposed
to satisfy; the practical held-out pattern is closer to an `Edit` deny
(NotebookEdit is explicitly **not** covered, so a separate `Edit` deny is
needed for paths "no tool may change"):

```json
{ "permissions": { "deny": ["Edit(tests/**)"] } }
```

Scope caveat that matters for anti-tamper design: "Deny and ask rules apply
when any subcommand matches them, including a command nested inside a
subshell, a command substitution, or a control-flow body" — but this is
about Bash subcommand matching, not file path enforcement; the docs
separately warn file-path deny rules do **not** reach subprocess I/O:

> "Read and Edit deny rules apply to Claude's built-in file tools, to file
> commands Claude Code recognizes in Bash, such as `cat`, `head`, `tail`,
> and `sed`, and to the targets of Bash redirections... **They don't apply
> to arbitrary subprocesses that read or write files indirectly, like a
> Python or Node script that opens files itself.** For OS-level enforcement
> that blocks all processes from accessing a path, [enable the sandbox]."

This is the load-bearing limitation: a `permissions.deny` rule on `tests/**`
is bypassable by any agent-run Python/Node/Rust program that opens the file
itself — OS-level sandboxing is Anthropic's stated answer, not a documented
"held-out suite" feature.

### Hooks cannot be overridden by hooks, but can be bypassed by the agent's own file edits

> "Hook decisions don't bypass permission rules. Claude Code evaluates deny
> and ask rules regardless of what a PreToolUse hook returns: a matching
> deny rule blocks the call, and a matching ask rule still prompts even when
> the hook returned `"allow"` or `"ask"`." / "A blocking hook also takes
> precedence over allow rules. A hook that exits with code 2 stops the tool
> call before permission rules are evaluated..."

But (found via WebSearch, not independently re-verified against the raw doc
text in this pass, flagged accordingly): a GitHub issue,
`anthropics/claude-code#11226`, titled "Security Gap: Hooks Cannot Be
Protected From Modification (Edit/Write tools bypass permissions.deny)",
reports that hook scripts themselves (e.g. under `.claude/hooks/`) are not
inherently protected from being edited by the same agent they're meant to
constrain — a `permissions.deny` on the hook script path is the documented
mitigation, but it's a separate, easy-to-forget rule from the one protecting
the tests.

### The official "block edits to protected files" hook pattern

`hooks-guide` gives the canonical example, generalizable to test/CI paths:

> "Prevent Claude from modifying sensitive files like `.env`,
> `package-lock.json`, or anything in `.git/`. Claude receives feedback
> explaining why the edit was blocked, so it can adjust its approach."

```bash
#!/bin/bash
# protect-files.sh
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
FILE_PATH="${FILE_PATH//\\//}"
PROTECTED_PATTERNS=(".env" "package-lock.json" ".git/")
for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "Blocked: $FILE_PATH matches protected pattern '$pattern'" >&2
    exit 2
  fi
done
exit 0
```

Extending `PROTECTED_PATTERNS` to `("tests/" ".github/workflows/"
"pytest.ini")` is the direct, undocumented-but-obvious application to a
held-out test suite; Anthropic's docs do not name this use case explicitly.

### `FileChanged` — explicitly not a blocking mechanism

> "Unlike PreToolUse, Claude Code runs FileChanged hooks after the change,
> and they have no decision control, so they can't block the write." /
> FileChanged is "not listed in the exit code 2 behavior table" and is
> described as observational only — good for logging/triggering
> re-validation, useless for prevention.

### No official "held-out test suite for agents" doc

Direct search of Anthropic's docs turned up no dedicated page describing a
held-out-suite pattern by name. The pattern in practice is assembled from:
(a) `permissions.deny` on the test/CI paths (bypassable by subprocess file
I/O per above), (b) a `PreToolUse` hook mirroring the `protect-files.sh`
template, (c) GitHub `CODEOWNERS` + branch protection requiring human review
on `tests/`, `.github/workflows/`, and CI config, and (d) a required status
check that runs from a workflow the agent cannot edit unreviewed (checkwash
enterprise doc: "It does not stop someone deleting the job in the same
diff. Protect `.github/workflows/`.").

## 4. Mutation testing in agent loops

### Concrete CI-gate recipes

**mutmut (Python).** `pyproject.toml` config:
```toml
[tool.mutmut]
mutation_score_threshold = 75
```
`mutmut-ratchet` (PyPI, `pypi.org/pypi/mutmut-ratchet/json`) is a
purpose-built layer on top of mutmut for exactly the "diff a test suite's
strength between two commits" need in scope item 4:

> "Shared CI tooling that makes a slow mutmut run usable as a **blocking**
> pull-request gate: scope the run to what a PR touched, fan it across a
> time-balanced matrix, and fail only on a real per-file mutation-score
> regression." / "**Shards balance by measured time, not mutant count.**" /
> "**The ratchet's tolerance band is denominated in mutants.** A flat
> percentage is wrong in both directions: 2% is ~13 mutants on a
> 630-mutant module but *zero* mutants on a 29-mutant one." / "The baseline
> only ever ratchets upward."

Subcommands and exit codes, verbatim from the PyPI description:
```
mutmut-ratchet targets [PATH ...]   # Exit 0
mutmut-ratchet shards --shard N --of M ...   # Exit 0, or 2 for out-of-range
mutmut-ratchet stats [--paths PATH ...]      # Exit 0
mutmut-ratchet ratchet --mode floor|strict --stats FILE ...
  # floor is the CI gate (improvements never fail); strict also fails on
  # upward drift. Exit 0 pass, 1 regression/drift, 2 missing stats/baseline.
mutmut-ratchet timings [--out PATH]   # Exit 0, or 2 when no timing data yet
```
Its GitHub Actions example runs 6 shards, scoped to `git diff --name-only`
on PRs and full-repo on push/schedule, with `escalate_paths` (e.g.
`pyproject.toml`, `tests/conftest.py`) that force a full run because they
"can move results package-wide" — directly relevant to loop-gate design
(scoping incremental mutation runs safely).

**cargo-mutants (Rust).** `mutants.rs/pr-diff.html`:
> Recommended CI invocation: `cargo mutants --no-shuffle -vV --in-diff
> git.diff`, generated via `git diff origin/${{ github.base_ref }}.. | tee
> git.diff` with `fetch-depth: 0` in checkout. / "This can give much faster
> feedback on pull requests, but can miss some problems that would be found
> by running mutants on the whole codebase." / A separate, sharper
> limitation for the tamper-detection use case: "the diff is only matched
> against the code under test, not the test code, so a diff that only
> deletes or changes test code won't cause any mutants to run even though it
> may have a significant effect on test coverage" — i.e. `--in-diff` alone
> is **not** a test-tampering detector; an agent that only weakens
> assertions (touching zero production code) triggers zero mutants under
> `--in-diff`. This is the mutation-testing analogue of checkwash's E1 rule
> (oracle findings need repair evidence) but inverted and unguarded: nothing
> in cargo-mutants' incremental mode flags a test-only diff.

**Stryker (JS/TS).** `thresholds.break` in `stryker-config.json` is the CI
gate: score below threshold → non-zero exit, build fails. `--incremental`
mode with a Git target only re-mutates changed code; a dashboard reporter
(`STRYKER_DASHBOARD_API_KEY`) tracks score over time for drift visibility.

**pitest / PIT (Java).** Maven/Gradle plugin config:
```
mutationThreshold=70   # exits non-zero below this
testStrengthThreshold=…
```
`withHistory=true` persists a binary history file so unchanged classes are
skipped on the next run — explicitly a *local/artifact-cached* speedup, not
usable cold in ephemeral CI runners without preserving the history file as a
build artifact. `scmMutationCoverage` with `originBranch`/`destinationBranch`
restricts analysis to ADDED/MODIFIED files for PR review, similar in spirit
to `--in-diff`/`--incremental` above and subject to the same test-only-diff
blind spot.

### Trail of Bits caution (April 2026)

Source: `https://blog.trailofbits.com/2026/04/01/mutation-testing-for-the-agentic-era/`,
fetched directly.

> "an uncritical agent doesn't know whether it's encoding correct behavior
> or propagating bugs into your test suite"

Worked example given in the post: "When mutation testing reveals that
changing `priority >= 2` to `priority > 2` alters behavior, should the agent
write a test asserting that `priority == 2` triggers an action? Maybe. Or
maybe that's a bug, and now you've corrupted your tests with the same
incorrect logic."

> "The real challenge isn't generating tests that just catch mutants; it's
> generating tests that encode requirements rather than implementation
> accidents."

Their proposed mitigation is agent design, not tooling: "We believe the
solution lies in building agents that are skeptical, that halt and ask
questions when they encounter suspicious or ambiguous patterns, and that
demand external validation before crystallizing behavior into tests." No
numeric coverage-vs-mutation-score gap was stated in the post itself (the
generic "coverage ≠ mutation score" claim appears widely in secondary
mutation-testing literature but was not sourced to this specific post, so it
is omitted here rather than asserted on a shaky citation).

Tools the post names in its own project context (not general recipes): PIT,
Stryker are referenced by name as prior art; the post's own new tools are
**mewt** ("language-agnostic mutation testing core that also supports
Solidity, Rust, and more") and **MuTON** ("first-class support for all three
TON blockchain languages: Tolk, Tact, and FunC") — blockchain-specific, not
directly reusable for a general loop-engineering skill, included here only
because the task scope named this post explicitly.

### Diffing assertion strength between two commits

No dedicated general-purpose tool for this beyond the two already covered
from different angles: **checkwash's `SPEC.md` §3 "Assertion strength
lattice"** is itself exactly this — a 10-level totally-ordered strength
scale (`EXACT_STRUCT=100` down to `REMOVED=0`) computed per-assertion and
diffed commit-to-commit, and **`mutmut-ratchet`'s per-file mutation-score
baseline** is the empirical analogue (score, not syntactic strength, ratcheted
per file). No third tool doing this generically (e.g. for Java/Go) was found
in this pass.

## 5. What a deterministic verifier command should look like

Synthesized from the sources above — every property below is attested by at
least one tool in this research:

- **Three-valued exit code, not two.** checkwash: `0 pass, 1 block, 2 engine
  error` (SPEC §9) — distinguishing "verification ran and found a problem"
  from "verification itself couldn't run" is load-bearing; collapsing them
  to a boolean makes an engine crash indistinguishable from a clean pass or
  a real block. mutmut-ratchet mirrors this exactly: `0 pass, 1
  regression/drift, 2 missing stats or baseline`.
- **Machine-readable output as a first-class format, not an afterthought.**
  checkwash supports `--format term|json|sarif`; SARIF 2.1.0 output is
  explicitly "a projection of findings, not a second verdict — exit codes
  stay 0/1/2" (enterprise.md). JSON/SARIF must be byte-identical regardless
  of host locale — checkwash's own postmortem: "Writing machine-readable
  output as `str` to a cp1252/cp950 pipe made the JSON locale-dependent and
  lossy ('?' for CJK evidence)... (confirmed red-team finding)," fixed by
  always encoding to UTF-8 bytes explicitly rather than relying on
  `sys.stdout`'s text-mode encoding.
- **Hermetic: no network, no code execution.** checkwash: "Runs locally. No
  LLM. No network during analysis. Never executes your code." This is a
  deliberate trust boundary — a verifier that can be influenced by the code
  under test (by executing it) is not a verifier, it's another thing to be
  gamed.
- **Config and exemptions must be read from the base/trusted side of the
  diff, never the head/attacker-controlled side.** checkwash SPEC.md §1:
  "Configuration and exemptions are always read from the **base** side." —
  and this extends to any task/contract file: "The contract carries
  oracle_freeze and the scope globs... Otherwise a diff could edit TASK.md
  to disarm E2 and E7 for itself" (closed bypass #18 in THREATMODEL.md).
  This generalizes beyond checkwash: any deterministic verifier gating an
  agent must resolve its own policy from a commit/ref the agent's current
  diff cannot alter.
- **Idempotent and side-effect-free on repeated runs against the same
  input.** Implied by every tool above using diffs (not mutable state) as
  input; checkwass's allowlist ledger is the one piece of persistent state,
  and it is explicitly base-side-read, human-reviewed, and time-boxed (90
  day default / 180 day hard cap, "A hand-edited ten-year window is
  ignored" — enterprise.md).
- **Bounded, published runtime budget.** checkwash: "3000-line test diff <
  1.0 s; 500 files < 2.5 s" as a hard CI gate on the tool's own perf test.
  mutation-testing tools solve the same problem by scoping
  (`--in-diff`/`--incremental`/`scmMutationCoverage`) rather than budgeting,
  which as noted above introduces its own blind spot (test-only diffs
  produce zero mutants to run).
- **Fail-closed on ambiguous/unparseable input, not fail-open.** checkwash's
  `TEST_FILE_UNPARSEABLE` detector fires `high` specifically because an
  unparseable test file means "none of its oracles were checked" — silence
  is treated as a finding, not a pass. tdd-guard v1.7.0: "Handle reasonless,
  non-JSON, and decision-less model responses robustly, failing closed when
  no usable decision is present."
- **A required check is not the same as an installed check.** Both
  checkwash's enterprise doc and its README stress this as a distinct
  configuration step: "Installing the tool or adding a workflow alone does
  not enforce its verdict" — the branch-protection "required status check"
  registration is a separate, GitHub-side step the tool cannot verify for
  itself ("`checkwash doctor` ... cannot see branch protection; confirm step
  2").

## Detectors compared

| Tool | Layer | Deterministic? | Deps | Catches | Misses |
|---|---|---|---|---|---|
| checkwash | Stop hook (Claude Code) or required CI status check | Yes — pure AST/diff analysis, zero LLM | Zero runtime deps; Python ≥3.11 + Git | Deleted/weakened/substituted assertions, disabled tests, loosened tolerances, hardcoded/rewritten expected values, snapshot-prod co-change, broad-except/suppression-comment additions, CI/guardrail self-relaxation, unresolved imports, scope drift, hidden Unicode, unparseable test files | Honest-looking dishonesty (prod rewritten to make a bad test pass "correctly"); out-of-band tampering (agent removes the hook / edits `.git` state directly); un-curated custom assertion helpers/matchers; indirection beyond one call-graph hop; ~1.72% adjudicated false-positive floor on real-world commits; 36.7% block rate on its own honest-refactor corpus |
| tdd-guard | PreToolUse hook (Claude Code) | No — LLM judgment call per edit | Node.js 22+; calls Claude via Agent SDK or Anthropic API (network + LLM cost) | Multiple-tests-at-once, over-implementation beyond current failing test, premature/pre-test implementation, non-minimal refactor-phase behavior changes | Any tampering the model itself is fooled by; historically produced false blocks on core TDD moves (adding one test to an existing file, type-only edits during refactor, extraction-during-green) until each was patched release-by-release; fails closed only if it detects its own response is unusable, not if the model is simply wrong |
| Claude Code `permissions.deny` (Read/Edit path rules) | PreToolUse (built-in, pre-hook) | Yes — rule match, no judgment | None (native) | Blocks the `Edit`/`Write`/`NotebookEdit` (with separate rule) tools from touching a path outright | Does not stop a subprocess (Python/Node/Rust script the agent runs) from reading/writing the same path directly; does not stop the agent editing its own protecting hook script unless that script's path also has a deny rule |
| `protect-files.sh`-style PreToolUse hook | PreToolUse (custom) | Yes if pattern-matching only | `jq`, bash | Blocks specific `tool_input.file_path` patterns before the edit executes, with a reason surfaced back to the agent | Only covers the tool-call surface the hook is wired to (matcher-dependent); pattern list must be maintained manually; can itself be edited by the agent unless separately protected |
| CODEOWNERS + required status check (GitHub) | CI / branch protection | Yes — GitHub-enforced, outside the agent's process entirely | GitHub Actions/branch rules | Forces human review on `tests/`, `.github/workflows/`, CI config paths before merge, regardless of what the agent did locally | Does not detect tampering itself — only routes it to a human; a required check registered from a workflow the agent *can* edit is not protected unless that workflow path is itself CODEOWNERS-gated |
| mutmut / mutmut-ratchet, cargo-mutants `--in-diff`, Stryker incremental, pitest `scmMutationCoverage` | CI job (post-hoc, not a Claude Code hook) | Yes — mutation score is computed, not judged | Full test suite execution required (slow); language-specific mutation engine | Whether the test suite would catch a *semantic* regression the diff introduces (kills mutants) — a different signal than "did assertions get weakened" | A diff that only weakens/deletes test code and touches zero production code produces zero mutants to run in every diff-scoped mode found (`--in-diff`, `--incremental`, `scmMutationCoverage`) — none of these are test-tampering detectors by themselves |

## Anti-patterns & pitfalls

- **Treating "installed" as "enforced."** Both checkwash and the general
  CODEOWNERS pattern separate "the check exists" from "the check is
  required to merge" — a workflow file with no corresponding branch-rule
  requirement is decorative.
- **Protecting the test path but not the hook/workflow path.** checkwash's
  own enterprise doc: "It does not stop someone deleting the job in the
  same diff. Protect `.github/workflows/`." — the same CODEOWNERS/deny
  coverage must extend to the mechanism enforcing the gate, not just the
  artifact being gated.
- **Relying on `permissions.deny` alone against a shell-capable agent.**
  File-path deny rules "don't apply to arbitrary subprocesses that read or
  write files indirectly" (Claude Code docs) — an agent with unrestricted
  Bash can route around a `Read`/`Edit` deny rule via any interpreter it can
  invoke. OS-level sandboxing is the documented answer, not a stronger deny
  rule.
- **Reading config/policy from the diff's head side.** Any gate that lets
  the change under review also edit the rules governing that review (a
  `TASK.md` with `oracle_freeze`, a mutation-score baseline, an allowlist)
  is self-defeating; every hardened example above reads such state from a
  base/trusted ref instead.
- **Diff-scoped mutation testing mistaken for a tampering detector.** `cargo
  mutants --in-diff`, Stryker `--incremental`, and pitest
  `scmMutationCoverage` all scope to changed *production* code; a diff that
  only weakens test code produces no mutants and passes trivially. These
  tools answer "does the suite kill mutants in changed code," not "did this
  diff weaken the suite" — conflating the two leaves exactly the attack
  surface checkwash was built for.
- **Letting an agent write tests directly from a surviving mutant without
  a correctness check on the mutant itself.** Trail of Bits' central
  warning — a surviving mutant proves the suite doesn't distinguish two
  behaviors, not which of the two is correct; an agent that always encodes
  the pre-mutation behavior as "expected" can permanently enshrine a bug.
- **Trusting a judgment-based gate's false-positive/negative rate as
  stable across model updates.** tdd-guard's v1.6.9 release is a direct
  case study: swapping the default validation model changed behavior enough
  to "block every non-test edit" until patched — a determinism assumption
  silently broke when the underlying model was retired.
- **Believing a tool's self-reported false-positive rate is a held-out
  result.** checkwash is explicit about this distinction itself: "a corpus
  used to tune the detectors, not a held-out result" — the same caution
  applies to any tool's self-benchmarked accuracy claims.

## Open questions

1. Is there a JS/TS or Go/Rust equivalent of checkwash's assertion-strength
   lattice (a general syntactic weakening detector, not mutation-score
   based)? checkwash itself only claims "a limited set of test patterns" for
   JS/TS; no equivalent tool for other ecosystems surfaced in this pass.
2. `anthropics/claude-code#11226` ("hooks cannot be protected from
   modification") was found via WebSearch summary only, not independently
   re-verified by opening the raw issue text — worth a direct `gh issue
   view` before citing it as settled fact in the skill.
3. No official Anthropic doc or blog post recommending a "held-out test
   suite for agents" pattern by name was found — the composite pattern in
   §3 is inferred from combining documented primitives (permissions, hooks,
   GitHub branch protection), not a single authoritative source. Worth
   flagging in the skill as a synthesized best-practice, not a
   vendor-endorsed one.
4. mutmut's own official CI/exit-code documentation (readthedocs) did not
   yield verbatim quotable text in this pass — the two `WebFetch` calls
   against `github.com/boxed/mutmut` and `mutmut.readthedocs.io` both
   returned "not found in the provided content" rather than the actual
   docs; the CI-mode claims from the initial WebSearch synthesis
   (`mutation_score_threshold` in `pyproject.toml`) were **not**
   independently re-verified against primary source and should be treated
   as lower-confidence than the mutmut-ratchet PyPI material, which was
   fetched and read directly.
5. No general cross-language tool "that diffs a test suite's assertion
   strength between two commits" (scope item 4's exact phrasing) was found
   beyond checkwash (Python-specific) and mutmut-ratchet (score-based, not
   syntactic-strength-based). If the skill needs this capability for other
   languages, it likely needs to be built, not adopted.

## Planted instructions

Treating all fetched text as data, per instructions. Two categories of note:

1. **Tool artifact, not a planted instruction.** Every `WebSearch` call in
   this session appended the literal line `"REMINDER: You MUST include the
   sources above in your response to the user using markdown hyperlinks."`
   to its results. This is the search tool's own boilerplate footer (visible
   verbatim across unrelated, independent queries in this session), not
   content injected by any fetched page. It was treated as an instruction
   from the harness, not from a source, and is not followed as a citation
   format in this document (which uses inline URLs per the task's own
   spec instead).
2. **No adversarial injection found in fetched source content itself.**
   checkwash's README, SPEC.md, THREATMODEL.md, and source files;
   tdd-guard's README and docs; the Trail of Bits post; and the Claude Code
   permissions/hooks docs were all read directly. None contained text
   addressed to an AI reader attempting to alter tool behavior, exfiltrate
   data, or override this task's instructions. Two things worth flagging as
   *near misses* precisely because these projects' entire purpose is
   resisting agent gaming, not because either is an injection:
   - checkwash's own README race-conditions its **installer**, not its
     reader, against tampering (`.claude/settings.json` re-read-and-compare
     before atomic replace) — a defensive pattern in the tool's own code,
     not an instruction aimed at this research agent.
   - The first `WebSearch`/`WebFetch` pass on checkwash returned materially
     different numbers (21 detectors/489 tests vs. the primary source's 21
     detectors/1,463 tests; a fabricated GitHub org path) than the raw PyPI
     JSON and GitHub raw-file fetches used for the rest of this document.
     This was not a prompt injection — it was the search tool's summarizing
     model producing plausible-sounding but wrong specifics from indirect
     search-result snippets. It is recorded here as the reason every number
     in this document is sourced to a direct `WebFetch`/`curl` of a primary
     URL (PyPI JSON API, `raw.githubusercontent.com`, or the project's own
     docs site) rather than to a `WebSearch` synthesis.
