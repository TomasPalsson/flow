# Mode B — Agent team

Use when slices are independent and benefit from durable, coordinating contexts. Backed by **TeamCreate + Task\* + SendMessage**.

1. **Create the team** (its task list is created with it):
   `TeamCreate({team_name: "flow-build", description: "Build <feature> end to end"})`
2. **One task per build slice**, plus one per review lens — exactly `correctness` and `gaming` per slice at step 4 (the pair `build-slices` is pinned to), all four at step 5 — with dependency edges:
   `TaskCreate({subject: "Slice 1: walking skeleton", description: "<brief path from slice-brief + behavior IDs + execution-prompt.md §2-§4 ref>"})`
   then `TaskUpdate({taskId: "2", addBlockedBy: ["1"]})` to enforce slice order — skeleton before the rest.
3. **Spawn named teammates** via the Agent tool with `team_name` + `name`, matching agent type to the work. Implementers need full capability (`general-purpose`); a reviewer can be read-only. Pin `model` on every spawn.
   `Agent({team_name: "flow-build", name: "builder", subagent_type: general-purpose, model: sonnet, prompt: "<role + execution-prompt.md + the TDD invariants>. For every slice you claim, run ${CLAUDE_PLUGIN_ROOT}/scripts/slice-brief on the plan for that slice number and work from the brief only — do not re-derive naming, module boundaries or error shapes a contract block already fixes."})`
   A typical roster: **builder** (claims slices in ID order, Red/Green/Refactor each), **reviewer** (claims lens tasks once a slice's diff exists — never reviews a slice it built), **verifier** (collates results for the orchestrator's gate; does NOT approve).
4. **Coordinate by message, not by terminal.** Teammates report progress and blockers via `SendMessage` (by name). They claim unblocked tasks in ID order with `TaskUpdate({taskId: "<id>", owner: "<name>"})` and finish with `TaskUpdate({taskId: "<id>", status: "completed"})` — `taskId` is required on every call.
5. **Gates stay with the orchestrator.** When builds and reviews finish, the orchestrator runs `harness check`, browser verification, and brings **user verification back to the main loop**. The team never approves on the user's behalf.
6. **Shut down** when the PR is open: `SendMessage({to, message: {type: "shutdown_request"}})` to each teammate.

## Discipline

- A builder's Red task must leave `TEST_CMD` non-zero; **the lead re-runs `TEST_CMD` itself** before accepting any slice. Red exits non-zero and Green exits zero, verified by you and not an agent's word.
- Two teammates never edit the same files concurrently. The `addBlockedBy` edges, the one-slice-per-task rule, and `slice-overlap`'s clean exit at plan time are what keep them apart.
- Scanner ≠ fixer ≠ verifier applies across teammates too: the teammate that raised a finding does not fix it, and the one that fixed it does not close it.
- Review protocol, severities, the ≥80 keep rule and the fix ladder are in `flow/review.md` — teammates read it, they do not invent a rubric.
