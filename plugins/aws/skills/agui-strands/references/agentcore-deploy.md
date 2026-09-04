---
name: agentcore-deploy
description: Deploying an AG-UI/Strands agent to Bedrock AgentCore Runtime — the /invocations + /ping + 8080 contract, arm64 + buildx flags, Terraform, IAM, runtimeSessionId, OpenNext streaming, and ARN wiring. Load before any deploy or infra work.
---

# Deploying to Bedrock AgentCore Runtime

## The runtime contract (non-negotiable)
The container MUST:
- bind **`0.0.0.0:8080`** (not `localhost`).
- serve **`POST /invocations`** — receives the `RunAgentInput` JSON body, returns the AG-UI SSE stream.
- serve **`GET /ping`** — returns `{"status":"Healthy"}` (AgentCore polls this).
- be a **single-platform `linux/arm64`** image. AgentCore does not run x86; an amd64 image health-checks
  fine then crashes on first invoke (`ELF ... OS ABI invalid` / `Illegal instruction`).

`EventEncoder(accept=request.headers.get("accept"))` + `get_content_type()` negotiate SSE vs proto;
the route always sends `accept: text/event-stream`.

## Container build (the flags that bite)
```dockerfile
FROM --platform=linux/arm64 python:3.13-slim
WORKDIR /app
COPY requirements.txt . && RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["python", "main.py"]
```
```bash
docker buildx build --platform linux/arm64 \
  --provenance=false --sbom=false \   # CRITICAL: else buildx pushes a manifest LIST + attestation
  --tag "$IMAGE" --push "$AGENT_DIR"  #          layers, and CreateAgentRuntime rejects it as
                                      #          "image does not exist"
```
On x86 CI, create a cross-builder: `docker buildx create --use`. `requirements.txt` is minimal:
`ag-ui-strands strands-agents fastapi uvicorn` (+ your data libs). No boto3 — the role provides creds.

## InvokeAgentRuntime (the caller side)
```ts
const result = await client.send(new InvokeAgentRuntimeCommand({
  agentRuntimeArn: AGENT_RUNTIME_ARN,
  runtimeSessionId: sessionId,         // 33–256 chars. one crypto.randomUUID() (36) is enough.
  contentType: "application/json",
  accept: "text/event-stream",         // omit → whole response BUFFERS (frozen pane, then all at once)
  payload: new TextEncoder().encode(JSON.stringify(agInput)),
}));
const webStream = result.response?.transformToWebStream();   // Node runtime only
```
boto3 equivalent: `bedrock-agentcore` client `invoke_agent_runtime(...)`, read via `iter_lines()`.

## Session model
microVM per `runtimeSessionId`; **900s idle timeout, 8h max lifetime**; no cold start *within* a live
session, but the first invoke after deploy/idle pays container-pull + Python + Strands startup
(10–30s — consider a warm-up ping when the pane opens). AgentCore does NOT map users→sessions; your
backend must send a stable `runtimeSessionId` to keep multi-turn context.

## Terraform (the working shape)
```hcl
resource "aws_bedrockagentcore_agent_runtime" "this" {
  agent_runtime_name = var.agent_name
  role_arn           = aws_iam_role.runtime.arn
  agent_runtime_artifact { container_configuration { container_uri = local.image_uri } }
  network_configuration  { network_mode = "PUBLIC" }
  environment_variables  = { MODEL_ID = var.model_id, /* api keys, MEMORY_ID, ... */ }
  depends_on = [null_resource.image]
}
```
**Content-addressed image tag** so a source change forces a rebuild+roll (never `:latest`):
```hcl
image_tag = substr(sha1(join("", [for f in local.image_files : filemd5("${local.src}/${f}")])), 0, 12)
```
Providers: `aws >= 6.0` (the `bedrockagentcore` resources are new), `null >= 3.2`.

## IAM
Runtime execution role — trust principal `bedrock-agentcore.amazonaws.com`; permissions:
`bedrock:InvokeModel` + `bedrock:InvokeModelWithResponseStream`, ECR pull
(`GetAuthorizationToken`/`BatchGetImage`/`GetDownloadUrlForLayer`), CloudWatch Logs on
`/aws/bedrock-agentcore/*`, X-Ray, `cloudwatch:PutMetricData`,
`bedrock-agentcore:GetWorkloadAccessToken*`. With AgentCore Memory, also the memory data-plane actions
(`CreateEvent`, `RetrieveMemoryRecords`, `ListEvents`, …) scoped to the memory ARN.
Caller (the Next SSR Lambda) needs **`bedrock-agentcore:InvokeAgentRuntime`** — a *different*
namespace from `bedrock:*`. Granting only `bedrock:InvokeModel` yields `AccessDenied` on invoke.

## Next.js side — streaming & wiring
- Route: `export const runtime = "nodejs"; export const dynamic = "force-dynamic"; export const
  maxDuration = 120;` (raise from 60 for multi-tool runs; also bump the Lambda timeout in SST
  `transform.server.timeout`).
- **OpenNext streaming** (SST `sst.aws.Nextjs`): add `open-next.config.ts` with
  `override: { wrapper: "aws-lambda-streaming" }`. Without it the SSE response is fully buffered on
  Lambda — tokens and cards arrive only after the agent finishes.
- ARN wiring: `terraform output -raw agent_runtime_arn` → `bunx sst secret set AgentRuntimeArn "$ARN"`
  → SST injects it as `AGENT_RUNTIME_ARN` env into the Lambda → the route reads `process.env`.
- SST grants the server function `bedrock-agentcore:InvokeAgentRuntime`. Set unused mode envs (e.g.
  `GARRI_AGENT_URL`) to `""` in prod so a leaked localhost URL can't activate local mode.
- Region: build the client from the ARN's region (`ARN.split(":")[3]`) or `AGENT_REGION` — a mismatch
  gives `ResourceNotFoundException`.

## Local dev
- Run the agent: `uvicorn`/`python main.py` on `:8080`; point the route at it via the local-mode env
  (e.g. `GARRI_AGENT_URL=http://localhost:8080`). Full AG-UI path, no AWS.
- Put `AWS_PROFILE`/`AWS_REGION` in **`.envrc`** (direnv), never `.env`/`.env.local` — Next bundles
  `.env*` into the Lambda, where profile creds break the SDK credential chain.

## AgentCore Memory (optional)
A `strands.hooks.HookProvider` (`MemoryHook`) does pre-invoke `retrieve_memories` (inject into system
prompt) and post-invoke `create_event`. Strategies on one memory store: `SEMANTIC`, `SUMMARIZATION`,
`USER_PREFERENCE`, with namespaces like `/app/facts/{actorId}` ({actorId} substituted by AgentCore).
If `MEMORY_ID` is unset the hook self-disables — safe for local dev. This pairs with a per-request
`Agent` (to scope `actor_id`), unlike the singleton AG-UI agent.
