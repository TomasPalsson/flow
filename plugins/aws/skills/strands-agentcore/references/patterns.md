# Implementation Patterns & Best Practices

## Table of Contents

1. [Agent Factory Pattern](#agent-factory-pattern)
2. [Tool Design Patterns](#tool-design-patterns)
3. [MCP Integration Patterns](#mcp-integration-patterns)
4. [Multi-Agent Patterns](#multi-agent-patterns)
5. [Security Patterns](#security-patterns)
6. [Performance Optimization](#performance-optimization)
7. [Testing Patterns](#testing-patterns)
8. [Conversation Management](#conversation-management)
9. [Error Handling](#error-handling)

---

## Agent Factory Pattern

Reusable factories with organizational defaults:

```python
from strands import Agent
from strands.models import BedrockModel
from strands.session import DynamoDBSessionManager
from strands.agent.conversation_manager import SlidingWindowConversationManager
import os


class AgentFactory:
    """Create agents with standard configuration."""

    @staticmethod
    def create(agent_id: str, system_prompt: str, tools: list) -> Agent:
        return Agent(
            agent_id=agent_id,
            model=BedrockModel(
                model_id=os.getenv(
                    "DEFAULT_MODEL_ID",
                    "anthropic.claude-sonnet-4-5-20250929-v1:0",
                ),
                region_name=os.getenv("AWS_REGION", "us-east-1"),
            ),
            system_prompt=system_prompt,
            tools=tools,
            session_manager=DynamoDBSessionManager(
                table_name=os.getenv("SESSION_TABLE", "agent-sessions"),
            ),
            conversation_manager=SlidingWindowConversationManager(max_messages=20),
        )
```

---

## Tool Design Patterns

### Task-Oriented Tools

Design tools around user tasks, not API endpoints:

```python
# Bad: API-style granularity
@tool
def get_user_by_id(user_id: str) -> dict: ...

@tool
def get_user_orders(user_id: str) -> list: ...

# Good: Task-oriented
@tool
def get_customer_profile(customer_email: str) -> dict:
    """Get complete customer profile including orders and preferences.

    Args:
        customer_email: Customer's email address.
    """
    user = _get_user_by_email(customer_email)
    orders = _get_user_orders(user["id"])
    preferences = _get_user_preferences(user["id"])
    return {
        "status": "success",
        "content": [{"text": json.dumps({
            "user": user, "orders": orders, "preferences": preferences
        })}],
    }
```

### Structured Error Handling

Tools should never raise exceptions to the model:

```python
@tool
def query_database(sql: str) -> dict:
    """Execute SQL query and return results.

    Args:
        sql: SQL query to execute. Must be SELECT only.
    """
    try:
        results = database.execute(sql)
        return {"status": "success", "content": [{"text": json.dumps(results)}]}
    except DatabaseError as e:
        return {"status": "error", "content": [{"text": f"Query failed: {str(e)}"}]}
```

### Pagination for Large Results

```python
@tool
def search_records(query: str, page: int = 1, page_size: int = 10) -> dict:
    """Search records with pagination.

    Args:
        query: Search query string.
        page: Page number (1-based).
        page_size: Results per page. Max 50.
    """
    results = db.query(query, offset=(page - 1) * page_size, limit=page_size)
    return {
        "status": "success",
        "content": [{"text": json.dumps(results)}],
        "pagination": {
            "page": page,
            "has_more": len(results) == page_size,
        },
    }
```

### Async Tools

```python
@tool
async def fetch_api_data(endpoint: str) -> dict:
    """Fetch data from an external API.

    Args:
        endpoint: API endpoint path (e.g., /users/123).
    """
    async with aiohttp.ClientSession() as session:
        async with session.get(f"https://api.example.com{endpoint}") as resp:
            data = await resp.json()
            return {"status": "success", "content": [{"text": json.dumps(data)}]}
```

---

## MCP Integration Patterns

### Direct MCP Client

```python
from strands.tools.mcp import MCPClient
from mcp import streamablehttp_client

client = MCPClient(lambda: streamablehttp_client("http://mcp-server:8000/mcp"))
with client:
    tools = client.list_tools_sync()

agent = Agent(tools=tools)
```

### MCP Server Registry

For organizations with multiple MCP servers:

```python
class MCPRegistry:
    ENDPOINTS = {
        "database": "http://mcp-database.internal:8000/mcp",
        "aws-tools": "http://mcp-aws.internal:8000/mcp",
        "notifications": "http://mcp-notify.internal:8000/mcp",
    }

    @staticmethod
    def load(server_names: list[str]) -> list:
        all_tools = []
        for name in server_names:
            endpoint = MCPRegistry.ENDPOINTS[name]
            client = MCPClient(lambda e=endpoint: streamablehttp_client(e))
            with client:
                all_tools.extend(client.list_tools_sync())
        return all_tools

# Usage
tools = MCPRegistry.load(["database", "aws-tools"])
agent = Agent(tools=tools)
```

### Authenticated MCP Client

When connecting to an MCP server deployed in AgentCore:

```python
from fastmcp import Client as MCPClient

# Pass auth token to authenticated MCP endpoints
client = MCPClient(mcp_source=mcp_url, auth=bearer_token)
async with client as c:
    tools = await c.list_tools()
    result = await c.call_tool("my_tool", {"param": "value"})
```

### Semantic Tool Search (> 50 Tools)

Models struggle with too many tools. Use semantic search to dynamically select relevant ones:

```python
from sentence_transformers import SentenceTransformer
import numpy as np


class DynamicToolLoader:
    def __init__(self, all_tools: list):
        self.all_tools = all_tools
        self.model = SentenceTransformer("all-MiniLM-L6-v2")
        self.embeddings = self.model.encode(
            [tool.__doc__ or tool.__name__ for tool in all_tools]
        )

    def get_relevant(self, query: str, top_k: int = 10) -> list:
        query_emb = self.model.encode([query])
        scores = np.dot(self.embeddings, query_emb.T).flatten()
        top = np.argsort(scores)[-top_k:]
        return [self.all_tools[i] for i in top]

# Usage: only give the agent ~10 relevant tools, not all 100+
loader = DynamicToolLoader(all_tools)
relevant = loader.get_relevant(user_query, top_k=10)
agent = Agent(tools=relevant)
```

---

## Multi-Agent Patterns

### Agent-as-Tool

Simplest multi-agent pattern. Wrap specialist agents as tools:

```python
researcher = Agent(system_prompt="Research specialist.", tools=[web_search])
writer = Agent(system_prompt="Content writer.", tools=[grammar_check])

@tool
def research(topic: str) -> str:
    """Delegate research to a specialist agent.

    Args:
        topic: Topic to research.
    """
    result = researcher(f"Research: {topic}")
    return result.message["content"][0]["text"]

@tool
def write_article(data: str, topic: str) -> str:
    """Write an article using specialist agent.

    Args:
        data: Research data to use.
        topic: Article topic.
    """
    result = writer(f"Write about {topic} using: {data}")
    return result.message["content"][0]["text"]

orchestrator = Agent(
    system_prompt="Coordinate research and writing.",
    tools=[research, write_article],
)
```

### Graph Pattern (Deterministic)

```python
from strands.multiagent import GraphBuilder

builder = GraphBuilder()
builder.add_node("collect", data_collector)
builder.add_node("analyse", analyser)
builder.add_node("report", reporter)

builder.add_edge("collect", "analyse")
builder.add_edge("analyse", "report")

builder.set_execution_timeout(300)
builder.set_max_node_executions(10)

graph = builder.build(entry_point="collect")
result = graph.run({"task": "Analyse Q4 data"})
```

### Swarm Pattern (Autonomous)

```python
from strands.multiagent import Swarm

swarm = Swarm(
    nodes=[researcher, writer, reviewer],
    entry_point=researcher,
    max_handoffs=10,
    execution_timeout=300.0,
)
result = swarm.run("Create and review an article")
```

**Cost multipliers**: Agent-as-Tool 2-3x, Graph 3-5x, Swarm 5-8x.

---

## Security Patterns

### Tool-Level Permissions

```python
from strands.hooks import BeforeToolCallEvent, HookProvider, HookRegistry

PERMISSIONS = {
    "delete_records": "admin:delete",
    "send_email": "user:send",
    "read_data": "user:read",
}


class PermissionValidator(HookProvider):
    def __init__(self, user_permissions: list[str]):
        self.user_permissions = user_permissions

    def register_hooks(self, registry: HookRegistry, **kwargs):
        registry.add_callback(BeforeToolCallEvent, self.validate)

    def validate(self, event: BeforeToolCallEvent):
        required = PERMISSIONS.get(event.tool_use["name"])
        if required and required not in self.user_permissions:
            event.cancel_tool = f"Permission denied: {required} required"


agent = Agent(
    tools=[delete_records, read_data],
    hooks=[PermissionValidator(["user:read"])],
)
```

### Human-in-the-Loop

```python
class ApprovalHook(HookProvider):
    SENSITIVE = ["delete_records", "send_email", "transfer_funds"]

    def register_hooks(self, registry: HookRegistry, **kwargs):
        registry.add_callback(BeforeToolCallEvent, self.require_approval)

    def require_approval(self, event: BeforeToolCallEvent):
        if event.tool_use["name"] in self.SENSITIVE:
            approval = event.interrupt("approval-required", reason={
                "action": event.tool_use["name"],
                "params": event.tool_use["input"],
            })
            if approval.lower() != "approved":
                event.cancel_tool = "Denied by user"
```

### Least-Privilege Tool Execution

```python
@tool
def query_database(sql: str) -> dict:
    """Query database with read-only role.

    Args:
        sql: SELECT query to execute.
    """
    # Use read-only credentials
    conn = get_readonly_connection()
    cursor = conn.cursor()
    cursor.execute(sql)
    return {"status": "success", "content": [{"text": json.dumps(cursor.fetchall())}]}
```

---

## Performance Optimization

### Concurrent Tool Execution

```python
from strands.tools.executors import ConcurrentToolExecutor

agent = Agent(
    tools=[fetch_api, query_db, check_cache],
    tool_executor=ConcurrentToolExecutor(),
)
```

Use when tools are I/O-bound, thread-safe, and order-independent.

### Tool Caching

```python
from functools import lru_cache

@tool
@lru_cache(maxsize=100)
def get_product_catalog() -> dict:
    """Get product catalog (cached)."""
    return {"status": "success", "content": [{"text": json.dumps(db.get_products())}]}
```

### Warm Agent Pool

Avoid cold starts by pre-warming agents:

```python
import queue


class AgentPool:
    def __init__(self, factory, pool_size: int = 5):
        self.pool = queue.Queue(maxsize=pool_size)
        for _ in range(pool_size):
            self.pool.put(factory())

    def get(self) -> Agent:
        return self.pool.get()

    def release(self, agent: Agent):
        agent.messages.clear()
        self.pool.put(agent)
```

---

## Testing Patterns

### Unit Test Tools

```python
def test_search_tool():
    result = search_database(query="test", limit=5)
    assert result["status"] == "success"
    assert "content" in result
```

### Integration Test Agent

```python
from unittest.mock import Mock

def test_agent_uses_tool():
    mock_tool = Mock(return_value={
        "status": "success",
        "content": [{"text": "mocked"}],
    })
    mock_tool.__name__ = "mock_tool"
    mock_tool.__doc__ = "A mock tool."

    agent = Agent(
        system_prompt="Use mock_tool for everything.",
        tools=[mock_tool],
    )
    result = agent("Do the thing")
    assert mock_tool.called
```

### Local Development

Test agents locally before deploying:

```python
# Run agent locally (no AgentCore needed)
agent = Agent(
    model=BedrockModel(model_id="anthropic.claude-sonnet-4-5-20250929-v1:0"),
    tools=[my_tool],
    system_prompt="You are helpful.",
)

# Interactive loop
while True:
    user_input = input("You: ")
    if user_input.lower() in ("exit", "quit"):
        break
    result = agent(user_input)
    print(f"Agent: {result.message['content'][0]['text']}")
```

---

## Conversation Management

### Short Sessions (< 10 exchanges)

```python
from strands.agent.conversation_manager import SlidingWindowConversationManager

manager = SlidingWindowConversationManager(max_messages=15, min_messages=2)
agent = Agent(conversation_manager=manager)
```

### Long Sessions (need history)

```python
from strands.agent.conversation_manager import SummarizingConversationManager

manager = SummarizingConversationManager(
    max_messages=30,
    summarize_messages_count=25,
)
agent = Agent(conversation_manager=manager)
```

---

## Error Handling

### Retry with Backoff

```python
import time
import random
from botocore.exceptions import ClientError


def invoke_with_retry(agent: Agent, query: str, max_retries: int = 3):
    for attempt in range(max_retries):
        try:
            return agent(query)
        except ClientError as e:
            if e.response["Error"]["Code"] == "ThrottlingException":
                wait = (2 ** attempt) + random.uniform(0, 1)
                time.sleep(wait)
            else:
                raise
    raise Exception("Max retries exceeded")
```

### Tool Error Wrapper

```python
def safe_tool_call(func):
    """Decorator to catch exceptions and return structured errors."""
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            return {
                "status": "error",
                "content": [{"text": f"{func.__name__} failed: {str(e)}"}],
            }
    wrapper.__name__ = func.__name__
    wrapper.__doc__ = func.__doc__
    return wrapper
```
