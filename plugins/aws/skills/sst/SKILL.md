---
name: sst
description: "Build and deploy full-stack applications on AWS using SST v3 (Ion). Use whenever the user mentions SST, Serverless Stack, sst.config.ts, sst dev, sst deploy, or builds serverless TypeScript apps on AWS. Also trigger on imports like `import { Resource } from 'sst'`, `sst.aws.*` components, or Lambda + API Gateway + DynamoDB + S3 patterns. Covers component selection, resource linking, secrets, deployment stages, CI/CD, cost optimization, and troubleshooting."
---

# SST v3 (Ion) Expert Guide

SST v3 uses Pulumi/Terraform (not CDK/CloudFormation like v2), deploys from your local machine, and stores state in S3. Your entire app is defined in a single `sst.config.ts`.

---

## Architecture Thinking Framework

Before writing infrastructure code, answer these questions — they drive every component and configuration decision:

| Question | Impact |
|----------|--------|
| **Traffic pattern**: Bursty or steady? Peak RPS? | Bursty → Lambda. Steady/high-throughput → ECS Service |
| **Latency budget**: Can you tolerate cold starts? | <100ms p99 → warm Service or provisioned Lambda. <1s OK → Lambda |
| **Data model**: Relational or access-pattern-driven? | Complex joins → Postgres (Aurora). Known access patterns → DynamoDB |
| **Execution time**: Under 15 minutes? | Yes → Lambda. No → Task (one-off) or Service (persistent) |
| **Persistent connections**: WebSockets, streaming, connection pools? | Yes → Service (Fargate) or Realtime. Lambda can't hold connections |
| **Cost ceiling**: Monthly budget? | <$10/mo → Lambda + DynamoDB (pure serverless). $50+ → can afford VPC/Postgres |
| **Team stages**: Devs need isolated environments? | Yes → SST stages. Each `sst dev` creates personal infra per developer |

**Use the answers to route into the decision tree below.**

---

## Decision Tree: What Are You Building?

| Scenario | Framework Fit | Primary Components |
|----------|--------------|-------------------|
| REST/GraphQL API | Bursty, <15min, access-pattern data | `ApiGatewayV2` + `Function` + `Dynamo`/`Postgres` |
| Full-stack Next.js/Remix/Astro | Frontend + API, SSR needed | `Nextjs`/`Remix`/`Astro` + `ApiGatewayV2` |
| Static site + API | No SSR, bursty API | `StaticSite` + `ApiGatewayV2` + `Function` |
| Event-driven microservices | Async, decoupled producers/consumers | `Bus` + `Queue` + `SnsTopic` + `Function` |
| Containers (long-running) | Steady traffic, persistent connections, >15min | `Cluster` + `Service` |
| Background jobs / Cron | Scheduled or one-off compute | `Cron` + `Function` or `Task` (>15min) |
| Real-time (WebSocket) | Persistent connections, pub/sub | `Realtime` or `ApiGatewayWebSocket` |
| AI/ML streaming | Response streaming, long inference | `Function` (streaming) or `Service` (GPU) |

**MANDATORY** — Read [components.md](references/components.md) before selecting or configuring components. **Do NOT load** patterns.md, deployment.md, or troubleshooting.md for component selection.

**MANDATORY** — Read [patterns.md](references/patterns.md) when designing multi-service architecture or choosing between patterns. **Do NOT load** deployment.md or troubleshooting.md for architecture design.

---

## Common Pitfalls — Things That Will Burn You

- **NEVER use `.env` files for resource credentials** — SST's linking system (`link: [resource]` + `Resource.X.name`) is type-safe, auto-rotates credentials, and manages IAM permissions automatically. `.env` files are insecure, stage-unaware, and cause credential drift across team members.

- **NEVER forget `/// <reference path="./.sst/platform/config.d.ts" />` at the top of sst.config.ts** — without it, TypeScript won't know about `$config`, `sst.aws.*`, or `$app`. Run `sst dev` once to generate the types if they're missing.

- **NEVER set `removal: "remove"` in production** — this deletes all resources (including databases with your data) when you run `sst remove`. Production must use `"retain"`: `removal: input?.stage === "production" ? "retain" : "remove"`.

- **NEVER import resources managed by another IaC tool** — SST takes full ownership of imported resources. Removing the import from code deletes the actual resource. If another team manages it, reference it via `Linkable` instead.

- **NEVER put secrets in `sst.config.ts` directly** — they end up in state files and git. Use `new sst.Secret("MySecret")` + `sst secret set MySecret value`. Secrets are encrypted in S3.

- **NEVER manually create IAM roles for linked resources** — when you `link: [bucket]` on a function, SST automatically grants the correct IAM permissions. Adding manual policies causes conflicts and over-permissioning.

- **NEVER skip the `--fallback` flag for secrets in preview/PR environments** — PR-based preview stages don't have secrets set. `sst secret set MySecret fallback-value --fallback` provides a default for all stages without explicit secrets.

- **NEVER use `process.env` to access linked resources in functions** — linked resources are injected encrypted into `globalThis` (not env vars) and decrypted by the SST SDK. Use `import { Resource } from "sst"` and `Resource.MyBucket.name`.

- **NEVER deploy containers without setting `health.path`** — ECS services will repeatedly restart without proper health checks. Use a lightweight `/health` endpoint returning 200, not your main handler.

- **NEVER use VPC for Lambda unless you actually need private resource access** — VPC adds cold start latency (seconds, not ms) and requires NAT Gateway ($32+/month) for internet access. Most Lambda functions don't need VPC. DynamoDB, S3, SQS, SNS, EventBridge are all accessible without VPC.

- **NEVER run `sst dev` on shared or production stages** — `sst dev` replaces Lambda functions with stub proxies. If you kill the CLI, the stubs remain deployed and all invocations will timeout. Run `sst deploy` to restore real functions. Personal stages only.

- **NEVER expect automatic rollback on failed deploys** — unlike CloudFormation, SST v3 has NO rollback. A failed deploy leaves infrastructure partially updated. Always test in a dev stage first. Use `sst diff` to preview changes before deploying.

- **NEVER forget `protect: true` for production** — this prevents `sst remove` from executing at all on the stage, as a safety net beyond `removal: "retain"`.

- **NEVER delete the SSM parameter at `/sst/passphrase/<app>/<stage>`** — without it, SST cannot decrypt your state file or deploy your app. This is the encryption key for all secrets in state.

- **NEVER use managed NAT Gateway in dev/staging stages** — use `nat: "ec2"` (t4g.nano ~$4/month) instead of `nat: "managed"` ($32/month per AZ). Reserve managed NAT for production where you need HA.

- **NEVER name resources with lowercase or special characters** — SST component names must be PascalCase alphanumeric (e.g., `"MyBucket"` not `"my-bucket"`). SST auto-generates actual AWS resource names from this.

- **NEVER deploy to production without `$transform` for global standards** — use global transforms to enforce ARM architecture, log retention, tagging, and permissions boundaries across all functions.

---

## The sst.config.ts Structure

```typescript
/// <reference path="./.sst/platform/config.d.ts" />

export default $config({
  app(input) {
    return {
      name: "my-app",
      removal: input?.stage === "production" ? "retain" : "remove",
      protect: ["production"].includes(input?.stage),
      home: "aws",
      providers: { aws: { region: "us-east-1" } },
    };
  },
  async run() {
    // Global standards — enforce on ALL functions
    $transform(sst.aws.Function, (args) => {
      args.architecture ??= "arm64";
      args.logging ??= { retention: "1 week" };
    });

    // Split infra into files
    await import("./infra/storage");
    await import("./infra/api");

    // Return outputs: return { apiUrl: api.url }
  },
});
```

**Key facts**: `run()` is `async`. `$app.stage` gives current stage. `$dev` is `true` during `sst dev`. `??=` in transforms lets individual functions override defaults.

---

## Resource Linking — The Core Pattern

Linking replaces hardcoded env vars with type-safe, IAM-managed resource access.

```typescript
// infra: link resources to functions
const bucket = new sst.aws.Bucket("Uploads");
api.route("POST /upload", {
  handler: "packages/functions/src/upload.handler",
  link: [bucket],  // grants IAM permissions + injects reference
});

// function code: access via Resource
import { Resource } from "sst";
Resource.Uploads.name;  // type-safe, auto-completed bucket name
```

**What linking handles for you:** IAM permissions (read/write to the linked resource), type-safe access (`Resource.X`), encrypted injection in Lambda (not env vars), and `SST_RESOURCE_*` env vars for frontends (server-side only).

**Also works with:** Secrets (`Resource.MySecret.value`), custom linkables (`new sst.Linkable("Config", { properties: { ... } })`), external Pulumi resources (`Linkable.wrap()`), and all frontend frameworks.

---

## Secrets Management

```typescript
const stripeKey = new sst.Secret("StripeKey");
// Link to function: link: [stripeKey]
// Access in code: Resource.StripeKey.value
```

```bash
sst secret set StripeKey sk_live_xxx --stage production    # per-stage
sst secret set StripeKey sk_test_xxx --fallback            # fallback for PR/preview stages
```

**Placeholder pattern** for non-sensitive defaults: `new sst.Secret("SentryDsn", "https://default@sentry.io/123")` — can be overridden per stage but has a usable default out of the box.

---

## Project Structure

SST recommends a monorepo: `sst.config.ts` at root, `infra/` for infrastructure split by domain (api.ts, storage.ts, auth.ts), `packages/functions/` for Lambda handlers, `packages/core/` for shared business logic, `packages/web/` for frontend.

**Why split `infra/` into files?** Keeps config readable and imports clean: `await import("./infra/storage")` in `run()`. Organize by domain (orders, users, auth), not by AWS service.

---

## Deployment & Stages

`sst dev` creates a personal stage per developer. `sst deploy --stage X` deploys named stages. `sst remove --stage X` tears down everything.

**Stage-conditional pattern:**
```typescript
const isProd = $app.stage === "production";
const api = new sst.aws.ApiGatewayV2("Api", {
  domain: isProd ? { name: "api.example.com" } : undefined,
});
```

**MANDATORY** — Read [deployment.md](references/deployment.md) when setting up CI/CD, GitHub Actions, SST Console auto-deploy, custom domains, or preview environments. **Do NOT load** components.md or patterns.md for deployment setup.

---

## Transform & Global Standards

```typescript
// Global: enforce ARM + log retention on ALL functions
$transform(sst.aws.Function, (args) => {
  args.architecture = "arm64";     // Graviton — 20% cheaper, faster
  args.logRetention = "1 week";    // prevent unbounded CloudWatch costs
});

// Per-component: customize underlying AWS resources
new sst.aws.Function("MyFunc", {
  handler: "src/handler.main",
  transform: {
    function: (args) => { args.ephemeralStorage = { size: 1024 }; },
    role: (args) => { args.maxSessionDuration = 7200; },
  },
});
```

**Production checklist for `$transform`:**
- ARM architecture (`arm64`) — 20% cost savings, faster cold starts
- Log retention — prevent unbounded CloudWatch costs
- Permissions boundaries — enforce least privilege org-wide
- Tagging — cost allocation and compliance

---

## Importing Existing Resources

Add `opts.import` in the component's transform → deploy → read the error message → set matching args → deploy again → remove `opts.import` (keep args).

```typescript
new sst.aws.Bucket("MyBucket", {
  transform: {
    bucket: (args, opts) => { opts.import = "my-existing-bucket-name"; },
  },
});
```

**Warning:** Once imported, SST owns it. Removing from code deletes the real resource. To reference without owning, use `Linkable` instead.

---

## Cost Awareness

| Resource | Hidden Cost | Mitigation |
|----------|------------|------------|
| NAT Gateway | $32+/month per AZ | Avoid VPC for Lambda; use `nat: "ec2"` ($4/mo) in dev |
| CloudWatch Logs | Unbounded | Set `logRetention: "1 week"` via `$transform` |
| API Gateway | $1/million requests | Watch for runaway polling from frontends |
| DynamoDB On-Demand | $1.25/million writes | Use provisioned for predictable workloads |
| RDS Aurora Serverless | $0.06/ACU-hour min | Cold start takes 25+ seconds; min ~$43/month |
| Secrets Manager | $0.40/secret/month | SST uses S3-encrypted secrets instead (free) |

**Biggest trap:** VPC with NAT Gateways for Lambda functions that don't need private access. Three AZs with managed NAT = $96/month idle.

---

## Troubleshooting Decision Tree

**Deployment fails?**
1. "Unable to resolve AWS account" → `aws sts get-caller-identity` — fix credentials
2. "Resource already exists" → `sst remove --stage X` to clean up orphaned resources
3. State lock error → another deploy running or crashed; check S3 state bucket
4. Circular dependency → split resources into separate infra files, use `$output()` to break cycles

**Function not working in `sst dev`?**
1. No logs → handler path doesn't match file location (paths are relative to project root)
2. Timeout → trying to reach VPC resource without VPC config, or cold start exceeding timeout
3. "Resource is not defined" → missing `link: [resource]` on the function
4. Type errors → delete `.sst/` and run `sst dev` to regenerate types

**Frontend can't access API?**
1. CORS → add `cors: true` to `ApiGatewayV2` and return CORS headers from Lambda
2. Env var undefined → frontends use `environment` prop (not `link`), with `NEXT_PUBLIC_`/`VITE_` prefix for client-side
3. API URL undefined → return from `run()` and pass via `environment: { NEXT_PUBLIC_API: api.url }`

**MANDATORY** — Read [troubleshooting.md](references/troubleshooting.md) for detailed error resolution, state recovery, or migration from v2/Serverless Framework/CDK. **Do NOT load** other references when debugging.
