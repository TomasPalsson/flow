#!/usr/bin/env python3
"""Print a correct, current Strands steering skeleton — right imports, signatures, registration.

    python scaffold_steering.py hook          # raw HookProvider (mutate writable fields)
    python scaffold_steering.py intervention  # InterventionHandler (typed actions, STABLE)
    python scaffold_steering.py steering       # SteeringHandler subclass (steer, don't block)
    python scaffold_steering.py plugin         # Plugin + @hook (shareable bundle)

Templates are pinned to the source-verified API (SDK ~ post-1.44.0). Run
`introspect_strands_hooks.py` first to confirm the installed version matches.
Pure stdlib; emits to stdout — redirect into a file: `... steering > my_handler.py`.
"""
from __future__ import annotations

import sys

HOOK = '''\
"""Raw HookProvider: steer by mutating writable event fields directly."""
from strands import Agent
from strands.hooks import (
    HookProvider, HookRegistry, HookOrder,
    BeforeToolCallEvent, AfterToolCallEvent,
)

BLOCKED = {"drop_table", "delete_all"}


class MySteering(HookProvider):
    """One provider, several related callbacks. Build a NEW instance per request on a
    server — keep per-request state in event.invocation_state, never on self."""

    def register_hooks(self, registry: HookRegistry, **kwargs) -> None:
        registry.add_callback(BeforeToolCallEvent, self.before_tool, order=HookOrder.DEFAULT)
        registry.add_callback(AfterToolCallEvent, self.after_tool)

    def before_tool(self, event: BeforeToolCallEvent) -> None:
        name = event.tool_use["name"]
        if name in BLOCKED:                       # block (model is told, run continues)
            event.cancel_tool = f"Policy: '{name}' is disabled."
            return
        inp = event.tool_use["input"]             # rewrite args in place
        if inp.get("limit", 0) > 1000:
            inp["limit"] = 1000
        # event.selected_tool = other_tool        # swap implementation
        # event.interrupt("approve", reason=inp)  # pause for a human (HITL)

    def after_tool(self, event: AfterToolCallEvent) -> None:
        if event.result.get("status") == "error":
            tid = event.tool_use.get("toolUseId", "")
            tries = event.invocation_state.get(f"try:{tid}", 0)
            if tries < 2:                          # bounded retry (counter prevents infinite loop)
                event.invocation_state[f"try:{tid}"] = tries + 1
                event.retry = True
        # else: mutate event.result["content"] to reshape what the model sees

    # Hooks that raise abort the whole run (only InterruptException is caught) — guard I/O.


if __name__ == "__main__":
    agent = Agent(tools=[], hooks=[MySteering()])
'''

INTERVENTION = '''\
"""InterventionHandler: typed actions for policy/guardrails (STABLE, Python + TypeScript)."""
from strands import Agent, InterventionHandler
from strands.interventions import Proceed, Deny, Guide, Confirm, OnError
from strands.hooks import BeforeToolCallEvent, BeforeModelCallEvent

BLOCKED = {"drop_table"}


class MyPolicy(InterventionHandler):
    name = "my-policy"

    @property
    def on_error(self) -> OnError:
        return "deny"          # "throw" (default) | "proceed" (fail-open) | "deny" (fail-closed)

    def before_tool_call(self, event: BeforeToolCallEvent, **kwargs):
        name = event.tool_use["name"]
        if name in BLOCKED:
            return Deny(reason=f"'{name}' is not permitted.")     # blocks + short-circuits
        if name == "issue_refund" and event.tool_use["input"].get("amount", 0) > 100:
            return Confirm(prompt="Approve this refund?")          # before_tool_call only
        return Proceed()

    def before_model_call(self, event: BeforeModelCallEvent, **kwargs):
        return Proceed()       # return Guide(feedback="...") to inject correction + retry

    # Other overridables: before_invocation, after_tool_call, after_model_call.
    # Guide uses feedback=...; Deny is invalid on after_* events.


if __name__ == "__main__":
    agent = Agent(tools=[], interventions=[MyPolicy()])
'''

STEERING = '''\
"""SteeringHandler: 'steer, don't block' — guide the model with context, let it retry.
STABLE, Python only. Import from vended_plugins.steering (NOT experimental.steering)."""
from strands import Agent
from strands.vended_plugins.steering import (
    SteeringHandler, LedgerProvider,
    Proceed, Guide, Interrupt,           # Pydantic; reason= is REQUIRED (not the intervention ones)
    ToolSteeringAction, ModelSteeringAction,
)


class MySteering(SteeringHandler):
    def __init__(self) -> None:
        super().__init__(context_providers=[LedgerProvider()])  # ledger of past tool calls
        self.max_failures = 3

    async def steer_before_tool(self, *, agent, tool_use, **kwargs) -> ToolSteeringAction:
        ledger = self.steering_context.data.get("ledger") or {}
        name = tool_use["name"]
        fails = sum(1 for c in ledger.get("tool_calls", [])
                    if c.get("tool_name") == name and c.get("status") == "error")
        if fails >= self.max_failures:
            return Interrupt(reason=f"'{name}' failed {fails}x — human review needed.")
        if fails:
            return Guide(reason=f"'{name}' failed before; change the arguments this time.")
        return Proceed(reason="ok")

    async def steer_after_model(self, *, agent, message, stop_reason, **kwargs) -> ModelSteeringAction:
        # Fires on EVERY model turn. Guide(reason=...) injects feedback AND retries the model —
        # returning Guide unconditionally here is an infinite loop; only Guide on a real problem.
        return Proceed(reason="accepting response")  # Interrupt is NOT valid post-model


if __name__ == "__main__":
    # For natural-language rules instead of code, use LLMSteeringHandler(system_prompt="..."):
    #   from strands.vended_plugins.steering import LLMSteeringHandler   # +1 LLM call per check
    agent = Agent(tools=[], plugins=[MySteering()])   # NOTE: plugins=, not hooks=/interventions=
'''

PLUGIN = '''\
"""Plugin + @hook: shareable bundle; @hook auto-registers by the event type hint."""
from strands import Agent
from strands.plugins import Plugin, hook
from strands.hooks import BeforeToolCallEvent, AfterInvocationEvent


class MyPlugin(Plugin):
    name = "my-plugin"        # required, unique

    @hook
    def on_tool(self, event: BeforeToolCallEvent) -> None:
        print("calling", event.tool_use["name"])

    @hook
    def on_done(self, event: AfterInvocationEvent) -> None:
        # event.result is read-only here; only event.resume is writable
        ...

    # A Plugin can also expose @tool methods and an init_agent() lifecycle.


if __name__ == "__main__":
    agent = Agent(tools=[], plugins=[MyPlugin()])
'''

TEMPLATES = {"hook": HOOK, "intervention": INTERVENTION, "steering": STEERING, "plugin": PLUGIN}


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in TEMPLATES:
        print(f"usage: {argv[0] if argv else 'scaffold_steering.py'} "
              f"{{{'|'.join(TEMPLATES)}}}", file=sys.stderr)
        return 2
    print(TEMPLATES[argv[1]], end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
