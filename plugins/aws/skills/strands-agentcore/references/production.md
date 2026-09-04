# Production Operations

## Table of Contents

1. [Observability](#observability)
2. [AgentCore Evaluations](#agentcore-evaluations)
3. [Cost Tracking](#cost-tracking)
4. [Monitoring & Alerts](#monitoring--alerts)
5. [Security Hardening](#security-hardening)
6. [Known Limitations](#known-limitations)

---

## Observability

### AgentCore Observability (Managed)

Automatic instrumentation for agents running on AgentCore Runtime.

**Setup**:
```bash
pip install 'strands-agents[otel]' aws-opentelemetry-distro
```

**Agent code**:
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

Traces appear automatically in the CloudWatch GenAI Observability Dashboard.

**Enable Transaction Search** (one-time):
```bash
aws logs put-resource-policy --policy-name AgentCoreObs --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "xray.amazonaws.com"},
    "Action": "logs:PutLogEvents",
    "Resource": ["arn:aws:logs:*:*:log-group:aws/spans:*"]
  }]
}'

aws xray update-trace-segment-destination --destination CloudWatchLogs
```

### Self-Hosted Observability

For agents not on AgentCore Runtime:

```bash
export AGENT_OBSERVABILITY_ENABLED=true
export OTEL_PYTHON_DISTRO=aws_distro
export OTEL_PYTHON_CONFIGURATOR=aws_configurator
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_RESOURCE_ATTRIBUTES="service.name=my-agent"

opentelemetry-instrument python agent.py
```

### OpenTelemetry Fluent API

```python
from strands.observability import StrandsTelemetry

# Development
telemetry = StrandsTelemetry().setup_console_exporter()

# Production
telemetry = StrandsTelemetry().setup_otlp_exporter()

# Both
telemetry = StrandsTelemetry() \
    .setup_console_exporter() \
    .setup_otlp_exporter() \
    .setup_meter(enable_otlp_exporter=True)
```

### Custom Trace Attributes

```python
agent = Agent(
    system_prompt="...",
    tools=[...],
    trace_attributes={
        "environment": "production",
        "customer_tier": "enterprise",
        "region": "us-east-1",
    },
)
```

### Session Tracking

```python
from opentelemetry import baggage, context

session_id = "user-123-session-456"
ctx = baggage.set_baggage("session.id", session_id)

with context.attach(ctx):
    response = agent("First question")
    response = agent("Follow-up")
```

### Automatic Metrics

```python
result = agent("Query")
metrics = result.metrics

print(metrics.accumulated_usage["totalTokens"])
print(metrics.accumulated_usage["inputTokens"])
print(metrics.accumulated_usage["outputTokens"])
print(metrics.cycle_count)

for tool_name, data in metrics.tool_metrics.items():
    print(f"{tool_name}: {data['call_count']} calls")
    success_rate = data["success_count"] / data["call_count"]
    print(f"  Success: {success_rate:.1%}")
```

### Custom Observability Hook

```python
from strands.hooks import HookProvider, HookRegistry
from strands.hooks.events import (
    BeforeToolCallEvent,
    AfterToolCallEvent,
    AfterInvocationEvent,
)
import logging
import time


class ObservabilityHook(HookProvider):
    def __init__(self, agent_name: str):
        self.agent_name = agent_name
        self.logger = logging.getLogger(f"agent.{agent_name}")
        self.timings = {}

    def register_hooks(self, registry: HookRegistry, **kwargs):
        registry.add_callback(BeforeToolCallEvent, self.before_tool)
        registry.add_callback(AfterToolCallEvent, self.after_tool)
        registry.add_callback(AfterInvocationEvent, self.log_completion)

    def before_tool(self, event: BeforeToolCallEvent):
        self.timings[event.tool_use["toolUseId"]] = time.time()
        self.logger.info("Tool invoked", extra={
            "tool": event.tool_use["name"],
            "input": event.tool_use["input"],
        })

    def after_tool(self, event: AfterToolCallEvent):
        duration = time.time() - self.timings[event.tool_use["toolUseId"]]
        self.logger.info("Tool completed", extra={
            "tool": event.tool_use["name"],
            "duration_ms": duration * 1000,
        })
        if duration > 5.0:
            self.logger.warning(f"Slow tool: {event.tool_use['name']} ({duration:.2f}s)")

    def log_completion(self, event: AfterInvocationEvent):
        metrics = event.result.metrics.get_summary()
        self.logger.info("Agent completed", extra={
            "cycles": metrics["total_cycles"],
            "tokens": metrics["accumulated_usage"]["totalTokens"],
        })
```

### CloudWatch Log Paths

- Runtime logs: `/aws/bedrock-agentcore/runtimes/<agent_id>-<endpoint>/[runtime-logs]`
- OTEL logs: `/aws/bedrock-agentcore/runtimes/<agent_id>-<endpoint>/otel-rt-logs`
- Transaction Search: CloudWatch > Transaction Search > `/aws/spans/default`

### Third-Party Platforms

**Arize Phoenix**:
```python
import phoenix as px
from phoenix.trace.opentelemetry import OpenInferenceTracer

session = px.launch_app()
tracer = OpenInferenceTracer()
telemetry = StrandsTelemetry(tracer_provider=tracer.tracer_provider)
```

**Langfuse**:
```python
from langfuse.opentelemetry import LangfuseSpanExporter
from opentelemetry.sdk.trace import TracerProvider, SimpleSpanProcessor

exporter = LangfuseSpanExporter(
    public_key="pk-xxx", secret_key="sk-xxx",
    host="https://cloud.langfuse.com",
)
provider = TracerProvider()
provider.add_span_processor(SimpleSpanProcessor(exporter))
telemetry = StrandsTelemetry(tracer_provider=provider)
```

---

## AgentCore Evaluations

LLM-as-a-Judge quality assessment for agents.

### Built-in Evaluators

**Quality**: Helpfulness, Correctness, Faithfulness, ResponseRelevance, Conciseness, Coherence, InstructionFollowing

**Safety**: Refusal, Harmfulness, Stereotyping

**Tool Performance**: GoalSuccessRate, ToolSelectionAccuracy, ToolParameterAccuracy, ContextRelevance

### Setup

```python
from bedrock_agentcore_starter_toolkit import Evaluation

eval_client = Evaluation()
config = eval_client.create_online_config(
    config_name="quality_monitor",
    agent_id="agent_myagent-ABC123",
    sampling_rate=10.0,  # Evaluate 10% of interactions
    evaluator_list=[
        "Builtin.Helpfulness",
        "Builtin.GoalSuccessRate",
        "Builtin.ToolSelectionAccuracy",
    ],
    enable_on_create=True,
)
```

### Custom Evaluators

```python
custom = eval_client.create_evaluator(
    evaluator_name="CustomerSatisfaction",
    model_id="anthropic.claude-sonnet-4-5-20250929-v1:0",
    evaluation_prompt="""Assess customer satisfaction:
1. Query resolution (0-10)
2. Response clarity (0-10)
3. Tone (0-10)
Return average score.""",
    level="Agent",
)
```

### Quality Alerts

```python
import boto3

cw = boto3.client("cloudwatch")
cw.put_metric_alarm(
    AlarmName="AgentQualityDrop",
    MetricName="Helpfulness",
    Namespace="AWS/BedrockAgentCore/Evaluations",
    Statistic="Average",
    Period=3600,
    EvaluationPeriods=2,
    Threshold=7.0,
    ComparisonOperator="LessThanThreshold",
)
```

---

## Cost Tracking

### Cost Hook

```python
from strands.hooks import HookProvider
from strands.hooks.events import AfterInvocationEvent
import boto3

# Approximate pricing per 1K tokens (update as needed)
PRICING = {"input": 0.003 / 1000, "output": 0.015 / 1000}


class CostTracker(HookProvider):
    def __init__(self, budget: float = 100.0):
        self.budget = budget
        self.total = 0.0
        self.cw = boto3.client("cloudwatch")

    def register_hooks(self, registry, **kwargs):
        registry.add_callback(AfterInvocationEvent, self.track)

    def track(self, event):
        usage = event.result.metrics.accumulated_usage
        cost = (
            usage["inputTokens"] * PRICING["input"]
            + usage["outputTokens"] * PRICING["output"]
        )
        self.total += cost

        self.cw.put_metric_data(
            Namespace="AgentCosts",
            MetricData=[{"MetricName": "InvocationCost", "Value": cost, "Unit": "None"}],
        )

        if self.total > self.budget * 0.9:
            logging.warning(f"Budget: ${self.total:.2f} / ${self.budget:.2f}")
```

### Cost Optimization Strategies

1. **Use Haiku for simple tasks** — `anthropic.claude-haiku-4-5-20251001-v1:0` is 10x cheaper
2. **Implement conversation managers** — Prevent unbounded context growth
3. **Cache tool results** — `@lru_cache` for idempotent tools
4. **Limit tool rounds** — Set `max_tool_rounds` on Agent
5. **Monitor per-agent costs** — CloudWatch custom metrics
6. **Use semantic tool search** — Fewer tools = less input tokens

---

## Monitoring & Alerts

### Essential CloudWatch Alarms

```python
import boto3

cw = boto3.client("cloudwatch")

# High error rate
cw.put_metric_alarm(
    AlarmName="AgentHighErrorRate",
    MetricName="ErrorCount",
    Namespace="AgentMetrics",
    Statistic="Sum",
    Period=300,
    EvaluationPeriods=2,
    Threshold=10,
    ComparisonOperator="GreaterThanThreshold",
)

# Slow response time
cw.put_metric_alarm(
    AlarmName="AgentSlowResponse",
    MetricName="ResponseLatency",
    Namespace="AgentMetrics",
    Statistic="p99",
    Period=300,
    EvaluationPeriods=2,
    Threshold=30000,  # 30 seconds
    ComparisonOperator="GreaterThanThreshold",
)
```

### Production Checklist

- [ ] OpenTelemetry tracing enabled
- [ ] Cost tracking implemented
- [ ] CloudWatch dashboards created
- [ ] Error alerting configured
- [ ] Latency tracked (p50, p90, p99)
- [ ] Token usage monitored
- [ ] Tool success rates tracked
- [ ] Sensitive data redacted from traces
- [ ] Access logs enabled
- [ ] Retention policies configured

---

## Security Hardening

### Data Residency

```python
model = BedrockModel(
    model_id="anthropic.claude-sonnet-4-5-20250929-v1:0",
    region_name="eu-west-1",  # GDPR-compliant
)
session_manager = DynamoDBSessionManager(
    table_name="agent-sessions",
    region_name="eu-west-1",
)
```

### Principle of Least Privilege

- Agent IAM role: Only permissions the agent actually needs
- Tool execution: Use read-only credentials where possible
- DynamoDB: Use `use_optimistic_locking=True` for concurrent access

### Redact Sensitive Data

```python
class RedactionHook(HookProvider):
    SENSITIVE_PATTERNS = [r"\b\d{16}\b", r"\b\d{3}-\d{2}-\d{4}\b"]  # CC, SSN

    def register_hooks(self, registry, **kwargs):
        registry.add_callback(AfterToolCallEvent, self.redact)

    def redact(self, event):
        import re
        for content in event.result.get("content", []):
            text = content.get("text", "")
            for pattern in self.SENSITIVE_PATTERNS:
                text = re.sub(pattern, "[REDACTED]", text)
            content["text"] = text
```

---

## Known Limitations

| Limitation | Impact | Mitigation |
|-----------|--------|------------|
| > 50-100 tools | Wrong tool selection | Semantic search |
| 200K context (Claude 4.5) | Truncated history | Conversation managers |
| Lambda no streaming | No real-time responses | AgentCore Runtime |
| Multi-agent 5-10x cost | Unexpected bills | Cost tracking, budget alerts |
| Bedrock throttling (50-100 TPS) | Rate limit errors | Retry with backoff, quota increase |
| Runtime max 8 hours | Task must complete | Break into resumable chunks |
| OpenAPI specs > 2MB | Gateway can't load | Split into multiple registrations |
| Memory > 100K entries | Degraded performance | Use for high-value data only |
| Swarm unpredictability | Unexpected handoffs | Set max_handoffs, execution_timeout |
| Cold starts (Lambda) | 30-60s delay | Provisioned concurrency, AgentCore |
| Agent latency 1-10s | Not real-time | Not for high-frequency use cases |
