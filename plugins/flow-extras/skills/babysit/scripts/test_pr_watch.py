#!/usr/bin/env python3
"""Truth table for pr-watch decide(). No network: decide() takes a dict."""
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


class Decide(unittest.TestCase):
    def check(self, want, **kw):
        self.assertEqual(pw.decide(pr(**kw)), want, kw)

    def test_clean_is_done(self):
        self.check("done")

    def test_draft_clean_is_still_done(self):
        self.check("done", isDraft=True)

    def test_no_checks_is_done(self):
        self.check("done", checks=[])

    def test_skipped_check_is_not_red(self):
        self.check("done", checks=[{"name": "x", "bucket": "skipping"}])

    def test_merged_and_closed_stop(self):
        self.check("stop-merged", state="MERGED")
        self.check("stop-closed", state="CLOSED")

    def test_merged_beats_everything(self):
        self.check("stop-merged", state="MERGED", checks=red("build"), open_threads=3)

    def test_pending_waits(self):
        self.check("wait", checks=[{"name": "build", "bucket": "pending"}])

    def test_unknown_mergeability_waits(self):
        self.check("wait", mergeable="UNKNOWN")

    def test_changes_requested_waits_for_the_reviewer(self):
        self.check("wait", reviewDecision="CHANGES_REQUESTED")

    def test_conflict(self):
        self.check("resolve-conflict", mergeable="CONFLICTING")
        self.check("resolve-conflict", mergeStateStatus="DIRTY")

    def test_conflict_before_threads_and_ci(self):
        self.check("resolve-conflict", mergeable="CONFLICTING", open_threads=1,
                   checks=red("build"))

    def test_open_threads_stop_for_the_user(self):
        self.check("stop-threads", open_threads=2)

    def test_red_ci_is_worked_before_threads_stop(self):
        self.check("fix-ci", open_threads=1, checks=red("build"))

    def test_threads_stop_instead_of_waiting(self):
        self.check("stop-threads", open_threads=1,
                   checks=[{"name": "b", "bucket": "pending"}])

    def test_red_ci_is_fix(self):
        self.check("fix-ci", checks=red("build"))

    def test_cancelled_counts_as_red(self):
        self.check("fix-ci", checks=[{"name": "b", "bucket": "cancel"}])

    def test_red_beats_pending(self):
        self.check("fix-ci", checks=red("build") + [{"name": "t", "bucket": "pending"}])

    def test_flake_rerun_once(self):
        self.check("rerun-flake", checks=red("e2e"), flaky=["e2e"])

    def test_flake_after_one_rerun_is_a_real_failure(self):
        self.check("fix-ci", checks=red("e2e"), flaky=["e2e"], reruns=1)

    def test_unflagged_red_is_never_rerun(self):
        self.check("fix-ci", checks=red("e2e"), flaky=["other"])

    def test_mixed_flaky_and_real_red_is_fix(self):
        self.check("fix-ci", checks=red("e2e", "unit"), flaky=["e2e"])


class Pick(unittest.TestCase):
    def test_merged_pr_is_skipped(self):
        a, b, c = pr(number=50, state="MERGED"), pr(number=51, checks=red("x")), pr(number=52)
        self.assertEqual(pw.pick([a, b, c])["number"], 51)

    def test_first_red_pr_in_the_list_wins(self):
        a, b = pr(number=51, checks=red("x")), pr(number=52, checks=red("y"))
        self.assertEqual(pw.pick([a, b])["number"], 51)

    def test_green_pr_does_not_hide_a_red_one_after_it(self):
        a, b = pr(number=51), pr(number=52, checks=red("x"))
        self.assertEqual(pw.decide(pw.pick([a, b])), "fix-ci")

    def test_all_done_is_done(self):
        self.assertEqual(pw.decide(pw.pick([pr(number=51), pr(number=52)])), "done")

    def test_all_merged_stops(self):
        a, b = pr(number=50, state="MERGED"), pr(number=51, state="MERGED")
        self.assertEqual(pw.decide(pw.pick([a, b])), "stop-merged")

    def test_closed_pr_in_the_list_stops(self):
        a, b = pr(number=51, state="CLOSED"), pr(number=52)
        self.assertEqual(pw.decide(pw.pick([a, b])), "stop-closed")

    def test_waiting_pr_does_not_block_a_conflict_after_it(self):
        a = pr(number=51, checks=[{"name": "b", "bucket": "pending"}])
        b = pr(number=52, mergeable="CONFLICTING")
        self.assertEqual(pw.pick([a, b])["number"], 52)

    def test_threads_stop_does_not_hide_red_ci_after_it(self):
        a, b = pr(number=51, open_threads=2), pr(number=52, checks=red("x"))
        self.assertEqual(pw.pick([a, b])["number"], 52)

    def test_closed_pr_does_not_hide_red_ci_after_it(self):
        a, b = pr(number=51, state="CLOSED"), pr(number=52, checks=red("x"))
        self.assertEqual(pw.pick([a, b])["number"], 52)

    def test_flake_rerun_counts_as_actionable(self):
        a = pr(number=51, checks=[{"name": "b", "bucket": "pending"}])
        b = pr(number=52, checks=red("f"), flaky=["f"])
        self.assertEqual(pw.decide(pw.pick([a, b])), "rerun-flake")

    def test_waiting_beats_a_stop_so_polling_continues(self):
        a = pr(number=51, open_threads=1)
        b = pr(number=52, checks=[{"name": "b", "bucket": "pending"}])
        self.assertEqual(pw.pick([a, b])["number"], 52)


class FakeGh:
    """Stands in for pw.gh: maps the gh subcommand to (rc, stdout, stderr)."""
    def __init__(self, view, checks, threads, checks_rc=0):
        self.view, self.checks, self.threads, self.checks_rc = view, checks, threads, checks_rc

    def __call__(self, args):
        if args[:2] == ["pr", "view"]:
            return 0, json.dumps(self.view), ""
        if args[:2] == ["pr", "checks"]:
            return self.checks_rc, json.dumps(self.checks), ""
        if args[:2] == ["repo", "view"]:
            return 0, json.dumps({"nameWithOwner": "o/r"}), ""
        return 0, json.dumps({"data": {"repository": {"pullRequest": {
            "reviewThreads": {"nodes": self.threads}}}}}), ""


def thread(resolved=False):
    return {"isResolved": resolved}


class ReadState(unittest.TestCase):
    def read(self, threads, checks=(), checks_rc=0):
        view = {"number": 7, "state": "OPEN", "isDraft": True, "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN", "reviewDecision": "", "baseRefName": "main"}
        orig, pw.gh = pw.gh, FakeGh(view, list(checks), threads, checks_rc)
        try:
            return pw.read_state(7, None, [], 0)
        finally:
            pw.gh = orig

    def test_counts_only_unresolved_threads(self):
        s = self.read([thread(), thread(), thread(resolved=True)])
        self.assertEqual(s["open_threads"], 2)

    def test_check_links_are_kept(self):
        s = self.read([], [{"name": "build", "bucket": "fail", "link": "https://x/runs/9"}],
                      checks_rc=1)
        self.assertEqual(s["checks"][0]["link"], "https://x/runs/9")

    def test_line_prints_each_failing_check_link(self):
        s = pr(number=7, checks=[{"name": "build", "bucket": "fail", "link": "https://x/runs/9"},
                                 {"name": "lint", "bucket": "pass", "link": "https://x/runs/8"}])
        text = pw.line(s, "fix-ci")
        self.assertIn("failing build https://x/runs/9", text)
        self.assertNotIn("runs/8", text)

    def test_failing_checks_json_is_kept_despite_nonzero_exit(self):
        s = self.read([], [{"name": "build", "bucket": "fail"}], checks_rc=1)
        self.assertEqual(pw.decide(s), "fix-ci")

    def test_gh_failure_raises(self):
        orig, pw.gh = pw.gh, lambda a: (1, "", "boom")
        try:
            with self.assertRaises(RuntimeError):
                pw.read_state(7, "o/r", [], 0)
        finally:
            pw.gh = orig


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
        self.assertEqual(d["prs"][1]["failing"], [{"name": "x", "link": "L"}])


if __name__ == "__main__":
    unittest.main()
