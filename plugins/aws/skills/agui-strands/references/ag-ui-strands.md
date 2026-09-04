---
name: ag-ui-strands
description: How ag_ui_strands.StrandsAgent wraps a Strands agent and emits AG-UI events, the Strands @tool schema/return rules, BedrockModel config, history replay, and frontend tools. Load before writing the agent or its tools.
---

# ag-ui-strands + Strands agent layer

`ag-ui-strands` (PyPI; v0.1.9 studied) is the glue: `StrandsAgent` wraps a Strands `Agent` and
turns its streaming events into AG-UI protocol events. You write tools + configure the agent; the
library does all AG-UI emission. `strands-agents` is the underlying SDK.

## Minimal server agent

```python
from ag_ui_strands import StrandsAgent
from ag_ui.core import RunAgentInput
from ag_ui.encoder import EventEncoder
from strands import Agent, tool
from strands.models import BedrockModel

model = BedrockModel(model_id="eu.anthropic.claude-opus-4-6-v1", region_name="eu-west-1")
strands_agent = Agent(model=model, system_prompt=SYSTEM_PROMPT, tools=[...], callback_handler=None)
agui_agent = StrandsAgent(agent=strands_agent, name="my_agent", description="...")  # module-level SINGLETON
```
`agui_agent.run(RunAgentInput(**input_data))` is an async generator of AG-UI events; `EventEncoder`
serializes each to an SSE `data:` frame. See agent_server.py for the FastAPI wrapper.

## How StrandsAgent works internally (so you can reason about it)

- **One Strands agent per `thread_id`**, cached in `_agents_by_thread` (created lazily from the
  template's extracted model/system_prompt/tools/kwargs). The template agent is used only for config
  extraction — never call it directly. **No eviction policy** → memory grows unbounded in long-lived
  servers; restart or add your own eviction for high traffic.
- **History reconciliation (default `replay_history_into_strands=True`)**: before each run it converts
  `RunAgentInput.messages` (AG-UI) → Strands/Bedrock native format, sets `strands_agent.messages =
  history`, and calls `stream_async(None)` (None = "use existing messages, append nothing"). This is
  how frontend-tool results reach the model without Strands re-executing the tool.
- If you set a `session_manager_provider` (File/S3 SessionManager), Strands owns history instead; set
  `replay_history_into_strands=False`. The two paths are mutually exclusive. Setting `session_manager`
  on the *template* agent is silently ignored — use the config provider.
- **Run lifecycle**: emits `RUN_STARTED` first; text deltas → `TEXT_MESSAGE_*`; tool-arg streaming →
  `TOOL_CALL_START/ARGS`; `contentBlockStop` → `TOOL_CALL_END`; tool result message →
  `TOOL_CALL_RESULT(content=json.dumps(result))`; ends with `STATE_SNAPSHOT` + `RUN_FINISHED`; any
  exception → `RUN_ERROR(code="STRANDS_ERROR")`. Reasoning maps to `REASONING_*`.
- **Frontend tools** (declared in `RunAgentInput.tools`): registered as proxy stubs; after the LLM
  calls one, the stream emits `TOOL_CALL_END` then halts (`pending_halt`). The client executes the
  tool, appends a `tool` message, and sends a NEW `RunAgentInput` to continue.

## Strands @tool — schema and return rules

```python
@tool
def search_products(query: str, only_offers: bool = False) -> str:
    """Search the catalog.                       # ← summary becomes the tool description

    Args:
        query: Icelandic search term.            # ← each Arg line becomes a param description (LLM sees these)
        only_offers: If true, only on-offer items.
    """
    try:
        products = search(query, only_offers=only_offers, limit=8)
    except Exception as e:
        return json.dumps({"error": str(e), "products": []})
    return json.dumps({"query": query, "count": len(products), "products": products})
```
- The decorator parses the **docstring** (summary + `Args:`) and **type hints** into the Bedrock
  `inputSchema.json`. Write precise arg docs — they are the model's only guidance.
- **Always return a JSON string** (`json.dumps(...)`). Strands serializes the return into
  `toolResult.content[0].text`; ag-ui-strands `json.loads` it back into `TOOL_CALL_RESULT.content`.
  Returning a dict mostly works (auto-serialized) but be explicit.
- **Everything inside must be JSON-serializable.** Cast `Decimal`/`datetime`/`float` at the boundary
  (`round(float(x))`) or `json.dumps` raises → the whole turn becomes a generic `RUN_ERROR`.
- **The function name is the contract with the frontend card switch.** Rename it → update the React
  `case`. Keep a shared `TOOL_NAMES` list.
- **Array-arg pattern**: Bedrock function-calling is shaky with top-level arrays, so production tools
  often take `items_json: str` (a JSON-encoded array string) and `json.loads` it themselves — OR take
  a real `list[str]` and let Strands convert (cleaner; avoids the model emitting Python-repr
  single-quoted strings that fail `json.loads`). Prefer `list[str]` unless you hit problems.
- The tool→card output shape is a hidden contract across Python and TS. Drift (e.g. `priceExVat` →
  `price_ex_vat`) yields `undefined`/`NaN` in cards with no error. Pin it with a shared schema or test.

## BedrockModel

```python
BedrockModel(model_id="eu.anthropic.claude-opus-4-6-v1", region_name="eu-west-1")
```
- Region resolution: arg → `boto_session` → `AWS_REGION` env → `us-west-2`. `region_name` and
  `boto_session` are mutually exclusive.
- **Use the cross-region inference-profile prefix** matching the region: `eu.` in EU, `us.` in US.
  A bare `anthropic.claude-...` id fails in `eu-west-1` with `ValidationException`/`ResourceNotFound`.
- Inside an AgentCore container, the runtime IAM role grants Bedrock — no API keys, no LiteLLM.
- `Agent(callback_handler=...)` defaults to a `PrintingCallbackHandler` that prints every token to
  stdout. Pass `callback_handler=None` in a server.

## System prompt drives whether cards appear

Without explicit tool-use instructions the model may answer in prose and **no card renders** (no
error — just wrong behavior). The prompt must state: which tool to call for each query type; never
fabricate data; cards render automatically so don't repeat tool output as text; and any ordering
rules (e.g. call display/quick-reply tools LAST so tall cards don't push text out of view).
