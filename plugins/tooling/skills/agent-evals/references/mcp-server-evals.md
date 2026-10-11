# Evaluating an MCP server's tools

An MCP server is good when a model with no inside knowledge picks the right tool, fills the arguments correctly and reaches the right answer. Reading the server code cannot tell you that. This method measures it with questions the data can settle.

## 1. Author the questions blind

Write the questions from the API documentation and the tool list (names, schemas, descriptions) only. Do not read the server's implementation. Why: a question written with the code open mirrors what the code makes easy, and the eval then passes for the wrong reason. Explore the live data with read-only calls and small `limit` values, so one tool cannot flood the context.

## 2. Closed data, one checkable answer

- Ask about finished things: a closed ticket, an ended thread, a fixed time window. "How many open issues" changes under you and turns every later run into noise.
- The answer is one value that exact string comparison can grade: an ID, a name, a number, a date in a stated format, true or false. Say the format in the question ("Use YYYY/MM/DD").
- Prefer readable answers over opaque IDs for most questions; mix the kinds so one parsing habit cannot pass them all.
- Include a few questions the data cannot answer, with the expected answer `NOT_FOUND`. A tool set that invents an answer must fail these.
- Make the questions hard: several tool calls, filtering, a join across two tools. A question one keyword search solves measures nothing.
- A tool that writes state is graded on the end state, not on the model's description of it: give the task a `check` command that reads the state back.

## 3. Collect tool feedback in the same run

The candidate prompt asks for `<feedback>` on tool names, parameters, errors and oversized responses. Read it across all runs: a complaint that appears in several runs points to a tool description to rewrite (see `agent-architecture/references/tool-design.md`). Treat one-off complaints as noise.

## 4. Run it with the fixed harness

`scripts/mcp_eval.py --tools tools.json --tasks tasks.json --call "<adapter>" --model <id>` runs the tasks in parallel and prints per-task pass, turns, tools used and feedback. The harness rules are what keep the numbers comparable:

- It answers every `tool_use` block in a turn. A reference harness that answers only the first block leaves parallel calls without a result and the next request fails or silently drops them.
- Turns are capped (`--max-turns`), so a looping model costs a bounded amount and is reported as `max_turns`.
- `--model` has no default. A pinned default goes stale; name the model under test and record it with the result.
- The candidate system prompt contains no words about grading, judging or testing (the unit test checks this). A model told it is being graded behaves differently from one serving a user.
- The adapter (`--call`) wraps your server client: it reads `{"name", "input"}` on stdin and prints the result text. The tools file is the `tools/list` output in Anthropic format (`name`, `description`, `input_schema`).

`tasks.json` is a list of `{"question", "answer"}` or `{"question", "check": ["argv", ...]}`; the file is yours and `check` runs without a shell.

## 5. Read the result

Run each task more than once before trusting a single pass or fail; model noise is large at ten tasks. For whether a change in the pass rate is real, load `statistics-and-cost.md`. Before comparing two server versions, read `eval-audit.md`.

Run the harness's own tests with `python3 -I scripts/test_mcp_eval.py`.

Credit: adapted from anthropics/skills mcp-builder/reference/evaluation.md @ dbd4588 (Apache-2.0).
