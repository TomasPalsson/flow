# Version claims in this skill

Every version-sensitive claim in the mcp-server skill, one row each. A row fails the ledger lint
(`plugins/flow/scripts/version-ledger-lint`) when its anchor text is no longer in the cited file or
when it has no re-verify command. The anchor is exact text, not a line number, so edits elsewhere in
the file do not break a row. When you change a claim, change its anchor and its Verified date.

| Claim | File | Anchor | Verified | Re-verify |
|---|---|---|---|---|
| Inspector CLI form `--cli <target> --method tools/list` | hygiene.md | `npx @modelcontextprotocol/inspector --cli node build/server.js --method tools/list` | 2026-10-11 | `npx -y @modelcontextprotocol/inspector --cli --help \| grep -e --method` |
| SDK Express helper defaults to loopback, Host check takes exact hostnames | hygiene.md | `exact hostnames without ports` | 2026-10-11 | `d=$(mktemp -d) && cd "$d" && npm pack @modelcontextprotocol/sdk --silent && tar xzf modelcontextprotocol-sdk-*.tgz && grep -n allowedHosts package/dist/esm/server/express.d.ts` |
| Claude Code supports elicitation since 2.1.76 | hygiene.md | `Claude Code since 2.1.76` | 2026-10-11 | `curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md \| sed -n '/^## 2.1.76/,/^## 2.1.75/p' \| grep -i elicitation` |
| Spec 2025-11-25 made CIMD preferred, DCR optional | auth.md | `Spec 2025-11-25 made CIMD preferred` | 2026-10-11 | `curl -sL https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization \| grep -i 'client id metadata'` |
| Claude's accepted auth types include oauth_cimd | auth.md | `oauth_cimd` | 2026-10-11 | `curl -sL https://claude.com/docs/connectors/building/authentication \| grep -o -i 'oauth_cimd' \| head -1` |
| Claude OAuth callback URL | auth.md | `https://claude.ai/api/mcp/auth_callback` | 2026-10-11 | `curl -sL https://claude.com/docs/connectors/building/authentication \| grep -o 'https://claude.ai/api/mcp/auth_callback' \| head -1` |
| ext-apps 1.x reached 1.7.5, 2.0.x needs core/client/server ^2 peers | apps.md | `the 1.x line reached 1.7.5` | 2026-10-11 | `npm view @modelcontextprotocol/ext-apps versions --json \| tail -6 && npm view @modelcontextprotocol/ext-apps peerDependencies --json` |
