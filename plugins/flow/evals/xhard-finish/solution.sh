#!/usr/bin/env bash
# What a perfect --finish run leaves on disk: finish armed, plan drafted then
# approved with the pre-approval suffix, two tasks committed and ticked through
# `flow tick`, the checkpoint evidenced and ticked --by user, gates green, PASS
# for HEAD, acceptance.md, Verified with the suffix, no PR (no remote) noted in
# NOTES.md, and finish mode switched off again.
set -euo pipefail
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
TODAY=$(date +%F)
SPEC=.specs/001-tally-summary
SUFFIX="(pre-approved: /flow:next --finish)"
BASE=$(git rev-parse --short HEAD)

$FLOW finish on --note "approve everything for this spec, including checkpoints and verification" >/dev/null

# ---- drafting
cat >"$SPEC/TASKS.md" <<MD
# Tasks — Category summary
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given expenses, when I run summary, then one row per category with count and total (AC-01) | T001 | test_summary_table |
| B2 (P0) | Given a tie, when I run summary, then sorted by total desc then name, TOTAL last (AC-02) | T001 | test_summary_sorts_ties_by_name |
| B3 (P0) | Given --month, when it is malformed, then stderr message, no stdout, exit 2 (AC-03) | T002 | test_summary_rejects_a_malformed_month |
| B4 (P0) | Given no expenses, when I run summary, then "No expenses." exit 0 (AC-04) | T002 | test_summary_of_nothing |
| B5 (P0) | Given the table, when I look at it in a terminal, then the columns line up (AC-05) | CHK001 | human |

## Phase 1 — Summary table
Goal: the summary command prints the category table.
Independent test: \`python3 -m tally summary --file sample/expenses.csv\` — prints the table from the spec.
- [ ] T001 summary command and table (B1, B2) — files: tally/cli.py, tests/test_cli_summary.py — verify: \`python3 -m unittest tests.test_cli_summary\`

## Phase 2 — Month filter and empty case
Goal: the summary can be narrowed to a month and says so when there is nothing to show.
Independent test: \`python3 -m unittest discover -s tests\` — whole suite green.
- [ ] T002 month filter, invalid month, empty summary (B3, B4) — files: tally/cli.py, tests/test_cli_summary.py — verify: \`python3 -m unittest tests.test_cli_summary\` — after: T001
- [ ] CHK001 human-verify the summary table's columns line up in a terminal — files: tally/cli.py — verify: human: the summary table's columns line up in a terminal — after: T002

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD
$FLOW lint "$SPEC/TASKS.md" >/dev/null

# ---- unapproved gate, pre-approved by --finish
{ head -2 "$SPEC/TASKS.md"; echo "Approved: $TODAY by user $SUFFIX"; tail -n +3 "$SPEC/TASKS.md"; } >"$SPEC/TASKS.new"
mv "$SPEC/TASKS.new" "$SPEC/TASKS.md"

# ---- T001
cat >tally/cli.py <<'PY'
import argparse
import sys

from tally.store import load_expenses
from tally.support.money import dollars
from tally.support.pad import fit


def render_listing(expenses):
    lines = []
    for expense in expenses:
        amount = fit(dollars(expense.amount_cents), 10, "right")
        lines.append(f"{fit(expense.day, 10)}  {fit(expense.category, 12)}  {amount}")
    return "\n".join(lines)


def summarise(expenses):
    totals = {}
    for expense in expenses:
        count, cents = totals.get(expense.category, (0, 0))
        totals[expense.category] = (count + 1, cents + expense.amount_cents)
    ranked = sorted(totals.items(), key=lambda pair: (-pair[1][1], pair[0]))
    return [(name, count, cents) for name, (count, cents) in ranked]


def render_summary(expenses):
    body = [(name, str(count), dollars(cents)) for name, count, cents in summarise(expenses)]
    overall = ("TOTAL", str(len(expenses)), dollars(sum(e.amount_cents for e in expenses)))
    table = [("Category", "Count", "Total")] + body + [overall]
    widths = [max(len(row[col]) for row in table) for col in range(3)]
    return "\n".join(
        "  ".join(
            (
                fit(row[0], widths[0]),
                fit(row[1], widths[1], "right"),
                fit(row[2], widths[2], "right"),
            )
        )
        for row in table
    )


def main(argv=None, out=None, err=None):
    out = out or sys.stdout
    err = err or sys.stderr
    parser = argparse.ArgumentParser(prog="tally")
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list")
    listing.add_argument("--file", required=True)
    summary = commands.add_parser("summary")
    summary.add_argument("--file", required=True)
    args = parser.parse_args(argv)
    if args.command == "list":
        out.write(render_listing(load_expenses(args.file)) + "\n")
    if args.command == "summary":
        out.write(render_summary(load_expenses(args.file)) + "\n")
    return 0
PY
cat >tests/test_cli_summary.py <<'PY'
import io
import unittest

from tally.cli import main

FULL = (
    "Category   Count      Total\n"
    "rent           1  $1,200.00\n"
    "groceries      2    $163.25\n"
    "transport      2     $42.00\n"
    "coffee         1      $4.50\n"
    "TOTAL          6  $1,409.75\n"
)


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    code = main(list(argv), out, err)
    return code, out.getvalue(), err.getvalue()


class TestSummaryCommand(unittest.TestCase):
    def test_summary_table_groups_and_totals_by_category(self):
        self.assertEqual(run("summary", "--file", "sample/expenses.csv"), (0, FULL, ""))

    def test_summary_sorts_ties_by_category_name(self):
        code, out, _ = run("summary", "--file", "tests/tie.csv")
        self.assertEqual([line.split()[0] for line in out.splitlines()], ["Category", "alpha", "beta", "TOTAL"])
PY
printf 'date,category,amount_cents\n2026-08-01,alpha,500\n2026-08-02,beta,500\n' >tests/tie.csv
python3 -m unittest tests.test_cli_summary >/dev/null 2>&1
git add tally/cli.py tests/test_cli_summary.py tests/tie.csv
git commit -q -m "cli: summary table by category"
$FLOW tick T001

# ---- T002
python3 - <<'PY'
p = "tally/cli.py"
s = open(p).read()
s = s.replace("import argparse\nimport sys\n", "import argparse\nimport re\nimport sys\n")
s = s.replace("\n\ndef render_listing", "\nMONTH = re.compile(r\"\\d{4}-(0[1-9]|1[0-2])\")\n\n\ndef render_listing", 1)
s = s.replace('    summary.add_argument("--file", required=True)\n',
              '    summary.add_argument("--file", required=True)\n    summary.add_argument("--month")\n')
s = s.replace('''    if args.command == "summary":
        out.write(render_summary(load_expenses(args.file)) + "\\n")
''', '''    if args.command == "summary":
        if args.month is not None and not MONTH.fullmatch(args.month):
            err.write(f"invalid month: {args.month}\\n")
            return 2
        expenses = load_expenses(args.file)
        if args.month:
            expenses = [expense for expense in expenses if expense.day.startswith(args.month)]
        if not expenses:
            out.write("No expenses.\\n")
            return 0
        out.write(render_summary(expenses) + "\\n")
''')
open(p, "w").write(s)
p = "tests/test_cli_summary.py"
s = open(p).read()
s += '''
    def test_summary_month_keeps_only_that_month(self):
        code, out, _ = run("summary", "--file", "sample/expenses.csv", "--month", "2026-08")
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines()[-1].split(), ["TOTAL", "3", "$181.25"])

    def test_summary_rejects_a_malformed_month(self):
        self.assertEqual(
            run("summary", "--file", "sample/expenses.csv", "--month", "2026-13"),
            (2, "", "invalid month: 2026-13\\n"),
        )

    def test_summary_of_a_month_with_nothing(self):
        self.assertEqual(
            run("summary", "--file", "sample/expenses.csv", "--month", "2025-01"),
            (0, "No expenses.\\n", ""),
        )
'''
open(p, "w").write(s)
PY
python3 -m unittest tests.test_cli_summary >/dev/null 2>&1
git add tally/cli.py tests/test_cli_summary.py
git commit -q -m "cli: summary month filter, invalid month and empty summary"
$FLOW tick T002

# ---- CHK001: evidence first, then the user's tick the user pre-approved
mkdir -p "$SPEC/verify"
{
  echo "# CHK001 evidence — the summary table in a terminal"
  echo
  echo '```'
  echo '$ python3 -m tally summary --file sample/expenses.csv'
  python3 -m tally summary --file sample/expenses.csv
  echo '```'
  echo
  echo "Header, four category rows and TOTAL share the same column edges (Category left-aligned, Count and Total right-aligned)."
} >"$SPEC/verify/CHK001.md"
$FLOW tick CHK001 --by user

# ---- gates
python3 -m unittest discover -s tests >/dev/null 2>&1
HEAD_SHA=$(git rev-parse --short HEAD)
cat >"$SPEC/PASS-$HEAD_SHA.md" <<MD
# PASS $HEAD_SHA
- G001 \`python3 -m unittest discover -s tests\` — exit 0
- G002 branch review — no findings above threshold
MD
$FLOW tick G001
$FLOW tick G002

# ---- unverified gate, pre-approved by --finish: acceptance evidence first
python3 -m tally summary --file sample/expenses.csv >/dev/null
python3 -m tally summary --file sample/expenses.csv --month 2026-13 >/dev/null 2>&1 || CODE=$?
cat >"$SPEC/verify/acceptance.md" <<MD
# Acceptance — Category summary

| Criterion | Command run now | Exit | Showed |
|-----------|-----------------|------|--------|
| AC-01 one row per category with count and total | \`python3 -m unittest tests.test_cli_summary\` | 0 | table matches the spec example |
| AC-02 sorted by total desc, ties by name, TOTAL row last | \`python3 -m unittest tests.test_cli_summary\` | 0 | tie test and full table pass |
| AC-03 --month filter; malformed month exits 2 with stderr message | \`python3 -m tally summary --file sample/expenses.csv --month 2026-13\` | ${CODE:-2} | stderr: invalid month: 2026-13, nothing on stdout |
| AC-04 empty summary prints No expenses. | \`python3 -m unittest tests.test_cli_summary\` | 0 | month with no rows prints No expenses. |
| AC-05 columns line up in a terminal | see verify/CHK001.md | 0 | rendered table, ticked by user under --finish |
MD
# Finish rule 5: claim-check re-runs each acceptance row before Verified: is written.
cat >"$SPEC/verify/claim-check.md" <<MD
CLAIM: AC-01..AC-04 pass
VERDICT: CONFIRMED
COMMAND: python3 -m unittest tests.test_cli_summary
OUTPUT: OK

5 confirmed, 0 unsupported, 0 inconclusive, 0 not-checkable.
MD
sed -i "s|^Approved:.*\$|&\nVerified: $TODAY by user $SUFFIX|" "$SPEC/TASKS.md"

# ---- shippable, but the repo has no remote
printf 'Discovered: no PR opened — this repo has no git remote — defer\n' >>"$SPEC/NOTES.md"
$FLOW finish off >/dev/null
git add "$SPEC"
git commit -q -m "specs: category summary plan, evidence, PASS and verification"
