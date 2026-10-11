# Version claims in the strands-agentcore skill

Version-sensitive claims in SKILL.md and its references, one row each. A row fails the ledger lint
(`plugins/flow/scripts/version-ledger-lint`) when its anchor text is gone from the cited file or when
it has no re-verify command. Anchors are exact text, never line numbers. File paths are relative to
this directory. Change a claim, then change its anchor and its Verified date.

Not listed on purpose: the Claude Opus 4.5 row in SKILL.md's model table. Its ID did not match the live
Bedrock catalog when this ledger was written (the catalog lists `anthropic.claude-opus-4-5-20251101-v1:0`),
so it has no verified row until the SKILL.md text is corrected.

| Claim | File | Anchor | Verified | Re-verify |
|---|---|---|---|---|
| Claude Sonnet 4.5 Bedrock model ID | ../SKILL.md | `anthropic.claude-sonnet-4-5-20250929-v1:0` | 2026-10-11 | `aws bedrock list-foundation-models --region us-east-1 --by-provider anthropic --query 'modelSummaries[].modelId' --output text \| tr '\t' '\n' \| grep -x 'anthropic.claude-sonnet-4-5-20250929-v1:0'` |
| Claude Haiku 4.5 Bedrock model ID | ../SKILL.md | `anthropic.claude-haiku-4-5-20251001-v1:0` | 2026-10-11 | `aws bedrock list-foundation-models --region us-east-1 --by-provider anthropic --query 'modelSummaries[].modelId' --output text \| tr '\t' '\n' \| grep -x 'anthropic.claude-haiku-4-5-20251001-v1:0'` |
| AgentCore containers must be linux/arm64 | ../SKILL.md | `ARM64 required` | 2026-10-11 | `curl -sL https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/getting-started-custom.html \| grep -o -i -m1 'arm64'` |
| MCP servers use streamable-http transport | ../SKILL.md | `streamable-http` | 2026-10-11 | `curl -sL https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp.html \| grep -o -i -m1 'streamable'` |
| strands-agents minimum pin in the Dockerfile requirements | deployment.md | `strands-agents>=1.16.0` | 2026-10-11 | `pip index versions strands-agents \| head -1` |
| bedrock-agentcore minimum pin in the Dockerfile requirements | deployment.md | `bedrock-agentcore>=1.0.6` | 2026-10-11 | `pip index versions bedrock-agentcore \| head -1` |
