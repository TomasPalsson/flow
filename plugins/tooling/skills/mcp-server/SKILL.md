---
name: mcp-server
description: >-
  Build or audit an MCP server's construction: stdio logging hygiene, bind address
  and Origin/Host validation, Claude auth (CIMD over DCR, audience check, no token
  passthrough), elicitation with a fallback, Inspector CLI smoke tests, MCP apps
  (ext-apps widgets) and local-server security. Use when writing, reviewing or
  debugging an MCP server in TypeScript or Python, "my MCP server prints garbage /
  breaks the client", "add OAuth to my MCP server", "make the server reachable on
  the LAN", or "test an MCP server". Not for tool schemas, annotations or result
  shapes (use tooling:agent-architecture, its tool-design reference) and not for
  AgentCore deploy target or transport choice (use aws:strands-agentcore).
---

# MCP server construction

Tool contracts (names, annotations, `confirmation_required`, `isError`) live in
[`../agent-architecture/references/tool-design.md`](../agent-architecture/references/tool-design.md).
Deploying on AgentCore (MCP containers listen on 0.0.0.0:8000/mcp, ARM64, `streamable-http`) lives in
[`../../../aws/skills/strands-agentcore/SKILL.md`](../../../aws/skills/strands-agentcore/SKILL.md).
This skill covers what neither says: how the server process itself behaves.

## Steps

1. Pick the transport: stdio for a local subprocess, Streamable HTTP for anything
   remote or shared. Then read [`references/hygiene.md`](references/hygiene.md) in full:
   logging to stderr on stdio, the bind address, Origin and Host validation, the
   elicitation fallback and the Inspector smoke test. Done when the server passes the
   smoke test in that file.
2. Remote server with users? Read [`references/auth.md`](references/auth.md) before writing any
   auth code. Done when a token minted for another audience is rejected.
3. Local server that touches files or runs commands? Read
   [`references/local-security.md`](references/local-security.md). Done when its checklist is ticked.
4. Server returns widgets (MCP apps)? Read [`references/apps.md`](references/apps.md). Done when the
   tool's text content still reads sensibly in a host without the apps surface.
5. Pinning `@modelcontextprotocol/*` packages or a spec date? Check
   [`references/versions.md`](references/versions.md) first and run its re-verify commands; the ledger
   is linted by `flow`'s `version-ledger-lint`, so a rewritten claim must update its row.

## Rules that save the most time

- Nothing but protocol frames goes to stdout on a stdio server. One stray `print` corrupts the
  JSON-RPC stream and the client reports a parse error far from the cause.
- A server that can run commands or write files is reachable by whoever can reach its port.
  Binding wider than loopback needs an Origin/Host allowlist and auth together.
- Claude's client supports a fixed set of auth types; a spec-valid flow that Claude does not
  speak fails at connect time. Check the table in `references/auth.md`.
- Elicitation throws when the client lacks the capability. Check, then fall back to a text
  result that asks the model to relay the question.

Credit: adapted from anthropics/claude-plugins-official plugins/mcp-server-dev/skills/build-mcp-server/SKILL.md @ a9fd216 (Apache-2.0).
