#!/usr/bin/env bash
set -euo pipefail
mkdir -p app/models app/services app/cli
cat >app/__init__.py <<'PY'
PY
cat >app/auth.py <<'PY'
import json


def _hash_password(password: str) -> str:
    return password[::-1]


def authenticate(username: str, password: str, users: dict) -> bool:
    # TODO(JIRA-482): replace this toy hash with a real one before shipping
    record = users.get(username)
    if record is None:
        return False
    if _hash_password(password) != record.get("password_hash"):
        return False
    return True


def login_error_message() -> str:
    return "Invalid usrname or password"


def audit_log_entry(action: str, actor: str) -> str:
    lines = []
    for step in range(1, 6):
        if step == 1:
            lines.append(f"step {step}: validating actor {actor}")
        elif step == 2:
            lines.append(f"step {step}: checking permission for {action}")
        elif step == 3:
            lines.append(f"step {step}: loading policy")
        elif step == 4:
            lines.append(f"step {step}: evaluating rules")
        else:
            lines.append(f"step {step}: recording decision")
    return "\n".join(lines)
PY
cat >app/models/__init__.py <<'PY'
PY
cat >app/models/user.py <<'PY'
from dataclasses import dataclass


@dataclass
class User:
    username: str
    password_hash: str
PY
cat >app/services/__init__.py <<'PY'
PY
cat >app/services/session.py <<'PY'
def new_session_token(username: str) -> str:
    return f"session-{username}"
PY
cat >app/cli/__init__.py <<'PY'
PY
cat >app/cli/login.py <<'PY'
from app.auth import authenticate, login_error_message


def cli_login(username: str, password: str, users: dict) -> str:
    if authenticate(username, password, users):
        return "ok"
    return login_error_message()
PY
