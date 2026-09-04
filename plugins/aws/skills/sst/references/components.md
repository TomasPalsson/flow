# SST v3 Components Reference

Focused on decisions, trade-offs, and gotchas — not API documentation. For constructor props, check [sst.dev/docs/components](https://sst.dev/docs/components/).

## Component Routing

| Working with... | Read section |
|-----------------|-------------|
| Lambda functions | [Compute > Function](#function) |
| Containers/ECS | [Compute > Service/Task](#service) |
| REST/GraphQL APIs | [API](#api) |
| Frontend frameworks | [Frontend](#frontend) |
| S3, DynamoDB, Postgres | [Storage & Database](#storage--database) |
| SQS, SNS, EventBridge | [Messaging](#messaging) |
| Auth/Cognito | [Auth](#auth) |
| VPC/networking | [Networking](#networking) |

---

## Compute

### Function
`sst.aws.Function` — wraps AWS Lambda. The workhorse of SST.

**Key decisions:**
| Decision | Recommendation | Why |
|----------|---------------|-----|
| Architecture | Always `arm64` | 20% cheaper, faster cold starts. Only use x86 for native modules without ARM builds |
| Memory | Start at 512 MB | More memory = more CPU = faster. Profile with AWS Lambda Power Tuning |
| Timeout | Match actual max time | Don't over-provision. Default 20s is often too long or too short |
| VPC | Avoid unless required | Adds 2-5s cold start + $32/mo NAT. Only for RDS/ElastiCache/VPN |
| Streaming | Use for AI/large responses | Set `streaming: true`. Incompatible with `url: true` |
| Log retention | Always set | Default is forever = unbounded CloudWatch costs. Use `logRetention: "1 week"` |
| Function URL vs API Gateway | URL for single-function APIs | No API Gateway overhead. Use Router component for custom domains |

**Bundling (esbuild):**
- Native modules (sharp, prisma, bcrypt): use `nodejs: { install: ["sharp"] }` — installs via npm instead of bundling
- Exclude AWS SDK v3: `nodejs: { esbuild: { external: ["@aws-sdk/*"] } }` — already in Lambda runtime
- Python functions: use `python: { container: true }` for native extensions

**Gotcha**: In `sst dev`, layers are NOT applied — functions run locally. You need local versions of whatever the layer provides.

### Cron
`sst.aws.Cron` — EventBridge-scheduled Lambda.

Schedule formats: `"rate(1 day)"`, `"rate(5 minutes)"`, `"cron(0 12 * * ? *)"` (UTC).

**Gotcha**: Cron triggers in `sst dev` hit stub functions. If your local build is slow, the 8-second stub timeout causes errors. Create cron schedules only for staging/production:
```typescript
if (!$dev) {
  new sst.aws.Cron("Daily", { schedule: "rate(1 day)", job: "src/daily.handler" });
}
```

### Task
`sst.aws.Task` — one-off ECS Fargate tasks. Use instead of Function when execution >15 minutes, >10GB memory, or predictable CPU needed.

### Service
`sst.aws.Service` — always-running ECS Fargate containers.

**When to use Service vs Function:**
| Factor | Function (Lambda) | Service (Fargate) |
|--------|-------------------|-------------------|
| Max execution | 15 minutes | Unlimited |
| Cold start | 100ms-2s | 0ms (always warm) |
| Cost at low traffic | Near-zero | Min ~$12/month |
| Cost at high traffic | Can be expensive | More predictable |
| WebSockets | Not supported | Supported |
| GPU | Not available | Available |
| Cost with Spot | N/A | ~50% savings: `capacity: "spot"` |

**Required**: Always set `health: { path: "/health" }` — without it, services restart-loop.

### Cluster
`sst.aws.Cluster` — ECS cluster that Service and Task components require.
```typescript
const vpc = new sst.aws.Vpc("MyVpc");
const cluster = new sst.aws.Cluster("MyCluster", { vpc });
```

---

## Frontend

All SSR frameworks deploy via S3 + CloudFront + Lambda. SST uses OpenNext for Next.js.

**Framework selection — what matters:**
| Component | Framework | SST-Specific Gotcha |
|-----------|-----------|-------------------|
| `Nextjs` | Next.js | Uses OpenNext. Pin `openNextVersion` in CI. ISR uses SQS + DynamoDB internally |
| `Remix` | Remix | Classic config may cause empty file downloads — use Vite config |
| `Astro` | Astro | `astro-sst` adapter compatibility issues with Astro v5 |
| `SvelteKit` | SvelteKit | Creates many cache behaviors — may hit CloudFront's 25 limit |
| `StaticSite` | Any SPA | No SSR Lambda. S3 + CloudFront only |

**Key pattern for all frontends:**
- `link: [...]` works server-side only. For client-side values, use `environment: { NEXT_PUBLIC_X: value }`
- `warm: N` keeps N Lambda instances warm in production (reduces cold starts)
- `domain: { name: "app.example.com", redirects: ["www.example.com"] }` for custom domains

---

## API

### ApiGatewayV2
`sst.aws.ApiGatewayV2` — HTTP API. The default for REST APIs.

**Authorization decision:**
| Type | Use Case |
|------|----------|
| `auth: { iam: true }` | Service-to-service, Cognito Identity Pool |
| `auth: { jwt: { issuer, audiences } }` | Cognito User Pool, Auth0, any OIDC |
| `auth: { lambda: { function } }` | Custom auth logic (API keys, etc.) |
| No auth | Public endpoints |

**Route syntax**: `"GET /users/{id}"`, `"POST /users"`, `"$default"` (catch-all). Handler path is relative to project root.

### Router
`sst.aws.Router` — CloudFront-based routing. Combine multiple backends under one domain:
```typescript
const router = new sst.aws.Router("Router", {
  domain: "example.com",
  routes: { "/api/*": api.url, "/*": site.url },
});
```

### ApiGatewayWebSocket
`sst.aws.ApiGatewayWebSocket` — for WebSocket APIs with connection management. Routes: `$connect`, `$disconnect`, `$default`, plus custom routes.

---

## Storage & Database

### Bucket (`sst.aws.Bucket`)
S3 bucket. Access modes: private (default), `public`, or `cloudfront`.

**Key patterns**: Subscribe to events with `bucket.subscribe("handler", { events: ["s3:ObjectCreated:*"], filterPrefix: "uploads/" })`. Also supports queue/topic subscribers.

**Gotcha**: Lambda that writes to a bucket must NOT be triggered by the same bucket/prefix — creates infinite loops.

### Dynamo (`sst.aws.Dynamo`)
DynamoDB table. Always use single-table design with `pk`/`sk` composite keys.

```typescript
const table = new sst.aws.Dynamo("Data", {
  fields: { pk: "string", sk: "string", gsi1pk: "string", gsi1sk: "string" },
  primaryIndex: { hashKey: "pk", rangeKey: "sk" },
  globalIndexes: { gsi1: { hashKey: "gsi1pk", rangeKey: "gsi1sk" } },
  stream: "new-and-old-images",  // enable for event subscribers
});
```

**Stream subscribers**: `table.subscribe("handler", { filters: [{ eventName: ["INSERT"] }] })` — up to 5 filters.

**Linked access**: `Resource.Data.name` (table name), `Resource.Data.arn`.

### Postgres (`sst.aws.Postgres`)
RDS PostgreSQL (single instance, not Aurora Serverless).

```typescript
const db = new sst.aws.Postgres("Database", { vpc });
```

**Key decisions:**
| Decision | Recommendation |
|----------|---------------|
| Instance type | `t4g.micro` default (~$14/mo). Size up for production |
| RDS Proxy | Enable with `proxy: true` for Lambda connection pooling (+$22/mo) |
| Local dev | Use `dev: { host: "localhost", port: 5432, ... }` to skip deploying RDS |
| Multi-AZ | Doubles cost. Only for production HA |
| Migrations | Use `sst shell -- npx drizzle-kit migrate` or Lambda-based migration |

**Linked access**: `Resource.Database.host`, `.port`, `.username`, `.password`, `.database`.

### Vector (`sst.aws.Vector`)
Vector DB for AI embeddings (backed by Aurora Postgres + pgvector). `new sst.aws.Vector("Embeddings", { dimension: 1536 })`.

---

## Messaging

**When to use which:**
| Pattern | Component | Use Case |
|---------|-----------|----------|
| Point-to-point processing | `Queue` (SQS) | Worker processing, rate limiting, retry with DLQ |
| Fan-out to many | `SnsTopic` (SNS) | Same event to multiple subscribers |
| Complex event routing | `Bus` (EventBridge) | Pattern matching on source, detail-type, nested fields |
| Real-time pub/sub | `Realtime` (IoT Core) | Client WebSocket connections, millions of connections |

### Queue (`sst.aws.Queue`)
**Critical config**: Always set up DLQ for production:
```typescript
const dlq = new sst.aws.Queue("DLQ");
const queue = new sst.aws.Queue("Jobs", { dlq: { queue: dlq.arn, retry: 3 } });
queue.subscribe("handler", { batch: { size: 10, window: "30 seconds" } });
```

FIFO queues: `new sst.aws.Queue("OrderQueue", { fifo: true })`.

### SnsTopic (`sst.aws.SnsTopic`)
Fan-out: `topic.subscribe("handler")` + `topic.subscribeQueue(queue.arn)`. Supports message filtering.

### Bus (`sst.aws.Bus`)
EventBridge bus with pattern matching:
```typescript
bus.subscribe("handler", {
  pattern: { source: ["orders"], detailType: ["OrderCreated"], detail: { amount: [{ numeric: [">", 100] }] } },
});
```

### Realtime (`sst.aws.Realtime`)
IoT Core-based real-time messaging. Scales to millions of connections without managing infrastructure. Requires custom authorizer Lambda. **Critical**: Prefix topics by app/stage — IoT Core endpoint is shared across all apps in the same AWS account/region.

---

## Auth

### Cognito (`sst.aws.Cognito`)
User Pool + optional Identity Pool. Configure MFA, custom triggers, social sign-in (Google, GitHub, Apple via OIDC).

### Auth (`sst.aws.Auth`)
OpenAuth-based auth (beta). Lambda-backed issuer with DynamoDB for persistence.

### Email (`sst.aws.Email`)
SES identity. `sender` must be verified (email confirmation or DNS for domains).

---

## Networking

### Vpc (`sst.aws.Vpc`)
**The NAT decision is the most important cost choice:**

| NAT Option | Cost | When |
|-----------|------|------|
| `nat: "ec2"` | ~$4/mo | Dev/staging — uses t4g.nano with fck-nat AMI |
| `nat: "managed"` | ~$32/mo per AZ | Production — highly available, auto-scales |
| No NAT | Free | Lambda functions that don't need internet from VPC |

```typescript
const vpc = new sst.aws.Vpc("MyVpc", {
  nat: isProd ? "managed" : "ec2",
  bastion: true,  // enables sst tunnel for local dev DB access
});
```

**You need VPC for**: RDS/Aurora, ElastiCache/Redis, ECS Services, VPN/Direct Connect, compliance requirements.

**You do NOT need VPC for**: Lambda + DynamoDB, Lambda + S3, Lambda + SQS/SNS/EventBridge.

---

## Other

### Linkable (`sst.Linkable`)
Make arbitrary values or external resources linkable:
```typescript
new sst.Linkable("Config", { properties: { apiUrl: "https://external.com" } });
// Wrap Pulumi resources: Linkable.wrap(aws.dynamodb.Table, ...)
// Export as env vars for non-SST compute: Linkable.env([bucket, secret])
```

### DevCommand (`sst.x.DevCommand`)
Run dev commands in `sst dev` multiplexer. Only runs during dev, ignored during deploy.

---

## Common Component Failure Modes

Real issues from GitHub — check here when something breaks.

| Component | Failure | Cause | Fix |
|-----------|---------|-------|-----|
| **Nextjs** | Build hangs at "Creating nextjs" | OpenNext version mismatch or OOM | Pin `openNextVersion`, increase CI memory |
| **Nextjs** | "Cannot find module 'next'" | Multiple lock files in monorepo | Ensure single lock file at project root |
| **Nextjs** | Empty streaming responses | Lambda streaming edge case | `OPEN_NEXT_FORCE_NON_EMPTY_RESPONSE=true` |
| **Postgres** | Cold start blocks deploy | RDS cold start 25+ seconds | Use `dev` prop for local Postgres in dev |
| **Postgres** | Connection exhaustion | Lambda concurrency > DB connections | Enable `proxy: true` for RDS Proxy |
| **Service** | Container restart loop | Missing/wrong `health.path` | Lightweight `/health` endpoint returning 200 |
| **Service** | OOM kills | Container memory too low | Increase `memory`, check for leaks |
| **Function** | Prisma breaks after bundling | esbuild can't bundle `.node` binaries | `nodejs: { install: ["prisma", "@prisma/client"] }` |
| **Function** | "esbuild for another platform" | macOS build for Linux Lambda | Ensure correct platform binary |
| **Vpc** | Deploy takes 5+ minutes | NAT Gateway creation is slow | Expected — first deploy only |
| **Bucket** | Infinite notification loop | Lambda writes to same triggering bucket | Use different prefix or separate bucket |
| **Dynamo** | Stream subscriber duplicates | v2 and v3 both subscribing | Remove v2 subscriber before adding v3 |
| **All frontends** | CloudFront 25 behavior limit | Too many top-level routes/files | Reorganize into subdirectories |
| **All** | State lock error | Crashed mid-deploy | `sst unlock`, then retry. If stuck: `sst refresh` |
| **All** | Panic / nil pointer | Corrupted state or SST bug | `sst upgrade`, then `sst refresh` |
