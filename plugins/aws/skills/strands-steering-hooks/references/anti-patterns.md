---
name: anti-patterns
description: Strands steering-hook failure modes with symptom → root cause → fix — non-writable field mutation, hook exceptions aborting the run, concurrent provider state leakage, message-visibility timing, retry/stream contamination, structured-output gaps, ordering reversal, deprecated imports, infinite resume loops. Load when debugging a hook or before shipping one.
---

# Steering-hook anti-patterns (source-verified)

Symptom → Root cause → Fix. Confidence noted where it isn't a direct source fact.

## 1. Mutating a non-writable field → `AttributeError`
**Symptom:** `AttributeError: Property <name> is not writable` from inside a callback, which
(see #2) aborts the run.
**Cause:** Each event's `_can_write()` is a strict allowlist. The split is asymmetric —
`result` is writable on `AfterToolCallEvent` but **read-only** on `AfterInvocationEvent`;
`tool_use`/`selected_tool` are writable on `BeforeToolCallEvent` but read-only on
`AfterToolCallEvent`.
**Fix:** Only assign the levers in the event-catalog table. To change the final agent result,
do it after `agent()` returns, not in `AfterInvocationEvent`.

## 2. Letting a hook raise → whole run aborts
**Symptom:** A transient error in a guardrail (network timeout, KeyError) crashes the entire
agent call.
**Cause:** `invoke_callbacks_async` catches **only** `InterruptException`; everything else
propagates out of the agent loop. There is no soft-failure mode.
**Fix:** Wrap risky hook bodies in `try/except` and choose a posture deliberately: fail-open
(allow on error) vs fail-closed (block on error). For guardrails this is a security decision —
make it explicit:

```python
def guard(event: BeforeToolCallEvent):
    try:
        verdict = external_policy_check(event.tool_use)     # may time out / raise
    except Exception:                                        # never let it reach the agent loop
        event.cancel_tool = "Policy check unavailable."      # fail-CLOSED (block on error)
        # pass                                               # fail-OPEN alternative (allow on error)
        return
    if not verdict.allowed:
        event.cancel_tool = verdict.reason
```

(Interventions formalize this with `on_error="proceed"|"deny"|"throw"`; steering handlers
fail-open silently — validate inputs yourself.)

## 3. Shared provider state under concurrency
**Symptom:** Counters/flags/user data bleed across simultaneous requests in a web server.
**Cause:** A single `HookProvider`/`InterventionHandler`/`SteeringHandler` instance reused
across invocations stores per-request state on `self`; the SDK gives no per-call isolation.
**Fix:** Construct the agent and its hook instances **per request** (this repo's
`agent/main.py` already does), or keep per-request state in `event.invocation_state` (fresh
dict per call), never on `self`.

## 4. Reading the wrong messages in `BeforeInvocationEvent`
**Symptom:** An input guardrail inspects the previous turn (or an empty list) and lets the new
message through / blocks the wrong thing.
**Cause:** At `BeforeInvocationEvent`, the new user message is **not yet** in
`agent.messages`.
**Fix:** Read and mutate `event.messages` (the writable field), not `event.agent.messages`.

## 5. `retry=True` contaminates streamed output
**Symptom:** A UI shows partial output from a failed attempt, then the retried output.
**Cause:** `AfterToolCallEvent.retry`/`AfterModelCallEvent.retry` discard the result, but
stream chunks from the discarded attempt were already emitted to consumers. Only the final
`ToolResultEvent` is suppressed.
**Fix:** Make stream consumers retry-aware (buffer until the final result, or track attempt
state); or avoid `retry` on streaming paths.

## 6. Assuming `AfterInvocationEvent.result` is writable
**Symptom:** `AttributeError` when setting `event.result`.
**Cause:** Only `resume` is writable on that event.
**Fix:** Post-process the return value after `agent()`; use `resume` only to loop.

## 7. Infinite `resume`/`retry` loop
**Symptom:** The agent never returns (or burns tokens) because a hook keeps setting
`resume`/`retry`.
**Cause:** No stop condition. Neither field is loop-limited by the SDK.
**Fix:** Always gate with a counter in `invocation_state` (per request) or `agent.state`
(across requests).

## 8. Using deprecated imports
**Symptom:** `DeprecationWarning`, or code that breaks on a future minor.
**Cause:** `strands.experimental.steering.*`, `strands.experimental.hooks.*InvocationEvent`,
and `strands.experimental.hooks.multiagent.*` are deprecated shims.
**Fix:** `strands.vended_plugins.steering`, `strands.hooks` (for `*CallEvent` and multi-agent
events). Confirm with `scripts/introspect_strands_hooks.py`.

## 9. `async def` callback on `AgentInitializedEvent`
**Symptom:** `ValueError: AgentInitializedEvent can only be registered with a synchronous
callback` — at **registration** time, not when it fires.
**Cause:** That event runs on a sync path during `__init__`.
**Fix:** Use a sync callback; kick off async setup later in `BeforeInvocationEvent`.
(Separately, the sync `invoke_callbacks` raises `RuntimeError` if any callback is async — the
normal `agent()`/`stream_async()` paths use the async invoker, so async callbacks work there.)

## 10. Confusing the two `Guide`/`Proceed` action sets
**Symptom:** Validation error or wrong field name (`feedback` vs `reason`).
**Cause:** Interventions expose `Guide(feedback=...)` (frozen dataclass) from
`strands.interventions`; Steering exposes `Guide(reason=...)` (Pydantic) from
`strands.vended_plugins.steering`. Same names, different types.
**Fix:** Import from the correct module for the tier you're in; steering actions require
`reason`.

## 11. Misreading "reverse" callback order
**Symptom:** Teardown/cleanup runs in an unexpected order when mixing `HookOrder` priorities.
**Cause:** `After*` events reverse callbacks **within each priority group**, not globally.
With A,B at `DEFAULT` and C at `SDK_LAST`, order is B → A → C.
**Fix:** Use explicit `HookOrder` for cross-group ordering; rely on reversal only within one
group.

## 12. Expecting model events for the deprecated `structured_output()`
**Symptom:** A rate-limiter on `Before/AfterModelCallEvent` misses structured-output calls.
**Cause:** The **deprecated** `Agent.structured_output()` bypasses the event loop. (The modern
`structured_output_model=` invocation path fires model events normally.)
**Fix:** For request-level counting use `Before/AfterInvocationEvent` (fire on all paths), or
migrate to the modern structured-output API.

## 13. Trying to redact in `MessageAddedEvent`
**Symptom:** Can't change the message; PII still stored.
**Cause:** `MessageAddedEvent.message` is read-only (observation only), and it may fire after a
memory manager already persisted the message.
**Fix:** Redact earlier at `BeforeInvocationEvent` (writable `messages`), and order any
`MessageAddedEvent` observers with `HookOrder` relative to the memory/session manager.

## 14. No hook for context-window eviction
**Symptom:** Want to extract/summarize when history is compressed; no event fires.
**Cause:** There is no eviction hook event (tracked upstream as a feature request).
**Fix:** Implement a custom `ConversationManager` for eviction-time logic instead. *(Confidence:
high that no event exists at the research snapshot — re-check with the introspection script.)*

## 15. `LLMSteeringHandler` cost surprise
**Symptom:** Latency/cost roughly doubles per tool call.
**Cause:** It runs a fresh isolated `Agent` (an extra LLM call) on every steering evaluation.
**Fix:** Restrict steering to risky/ambiguous tools, or use a code-based `SteeringHandler`
subclass with `LedgerProvider` for deterministic checks.

## 16. Needing `HookOrder` priority from a `@hook` method
**Symptom:** You wrote a `Plugin` with `@hook` but can't make a guardrail run before another
hook — `@hook` takes no `order=` argument.
**Cause:** `@hook` auto-registers by the event type hint at `HookOrder.DEFAULT`; priority is a
parameter of `registry.add_callback(EventType, cb, order=...)`, not of the decorator.
**Fix:** For explicit ordering, use a `HookProvider` and call `add_callback(..., order=...)`
yourself (e.g. `HookOrder.SDK_FIRST`), or register that one callback imperatively in the
plugin's `init_agent()`. Reserve `@hook` for default-order callbacks. *(Confidence: high that
`@hook` infers type and registers at default order; re-check `order=` support with the
introspection script if a future version adds it.)*

## Quick reference

| # | One-liner | Severity |
|---|---|---|
| 1 | Only documented levers are writable | high |
| 2 | Unhandled hook exception aborts the run | high |
| 3 | Per-request state must not live on `self` | high |
| 4 | Use `event.messages`, not `event.agent.messages`, in BeforeInvocation | high |
| 5 | `retry` duplicates streamed chunks | med |
| 6 | `AfterInvocationEvent.result` is read-only | high |
| 7 | Gate `resume`/`retry` with a counter | high |
| 8 | Avoid `experimental.*` deprecated imports | high |
| 9 | `AgentInitializedEvent` is sync-only | med |
| 10 | Two different `Guide` types | med |
| 11 | "Reverse" is within-group only | med |
| 12 | Deprecated `structured_output()` skips model events | med |
| 13 | `MessageAddedEvent` is observe-only | med |
| 14 | No eviction hook event | low |
| 15 | `LLMSteeringHandler` = +1 LLM call per check | med |
| 16 | `@hook` can't set `order=`; use `HookProvider.add_callback` for priority | med |
