# Auth for remote MCP servers

Auth is the usual reason a server must be remote: redirects, token storage and refresh all need
a hosted endpoint. Local stdio servers can run OAuth (browser, localhost redirect, OS keychain)
but it breaks headless and every user repeats it; lean remote when OAuth is required.

## What Claude's client accepts

Check the current list at https://claude.com/docs/connectors/building/authentication before
choosing, since a spec-valid flow Claude does not speak fails at connect time.

| Type | Notes |
|---|---|
| `oauth_cimd` | Supported and preferred. The host publishes client metadata at an HTTPS URL and uses that URL as its `client_id`; no registration endpoint, no stored client records. |
| `oauth_dcr` | Supported, backward-compat fallback. Registers a new client on every fresh connection, so it is heavy for high-volume use. |
| `oauth_anthropic_creds` | Partner gives `client_id`/`client_secret` to Anthropic; user-consent-gated. |
| `custom_connection` | User supplies URL and credentials at connect time. |
| `none` | Authless. |

Not supported: user-pasted bearer tokens, and a pure machine-to-machine `client_credentials` grant
with no user consent. Callback URL for all surfaces: `https://claude.ai/api/mcp/auth_callback`.

## Prefer CIMD over DCR

Spec 2025-11-25 made CIMD preferred and DCR optional. Client priority is pre-registered, then CIMD
(when the authorization server advertises `client_id_metadata_document_supported`), then DCR (when
it has a `registration_endpoint`), then prompt the user. Server duties for CIMD:

1. Serve authorization-server metadata (RFC 8414) at `/.well-known/oauth-authorization-server`
   with `client_id_metadata_document_supported: true`.
2. Serve protected-resource metadata that points at it.
3. At authorize time, fetch `client_id` as an HTTPS URL, validate the returned metadata, continue.
4. Validate the bearer token on every `/mcp` request.

Add DCR only for hosts that have not moved to CIMD.

## Audience check and no passthrough (both are spec MUSTs)

A valid signature is not enough. Validate that the token was minted for this server (RFC 8707
audience): a token issued for `api.other-service.com` is rejected even when the signature checks out.
Never accept a token and forward it upstream; exchange it, or call the upstream with the server's own
credentials. Test: send a token for a different audience and expect 401.

## Token storage

| Deployment | Store tokens in |
|---|---|
| Remote, stateless | nowhere, the host sends the bearer each request |
| Remote, stateful | a session store keyed by MCP session id |
| Local / packaged | the OS keychain (`keytar`, `keyring`), never a plaintext file |

Use the SDK's auth helpers (`mcpAuthRouter`, bearer middleware, proxy provider in
`@modelcontextprotocol/sdk/server/auth`) before writing your own; confirm the names against the
version you pin (see `versions.md`).

Credit: adapted from anthropics/claude-plugins-official plugins/mcp-server-dev/skills/build-mcp-server/references/auth.md @ a9fd216 (Apache-2.0).
