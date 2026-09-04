---
name: agui-protocol
description: The AG-UI protocol reference — event catalogue with exact field names, RunAgentInput & Message schema, the SSE/EventEncoder wire facts, and state sync. Load when you need exact AG-UI names or wire behavior.
---

# AG-UI protocol reference

AG-UI (by CopilotKit) is the **Agent ↔ User** layer (complementary to MCP = agent↔tools, A2A =
agent↔agent). An agent run is a typed **event stream**; reference transport is HTTP + SSE but it is
transport-agnostic. Verified against the `ag-ui-protocol/ag-ui` source (Python `ag_ui` v0.1.x).

## Wire facts (verified from encoder.py)
- **SSE frame: `data: {json}\n\n`** — one `data:` field, double-newline terminator; no `event:`/`id:`.
- **Content-Type `text/event-stream`** (or `application/vnd.ag-ui.event+proto` for protobuf, TS only).
- **camelCase always.** Python serializes `by_alias=True, exclude_none=True` →
  `messageId`/`toolCallId`/`threadId`/`toolCallName`/`parentMessageId` on the wire. Emitting
  snake_case breaks JS clients. Deserialization accepts both (`populate_by_name=True`); unknown fields
  allowed (`extra="allow"`, forward-compatible).
- **No `[DONE]` sentinel.** End-of-stream = the terminal lifecycle event + HTTP close. (The Vercel AI
  SDK *does* use `[DONE]` — don't confuse the two layers.)
- Encoder: `EventEncoder(accept=...)`, `.get_content_type()`, `.encode(event)`.

## Run lifecycle (mandatory brackets)
A run MUST begin with `RUN_STARTED` and end with exactly one of `RUN_FINISHED` / `RUN_ERROR`.
Everything else is optional. `STEP_STARTED`/`STEP_FINISHED` must balance if used.

## Event catalogue (wire/camelCase field names)
**Lifecycle**
- `RUN_STARTED` — `threadId`, `runId`, `parentRunId?`, `input?`
- `RUN_FINISHED` — `threadId`, `runId`, `result?`, `outcome?` (`{type:"success"}` | `{type:"interrupt", interrupts:[...]}`)
- `RUN_ERROR` — `message`, `code?`
- `STEP_STARTED` / `STEP_FINISHED` — `stepName`

**Text message**
- `TEXT_MESSAGE_START` — `messageId`, `role?` (default `"assistant"`)
- `TEXT_MESSAGE_CONTENT` — `messageId`, `delta` (non-empty)
- `TEXT_MESSAGE_END` — `messageId`
- `TEXT_MESSAGE_CHUNK` — convenience; consumer expands to START→CONTENT→END

**Tool call**
- `TOOL_CALL_START` — `toolCallId`, `toolCallName`, `parentMessageId?`
- `TOOL_CALL_ARGS` — `toolCallId`, `delta` ← **JSON-string FRAGMENT**; concat per id, parse once at END
- `TOOL_CALL_END` — `toolCallId`
- `TOOL_CALL_RESULT` — `messageId`, `toolCallId`, `content` (string), `role?` (`"tool"`)
- `TOOL_CALL_CHUNK` — convenience; expands to START→ARGS→END

**State / sync**
- `STATE_SNAPSHOT` — `snapshot` (full state; client REPLACES its state)
- `STATE_DELTA` — `delta` (**RFC 6902 JSON Patch** array; applied with fast-json-patch; on failure the
  SDK warns and skips → recover by requesting a fresh snapshot)
- `MESSAGES_SNAPSHOT` — `messages` (full history; for init/reconnect/interrupt boundaries)

**Reasoning** (newer; replaces deprecated `THINKING_*`) — `REASONING_START`,
`REASONING_MESSAGE_START/CONTENT/END`, `REASONING_END`, `REASONING_ENCRYPTED_VALUE`.
**Special** — `RAW` (`event`, `source?`), `CUSTOM` (`name`, `value`).

> Treat reasoning/activity events as version-dependent. The "classic" stable core is lifecycle +
> text + tool + state + RAW/CUSTOM. There is **no version field on events** — don't branch on one.

## RunAgentInput (client → agent body)
```
threadId: string        // stable conversation id; reused across runs and on resume
runId: string           // unique per single run
parentRunId?: string
state: any              // REQUIRED (shared app state synced via STATE_SNAPSHOT/DELTA)
messages: Message[]     // REQUIRED (conversation so far)
tools: Tool[]           // REQUIRED (FRONTEND-defined tools available this run; [] if all server-side)
context: Context[]      // REQUIRED ([{description, value}] ambient items)
forwardedProps: any     // REQUIRED (opaque passthrough)
resume?: ResumeEntry[]  // optional (HITL interrupt responses)
```
`state` and `forwardedProps` are `any` but **required**. The bridge route builds this from the
flattened UIMessages, usually with `tools: [], state: {}, context: [], forwardedProps: {}`.

## Message format (discriminated on `role`)
Base: `id`, `role`, `content?`, `name?`. By role:
- `user` — `content: string | InputContent[]` (multimodal: text/image/document/video; audio
  unsupported by Strands)
- `assistant` — `content?`, `toolCalls?: ToolCall[]`
- `tool` — `content: string`, `toolCallId` (binds to the originating call)
- `system`/`developer` — `content`
`ToolCall`: `{ id, type:"function", function:{ name, arguments } }` — **`arguments` is a JSON string**,
not an object.

## HITL / generative UI (two patterns)
1. **Frontend tool** — declared in `tools`; LLM calls it; wire emits START→ARGS→END; client renders,
   collects input, returns a `tool` message; the run continues (in ag-ui-strands the stream halts and
   the client sends a NEW RunAgentInput). The tool call *is* the render instruction.
2. **Interrupt lifecycle** — agent emits state, then `RUN_FINISHED { outcome:{type:"interrupt",
   interrupts:[...]} }`; resume = a new run (same `threadId`, new `runId`) carrying `resume:[{
   interruptId, status, payload? }]` for every open interrupt.

## vs the Vercel AI SDK stream (the layer you bridge to)
Both are SSE, but AG-UI is `SCREAMING_SNAKE_CASE` with run-lifecycle events, RFC-6902 state deltas,
bidirectional, **no `[DONE]`**; the AI SDK stream is `kebab-case` parts (`text-delta`,
`tool-input-delta`), server→client, framework-coupled, **ends with `data: [DONE]`** and uses the
`x-vercel-ai-ui-message-stream: v1` header. Your route is exactly the adapter between them.
