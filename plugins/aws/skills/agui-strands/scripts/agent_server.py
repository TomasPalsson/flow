"""agent/main.py — an AG-UI server on Bedrock AgentCore Runtime.

Contract AgentCore requires: POST /invocations (AG-UI SSE) + GET /ping, on 0.0.0.0:8080,
in a linux/arm64 container. `ag_ui_strands.StrandsAgent` wraps a Strands agent and emits the
AG-UI events; the route on the Next.js side translates them into AI SDK parts.

requirements.txt:  ag-ui-strands  strands-agents  fastapi  uvicorn  (+ your data libs)
Dockerfile:        FROM --platform=linux/arm64 python:3.13-slim ; CMD ["python","main.py"]
"""

import os
import json

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from ag_ui_strands import StrandsAgent
from ag_ui.core import RunAgentInput
from ag_ui.encoder import EventEncoder
from strands import Agent, tool
from strands.models import BedrockModel

# Use the inference-profile prefix matching the region: eu. in EU, us. in US.
MODEL_ID = os.environ.get("MODEL_ID", "eu.anthropic.claude-opus-4-6-v1")
REGION = os.environ.get("AWS_REGION", "eu-west-1")

SYSTEM_PROMPT = """You are a product assistant.
- Call search_products for any catalog query; never fabricate product data.
- Cards render automatically from tool output — do NOT repeat tool data as prose.
- Call display/quick-reply tools LAST so tall cards don't push your text out of view."""


@tool
def search_products(query: str, only_offers: bool = False) -> str:
    """Search the product catalog.

    Args:
        query: The search term (the model's words for what the user wants).
        only_offers: If true, restrict to items currently on offer.
    """
    # ... your real lookup here ...
    products: list[dict] = []
    # ALWAYS return a JSON string; cast every value to a JSON-serializable type
    # (round(float(price)) — never raw Decimal/datetime — or json.dumps will throw → RUN_ERROR).
    return json.dumps({"query": query, "count": len(products), "products": products})


model = BedrockModel(model_id=MODEL_ID, region_name=REGION)

# The function name (search_products) is the dispatch key for the frontend card switch.
strands_agent = Agent(
    model=model,
    system_prompt=SYSTEM_PROMPT,
    tools=[search_products],
    callback_handler=None,   # silence PrintingCallbackHandler (else every token prints to stdout)
)

# Module-level SINGLETON. StrandsAgent keeps one Strands agent per thread_id internally and
# replays full history each turn (stream_async(None)). Don't recreate it per request.
agui_agent = StrandsAgent(
    agent=strands_agent,
    name="product_agent",
    description="Product assistant with live catalog search.",
)

app = FastAPI()


@app.post("/invocations")
async def invocations(input_data: dict, request: Request):
    """AG-UI endpoint — streams AG-UI events as SSE."""
    encoder = EventEncoder(accept=request.headers.get("accept"))

    async def event_generator():
        run_input = RunAgentInput(**input_data)  # threadId, runId, messages, tools, state, context, ...
        async for event in agui_agent.run(run_input):
            yield encoder.encode(event)          # → "data: {json}\n\n" (camelCase, no [DONE])

    return StreamingResponse(event_generator(), media_type=encoder.get_content_type())


@app.get("/ping")
async def ping():
    """Health check AgentCore polls."""
    return JSONResponse({"status": "Healthy"})


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)  # 0.0.0.0:8080 is mandatory
