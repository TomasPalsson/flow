# Claude model IDs: classify before you rename

Loaded by the "Claude model IDs" steps in SKILL.md. The catalog of live, legacy, deprecated and
retired IDs is read fresh each audit (Bedrock CLI or the Models Overview page); a copy kept here
would go stale, which is the failure this section exists to catch.

## Getting the catalog

```bash
# Bedrock IDs with lifecycle status (ACTIVE or LEGACY), so legacy models are not read as current
aws bedrock list-foundation-models --region us-east-1 --by-provider anthropic \
  --query 'modelSummaries[].[modelId,modelLifecycle.status]' --output text > catalog.txt
```

First-party IDs and every status come from the Models Overview page (WebFetch it). Append one line
per non-current model to the same file: `claude-3-5-sonnet-20241022 retired 2025-10-28`, or
`... deprecated 2026-04-19`, or `... legacy`. A plain ID counts as current. Then run
`node scripts/model-ids.mjs <repo> --catalog catalog.txt`.

Bedrock IDs match on the base name, so `us.anthropic.claude-sonnet-4-5-20250929-v1:0` and
`claude-sonnet-4-5-20250929` are the same model; a different `-vN:M` than the catalog lists is `unknown`. An ID the catalog does not list is `unknown`:
usually a mistyped snapshot date, sometimes a model the account cannot see. Check before renaming.

## The four buckets

| Bucket | Looks like | Action |
|---|---|---|
| caller | `model=` / `modelId:` in a request, SDK client calls | swap the ID and apply the breaking-change checklist for the target model |
| definer | model registries, routing or queue configs, pricing tables, generated catalogs | keep the old entry (the model is still served); add the new one alongside; ask before retiring |
| opaque | UI fallbacks, env defaults, test fixtures, label parsers, doc tables | usually swap after checking every parser, regex and substring match handles the new ID |
| suffixed | `-fast`, `-200k`, `-1m`, `[1m]` deployment or routing IDs | not public model IDs; do not assume a new equivalent exists; verify in the registry, else leave and flag |

Sub-cases inside opaque:

- **Capability gate** (`if 'sonnet-4-5' in model:` turns a feature on): add the new ID alongside.
  The old model is still served and still has the capability; replacing would silently switch the
  feature off for any traffic still on it. The scanner prints these as `gate add-alongside`.
- **Registry-assert test** (a test listing several model versions): add an assertion for the new
  model and keep the old one.
- **Frozen or generated snapshot**: regenerate it, never hand-edit.
- **Coupled to a definer** (a test whose authorization or tier comes from a seed list): confirm the
  definer has the new model first; do not skip the test.

If the user did not name a scope, count references per directory before editing and ask which to
migrate; an unscoped rename of a model ID touches definers that must stay.

Credit: adapted from anthropics/skills skills/claude-api/shared/model-migration.md @ dbd4588 (Apache-2.0).
Credit: adapted from anthropics/skills skills/claude-api/shared/models.md @ dbd4588 (Apache-2.0).
