# SST Deployment & CI/CD

## Table of Contents
- [GitHub Actions](#github-actions)
- [SST Console Auto-Deploy](#sst-console-auto-deploy)
- [Multi-Account Strategy](#multi-account-strategy)
- [Custom Domains](#custom-domains)
- [Preview Environments](#preview-environments)
- [Seed.run](#seedrun)

---

## GitHub Actions

### Basic Deploy Workflow

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write      # Required for OIDC
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - run: npm ci

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID:role/GitHubActionsRole
          aws-region: us-east-1

      - run: npx sst deploy --stage production
```

**Use OIDC, not access keys.** OIDC (role-to-assume) is more secure than storing AWS access keys in GitHub secrets. Set up an IAM role with a trust policy for your GitHub org/repo.

### Multi-Stage Pipeline

```yaml
name: Pipeline
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    steps:
      # ... setup ...
      - run: npx sst deploy --stage dev

  deploy-staging:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      # ... setup ...
      - run: npx sst deploy --stage staging

  deploy-production:
    if: github.ref == 'refs/heads/main'
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production        # requires manual approval
    steps:
      # ... setup ...
      - run: npx sst deploy --stage production

  preview:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      # ... setup ...
      - run: npx sst deploy --stage pr-${{ github.event.pull_request.number }}

  cleanup-preview:
    if: github.event.action == 'closed'
    runs-on: ubuntu-latest
    steps:
      # ... setup ...
      - run: npx sst remove --stage pr-${{ github.event.pull_request.number }}
```

---

## SST Console Auto-Deploy

The SST Console (sst.dev/console) can handle deployments directly, eliminating the need for GitHub Actions entirely.

**Setup:**
1. Connect your GitHub repo in the Console
2. Configure stages and their target branches
3. Console auto-deploys on push

**Features:**
- Automatic preview environments for PRs
- Resource visibility (all infra, not just SST components)
- Change tracking and audit logs
- Log tailing from the web UI
- Free tier available

**When to use Console vs GitHub Actions:**
| Factor | Console | GitHub Actions |
|--------|---------|----------------|
| Setup complexity | Click-through | YAML config |
| Custom build steps | Limited | Full flexibility |
| Integration tests | Not built-in | Easy to add |
| Cost | Free tier, paid plans | Free for public repos |
| Multi-account | Supported | Manual IAM setup |

---

## Multi-Account Strategy

For production isolation, use separate AWS accounts per environment.

```typescript
// sst.config.ts
app(input) {
  return {
    name: "my-app",
    removal: input?.stage === "production" ? "retain" : "remove",
    home: "aws",
    providers: {
      aws: {
        region: "us-east-1",
        // AWS_PROFILE or role assumption handles account switching
      },
    },
  };
},
```

```bash
# Deploy to different accounts via profiles
AWS_PROFILE=dev sst deploy --stage dev
AWS_PROFILE=prod sst deploy --stage production
```

**Recommended account structure:**
- **Dev account**: Personal stages + shared dev stage
- **Staging account**: Pre-production testing
- **Production account**: Production only, restricted access

---

## Custom Domains

### API Custom Domain
```typescript
const api = new sst.aws.ApiGatewayV2("Api", {
  domain: {
    name: "api.example.com",
    dns: sst.aws.dns({ zone: "Z1234567890" }),  // Route53 hosted zone
  },
});
```

### Frontend Custom Domain
```typescript
new sst.aws.Nextjs("Web", {
  path: "packages/web",
  domain: {
    name: "app.example.com",
    redirects: ["www.example.com"],  // redirect www to apex
  },
});
```

### Using Cloudflare DNS
```typescript
domain: {
  name: "api.example.com",
  dns: sst.cloudflare.dns(),
}
```

**DNS providers supported:** Route53 (default), Cloudflare, Vercel. For other providers, use `dns: false` and manually create CNAME records.

---

## Preview Environments

Preview environments give each PR its own isolated deployment.

```typescript
// sst.config.ts — handle preview stage naming
async run() {
  const isProd = $app.stage === "production";
  const isPreview = $app.stage.startsWith("pr-");

  const api = new sst.aws.ApiGatewayV2("Api", {
    domain: isProd
      ? { name: "api.example.com" }
      : isPreview
        ? { name: `${$app.stage}.preview.example.com` }
        : undefined,
  });
}
```

**Secret fallbacks are critical for preview environments:**
```bash
# Set once — all PR stages will use these
sst secret set StripeKey sk_test_xxx --fallback
sst secret set DatabaseUrl postgres://... --fallback
```

**Cleanup:** Always remove preview stages when PRs close. Without cleanup, orphaned resources accumulate costs.

---

## Seed.run

Seed is a CI/CD platform built specifically for SST (by the same team).

**Key advantage:** Zero-config deployment — connect your repo and it auto-detects SST, configures builds, and manages stages.

**When to use Seed vs GitHub Actions vs Console:**
- **Seed**: Simplest setup, good for teams that want zero CI/CD config
- **Console**: Good visibility + deployment, growing feature set
- **GitHub Actions**: Maximum flexibility, custom pipelines, existing CI/CD investment
