# SST Troubleshooting & Migration

## Table of Contents
- [Common Errors](#common-errors)
- [Debugging Strategies](#debugging-strategies)
- [State & Lock Issues](#state--lock-issues)
- [Performance Issues](#performance-issues)
- [Migration from v2](#migration-from-v2)
- [Migration from Serverless Framework](#migration-from-serverless-framework)
- [Migration from CDK](#migration-from-cdk)

---

## Common Errors

### "Unable to resolve AWS account"
**Cause:** AWS credentials not configured or expired.
**Fix:**
```bash
# Check current credentials
aws sts get-caller-identity

# If using SSO
aws sso login --profile your-profile

# If using env vars, ensure these are set:
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
```

### "Resource already exists"
**Cause:** Previous deployment left resources, or another stage has same resource name.
**Fix:**
```bash
# Remove the stage cleanly
sst remove --stage <stage-name>

# If that fails, manually delete in AWS Console, then:
sst deploy --stage <stage-name>
```

### "Access Denied" / "not authorized to perform"
**Cause:** IAM user/role lacks permissions SST needs.
**Fix:** For development, use `AdministratorAccess`. For CI/CD, create a role with:
- CloudFormation, S3, Lambda, IAM, CloudWatch Logs, API Gateway (minimum)
- Add service-specific permissions as needed (DynamoDB, SQS, etc.)
- SST manages IAM roles for linked resources, so your deploy role needs `iam:CreateRole`, `iam:AttachRolePolicy`, etc.

### TypeScript errors in sst.config.ts
**Cause:** Missing type definitions.
**Fix:**
1. Ensure `/// <reference path="./.sst/platform/config.d.ts" />` is at the top
2. Run `sst dev` once to generate `.sst/` directory with types
3. If types are stale, delete `.sst/` and run `sst dev` again

### "Cannot find module 'sst'"
**Cause:** SST SDK not installed in the package where you're importing `Resource`.
**Fix:**
```bash
# In the package that imports { Resource } from "sst":
npm install sst
```

### Function handler not found
**Cause:** Handler path in config doesn't match actual file.
**Fix:** Handler paths are relative to the project root, not the infra file.
```typescript
// If your file is at: packages/functions/src/api/users.ts
// And it exports: export const handler = ...
// Then the handler path is:
handler: "packages/functions/src/api/users.handler"
//        ^--- relative to project root         ^--- exported function name
```

### CORS errors
**Cause:** API Gateway CORS not configured, or misconfigured.
**Fix:**
```typescript
new sst.aws.ApiGatewayV2("Api", {
  cors: {
    allowOrigins: ["http://localhost:3000", "https://app.example.com"],
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
    allowCredentials: true,
  },
});
```
Also ensure your Lambda handler returns CORS headers (API Gateway CORS config alone may not suffice for all cases):
```typescript
return {
  statusCode: 200,
  headers: {
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json",
  },
  body: JSON.stringify(data),
};
```

### "Circular dependency"
**Cause:** Two infra files import from each other.
**Fix:** Extract the shared resource into a third file, or use `$output()` to break the cycle. Reorganize infra files by domain rather than by resource type.

---

## Debugging Strategies

### Local Development (`sst dev`)
1. **Console output**: `console.log()` in Lambda handlers appears in the `sst dev` terminal
2. **SST Console**: `sst console` opens a web UI with log tailing, resource inspection
3. **Breakpoints**: Use `--debug-stack` flag and attach your IDE debugger
4. **VPC tunnel**: `sst tunnel` creates SSH tunnel to VPC resources for local access

### Production Debugging
1. **CloudWatch Logs**: Logs persist in CloudWatch. Set `logRetention` on Functions to control retention.
2. **SST Console**: Connect your production stage for live log tailing
3. **X-Ray**: Enable tracing for distributed request tracing:
   ```typescript
   new sst.aws.Function("MyFunc", {
     handler: "src/handler.main",
     transform: {
       function: (args) => {
         args.tracingConfig = { mode: "Active" };
       },
     },
   });
   ```

### Common Debugging Patterns

**"Function works locally but fails deployed":**
1. Check environment variables are set (linked resources might be missing)
2. Check IAM permissions (local dev uses your AWS credentials, deployed uses the function's role)
3. Check VPC configuration (function might not have internet access)

**"Timeout errors":**
1. Function trying to connect to VPC resource without VPC config
2. Function trying to reach internet from VPC without NAT Gateway
3. Cold start + processing time exceeding timeout

**"Cannot read properties of undefined":**
1. `Resource.X` is undefined — missing `link: [X]` on the function
2. `event.body` is undefined — request has no body (GET requests)
3. `event.pathParameters` is undefined — route pattern doesn't have `{id}`

---

## State & Lock Issues

### Stuck Deployment
**Cause:** Previous deploy crashed, leaving a state lock.
**Fix:**
```bash
# SST stores state in S3. Check for lock files:
# Bucket: sst-state-<hash>
# Look for .lock files

# If you're sure no other deploy is running:
# The lock should auto-expire. Wait a few minutes, then retry.
# If it persists, manually delete the lock file from S3.
```

### State Corruption
**Cause:** Rare — usually from manual AWS Console changes conflicting with SST state.
**Fix:**
1. Don't panic — state is backed up in S3
2. Try `sst deploy` — it often self-corrects
3. If resource exists in AWS but not in state, import it
4. As last resort, `sst remove` and redeploy (will destroy resources)

### State Drift
**Cause:** Someone modified resources via AWS Console instead of SST.
**Fix:** SST detects drift on next deploy and will correct it. To preview: `sst diff` (if available) or review the deploy plan output.

---

## Performance Issues

### Cold Starts
**Root causes and mitigations:**

| Cause | Impact | Mitigation |
|-------|--------|------------|
| VPC attachment | +2-5 seconds | Avoid VPC unless required |
| Large bundle | +0.5-2 seconds | Tree-shake, externalize AWS SDK |
| Low memory | +0.5-1 second | Increase memory (also increases CPU) |
| Runtime init | +100-500ms | Use top-level imports wisely |

**Specific mitigations:**
```typescript
// 1. Use ARM architecture (faster cold starts)
$transform(sst.aws.Function, (args) => {
  args.architecture = "arm64";
});

// 2. Keep bundles small
new sst.aws.Function("Fast", {
  handler: "src/handler.main",
  nodejs: {
    esbuild: {
      external: ["@aws-sdk/*"],  // Already in Lambda runtime
    },
  },
});

// 3. Warm production functions
new sst.aws.Nextjs("Web", {
  warm: 5,  // Keep 5 instances warm
});
```

### Slow Deployments
- First deploy is always slowest (creating all resources)
- Subsequent deploys are incremental and much faster
- If deploys are slow, check if you're creating VPC resources (NAT Gateway creation takes minutes)
- Avoid creating too many Lambda functions — consider using a Router or catch-all routes

---

## Migration from v2

### Key Architectural Changes
- **CDK/CloudFormation → Pulumi/Terraform**: Different state management
- **Stacks → No stacks**: No resource limits per stack
- **`sst bind` → built into `sst dev`**: Multiplexer handles frontends
- **`Resource` import path**: `import { Resource } from "sst"` (same)
- **Config format**: `stacks(app) {}` → `$config({ app(), async run() {} })`

### Migration Steps
1. **Don't try to migrate in-place** — create new sst.config.ts alongside old config
2. **Map constructs to components**:
   | v2 Construct | v3 Component |
   |-------------|-------------|
   | `Api` | `sst.aws.ApiGatewayV2` |
   | `Table` | `sst.aws.Dynamo` |
   | `Bucket` | `sst.aws.Bucket` |
   | `Function` | `sst.aws.Function` |
   | `Cron` | `sst.aws.Cron` |
   | `Queue` | `sst.aws.Queue` |
   | `Topic` | `sst.aws.Topic` |
   | `StaticSite` | `sst.aws.StaticSite` |
   | `NextjsSite` | `sst.aws.Nextjs` |
   | `RemixSite` | `sst.aws.Remix` |
   | `AstroSite` | `sst.aws.Astro` |
3. **Import existing resources** if you want to keep data (DynamoDB tables, S3 buckets)
4. **Update function code**: `import { Resource } from "sst"` stays the same
5. **Update secrets**: `sst secret set` per stage (secrets aren't migrated automatically)
6. **Test thoroughly** on a dev stage before touching production

### Things That Changed
- No more `use()` for stack references — just import from other infra files
- No more `StackContext` — use `$app.stage` directly
- Permissions are automatic via `link` — no more manual `permissions` arrays for linked resources
- `transform` replaces CDK's `cdk.xxx` overrides

---

## Migration from Serverless Framework

### Mapping
| Serverless Framework | SST v3 |
|---------------------|--------|
| `serverless.yml` | `sst.config.ts` |
| `functions:` section | `new sst.aws.Function()` + `api.route()` |
| `resources:` section | Native SST components |
| `plugins:` | Usually not needed (SST handles most) |
| `sls deploy` | `sst deploy` |
| `sls offline` | `sst dev` (but deploys real infra, not local simulation) |
| Environment variables | Resource linking |
| `serverless-offline` | `sst dev` live Lambda |

### Key Difference
Serverless Framework simulates locally with `serverless-offline`; SST deploys real infrastructure and proxies function invocations to your local machine. This means:
- Your local code runs against real AWS services (real DynamoDB, real S3)
- No more "works locally but not in prod" issues from simulation gaps
- You need AWS credentials even for local development

---

## Migration from CDK

### Mapping
| CDK | SST v3 |
|-----|--------|
| `cdk.Stack` | No stacks needed |
| `new lambda.Function()` | `new sst.aws.Function()` |
| `new apigateway.RestApi()` | `new sst.aws.ApiGatewayV2()` |
| `new dynamodb.Table()` | `new sst.aws.Dynamo()` |
| `fn.addEnvironment()` | `link: [resource]` |
| `bucket.grantRead(fn)` | Automatic via `link` |
| L3 constructs | SST components (higher-level) |
| `cdk deploy` | `sst deploy` |
| CloudFormation state | Pulumi/S3 state |

### What SST adds over CDK
- Live local development (`sst dev`)
- Type-safe resource linking (no hardcoded env vars)
- Automatic IAM permissions for linked resources
- Frontend framework components (Nextjs, Remix, etc.)
- Secrets management built-in
- Console for monitoring and debugging
