---
name: failure-recovery
description: Google Ads MCP failure modes — reading the flattened ToolError, auth and developer-token access levels, manager/test-account traps, quotas, the failures that bypass error handling entirely, and the empty-result decision tree. Load on any authentication, permission, quota, or setup error, or when configuring the server.
---

# Failure Recovery

Diagnosis here is symptom → next call, not symptom → memorized code. The server
discards the structured error code, so the message text is the diagnostic.

---

## How errors reach you

Every recognized Google Ads API error is flattened into one FastMCP `ToolError`:

```
Request ID: {request_id}
Google Ads API Error: {message}
```

with one `Google Ads API Error:` line per underlying error. **The structured
`error_code` enum does not survive this wrapping.** Classify by reading the
message text; do not expect a machine-readable code.

The request ID is opaque to you — it is not a lookup key you can resolve. Its
value is for support escalation. Hand it to the user together with the message
when a failure is not self-explanatory.

### The failures that bypass this entirely

Two failure classes never produce the format above, because they are not
Ads-API-recognized errors and the server only catches `GoogleAdsException`:

1. **A sunset API version.** The server does not pin its API version in code —
   it inherits whatever the installed `google-ads` client library defaults to,
   with no upper bound in the dependency spec. When Google sunsets that version,
   the RPC fails without Google Ads failure metadata, so it propagates as a raw
   `grpc.RpcError` past the handler.
2. **A response exceeding the 64MB gRPC cap.** Surfaces as a raw gRPC error, not
   a `GoogleAdsError`.

**Diagnostic signal: a tool failure with no `Request ID:` line at all.** That
points at one of these two — not at a malformed query. For the 64MB case, narrow
`fields` and add a `limit`. For the sunset case, the fix is upgrading the server's
`google-ads` dependency, which is outside the query's control; report it.

---

## Retry classification

Since the code is gone, classify by message text.

| Do not retry — fix the request | Retry with exponential backoff + jitter |
|---|---|
| Malformed query, unknown field, prohibited metric/segment combination | `INTERNAL`, `UNKNOWN` |
| `PERMISSION_DENIED`, `UNAUTHENTICATED` | `UNAVAILABLE`, `DEADLINE_EXCEEDED` |
| `NOT_FOUND`, `INVALID_ARGUMENT`, `FAILED_PRECONDITION` | Short-term throttling (`RESOURCE_TEMPORARILY_EXHAUSTED`) |
| Daily quota exhausted (`RESOURCE_EXHAUSTED`) — will not clear for hours | |

Distinguish the two exhaustion cases: short-term throttling is worth retrying in
seconds; a daily quota is not worth retrying at all until reset.

---

## Setup and authentication

The server builds a fresh client on **every** tool call, so a missing environment
variable fails immediately, before any network request.

| Symptom | Cause | Fix |
|---|---|---|
| `GOOGLE_ADS_DEVELOPER_TOKEN environment variable not set.` (a `ValueError`, not an API error) | Env var absent from the MCP client's `env` block | Set it in the client config |
| `DEVELOPER_TOKEN_INVALID` | Typo, or token in the wrong variable | Re-copy verbatim from the API Center |
| `"The developer token is only approved for use with test accounts..."` | A Test-level token pointed at a production account | Apply for Explorer/Basic access, or query a test account |
| `OAUTH_TOKEN_REVOKED` / expired token | ADC expired or access revoked | Re-run `gcloud auth application-default login` with the `adwords` scope |
| `"User doesn't have permission to access customer. Note: If you're accessing a client customer, the manager's customer id must be set in the 'login-customer-id' header."` | Credential reaches a child account through a manager, but `GOOGLE_ADS_LOGIN_CUSTOMER_ID` is unset or wrong | Set it to the **manager** account ID, digits only |
| `CUSTOMER_NOT_FOUND` | Newly created account not yet propagated, or an unresolvable ID without `login-customer-id` | Wait a few minutes and retry; otherwise check `login-customer-id` |
| `CUSTOMER_NOT_ENABLED` | Signup incomplete, or account deactivated | Account-side fix, not a query fix |

**The `adwords` scope is mandatory** on Application Default Credentials
(`https://www.googleapis.com/auth/adwords`). Credentials created without it
authenticate fine and then fail on every Ads call.

### Developer token access levels

Access level governs how many operations per day the token may run. Test-level
tokens **cannot query production accounts at all** — which is the most common
reason a correctly-configured setup returns errors on a real account. Standard
access lifts the daily cap.

Review timelines for upgrades are actively changing (Google was piloting a
faster brand-verification path in 2026), so do not quote a specific
business-day SLA — point the user at the API Center for the current process.

---

## Empty results — the five-way branch

An empty result is the most misread outcome in this domain. **Never report "no
data" before ruling these out**, roughly cheapest first:

1. **The customer ID is a manager account.** `customers_list_accessible_customers`
   returns manager and serving IDs in an identical shape — there is no flag to
   tell them apart. Query `customer_client` for `id`, `descriptive_name`,
   `manager`, `level`. Rows coming back with `level >= 1` mean you were querying
   the manager; retarget to a child ID.
2. **It is a test account.** Test accounts have no serving data by design. The
   setup is correct; there is simply nothing to report. Confirm the field name
   for the test-account flag via `metadata_get_resource_metadata("customer")`
   rather than assuming it.
3. **The filter over-constrained.** Drop conditions one at a time, starting with
   the date filter. When rows reappear, inspect that condition — a case
   mismatch is a frequent culprit, since `=`, `IN` and `CONTAINS` are
   case-sensitive while `LIKE` is not.
4. **Outside the retention window.** Granular (daily/weekly/hourly) data is
   retained 37 months; monthly and coarser, 11 years. A day-segmented query
   further back raises `REQUESTED_DATE_GRANULARITY_NOT_SUPPORTED` — an explicit
   error, not silence. Re-ask the question without the date segment.
5. **Genuinely no data.** Re-run with a wide window and a single reliable canary
   field such as `metrics.impressions`. Still zero → check `campaign.status` and
   `campaign.start_date` for whether the campaign was ever eligible to serve in
   that window.

Privacy suppression is a sixth case, but it produces *missing rows*, not an empty
result — see `measurement-traps.md`.

---

## Field-level failures

| Symptom | Next call | Reading the answer |
|---|---|---|
| Unknown or invalid field name | `metadata_get_resource_metadata(resource)` (reuse the session cache) | Check the exact dotted name against `selectable`. A miss usually means the wrong resource prefix — the attributed-resource graph is not guessable from naming — or the field does not exist in this API version. |
| Metric or segment incompatible with the resource | Same call | Absent from the returned lists → fundamentally incompatible; change resource or drop it. **Present** in the lists → the conflict is pairwise with another field already in the query. `get_resource_metadata` reports resource-level compatibility only, never pairwise combinations, so remove one recently-added field at a time until it succeeds. |
| Permission error on a field that exists | Re-run without the suspect field to confirm the rest works | `selectable = true` is a **schema** fact, not an **entitlement** fact. Auction Insights fields are the canonical case: real, selectable, and permission-denied for almost everyone behind a closed allowlist. Nothing predicts this in advance. Repeated permission errors on one field family are an account entitlement gap to report, not a query bug to fix. |

---

## Resource-specific constraints worth knowing before you query

These raise errors that do not name the real cause:

- `change_event` and `change_status` require a date bound and `LIMIT <= 10000`.
  Paginate by re-querying with the last-seen timestamp as a lower bound.
- `click_view` must be filtered to **exactly one day**, and reaches back only 90
  days. A multi-day range is rejected outright.
- Date ranges must be closed at both ends. Half-open comparisons fail.

---

## Cost control as a failure mode

Context exhaustion is a failure even when every call succeeds.

- The documentation resources are unusable in a loop: `metrics` ~1.25M tokens,
  `segments` ~1.39M, `discovery-document` ~662k. Two exceed a 1M-token window
  outright. `release-notes` (~96k) only for a targeted deprecation question.
- `metadata_get_resource_metadata` costs tens of thousands of tokens per
  resource. Cache per resource per session. Its docstring's instruction to call
  it before every query is not affordable literally.
- `search_search` has no server-side row cap and does not paginate. An unbounded
  query on a large account is the single easiest way to blow the context window.
  Size `fields` to the question and treat `limit` as mandatory below campaign
  grain.

---

## Session cache

Hold for the session: discovered customer IDs and which are managers; every
`get_resource_metadata` response keyed by resource.

Do not carry a metadata cache across sessions — API versions change fields, and
the server's effective version can shift under it without a code change.

**Staleness signal:** a field that worked earlier in the session starting to fail
with no query change means re-fetch that resource's metadata rather than trusting
the cached answer.
