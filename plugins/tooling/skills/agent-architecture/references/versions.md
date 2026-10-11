# Version claims in agent-architecture references

Version-sensitive claims that rot silently, one row each. A row fails the ledger lint
(`plugins/flow/scripts/version-ledger-lint`) when its anchor text is gone from the cited file or when
it has no re-verify command. Anchors are exact text, never line numbers, so unrelated edits do not
break a row. File paths are relative to this directory. When a claim changes, change its anchor and
its Verified date together. A claim you could not confirm stays out of the table until you can.

| Claim | File | Anchor | Verified | Re-verify |
|---|---|---|---|---|
| Per-model minimum cacheable tokens (Haiku 4.5 and Opus 4.5/4.6 need 4,096) | token-economics.md | `4,096 (Opus 4.5/4.6, Haiku 4.5)` | 2026-10-11 | `curl -sL https://platform.claude.com/docs/en/build-with-claude/prompt-caching \| grep -o -m1 '4,096 tokens for Claude Haiku 4.5'` |
| Regex tool-search tool type string | tool-design.md | `tool_search_tool_regex_20251119` | 2026-10-11 | `curl -sL https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool \| grep -o -m1 'tool_search_tool_regex_[0-9]*'` |
| AgentCore A2A containers listen on port 9000 at the root path | multi-agent.md | `A2A \| 9000` | 2026-10-11 | `curl -sL https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-a2a.html \| grep -o -m1 '9000'` |
| AgentCore MCP containers listen on 0.0.0.0:8000/mcp | multi-agent.md | `MCP \| 8000` | 2026-10-11 | `curl -sL https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp.html \| grep -o -m1 '0.0.0.0:8000'` |
