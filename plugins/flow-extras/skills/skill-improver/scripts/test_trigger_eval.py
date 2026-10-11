#!/usr/bin/env python3
"""Fixture tests for trigger-eval and optimise-description. A stub `claude`
binary stands in for the real one, so no network and no model are involved.

Run: python3 -I test_trigger_eval.py
"""

import importlib.machinery
import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent


def load(name, filename):
    loader = importlib.machinery.SourceFileLoader(name, str(HERE / filename))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


te = load("trigger_eval", "trigger-eval")
od = load("optimise_description", "optimise-description")

# The stub decides from the staged plugin's SKILL.md, like the real model would
# decide from the description it was shown. Stream mode: a query triggers when
# its last word appears in the description. "grep ..." queries call Grep first.
# "other ..." queries call a different skill. "flaky ..." triggers on 2 of 3 runs.
# Text mode (the description improver): returns the next canned description.
STUB = r'''#!/usr/bin/env python3
import json, os, sys, glob
args = sys.argv[1:]
d = os.environ["STUB_DIR"]
query = args[args.index("-p") + 1]
log = {"args": args, "cwd": os.getcwd(), "claudecode": "CLAUDECODE" in os.environ}
with open(os.path.join(d, "calls.jsonl"), "a") as f:
    f.write(json.dumps(log) + "\n")

def counter(name):
    p = os.path.join(d, name)
    n = int(open(p).read()) if os.path.exists(p) else 0
    open(p, "w").write(str(n + 1))
    return n

if "stream-json" not in args:
    with open(os.path.join(d, "improver_prompts.txt"), "a") as f:
        f.write(query + "\n=====\n")
    outs = json.load(open(os.path.join(d, "improver.json")))
    n = counter("improver.n")
    print("<new_description>" + outs[min(n, len(outs) - 1)] + "</new_description>")
    sys.exit(0)

if os.environ.get("STUB_FAIL"):
    sys.stderr.write("Invalid API key\n")
    sys.exit(1)
plugin = args[args.index("--plugin-dir") + 1]
skill_md = glob.glob(os.path.join(plugin, "skills", "*", "SKILL.md"))[0]
text = open(skill_md).read().lower()
name = json.load(open(os.path.join(plugin, ".claude-plugin", "plugin.json")))["name"]
skill = os.path.basename(os.path.dirname(skill_md))

def emit(tool, inp):
    print(json.dumps({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": tool, "input": inp}]}}))

print(json.dumps({"type": "system", "subtype": "init"}))
words = query.lower().split()
if words[0] == "grep":
    emit("Grep", {"pattern": "x"})
if words[0] == "other":
    emit("Skill", {"skill": "other:thing"})
elif words[0] == "flaky":
    if counter("flaky." + words[-1]) % 3 < 2:
        emit("Skill", {"skill": name + ":" + skill})
elif words[-1] in text:
    emit("Skill", {"skill": name + ":" + skill})
print(json.dumps({"type": "result"}))
'''


class Fixture:
    def __init__(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name).resolve()
        self.stub_dir = self.root / "stub"
        self.stub_dir.mkdir()
        self.claude = self.root / "claude"
        self.claude.write_text(STUB)
        self.claude.chmod(self.claude.stat().st_mode | stat.S_IXUSR)
        self.plugin = self.root / "plugins" / "demo"
        (self.plugin / ".claude-plugin").mkdir(parents=True)
        (self.plugin / ".claude-plugin" / "plugin.json").write_text('{"name": "demo"}')
        self.skill_md = self.plugin / "skills" / "widget" / "SKILL.md"
        self.skill_md.parent.mkdir(parents=True)
        self.set_description("Handles nothing in particular.")
        self.repo = self.root / "repo"
        (self.repo / ".claude").mkdir(parents=True)
        os.environ["STUB_DIR"] = str(self.stub_dir)
        os.environ["CLAUDECODE"] = "1"

    def set_description(self, desc):
        self.skill_md.write_text(f'---\nname: widget\ndescription: {json.dumps(desc)}\n---\n\n# Widget\n')

    def improver(self, outs):
        (self.stub_dir / "improver.json").write_text(json.dumps(outs))

    def calls(self):
        p = self.stub_dir / "calls.jsonl"
        return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []

    def close(self):
        self._tmp.cleanup()


def q(text, should):
    return {"query": text, "should_trigger": should}


class TriggerEval(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def run_eval(self, queries, desc=None, runs=1, workers=1):
        return te.evaluate(queries, self.fx.plugin, "widget", desc, runs=runs, workers=workers,
                           claude=str(self.fx.claude))

    def test_grep_then_skill_transcript_is_a_hit(self):
        self.fx.set_description("Use for widgets.")
        res = self.run_eval([q("grep the repo for widgets", True)])
        self.assertEqual(res["results"][0]["triggers"], 1)
        self.assertTrue(res["results"][0]["pass"])

    def test_other_skill_and_no_skill_are_misses(self):
        self.fx.set_description("Use for widgets.")
        res = self.run_eval([q("other widgets", True), q("tell me a joke", False)])
        self.assertEqual([r["triggers"] for r in res["results"]], [0, 0])
        self.assertEqual([r["pass"] for r in res["results"]], [False, True])

    def test_classify_requires_the_namespaced_name(self):
        line = json.dumps({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Skill", "input": {"skill": "widget"}}]}})
        self.assertFalse(te.classify_events([line], "demo:widget"))
        self.assertTrue(te.classify_events([line], "widget"))

    def test_per_query_counts_and_threshold(self):
        self.fx.set_description("Use for widgets.")
        res = self.run_eval([q("flaky one", True), q("flaky two", False), q("zzz widgets", True)],
                            runs=3)
        r = {x["query"]: x for x in res["results"]}
        self.assertEqual((r["flaky one"]["triggers"], r["flaky one"]["runs"]), (2, 3))
        self.assertTrue(r["flaky one"]["pass"])  # 2/3 > 0.5
        self.assertFalse(r["flaky two"]["pass"])  # triggers 2/3 but should not
        self.assertEqual(r["zzz widgets"]["triggers"], 3)
        self.assertEqual(res["summary"], {"total": 3, "passed": 2, "failed": 1})

    def test_runs_in_scratch_with_plugin_dir_and_no_claudecode(self):
        self.fx.set_description("Use for widgets.")
        cwd = os.getcwd()
        os.chdir(self.fx.repo)
        try:
            self.run_eval([q("zzz widgets", True)])
        finally:
            os.chdir(cwd)
        call = self.fx.calls()[0]
        self.assertNotIn(str(self.fx.repo), call["cwd"])
        self.assertFalse(call["claudecode"])
        self.assertIn("--plugin-dir", call["args"])
        self.assertIn("--max-turns", call["args"])

    def test_description_override_is_staged_not_written(self):
        before = self.fx.skill_md.read_bytes()
        res = self.run_eval([q("zzz gadgets", True)], desc="Use for gadgets.")
        self.assertEqual(res["results"][0]["triggers"], 1)
        self.assertEqual(self.fx.skill_md.read_bytes(), before)
        staged = self.fx.calls()[0]["args"][self.fx.calls()[0]["args"].index("--plugin-dir") + 1]
        self.assertNotEqual(Path(staged).resolve(), self.fx.plugin)

    def test_nothing_written_under_invoking_repo_claude_dir(self):
        self.fx.set_description("Use for widgets.")
        qfile = self.fx.root / "queries.json"
        qfile.write_text(json.dumps([q("zzz widgets", True), q("tell me a joke", False)]))
        cwd = os.getcwd()
        os.chdir(self.fx.repo)
        try:
            rc = te.main(["--plugin-dir", str(self.fx.plugin), "--skill", "widget",
                          "--queries", str(qfile), "--runs", "1", "--workers", "1",
                          "--claude", str(self.fx.claude)])
        finally:
            os.chdir(cwd)
        self.assertEqual(rc, 0)
        self.assertEqual(list((self.fx.repo / ".claude").iterdir()), [])
        out = json.loads((self.fx.repo / ".skill-forge" / "widget" / "trigger.json").read_text())
        self.assertEqual(out["summary"]["passed"], 2)

    def test_failing_cli_is_an_error_and_writes_no_trigger_json(self):
        qfile = self.fx.root / "queries.json"
        qfile.write_text(json.dumps([q("zzz widgets", True), q("tell me a joke", False)]))
        os.environ["STUB_FAIL"] = "1"
        self.addCleanup(os.environ.pop, "STUB_FAIL", None)
        cwd = os.getcwd()
        os.chdir(self.fx.repo)
        try:
            rc = te.main(["--plugin-dir", str(self.fx.plugin), "--skill", "widget",
                          "--queries", str(qfile), "--runs", "1", "--workers", "1",
                          "--claude", str(self.fx.claude)])
        finally:
            os.chdir(cwd)
        self.assertNotEqual(rc, 0)
        self.assertFalse((self.fx.repo / ".skill-forge").exists())

    def test_failing_cli_stops_the_optimiser(self):
        qfile = self.fx.root / "queries.json"
        qfile.write_text(json.dumps([q("zzz widgets", True), q("tell me a joke", False)]))
        os.environ["STUB_FAIL"] = "1"
        self.addCleanup(os.environ.pop, "STUB_FAIL", None)
        cwd = os.getcwd()
        os.chdir(self.fx.repo)
        try:
            rc = od.main(["--plugin-dir", str(self.fx.plugin), "--skill", "widget",
                          "--queries", str(qfile), "--approved", "--runs", "1",
                          "--workers", "1", "--claude", str(self.fx.claude)])
        finally:
            os.chdir(cwd)
        self.assertNotEqual(rc, 0)
        self.assertFalse((self.fx.repo / ".skill-forge").exists())

    def test_optimiser_default_out_is_not_the_measurement_file(self):
        self.fx.set_description("Use for widgets.")
        qfile = self.fx.root / "queries.json"
        qfile.write_text(json.dumps([q("zzz widgets", True), q("tell me a joke", False)]))
        cwd = os.getcwd()
        os.chdir(self.fx.repo)
        try:
            od.main(["--plugin-dir", str(self.fx.plugin), "--skill", "widget",
                     "--queries", str(qfile), "--approved", "--runs", "1", "--iterations", "0",
                     "--workers", "1", "--claude", str(self.fx.claude)])
        finally:
            os.chdir(cwd)
        self.assertFalse((self.fx.repo / ".skill-forge" / "widget" / "trigger.json").exists())
        self.assertTrue((self.fx.repo / ".skill-forge" / "widget" / "optimise.json").exists())

    def test_duplicate_queries_are_rejected(self):
        qfile = self.fx.root / "queries.json"
        qfile.write_text(json.dumps([q("a", True), q("a", False)]))
        with self.assertRaises(ValueError):
            te.load_queries(qfile)

    def test_split_is_stratified_disjoint_and_stable(self):
        qs = [q(f"p{i}", True) for i in range(10)] + [q(f"n{i}", False) for i in range(5)]
        train, held = te.split_queries(qs)
        self.assertEqual(sum(1 for x in held if x["should_trigger"]), 4)
        self.assertEqual(sum(1 for x in held if not x["should_trigger"]), 2)
        self.assertEqual(len(train) + len(held), 15)
        self.assertFalse({x["query"] for x in train} & {x["query"] for x in held})
        self.assertEqual(te.split_queries(qs), (train, held))

    def test_description_patcher_handles_block_scalars(self):
        text = "---\nname: x\ndescription: >\n  old line one\n  old line two\nother: 1\n---\nbody\n"
        out = te._patched_description_text(text, "new one")
        self.assertIn('description: "new one"', out)
        self.assertNotIn("old line", out)
        self.assertIn("other: 1", out)
        self.assertTrue(out.endswith("body\n"))


def cand(i, train, held, desc="d"):
    return {"iteration": i, "description": desc + str(i), "train_passed": train, "train_total": 6,
            "held_passed": held, "held_total": 4}


class Optimiser(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def test_best_by_holdout_beats_best_by_train(self):
        cands = [cand(0, 2, 1), cand(1, 6, 1), cand(2, 4, 3)]
        self.assertEqual(od.pick_best(cands)["iteration"], 2)
        winner, label = od.verdict(cands)
        self.assertEqual((winner["iteration"], label), (2, "better"))

    def test_holdout_tie_goes_to_train_then_earlier(self):
        self.assertEqual(od.pick_best([cand(0, 3, 2), cand(1, 5, 2), cand(2, 5, 2)])["iteration"], 1)

    def test_win_under_two_queries_is_noise_and_original_stays(self):
        winner, label = od.verdict([cand(0, 2, 1), cand(1, 6, 2)])
        self.assertEqual((winner["iteration"], label), (0, "noise"))

    def test_original_best_is_reported(self):
        winner, label = od.verdict([cand(0, 3, 3), cand(1, 6, 1)])
        self.assertEqual((winner["iteration"], label), (0, "original-best"))

    def test_prompt_carries_train_failures_only(self):
        train = [{"query": "train miss", "should_trigger": True, "triggers": 0, "runs": 3, "pass": False},
                 {"query": "train ok", "should_trigger": True, "triggers": 3, "runs": 3, "pass": True}]
        history = [cand(0, 1, 9, "old")]
        prompt = od.build_prompt("# body", "old", train, history)
        self.assertIn("train miss", prompt)
        self.assertNotIn("train ok", prompt)
        self.assertNotIn("held", prompt.lower())
        self.assertIn("train 1/6", prompt)
        self.assertIn("structurally different", prompt)

    def test_approval_gate_prints_queries_and_runs_nothing(self):
        qfile = self.fx.root / "queries.json"
        qfile.write_text(json.dumps([q("zzz widgets", True), q("tell me a joke", False)]))
        out = self.fx.root / "trigger.json"
        rc = od.main(["--plugin-dir", str(self.fx.plugin), "--skill", "widget", "--queries",
                      str(qfile), "--out", str(out), "--claude", str(self.fx.claude)])
        self.assertEqual(rc, 2)
        self.assertEqual(self.fx.calls(), [])
        self.assertFalse(out.exists())

    def run_optimise(self, queries, improver, iterations=2):
        self.fx.improver(improver)
        return od.optimise(queries, self.fx.plugin, "widget", iterations=iterations, runs=1,
                           workers=1, claude=str(self.fx.claude))

    def queries(self):
        words = ["alpha", "beta", "gamma", "delta", "epsilon"]
        return ([q(f"find {w}", True) for w in words] +
                [q(f"unrelated {i} nothing{i}", False) for i in range(5)])

    def test_end_to_end_picks_candidate_and_hides_heldout_from_improver(self):
        before = self.fx.skill_md.read_bytes()
        res = self.run_optimise(self.queries(), ["Handles alpha beta gamma delta epsilon."])
        train, held = te.split_queries(self.queries())
        self.assertEqual(res["verdict"], "better")
        self.assertEqual(res["winner"], "Handles alpha beta gamma delta epsilon.")
        prompts = (self.fx.stub_dir / "improver_prompts.txt").read_text()
        for h in held:
            self.assertNotIn(h["query"], prompts)
        self.assertTrue(any(t["query"] in prompts for t in train if t["should_trigger"]))
        self.assertEqual(self.fx.skill_md.read_bytes(), before)

    def test_overlong_description_gets_one_shorten_retry(self):
        res = self.run_optimise(self.queries(), ["x" * 1200, "Handles alpha beta gamma delta epsilon."])
        text_calls = [c for c in self.fx.calls() if "stream-json" not in c["args"]]
        self.assertEqual(len(text_calls), 2)
        self.assertEqual(res["winner"], "Handles alpha beta gamma delta epsilon.")
        shorten = (self.fx.stub_dir / "improver_prompts.txt").read_text().split("=====")[1]
        self.assertIn("over the 1024 limit", shorten)


if __name__ == "__main__":
    unittest.main()
