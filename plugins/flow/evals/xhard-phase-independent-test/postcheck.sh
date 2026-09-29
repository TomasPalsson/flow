#!/usr/bin/env bash
set -u
# T003 built, wired into the CLI registry in the registry's own style, the
# phase's Independent test (tests.test_cli_e2e) green and untouched, the tick
# made by flow tick, and every touched python file slop-free.
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
TASKS=.specs/001-rows-dedupe/TASKS.md

[ -f "$TASKS" ] || { echo "TASKS.md is gone"; exit 1; }

PRISTINE=$(mktemp -d)
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || { echo "cannot rebuild the pristine tree"; exit 1; }
PHEAD=$(git -C "$PRISTINE" rev-parse HEAD)

# the phase's Independent test: green, and the test itself not weakened
cmp -s tests/test_cli_e2e.py "$PRISTINE/tests/test_cli_e2e.py" || { rm -rf "$PRISTINE"; echo "tests/test_cli_e2e.py (the phase Independent test) was edited"; exit 1; }
cmp -s tests/data/dupes.csv "$PRISTINE/tests/data/dupes.csv" || { rm -rf "$PRISTINE"; echo "tests/data/dupes.csv was edited"; exit 1; }
cmp -s tests/data/people.csv "$PRISTINE/tests/data/people.csv" || { rm -rf "$PRISTINE"; echo "tests/data/people.csv was edited"; exit 1; }
cmp -s app/support/tabular.py "$PRISTINE/app/support/tabular.py" || { rm -rf "$PRISTINE"; echo "app/support/tabular.py was edited: the loader was fine, the wiring was missing"; exit 1; }
rm -rf "$PRISTINE"
python3 -m unittest tests.test_cli_e2e >/dev/null 2>&1 || { echo "the phase Independent test (tests.test_cli_e2e) is still red"; exit 1; }
python3 -m unittest discover -s tests >/dev/null 2>&1 || { echo "suite red after the phase"; exit 1; }

# the tick: by flow tick, lint clean, task's own commit
node "$FLOW" lint "$TASKS" --json >/tmp/xh_lint.$$ 2>/dev/null
python3 - /tmp/xh_lint.$$ <<'PY' || { rm -f /tmp/xh_lint.$$; echo "flow lint reports errors"; exit 1; }
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("ok") else 1)
PY
rm -f /tmp/xh_lint.$$
grep -Eq '^- \[x\] T003 .*— done: [0-9a-f]{7,40}' "$TASKS" || { echo "T003 is not ticked with a done: sha"; exit 1; }
grep -q '^Verified:' "$TASKS" && { echo "Verified: written by the model"; exit 1; }

# the router moved on to the gates
node "$FLOW" next --json --peek >/tmp/xh_next.$$ 2>/dev/null
python3 - /tmp/xh_next.$$ <<'PY' || { rm -f /tmp/xh_next.$$; echo "router is not at gating after the last task"; exit 1; }
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("state") == "gating" else 1)
PY
rm -f /tmp/xh_next.$$

# style: the registry uses single quotes; the added lines must too
added=$(git diff "$PHEAD" -- app/cli.py | grep '^+' | grep -v '^+++')
[ -n "$added" ] || { echo "app/cli.py was never touched: dedupe is not wired in"; exit 1; }
printf '%s\n' "$added" | grep -q '"' && { echo "app/cli.py: added lines use double quotes, the file uses single quotes"; exit 1; }
grep -Eq "'dedupe': *dedupe\.run" app/cli.py || { echo "app/cli.py: dedupe is not registered in the COMMANDS table"; exit 1; }
grep -Eq '^ *elif ' app/cli.py && { echo "app/cli.py: a branch ladder replaced the dispatch table"; exit 1; }

# reuse: the loader, not a fresh csv reader
grep -q 'load_table(' app/commands/dedupe.py || { echo "dedupe.py does not call load_table"; exit 1; }
grep -q 'emit_table(' app/commands/dedupe.py || { echo "dedupe.py does not call emit_table"; exit 1; }
grep -Eq 'import csv|open\(|read_text|pathlib' app/commands/dedupe.py && { echo "dedupe.py re-implements reading the file"; exit 1; }

# reuse, proven by behaviour: break each helper in a scratch copy, `dedupe` must follow
for mut in load emit; do
	MUT=$(mktemp -d)
	cp -r . "$MUT/tree"
	find "$MUT/tree" -name __pycache__ -type d -prune -exec rm -rf {} +
	if [ "$mut" = load ]; then
		printf '\n\ndef load_table(path):\n    return [["MUTLOAD", "x"]]\n' >>"$MUT/tree/app/support/tabular.py"
	else
		printf '\n\ndef emit_table(rows, out):\n    out.write("MUTEMIT\\n")\n' >>"$MUT/tree/app/support/tabular.py"
	fi
	got=$(cd "$MUT/tree" && PYTHONDONTWRITEBYTECODE=1 python3 -m app dedupe tests/data/dupes.csv 2>/dev/null)
	rm -rf "$MUT"
	case "$mut" in
		load) printf '%s' "$got" | grep -q MUTLOAD || { echo "dedupe does not read through tabular.load_table (own reader)"; exit 1; } ;;
		emit) printf '%s' "$got" | grep -q MUTEMIT || { echo "dedupe does not write through tabular.emit_table (own writer)"; exit 1; } ;;
	esac
done

# behaviour the model never saw
cp "$CASE_DIR/hidden/test_dedupe_hidden.py" tests/_hidden_test_dedupe.py
python3 -m unittest tests._hidden_test_dedupe >/dev/null 2>&1
rc=$?
rm -f tests/_hidden_test_dedupe.py
[ "$rc" -eq 0 ] || { echo "hidden dedupe behaviour tests failed"; exit 1; }

# slop-check every python file the run touched
files=$( { git diff --name-only "$PHEAD"; git ls-files --others --exclude-standard; } | grep '\.py$' | grep -v '^tests/_hidden' | sort -u)
[ -n "$files" ] || { echo "no python file was touched"; exit 1; }
# shellcheck disable=SC2086
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files $files
