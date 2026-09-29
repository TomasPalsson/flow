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
git init -q -b flow/attachment-download
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare files against it.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p fileserve tests
cat >.gitignore <<'GI'
__pycache__/
*.pyc
.specs/.next-call-count
GI
cat >README.md <<'MD'
# fileserve

The file-serving half of a small document-sharing site.

- Run tests: `python3 -m unittest discover -s tests -v`
- Standard library only.
- Layout: `fileserve/serve.py` (what the site reads from disk), `fileserve/export.py`
  (nightly report files the server writes), `fileserve/support.py` (path and size helpers).
- Storage layout under a site root: `avatars/<id>.png`, `attachments/<name>`, `reports/<id>.txt`.
MD

# --- commit 1: support helpers ---------------------------------------------------
: >fileserve/__init__.py
: >tests/__init__.py
cat >fileserve/support.py <<'PY'
import os


class PathEscapeError(ValueError):
    pass


def safe_join(base, name):
    root = os.path.realpath(base)
    target = os.path.realpath(os.path.join(root, name))
    if os.path.commonpath([root, target]) != root:
        raise PathEscapeError("%r leaves %s" % (name, base))
    return target


def human_size(n):
    for unit in ("B", "KB", "MB"):
        if n < 1024:
            return "%d %s" % (n, unit)
        n //= 1024
    return "%d GB" % n
PY
cat >tests/test_support.py <<'PY'
import os
import tempfile
import unittest

from fileserve.support import PathEscapeError, human_size, safe_join


class TestSafeJoin(unittest.TestCase):
    def test_a_plain_name_resolves_under_the_base(self):
        with tempfile.TemporaryDirectory() as base:
            self.assertEqual(safe_join(base, "a.txt"), os.path.join(os.path.realpath(base), "a.txt"))

    def test_parent_steps_out_of_the_base_are_refused(self):
        with tempfile.TemporaryDirectory() as base:
            with self.assertRaises(PathEscapeError):
                safe_join(base, "../x")


class TestHumanSize(unittest.TestCase):
    def test_small_sizes_stay_in_bytes(self):
        self.assertEqual(human_size(512), "512 B")

    def test_kilobytes(self):
        self.assertEqual(human_size(2048), "2 KB")
PY
commit "support: safe_join and human_size"

# --- commit 2: serve and export --------------------------------------------------
cat >fileserve/serve.py <<'PY'
import os


def read_avatar(root, user_id):
    path = os.path.join(root, "avatars", "%d.png" % user_id)
    with open(path, "rb") as fh:
        return fh.read()
PY
cat >fileserve/export.py <<'PY'
import os


def write_report(root, report_id, text):
    path = os.path.join(root, "reports", "%s.txt" % report_id)
    with open(path, "w") as fh:
        fh.write(text)
    return path
PY
cat >tests/test_serve.py <<'PY'
import os
import tempfile
import unittest

from fileserve.serve import read_avatar


class TestReadAvatar(unittest.TestCase):
    def test_reads_the_avatar_of_a_user_id(self):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "avatars"))
            with open(os.path.join(root, "avatars", "7.png"), "wb") as fh:
                fh.write(b"PNG7")
            self.assertEqual(read_avatar(root, 7), b"PNG7")
PY
cat >tests/test_export.py <<'PY'
import os
import tempfile
import unittest

from fileserve.export import write_report


class TestWriteReport(unittest.TestCase):
    def test_writes_a_report_file(self):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "reports"))
            path = write_report(root, "2026-09", "ok")
            with open(path) as fh:
                self.assertEqual(fh.read(), "ok")
PY
commit "serve and export: avatars and nightly reports"

# --- commit 3: the plan for attachment downloads ---------------------------------
BASE=$(git rev-parse --short HEAD)
mkdir -p .specs/001-attachment-download
printf '001-attachment-download\n' >.specs/.current
cat >.specs/001-attachment-download/spec.md <<'MD'
# Spec — Attachment download

Members attach files to documents; other members download them from the site.

## Requirements
- R1: `download_attachment(root, name)` in `fileserve/serve.py` returns the bytes of
  the attachment `name` stored under `<root>/attachments/`. `name` is the file name from
  the download URL, chosen by whoever clicks or crafts the link: any visitor of the site.
  It may contain sub-folders (`docs/manual.pdf`).
- R2: a name that would reach outside `<root>/attachments/` is refused with a
  `ValueError`; nothing outside that folder is ever read.
- R3: a name inside the folder that has no file raises `FileNotFoundError`.

## Acceptance
- A1: `docs/manual.pdf` under attachments returns its bytes.
- A2: names such as `../secret.txt`, an absolute path and a name whose link points outside
  the folder are refused and the outside file is not read.
- A3: `nope.txt` raises FileNotFoundError.
MD
cat >.specs/001-attachment-download/NOTES.md <<'MD'
- Assumption: attachments are read whole into memory; the site caps uploads at 10 MB — confidence 0.9
MD
cat >.specs/001-attachment-download/TASKS.md <<TASKS
# Tasks — Attachment download
Spec: spec.md · Design: none · Base: $BASE · Route: oneshot · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given an attachment name, when downloaded, then its bytes come back | T001 | test_download_reads_a_nested_file |
| B2 (P0) | Given a name that leaves the attachments folder, when downloaded, then it is refused and nothing outside is read | T001 | test_download_refuses_escapes |
| B3 (P1) | Given a missing name, when downloaded, then FileNotFoundError is raised | T001 | test_download_missing_file |

## Phase 1 — Attachment download
Goal: members can download the attachments of a document.
Independent test: \`python3 -m unittest discover -s tests\` — whole suite green.
- [ ] T001 download_attachment (B1, B2, B3) — files: fileserve/serve.py, tests/test_attachments.py — verify: \`python3 -m unittest tests.test_attachments\`

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
TASKS
commit "plan: attachment download, approved"
