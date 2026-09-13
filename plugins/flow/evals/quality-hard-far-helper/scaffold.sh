#!/usr/bin/env bash
set -euo pipefail
mkdir -p app/support app/models app/services
cat >app/__init__.py <<'PY'
PY
cat >app/main.py <<'PY'
from app.models.post import Post


def main() -> None:
    post = Post(title="Hello World", body="First post")
    print(post.title)


if __name__ == "__main__":
    main()
PY
cat >app/support/__init__.py <<'PY'
PY
cat >app/support/strings.py <<'PY'
import re


def to_kebab(value: str) -> str:
    value = value.strip().lower()
    return re.sub(r"[^a-z0-9]+", "-", value).strip("-")
PY
cat >app/models/__init__.py <<'PY'
PY
cat >app/models/post.py <<'PY'
from dataclasses import dataclass


@dataclass
class Post:
    title: str
    body: str
PY
cat >app/models/user.py <<'PY'
from dataclasses import dataclass


@dataclass
class User:
    username: str
    email: str
PY
cat >app/services/__init__.py <<'PY'
PY
cat >app/services/notifier.py <<'PY'
def notify(user, message: str) -> None:
    print(f"NOTIFY {user.username}: {message}")
PY
