#!/usr/bin/env python3
"""
mcp_eval.py - run question tasks against a tool server and grade the end state.

The model sees the server's tool definitions and answers each task. Every
tool_use block in a turn is answered in the next request (a turn with two
parallel tool calls needs two tool_result blocks, or the API rejects the
request). Turns are capped. Tasks run in parallel.

Inputs (JSON files, no server code is read):
  --tools  the tool list in Anthropic format: [{name, description, input_schema}]
  --tasks  [{"question": "...", "answer": "exact string", "check": ["cmd", "arg"]}]
           answer is compared by exact string against the <response> tag; use
           "NOT_FOUND" for a question the data cannot answer. check is an argv
           list run after the task with no shell; exit 0 passes (grades the end
           state of a tool that writes). A task needs at least one of the two.
  --call   argv that runs one tool call: reads {"name", "input"} as JSON on
           stdin, prints the result text on stdout. Wrap your server client in it.
  --model  required, no default: a pinned model id goes stale, so the caller
           names the one under test.

Needs the anthropic SDK for a real run (pip install anthropic); the unit tests
need only the standard library.

Credit: adapted from anthropics/skills mcp-builder/reference/evaluation.md @ dbd4588 (Apache-2.0).
"""
import argparse
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

# The candidate sees only this. It names no grading, judging or checking, so the
# model behaves as it would for a user. Keep those words out when editing it.
CANDIDATE_PROMPT = """You are an assistant with access to tools.

Use the tools to complete the task you are given. Reply in three tagged parts:
<summary> the steps you took, which tools you used and why </summary>
<feedback> comments on the tools: unclear names, unclear parameters, errors you hit, responses that were too long </feedback>
<response> the final answer only: just the number for a count, just the ID for an ID, the exact text for a name </response>

If the tools cannot give you the answer, put NOT_FOUND inside <response>."""

TAG = re.compile(r"<(response|feedback)>(.*?)</\1>", re.S)


def block_field(block, name):
    """Read a field from an SDK block object or a plain dict."""
    if isinstance(block, dict):
        return block.get(name)
    return getattr(block, name, None)


def parse_tags(text):
    out = {"response": None, "feedback": None}
    for name, body in TAG.findall(text or ""):
        out[name] = body.strip()
    return out


def run_tool(call_argv, name, tool_input, timeout):
    """One tool call through the adapter. Returns (text, is_error)."""
    payload = json.dumps({"name": name, "input": tool_input})
    try:
        p = subprocess.run(call_argv, input=payload, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return "tool call failed: %s" % e, True
    if p.returncode != 0:
        return "tool call failed (exit %d): %s" % (p.returncode, p.stderr.strip()[-500:]), True
    return p.stdout, False


def run_task(client, model, tools, task, call_tool, max_turns=20, max_tokens=4096):
    """Drive one task. call_tool(name, input) -> (text, is_error)."""
    messages = [{"role": "user", "content": task["question"]}]
    names = []
    for turn in range(1, max_turns + 1):
        resp = client.messages.create(
            model=model, max_tokens=max_tokens, system=CANDIDATE_PROMPT,
            messages=messages, tools=tools,
        )
        messages.append({"role": "assistant", "content": resp.content})
        # Answer every tool_use block, not the first: parallel calls arrive together.
        uses = [b for b in resp.content if block_field(b, "type") == "tool_use"]
        if not uses:
            text = "".join(block_field(b, "text") or "" for b in resp.content if block_field(b, "type") == "text")
            tags = parse_tags(text)
            return {"turns": turn, "tools": names, "status": "answered",
                    "response": tags["response"], "feedback": tags["feedback"]}
        results = []
        for u in uses:
            name = block_field(u, "name")
            names.append(name)
            body, is_err = call_tool(name, block_field(u, "input") or {})
            r = {"type": "tool_result", "tool_use_id": block_field(u, "id"), "content": body}
            if is_err:
                r["is_error"] = True
            results.append(r)
        messages.append({"role": "user", "content": results})
    return {"turns": max_turns, "tools": names, "status": "max_turns", "response": None, "feedback": None}


def grade(task, outcome):
    """Pass when every criterion the task names holds. Returns (passed, reasons)."""
    reasons = []
    if "answer" in task and outcome["response"] != task["answer"]:
        reasons.append("answer %r != expected %r" % (outcome["response"], task["answer"]))
    if "check" in task:
        try:
            rc = subprocess.run(task["check"], capture_output=True, text=True, timeout=120).returncode
        except (OSError, subprocess.TimeoutExpired) as e:
            reasons.append("end-state check failed to run: %s" % e)
        else:
            if rc != 0:
                reasons.append("end-state check exited %d" % rc)
    if outcome["status"] != "answered":
        reasons.append("no final answer: " + outcome["status"])
    return (not reasons), reasons


def run_all(client, model, tools, tasks, call_tool, workers=4, max_turns=20):
    for t in tasks:
        if "answer" not in t and "check" not in t:
            raise ValueError("task needs an answer or a check: %r" % t.get("question"))

    def one(t):
        outcome = run_task(client, model, tools, t, call_tool, max_turns=max_turns)
        passed, reasons = grade(t, outcome)
        return dict(outcome, question=t["question"], passed=passed, reasons=reasons)

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        return list(ex.map(one, tasks))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--tools", required=True)
    ap.add_argument("--tasks", required=True)
    ap.add_argument("--call", required=True, help="tool adapter command (argv, split on spaces)")
    ap.add_argument("--model", required=True)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--max-turns", type=int, default=20)
    ap.add_argument("--tool-timeout", type=int, default=60)
    a = ap.parse_args(argv)
    try:
        import anthropic
    except ImportError:
        print("mcp_eval: the anthropic SDK is not installed (pip install anthropic)", file=sys.stderr)
        return 2
    with open(a.tools) as f:
        tools = json.load(f)
    with open(a.tasks) as f:
        tasks = json.load(f)
    call_argv = a.call.split()
    results = run_all(anthropic.Anthropic(), a.model, tools, tasks,
                      lambda n, i: run_tool(call_argv, n, i, a.tool_timeout),
                      workers=a.workers, max_turns=a.max_turns)
    passed = sum(1 for r in results if r["passed"])
    json.dump({"model": a.model, "passed": passed, "total": len(results), "results": results}, sys.stdout, indent=2)
    print()
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
