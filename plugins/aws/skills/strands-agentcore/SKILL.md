---
name: strands-agentcore
description: "Build production-quality AI agents using AWS Strands Agents SDK and deploy them to Amazon Bedrock AgentCore. Use this skill whenever the user mentions Strands agents, Bedrock AgentCore, AgentCore Runtime, AgentCore Identity, Bedrock Identity, workload identity, MCP servers on AWS, agent deployment to AWS, or building AI agents with Python on AWS. Also trigger when you see imports like `from strands import Agent`, `from bedrock_agentcore`, `from strands.models import BedrockModel`, or discussions about OAuth/auth in agent contexts, agent-to-user authentication flows, or deploying agents with identity providers (Google, GitHub, Cognito, Okta). This skill covers the full lifecycle: agent creation, tool design, Bedrock Identity with programmatic OAuth (custom auth URLs, workload identities), MCP server patterns, multi-agent orchestration, and production deployment with observability."
---

# AWS Strands Agents & Bedrock AgentCore

You are building production AI agents using the Strands Agents SDK deployed to Amazon Bedrock AgentCore. This skill covers the full lifecycle from agent creation through production deployment with enterprise authentication.

## Core Concepts

**Strands Agents SDK**: Open-source Python framework where the model drives orchestration. You define tools and a system prompt; the model decides what to call and when. Minimal code, maximum flexibility.

**Amazon Bedrock AgentCore**: Enterprise platform providing managed infrastructure — 8-hour runtimes, session isolation in microVMs, streaming, identity management, observability, and auto-scaling. Optional but recommended for production.

**Bedrock Identity**: AgentCore's authentication layer. Integrates with Cognito, Okta, Entra ID, Google, GitHub, and custom OIDC providers. Supports both the simple `@requires_access_token` decorator AND programmatic workload identity flows for full control over OAuth URLs.

---

## Decision Tree

**What are you building?**

| Scenario | Recommendation |
|----------|---------------|
| Stateless event-driven agent | Lambda |
| Interactive agent with streaming | AgentCore Runtime |
| MCP tool server | ECS/Fargate or AgentCore Runtime (NEVER Lambda) |
| Multi-agent system | AgentCore Runtime |
| Agent needing user OAuth (Google, GitHub, etc.) | AgentCore Runtime + Bedrock Identity |

**MCP servers MUST use `streamable-http` transport** — Lambda's ephemeral nature breaks persistent connections.

---

## Common Pitfalls — Things That Will Break Your Agent

- **NEVER stack `@tool` and `@requires_access_token` on the same function** — causes parameter parsing interference where the model tries to fill `access_token` as input. Use separate wrapper + implementation functions.
- **NEVER use port 8000 for AgentCore containers** — must be `0.0.0.0:8080`. MCP servers use 8000 when self-hosted, but AgentCore Runtime expects 8080.
- **NEVER build x86 containers** — AgentCore requires ARM64 (`--platform linux/arm64`). Use `docker buildx` for cross-compilation.
- **NEVER use session IDs under 33 characters** — API validation rejects them. Use UUIDs.
- **NEVER deploy MCP servers to Lambda** — ephemeral runtime breaks persistent connections and connection pools. Use ECS/Fargate or AgentCore Runtime.
- **NEVER expect code updates in active sessions** — each microVM uses the version from session creation. Users must start new sessions to get updated code.
- **NEVER use VPC mode without a NAT Gateway** — your agent won't reach Bedrock models or external APIs. Place ENIs in private subnets routed through NAT in public subnets.
- **NEVER omit `aws-opentelemetry-distro` from requirements** — observability silently fails without it, and you get no traces in CloudWatch.
- **NEVER assume cached OAuth tokens are valid** — providers can revoke at any time. Implement `force_authentication=True` as a fallback when API calls fail with 401.
- **NEVER use `@requires_access_token` when you need to surface the auth URL to users** — the decorator blocks until auth completes. Use the programmatic Workload pattern to capture and return the URL.
- **NEVER let tools raise exceptions** — return `{"status": "error", "content": [{"text": "..."}]}` dicts so the model can reason about failures and retry.

---

## Authentication: Two Approaches

This is the most critical architectural decision for agents that need to act on behalf of users.

### Approach 1: Simple — `@requires_access_token` Decorator

The decorator handles the OAuth dance automatically. Good for simple cases where you don't need control over the flow.

**Critical**: `@requires_access_token` and `@tool` MUST be on SEPARATE functions. Stacking them on the same function causes parameter parsing interference — the model tries to fill `access_token` as an input parameter. Use an inner implementation function:

```python
from bedrock_agentcore.identity.auth import requires_access_token
from strands import tool

@tool
def list_drive_files(query: str = "") -> dict:
    """List files from Google Drive."""
    return _list_drive_files_impl(query)

@requires_access_token(
    provider_name="google-oauth",
    scopes=["https://www.googleapis.com/auth/drive"],
    auth_flow="USER_FEDERATION",
    on_auth_url=lambda url: print(f"Auth URL: {url}"),
)
def _list_drive_files_impl(query: str = "", *, access_token: str = "") -> dict:
    creds = Credentials(token=access_token)
    service = build("drive", "v3", credentials=creds)
    return service.files().list(q=query).execute()
```

**Limitation**: The decorator manages auth behind the scenes. The agent cannot easily surface the authorization URL to the user in a structured way. For interactive agents where you need to return the auth URL as a tool response (e.g., "click this link to authorize"), use the programmatic approach instead.

### Approach 2: Programmatic — Workload Identity with Custom Auth URLs

When you need full control — especially when the agent must return an authorization URL to the user — use the `IdentityClient` directly. **Read `references/identity.md` for the complete deep-dive on this pattern.**

```python
from bedrock_agentcore.services.identity import IdentityClient
from bedrock_agentcore.identity.auth import _get_region

class Workload:
    def __init__(self, callback_url="https://your-domain.com/redirect"):
        self.client = IdentityClient(_get_region())
        self.callback_url = callback_url

    async def get_oauth_url(self, provider_name, scopes, user_id):
        """Get OAuth URL that the agent can return to the user."""
        agent_token = await self.get_workload_access_token(user_id)

        url_future = asyncio.get_running_loop().create_future()

        def on_auth_url(url: str):
            if not url_future.done():
                url_future.set_result(url)

        async def _run_flow():
            try:
                await self.client.get_token(
                    provider_name=provider_name,
                    agent_identity_token=agent_token,
                    scopes=scopes,
                    on_auth_url=on_auth_url,        # Capture the URL
                    auth_flow="USER_FEDERATION",
                    callback_url=self.callback_url,
                    force_authentication=True,
                )
            except Exception as e:
                if not url_future.done():
                    url_future.set_exception(e)

        asyncio.create_task(_run_flow())
        return await url_future  # Returns the auth URL string
```

The key insight: `on_auth_url` is a callback that fires with the authorization URL before the OAuth flow completes. By capturing it with an `asyncio.Future`, you can return it to the user immediately while the flow waits for completion in the background.

---

## MCP Server Pattern with Identity

For agents deployed as MCP servers in AgentCore, combine FastMCP with the Workload pattern:

```python
from mcp.server.fastmcp import FastMCP
from workload import Workload

mcp = FastMCP(host="0.0.0.0", port=8000, stateless_http=True)
workload = Workload()

@mcp.tool()
async def authenticate_user() -> dict:
    """Get OAuth authorization URL for the user to grant access."""
    return await workload.get_google_auth_url()

@mcp.tool()
async def list_files(query: str = "") -> dict:
    """List files from Google Drive."""
    token = await workload.get_token()
    if isinstance(token, dict):  # Auth required
        return token
    # Use token to call Google API...

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

The tools return structured auth responses that the calling agent surfaces to the user:
```python
{
    "type": "authorization_required",
    "authorization_url": "https://accounts.google.com/o/oauth2/...",
    "message": "Open this link to grant access to Google Drive."
}
```

---

## Tool Design

Tools use the `@tool` decorator. The docstring becomes the model's tool description — make it specific and include `Args:` descriptions. Always return `{"status": "success/error", "content": [{"text": "..."}]}` dicts, never raise exceptions. See `references/patterns.md` for task-oriented design, pagination, async tools, and the `ToolContext` injection pattern.

### MCP Tool Integration

```python
from strands.tools.mcp import MCPClient
from mcp import streamablehttp_client

client = MCPClient(lambda: streamablehttp_client("http://mcp-server:8000/mcp"))
with client:
    tools = client.list_tools_sync()

agent = Agent(tools=tools)
```

---

## Session & Conversation Management

```python
from strands import Agent
from strands.models import BedrockModel
from strands.session import DynamoDBSessionManager
from strands.agent.conversation_manager import SlidingWindowConversationManager

agent = Agent(
    agent_id="my-agent",
    model=BedrockModel(model_id="anthropic.claude-sonnet-4-5-20250929-v1:0"),
    system_prompt="You are helpful.",
    tools=[tool1, tool2],
    session_manager=DynamoDBSessionManager(table_name="agent-sessions"),
    conversation_manager=SlidingWindowConversationManager(max_messages=20),
)
```

| Session Backend | Use Case |
|----------------|----------|
| `FileSystem` | Local dev only |
| `S3` | Serverless, simple |
| `DynamoDB` | Production (low latency, multi-region) |
| `AgentCore Memory` | Cross-session intelligence, knowledge graphs |

For long sessions needing history summarization:
```python
from strands.agent.conversation_manager import SummarizingConversationManager
manager = SummarizingConversationManager(max_messages=30, summarize_messages_count=25)
```

---

## Multi-Agent Patterns

### Agent-as-Tool (Simple Delegation)
```python
researcher = Agent(system_prompt="Research specialist.", tools=[web_search])

@tool
def research_topic(topic: str) -> str:
    """Delegate research to a specialist agent."""
    result = researcher(f"Research: {topic}")
    return result.message["content"][0]["text"]

orchestrator = Agent(tools=[research_topic, write_article])
```

### Graph (Deterministic Workflow)
```python
from strands.multiagent import GraphBuilder
builder = GraphBuilder()
builder.add_node("collector", data_agent)
builder.add_node("analyser", analysis_agent)
builder.add_edge("collector", "analyser")
graph = builder.build(entry_point="collector")
```

### Swarm (Autonomous Collaboration)
```python
from strands.multiagent import Swarm
swarm = Swarm(nodes=[agent_a, agent_b, agent_c], entry_point=agent_a, max_handoffs=10)
```

**Cost warning**: Multi-agent systems multiply costs — Agent-as-Tool 2-3x, Graph 3-5x, Swarm 5-8x.

---

## Deployment to AgentCore Runtime

**Read `references/deployment.md` for the complete deployment guide including Dockerfile, IAM, networking, and CLI commands.**

### Minimal AgentCore App

```python
from strands import Agent
from strands.models import BedrockModel
from bedrock_agentcore.runtime import BedrockAgentCoreApp

app = BedrockAgentCoreApp()
agent = Agent(
    model=BedrockModel(model_id="anthropic.claude-sonnet-4-5-20250929-v1:0"),
    tools=[my_tool],
    system_prompt="You are helpful.",
)

@app.entrypoint
def handler(payload):
    return agent(payload["prompt"]).message["content"][0]["text"]
```

### Critical Deployment Details

- **Port 8080** — Containers must listen on `0.0.0.0:8080` (not 8000)
- **ARM64 required** — All containers must be `linux/arm64` (AWS Graviton)
- **Session IDs min 33 chars** — Use UUIDs for session identifiers
- **Two deployment paths**: Container (ECR) or Direct Code (S3 zip, no Docker needed)

### Create Runtime via CLI

```bash
aws bedrock-agentcore-control create-agent-runtime \
  --agent-runtime-name my-agent \
  --agent-runtime-artifact containerConfiguration={containerUri=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/my-agent:latest} \
  --role-arn $ROLE_ARN \
  --network-configuration networkMode=PUBLIC \
  --protocol-configuration serverProtocol=HTTP \
  --region $REGION
```

---

## Production Checklist

Read `references/production.md` for observability, evaluations, security patterns, and cost tracking.

- [ ] Conversation manager configured (SlidingWindow or Summarizing)
- [ ] Session backend set (DynamoDB for production)
- [ ] Error handling in all tools (return structured errors, never raise)
- [ ] Bedrock Identity configured if user auth needed
- [ ] AgentCore Observability enabled (`strands-agents[otel]` + `aws-opentelemetry-distro`)
- [ ] Cost tracking hooks implemented
- [ ] Tool permissions validated (principle of least privilege)
- [ ] MCP servers on ECS/Fargate or AgentCore (never Lambda)
- [ ] CloudWatch alarms configured
- [ ] Timeout limits set on all external calls

---

## Reference Files

| File | When to Read | Do NOT Load When |
|------|-------------|-----------------|
| `references/identity.md` | Building agents with OAuth/user auth, workload identities, custom auth URLs | Simple agents without user authentication |
| `references/deployment.md` | Deploying to AgentCore Runtime, Dockerfile, IAM, networking, CLI | Local development only, not deploying yet |
| `references/patterns.md` | Agent factories, tool design, security hooks, testing, performance | Quick prototype with a single tool |
| `references/production.md` | Observability, evaluations, cost tracking, monitoring, security | Development phase, pre-deployment |

## Model Selection

| Model | Use Case | Model ID |
|-------|----------|----------|
| Claude Sonnet 4.5 | Production default | `anthropic.claude-sonnet-4-5-20250929-v1:0` |
| Claude Haiku 4.5 | Fast/economical | `anthropic.claude-haiku-4-5-20251001-v1:0` |
| Claude Opus 4.5 | Complex reasoning | `anthropic.claude-opus-4-5-20250514-v1:0` |
