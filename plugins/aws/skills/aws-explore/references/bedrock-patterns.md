---
name: bedrock-patterns
description: Bedrock and AgentCore CLI patterns — model availability, agent status, runtime debugging, namespace reference
---

# Bedrock & AgentCore Exploration Patterns

## Quick Reference

```bash
# Available foundation models
aws-explore bedrock models [provider]

# Agents + knowledge bases + guardrails
aws-explore bedrock agents

# AgentCore runtimes, gateways, memories, browsers, code interpreters
aws-explore bedrock agentcore

# Find all FAILED resources
aws-explore bedrock debug
```

## The Four CLI Namespaces

This is the most important thing to understand — there are **four separate namespaces**, not two:

| Namespace | Purpose | Example |
|---|---|---|
| `aws bedrock` | Foundation models, custom models, guardrails, inference profiles | `list-foundation-models` |
| `aws bedrock-agent` | Agents, knowledge bases, data sources, flows (control plane) | `list-agents`, `list-knowledge-bases` |
| `aws bedrock-agent-runtime` | Invocations, sessions, memory retrieval (data plane) | `list-sessions`, `invoke-agent` |
| `aws bedrock-agentcore-control` | AgentCore runtimes, gateways, memories, browsers, code interpreters | `list-agent-runtimes`, `list-gateways` |

**`bedrock-agent` != `bedrock-agentcore-control`** — classic Bedrock Agents (managed) vs AgentCore (bring-your-own container).

There's also `aws bedrock-agentcore` (data plane) for invoking runtimes and managing sessions, but it requires a per-runtime `--endpoint-url`.

## Common Debugging Scenarios

### "Is my model available in this region?"

```bash
aws bedrock list-foundation-models --by-provider Anthropic --no-cli-pager \
  --query 'modelSummaries[?modelLifecycle.status==`ACTIVE`].{ID: modelId, Status: modelLifecycle.status}'
```

### "Why is my agent failing?"

```bash
# Check agent status
aws bedrock-agent list-agents --no-cli-pager \
  --query 'agentSummaries[].[agentId, agentName, agentStatus]' --output text

# If FAILED or NOT_PREPARED, get details (omit instruction to save context)
aws bedrock-agent get-agent --agent-id AGENT_ID --no-cli-pager \
  --query 'agent.[agentId, agentName, agentStatus, foundationModel, failureReasons]'
```

### "Is the knowledge base synced?"

```bash
# Check KB status
aws bedrock-agent list-knowledge-bases --no-cli-pager \
  --query 'knowledgeBaseSummaries[].[knowledgeBaseId, name, status]' --output text

# Check ingestion job status
aws bedrock-agent list-ingestion-jobs --knowledge-base-id KB_ID --data-source-id DS_ID --no-cli-pager \
  --query 'ingestionJobSummaries[].[ingestionJobId, status, startedAt]' --output text
```

### "Is my AgentCore runtime healthy?"

```bash
# Runtime status
aws bedrock-agentcore-control list-agent-runtimes --no-cli-pager \
  --query 'agentRuntimes[].[agentRuntimeId, agentRuntimeName, status]' --output text

# If READY, check endpoints
aws bedrock-agentcore-control list-agent-runtime-endpoints --agent-runtime-id RUNTIME_ID --no-cli-pager \
  --query 'endpoints[].[endpointId, status]' --output text

# Full runtime config (networking, env vars, container)
aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id RUNTIME_ID --no-cli-pager
```

### "Gateway not working?"

```bash
# Gateway status + auth config
aws bedrock-agentcore-control list-gateways --no-cli-pager \
  --query 'items[].[gatewayId, name, status, protocolType, authorizerType]' --output text

# Full config including exception level
aws bedrock-agentcore-control get-gateway --gateway-identifier GW_ID --no-cli-pager

# Check gateway targets
aws bedrock-agentcore-control list-gateway-targets --gateway-identifier GW_ID --no-cli-pager
```

## Useful Commands

### Foundation Models

```bash
# All active models from a provider
aws bedrock list-foundation-models --by-provider Anthropic --no-cli-pager \
  --query 'modelSummaries[?modelLifecycle.status==`ACTIVE`].modelId' --output text

# Models that support streaming
aws bedrock list-foundation-models --by-inference-type ON_DEMAND --no-cli-pager \
  --query 'modelSummaries[?responseStreamingSupported==`true`].[modelId, providerName]' --output text

# Custom models
aws bedrock list-custom-models --no-cli-pager \
  --query 'modelSummaries[].[modelName, baseModelName, customizationType, modelStatus]' --output text

# Provisioned throughput status
aws bedrock list-provisioned-model-throughputs --no-cli-pager \
  --query 'provisionedModelSummaries[].[provisionedModelName, status, modelUnits]' --output text
```

### Agents

```bash
# Agent aliases (needed for invocation)
aws bedrock-agent list-agent-aliases --agent-id AGENT_ID --no-cli-pager \
  --query 'agentAliasSummaries[].[agentAliasId, agentAliasName, agentAliasStatus]' --output text

# Agent's model and status (excluding instruction field — it can be huge)
aws bedrock-agent get-agent --agent-id AGENT_ID --no-cli-pager \
  --query 'agent.[agentId, agentName, agentStatus, foundationModel, updatedAt]'
```

### Knowledge Bases

```bash
# Data sources for a KB
aws bedrock-agent list-data-sources --knowledge-base-id KB_ID --no-cli-pager \
  --query 'dataSourceSummaries[].[dataSourceId, name, status]' --output text

# Full KB config (vector store, embedding model, chunking strategy)
aws bedrock-agent get-knowledge-base --knowledge-base-id KB_ID --no-cli-pager
```

### AgentCore Resources

```bash
# Memory stores
aws bedrock-agentcore-control list-memories --no-cli-pager \
  --query 'memories[].[id, status]' --output text

# Memory detail (use without_decryption to avoid exposing secrets)
aws bedrock-agentcore-control get-memory --memory-id MEM_ID --view without_decryption --no-cli-pager

# Browsers and code interpreters
aws bedrock-agentcore-control list-browsers --no-cli-pager \
  --query 'browsers[].[browserId, name, status]' --output text
aws bedrock-agentcore-control list-code-interpreters --no-cli-pager \
  --query 'codeInterpreters[].[codeInterpreterId, name, status]' --output text

# Workload identities
aws bedrock-agentcore-control list-workload-identities --no-cli-pager \
  --query 'workloadIdentities[].[name, workloadIdentityArn]' --output text

# Credential providers
aws bedrock-agentcore-control list-api-key-credential-providers --no-cli-pager
aws bedrock-agentcore-control list-oauth2-credential-providers --no-cli-pager
```

## CloudWatch Logs for AgentCore

### Log Group Architecture

Each AgentCore runtime creates log groups under `/aws/bedrock-agentcore/runtimes/`. OTEL trace spans go to a shared `aws/spans` group.

| Log Group | Contains |
|---|---|
| `/aws/bedrock-agentcore/runtimes/<runtime-name>/` | Runtime stdout/stderr, Python logging |
| `aws/spans` | OTEL trace spans (shared across all runtimes) |

### Finding Log Groups

```bash
# Find all log groups for a runtime prefix
aws-explore bedrock logs naestaskref

# Or manually:
aws logs describe-log-groups --no-cli-pager \
  --log-group-name-prefix "/aws/bedrock-agentcore/runtimes/naestaskref" \
  --query 'logGroups[].logGroupName' --output text
```

### Tailing Logs

```bash
# Live tail (shorthand — auto-prepends the AgentCore prefix)
aws-explore bedrock tail naestaskref_tomas_vegvisir-cWC2xaChqq-prod

# Or with full path
aws logs tail "/aws/bedrock-agentcore/runtimes/naestaskref_tomas_vegvisir-cWC2xaChqq-prod" \
  --follow --since 10m --format short --no-cli-pager
```

### Searching for Errors

```bash
# Recent errors in runtime logs
aws logs filter-log-events --no-cli-pager \
  --log-group-name "/aws/bedrock-agentcore/runtimes/<runtime-name>" \
  --filter-pattern "ERROR" --max-items 20 \
  --query 'events[].{Time:timestamp,Message:message}'
```

## OTEL Trace Spans (Strands Agents)

### Span Types

Strands emits 4 span types per agent invocation:

| Span Name | Operation | Key Attributes |
|---|---|---|
| `invoke_agent {name}` | `invoke_agent` | `gen_ai.agent.name`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens` |
| `execute_event_loop_cycle` | cycle | `event_loop.cycle_id` |
| `chat` | model call | `gen_ai.request.model`, `gen_ai.usage.*_tokens`, `gen_ai.server.time_to_first_token` |
| `execute_tool {name}` | tool call | `gen_ai.tool.name`, `gen_ai.tool.call.id`, `gen_ai.tool.status` |

### Span Hierarchy

```
invoke_agent my-agent              (root span — total invocation)
└── execute_event_loop_cycle       (cycle 1)
    ├── chat                       (LLM call — has token counts)
    └── execute_tool calculator    (tool call — has tool status)
└── execute_event_loop_cycle       (cycle 2, if tool result triggers another LLM call)
    └── chat
```

### Querying Traces

```bash
# Recent traces for a runtime
aws-explore bedrock traces naestaskref_tomas_vegvisir

# Last 2 hours
aws-explore bedrock traces naestaskref_tomas_vegvisir 2h

# All spans for a specific trace
aws-explore bedrock trace 4bf92f3577b34da6a3ce929d0e0e4736
```

### Useful Insights Queries (manual)

Run these against the `aws/spans` log group via `aws logs start-query`:

```
# Slow invocations (>5s)
fields @timestamp, traceId, name, durationNano/1000000 as ms,
  attributes.`gen_ai.agent.name` as agent
| filter name like "invoke_agent" and durationNano > 5000000000
| sort @timestamp desc | limit 20

# Token usage by agent
fields attributes.`gen_ai.agent.name` as agent,
  attributes.`gen_ai.usage.input_tokens` as input,
  attributes.`gen_ai.usage.output_tokens` as output
| filter name like "invoke_agent"
| stats sum(input) as total_input, sum(output) as total_output by agent

# Failed tool calls
fields @timestamp, traceId, attributes.`gen_ai.tool.name` as tool,
  attributes.`gen_ai.tool.status` as status
| filter name like "execute_tool" and status != "success"
| sort @timestamp desc | limit 20

# Error rate over time
fields name
| filter name like "invoke_agent"
| stats count(*) as total,
  count_distinct(case when status.code = "ERROR" then traceId end) as errors
  by bin(1h)
```

### Debugging Missing Traces

If traces aren't appearing in `aws/spans`:

1. **Check `aws-opentelemetry-distro` is installed** — traces silently fail without it. This is the #1 cause.
2. **Check runtime logs for OTEL errors** — `aws-explore bedrock tail <runtime>` and look for OTEL/telemetry errors
3. **Verify Transaction Search is enabled** — one-time account setup:
   ```bash
   aws xray update-trace-segment-destination --destination CloudWatchLogs --no-cli-pager
   ```
4. **Check the `otel-rt-logs` stream** — if it exists, the OTEL collector is running but may be misconfigured

## Gotchas

- **`get-agent` instruction field can be thousands of tokens** — always exclude it unless debugging behavior: `--query 'agent.[agentId, agentName, agentStatus, foundationModel]'`
- **`get-memory --view full` may include decrypted credentials** — use `--view without_decryption`
- **`list-foundation-models` bare = 100+ models** — always filter with `--by-provider` or `--by-inference-type`
- **AgentCore data plane needs `--endpoint-url`** — the per-runtime endpoint, not the regional endpoint
- **No global session listing** — `list-browser-sessions` and `list-code-interpreter-sessions` require a resource ID
- **No CLI access to runtime execution logs** — use `aws logs` with the appropriate log group
- **`bedrock-agent` agent != `bedrock-agentcore-control` agent runtime** — completely different resources

## Status Values Reference

| Resource | Statuses |
|---|---|
| Foundation model lifecycle | ACTIVE, LEGACY, EOL |
| Agent | CREATING, PREPARING, PREPARED, NOT_PREPARED, DELETING, FAILED, VERSIONING, UPDATING |
| Knowledge base | CREATING, ACTIVE, DELETING, UPDATING, FAILED |
| Ingestion job | STARTING, IN_PROGRESS, COMPLETE, FAILED, STOPPING, STOPPED |
| Agent runtime | CREATING, CREATE_FAILED, UPDATING, UPDATE_FAILED, READY, DELETING |
| Gateway | CREATING, UPDATING, UPDATE_UNSUCCESSFUL, DELETING, READY, FAILED |
| Memory | CREATING, ACTIVE, FAILED, DELETING |
