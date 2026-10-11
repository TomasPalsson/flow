#!/usr/bin/env python3
"""Unit tests for mcp_eval.py with a mocked client. Run: python3 -I test_mcp_eval.py"""
import os
import re
import sys
import unittest
from types import SimpleNamespace as NS

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mcp_eval  # noqa: E402


def tool_use(i, name="lookup", inp=None):
    return NS(type="tool_use", id=i, name=name, input=inp or {})


def text(t):
    return NS(type="text", text=t)


class Client:
    """Replays scripted responses and snapshots each request's messages."""

    def __init__(self, scripted):
        self.scripted = list(scripted)
        self.requests = []
        self.messages = self

    def create(self, **kw):
        self.requests.append(dict(kw, messages=list(kw["messages"])))
        return self.scripted.pop(0)


def resp(blocks, stop="tool_use"):
    return NS(content=blocks, stop_reason=stop)


class McpEvalTest(unittest.TestCase):
    def test_two_tool_use_blocks_get_two_tool_results(self):
        c = Client([
            resp([tool_use("a1"), tool_use("b2")]),
            resp([text("<response>42</response>")], "end_turn"),
        ])
        calls = []
        out = mcp_eval.run_task(c, "m", [], {"question": "q"},
                                lambda n, i: (calls.append(n) or ("r-" + n, False)))
        second = c.requests[1]["messages"][-1]
        self.assertEqual(second["role"], "user")
        ids = [b["tool_use_id"] for b in second["content"]]
        self.assertEqual(ids, ["a1", "b2"])
        self.assertTrue(all(b["type"] == "tool_result" for b in second["content"]))
        self.assertEqual(len(calls), 2)
        self.assertEqual(out["response"], "42")

    def test_turn_cap_stops_a_looping_model(self):
        c = Client([resp([tool_use("x%d" % i)]) for i in range(5)])
        out = mcp_eval.run_task(c, "m", [], {"question": "q"}, lambda n, i: ("r", False), max_turns=3)
        self.assertEqual(out["status"], "max_turns")
        self.assertEqual(len(c.requests), 3)

    def test_tool_error_is_flagged_not_raised(self):
        c = Client([resp([tool_use("e1")]), resp([text("<response>NOT_FOUND</response>")], "end_turn")])
        mcp_eval.run_task(c, "m", [], {"question": "q"}, lambda n, i: ("boom", True))
        self.assertTrue(c.requests[1]["messages"][-1]["content"][0]["is_error"])

    def test_feedback_tag_is_captured(self):
        c = Client([resp([text("<feedback>name is vague</feedback><response>7</response>")], "end_turn")])
        out = mcp_eval.run_task(c, "m", [], {"question": "q"}, lambda n, i: ("", False))
        self.assertEqual(out["feedback"], "name is vague")

    def test_grade_answer_and_end_state(self):
        ok = {"status": "answered", "response": "7"}
        self.assertTrue(mcp_eval.grade({"answer": "7"}, ok)[0])
        self.assertFalse(mcp_eval.grade({"answer": "8"}, ok)[0])
        self.assertTrue(mcp_eval.grade({"check": [sys.executable, "-c", "pass"]}, ok)[0])
        self.assertFalse(mcp_eval.grade({"check": [sys.executable, "-c", "raise SystemExit(3)"]}, ok)[0])
        self.assertFalse(mcp_eval.grade({"answer": "7"}, {"status": "max_turns", "response": None})[0])

    def test_run_all_parallel_and_rejects_ungradable_task(self):
        c = Client([resp([text("<response>1</response>")], "end_turn"),
                    resp([text("<response>2</response>")], "end_turn")])
        res = mcp_eval.run_all(c, "m", [], [{"question": "a", "answer": "1"}, {"question": "b", "answer": "2"}],
                               lambda n, i: ("", False), workers=1)
        self.assertEqual([r["passed"] for r in res], [True, True])
        with self.assertRaises(ValueError):
            mcp_eval.run_all(c, "m", [], [{"question": "no criterion"}], lambda n, i: ("", False))

    def test_candidate_prompt_names_no_grading(self):
        self.assertIsNone(re.search(r"eval|judge|test", mcp_eval.CANDIDATE_PROMPT, re.I))

    def test_model_flag_is_required_and_has_no_default(self):
        with open(mcp_eval.__file__) as f:
            src = f.read()
        self.assertIsNone(re.search(r"claude-[a-z0-9.-]*\d{8}", src), "no dated model id in the script")
        with self.assertRaises(SystemExit):
            mcp_eval.main(["--tools", "t", "--tasks", "k", "--call", "c"])


if __name__ == "__main__":
    unittest.main()
