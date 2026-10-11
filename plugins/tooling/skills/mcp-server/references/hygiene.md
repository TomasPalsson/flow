# Server hygiene

## stdout belongs to the protocol (stdio transport)

A stdio server talks JSON-RPC over stdout. Any other byte there, a `print`, a
`console.log`, a library banner, corrupts the stream.

- Log to stderr: `console.error(...)` in Node, `logging` with `stream=sys.stderr` or
  `print(..., file=sys.stderr)` in Python.
- Find offenders: `grep -rnE 'console\.log|^\s*print\(' src/` and read each hit.
- Check from outside: run the server alone and pipe its stdout through `jq -c .`. Every line
  must parse; a line that does not is the leak.

## Bind address and Origin

A local HTTP server is reachable from any web page in the user's browser unless it checks who is
asking (DNS rebinding). Two checks, both required:

1. **Host header** against an allowlist of hostnames.
2. **Origin header** against an allowlist, when present. Browsers send it on cross-origin and
   POST requests (not always on same-origin GETs); most non-browser clients do not, so absent is allowed and a mismatch is a 403.

| Situation | Bind | Required |
|---|---|---|
| Default, only this machine | `127.0.0.1` | Host + Origin allowlist (`localhost`, `127.0.0.1`, `[::1]`) |
| Dev server the user reaches as `*.pc:<port>` from other machines | `0.0.0.0` | Host + Origin allowlist that includes the `.pc` names, plus auth |
| Public or shared | behind a proxy | Auth per `auth.md`, TLS at the proxy |

The user's dev-server default (bind `0.0.0.0`, allow the `.pc` host) is fine for UI dev servers.
An MCP server differs because its tools may run commands, so the LAN case adds auth: anyone on
the network can otherwise call every tool. Use a bearer check even for a throwaway LAN server.

TypeScript SDK facts (checked against `@modelcontextprotocol/sdk` 1.32.1):
`createMcpExpressApp({ host })` defaults to `127.0.0.1` and turns Host validation on for loopback
hosts; with `host: '0.0.0.0'` it adds none unless you pass `allowedHosts`. `allowedHosts` takes
exact hostnames without ports, so `*.pc` is not expressible: list each machine name, or write a
small middleware that accepts a hostname ending in `.pc`. The SDK validates Host only; write the
Origin check yourself.

```ts
app.use((req, res, next) => {
  const origin = req.headers.origin;
  let host = null;
  try { host = origin ? new URL(origin).hostname : null; } catch { /* "null" or malformed */ }
  if (origin && !(host && allowedOrigins.has(host))) return res.status(403).end();
  next();
});
```

## Elicitation, with a fallback

Elicitation lets a tool pause and ask the user for a few flat fields (a confirmation, a pick from
an enum). Use it before reaching for a widget. Host support is recent (Claude Code since 2.1.76);
the SDK throws `CapabilityNotSupported` when the client does not advertise it, so check first.

```ts
if (server.getClientCapabilities()?.elicitation) {
  const r = await server.elicitInput({ mode: "form", message: "Delete all items?",
    requestedSchema: { type: "object", properties: { confirm: { type: "boolean" } }, required: ["confirm"] } });
  if (r.action === "accept" && r.content?.confirm) return doDelete();
  return text("Cancelled.");
}
return text("Confirmation required. Ask the user to confirm deletion, then call again with confirm=true.");
```

- Flat objects, primitives and enums only; string formats limited to email, uri, date, date-time.
- Three outcomes: `accept` (content present), `decline` (user said no), `cancel` (dismissed).
- Never ask for passwords, API keys or tokens this way; those go through OAuth or sensitive config.
- When the data needs nesting, long lists or a preview, that is the signal to use a widget.

## Smoke test with the Inspector CLI

Run after every change to registration or transport. No UI needed:

```bash
npx @modelcontextprotocol/inspector --cli node build/server.js --method tools/list
npx @modelcontextprotocol/inspector --cli http://localhost:3000/mcp --method tools/list
npx @modelcontextprotocol/inspector --cli http://localhost:3000/mcp --method tools/call --tool-name echo --tool-arg text=hi
```

Pass means: the list shows every registered tool, and a call returns its result. For a remote
server add `--header "Authorization: Bearer <token>"` and also run one call with no header; it
must fail. The Inspector has no payload cap, so a widget that works here can still break in a host
(see `apps.md`).

Credit: adapted from anthropics/claude-plugins-official plugins/mcp-server-dev/skills/build-mcp-server/references/elicitation.md @ a9fd216 (Apache-2.0).
Credit: adapted from anthropics/skills skills/mcp-builder/reference/mcp_best_practices.md @ dbd4588 (Apache-2.0).
