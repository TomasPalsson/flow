---
name: aws-explore
description: "Token-efficient AWS resource exploration during debugging. Use when: (1) debugging live AWS resources — S3 access issues, DynamoDB query patterns, Bedrock/AgentCore failures, (2) the user asks what's in their AWS account, (3) you need to understand the shape/config of AWS resources before making changes. Covers S3, DynamoDB, and Bedrock/AgentCore. Do NOT use for: creating/modifying AWS resources (use sst skill), deploying agents (use strands-agentcore skill), or general AWS documentation questions. Trigger keywords: s3, bucket, dynamodb, table, bedrock, agentcore, aws, 403, access denied, describe, explore, scan."
---

# AWS Explore Workflow

You are exploring live AWS resources to support debugging or development. Every command you run feeds output into your context window — **token efficiency is critical**.

## NEVER Do

- **NEVER run `aws dynamodb scan` without `--limit`** — full table scans on multi-GB tables will flood context and run for minutes
- **NEVER call `aws s3api list-objects-v2` without `--max-items` and `--prefix`** — buckets can have millions of objects
- **NEVER use `--output table`** — border characters tokenize individually, worst format for LLMs
- **NEVER call detail on more than 3 resources in one turn** — each detail call should answer a specific hypothesis
- **NEVER run raw `describe-*` without `--query`** — up to 98% token waste
- **NEVER include full ARNs in reasoning** — use the human-readable name/ID
- **NEVER forget `--no-cli-pager`** — it will hang waiting for interactive input (the `aws-explore` script handles this, but remember for any raw `aws` calls)

## Pre-requisites

Requires `AWS_PROFILE` and `AWS_DEFAULT_REGION` set in environment. If credentials are expired, tell the user to run `aws sso login`. The script defaults to `eu-west-1` if no region is set.

The `aws-explore` script is at `~/.local/bin/aws-explore`. It validates credentials before running any command.

## Progressive Disclosure Protocol

**ALWAYS follow this order. Do NOT skip to detail without running overview first.**

### Step 1: Overview

Run `aws-explore <service> overview` first. This returns a compact summary (~15-30 tokens per resource) of all resources in the service.

Read the overview to identify which specific resources are relevant to the bug or task.

### Step 2: Detail (targeted)

Run detail commands ONLY for resources identified in Step 1:
- `aws-explore s3 bucket <name>` — ~600-900 tokens
- `aws-explore dynamodb table <name>` — ~300-500 tokens (schema + TTL + 3 sample items)
- `aws-explore bedrock agents` or `bedrock agentcore` — ~200-400 tokens

### Step 3: Targeted queries (if needed)

Only after detail confirms the data model:
- `aws-explore dynamodb query <table> <pk-value>` — query with auto-detected key schema
- `aws-explore s3 objects <bucket> <prefix>` — bounded object listing
- `aws-explore s3 debug-403 <bucket> <key>` — full 403 diagnosis

## Reference Files

Load these ONLY when investigating the specific service. Do NOT load all references upfront.

| File | When to Read | Do NOT Load When |
|------|-------------|-----------------|
| `references/s3-patterns.md` | Debugging S3 access, bucket policies, object metadata, CORS, replication | DynamoDB or Bedrock-only issues |
| `references/dynamodb-patterns.md` | Debugging table access patterns, GSI queries, capacity, TTL | S3 or Bedrock-only issues |
| `references/bedrock-patterns.md` | Debugging AgentCore runtimes, model availability, gateway config | S3 or DynamoDB-only issues |

## Command Reference

### S3

```bash
aws-explore s3 overview                     # All buckets: name, region, versioning, encryption, public access
aws-explore s3 bucket <name>                # Deep dive: config, policy summary, tags, prefixes, CORS, lifecycle
aws-explore s3 objects <bucket> [prefix]    # List objects (max 20) with size, modified date, storage class
aws-explore s3 debug-403 <bucket> <key>     # Full 403 diagnosis: identity, policy, public block, ownership, object metadata
```

### DynamoDB

```bash
aws-explore dynamodb overview               # All tables: name, status, billing, key schema, GSI/LSI names
aws-explore dynamodb table <name>           # Schema + GSI detail + TTL config + 3 sample items
aws-explore dynamodb query <table> <pk>     # Query by partition key (auto-detects key name and type, limit 5)
aws-explore dynamodb schema [t1 t2 ...]     # Compact schema dump: pk, sk, attrs, GSIs (for all or specific tables)
```

### Bedrock / AgentCore

```bash
aws-explore bedrock models [provider]       # Foundation models (default: Anthropic) with status, streaming, inference types
aws-explore bedrock agents                  # Bedrock agents + knowledge bases + guardrails
aws-explore bedrock agentcore               # AgentCore runtimes, gateways, memories, browsers, code interpreters
aws-explore bedrock logs <prefix>           # Find AgentCore log groups + recent errors
aws-explore bedrock tail <runtime-name>     # Tail live runtime logs (ctrl-c to stop)
aws-explore bedrock traces <prefix> [since] # Query OTEL spans — duration, tokens, model, status (default: last 1h)
aws-explore bedrock trace <trace-id>        # Get all spans for a trace — full hierarchy with tool calls
aws-explore bedrock debug                   # Find all FAILED resources across Bedrock services
```

## Decision Tree: Which Service to Explore

```
What is the symptom?
|
+-- Access denied / 403 on S3
|   -> aws-explore s3 debug-403 <bucket> <key>
|
+-- Data missing or wrong from DynamoDB
|   -> aws-explore dynamodb table <name>
|   -> Check TTL if items are disappearing
|
+-- Agent/model invocation failing
|   -> aws-explore bedrock debug (find FAILED resources first)
|   -> aws-explore bedrock models (check model availability in region)
|
+-- Agent invocation slow or erroring
|   -> aws-explore bedrock traces <runtime-prefix> (check OTEL spans)
|   -> aws-explore bedrock trace <trace-id> (drill into specific invocation)
|
+-- Need to see runtime logs
|   -> aws-explore bedrock logs <prefix> (find log groups + recent errors)
|   -> aws-explore bedrock tail <runtime-name> (live tail)
|
+-- "What's in this AWS account?"
|   -> aws-explore s3 overview
|   -> aws-explore dynamodb overview
|   -> aws-explore bedrock agents
|
+-- Unknown / mixed symptoms
|   -> Check the service mentioned in the error message first
|   -> Use aws-explore <service> overview to orient
```

## Manual AWS CLI Calls

If `aws-explore` doesn't cover your specific need, you can run raw AWS CLI calls. Always follow these rules:

1. `--no-cli-pager` on every call
2. `--query` with JMESPath to select only needed fields
3. `--max-items N` for any listing command (50 is a sane default)
4. `--filters` (server-side) before `--query` (client-side) where supported
5. `--output json` for structured data, `--output text` for IDs/counts

Load the appropriate reference file for JMESPath patterns specific to the service you're querying.
