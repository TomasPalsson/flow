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

    def test_no_checks_is_done_when_ci_is_not_expected(self):
        self.check("done", checks=[])
        self.check("done", checks=[], expect_ci=False, empty_polls=9)

    def test_no_checks_waits_when_ci_is_expected(self):
        self.check("wait", checks=[], expect_ci=True, empty_polls=0)
        self.check("wait", checks=[], expect_ci=True, empty_polls=2)

    def test_no_checks_after_three_polls_stops(self):
        self.check("stop-no-checks", checks=[], expect_ci=True, empty_polls=3)

    def test_red_check_beats_the_empty_rule(self):
        self.check("fix-ci", checks=red("x"), expect_ci=True, empty_polls=5)

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


class ExpectCi(unittest.TestCase):
    def tree(self, files):
        import tempfile
        d = tempfile.mkdtemp()
        self.addCleanup(__import__("shutil").rmtree, d)
        os.makedirs(os.path.join(d, ".github", "workflows"))
        for name, body in files.items():
            with open(os.path.join(d, ".github", "workflows", name), "w") as f:
                f.write(body)
        return d

    def test_pull_request_trigger_expects_ci(self):
        for body in ("on: pull_request\n", "on: [push, pull_request]\n",
                     "on:\n  push:\n    branches: [main]\n  pull_request:\n    branches: [main]\n",
                     "on:\n  pull_request_target:\n"):
            self.assertTrue(pw.detect_expect_ci(self.tree({"ci.yml": body})), body)

    def test_push_only_workflow_does_not(self):
        d = self.tree({"ci.yml": "on:\n  push:\n    branches: [main]\n"
                                 "jobs:\n  a:\n    if: github.event_name == 'pull_request'\n"})
        self.assertFalse(pw.detect_expect_ci(d))

    def test_no_workflows_does_not(self):
        import tempfile
        self.assertFalse(pw.detect_expect_ci(tempfile.mkdtemp()))

    def test_flag_overrides_detection(self):
        view = {"number": 7, "state": "OPEN", "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN", "reviewDecision": ""}
        orig, pw.gh = pw.gh, FakeGh(view, [], [])
        try:
            self.assertTrue(pw.read_state(7, None, [], 0, True)["expect_ci"])
            self.assertFalse(pw.read_state(7, None, [], 0, False)["expect_ci"])
        finally:
            pw.gh = orig

    def run_main(self, extra):
        orig = (pw.read_state, pw.time.sleep)
        seen = []
        pw.read_state = lambda p, r, f, n, e=None: pr(number=7, checks=[], expect_ci=bool(e))
        pw.time.sleep = lambda n: seen.append(n)
        out, err = io.StringIO(), io.StringIO()
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc = pw.main(["7", "--interval", "1"] + ([] if "--no-expect-ci" in extra else ["--expect-ci"]) + extra)
        finally:
            pw.read_state, pw.time.sleep = orig
        self.err = err.getvalue()
        return rc, seen, out.getvalue()

    def test_poll_loop_stops_after_three_empty_polls(self):
        rc, sleeps, out = self.run_main([])
        self.assertEqual((rc, len(sleeps)), (2, 3))
        self.assertIn("no checks registered after 3 polls; workflow filters may exclude this PR", self.err)

    def test_once_with_no_checks_waits(self):
        rc, sleeps, _ = self.run_main(["--once"])
        self.assertEqual((rc, sleeps), (3, []))

    def test_flags_are_accepted(self):
        self.assertEqual(self.run_main([])[0], 2)
        self.assertEqual(self.run_main(["--no-expect-ci"])[0], 0)

    def test_json_stdout_stays_parseable_on_stop_no_checks(self):
        rc, _, out = self.run_main(["--json"])
        self.assertEqual(rc, 2)
        for ln in out.splitlines():
            json.loads(ln)

    def test_step_name_outside_on_block_does_not_expect_ci(self):
        d = self.tree({"ci.yml": "on:\n  push:\njobs:\n  a:\n    steps:\n      - name: Label pull_request\n"})
        self.assertFalse(pw.detect_expect_ci(d))


if __name__ == "__main__":
    unittest.main()
