#!/usr/bin/env bash
set -euo pipefail
mkdir -p app/cli app/services app/exporters
cat >app/__init__.py <<'PY'
PY
cat >app/report.py <<'PY'
def render(rows: list[dict]) -> str:
    if not rows:
        return ""
    header = "\t".join(rows[0].keys())
    body = ["\t".join(str(v) for v in row.values()) for row in rows]
    return "\n".join([header] + body)
PY
cat >app/cli/__init__.py <<'PY'
PY
cat >app/cli/table_view.py <<'PY'
from app.report import render


def print_table(rows: list[dict]) -> None:
    print(render(rows))
PY
cat >app/services/__init__.py <<'PY'
PY
cat >app/services/summary.py <<'PY'
from app.report import render


def summary_block(rows: list[dict]) -> str:
    return f"Summary:\n{render(rows)}"
PY
cat >app/exporters/__init__.py <<'PY'
PY
cat >app/exporters/csv_export.py <<'PY'
def export_csv(rows: list[dict]) -> str:
    raise NotImplementedError
PY
