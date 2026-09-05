# Code design — lesson provenance, recurrence, budget and deny rung

Not a spec. Pins names, locations and grammars that cross slices; silent about everything inside one slice. Sections 1–7 (Medium). Post-merge smells: `${CLAUDE_PLUGIN_ROOT}/skills/flow-deepen/references/detection-heuristics.md`.

## 1. Contract files + ubiquitous language

Bash has no importable types; the contract is **golden files** every slice's tests read and never edit: `plugins/flow/scripts/tests/fixtures/lesson/{PROGRESS.md, lesson-fires.log, stats.expected.tsv, stats.expected.json}`. A slice whose output disagrees with a golden file is wrong; a golden file is changed only by the orchestrator.

| Canonical | identifier | plural | defined in | banned synonyms |
|---|---|---|---|---|
| ruling | `- Ruling: <what> — <mechanism> — <cost> (<YYYY-MM-DD>)` (legacy: no trailing date) | rulings | PROGRESS.md `## Rulings` | lesson entry, record, note |
| what | the free text between `Ruling: ` and the first ` — `; single line; no tab | — | ruling | title, id, key, summary |
| marker | `lesson(<YYYY-MM-DD>): <what>` | markers | host file comment: bash `# …`, markdown `<!-- … -->`, hook reason `[…]` | tag, label, provenance id |
| fire | `<YYYY-MM-DD>\t<what>\t<UTC ISO-8601 Z>\t<hook basename>` | fires | `<project>/.claude/lesson-fires.log` | hit, event, count |
| caught | number of fires whose (date, what) equal a ruling's | — | lesson-stats | hits, triggers |
| escaped | number of LATER rulings with the same what | — | lesson-stats | recurrences, repeats |
| rung | first word of mechanism, lowercased (`hook`, `lint`, `test`, `deny`, `script`, `skill`, `claude.md`) | rungs | lesson-stats | level, layer, tier |
| verdict | one of `unmeasured` `escaped` `held` `prune?` `young` `orphan`, first match wins in that order | — | lesson-stats | status, state |
| budget | 100 lines for a project CLAUDE.md, 40 for `$HOME/.claude/CLAUDE.md` | — | lesson-claude-md, lesson-sites | limit, cap |

Dates are `YYYY-MM-DD` only. Every script takes `--date` (writers) or `--now` (readers) so tests never depend on the clock. All scripts are sync, standalone, `set -u`, bash 3.2.

## 2. Trust boundaries

| Boundary | untrusted input shape | parse | failure granularity |
|---|---|---|---|
| hook reason string | arbitrary text | first `[lesson(D): W]` via `sed -n` with the digit-class date pattern; strip `\t` and newlines from W | no marker → no fire, nothing else changes |
| PROGRESS.md line | arbitrary line | `^- Ruling: ` prefix, split on ` — `; trailing ` (D)` optional | unparsable → skipped, one stderr count |
| fire log line | arbitrary line | exactly 4 tab fields, field 1 a date | malformed → skipped, one stderr count |
| CLAUDE.md line | arbitrary line | normalise: strip `<!-- … -->`, lowercase, drop `[^a-z0-9 ]`, collapse spaces | compare normalised |
| `--date` / `--now` | argv | `[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]` | else exit 2 |

Absent vs null: a missing date is `-` in TSV and `null` in JSON; a missing last-fire is the same. A ruling is identified by its (date, what) pair; nothing mints numbers.

## 3. Error taxonomy (exit codes; scripts return, hooks never change theirs)

`0` written/ok · `2` usage or bad argument · `3` duplicate or conflicting target (`--cut` line missing) · `4` cannot read/write · `5` at budget without `--cut`. Adding a code is a design change — escalate, do not add locally. Hooks: bookkeeping failure is swallowed; stdout, stderr wording and exit code stay byte-identical.

## 4. Module boundaries

- `plugins/flow/scripts/lesson-record` · standalone · may import: nothing · exports: CLI · seam: **ruling writer**
- `plugins/flow/scripts/lesson-stats` · standalone · reads PROGRESS.md + fire log · seam: **ruling reader**
- `plugins/flow/scripts/lesson-claude-md` · standalone · seam: **budgeted line writer**
- `plugins/flow/scripts/lesson-sites` · standalone · seam: **rung locator**
- `plugins/flow/hooks/lib/hookout.sh` · sourced by every hook · may import: nothing · may not call scripts · seam: **fire recorder**
- `plugins/flow/skills/lesson/SKILL.md` · references scripts only by full path: `${CLAUDE_PLUGIN_ROOT}/scripts/lesson-record`, `lesson-sites`, `lesson-stats`, `lesson-claude-md` · seam: **ladder**
- Tests: `plugins/flow/scripts/tests/test_lesson.sh` (slice 1), `test_lesson_stats.sh` (slice 3), `test_lesson_claude_md.sh` (slice 4), `test_lesson_ladder.sh` (slice 5; the existing `t_lesson_skill_frontmatter_and_references` in test_lesson.sh is never edited), `plugins/flow/hooks/tests/test_lesson_nudge.sh` (slice 2); helpers from each suite's `lib.sh` only.
Anything not listed is a bug. No `scripts/lib/`; no hook sources a script.

## 5. Shared resources & construction

| resource | constructed-by | passed-how | received-by |
|---|---|---|---|
| PROGRESS.md | lesson-record (creates from template; `mkdir PROGRESS.md.lock`) | path arg `--file`, default `./PROGRESS.md` | lesson-stats (read only, no lock) |
| `.claude/lesson-fires.log` | hookout.sh (`mkdir -p`, `>>` append, no lock) | `$(hook_project_dir)/.claude/lesson-fires.log` | lesson-stats via `--dir` (default git toplevel else `pwd -P`) |
| CLAUDE.md | lesson-claude-md (`mkdir <file>.lock`) | `--file` | nobody else writes |
| clock | `date -u +%Y-%m-%d` / `date -u +%Y-%m-%dT%H:%M:%SZ` | `--date` / `--now` override | every script; hookout uses the clock directly |
| settings.json | never written by this feature | path only | lesson-sites (existence + `"deny"` grep) |

Config keys: none. Nobody adds a dependency; `jq`/`python3` are guarded with `command -v` and never required.

## 6. Deliberately duplicated — do NOT consolidate

- The date pattern and the marker `sed` expression appear verbatim in hookout.sh and in each script. No shared bash library across hooks and scripts; copy the literal.
- The `mkdir` lock snippet is copied from lesson-record into lesson-claude-md, not extracted.
- Days-between-dates is an inline awk Julian-day function inside lesson-stats only (`date -d`/`-v` are banned).
- `usage()` heredocs and the `while [ $# -gt 0 ]` parser are copied per script, as every existing script does.

## 7. Decisions

1. In the context of provenance, facing "a ruling must be findable from the rung and the rung from the ruling" (spec FR-001/002), we chose the literal marker `lesson(D): W` joined by text and rejected a numeric ruling id, to achieve grep-ability by humans and hooks, accepting that editing a ruling's what orphans its fires. `Makes hard:` renaming a what — touches PROGRESS.md, the rung's comment, `.claude/lesson-fires.log`.
2. In the context of recurrence, facing "every deny/block/feedback already passes through one function" (`hookout.sh` `_lesson_nudge`), we chose to count there and rejected per-hook counters, to achieve zero per-hook edits, accepting that test, deny, script, skill and CLAUDE.md rungs are unmeasured. `Makes hard:` measuring a settings-deny — needs a client signal and a new source column; touches `plugins/flow/hooks/lib/hookout.sh` and `plugins/flow/scripts/lesson-stats`.
3. In the context of state, facing "counts must survive reboot for a 30-day window", we chose `<project>/.claude/lesson-fires.log` and rejected `$TMPDIR`, to achieve durability, accepting one more untracked file under `.claude/`. `Makes hard:` a shared machine-wide view — touches lesson-stats `--dir`.
4. In the context of the cross-slice grammar, facing "bash has no types", we chose golden fixture files and rejected a sourced `scripts/lib/lesson.sh`, to achieve one testable truth without a hooks↔scripts dependency, accepting duplicated regex literals (section 6). `Makes hard:` changing the ruling grammar — touches all four fixtures, lesson-record, lesson-stats, hookout.sh.
5. In the context of the ruling line, facing "legacy rulings must keep parsing", we chose a trailing ` (YYYY-MM-DD)` and rejected `- Ruling (D): …`, to keep the `- Ruling: ` prefix every grep uses, accepting that legacy rulings show as unmeasured. `Makes hard:` a second metadata field — touches lesson-record, lesson-stats, the fixtures.
6. In the context of noise, facing the maintainer's "never hammer the model", we chose to suppress the second-identical-block nudge for marker reasons and rejected a lesson-aware nudge, to achieve zero added turn-loop output, accepting that a re-fired lesson is only visible in lesson-stats. `Makes hard:` any proactive prompt — touches hookout.sh and the spec's non-goals.

---

## Contract for this slice — Slice 1
CONTRACT   plugins/flow/scripts/tests/fixtures/lesson/PROGRESS.md — the dated line grammar; read it, never edit it.
NAMES      ruling · what · marker `lesson(<YYYY-MM-DD>): <what>` · banned: lesson entry, id, tag
MODULE     plugins/flow/scripts/lesson-record · standalone · may import: nothing · exports: CLI · seam: ruling writer
CALLS      `lesson-record --what <what> --mechanism <mechanism> --cost <cost> [--file <PROGRESS.md>] [--date <YYYY-MM-DD>]` → stdout line 1 the ruling written, line 2 `marker: lesson(<YYYY-MM-DD>): <what>`; exit 0 · 2 (also for a malformed date) · 3 · 4 as today
DUPLICATE  keep the existing lock, template and awk insertion; copy nothing out
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for this slice — Slice 2
CONTRACT   plugins/flow/scripts/tests/fixtures/lesson/lesson-fires.log — the fire line grammar `<date>\t<what>\t<UTC Z>\t<hook basename>`.
NAMES      fire · marker in a reason is bracketed `[lesson(<YYYY-MM-DD>): <what>]`, first one counts · banned: hit, event
MODULE     plugins/flow/hooks/lib/hookout.sh · may import: nothing · may not call scripts · seam: fire recorder
CALLS      inside `_lesson_nudge`: when the reason contains a marker → append one fire to `$(hook_project_dir)/.claude/lesson-fires.log` (mkdir -p; failures swallowed), then `printf '%s' "$reason"` and return — no nudge text, no signature file write. Reasons without a marker: unchanged code path.
DUPLICATE  date pattern `[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]` written inline; strip tab and newline from what with `tr -d '\t\n'`
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for this slice — Slice 3
CONTRACT   plugins/flow/scripts/tests/fixtures/lesson/{PROGRESS.md, lesson-fires.log, stats.expected.tsv, stats.expected.json} — `lesson-stats --dir <fixture copy> --now 2026-10-15` must reproduce both expected files byte for byte (TSV: header row then one row per ruling in file order, orphans last; JSON: array, keys in the shown order, `null` for missing).
NAMES      caught · escaped · rung · verdict (`unmeasured` → `escaped` → `held` → `prune?` → `young`; `orphan` for unmatched fires) · banned: hits, recurrences, status
MODULE     plugins/flow/scripts/lesson-stats · standalone · seam: ruling reader
CALLS      `lesson-stats [--dir <project>] [--file <PROGRESS.md>] [--log <lesson-fires.log>] [--now <YYYY-MM-DD>] [--prune-days <days, default 30>] [--json]`; exit 0 · 2 (usage, bad date, no PROGRESS.md) ; malformed lines skipped with one stderr line `lesson-stats: skipped N malformed line(s)`
DUPLICATE  Julian-day awk function inline; ruling parser inline (split on ` — `, first field what, last field cost, trailing ` (D)` optional)
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for this slice — Slice 4
CONTRACT   marker in markdown is ` <!-- lesson(<YYYY-MM-DD>): <what> -->` appended to the same line; budget 100 (project) / 40 (`$HOME/.claude/CLAUDE.md`).
NAMES      budget · duplicate (normalised equal) · similar (≥ 50 % of the new line's words of 4+ letters appear in one existing line) · banned: limit, cap, match
MODULE     plugins/flow/scripts/lesson-claude-md · standalone · seam: budgeted line writer
CALLS      `lesson-claude-md --file <CLAUDE.md> --line "<text>" [--what <what> --date <YYYY-MM-DD>] [--cut "<exact existing line>"] [--budget <lines>]` → stdout: the line written, `lines: n/N`, zero or more `similar: <no>: <text>`; exit 0 · 2 · 3 (duplicate, or `--cut` target missing) · 4 · 5 (at budget without `--cut`)
DUPLICATE  copy the `mkdir` lock from lesson-record; normalisation inline (`sed` strip comment → `tr` lowercase → `tr -cd 'a-z0-9 \n'` → collapse spaces)
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.

## Contract for this slice — Slice 5
CONTRACT   lesson-sites line grammar `<rung> <status> <detail>` unchanged; new rung name is exactly `deny`, emitted between `test` and `hook`; JSON key `deny`; `present` only when `.claude/settings.json` exists and contains `"deny"`.
NAMES      rung order Test → Deny → Hook / lint → Script → Skill → CLAUDE.md · marker · lesson-stats · lesson-claude-md · banned: permission rung, settings rung
MODULE     plugins/flow/scripts/lesson-sites, plugins/flow/skills/lesson/SKILL.md, README + docs rows · seam: rung locator + ladder
CALLS      SKILL.md Step 4 names `${CLAUDE_PLUGIN_ROOT}/scripts/lesson-claude-md` for the CLAUDE.md rung; Step 6 names `${CLAUDE_PLUGIN_ROOT}/scripts/lesson-stats` as the later check and states that lesson-record prints the marker to write on the rung. No per-turn instruction anywhere.
DUPLICATE  none
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the contract — copy the literal declaration. (2) NEVER type a boundary function's parameter as the narrow type; the narrow type appears only as the RETURN of a fallible function. (3) NEVER add a mode, flag, boolean or extra required parameter to a shared abstraction the design handed you — duplicate it inside your slice and say so in your completion note; and before extracting anything, write the signature first, because a flag needed at birth disproves the extraction. (4) NEVER refactor, rename or restructure outside your slice — a change to an unlisted file is a defect. (5) NEVER abbreviate inside an identifier. Spell the word.
