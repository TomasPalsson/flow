# MCP apps (widgets)

A widget is an HTML view a tool returns, rendered in a sandboxed iframe by the host. Reach for it
only when elicitation (a short flat form) cannot do the job. Build and test the text content first:
a host without the apps surface still shows only that.

## Version pin

The upstream skill pins `@modelcontextprotocol/ext-apps@1.2.2` for its CDN snippet. That pin is old:
the 1.x line reached 1.7.5, and 2.0.x needs `@modelcontextprotocol/core`, `client` and `server`
at ^2 as peers. Match what the project already installs (user repos use ^1.7.4) and re-check with the
commands in `versions.md` before copying any pin.

## Payload budget

Hosts cap a tool result's size; past the cap the host swaps in a file-pointer string and the widget
fails with a JSON parse error on `content[0].text`. The Inspector has no cap, so it hides this.
Cap your own payload near 130 KB and degrade in order:

1. Ship full rows while `JSON.stringify(rows).length` is under the cap.
2. Prune columns to those the render spec references, counting both `field:` keys and `datum.X`
   references inside expressions (an aliased column appears only as `datum.X`).
3. Truncate rows last and include `{ truncated: N }` so the widget can say so.

Send heavy assets through `callServerTool`, not the result.

## Instances persist

Each call mounts a new iframe; earlier ones stay in the transcript, so a click on a stale widget can
send a message after a newer one rendered. Detect supersession with a `BroadcastChannel`, mark older
instances inert, and guard outbound calls:

```js
let superseded = false; const seq = Date.now() + Math.random();
const bc = new BroadcastChannel("my-widget");
bc.onmessage = (e) => { if (e.data?.seq > seq) superseded = true; };
bc.postMessage({ seq });
const safeSend = (m) => { if (!superseded) app.sendMessage(m); };
```

## Inlining the bundle

When substituting a bundle into HTML with `String.replace`, pass a replacer function
(`() => bundle`), because a bare string treats `$...` sequences in the minified code as patterns.

Credit: adapted from anthropics/claude-plugins-official plugins/mcp-server-dev/skills/build-mcp-app/references/payload-budgeting.md @ a9fd216 (Apache-2.0).
