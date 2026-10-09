#!/usr/bin/env python3
"""Truth table for pr-watch: external links, wave budget, --max-minutes, --json.
Split from test_pr_watch.py to stay under the file-size limit. No network."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("pr_watch", os.path.join(HERE, "pr-watch"))
_spec = importlib.util.spec_from_loader("pr_watch", _loader)
pw = importlib.util.module_from_spec(_spec)
_loader.exec_module(pw)


def pr(**kw):
    base = {"state": "OPEN", "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN",
            "reviewDecision": "", "checks": [{"name": "build", "bucket": "pass"}],
            "open_threads": 0, "flaky": [], "reruns": 0}
    base.update(kw)
    return base


def red(*names):
    return [{"name": n, "bucket": "fail"} for n in names]


class External(unittest.TestCase):
    def test_vercel_link_is_tagged_external(self):
        s = pr(number=7, checks=[{"name": "Vercel", "bucket": "fail",
                                  "link": "https://vercel.com/o/p/abc"}])
        self.assertIn("  failing Vercel https://vercel.com/o/p/abc (external)", pw.line(s, "fix-ci"))

    def test_actions_run_link_has_no_tag(self):
        s = pr(number=7, checks=[{"name": "build", "bucket": "fail",
                                  "link": "https://github.com/o/r/actions/runs/123/job/4"}])
        text = pw.line(s, "fix-ci")
        self.assertIn("failing build https://github.com/o/r/actions/runs/123/job/4", text)
        self.assertNotIn("external", text)

    def test_missing_link_is_external(self):
        s = pr(number=7, checks=[{"name": "x", "bucket": "fail"}])
        self.assertIn("(no link) (external)", pw.line(s, "fix-ci"))

    def test_json_marks_only_external_entries(self):
        s = pr(number=7, checks=[
            {"name": "V", "bucket": "fail", "link": "https://vercel.com/x"},
            {"name": "b", "bucket": "fail", "link": "https://github.com/o/r/actions/runs/9"}])
        self.assertEqual(pw.failing(s), [
            {"name": "V", "link": "https://vercel.com/x", "external": True},
            {"name": "b", "link": "https://github.com/o/r/actions/runs/9"}])


class WaveBudget(unittest.TestCase):
    def run_main(self, extra):
        orig = pw.read_state
        pw.read_state = lambda *a: pr(number=7, checks=red("build"))
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return pw.main(["7"] + extra)
        finally:
            pw.read_state = orig

    def test_work_returns_5_under_budget(self):
        self.assertEqual(self.run_main(["--waves", "4", "--max-waves", "5"]), 5)

    def test_spent_budget_returns_3(self):
        self.assertEqual(self.run_main(["--waves", "5", "--max-waves", "5"]), 3)

    def test_no_limit_by_default(self):
        self.assertEqual(self.run_main(["--waves", "99"]), 5)


class MaxMinutes(unittest.TestCase):
    def test_default_is_sixty_minutes(self):
        self.assertEqual(pw.deadline_for(60, False, 1000), 1000 + 3600)

    def test_explicit_zero_means_no_limit(self):
        self.assertIsNone(pw.deadline_for(0, False, 1000))

    def test_once_ignores_the_limit(self):
        self.assertIsNone(pw.deadline_for(60, True, 1000))

    def run_main(self, extra):
        """Polls a waiting PR with a fake clock; returns (exit code, sleeps)."""
        orig = (pw.read_state, pw.time.time, pw.time.sleep)
        clock, sleeps = [0.0], []

        def sleep(n):
            sleeps.append(n)
            clock[0] += n
            if len(sleeps) > 200:
                raise AssertionError("polled past any limit")
        pw.read_state = lambda *a: pr(number=7, checks=[{"name": "b", "bucket": "pending"}])
        pw.time.time, pw.time.sleep = lambda: clock[0], sleep
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return pw.main(["7", "--interval", "600"] + extra), sleeps
        finally:
            pw.read_state, pw.time.time, pw.time.sleep = orig

    def test_polling_stops_at_sixty_minutes_by_default(self):
        rc, sleeps = self.run_main([])
        self.assertEqual((rc, len(sleeps)), (3, 6))

    def test_explicit_limit_is_honoured(self):
        rc, sleeps = self.run_main(["--max-minutes", "20"])
        self.assertEqual((rc, len(sleeps)), (3, 2))

    def test_zero_keeps_polling_past_sixty_minutes(self):
        with self.assertRaises(AssertionError):
            self.run_main(["--max-minutes", "0"])

    def test_negative_limit_is_rejected(self):
        with self.assertRaises(SystemExit):
            self.run_main(["--max-minutes", "-5"])

    def test_once_does_not_poll(self):
        rc, sleeps = self.run_main(["--once"])
        self.assertEqual((rc, sleeps), (3, []))


class JsonMode(unittest.TestCase):
    def test_json_lists_every_pr_action(self):
        states = {1: pr(number=1, checks=[{"name": "b", "bucket": "pending"}]),
                  2: pr(number=2, checks=[{"name": "x", "bucket": "fail", "link": "L"}])}
        orig = pw.read_state
        pw.read_state = lambda p, *a: states[p]
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                rc = pw.main(["1", "2", "--json"])
        finally:
            pw.read_state = orig
        d = json.loads(out.getvalue())
        self.assertEqual((rc, d["pr"], d["action"]), (5, 2, "fix-ci"))
        self.assertEqual([(x["pr"], x["action"]) for x in d["prs"]], [(1, "wait"), (2, "fix-ci")])
        self.assertEqual(d["prs"][1]["failing"], [{"name": "x", "link": "L", "external": True}])


if __name__ == "__main__":
    unittest.main()
