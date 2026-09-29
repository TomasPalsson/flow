#!/usr/bin/env bash
# What a perfect run leaves: download_attachment built on the package's safe_join
# (the review step's finding: user-supplied names must not reach outside the
# attachments folder), tests for the traversal shapes, a pathspec commit of exactly
# the task's two files, and T001 ticked through flow tick. The gates are the next turn.
set -euo pipefail
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"

python3 - <<'PY'
p = "fileserve/serve.py"
s = open(p).read()
s = s.replace("import os\n", "import os\n\nfrom fileserve.support import safe_join\n", 1)
s += '''

def download_attachment(root, name):
    with open(safe_join(os.path.join(root, "attachments"), name), "rb") as fh:
        return fh.read()
'''
open(p, "w").write(s)
PY
cat >tests/test_attachments.py <<'PY'
import os
import tempfile
import unittest

from fileserve.serve import download_attachment


class TestDownloadAttachment(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = os.path.realpath(tmp.name)
        self.attachments = os.path.join(self.root, "attachments")
        os.makedirs(os.path.join(self.attachments, "docs"))
        self.write(os.path.join(self.attachments, "docs", "manual.pdf"), b"MANUAL")
        self.write(os.path.join(self.root, "secret.txt"), b"SECRET")

    @staticmethod
    def write(path, data):
        with open(path, "wb") as fh:
            fh.write(data)

    def test_download_reads_a_nested_file(self):
        self.assertEqual(download_attachment(self.root, "docs/manual.pdf"), b"MANUAL")

    def test_download_refuses_parent_steps(self):
        with self.assertRaises(ValueError):
            download_attachment(self.root, "../secret.txt")

    def test_download_refuses_an_absolute_name(self):
        with self.assertRaises(ValueError):
            download_attachment(self.root, os.path.join(self.root, "secret.txt"))

    def test_download_refuses_a_link_that_leaves_the_folder(self):
        os.symlink(os.path.join(self.root, "secret.txt"), os.path.join(self.attachments, "leak.txt"))
        with self.assertRaises(ValueError):
            download_attachment(self.root, "leak.txt")

    def test_download_refuses_a_sibling_folder_sharing_the_prefix(self):
        os.makedirs(os.path.join(self.root, "attachments-evil"))
        self.write(os.path.join(self.root, "attachments-evil", "x.txt"), b"EVIL")
        with self.assertRaises(ValueError):
            download_attachment(self.root, "../attachments-evil/x.txt")

    def test_download_missing_file(self):
        with self.assertRaises(FileNotFoundError):
            download_attachment(self.root, "nope.txt")
PY
python3 -m unittest tests.test_attachments >/dev/null
git add fileserve/serve.py tests/test_attachments.py
git commit -q -m "serve: download_attachment reads a user-named file under attachments/" -- fileserve/serve.py tests/test_attachments.py
$FLOW tick T001

# phase boundary: the Independent test, executed
python3 -m unittest discover -s tests >/dev/null
