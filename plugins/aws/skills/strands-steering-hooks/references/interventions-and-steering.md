---
name: interventions-and-steering
description: Full reference for the two higher-level steering tiers in Strands — the stable Interventions API (InterventionHandler, Proceed/Deny/Guide/Confirm/Transform, action-compatibility matrix, on_error) and the stable Steering plugin (SteeringHandler/LLMSteeringHandler/LedgerProvider, Proceed/Guide/Interrupt). Load when building an InterventionHandler or SteeringHandler.
---

# Interventions & Steering (source-verified)

Both sit on the raw hook events but give you typed decisions instead of field mutation.
Choose by intent: **Interventions** = enforce policy (block/authorize/approve);
**Steering** = adaptively guide the model back on track.

---

## Tier 2 — Interventions (`strands.interventions`, STABLE, Python + TypeScript)

```python
from strands import Agent, InterventionHandler         # top-level export
from strands.interventions import Proceed, Deny, Guide, Confirm, Transform, OnError
```

Register via the dedicated parameter: `Agent(interventions=[Handler(), ...])`. Handlers run
in registration order. Subclass `InterventionHandler`, set `name`, override the lifecycle
methods you care about, and **return an action** (never mutate the event directly except via
`Transform`).

### Lifecycle methods (override only what you need; sync or async)

```python
class MyPolicy(InterventionHandler):
    name = "my-policy"

    @property
    def on_error(self) -> OnError:        # default "throw"
        return "deny"                      # "throw" | "proceed" (fail-open) | "deny" (fail-closed)

    def before_invocation(self, event, **kw):  -> Proceed|Deny|Guide|Transform
    def before_tool_call(self, event, **kw):   -> Proceed|Deny|Guide|Confirm|Transform
    def after_tool_call(self, event, **kw):    -> Proceed|Transform
    def before_model_call(self, event, **kw):  -> Proceed|Deny|Guide|Transform
    def after_model_call(self, event, **kw):   -> Proceed|Guide|Transform
```

(`before_invocation` exists in source even though some docs tables omit it.)

### Actions (frozen dataclasses)

| Action | Field(s) | Meaning |
|---|---|---|
| `Proceed(reason=None)` | optional debug note (not shown to model) | allow |
| `Deny(reason="")` | message shown to model | block + **short-circuit** remaining handlers |
| `Guide(feedback="", reason=None)` | `feedback` → model; `reason` internal | inject corrective feedback (accumulates across handlers; does NOT short-circuit) |
| `Confirm(prompt="", response=None, evaluate=None)` | approval gate | **`before_tool_call` only**; uses preset response or an interrupt, denies if rejected |
| `Transform(apply=callable)` | `apply(event)` mutates in place | low-level escape hatch; later handlers see the change |

### Action-compatibility matrix (from source)

```
Action     before_invocation  before_tool_call  before_model_call  after_tool_call  after_model_call
Proceed         —                 —                 —                  —                —
Deny            cancel            cancel            cancel             —(no-op)         —(no-op)
Guide           cancel+           cancel+           inject             —(no-op)         inject+retry
Confirm         —                 confirm           —                  —                —
Transform       apply             apply             apply              apply            apply
```
`—` = no-op + runtime warning. `Deny` is **not** valid on `after_*`. `Guide` on
`after_model_call` injects feedback and triggers a retry so the model sees it.

### Example — block + approve

```python
from strands import Agent, InterventionHandler
from strands.interventions import Proceed, Deny, Confirm
from strands.hooks import BeforeToolCallEvent

class Policy(InterventionHandler):
    name = "policy"
    def before_tool_call(self, event: BeforeToolCallEvent, **kw):
        name = event.tool_use["name"]
        if name == "drop_table":
            return Deny(reason="Destructive DDL is disabled.")
        if name == "issue_refund" and event.tool_use["input"].get("amount", 0) > 100:
            return Confirm(prompt=f"Approve refund of {event.tool_use['input']['amount']}?")
        return Proceed()

agent = Agent(interventions=[Policy()])
```

### Vended interventions (ship ready-made)

```python
from strands.vended_interventions import HumanInTheLoop, CedarAuthorization
agent = Agent(interventions=[CedarAuthorization(...)])   # NOTE: interventions=, not plugins=
```
`CedarAuthorization` (Cedar policy auth) and `HumanInTheLoop` are `InterventionHandler`s — a
common mistake is registering them via `plugins=`.

---

## Tier 3 — Steering (`strands.vended_plugins.steering`, STABLE, **Python only**)

> Import from `strands.vended_plugins.steering`. The old `strands.experimental.steering` path
> is a deprecated shim that emits `DeprecationWarning`.

```python
from strands.vended_plugins.steering import (
    SteeringHandler, LLMSteeringHandler, LedgerProvider,
    Proceed, Guide, Interrupt,          # Pydantic models — DIFFERENT from intervention actions
    ToolSteeringAction, ModelSteeringAction,
)
```

Register via `Agent(plugins=[handler])` (`SteeringHandler` extends `Plugin`). Philosophy:
**steer, don't block** — when the agent goes off-track, `Guide` it with context and let it
retry, rather than hard-failing. Vendor-reported benchmark (Strands blog "Steering accuracy
beats prompts & workflows" — treat as directional, not independently replicated): 100%
accuracy vs 99.8% SOPs / 82.5% prompt instructions / 80.8% graph workflows over 3,000 runs
(6 scenarios × 100 runs × 5 variants), at ~66% fewer input tokens than SOPs.

### Actions (Pydantic; `reason` is REQUIRED)

| Action | Valid at | Effect |
|---|---|---|
| `Proceed(reason=...)` | tool, model | continue |
| `Guide(reason=...)` | tool, model | tool: set `cancel_tool` with guidance; model: `retry=True` + append guidance message |
| `Interrupt(reason=...)` | **tool only** | pause for human (model already responded → not allowed post-model) |

`ToolSteeringAction = Proceed|Guide|Interrupt`; `ModelSteeringAction = Proceed|Guide`. These
are **not** the intervention `Proceed`/`Guide` — different module, Pydantic not dataclass,
field is `reason` not `feedback`. Don't cross the imports.

### A. `LLMSteeringHandler` — natural-language rules

```python
from strands import Agent
from strands.vended_plugins.steering import LLMSteeringHandler

handler = LLMSteeringHandler(
    system_prompt=(
        "You evaluate tool calls for a book-renewal agent. Rules: renewals ≤ 30 days; "
        "never renew recalled books; library-card numbers must match. If the ledger shows a "
        "prior failure for the same tool+args, Guide the agent to try differently. If human "
        "sign-off is needed, Interrupt."
    ),
    # model=None  → reuses the host agent's model
    # context_providers=None → defaults to [LedgerProvider()]; pass [] to disable
)
agent = Agent(tools=[renew_book], plugins=[handler])
```

**Cost warning:** `LLMSteeringHandler` spins up a **fresh, isolated `Agent` for every steering
evaluation** (one extra LLM call per tool call / model turn). At volume this doubles
tool-decision latency and cost. Gate it (only steer ambiguous/risky tools) or use a
`SteeringHandler` subclass for cheap rule-based checks.

### B. `SteeringHandler` subclass — code-driven, no extra LLM

```python
from strands.vended_plugins.steering import (
    SteeringHandler, LedgerProvider, Proceed, Guide, Interrupt, ToolSteeringAction)

class RetryLimit(SteeringHandler):
    def __init__(self):
        super().__init__(context_providers=[LedgerProvider()])
        self.max_failures = 3
    async def steer_before_tool(self, *, agent, tool_use, **kw) -> ToolSteeringAction:
        ledger = self.steering_context.data.get("ledger") or {}
        fails = sum(1 for c in ledger.get("tool_calls", [])
                    if c.get("tool_name") == tool_use["name"] and c.get("status") == "error")
        if fails >= self.max_failures:
            return Interrupt(reason=f"{tool_use['name']} failed {fails}x — needs human review.")
        return Proceed(reason="within failure budget")

agent = Agent(tools=[my_tool], plugins=[RetryLimit()])
```

Override `steer_before_tool` (wired to `BeforeToolCallEvent`) and/or `steer_after_model`
(wired to `AfterModelCallEvent`). Both are `async`. Both fire reliably today. **Steering's own
error policy:** if your `steer_*` raises, it's logged at DEBUG and treated as `Proceed`
(silent fail-open) — it does NOT use the interventions `on_error`. Validate inputs yourself.

`LedgerProvider` records every tool call (`tool_name`, `tool_args`, `status`,
`result`/`error`, timestamps) into `self.steering_context.data["ledger"]` for both
`LLMSteeringHandler` prompts and imperative checks.

---

## Choosing a tier (summary)

| Need | Tier | API |
|---|---|---|
| Log / trace / count | Raw hooks | `@hook` / `HookProvider`; OTel `StrandsTelemetry` for spans |
| Block a tool / authorize / hard policy | Interventions | `Deny`, `CedarAuthorization` |
| Human approval gate | Interventions or raw `interrupt()` | `Confirm`, `HumanInTheLoop`, `event.interrupt()` |
| Adaptive "you're drifting, here's context, retry" | Steering | `LLMSteeringHandler` / `SteeringHandler` |
| Rewrite args / override result / inject per-turn context / dedupe | Raw hooks | writable fields |

Cross-framework note: `agent-control-sdk` (`AgentControlPlugin`/`AgentControlSteeringHandler`)
is a **community** project by Galileo, not AWS — it layers a central policy server on the same
surfaces.
