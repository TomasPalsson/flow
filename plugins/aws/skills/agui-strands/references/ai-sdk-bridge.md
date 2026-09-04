---
name: ai-sdk-bridge
description: The AG-UI → Vercel AI SDK translation table, the complete UIMessage-stream part types, the start/finish truth, and the frontend generative-UI rendering state machine. Load before writing the /api/chat route or any tool card.
---

# The AG-UI ↔ Vercel AI SDK bridge (v5/v6)

Verified against `ai@6.0.184`, `@ai-sdk/react@3.0.186`. The wire format changed completely from v4
(the old `0:`/`9:`/`a:` prefixes and `message.content`/`toolInvocations` are GONE). Ignore v4 advice.

## 1. The translation table (the crux)

Two independent production codebases (elko, garri) converge on this exact 10-case switch. The route
keeps per-run context: `toolArgs: Record<id,string>` (accumulates arg fragments), `toolNames:
Record<id,string>` (TOOL_CALL_RESULT omits the name), `currentTextId`, and a fallback counter.

| AG-UI event | `writer.write(...)` part |
|---|---|
| `RUN_STARTED` | `{ type: "start-step" }` |
| `TEXT_MESSAGE_START` | `{ type: "text-start", id }` |
| `TEXT_MESSAGE_CONTENT` | `{ type: "text-delta", id, delta }` |
| `TEXT_MESSAGE_END` | `{ type: "text-end", id }` |
| `TOOL_CALL_START` | `{ type: "tool-input-start", toolCallId, toolName }` |
| `TOOL_CALL_ARGS` | `{ type: "tool-input-delta", toolCallId, inputTextDelta: delta }` |
| `TOOL_CALL_END` | `{ type: "tool-input-available", toolCallId, toolName, input }` ← `JSON.parse(accumulated args)` |
| `TOOL_CALL_RESULT` | `{ type: "tool-output-available", toolCallId, output }` ← `JSON.parse(event.content)` |
| `RUN_ERROR` | `{ type: "error", errorText }` |
| `RUN_FINISHED` | `{ type: "finish-step" }` |

The outer `start`/`finish` envelope is written by the route, NOT derived from AG-UI events.
`TOOL_CALL_END` does `try { JSON.parse(toolArgs[id]) } catch { input = {} }`. `TOOL_CALL_RESULT`'s
`content` is a JSON string — parse it so the card receives an object.

## 2. The start/finish truth (source-verified — corrects common misinformation)

`createUIMessageStream({ execute, onError })` runs `execute({ writer })`, then pipes through
`handleUIMessageStreamFinish`. That transform's ONLY start behavior is:
```js
if (chunk.type === "start" && chunk.messageId == null) chunk.messageId = messageId; // back-fill
```
It does **not** create a `start` chunk and does **not** create a `finish` chunk. So in the
manual-writer / AG-UI bridge path **you must write both yourself**:

```ts
const stream = createUIMessageStream({
  execute: async ({ writer }) => {
    writer.write({ type: "start" });          // id back-filled by the SDK
    try { /* translateEvent loop */ }
    finally { writer.write({ type: "finish" }); }
  },
  onError: () => "Agent service error",
});
return createUIMessageStreamResponse({ stream });
```
`createUIMessageStreamResponse` sets `content-type: text/event-stream`,
`x-vercel-ai-ui-message-stream: v1`, `x-accel-buffering: no`, and appends `data: [DONE]`. **You never
write `[DONE]`.** (The "don't write start manually" advice is true only for
`streamText(...).toUIMessageStreamResponse()`, a different, model-backed path the bridge does not use.)

## 3. Complete UIMessageChunk part types (exact `type` strings)

```
LIFECYCLE   start(messageId?) · finish(finishReason?) · start-step · finish-step · abort · message-metadata
TEXT        text-start(id) · text-delta(id, delta) · text-end(id)
REASONING   reasoning-start(id) · reasoning-delta(id, delta) · reasoning-end(id)
TOOL INPUT  tool-input-start(toolCallId, toolName) · tool-input-delta(toolCallId, inputTextDelta)
            tool-input-available(toolCallId, toolName, input) · tool-input-error(...)
TOOL OUTPUT tool-output-available(toolCallId, output) · tool-output-error(toolCallId, errorText)
TOOL FLOW   tool-output-denied · tool-approval-request(approvalId, toolCallId)
SOURCES     source-url(sourceId, url, title?) · source-document(sourceId, mediaType, title)
FILE        file(url, mediaType)
DATA        data-<NAME>(data, id?, transient?)        ← transient:true = delivered via onData, not persisted
ERROR       error(errorText)                          ← does NOT terminate the stream
```
Required ordering: `start → (start-step → [text/tool/...] → finish-step)* → finish`.
Set `dynamic: true` on a tool-input chunk when the tool name is not known at type time → it lands as
a `dynamic-tool` part instead of `tool-<name>`. The AG-UI bridge always produces `dynamic-tool` parts
(no compile-time tool types), so the frontend reads `part.toolName`.

## 4. UIMessage parts (what the frontend reads)

`message.parts: UIMessagePart[]`; there is **no `message.content`**. Part types: `text`
(`{text, state}`), `reasoning`, `step-start`, `tool-<name>` (`ToolUIPart`), `dynamic-tool`
(`{toolName, ...}`), `source-url`, `source-document`, `file`, `data-<name>`.

Tool part `state` machine: `input-streaming` → `input-available` → `output-available`
(or `output-error`, `approval-requested`). `output` exists only in `output-available`. The part
mutates in place as state advances (stable index, but key by `toolCallId`, not index).

## 5. useChat (v5/v6) — custom backend

```tsx
import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport } from "ai";
const { messages, sendMessage, status, regenerate } = useChat({
  transport: new DefaultChatTransport({ api: "/api/chat" }),   // `api` lives on the transport, not useChat
});
// status: "submitted" | "streaming" | "ready" | "error"  (NOT isLoading)
// send:   sendMessage({ text })  (NOT append / handleSubmit)
```
Message `id` is stable for the lifetime of a conversation (first message id) — both routes key their
session map on `messages[0].id`.

## 6. Generative-UI rendering pattern (from elko/garri)

Split each message's parts into text vs tool; render text as markdown, tool parts through a
dispatcher. The proven `ToolInvocationPart` state machine:

```tsx
function ToolInvocationPart({ toolName, state, output, isStreaming }) {
  // 1. running: animated chip
  if ((state === "input-streaming" || state === "input-available") && !output)
    return <ToolChip toolName={toolName} />;
  if (state !== "output-available" && !output) return null;
  // 2. output ready BUT parent message still streaming: compact "done" chip (avoid layout thrash)
  if (isStreaming && toolName !== "suggest_replies")   // quick-reply chips stay live
    return <ToolChip toolName={toolName} done />;
  // 3. settled: the real card
  const d = parse(output);                  // tolerate string OR object (see below)
  switch (toolName) {
    case "search_products": return <ProductGridCard {...d} />;
    case "compare":         return <CompareCard {...d} />;
    /* one case per Strands tool name */
    default: return null;                   // ← silent disappearance if a name is unmapped
  }
}
```

Dual-mode parse (AG-UI path delivers parsed objects; a direct-Bedrock fallback delivers raw objects;
defensive string-parse covers both):
```ts
function parse<T>(o: unknown): T | null {
  if (!o) return null;
  if (typeof o === "string") { try { return JSON.parse(o) as T; } catch { return null; } }
  return o as T;
}
```
Guard every card on `if (!d || d.error || !d.<requiredField>) return null;`.

Layout intelligence (optional but real): render `search_products` first; if any "hero" card exists,
collapse search to a compact summary; stagger card entrance with `animationDelay: i*70ms`. Cross-card
actions (a card calling `sendMessage`) go through a `ChatActionsProvider` context, with a no-op
fallback so cards don't crash outside the provider.

## 7. Frontend footguns (see anti-patterns.md for the full set)
- `text-delta` with an `id` that never had a `text-start` → client throws `text part <id> not found`.
  If `currentTextId` is empty at CONTENT time, write a **synthetic `text-start` first**.
- `tool-output-available` without a prior `tool-input-available` → the part has no `toolName`.
- Key tool parts by `toolCallId`, not array index, or interactive card state resets on stream updates.
