---
name: api-explorer
description: Reverse-engineer APIs and websites using Chrome DevTools MCP to produce detailed, agent-consumable specifications. Use when pointed at a URL to understand how an API or website works — discovering REST endpoints, GraphQL schemas, WebSocket protocols, auth flows, data models, and pagination patterns. Triggers on: "explore this API", "figure out how this site works", "reverse engineer", "create an API spec", "map this API", "discover endpoints", "understand this website's API", "reverse engineer this GraphQL API", "figure out this WebSocket protocol", "what endpoints does this site use". Produces structured three-tier specs other agents can use to build integrations.
---

# API Explorer

Reverse-engineer any website or API into a detailed specification using Chrome DevTools MCP.

## Core Philosophy

**Architecture classification determines everything.** The first 5 minutes decide whether you waste the next 30. A GraphQL SPA and a server-rendered form app require completely different strategies. Classify before exploring.

**Static analysis before runtime observation.** Page source, hydration globals, and JS bundles reveal more about API structure in less time than watching network traffic. You can see every route from the code before navigating once.

**Requests are state-dependent, not independent.** A captured request is the product of every prior request in the session. The initialization sequence that made it valid is as important as the request itself. Miss the init sequence and your spec is silently wrong.

**Document during exploration, not after.** Maintain a live working spec that you update every few minutes. Never explore for 30 minutes then try to recall what you found.

---

## Before You Start

Before committing to the full exploration, resolve three questions:

| Question | Options | Impact |
|----------|---------|--------|
| **What depth is needed?** | Quick scan (5 min) → Tier 1 only. Standard (35 min) → Tiers 1-2. Deep (60+ min) → full Tiers 1-3 with verification | Don't run a 35-minute exploration when Tier 1 endpoint list is all that's needed |
| **Does an official spec already exist?** | Check `/openapi.json`, `/swagger.json`, `/graphql` introspection, vendor API docs portal | If found, extract it directly — skip Phases 1-3 and augment in Phase 4 |
| **Who consumes this spec?** | Agent writing integration code → prioritize auth flow + request schemas. Agent calling the API directly → prioritize curl examples + error handling. Human reviewing → prioritize Tier 1 overview | Drives which tiers and sections to invest time in |

If the user hasn't specified, default to **Standard depth** with **agent integration** as the consumer.

---

## Phase 1: Reconnaissance (5 minutes)

### Step 1: Read Raw Page Source

Before opening any DevTools tools, navigate to the URL and use `evaluate_script` to extract architecture signals:

```javascript
() => ({
  nextData: window.__NEXT_DATA__ ? {
    buildId: window.__NEXT_DATA__.buildId,
    runtimeConfig: window.__NEXT_DATA__.runtimeConfig,
    pageProps: Object.keys(window.__NEXT_DATA__?.props?.pageProps || {}),
  } : null,
  nuxtData: window.__NUXT__ || null,
  remixContext: window.__remixContext ? 'present' : null,
  configGlobals: ['__ENV__','__CONFIG__','__APP_CONFIG__','APP_CONFIG'].filter(k => window[k]).map(k => ({key: k, value: window[k]})),
  scriptConfigs: [...document.querySelectorAll('script[type="application/json"]')].map(s => ({id: s.id, content: JSON.parse(s.textContent || '{}')})),
  metaApis: [...document.querySelectorAll('meta[name*="api"], meta[name*="endpoint"]')].map(m => ({name: m.name, content: m.content})),
  frameworkClues: {
    nextJs: !!document.getElementById('__next'),
    vue: !!document.getElementById('app') && !!document.querySelector('[data-v-]'),
    react: !!document.getElementById('root'),
    angular: !!document.querySelector('[ng-version]'),
  },
  scriptSrcs: [...document.querySelectorAll('script[src]')].map(s => s.src).slice(0, 20),
})
```

### Step 2: Probe Documentation Endpoints

Check these paths using `navigate_page` (or `evaluate_script` with fetch) — each reveals structural info in under 3 seconds:

| Path | What It Reveals |
|------|----------------|
| `/robots.txt` | Hidden paths, admin areas, disallowed routes (often the most interesting) |
| `/sitemap.xml` | All public routes — the complete URL map |
| `/api/` | Confirms /api/ prefix exists (even a 403 is useful) |
| `/swagger` or `/swagger-ui` or `/swagger.json` | REST API documentation |
| `/openapi.json` or `/openapi.yaml` | OpenAPI spec — if this exists, extract it directly |
| `/graphql` | GraphQL endpoint — try introspection immediately |
| `/health` or `/status` | Often reveals backend tech stack |

If `/openapi.json` returns a valid spec, you've shortcut the entire process — extract it and jump to Phase 4 (spec generation).

### Step 3: Classify the Architecture

Use the signals from Steps 1-2 to classify:

| Signal | Architecture | Exploration Strategy |
|--------|-------------|---------------------|
| Form `action=` attributes, minimal JS | Traditional SSR | Follow form POSTs, not XHR |
| Small HTML shell + large JS bundle | SPA (React/Vue/Angular) | Bundle analysis first, then runtime |
| Full HTML + `window.__NEXT_DATA__` | SSR + hydration (Next.js/Nuxt) | Extract hydration data first, then XHR |
| Single `/graphql` endpoint | GraphQL backend | Introspection → bundle search for queries |
| `wss://` connections on load | Real-time app | WS protocol fingerprinting before REST |
| Fetch calls to multiple base URLs | BFF / microservices | Map all base URLs separately |
| JSON at `/api/` but no browser UI | API-only service | Check for OpenAPI/Swagger docs |

---

## Phase 2: Exploration (20 minutes)

**MANDATORY — READ ENTIRE FILE BEFORE PROCEEDING**: Load [`references/js-recipes.md`](references/js-recipes.md) completely. It contains the fetch/XHR interceptor required for `initScript`, the WebSocket monitor, and all framework-specific extraction scripts used throughout this phase.

**Do NOT load** `references/spec-template.md` during this phase — load it only when you reach Phase 4.

### Set Up Network Capture

Use the fetch/XHR interceptor from `js-recipes.md` as the `initScript` parameter on your first navigation. This captures all fetch/XHR calls including those made during framework initialization (before DOMContentLoaded). `evaluate_script` fires too late and misses initialization requests.

Navigate with the interceptor:
```
navigate_page(url: <target>, initScript: <interceptor from js-recipes.md>)
```

Then capture network traffic with aggressive filtering:

```
list_network_requests(resourceTypes: ["fetch","xhr"], pageSize: 20, pageIdx: 0)
```

**NEVER call `list_network_requests` without `resourceTypes` and `pageSize` on any real website.** Unfiltered requests on a production SPA produce 100-300+ entries and overwhelm context. The `["fetch","xhr"]` filter alone gives a 10:1 noise reduction.

### Systematic Route Visit Order

Visit pages in this order — each builds on the previous:

1. **Unauthenticated homepage** — what's publicly visible? Note any API calls without auth.
2. **Login/signup flow** — captures auth initialization, CSRF token acquisition, token exchange.
3. **Main authenticated dashboard** — the "bootstrap" request (usually the largest JSON response).
4. **One list view** — reveals collection entity + pagination pattern.
5. **One detail view** — reveals individual entity shape + relationships.
6. **Create/edit form** — reveals mutation request body schema.
7. **Settings/profile** — config endpoints not exposed elsewhere.

**At each page, answer four questions:**
1. What initialization requests fired? (First 10 requests after navigation)
2. What is the largest JSON response? (This is the primary entity for this page)
3. What user interactions trigger new requests? (Click buttons, submit forms via `take_snapshot` → `click`)
4. Are there requests to different base URLs? (These are separate services)

### Auth Flow Discovery

Start from a completely fresh context (`new_page` with `isolatedContext: "fresh"`):

1. Observe the first 10 requests — this is the initialization sequence
2. Find the auth endpoint (`/api/auth/session`, `/api/me`, `/oauth/token`)
3. Identify what it returns: Bearer token, session cookie, or CSRF token
4. Identify where credentials go in subsequent requests: `Authorization` header, `Cookie`, or request body
5. Look for token refresh: a 401 followed by `/api/auth/refresh` → retry

**Auth mechanism fingerprinting:**

| Header/Cookie Pattern | Mechanism |
|----------------------|-----------|
| `Authorization: Bearer eyJ...` | JWT (decode to find `exp`, `sub`, `scope`) |
| `Authorization: Bearer <opaque>` | Server-validated opaque token |
| `Cookie: session=...` + `X-CSRF-Token` header | Session cookie + CSRF (both needed, CSRF may rotate) |
| `x-api-key` header | API key (stable, replayable) |
| POST `/oauth/token` with `grant_type=client_credentials` | OAuth Client Credentials |
| 401 → POST `/auth/refresh` → retry | Token refresh interceptor |

### Capture Endpoint Details

For each discovered endpoint, use `get_network_request(reqid)` to capture full details. **Save large response bodies to disk** to avoid context bloat:

```
get_network_request(reqid: <id>, responseFilePath: "/tmp/api-explorer/resp-<endpoint>.json")
```

### For GraphQL APIs

1. Try introspection first using the introspection snippet from `js-recipes.md`
2. If introspection is disabled or returns `PersistedQueryNotFound`, use the **GraphQL Bundle Mining** recipe from `js-recipes.md` — it extracts operation names, persisted query hashes, and GraphQL endpoints from loaded JS bundles
3. Look for `extensions.persistedQuery.sha256Hash` in request bodies via `list_network_requests` — this confirms APQ is in use
4. If both introspection AND bundle mining fail, fall back to observing all requests to the `/graphql` endpoint and extracting operation names and shapes from captured request/response pairs

### For WebSocket APIs

Check WebSocket connections: `list_network_requests(resourceTypes: ["websocket"])`. For frame capture, use the WebSocket monitor from `js-recipes.md` (already loaded) alongside the fetch interceptor in `initScript`. Use the protocol fingerprinting table in `js-recipes.md` to identify the WS framework from the first messages.

---

## When Discovery is Blocked

| Symptom | Likely Cause | Recovery |
|---------|-------------|---------|
| `evaluate_script` returns null or throws | CSP blocks inline scripts | Use `list_network_requests` only; skip framework-specific extraction |
| `list_network_requests` returns 0 after navigation | Service worker intercepts all traffic | Check SW registration via js-recipes.md snippet; document SW scope in spec Notes |
| Navigation redirects to CAPTCHA/challenge page | Bot detection (Cloudflare, Akamai) | Document as "automated exploration blocked"; record all static signals (page source, robots.txt) and generate partial Tier 1 only |
| All `/api/` probes return 403 immediately | Auth-wall or IP block | Map unauthenticated surface only; mark all endpoints as "auth required to discover" |
| Responses shrink or return nulls after 50+ requests | Adaptive rate limiting | Stop and prioritize: auth flow → dashboard → one list → one detail. Accept partial spec |
| `initScript` interceptor captures nothing | App uses Web Workers for API calls | Workers run in isolated contexts; `initScript` can't reach them. Fall back to `list_network_requests` only |

If blocked on multiple fronts, generate whatever partial spec you have with clear warnings. A partial spec with honest gaps is more useful than no spec.

---

## Phase 3: Verification (10 minutes)

**Never trust an unverified observation.** Verify by modifying captured requests:

1. **Strip headers one at a time** — remove auth headers individually to map exact auth requirements per endpoint
2. **Compare authenticated vs unauthenticated** — use `new_page(url, isolatedContext: "anon")` for a clean context, compare responses
3. **Test pagination boundary** — request the last page, then one beyond. Does it return empty array, 404, or repeat last page?
4. **Replay without init sequence** — call an endpoint with valid token but without prior init requests. Different response = session-state-dependent endpoint
5. **Check public vs private** — every endpoint observed while authenticated should be tested without credentials

### Critical Verification: The Initialization Sequence

Call the main data endpoint from a completely fresh context (no prior navigation, no init requests). If it returns different data or fails, the initialization sequence is mandatory for the spec. Document it as a numbered prerequisite sequence.

---

## Phase 4: Spec Generation

**MANDATORY — READ ENTIRE FILE**: Load [`references/spec-template.md`](references/spec-template.md) for the complete output template.

**Do NOT load** `references/js-recipes.md` during this phase — it was needed for Phase 2 only.

### When to Generate vs. Continue Exploring

Generate a spec when ANY of these are true:
- All entity types discovered and auth flow captured → **full spec ready**
- Exploration blocked for 2+ consecutive pages → **generate partial spec with warnings**
- Time budget exceeded → **mark incomplete sections explicitly**
- OpenAPI/Swagger spec found during reconnaissance → **extract and augment, skip manual exploration**

### Confidence Annotations (REQUIRED)

Every fact in the spec must carry one of:
- **(confirmed)** — observed multiple times OR verified by replay/modification
- **(inferred)** — observed once or derived from code analysis, not replay-verified
- **(unverified)** — suspected from signals but not directly observed

NEVER omit confidence markers to make the spec look cleaner. Consuming agents need to know what to trust and what to validate independently.

### Contradictory Observations

When the same endpoint returns different response shapes across observations:
1. Check for A/B test signals: `x-experiment` headers, `variant` fields, `account_tier` differences
2. Check if different auth states produce different schemas (role-based response shapes)
3. Document BOTH shapes in Tier 2 with the variation trigger: "Response varies by [experiment/role/feature flag]"
4. Mark the endpoint as `(variant observed)` in the Tier 1 discovery index
5. Add the variation details to the spec Notes section

Do NOT average or merge contradictory schemas — consuming agents need to know both shapes exist.

Add a top-level warning block if auth flow is unverified or Tier 2 coverage is below 50%:
> **WARNING**: Spec completeness LOW. [Specific gaps]. Recommend re-running with [specific action] before using for integration.

Generate the spec using the template. The spec has three tiers:

**Tier 1 — Discovery Index** (compact, always in context for consuming agents):
- All endpoints as a table: method, path, description, auth required
- ~500-2000 tokens for a large API

**Tier 2 — Endpoint Detail** (loaded on-demand per endpoint):
- Full request/response schemas, error codes, pagination params
- ~200-800 tokens per endpoint

**Tier 3 — Procedural Workflows** (injected for specific tasks):
- Auth initialization sequence as numbered steps
- Multi-endpoint workflows (e.g., create → configure → activate)

### Spec Content Priorities

Include in this order (each unlocks exponentially more value):

1. **Base URL and versioning pattern** — without this, nothing else works
2. **Auth initialization sequence** — numbered steps with exact URLs and field names
3. **Core entity types and ID fields** — the data model
4. **Collection endpoint pagination pattern** — cursor/offset, page size limits, boundary behavior
5. **Mutation request body schemas** — what fields are required for writes
6. **Error response envelope** — consistent error handling for consuming agents

### Format Guidelines

| Content Type | Use |
|-------------|-----|
| Parameter lists | Markdown table (name, type, required, description) |
| Auth flows | Numbered list + code block with exact values |
| Error codes | Table (code, meaning, agent action to take) |
| Request examples | curl or JSON code block (one per endpoint) |
| Pagination | Prose explanation + response shape code block |

Write the spec to a file the user specifies, or to `./api-spec-<domain>.md` by default.

---

## NEVER Do These

- **NEVER call `list_network_requests` without `resourceTypes` and `pageSize`** — unfiltered on a real SPA = 100-300 entries, context overflow
- **NEVER use `evaluate_script` to capture initialization requests** — it fires after page load; use `initScript` via `navigate_page` instead
- **NEVER read large response bodies inline** — use `get_network_request(responseFilePath: "/tmp/...")` to save to disk
- **NEVER assume a captured request is independently replayable** — it depends on the full navigation path and session state that preceded it
- **NEVER explore authenticated pages before mapping the unauthenticated surface** — you contaminate every observation with session state
- **NEVER document the error response as the API contract** — first requests often return 401/400; the success response has a different schema
- **NEVER assume the first list page is representative** — edge cases appear on page 2+, last page, and with maximum data density
- **NEVER trust that DevTools shows what really hit the network** — service workers can intercept and modify requests between the app and the network
- **NEVER treat WebSocket heartbeat frames as data** — count them separately; failing to respond to pings causes silent disconnects
- **NEVER replay cookies extracted from the browser in a separate HTTP client** — TLS fingerprint mismatch (JA3) causes silent failure on Cloudflare-protected sites
- **NEVER skip the initialization sequence in your spec** — it's the most commonly underdocumented and most critical aspect for consumers
- **NEVER assume JS bundle route extraction is complete** — code-split lazy-loaded routes won't appear in the main bundle; admin panels and premium features live in separate chunks that only load when navigated to. Mark any bundle-derived route list as "(partial)" in the spec
