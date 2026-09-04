---
name: s3-patterns
description: S3 CLI patterns for debugging — bucket config, object exploration, access issues, common gotchas
---

# S3 Exploration Patterns

## Quick Reference

```bash
# Account overview
aws-explore s3 overview

# Single bucket deep dive
aws-explore s3 bucket <name>

# List objects in a prefix
aws-explore s3 objects <bucket> [prefix]

# Diagnose 403 errors
aws-explore s3 debug-403 <bucket> <key>
```

## Common Debugging Scenarios

### "Why is this 403?"

Run `aws-explore s3 debug-403 <bucket> <key>` first. If you need to dig deeper:

1. **Check caller identity** — are you using the right account/role?
2. **Public access block** — all 4 booleans true = fully locked down
3. **Bucket policy** — look for explicit Deny statements
4. **KMS encryption** — SSE-KMS requires `kms:Decrypt` permission on the key
5. **Object ownership** — `BucketOwnerEnforced` means ACLs are disabled (good)

### "Where are the files?"

Use the delimiter trick to explore folder structure without listing everything:

```bash
# Top-level "directories"
aws s3api list-objects-v2 --bucket BUCKET --delimiter / \
  --query '{Prefixes: CommonPrefixes[].Prefix, Count: KeyCount}' --no-cli-pager

# Drill into a prefix
aws s3api list-objects-v2 --bucket BUCKET --prefix "uploads/2024/" --delimiter / \
  --max-items 30 --query 'CommonPrefixes[].Prefix' --no-cli-pager
```

### "Why are objects disappearing?"

Check lifecycle rules and versioning:

```bash
aws s3api get-bucket-lifecycle-configuration --bucket BUCKET --no-cli-pager \
  --query 'Rules[].{ID: ID, Status: Status, ExpiresIn: (Expiration.Days || Expiration.Date || `none`)}'

aws s3api get-bucket-versioning --bucket BUCKET --no-cli-pager
```

### "What's the most recent object?"

```bash
aws s3api list-objects-v2 --bucket BUCKET --prefix "logs/" --max-items 100 --no-cli-pager \
  --query 'reverse(sort_by(Contents, &LastModified))[:5].{Key: Key, Size: Size, Date: LastModified}'
```

### "How big is this prefix?"

```bash
aws s3api list-objects-v2 --bucket BUCKET --prefix "data/" --no-cli-pager \
  --query '{Count: KeyCount, TotalBytes: sum(Contents[].Size), Truncated: IsTruncated}'
```

## Gotchas

- **`get-bucket-location` returns `null` for us-east-1** — use `--query 'LocationConstraint || \`us-east-1\`'`
- **`list-buckets` now includes `BucketRegion`** — skip the separate `get-bucket-location` call
- **Bucket policies are double-encoded JSON** — pipe through `jq .Policy | jq .` to read them, or use `jq '[.Statement[] | {Sid, Effect, Action}]'` for a summary
- **`list-objects-v2` auto-paginates** — always use `--max-items` on unknown buckets
- **Empty versioning response `{}` means never enabled** (not "disabled" — that's `Suspended`)
- **`NoSuchBucketPolicy` is not an error** — it means no policy exists (default state)

## Useful JMESPath Patterns

```bash
# Filter buckets by name pattern
--query 'Buckets[?contains(Name, `prod`)].Name'

# Find large objects (>10MB)
--query 'Contents[?Size > `10485760`].{Key: Key, SizeMB: Size}'

# Objects modified after a date
--query 'Contents[?LastModified >= `2024-01-01`].Key'

# Find Glacier objects
--query 'Contents[?StorageClass==`GLACIER`].{Key: Key, Size: Size}'

# Policy summary (requires jq)
aws s3api get-bucket-policy --bucket BUCKET --query Policy --output text --no-cli-pager \
  | jq '[.Statement[] | {Sid, Effect, Principal: (.Principal | if type == "string" then . else (.AWS // .Service // .) end), Action}]'
```

## Object Metadata

```bash
# Full metadata for a specific object
aws s3api head-object --bucket BUCKET --key "path/to/file" --no-cli-pager \
  --query '{Size: ContentLength, Type: ContentType, Encryption: ServerSideEncryption, Modified: LastModified, Storage: StorageClass}'

# Check replication status
aws s3api head-object --bucket BUCKET --key "path/to/file" --no-cli-pager \
  --query 'ReplicationStatus' --output text
```
