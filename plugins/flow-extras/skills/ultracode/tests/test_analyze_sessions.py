"""Tests for scripts/analyze-sessions.mjs. Run: python3 -I test_analyze_sessions.py
Needs node on PATH (bun also works for the script itself)."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "scripts", "analyze-sessions.mjs")


def entry(kind, uuid, ts, **kw):
    e = {"type": kind, "uuid": uuid, "timestamp": ts}
    e.update(kw)
    return e


def assistant(uuid, req, usage, ts="2099-01-01T00:00:00Z"):
    return entry("assistant", uuid, ts, requestId=req, message={"id": "msg_0" + req, "usage": usage})


def user(uuid, text, ts="2099-01-01T00:00:00Z"):
    return entry("user", uuid, ts, message={"content": text})


def write(path, entries):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")


@unittest.skipUnless(shutil.which("node"), "node not installed")
class Analyze(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "projects")
        long_prompt = "refactor " + "x" * 200
        write(os.path.join(self.root, "proj-a", "s1.jsonl"), [
            user("u1", long_prompt),
            assistant("a1", "r1", {"input_tokens": 10, "cache_creation_input_tokens": 20,
                                   "cache_read_input_tokens": 30, "output_tokens": 1}),
            # same requestId, later entry carries the final output count: counted once
            assistant("a1b", "r1", {"input_tokens": 10, "cache_creation_input_tokens": 20,
                                    "cache_read_input_tokens": 30, "output_tokens": 5}),
        ])
        write(os.path.join(self.root, "proj-b", "s2.jsonl"), [
            user("u2", "big turn"),
            assistant("a2", "r2", {"input_tokens": 50000, "cache_creation_input_tokens": 100000,
                                   "cache_read_input_tokens": 7, "output_tokens": 3}),
        ])

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, *extra, cwd=None):
        r = subprocess.run(["node", SCRIPT, "--dir", self.root, *extra],
                           capture_output=True, text=True, cwd=cwd)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def test_cache_break_lists_exactly_the_big_turn_and_totals_match(self):
        rep = json.loads(self.run_script("--json"))
        self.assertEqual(len(rep["cache_breaks"]), 1)
        b = rep["cache_breaks"][0]
        self.assertEqual((b["project"], b["uncached"], b["total"]), ("proj-b", 150000, 150007))
        t = rep["totals"]
        self.assertEqual(t["input"], 10 + 50000)
        self.assertEqual(t["cacheCreate"], 20 + 100000)
        self.assertEqual(t["cacheRead"], 30 + 7)
        self.assertEqual(t["output"], 5 + 3)
        self.assertEqual(t["apiCalls"], 2)
        self.assertEqual(t["tokens"], 50010 + 100020 + 37 + 8)

    def test_threshold_flag_moves_the_line(self):
        rep = json.loads(self.run_script("--json", "--cache-break", "10"))
        self.assertEqual(len(rep["cache_breaks"]), 2)

    def test_prompt_preview_is_cut_to_80(self):
        rep = json.loads(self.run_script("--json", "--cache-break", "10"))
        for b in rep["cache_breaks"]:
            self.assertLessEqual(len(b["prompt"]), 80)

    def test_since_drops_old_entries(self):
        write(os.path.join(self.root, "proj-c", "old.jsonl"), [
            assistant("a3", "r3", {"input_tokens": 999999}, ts="2001-01-01T00:00:00Z"),
        ])
        rep = json.loads(self.run_script("--json"))
        self.assertEqual(rep["totals"]["apiCalls"], 2)

    def test_top_limits_projects(self):
        rep = json.loads(self.run_script("--json", "--top", "1"))
        self.assertEqual([p["project"] for p in rep["by_project"]], ["proj-b"])

    def test_writes_no_file_into_cwd(self):
        with tempfile.TemporaryDirectory() as cwd:
            self.run_script(cwd=cwd)
            self.run_script("--json", cwd=cwd)
            self.assertEqual(os.listdir(cwd), [])


if __name__ == "__main__":
    unittest.main()
