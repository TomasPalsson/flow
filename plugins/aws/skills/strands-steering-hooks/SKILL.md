---
name: strands-steering-hooks
description: >-
  Strands Agents (`strands-agents` Python SDK): steer — not just observe — an agent run at
  runtime. Block/redirect tool calls, rewrite tool args, override results, retry the model,
  gate on human approval, inject per-turn context, or nudge the model back on track. Also
  use to scaffold a hook/intervention/steering handler or to introspect which hook events
  the installed SDK exposes. Use whenever working with Strands hooks, interventions,
  steering, guardrails, human-in-the-loop, tool approval/blocking, PII redaction, retries,
  or agent observability. Triggers on: HookProvider, @hook, register_hooks, BeforeToolCallEvent /
  AfterToolCallEvent / Before-AfterModelCallEvent / BeforeInvocationEvent, cancel_tool,
  selected_tool, InterventionHandler, Agent(interventions=...), LLMSteeringHandler /
  SteeringHandler, strands.vended_plugins.steering, "steer don't block", event.interrupt();
  multi-agent node hooks (Graph / Swarm, BeforeNodeCallEvent, cancel_node), BidiAgent
  streaming hooks, StrandsTelemetry observability, "scaffold a Strands hook", or "how do I
  intercept/control a Strands agent".
---

# Steering Hooks in Strands

Strands lets you intercept an agent's lifecycle and **change what it does** mid-run, not
merely watch it. This skill covers the current (2026), source-verified way to do that.

> ⚠️ **The SDK ships weekly and renames things.** Your training memory is likely stale
> (e.g. the events were once `*InvocationEvent`; steering was once `experimental`). Before
> writing code, **pin the facts to the installed version**:
> ```bash
> python scripts/introspect_strands_hooks.py
> ```
> It prints the installed `strands-agents` version, every hook event with its **writable
> fields**, the `HookOrder` constants, and whether steering lives at the stable
> `strands.vended_plugins.steering` or only the deprecated `strands.experimental.steering`.
> Trust its output over this document if they disagree.

## The one idea: three layers of steering

"Steering hooks" is an umbrella for three stacked tiers. Pick the **lowest** tier that
expresses your intent cleanly — higher tiers are sugar over the same events.

```
Raw Hooks            mutate writable event fields directly      strands.hooks         Agent(hooks=[...])
   │                 maximal control, no decision typing
   ▼
Interventions        typed actions: Proceed/Deny/Guide/         strands.interventions  Agent(interventions=[...])
   │                 Confirm/Transform — ordered, short-circuit  (STABLE, Py + TS)
   ▼
Steering             LLM- or code-driven contextual guidance     strands.vended_plugins Agent(plugins=[...])
                     "steer, don't block" (Guide → retry)        .steering (STABLE, Py)
```

### Decision tree — which tier?

- **Just watch** (log, trace, metrics, audit) → raw `@hook` / `HookProvider`. (If you already
  use OpenTelemetry, prefer `StrandsTelemetry` for standard spans over hand-rolled hook tracing.)
- **Hard policy**: authorize, block a tool, require human approval → **Interventions**
  (`Deny` / `Confirm`). Stable, composable, Python + TypeScript. Default choice for guardrails.
- **Adaptive nudge**: "the model is drifting; correct it with context and let it retry" →
  **Steering** (`LLMSteeringHandler` for natural-language rules; `SteeringHandler` subclass
  for code). This is the "steer, don't block" tier.
- **Mechanical field tweak** with no real decision (cap a numeric arg, inject per-turn
  context, dedupe loops, count a budget, swap a tool) → raw hook writable fields.

Rule of thumb: anything that must be **unignorable** belongs in a hook/intervention, never
the system prompt — the model can reason around prose but never sees an interception.

**Before writing any hook, confirm three things:** (1) **policy or adaptation?** — a hard rule
→ Intervention `Deny`/`Confirm`; a "you're drifting, retry" nudge → Steering `Guide`. (2)
**must it be unignorable?** — yes → hook/intervention, not the system prompt. (3) **does it
hold per-request state?** — keep that state in `event.invocation_state`, never on `self`
(see anti-patterns #3).

## Foundation: the hook event system

### Registering hooks (three ways, all current)

```python
from strands import Agent
from strands.hooks import BeforeToolCallEvent, HookProvider, HookRegistry, HookOrder

# 1. Bare typed function — event type inferred from the annotation
def log_tool(event: BeforeToolCallEvent) -> None:
    print("calling", event.tool_use["name"])
agent = Agent(hooks=[log_tool])

# 2. HookProvider — bundle related callbacks (the workhorse)
class Guard(HookProvider):
    def register_hooks(self, registry: HookRegistry, **kwargs) -> None:
        registry.add_callback(BeforeToolCallEvent, self.check, order=HookOrder.DEFAULT)
    def check(self, event: BeforeToolCallEvent) -> None: ...
agent = Agent(hooks=[Guard()])

# 3. Plugin + @hook — shareable/distributable bundle (also auto-registers @tool, init_agent)
from strands.plugins import Plugin, hook
class GuardPlugin(Plugin):
    name = "guard"
    @hook
    def check(self, event: BeforeToolCallEvent) -> None: ...
agent = Agent(plugins=[GuardPlugin()])
```

Runtime registration: `agent.hooks.add_hook(Guard())` or
`agent.hooks.add_callback(BeforeToolCallEvent, fn)`. (Too late for `AgentInitializedEvent`,
which already fired during construction — pass it via `hooks=` instead.)

### The steering levers — writable fields per event

This table **is** how you steer with raw hooks. Each lever is one writable field on one
event; mutate it inside the callback and the SDK reads it back. Mutating any *other* field
raises `AttributeError`.

| Event (`from strands.hooks import …`) | Fires | Writable levers → effect |
|---|---|---|
| `AgentInitializedEvent` | once, post-construction | — (seed `event.agent.state` / system prompt in place) |
| `BeforeInvocationEvent` | start of each `agent(...)` | `messages` (rewrite/redact input) · `cancel` (`str`/`True` → abort request) |
| `AfterInvocationEvent` | end of request *(reverse order)* | `resume` (feed new input → agent loops again) — **`result` is read-only** |
| `MessageAddedEvent` | every message appended | — (observe only; highest-frequency event) |
| `BeforeModelCallEvent` | before each model call | `cancel` (skip this model call) — also mutate `messages`/`tool_specs` to shape the request |
| `AfterModelCallEvent` | after each model call *(reverse)* | `retry` (`True` → re-run the model call) |
| `BeforeToolCallEvent` | before each tool call | `cancel_tool` (block, send msg to model) · `selected_tool` (swap impl) · `tool_use` (rewrite name/`input`) · `event.interrupt(...)` (HITL) |
| `AfterToolCallEvent` | after each tool call *(reverse)* | `result` (override `ToolResult` the model sees) · `retry` (`True` → re-run the tool) |

Multi-agent (graphs/swarms, also in `strands.hooks`): `BeforeNodeCallEvent` (`cancel_node`,
`event.interrupt(...)`), `AfterNodeCallEvent`, `Before/AfterMultiAgentInvocationEvent`,
`MultiAgentInitializedEvent`.

Every event except `AgentInitializedEvent`/`MessageAddedEvent` carries `invocation_state` —
a per-request mutable `dict` (seeded by `agent("q", user_id="u1", db=conn)`), the right place
for cross-hook coordination and non-serializable per-request objects.

`HookOrder`: `SDK_FIRST=-100`, `INTERVENTION_OUTPUT=-90`, `DEFAULT=0`, `INTERVENTION_INPUT=90`,
`SDK_LAST=100` (lower runs first; `After*` events reverse order **within each group**).

### Steering recipe — human-in-the-loop (the one two-sided pattern)

Most levers are one-liners (mutate the field from the table). The only pattern with
caller-side control flow is interrupt + resume. `event.interrupt(name, reason=None)` **pauses
the run and returns the caller-supplied `response` value** (whatever you placed in
`interruptResponse.response` — compare against that exact value/type):

```python
def approve(event: BeforeToolCallEvent):                 # Agent(hooks=[approve])
    if event.tool_use["name"] == "issue_refund":
        answer = event.interrupt("refund", reason=event.tool_use["input"])  # pauses here
        if answer != "APPROVE":
            event.cancel_tool = "Refund not approved."

result = agent("refund order 7")
while result.stop_reason == "interrupt":                 # caller drives the resume loop
    responses = [{"interruptResponse": {"interruptId": i.id, "response": ask_human(i)}}
                 for i in result.interrupts]
    result = agent(responses)
```

**MANDATORY — READ THE ENTIRE FILE** before writing any other steering hook (block a tool,
rewrite args, override/retry a result, tool budget, debounce/loop-break, dynamic tool
filtering, PII redaction, dry-run tool swap, autonomous resume, observability):
[`references/recipes.md`](references/recipes.md). **Do NOT reconstruct these from memory** —
the bookkeeping (counter keys, `HookOrder`, streaming caveats) lives only there. Skip the file
only for a one-liner the table already covers.

## Layer 2: Interventions (stable, the default for guardrails)

Return a **typed action** instead of mutating fields. Composable, ordered, short-circuiting.

```python
from strands import Agent, InterventionHandler
from strands.interventions import Proceed, Deny
from strands.hooks import BeforeToolCallEvent

class ToolPolicy(InterventionHandler):
    name = "tool-policy"
    # on_error: "throw" (default) | "proceed" (fail-open) | "deny" (fail-closed)
    def before_tool_call(self, event: BeforeToolCallEvent, **kwargs):
        if event.tool_use["name"] in BLOCKED:
            return Deny(reason="Not permitted here.")
        return Proceed()

agent = Agent(interventions=[ToolPolicy()])
```

Actions: `Proceed`, `Deny`, `Guide(feedback=...)`, `Confirm(...)`, `Transform(apply=...)`.
Lifecycle methods: `before_invocation`, `before_tool_call`, `after_tool_call`,
`before_model_call`, `after_model_call`. `Deny`/denied-`Confirm` short-circuit; `Guide`
actions **accumulate** across handlers. Vended: `from strands.vended_interventions import
HumanInTheLoop, CedarAuthorization`.

**MANDATORY — READ THE ENTIRE FILE before implementing any `InterventionHandler` OR
`SteeringHandler`:** [`references/interventions-and-steering.md`](references/interventions-and-steering.md)
— the action-compatibility matrix (which action is valid on which event), `on_error`
semantics, the two non-interchangeable `Guide` types, `LedgerProvider`, and cost notes are
there and easy to get wrong from memory.

## Layer 3: Steering (stable; Python only) — "steer, don't block"

Instead of blocking a wrong move, **Guide** the model with context and let it retry. In
Strands' own published benchmark, steering scored 100% accuracy vs 82.5% (prompt
instructions) and 80.8% (graph workflows) over 3,000 runs (vendor-reported — treat as
directional, not independently replicated).

```python
from strands import Agent
from strands.vended_plugins.steering import LLMSteeringHandler   # NOT experimental.steering

handler = LLMSteeringHandler(system_prompt="Renewals ≤30 days; never renew recalled books; "
                                            "guide the agent to retry if a rule is violated.")
agent = Agent(tools=[renew_book], plugins=[handler])             # note: plugins=, not hooks=
```

Actions are `Proceed`/`Guide`/`Interrupt` (Pydantic, `reason` **required** — different
classes from the intervention actions). `LLMSteeringHandler` runs a **fresh isolated agent
per evaluation** (a real per-tool-call cost — gate it or prefer a `SteeringHandler` subclass
for cheap, rule-based checks). Override `steer_before_tool` / `steer_after_model`; context
comes from `LedgerProvider` (tool-call history). The full API + a `SteeringHandler` subclass
are in the same reference flagged above — read it before subclassing.

## Top anti-patterns (the landmines)

1. **Mutating a non-writable field** → `AttributeError` at runtime. Only the table's levers
   are writable; e.g. `AfterInvocationEvent.result` is read-only (only `resume` is).
2. **Letting a hook raise.** Only `InterruptException` is caught; any other exception
   **aborts the whole run.** Wrap external calls in `try/except` and decide fail-open vs
   fail-closed explicitly (guardrails especially).
3. **Sharing a `HookProvider`/handler instance across concurrent requests.** Instance
   attributes leak across users. Build per request (as this repo's `agent/main.py` does) or
   keep per-request state in `invocation_state`, not `self`.
4. **Reading `event.agent.messages` in `BeforeInvocationEvent`** — the new turn isn't there
   yet. Read/write `event.messages`.
5. **`retry=True` while streaming** — chunks from the discarded attempt were already emitted;
   make stream consumers retry-aware.
6. **`resume`/`retry` loops with no counter** → infinite loop. Always gate with a counter in
   `invocation_state` or `agent.state`.
7. **Importing `strands.experimental.steering`** → `DeprecationWarning`; use
   `strands.vended_plugins.steering`.
8. **`async def` on `AgentInitializedEvent`** → `ValueError` at registration (it's sync-only).
9. **Confusing intervention `Guide(feedback=...)` with steering `Guide(reason=...)`** — they
   are different, non-interchangeable types.

Full catalog with symptoms/causes/fixes: **read**
[`references/anti-patterns.md`](references/anti-patterns.md).

## Bundled resources

- [`references/event-catalog.md`](references/event-catalog.md) — **MANDATORY — READ ENTIRE
  FILE before relying on any event's exact attributes or writable fields**: every event
  (single-agent, multi-agent, bidi), the steering levers, lifecycle order, and the
  `*InvocationEvent → *CallEvent` migration map.
- [`references/interventions-and-steering.md`](references/interventions-and-steering.md) —
  **MANDATORY before building an `InterventionHandler` or `SteeringHandler`** (see trigger
  above): full APIs, action-compatibility matrix, `on_error`, `LedgerProvider`, cost notes.
- [`references/recipes.md`](references/recipes.md) — **MANDATORY before writing a non-trivial
  steering hook**: copy-paste production hooks (HITL, PII redaction, tool budget, debounce,
  dynamic tool filtering, dry-run swap, autonomous resume, multi-agent node guard, observability).
- [`references/anti-patterns.md`](references/anti-patterns.md) — **MANDATORY — READ ENTIRE
  FILE before shipping any hook**: the failure-mode catalog (symptom → cause → fix); #2 (a
  raised hook aborts the whole run) is catastrophic if missed.

**Do NOT load any reference** for a single writable-field tweak the steering-levers table
already covers — load on demand only at the decision points flagged above.

- `scripts/introspect_strands_hooks.py` — introspect the installed SDK (**run first**).
- `scripts/scaffold_steering.py` — generate a correct skeleton:
  `python scripts/scaffold_steering.py {hook|intervention|steering|plugin} > my_handler.py`.
