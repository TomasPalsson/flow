---
name: hubspot-write
description: Verified HubSpot endpoint paths, internal property names, association type IDs, dedupe search mechanics, the fill-only-empty algorithm, error taxonomy, rate limits, and the asymmetric rollback story.
---

# HubSpot write mechanics

## The plan file

`scripts/hubspot.ts write --plan plan.json` consumes this shape. **Every property needs a
matching `sources` entry** — the script validates before any HTTP call, exits non-zero on
a violation, and has no override flag.

```json
{
  "approved_by": "tomas.ari.palsson@apro.is",
  "approved_at": "2026-07-31T14:12:00Z",

  "company": {
    "existingId": "440956262641",
    "properties": {
      "name": "Læknafélag Íslands",
      "domain": "lis.is",
      "phone": "+3545644100"
    },
    "sources": {
      "name":   { "url": "https://www.lis.is/is/um-li", "quote": "Læknafélag Íslands", "method": "verbatim", "captured_at": "2026-07-31T13:02:11Z" },
      "domain": { "url": "https://www.lis.is/", "quote": "lis.is", "method": "verbatim", "captured_at": "2026-07-31T13:02:11Z" },
      "phone":  { "url": "https://www.lis.is/is/um-li/hafa-samband", "quote": "Sími: 564 4100", "method": "verbatim", "captured_at": "2026-07-31T13:02:11Z" }
    }
  },

  "contact": {
    "properties": {
      "firstname": "Dögg",
      "lastname": "Pálsdóttir",
      "email": "doggp@lis.is",
      "jobtitle": "Framkvæmdastjóri og lögfræðingur"
    },
    "sources": {
      "firstname": { "url": "https://www.lis.is/is/um-li/laeknafelagid/starfsfolk", "quote": "Dögg Pálsdóttir | Framkvstj. og lögfræðingur | doggp@lis.is", "method": "verbatim", "captured_at": "2026-07-31T13:04:50Z" },
      "lastname":  { "url": "https://www.lis.is/is/um-li/laeknafelagid/starfsfolk", "quote": "Dögg Pálsdóttir | Framkvstj. og lögfræðingur | doggp@lis.is", "method": "verbatim", "captured_at": "2026-07-31T13:04:50Z" },
      "email":     { "url": "https://www.lis.is/is/um-li/laeknafelagid/starfsfolk", "quote": "doggp@lis.is", "method": "verbatim", "captured_at": "2026-07-31T13:04:50Z" },
      "jobtitle":  { "url": "https://www.lis.is/is/um-li/laeknafelagid/starfsfolk", "quote": "Framkvstj. og lögfræðingur", "method": "verbatim", "captured_at": "2026-07-31T13:04:50Z" }
    }
  }
}
```

| Key | Rule |
|---|---|
| `approved_by` / `approved_at` | Required for `--apply` only. Who saw the review table, and when |
| `existingId` | Optional. Present → fill-empty PATCH. Absent → create (contact create catches 409 and switches to PATCH automatically) |
| `sources.<field>.url` | Required. The page the value came from |
| `sources.<field>.quote` | Required, ≥3 chars. The **verbatim** text containing the value |
| `sources.<field>.method` | Required. `verbatim` \| `inferred-pattern` \| `ladder-fallback` |
| `sources.<field>.captured_at` | Required ISO timestamp, taken at **scrape** time — the Art. 14 clock starts there, not at approval |

`hs_marketable_status` is stripped from the plan automatically; it is read-only.


Everything here was verified against primary docs and cross-validated. **A guessed
property name is a silent 400 with no fuzzy suggestion.** Get names byte-exact.

Hardcode `/crm/v3/` and `/crm/v4/`. HubSpot is rolling out dated paths (`/2026-03/`) and
its own docs site now shows them as the lead example — but legacy semantic-version paths
are guaranteed to keep working indefinitely. **Do not copy a dated path out of an example.**

## Internal property names

### Company

| Field | Internal name | Notes |
|---|---|---|
| Name | `name` | one of name/domain required |
| Domain | `domain` | **bare root only** (`vr.is`) — strip scheme, `www.`, path. NOT unique-enforced |
| Additional domains | `hs_additional_domains` | semicolon-separated list |
| Website | `website` | full URL goes here, not in `domain` |
| Phone | `phone` | normalise to E.164 yourself |
| Street | `address` | `address2` for line 2 |
| City / Region / Postcode | `city` / `state` / `zip` | |
| Country | `country` | **string in some portals, enumeration in others** — read the live schema |
| Industry | `industry` | enum. Leave blank unless exact match |
| Employees / Revenue | `numberofemployees` / `annualrevenue` | bare digits — a comma or currency symbol 400s |
| Description | `description` | |
| Lifecycle / Lead status | `lifecyclestage` / `hs_lead_status` | enum, portal-customisable |
| Owner | `hubspot_owner_id` | |

### Contact

| Field | Internal name | Notes |
|---|---|---|
| First / Last | `firstname` / `lastname` | |
| Email | `email` | **hard-unique.** Drives the 409 |
| Job title | `jobtitle` | free text, not enum |
| Phone / Mobile | `phone` / `mobilephone` | separate properties |
| LinkedIn | `hs_linkedin_url` | **not** `linkedin_url` or `linkedinbio` — those aren't real |
| Owner | `hubspot_owner_id` | |
| Marketing status | `hs_marketable_status` | **read-only.** Readable on GET, never writable |

## Required fields

- **Company:** at least one of `name` or `domain`. No third fallback.
- **Contact:** at least one of `email`, `firstname`, `lastname` — a specific enumerated
  set, not "any property". A contact with only `jobtitle` 400s.

## Uniqueness — the asymmetry that shapes the design

- **Contact `email` is a true schema-level unique constraint.** Creating a duplicate
  returns **409 CONFLICT** with the existing record's ID in the body.
- **Company `domain` and `name` are NOT unique-constrained.** HubSpot's "primary unique
  identifier" language describes UI behaviour, not an enforced index. You can have 50
  companies with the same domain. Batch upsert with `idProperty: "domain"` fails outright:
  *"Unable to perform update/upsert by non-unique 0-2 property domain"*.

Therefore:

- **Contacts: create-and-catch-409**, then PATCH the returned ID. This beats
  search-then-create, which has a race condition and costs an extra call.
- **Companies: explicit search then create or PATCH.** No upsert.
- **Never batch-upsert contacts by email** — HubSpot documents that *partial* upserts are
  unsupported when `email` is the `idProperty`, so field-preserving behaviour does not
  apply. Use search → diff → PATCH.

## Dedupe search

`POST /crm/v3/objects/{objectType}/search`

Filters **within** a `filterGroups[].filters` array are ANDed; separate groups are ORed.
Limits: 5 groups × 10 filters, 25 total, `limit` max 200, hard ceiling 10,000 results.
Only one `sorts` rule.

**`EQ` is case-insensitive** on string properties — `EQ "VR.IS"` matches stored `vr.is`.
Two exceptions: enum properties are case-**sensitive**, and the `IN` operator requires
pre-lowercased values (silent zero results otherwise).

### The `.is` tokenisation trap

`CONTAINS_TOKEN` is **token-based, not substring**. The value is tokenised by splitting on
**any non-alphanumeric character** — including the dot.

So `CONTAINS_TOKEN "vr.is"` becomes a query over tokens `vr` and `is`. **Every Icelandic
domain ends in `.is`**, so this matches across the whole portal. Use `EQ` on the
normalised bare domain.

The same applies to multi-word company names: `"Arion banki hf."` tokenises to
`arion`/`banki`/`hf`, and `CONTAINS_TOKEN "banki"` matches every bank in a finance-heavy
market. Strip suffixes (`hf.`, `ehf.`, `sf.`) and prefer exact `EQ` on the full name.

Whether Icelandic letters tokenise and case-fold correctly is **undocumented** — do not
rely on `CONTAINS_TOKEN` for accented name matching without testing against the portal.

### Key hierarchy

1. `EQ` on normalised bare `domain` → high confidence, may pre-select
2. `hs_additional_domains` as a second OR'd group → medium (indexing unconfirmed)
3. Exact `EQ` on `name` → medium-high, always show to user
4. `CONTAINS_TOKEN` on the most distinctive name word → low, **never** auto-selected

Handle `results.length > 1` as its own reviewable case, not a binary.

### Search caveats

- **~5 req/s, hard ceiling, no paid increase.** Separate from the general limit.
- **Search responses omit the rate-limit headers** other endpoints return. You cannot
  self-throttle by reading them — use a client-side token bucket.
- **Eventual consistency**: a just-created record may not appear. Use the ID from the
  create response, never a confirming search.
- **Archived records are excluded** — you may recreate something a human deliberately
  archived.

## Fill-only-empty

The load-bearing fact: **a property you explicitly request is always present in the
response** — with its value or as `null`. It is never silently absent. Code branching on
`"field" not in properties` never fires and treats every field as populated, silently
defeating the whole feature.

```
1. GET with properties=[every field the skill might write]
2. For each field F with a new value:
     current = response.properties[F]
     if current is null or current === "":   → stage F
     else:                                    → skip, record "kept: <current>"
3. PATCH only staged fields (PATCH is inherently partial)
4. Report {field, previous, new, action: filled|kept}
```

Treat **both `null` and `""` as empty.** HubSpot uses `null` for never-set and `""` after
an explicit clear; there is no API signal distinguishing them. The rule is about not
clobbering a *value*, and a cleared field has none.

## Associations

Three separate calls: create company → create contact → associate. Not inline. The
approval gate means both IDs are known, so bundling only entangles failure modes and
removes the clean retry point.

**Read existing associations first:**
`GET /crm/v4/objects/contacts/{contactId}/associations/companies`

```json
{"results":[{"toObjectId":5790939450,
  "associationTypes":[{"category":"HUBSPOT_DEFINED","typeId":1,"label":"Primary"}]}]}
```

`toObjectId` comes back as a **number**; compare as strings.

**If any association to the target company already exists, skip the write entirely.** A v4
association PUT takes an array of labels and **replaces** the full label set on that edge
— sending `279` intending to *add* can silently **strip** an existing `Primary` label.

| typeId | Meaning |
|---|---|
| **1** | Contact → Company, **Primary** ← use this |
| 279 | Contact → Company, unlabeled |
| 2 | Company → Contact, Primary |
| 280 | Company → Contact, unlabeled |
| 930 / 931 | Billing contact — exists, not used here |

Labeled: `PUT /crm/v4/objects/contacts/{id}/associations/companies/{id}` with
`[{"associationCategory":"HUBSPOT_DEFINED","associationTypeId":1}]`

A bare `279` leaves the contact associated but not primary, which can render with no
company chip in some views.

## Error taxonomy

| HTTP | Category | Trigger |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Unknown property (`PROPERTY_DOESNT_EXIST`), bad enum, wrong type, company with neither name nor domain |
| 401 | auth | Missing/malformed/revoked token |
| 403 | `MISSING_SCOPES` | Body's `errors[].context.requiredScopes` names exactly what's missing |
| 409 | `CONFLICT` | Duplicate contact email. **Body carries the existing record ID** |
| 429 | rate limit | `Retry-After` header |

`READ_ONLY_VALUE` is the code for attempting `hs_marketable_status`.

**`Retry-After` is in seconds** for direct REST calls. The "milliseconds" claim circulating
in community threads is real but scoped to the *Workflows* retry subsystem — a different
code path. Parse as an integer and sanity-check: a value over 3600 is almost certainly
milliseconds regardless.

Batch endpoints return **207 Multi-Status** — check per-row status even on a 2xx outer
code. A batch upsert can return an outer 409 while some rows succeeded; always send a
per-input `objectWriteTraceId` so rows can be reconciled. Naive whole-batch retry creates
duplicates.

## Rate limits (private apps)

| Tier | Per 10s | Daily |
|---|---|---|
| Free / Starter | 100 | 250,000 |
| Professional | 190 | 625,000 |
| Enterprise | 190 | 1,000,000 |
| + add-on (max 2) | 250 | +1,000,000 each |

Search is separate and stricter (~5/s, no increase available).

## Scopes

`crm.objects.companies.read` · `crm.objects.companies.write` ·
`crm.objects.contacts.read` · `crm.objects.contacts.write`

There is **no separate associations scope** — association permission rides on the write
scope of **both** object types being linked.

## Token introspection

`GET /oauth/v1/access-tokens/{token}` is for **OAuth tokens** and returns
*"The access token must have the correct format"* for a private-app token. Verified live.

For a private-app token use:

```
POST /oauth/v2/private-apps/get/access-token-info
{"tokenKey": "<token>"}
```

Returns `hubId` and the full `scopes` array. Verified against portal 48851469 (25 scopes).

Belt and braces: also make one cheap real read (`GET /crm/v3/properties/companies/industry`
— needed anyway for enum validation). A 401 or 403 there is definitive and uses only
confirmed error behaviour.

## Enums

`industry`, `lifecyclestage`, `hs_lead_status`, and possibly `country` are
portal-customisable. Values must match the option's **internal value** exactly —
case-sensitive, whitespace-trimmed. Since a Nov-2025 tightening, even invisible leading or
trailing whitespace 400s.

A bad enum **fails the entire single-object create**, not just that field. Fetch the live
list via `GET /crm/v3/properties/{objectType}/{propertyName}` or leave blank.

## HubSpot auto-enriches after you create — and it gets Iceland wrong

**Observed live, portal 48851469.** A company created via API with only
`name, domain, website, phone, address, zip, city, country` came back minutes later with
these fields populated by HubSpot's own enrichment, none of them written by the caller:

| Field | Auto-filled value | Reality |
|---|---|---|
| `state` | `Illinois` | Iceland has no states. Nonsense |
| `industry` | `COMPUTER_NETWORKING` | The company is a doctors' professional association |
| `description` | Text in garbled Danish/Norwegian | The company is Icelandic |
| `numberofemployees` | `2` | Its own staff page lists 11 |
| `lifecyclestage` | `lead` | Not set by the caller |

Two consequences, both load-bearing:

1. **It poisons fill-only-empty.** On a later run those fields are no longer empty, so the
   skill correctly refuses to fix them — and the garbage persists. Fill-empty is the right
   policy; this is a known cost of it.
2. **`state` must be treated as hostile for Icelandic records.** Iceland has no
   state/region in its postal format. Never write `state`, and **flag it in the review
   table if HubSpot has populated it**, because a US state on an Icelandic company will
   silently corrupt any territory routing built on that field.

**Required behaviour: after a create, re-read the record and report every field HubSpot
populated that the caller did not write.** Present it as "HubSpot auto-filled these —
review, they are frequently wrong for non-US companies." Do not silently accept it, and do
not attempt to clean it without the user's say-so — that would be an overwrite.

## Rollback — asymmetric, and worse than it looks

| When | Recovery |
|---|---|
| Before association written | Archive ≈ clean undo |
| After association, before any merge | 90-day recycle bin, but restore is documented to **lose some associated data** (HubSpot does not enumerate which) |
| After any merge | **None.** Merges are permanently irreversible |

Merges also cap at 250 combined per record for life, run two at a time, and the primary
record's non-empty values always win.

**Never trigger a merge from this skill.** HubSpot's own duplicate management only *flags*,
never auto-merges, runs on a schedule, and sits behind an Operations Hub tier — so it is
not a safety net you can assume exists.

Write a JSONL audit line per run: timestamp, record IDs created, source URLs, approver,
skill version. It is the only durable record of what a run did.
