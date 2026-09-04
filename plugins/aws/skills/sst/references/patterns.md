# SST Architecture Patterns

## Table of Contents
- [REST API + Database](#rest-api--database)
- [Full-Stack Next.js](#full-stack-nextjs)
- [Event-Driven Microservices](#event-driven-microservices)
- [SaaS Multi-Tenant](#saas-multi-tenant)
- [Real-Time Applications](#real-time-applications)
- [AI/ML Streaming](#aiml-streaming)
- [Background Processing](#background-processing)
- [Database Migration Pattern](#database-migration-pattern)

---

## REST API + Database

The most common SST pattern. API Gateway + Lambda + DynamoDB.

```typescript
// infra/storage.ts
export const table = new sst.aws.Dynamo("Items", {
  fields: {
    pk: "string",
    sk: "string",
    gsi1pk: "string",
    gsi1sk: "string",
  },
  primaryIndex: { hashKey: "pk", rangeKey: "sk" },
  globalIndexes: {
    gsi1: { hashKey: "gsi1pk", rangeKey: "gsi1sk" },
  },
});

// infra/api.ts
import { table } from "./storage";

export const api = new sst.aws.ApiGatewayV2("Api");

api.route("GET /items", {
  handler: "packages/functions/src/api/items.list",
  link: [table],
});
api.route("GET /items/{id}", {
  handler: "packages/functions/src/api/items.get",
  link: [table],
});
api.route("POST /items", {
  handler: "packages/functions/src/api/items.create",
  link: [table],
});
api.route("PUT /items/{id}", {
  handler: "packages/functions/src/api/items.update",
  link: [table],
});
api.route("DELETE /items/{id}", {
  handler: "packages/functions/src/api/items.delete",
  link: [table],
});
```

**SST-specific handler pattern** — the only SST-specific part is `Resource.Items.name`:
```typescript
import { Resource } from "sst";
// Use Resource.Items.name as TableName in DynamoDB calls
// Use Resource.Items.arn for IAM resource ARNs
```

**ORM note**: For DynamoDB, ElectroDB is the SST community favorite (built for single-table design). For Postgres, Drizzle ORM is recommended (lightweight bundle, good migration tool). Prisma works but has heavier Lambda bundles — requires `nodejs: { install: ["prisma", "@prisma/client"] }`.

---

## Full-Stack Next.js

Next.js frontend + API routes + SST backend resources.

```typescript
// infra/storage.ts
export const bucket = new sst.aws.Bucket("Uploads");
export const table = new sst.aws.Dynamo("Data", {
  fields: { pk: "string", sk: "string" },
  primaryIndex: { hashKey: "pk", rangeKey: "sk" },
});

// infra/api.ts
import { bucket, table } from "./storage";

export const api = new sst.aws.ApiGatewayV2("Api");
api.route("GET /api/data", {
  handler: "packages/functions/src/data.list",
  link: [table],
});
api.route("POST /api/upload", {
  handler: "packages/functions/src/upload.handler",
  link: [bucket],
});

// infra/web.ts
import { api } from "./api";
import { bucket, table } from "./storage";

new sst.aws.Nextjs("Web", {
  path: "packages/web",
  link: [bucket, table],            // server components can access these
  environment: {
    NEXT_PUBLIC_API_URL: api.url,   // client-side needs NEXT_PUBLIC_ prefix
  },
});
```

**Key pattern:** Use SST's API for Lambda-backed endpoints, and Next.js API routes for server-component-only logic. Heavy compute or async work should go to Lambda functions via the API, not Next.js API routes (which run on Lambda@Edge with tighter limits).

---

## Event-Driven Microservices

Decouple services using EventBridge + SQS.

```typescript
// infra/events.ts
export const bus = new sst.aws.Bus("EventBus");

// Order service publishes events
export const orderApi = new sst.aws.ApiGatewayV2("OrderApi");
orderApi.route("POST /orders", {
  handler: "packages/functions/src/orders/create.handler",
  link: [bus, orderTable],
});

// Payment service subscribes
bus.subscribe("packages/functions/src/payments/process.handler", {
  pattern: {
    source: ["orders"],
    detailType: ["OrderCreated"],
  },
});

// Notification service subscribes
bus.subscribe("packages/functions/src/notifications/send.handler", {
  pattern: {
    source: ["orders"],
    detailType: ["OrderCreated", "OrderShipped"],
  },
});

// Inventory service with SQS for reliable processing
const inventoryQueue = new sst.aws.Queue("InventoryQueue", {
  dlq: new sst.aws.Queue("InventoryDLQ").arn,
  retry: 3,
});

bus.subscribe({
  handler: "packages/functions/src/inventory/update.handler",
  link: [inventoryTable],
}, {
  pattern: {
    source: ["orders"],
    detailType: ["OrderCreated"],
  },
});
```

**Publishing events** — the SST-specific part is `Resource.EventBus.name`:
```typescript
import { Resource } from "sst";
// Use Resource.EventBus.name as EventBusName in PutEventsCommand
// Standard AWS SDK EventBridge client for publishing
```

---

## SaaS Multi-Tenant

Per-tenant isolation using DynamoDB partition keys or per-tenant stages.

**Approach 1: Shared infrastructure, tenant-scoped data (recommended for most)**
```typescript
const table = new sst.aws.Dynamo("Data", {
  fields: {
    pk: "string",      // TENANT#<tenantId>
    sk: "string",      // ENTITY#<entityId>
  },
  primaryIndex: { hashKey: "pk", rangeKey: "sk" },
});
```

**Approach 2: Per-tenant stages (for compliance/isolation requirements)**
```bash
sst deploy --stage tenant-acme
sst deploy --stage tenant-globex
```

Each tenant gets fully isolated infrastructure. Expensive but sometimes required for enterprise/regulated industries.

---

## Real-Time Applications

### Option 1: IoT Core via Realtime (simpler)
```typescript
const realtime = new sst.aws.Realtime("Chat", {
  authorizer: "packages/functions/src/auth/ws.handler",
});

// Subscribe to messages server-side
realtime.subscribe("packages/functions/src/chat/message.handler", {
  filter: `$app.stage + '/chat/+'`,
});
```

### Option 2: API Gateway WebSocket
```typescript
const wsApi = new sst.aws.ApiGatewayV2("WsApi", {
  routes: {
    $connect: "packages/functions/src/ws/connect.handler",
    $disconnect: "packages/functions/src/ws/disconnect.handler",
    sendMessage: "packages/functions/src/ws/message.handler",
  },
});
```

**When to use which:**
- IoT Core (Realtime): simpler pub/sub, built-in topic routing, scales to millions
- API Gateway WebSocket: more control over connection lifecycle, custom protocols

---

## AI/ML Streaming

Stream AI model responses back to clients using Lambda streaming.

```typescript
const api = new sst.aws.ApiGatewayV2("Api");

api.route("POST /chat", {
  handler: "packages/functions/src/ai/chat.handler",
  streaming: true,
  timeout: "60 seconds",
  memory: "1024 MB",
});
```

**Handler pattern**: Use `awslambda.streamifyResponse` + `HttpResponseStream.from(responseStream, { statusCode, headers })`. Write chunks with `stream.write()`, end with `stream.end()`. Standard AWS Lambda streaming API — the SST-specific part is only `streaming: true` in the component config.

---

## Background Processing

### Pattern: Queue + Worker
```typescript
const processQueue = new sst.aws.Queue("ProcessQueue");
const dlq = new sst.aws.Queue("ProcessDLQ");

processQueue.subscribe("packages/functions/src/workers/process.handler", {
  batch: { size: 10, window: "30 seconds" },
});

// API endpoint that enqueues work
api.route("POST /jobs", {
  handler: "packages/functions/src/api/jobs.create",
  link: [processQueue],
});
```

### Pattern: Long-running Task
```typescript
const importTask = new sst.aws.Task("DataImport", {
  handler: "packages/functions/src/tasks/import.handler",
  link: [bucket, table],
  memory: "4 GB",
  timeout: "2 hours",
});

// Trigger from API
api.route("POST /import", {
  handler: "packages/functions/src/api/import.trigger",
  link: [importTask],
});
```

---

## Database Migration Pattern

Run Drizzle/Prisma migrations automatically on deploy.

```typescript
// infra/database.ts
const vpc = new sst.aws.Vpc("Vpc", { nat: isProd ? "managed" : "ec2" });
const db = new sst.aws.Postgres("Database", { vpc });

// Migration function runs on every deploy
const migrator = new sst.aws.Function("Migrator", {
  handler: "packages/functions/src/migrations/run.handler",
  link: [db],
  vpc,
  timeout: "5 minutes",
  copyFiles: [{ from: "packages/core/drizzle", to: "drizzle" }],
});

// Invoke migration after deploy
new aws.lambda.Invocation("RunMigrations", {
  functionName: migrator.name,
  input: JSON.stringify({ timestamp: Date.now() }),
});
```

**Alternative: Use `sst shell` for manual migrations**
```bash
sst shell --stage production -- npx drizzle-kit migrate
```

---

## Common Tech Stack Combos

| Stack | Components | Best For |
|-------|-----------|----------|
| **Hono + DynamoDB** | ApiGatewayV2 + Function + Dynamo | Fast APIs, edge-ready |
| **tRPC + Postgres** | ApiGatewayV2 + Function + Postgres | Type-safe full-stack |
| **Next.js + DynamoDB** | Nextjs + Dynamo | Full-stack with SSR |
| **Astro + S3** | Astro + Bucket | Content sites with uploads |
| **Express + ECS** | Cluster + Service | Existing Express apps |
| **FastAPI + Lambda** | Function (Python) | Python ML/data APIs |
