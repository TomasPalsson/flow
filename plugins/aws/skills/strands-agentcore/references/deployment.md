# Deployment to Bedrock AgentCore

Complete guide to deploying Strands agents and MCP servers to AgentCore Runtime.

## Table of Contents

1. [Deployment Architectures](#deployment-architectures)
2. [AgentCore Runtime Deployment](#agentcore-runtime-deployment)
3. [Dockerfile Patterns](#dockerfile-patterns)
4. [IAM Configuration](#iam-configuration)
5. [Networking](#networking)
6. [CLI Commands Reference](#cli-commands-reference)
7. [Lambda Deployment](#lambda-deployment)
8. [ECS/Fargate for MCP Servers](#ecsFargate-for-mcp-servers)
9. [Hybrid Architecture](#hybrid-architecture)
10. [Starter Toolkit](#starter-toolkit)

---

## Deployment Architectures

| Component | Lambda | ECS/Fargate | AgentCore Runtime |
|-----------|--------|-------------|-------------------|
| Stateless Agents | Best | Overkill | Overkill |
| Interactive/Streaming | No | Possible | Best |
| MCP Servers | NEVER | Standard | With features |
| Duration limit | 15 min | Unlimited | 8 hours |
| Cold starts | Yes (30-60s) | No | No |
| Session isolation | None | Shared | microVM per session |
| Auto-scaling | Yes | Manual/ECS | Automatic |
| Identity integration | Manual | Manual | Built-in |

---

## AgentCore Runtime Deployment

### Step 1: Create the Agent App

```python
# agent.py
from strands import Agent
from strands.models import BedrockModel
from bedrock_agentcore.runtime import BedrockAgentCoreApp

app = BedrockAgentCoreApp()

agent = Agent(
    model=BedrockModel(
        model_id="anthropic.claude-sonnet-4-5-20250929-v1:0",
        region_name="us-east-1",
    ),
    tools=[my_tool],
    system_prompt="You are helpful.",
)

@app.entrypoint
def handler(payload):
    return agent(payload["prompt"]).message["content"][0]["text"]
```

### Step 2: Create requirements.txt

```
strands-agents>=1.16.0
strands-agents[otel]
bedrock-agentcore>=1.0.6
aws-opentelemetry-distro
```

### Step 3: Build Docker Image

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["python", "agent.py"]
```

### Step 4: Push to ECR

```bash
# Create ECR repository
aws ecr create-repository --repository-name my-agent --region us-east-1

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

# Build and push
docker build -t my-agent .
docker tag my-agent:latest $ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/my-agent:latest
docker push $ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/my-agent:latest
```

### Step 5: Create AgentCore Runtime

```bash
aws bedrock-agentcore-control create-agent-runtime \
  --agent-runtime-name my-agent \
  --agent-runtime-artifact containerConfiguration={containerUri=$ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/my-agent:latest} \
  --role-arn arn:aws:iam::$ACCOUNT:role/AgentCoreRuntimeRole \
  --network-configuration networkMode=PUBLIC \
  --protocol-configuration serverProtocol=HTTP \
  --region us-east-1
```

### Step 6: Verify Deployment

```bash
# Check status
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id my-agent-XXXXXXXXXX \
  --region us-east-1 \
  --query 'status' \
  --output text

# Should return: ACTIVE
```

---

## Dockerfile Patterns

### Strands Agent

```dockerfile
FROM --platform=linux/arm64 python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["python", "agent.py"]
```

### MCP Server (deployed as AgentCore Runtime)

```dockerfile
FROM --platform=linux/arm64 python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# MCP servers listen on 0.0.0.0:8000 when self-hosted, 0.0.0.0:8080 when on AgentCore
EXPOSE 8080

CMD ["python", "mcp_server.py"]
```

### With OpenTelemetry Instrumentation

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV AGENT_OBSERVABILITY_ENABLED=true
ENV OTEL_PYTHON_DISTRO=aws_distro
ENV OTEL_PYTHON_CONFIGURATOR=aws_configurator
ENV OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
ENV OTEL_RESOURCE_ATTRIBUTES="service.name=my-agent"

EXPOSE 8000

# Use opentelemetry-instrument to auto-instrument
CMD ["opentelemetry-instrument", "python", "agent.py"]
```

---

## IAM Configuration

### Agent Runtime Role

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:GetAuthorizationToken"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
```

### Trust Policy

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "bedrock-agentcore.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

### Additional Permissions (as needed)

```json
{
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"],
            "Resource": "arn:aws:dynamodb:*:*:table/agent-sessions"
        },
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject"],
            "Resource": "arn:aws:s3:::agent-data/*"
        }
    ]
}
```

---

## Networking

### PUBLIC Mode

Agent is accessible via the AgentCore endpoint. Simplest option.

```bash
--network-configuration networkMode=PUBLIC
```

### VPC Mode

Agent runs inside a VPC with access to private resources.

```bash
--network-configuration networkMode=VPC,subnetIds=subnet-abc123,securityGroupIds=sg-xyz789
```

Use VPC mode when:
- Agent needs to access private databases
- Agent connects to internal MCP servers
- Compliance requires network isolation

---

## CLI Commands Reference

### Create Runtime
```bash
aws bedrock-agentcore-control create-agent-runtime \
  --agent-runtime-name <name> \
  --agent-runtime-artifact containerConfiguration={containerUri=<ecr-uri>} \
  --role-arn <role-arn> \
  --network-configuration networkMode=PUBLIC \
  --protocol-configuration serverProtocol=HTTP \
  --region <region>
```

### Get Runtime Status
```bash
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id <runtime-id> \
  --region <region>
```

### Update Runtime
```bash
aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id <runtime-id> \
  --agent-runtime-artifact containerConfiguration={containerUri=<new-ecr-uri>} \
  --region <region>
```

### Delete Runtime
```bash
aws bedrock-agentcore-control delete-agent-runtime \
  --agent-runtime-id <runtime-id> \
  --region <region>
```

### Invoke Agent
```bash
# Via the invocation endpoint
curl -X POST "https://bedrock-agentcore.<region>.amazonaws.com/runtimes/<runtime-id>/invocations" \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Hello, how are you?"}'
```

---

## Lambda Deployment

For stateless, event-driven agents only.

```python
# lambda_handler.py
from strands import Agent
from strands.models import BedrockModel

def lambda_handler(event, context):
    agent = Agent(
        model=BedrockModel(model_id="anthropic.claude-sonnet-4-5-20250929-v1:0"),
        system_prompt="Process this task.",
        tools=[my_tool],
    )
    result = agent(event["query"])
    return {
        "statusCode": 200,
        "body": result.message["content"][0]["text"],
    }
```

**Limitations**:
- No streaming
- 15-minute max duration
- Cold starts (30-60s)
- No persistent connections (breaks MCP servers)
- No session isolation

---

## ECS/Fargate for MCP Servers

MCP servers need persistent connections — Lambda cannot host them.

```python
# mcp_server.py
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("My Tools", host="0.0.0.0", port=8000, stateless_http=True)

@mcp.tool()
def my_tool(param: str) -> dict:
    """Tool description."""
    return {"status": "success", "content": [{"text": "result"}]}

if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

**ECS Task Definition** (key settings):
- Container port: 8000
- Health check: `/mcp` endpoint
- CPU: 256-1024 (depending on load)
- Memory: 512-2048 MB

---

## Hybrid Architecture

The recommended production pattern combines all three:

```
Events (S3/SQS)  → Lambda Agents  → HTTP → ECS MCP Servers
API Gateway       → Lambda Agents  → HTTP → ECS MCP Servers
Web/Chat Client   → AgentCore Runtime      → HTTP → ECS MCP Servers
```

- **Lambda**: Handles event-driven, stateless workloads
- **AgentCore Runtime**: Powers interactive, streaming agents with identity
- **ECS/Fargate**: Hosts MCP tool servers with persistent connections

---

## Starter Toolkit

The `bedrock-agentcore-starter-toolkit` package simplifies deployment:

```python
from bedrock_agentcore_starter_toolkit import Runtime

runtime = Runtime()
runtime.configure(
    entrypoint="agent.py",
    requirements_file="requirements.txt",
)
runtime.launch()
```

Install:
```bash
pip install bedrock-agentcore-starter-toolkit
```

This handles ECR push, IAM role creation, and runtime provisioning automatically.

---

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `AWS_REGION` | AWS region for Bedrock calls |
| `DEFAULT_MODEL_ID` | Default model ID |
| `SESSION_TABLE` | DynamoDB table for sessions |
| `AGENT_OBSERVABILITY_ENABLED` | Enable OTEL tracing |
| `OTEL_PYTHON_DISTRO` | Set to `aws_distro` |
| `OTEL_RESOURCE_ATTRIBUTES` | `service.name=my-agent` |
