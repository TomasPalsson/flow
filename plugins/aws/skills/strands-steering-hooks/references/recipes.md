---
name: recipes
description: Copy-paste production-ready Strands steering-hook recipes — human-in-the-loop approval, PII redaction, tool budgets, debounce/loop-breaking, dynamic tool filtering, dry-run tool swap, result transform/retry, autonomous resume loops, multi-agent node guard, and observability. Load when implementing a specific steering behavior.
---

# Steering-hook recipes (production patterns)

Each recipe is self-contained and uses current imports (`from strands.hooks import ...`).
Adapt names to your tools. Most are `HookProvider`s so they bundle cleanly.

## 1. Human-in-the-loop approval (pause → human → resume)

```python
from strands.hooks import HookProvider, HookRegistry, BeforeToolCallEvent

class Approval(HookProvider):
    def __init__(self, guarded: set[str]): self.guarded = guarded
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(BeforeToolCallEvent, self.gate)
    def gate(self, event: BeforeToolCallEvent):
        if event.tool_use["name"] not in self.guarded:
            return
        # remember a "trust always" decision so we don't re-prompt
        if event.agent.state.get(f"trust:{event.tool_use['name']}"):
            return
        answer = event.interrupt("approval", reason=event.tool_use["input"])
        if answer == "always":
            event.agent.state.set(f"trust:{event.tool_use['name']}", True)
        elif str(answer).lower() != "y":
            event.cancel_tool = "Denied by operator."

agent = Agent(tools=[send_payment], hooks=[Approval({"send_payment"})])

# caller drives the resume loop:
result = agent("pay vendor X $500")
while result.stop_reason == "interrupt":
    responses = []
    for i in result.interrupts:
        ans = input(f"Approve {i.reason}? (y / always / n): ")
        responses.append({"interruptResponse": {"interruptId": i.id, "response": ans}})
    result = agent(responses)
```

## 2. PII redaction on input (once per request)

```python
import re
from strands.hooks import HookProvider, HookRegistry, BeforeInvocationEvent
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
SSN   = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")

class RedactInput(HookProvider):
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(BeforeInvocationEvent, self.redact)
    def redact(self, event: BeforeInvocationEvent):
        for msg in event.messages or []:          # event.messages, NOT event.agent.messages
            for block in msg.get("content", []):
                if "text" in block:
                    block["text"] = SSN.sub("[SSN]", EMAIL.sub("[EMAIL]", block["text"]))
```
Run before any memory/session hook by registering at a lower `HookOrder` (e.g.
`order=HookOrder.INTERVENTION_OUTPUT`) so PII never reaches storage first.

## 3. Per-request tool budget

```python
from strands.hooks import HookProvider, HookRegistry, BeforeInvocationEvent, BeforeToolCallEvent

class ToolBudget(HookProvider):
    def __init__(self, max_calls=10): self.max_calls = max_calls
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(BeforeInvocationEvent, self._reset)
        registry.add_callback(BeforeToolCallEvent, self._enforce)
    def _reset(self, event):                      # per-request counter in invocation_state
        event.invocation_state["tool_calls"] = 0
    def _enforce(self, event: BeforeToolCallEvent):
        n = event.invocation_state.get("tool_calls", 0) + 1
        event.invocation_state["tool_calls"] = n
        if n > self.max_calls:
            event.cancel_tool = (f"Tool budget {self.max_calls} reached. "
                                 "Answer with what you have; stop calling tools.")
```
Keep the counter in `invocation_state`, not `self`, so concurrent requests don't collide.

## 4. Debounce / loop-breaker (kill repeated identical calls)

```python
from strands.hooks import HookProvider, HookRegistry, BeforeInvocationEvent, BeforeToolCallEvent

class Debounce(HookProvider):
    def __init__(self, window=3): self.window = window
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(BeforeInvocationEvent, lambda e: e.invocation_state.update(_hist=[]))
        registry.add_callback(BeforeToolCallEvent, self.check)
    def check(self, event: BeforeToolCallEvent):
        hist = event.invocation_state.setdefault("_hist", [])
        key = (event.tool_use["name"], str(event.tool_use["input"]))
        if hist[-self.window:].count(key) >= 2:
            event.cancel_tool = "BLOCKED: duplicate call — try a different approach."
            return
        hist.append(key)
```

## 5. Dynamic tool filtering per turn (role-based)

```python
from strands.hooks import HookProvider, HookRegistry, BeforeModelCallEvent

class RoleTools(HookProvider):
    def __init__(self, hidden_for_nonadmin: set[str]): self.hidden = hidden_for_nonadmin
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(BeforeModelCallEvent, self.filter_tools)
    def filter_tools(self, event: BeforeModelCallEvent):
        if event.invocation_state.get("role") == "admin":
            return
        event.tool_specs = [s for s in event.tool_specs
                            if s.get("toolSpec", {}).get("name") not in self.hidden]
# usage: agent("...", role="viewer")
```
This controls model *intent* (what it can choose), not execution — pair with `cancel_tool`
for hard enforcement. (For real policy, prefer an Intervention `Deny`.)

## 6. Inject ephemeral per-turn context (not persisted to history)

```python
from strands.hooks import HookProvider, HookRegistry, BeforeModelCallEvent
import datetime

class ClockContext(HookProvider):
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(BeforeModelCallEvent, self.inject)
    def inject(self, event: BeforeModelCallEvent):
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        event.messages.append({"role": "user",
                               "content": [{"text": f"[context] now={now}"}]})
```
Mutating `event.messages` here is per-call only; it does not pollute `agent.messages`.

## 7. Dry-run tool swap (shadow mode)

```python
from strands import tool
from strands.hooks import HookProvider, HookRegistry, BeforeToolCallEvent

@tool
def write_file_dryrun(path: str, content: str) -> str:
    return f"[dry-run] would write {len(content)} bytes to {path}"

class DryRun(HookProvider):
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(BeforeToolCallEvent, self.swap)
    def swap(self, event: BeforeToolCallEvent):
        if event.tool_use["name"] == "write_file":
            event.selected_tool = write_file_dryrun   # model never knows
```

## 8. Result transform + bounded retry

```python
from strands.hooks import HookProvider, HookRegistry, AfterToolCallEvent

class ResilientResults(HookProvider):
    MAX, CAP = 2, 8000
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(AfterToolCallEvent, self.post)
    def post(self, event: AfterToolCallEvent):
        tid = event.tool_use.get("toolUseId", "")
        tries = event.invocation_state.get(f"try:{tid}", 0)
        if event.result.get("status") == "error" and tries < self.MAX:
            event.invocation_state[f"try:{tid}"] = tries + 1
            event.retry = True; return            # re-run same tool (counter prevents infinite loop)
        for block in event.result.get("content", []):     # truncate oversized output
            if "text" in block and len(block["text"]) > self.CAP:
                block["text"] = block["text"][:self.CAP] + "\n[truncated]"
```
If you stream to a UI, remember chunks from the discarded attempt were already emitted — make
the consumer retry-aware.

## 9. Autonomous resume loop (critic / refine), bounded

```python
from strands.hooks import HookProvider, HookRegistry, AfterInvocationEvent

class Critique(HookProvider):
    def __init__(self, rounds=2): self.rounds = rounds
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(AfterInvocationEvent, self.again)
    def again(self, event: AfterInvocationEvent):
        n = event.invocation_state.get("_round", 0)
        if n < self.rounds and event.result:
            event.invocation_state["_round"] = n + 1
            event.resume = f"Critique and improve your answer (round {n+1}/{self.rounds})."
# caller still gets ONE AgentResult; the agent looped internally.
```

## 10. Lightweight observability (latency + counts)

```python
import time, uuid
from strands.hooks import (HookProvider, HookRegistry, BeforeInvocationEvent,
                           AfterInvocationEvent, AfterModelCallEvent, AfterToolCallEvent)

class Observe(HookProvider):
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(BeforeInvocationEvent, self._start)
        registry.add_callback(AfterModelCallEvent,   lambda e: e.invocation_state.__setitem__(
            "models", e.invocation_state.get("models", 0) + 1))
        registry.add_callback(AfterToolCallEvent,    lambda e: e.invocation_state.__setitem__(
            "tools", e.invocation_state.get("tools", 0) + 1))
        registry.add_callback(AfterInvocationEvent,  self._end)
    def _start(self, e): e.invocation_state.update(rid=uuid.uuid4().hex[:8], t0=time.perf_counter())
    def _end(self, e):
        s = e.invocation_state
        print(f"[{s['rid']}] {time.perf_counter()-s['t0']:.2f}s "
              f"models={s.get('models',0)} tools={s.get('tools',0)}")
```
For standard distributed tracing use `StrandsTelemetry` (OpenTelemetry) — hooks are for the
business metrics OTel doesn't emit.

## 11. Node-level cancel in a Graph / Swarm (multi-agent)

```python
from strands.hooks import HookProvider, HookRegistry, BeforeNodeCallEvent

class NodeGuard(HookProvider):
    def __init__(self, blocked_nodes: set[str]): self.blocked = blocked_nodes
    def register_hooks(self, registry: HookRegistry, **kw):
        registry.add_callback(BeforeNodeCallEvent, self.gate)
    def gate(self, event: BeforeNodeCallEvent):
        if event.node_id in self.blocked:
            event.cancel_node = f"Node '{event.node_id}' is disabled by policy."
        # HITL at the node level: event.interrupt("review-node", reason={"node": event.node_id})
```

**Register on the orchestrator, not the child agents** — multi-agent events fire on the
`Graph`/`Swarm`, not on individual `Agent`s:

```python
graph.hooks.add_callback(BeforeNodeCallEvent, NodeGuard({"reviewer"}).gate)
# or build the orchestrator with hooks=[NodeGuard({"reviewer"})]
```

`BeforeNodeCallEvent` (writable `cancel_node`, plus `interrupt()`) and `AfterNodeCallEvent`
import from `strands.hooks` — the `strands.experimental.hooks.multiagent` path is deprecated.

## Server deployment note (matches this repo's `agent/main.py`)

Build the `Agent` (and its hook/handler instances) **per request**, not once at startup, so
provider instance state can't leak across users. Pass per-request context as kwargs —
`agent("q", user_id=uid, db=conn)` — and read it from `event.invocation_state` inside hooks.
