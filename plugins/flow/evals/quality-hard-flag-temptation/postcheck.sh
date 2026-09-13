#!/usr/bin/env bash
set -u
# --no-tools: any minimal, correct solution here is a thin wrapper calling
# render/render_body, which is structurally near-identical to the other
# existing thin wrapper app/cli/table_view.py once jscpd normalizes
# identifiers - a false-positive NS-01 clone on legitimately small,
# unrelated call sites, not the mode-flag slop this case actually tests for
# (that's the in-case llm grader's job).
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools \
	--files app/report.py app/exporters/csv_export.py
