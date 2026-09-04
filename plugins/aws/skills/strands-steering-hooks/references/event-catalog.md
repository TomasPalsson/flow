---
name: event-catalog
description: Complete Strands hook event reference — every single-agent, multi-agent, and bidi event with fire timing, attributes, writable fields, the lifecycle firing order, and the legacy→current name migration map. Load before relying on an event's exact attributes.
---

# Strands Hook Event Catalog (source-verified, SDK HEAD ≈ post-1.44.0)

All stable events import from `strands.hooks`. Writable fields are enforced by each event's
`_can_write()` allowlist — assigning any other attribute raises
`AttributeError: Property <name> is not writable`. "Reverse" = callbacks run in reverse
registration order **within each `HookOrder` group** (LIFO teardown).

## Single-agent events (`strands.hooks`)

| Event | Fires | Reverse | Key attributes | Writable |
|---|---|---|---|---|
| `AgentInitializedEvent` | once, after `Agent.__init__` | no | `agent` | none |
| `BeforeInvocationEvent` | start of each request (`__call__`/`stream_async`/structured) | no | `agent`, `messages`, `invocation_state`, `cancel` | `messages`, `cancel` |
| `AfterInvocationEvent` | end of each request | **yes** | `agent`, `invocation_state`, `result` (AgentResult\|None), `resume` | `resume` only (**`result` read-only**) |
| `MessageAddedEvent` | every message appended (user/assistant/tool) | no | `agent`, `message` | none |
| `BeforeModelCallEvent` | before each model inference | no | `agent`, `invocation_state`, `cancel`, `messages`, `tool_specs` | `cancel` (also mutate `messages`/`tool_specs` lists in place) |
| `AfterModelCallEvent` | after each model inference | **yes** | `agent`, `invocation_state`, `stop_response`, `exception`, `retry` | `retry` |
| `BeforeToolCallEvent` | before each tool call | no | `agent`, `tool_use`, `invocation_state`, `selected_tool`, `cancel_tool`; `interrupt()` | `cancel_tool`, `selected_tool`, `tool_use` |
| `AfterToolCallEvent` | after each tool call | **yes** | `agent`, `tool_use`, `selected_tool`, `invocation_state`, `result`, `exception`, `retry` | `result`, `retry` |

Notes:
- `tool_use` is a dict: `{"name": str, "toolUseId": str, "input": dict}`. Mutate `input` in
  place to rewrite args; set `tool_use["name"]` (without `selected_tool`) to re-resolve a tool
  by name from the registry.
- `AfterToolCallEvent.result` is a `ToolResult` TypedDict:
  `{"content": list, "status": "success"|"error", "toolUseId": str}`. Reassigning it (or
  mutating `content`) changes exactly what the model sees.
- `AfterModelCallEvent`'s writable field is named **`retry`** (the docstring prose says
  "retry_model" — that's wrong; the attribute is `retry`).
- `cancel`/`cancel_tool` accept `True` or a `str` message surfaced to the model.
- `BeforeModelCallEvent.cancel` / `AfterModelCallEvent.retry` are **not** fired by the
  *deprecated* `Agent.structured_output()` method, but **are** fired on the modern path
  (passing `structured_output_model=` to `__call__`/`stream_async`).

## Multi-agent events (`strands.hooks`, for `Graph`/`Swarm`)

| Event | Fires | Reverse | Writable / interrupt |
|---|---|---|---|
| `MultiAgentInitializedEvent` | orchestrator built | no | none |
| `BeforeMultiAgentInvocationEvent` | orchestration starts | no | none |
| `AfterMultiAgentInvocationEvent` | orchestration ends | yes | none |
| `BeforeNodeCallEvent` | before a node runs | no | `cancel_node`; `interrupt()` |
| `AfterNodeCallEvent` | after a node runs | yes | none |

Register on the orchestrator: `graph.hooks.add_callback(BeforeNodeCallEvent, fn)`. The legacy
path `strands.experimental.hooks.multiagent` is **deprecated** (emits `DeprecationWarning`).

## Bidirectional-streaming events (`strands.experimental.hooks`, EXPERIMENTAL)

For `BidiAgent` only. **All bidi callbacks must be `async def`** — a sync callback blocks the
streaming loop. Nine classes: `BidiAgentInitializedEvent`, `BidiBeforeInvocationEvent`,
`BidiAfterInvocationEvent`, `BidiMessageAddedEvent`, `BidiBeforeToolCallEvent`,
`BidiAfterToolCallEvent`, `BidiInterruptionEvent`, `BidiBeforeConnectionRestartEvent`,
`BidiAfterConnectionRestartEvent`. `BidiAfterToolCallEvent.result` is writable but there is
**no `retry`** field, and bidi tool events are **not** `_Interruptible`.

## Lifecycle firing order (single invocation, one tool round-trip)

```
agent("...")  ─► BeforeInvocationEvent            [cancel, messages]
                 MessageAddedEvent  (user msg)
                 ┌── model loop ──────────────────────────────────
                 │   BeforeModelCallEvent          [cancel]
                 │   AfterModelCallEvent  (reverse) [retry]
                 │   MessageAddedEvent  (assistant)
                 │   ── if stop_reason == "tool_use": ──
                 │      BeforeToolCallEvent         [cancel_tool, selected_tool, tool_use, interrupt()]
                 │      AfterToolCallEvent (reverse)[result, retry]
                 │      MessageAddedEvent  (tool result)
                 │      (loop back to BeforeModelCallEvent)
                 └────────────────────────────────────────────────
              ─► AfterInvocationEvent  (reverse)    [resume]
```

`BeforeModelCallEvent`/`AfterModelCallEvent` fire **once per model turn** — an agentic loop
fires them many times per request. Scan user input once at `BeforeInvocationEvent` instead.

## Interrupts (human-in-the-loop)

`event.interrupt(name: str, reason: Any = None, response: Any = None)` is available on
`BeforeToolCallEvent` and `BeforeNodeCallEvent` (they inherit `_Interruptible`).

Two-phase semantics: on the **first** pass `interrupt()` suspends the run, so the `agent(...)`
call returns an `AgentResult` with `stop_reason == "interrupt"` and a populated
`interrupts: Sequence[Interrupt]` (each has `.id`, `.name`, `.reason`). When you resume, the
**same hook re-runs** and this time `interrupt()` **returns the caller-supplied `response`
value** (exactly what you put in `interruptResponse.response` — compare against that value/type,
not a parsed string). Resume by calling the agent with a list of response dicts:

```python
result = agent(prompt)
while result.stop_reason == "interrupt":
    responses = [
        {"interruptResponse": {"interruptId": i.id, "response": get_human_answer(i)}}
        for i in result.interrupts
    ]
    result = agent(responses)
```

A `@tool` can raise the same kind of interrupt via `tool_context.interrupt(...)`
(use `@tool(context=True)`), which is cleaner when the approval threshold depends on the
tool's own arguments.

## State surfaces

| Surface | Scope | Persisted | Use for |
|---|---|---|---|
| `event.invocation_state` (dict) | one request | no | cross-hook flags, counters, trace ids, non-serializable per-request objects (db conns, loggers) |
| `event.agent.state` (`.get/.set/.delete`) | across invocations | yes (with a `SessionManager`); JSON only | trust levels, cumulative budgets, user prefs |
| instance attrs on the provider (`self.x`) | lifetime of the instance | no | **danger** — leaks across concurrent requests; avoid for per-request state |

Semi-private escape hatch: `event.invocation_state.setdefault("request_state", {})
["stop_event_loop"] = True` terminates the agent loop immediately (useful when `cancel_tool`
alone isn't enough, e.g. models that keep retrying a cancelled tool). Undocumented — pin your
SDK version if you depend on it.

## Migration map (old → current)

| If you see (old / training memory) | Use now |
|---|---|
| `BeforeToolInvocationEvent` / `AfterToolInvocationEvent` | `BeforeToolCallEvent` / `AfterToolCallEvent` |
| `BeforeModelInvocationEvent` / `AfterModelInvocationEvent` | `BeforeModelCallEvent` / `AfterModelCallEvent` |
| `from strands.experimental.hooks import Before*` | `from strands.hooks import Before*` |
| `from strands.experimental.hooks.multiagent import ...` | `from strands.hooks import ...` |
| `from strands.experimental.steering import ...` | `from strands.vended_plugins.steering import ...` |

The `*InvocationEvent` names still exist as aliases in `strands.experimental.hooks` but emit
`DeprecationWarning`. Confirm against the installed version with
`scripts/introspect_strands_hooks.py`.
