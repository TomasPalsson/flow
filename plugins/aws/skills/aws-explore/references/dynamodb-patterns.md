---
name: dynamodb-patterns
description: DynamoDB CLI patterns for debugging — schema discovery, querying, sample items, common gotchas
---

# DynamoDB Exploration Patterns

## Quick Reference

```bash
# All tables with schemas
aws-explore dynamodb overview

# Single table deep dive (schema + TTL + sample items)
aws-explore dynamodb table <name>

# Query by partition key (auto-detects key name/type)
aws-explore dynamodb query <table> <pk-value>

# Compact schema dump for multiple tables
aws-explore dynamodb schema [table1 table2 ...]
```

## Common Debugging Scenarios

### "What's the data model?"

Run `aws-explore dynamodb table <name>` — it shows key schema, GSIs, TTL, and 3 sample items.

For just the schema across multiple tables:
```bash
aws-explore dynamodb schema orders users sessions
```

### "Items are disappearing"

Check TTL — it's NOT in `describe-table`, requires a separate call:

```bash
aws dynamodb describe-time-to-live --table-name TABLE --no-cli-pager
```

If `TimeToLiveStatus: ENABLED`, check the TTL attribute on your items. DynamoDB deletes items when the epoch timestamp in that attribute is in the past.

### "Query is returning nothing"

1. Verify you're using the right key:
```bash
aws dynamodb describe-table --table-name TABLE --no-cli-pager \
  --query 'Table.{PK: KeySchema[?KeyType==`HASH`].AttributeName|[0], SK: KeySchema[?KeyType==`RANGE`].AttributeName|[0]}'
```

2. Check if you need a GSI instead:
```bash
aws dynamodb describe-table --table-name TABLE --no-cli-pager \
  --query 'Table.GlobalSecondaryIndexes[*].{Name: IndexName, PK: KeySchema[?KeyType==`HASH`].AttributeName|[0], SK: KeySchema[?KeyType==`RANGE`].AttributeName|[0]}'
```

3. Sample items to see actual key values:
```bash
aws dynamodb scan --table-name TABLE --limit 3 --query 'Items' --no-cli-pager
```

### "Is the table throttling?"

```bash
aws dynamodb describe-table --table-name TABLE --no-cli-pager \
  --query 'Table.{Billing: BillingModeSummary.BillingMode, RCU: ProvisionedThroughput.ReadCapacityUnits, WCU: ProvisionedThroughput.WriteCapacityUnits}'
```

If `PAY_PER_REQUEST`, throttling is unlikely (on-demand scales). If `PROVISIONED`, check CloudWatch for `ThrottledRequests`.

### "What access patterns are available?"

```bash
# Shows base table + all GSI/LSI key schemas
aws dynamodb describe-table --table-name TABLE --no-cli-pager \
  --query '{
    BaseTable: Table.KeySchema,
    GSIs: Table.GlobalSecondaryIndexes[*].{Name: IndexName, Keys: KeySchema, Projection: Projection.ProjectionType},
    LSIs: Table.LocalSecondaryIndexes[*].{Name: IndexName, Keys: KeySchema, Projection: Projection.ProjectionType}
  }'
```

## Querying

### By partition key

```bash
aws dynamodb query --table-name TABLE --no-cli-pager \
  --key-condition-expression "pk = :pk" \
  --expression-attribute-values '{":pk": {"S": "USER#123"}}' \
  --limit 5 --query 'Items'
```

### By partition + sort key range

```bash
aws dynamodb query --table-name TABLE --no-cli-pager \
  --key-condition-expression "pk = :pk AND sk BETWEEN :start AND :end" \
  --expression-attribute-values '{
    ":pk": {"S": "ORDER#456"},
    ":start": {"S": "2024-01-01"},
    ":end": {"S": "2024-12-31"}
  }' --limit 10 --query 'Items'
```

### Most recent items (reverse sort)

```bash
aws dynamodb query --table-name TABLE --no-cli-pager \
  --key-condition-expression "pk = :pk" \
  --expression-attribute-values '{":pk": {"S": "USER#123"}}' \
  --no-scan-index-forward --limit 5 --query 'Items'
```

### Query a GSI

```bash
aws dynamodb query --table-name TABLE --index-name email-index --no-cli-pager \
  --key-condition-expression "email = :email" \
  --expression-attribute-values '{":email": {"S": "user@example.com"}}' \
  --limit 5 --query 'Items'
```

### Count items for a key (no data returned)

```bash
aws dynamodb query --table-name TABLE --no-cli-pager \
  --key-condition-expression "pk = :pk" \
  --expression-attribute-values '{":pk": {"S": "USER#123"}}' \
  --select COUNT --query 'Count' --output text
```

## Gotchas

- **`--limit` vs `--max-items`**: `--limit` stops server-side (preferred for sampling). `--max-items` truncates client-side after potentially reading more.
- **TTL is a separate API call** — `describe-table` doesn't include it
- **`ItemCount` is approximate** — updated every ~6 hours, not real-time
- **DynamoDB uses typed JSON** — values are `{"S": "string"}`, `{"N": "123"}`, `{"BOOL": true}`, `{"L": [...]}`, `{"M": {...}}`
- **Numbers are strings in the wire format** — `{"N": "42"}` not `{"N": 42}`
- **Reserved words need `--expression-attribute-names`** — e.g., `#n` for `name`, `#s` for `status`, `#t` for `type`
- **Scanning a GSI might return nothing** — partition distribution can be uneven; use query if you know a key value

## DynamoDB Type Reference

| Descriptor | Type | Example |
|---|---|---|
| `S` | String | `{"name": {"S": "Alice"}}` |
| `N` | Number (as string) | `{"age": {"N": "30"}}` |
| `B` | Binary (base64) | `{"data": {"B": "dGVzdA=="}}` |
| `BOOL` | Boolean | `{"active": {"BOOL": true}}` |
| `NULL` | Null | `{"deleted": {"NULL": true}}` |
| `L` | List | `{"tags": {"L": [{"S": "a"}]}}` |
| `M` | Map | `{"meta": {"M": {"k": {"S": "v"}}}}` |
| `SS` | String Set | `{"roles": {"SS": ["admin"]}}` |
| `NS` | Number Set | `{"ids": {"NS": ["1", "2"]}}` |
