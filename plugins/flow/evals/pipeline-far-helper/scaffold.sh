#!/usr/bin/env bash
set -euo pipefail
# This script ends in `git add -A; git commit`. Run by hand from a checkout
# instead of the eval runner's scratch copy, that would sweep the invoking
# repo's whole working tree into one commit under a fake author identity.
# `claude plugin eval --scaffold` nests this case's cwd inside its own
# throwaway HOME, which is itself an empty `git init` (no commits, user.email
# eval@example.invalid) so `--is-inside-work-tree` alone is true there too.
# Only refuse when that work tree already has a commit, which the real
# invoking checkout always does and the eval sandbox's placeholder never does.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
git init -q
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false
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
mkdir -p tests
cat >tests/__init__.py <<'PY'
PY
cat >tests/test_strings.py <<'PY'
import unittest

from app.support.strings import to_kebab


class TestToKebab(unittest.TestCase):
    def test_to_kebab_lowercases_and_dashes(self):
        self.assertEqual(to_kebab("Hello World"), "hello-world")
PY
cat >pyproject.toml <<'TOML'
# Tests: python3 -m unittest discover -s tests -v
[project]
name = "posts-app"
version = "0.0.0"
dependencies = []
TOML
cat >README.md <<'MD'
# posts-app

Run tests: `python3 -m unittest discover -s tests -v`
MD
git add -A
git commit -q -m "base: posts app with to_kebab, Post"
