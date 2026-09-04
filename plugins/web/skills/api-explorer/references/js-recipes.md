---
name: js-recipes
description: JavaScript evaluation snippets and initScript interceptors for API discovery using Chrome DevTools MCP. Contains the fetch/XHR interceptor, WebSocket monitor, framework-specific extraction patterns, and utility scripts.
---

# JS Recipes for API Discovery

## The Fetch/XHR Interceptor (use with initScript)

This is the canonical interceptor. Pass it as the `initScript` parameter to `navigate_page` to capture ALL fetch/XHR calls, including those made during framework initialization (before DOMContentLoaded).

```javascript
window.__capturedRequests = [];
const _origFetch = window.fetch;
window.fetch = async function(input, init) {
  const url = typeof input === 'string' ? input : input.url;
  const method = (init?.method || 'GET').toUpperCase();
  const headers = Object.fromEntries(new Headers(init?.headers || {}).entries());
  const start = Date.now();
  try {
    const response = await _origFetch.apply(this, arguments);
    const clone = response.clone();
    let body = null;
    try {
      const text = await clone.text();
      body = text.length < 2000 ? text : '[truncated: ' + text.length + ' chars]';
    } catch(e) {}
    window.__capturedRequests.push({
      type: 'fetch', url, method, status: response.status,
      requestHeaders: headers, responseHeaders: Object.fromEntries(response.headers.entries()),
      duration: Date.now() - start, body
    });
    return response;
  } catch(err) {
    window.__capturedRequests.push({ type: 'fetch', url, method, error: err.message });
    throw err;
  }
};
const _origXHROpen = XMLHttpRequest.prototype.open;
XMLHttpRequest.prototype.open = function(method, url) {
  this.__url = url; this.__method = method;
  return _origXHROpen.apply(this, arguments);
};
const _origXHRSend = XMLHttpRequest.prototype.send;
XMLHttpRequest.prototype.send = function(body) {
  const self = this;
  this.addEventListener('load', function() {
    window.__capturedRequests.push({
      type: 'xhr', url: self.__url, method: self.__method,
      status: self.status, body: self.responseText?.slice(0, 2000)
    });
  });
  return _origXHRSend.apply(this, arguments);
};
```

**Retrieve captured requests after navigation:**
```javascript
() => window.__capturedRequests
```

**Critical limitation:** `initScript` only fires on the navigation it's attached to. SPA client-side navigations via `pushState` do NOT re-run it. However, the fetch/XHR monkey-patches persist since they mutate `window.fetch` in place. New iframes or workers do NOT get the interceptor.

---

## WebSocket Monitor (use with initScript)

Inject alongside the fetch interceptor to capture WebSocket messages:

```javascript
window.__wsMessages = [];
const _origWS = window.WebSocket;
window.WebSocket = function(url, protocols) {
  const ws = new _origWS(url, protocols);
  const meta = { url, protocols, messages: [] };
  window.__wsMessages.push(meta);
  ws.addEventListener('message', function(e) {
    const data = typeof e.data === 'string' ? e.data.slice(0, 1000) : '[binary: ' + e.data.byteLength + ' bytes]';
    meta.messages.push({ dir: 'in', data, ts: Date.now() });
  });
  const _origSend = ws.send.bind(ws);
  ws.send = function(data) {
    const captured = typeof data === 'string' ? data.slice(0, 1000) : '[binary]';
    meta.messages.push({ dir: 'out', data: captured, ts: Date.now() });
    return _origSend(data);
  };
  return ws;
};
```

**Retrieve WebSocket messages:**
```javascript
() => window.__wsMessages.map(ws => ({
  url: ws.url, protocols: ws.protocols,
  messageCount: ws.messages.length,
  sample: ws.messages.slice(0, 10)
}))
```

**WebSocket protocol fingerprinting (run after capturing messages):**

| First Message Pattern | Protocol |
|----------------------|----------|
| `{"topic":"...", "event":"...", "payload":{}}` | Phoenix Channels |
| `{"type":"...", "identifier":"...", "message":{}}` | ActionCable (Rails) |
| `0{"sid":"..."}` or `42["event", data]` | Socket.io (Engine.io framing) |
| `{"type":"connection_init"}` | graphql-ws |
| `CONNECT\n` frame format | STOMP |

---

## Framework-Specific Extraction

### Next.js — Full Hydration Data
```javascript
() => {
  const d = window.__NEXT_DATA__;
  if (!d) return null;
  return {
    buildId: d.buildId,
    runtimeConfig: d.runtimeConfig,
    pageProps: d.props?.pageProps,
    query: d.query,
    page: d.page,
    assetPrefix: d.assetPrefix
  };
}
```

### Nuxt.js — State and Async Data
```javascript
() => window.__NUXT__ || null
```

### Generic API Base URL Discovery
```javascript
() => {
  const found = {};
  ['__ENV__','__CONFIG__','__APP_CONFIG__','APP_CONFIG','config','ENV','__RUNTIME_CONFIG__']
    .forEach(k => { if (window[k]) found[k] = window[k]; });
  document.querySelectorAll('meta[name*="api"], meta[name*="endpoint"], meta[property*="api"]')
    .forEach(m => { found[m.name || m.getAttribute('property')] = m.content; });
  document.querySelectorAll('script[type="application/json"], script[id*="config"], script[id*="env"]')
    .forEach(s => { try { found[s.id || 'json-script'] = JSON.parse(s.textContent); } catch(e) {} });
  return found;
}
```

### Apollo GraphQL Cache Inspection
```javascript
() => {
  const client = window.__APOLLO_CLIENT__;
  if (!client) return { found: false };
  return {
    cacheKeys: client.cache?.data?.data ? Object.keys(client.cache.data.data).slice(0, 30) : null,
    activeQueries: client.queryManager ? Object.keys(client.queryManager.queries || {}).length : null,
    linkType: client.link?.constructor?.name
  };
}
```

### Service Worker Check
```javascript
async () => {
  const regs = await navigator.serviceWorker.getRegistrations();
  return regs.map(r => ({
    scope: r.scope,
    scriptURL: r.active?.scriptURL,
    state: r.active?.state
  }));
}
```

If a service worker is registered, DevTools shows what the app sent to the SW, not what the SW sent to the network. Headers may have been modified.

### Performance Entries — API Timing
```javascript
() => performance.getEntriesByType('resource')
  .filter(e => e.initiatorType === 'fetch' || e.initiatorType === 'xmlhttprequest')
  .map(e => ({ url: e.name, duration: Math.round(e.duration), size: e.transferSize }))
  .sort((a, b) => b.duration - a.duration)
  .slice(0, 20)
```

Useful for identifying the slowest (often most data-rich) API endpoints.

---

## GraphQL Bundle Mining (when introspection is disabled)

When introspection returns `PersistedQueryNotFound` or is disabled, extract GraphQL operations from JS bundles:

```javascript
async () => {
  // Get all loaded script URLs
  const scripts = [...document.querySelectorAll('script[src]')].map(s => s.src);
  const results = { operations: [], apiEndpoints: [], persistedHashes: [] };

  for (const src of scripts.slice(0, 15)) { // limit to 15 largest chunks
    try {
      const text = await (await fetch(src)).text();

      // Find GraphQL operation names (query X { or mutation X {)
      const opMatches = text.matchAll(/(?:query|mutation|subscription)\s+(\w+)\s*[\(\{]/g);
      for (const m of opMatches) results.operations.push(m[1]);

      // Find persisted query hashes (APQ sha256)
      const hashMatches = text.matchAll(/sha256Hash["':]\s*["']([a-f0-9]{64})["']/g);
      for (const m of hashMatches) results.persistedHashes.push(m[1]);

      // Find gql template literals with operation text
      const gqlMatches = text.matchAll(/gql\s*`([^`]{20,500})`/g);
      for (const m of gqlMatches) results.operations.push(m[1].trim().slice(0, 200));

      // Find API base URLs
      const urlMatches = text.matchAll(/["'](https?:\/\/[^"']+\/graphql[^"']*)["']/g);
      for (const m of urlMatches) results.apiEndpoints.push(m[1]);
    } catch(e) { /* cross-origin scripts will fail — expected */ }
  }

  return {
    operationNames: [...new Set(results.operations)],
    persistedQueryHashes: [...new Set(results.persistedHashes)],
    graphqlEndpoints: [...new Set(results.apiEndpoints)]
  };
}
```

**Limitations**: Code-split lazy-loaded chunks won't be found until their route is navigated. Mark results as `(partial — main bundle only)`. Cross-origin scripts (CDN-hosted) may block fetch — this is expected.

---

## GraphQL Introspection Attempt
```javascript
async () => {
  try {
    const r = await fetch('/graphql', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: '{ __schema { queryType { name } types { name kind description fields { name type { name kind ofType { name kind } } } } } }' })
    });
    const data = await r.json();
    if (data.errors) return { introspectionDisabled: true, errors: data.errors.map(e => e.message) };
    return { introspectionEnabled: true, typeCount: data.data.__schema.types.length, types: data.data.__schema.types.filter(t => !t.name.startsWith('__')).map(t => t.name) };
  } catch(e) { return { error: e.message }; }
}
```
