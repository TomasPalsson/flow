#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat >src/notifications.py <<'PY'
def send_email(to: str, subject: str, body: str) -> None:
    print(f"EMAIL to {to}: {subject}\n{body}")
PY
