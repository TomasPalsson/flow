---
name: agui-strands
description: "Build or debug generative-UI chat apps on the AG-UI × Strands × Bedrock AgentCore × Vercel AI SDK (useChat) stack. Use WHEN: scaffolding an ag_ui_strands agent server (StrandsAgent, @tool, BedrockModel, EventEncoder, RunAgentInput, /invocations, /ping, 0.0.0.0:8080, arm64); writing the createUIMessageStream bridge (RUN_STARTED→start-step, TOOL_CALL_RESULT→tool-output-available, start/finish envelope, SSE buffer flush); building generative-UI card renderers (useChat, dynamic-tool parts, tool-input-available, tool-output-available, AI SDK v5/v6); deploying to Bedrock AgentCore Runtime (InvokeAgentRuntime, runtimeSessionId, ECR, OpenNext streaming, Terraform); or debugging: blank chat bubble, tool chip spins forever, text part not found, agent forgets context after message 1, frozen pane, runtimeSessionId length errors, manifest-list/image-not-found on deploy."
---

# AG-UI × Strands × Generative UI

Build chat apps where a **Strands agent on Bedrock AgentCore** emits **AG-UI protocol** events,
a **Next.js route translates them into Vercel AI SDK stream parts**, and **`useChat` renders tool
calls as React cards**. This is the architecture in real production apps (elko.is, garri.is).

> "AGUI" here is NOT CopilotKit's frontend SDK. It is a hand-written bridge: AG-UI SSE on the
> backend, the Vercel AI SDK UI-message stream on the frontend, joined by ~50 lines in your route.
> Internalize that or you will look for libraries that do not exist.

## The mental model — four protocol layers, one data path

```
useChat (AI SDK v6) ──POST UIMessage[]──► /api/chat route
   ▲                                          │ flatten → AG-UI RunAgentInput {threadId,runId,messages,...}
   │ parts[]                                   ▼ InvokeAgentRuntime (accept: text/event-stream)
React cards ◄── AI SDK parts ◄── translateEvent() ◄── AG-UI SSE ◄── FastAPI /invocations :8080 (arm64)
                                                                       │ ag_ui_strands.StrandsAgent
                                                                       ▼ Strands Agent → Bedrock (Claude)
```

**Each layer is blind to the others.** A bug in the agent surfaces as a blank screen two layers up
with no error. When something is wrong, name the layer first: AG-UI event? SSE wire? AI SDK part
ordering? React card switch? Debug the boundary, not the symptom.

The single source of truth crossing the boundary is the **AG-UI → AI SDK part translation table**
(see `references/ai-sdk-bridge.md`). Get one `type` string or one ordering rule wrong and the chat
goes blank silently.

## Golden build order

Build and verify **backend → bridge → frontend → deploy**, proving each layer before the next.

1. **Agent server** (`agent/main.py`) — FastAPI + `ag_ui_strands.StrandsAgent`, `/invocations` SSE +
   `/ping`, on `0.0.0.0:8080`. Scaffold: [`scripts/agent_server.py`](scripts/agent_server.py).
   Verify with `curl -N -H 'accept: text/event-stream' localhost:8080/invocations -d '{...}'`.
2. **Tools** — Strands `@tool` functions returning `json.dumps({...})`. Before writing each tool, ask:
   **what is its exact three-part contract?** (a) the function name == the React card `case`; (b) the
   return JSON shape == what the card reads; (c) every value is JSON-serializable. Drift on any one
   fails silently — verify all three before moving on. See `references/ag-ui-strands.md`.
3. **The bridge** (`app/api/chat/route.ts`) — the crux. Copy
   [`scripts/route_bridge.ts`](scripts/route_bridge.ts) **as written** (translation table +
   buffer-flush + synthetic-text-start fixes baked in); **adapt only the session strategy** for
   production (see the session decision tree below). Read `references/ai-sdk-bridge.md` first.
4. **Frontend** — `useChat` + a `parts[]` renderer that switches `tool-<name>`/`dynamic-tool` parts
   to cards. See `references/ai-sdk-bridge.md` §rendering.
5. **Deploy** — arm64 image → ECR → AgentCore runtime; wire the ARN into the Next app; OpenNext
   streaming wrapper. See `references/agentcore-deploy.md`.

Run [`scripts/agui_doctor.py`](scripts/agui_doctor.py) against the project at any point to catch the
known footguns before they cost you an afternoon.

## The bridge envelope — the one thing you must get exactly right

The route uses `createUIMessageStream` with a **manual writer**. In this path the SDK does **NOT**
write `start`/`finish` for you — **you must** (it only back-fills `messageId` onto your `start`
chunk). This contradicts a lot of stale advice about `streamText().toUIMessageStreamResponse()`,
which is a *different* path. For the AG-UI bridge:

```ts
const stream = createUIMessageStream({
  execute: async ({ writer }) => {
    writer.write({ type: "start" });                 // REQUIRED (id back-filled by SDK)
    try {
      // for each AG-UI SSE event → translateEvent(event, writer, ctx)
      // (full RUN_*/TEXT_MESSAGE_*/TOOL_CALL_* → part mapping in references/ai-sdk-bridge.md §1)
    } finally {
      writer.write({ type: "finish" });              // REQUIRED (close envelope)
    }
  },
  onError: () => "Agent service error",
});
return createUIMessageStreamResponse({ stream });    // adds SSE framing + [DONE]; do NOT write [DONE]
```

The full, correct `translateEvent` switch is in `references/ai-sdk-bridge.md` and
`scripts/route_bridge.ts`. **Do not paraphrase it from memory — the exact `type` strings are
load-bearing.**

## Non-obvious rules that prevent silent failure

- **AG-UI wire is camelCase, has no `[DONE]` sentinel**, frames as `data: {json}\n\n`, and
  `TOOL_CALL_ARGS.delta` is a **JSON-string fragment** — concatenate per `toolCallId`, parse once at
  `TOOL_CALL_END`. A run MUST be bracketed `RUN_STARTED … RUN_FINISHED|RUN_ERROR`.
- **Flush the leftover SSE buffer after the read loop.** `buffer = lines.pop()` keeps the partial
  last line; if `RUN_FINISHED` lands in the final chunk you `break` before parsing it →
  `finish-step` never fires → client hangs in `streaming` forever. (Baked into the scaffold.)
- **`runtimeSessionId` must be 33–256 chars.** One `crypto.randomUUID()` (36) is enough; double-UUID
  is belt-and-suspenders.
- **AgentCore call must send `accept: "text/event-stream"`**, or the entire response buffers and the
  user sees a frozen pane, then everything at once.
- **`export const runtime = "nodejs"`** on the route (not edge) — the AWS SDK and web-stream
  transform need Node. Set `maxDuration` ≥ 120 for multi-tool runs.
- **Tool function name == React card `case`.** Renaming the Python tool without updating the card
  switch → the chip flashes and the card silently returns `null`. Keep a shared `TOOL_NAMES` const.
- **Tool returns must be JSON-serializable** — cast `Decimal`/`datetime`/floats at the boundary or
  `json.dumps` throws and the whole turn becomes a generic `RUN_ERROR`.

## NEVER (things this stack teaches the hard way)

- **NEVER** paraphrase the bridge `type` strings from memory — `tool-input-available` /
  `tool-input-delta` / `tool-output-available` are distinct; one wrong string silently drops the
  part and the card never renders. Copy from `references/ai-sdk-bridge.md` or `scripts/route_bridge.ts`.
- **NEVER** rely on `createUIMessageStream` to write `start`/`finish` for you on the bridge path — it
  does not. You write both; the SDK only back-fills `messageId`. (Auto-write is the `streamText` path.)
- **NEVER** set `session_manager` on the *template* Strands agent — `StrandsAgent` silently ignores it.
  Use `session_manager_provider` and set `replay_history_into_strands=False`.
- **NEVER** put AWS creds/profile in `.env` or `.env.local` — Next bundles them into the Lambda where
  the profile breaks the SDK credential chain. Use `.envrc` (direnv) locally; the IAM role when deployed.
- **NEVER** tag the AgentCore ECR image `:latest` — the runtime won't roll on source changes. Use a
  content-addressed tag (sha1 of source files) so Terraform forces a rebuild.
- **NEVER** set `runtime = "edge"` on the chat route — the AWS SDK + web-stream transform need Node.
- **NEVER** treat the system prompt as optional — without explicit tool-mandate instructions Claude
  answers in prose and no card ever renders (no error fires either).
- **NEVER** build the agent image as amd64 or with default buildx — AgentCore is arm64-only and
  rejects manifest lists; build `--platform linux/arm64 --provenance=false --sbom=false`.

## Decision trees

**Which backend mode?** (garri's three-mode pattern)
- `AGENT_URL` set → POST the local python agent (fast iteration, full AG-UI path, no AWS).
- else `AGENT_RUNTIME_ARN` set → `InvokeAgentRuntime` (deployed AgentCore).
- else → direct Bedrock `streamText` with TS tool mirrors (zero-infra fallback / demo).
Explicitly set the unused env to `""` in prod (SST) so a leaked local URL can't activate.

**Who owns conversation history?**
- Default `replay_history_into_strands=True`: stateless agent, the route sends full history each
  turn, `StrandsAgent` overwrites `agent.messages` and calls `stream_async(None)`. Use this.
- `session_manager_provider` (File/S3 SessionManager): Strands persists history; set
  `replay_history_into_strands=False`. Mutually exclusive with the above.

**Backend tool vs frontend tool?**
- Backend (`@tool` on the server): result arrives inline as `TOOL_CALL_RESULT`. Default choice.
- Frontend (declared in `RunAgentInput.tools`): stream halts after `TOOL_CALL_END`; the client
  executes it and sends a NEW `RunAgentInput` with the result. Only when the action needs the browser.

**Session id for production?** Mental model: on Lambda you have **no durable module-scope state** —
assume horizontal scale from day 1. The in-memory `sessions` Map works in `next dev` but **breaks on
Lambda** (per-instance, cold starts) → the agent forgets context after message #1. The
`runtimeSessionId` must be **stable across a conversation's requests**. Pick by deployment:
- **Next.js + auth (NextAuth/Clerk)** → derive the id from the session token / user id. Zero infra.
- **Anonymous / no auth** → use the stable `useChat` chat `id` (persist in `localStorage`) and send it
  as `threadId` in the request body; the route uses it instead of `messages[0].id`.
- **High-scale / multi-tenant** → store the id in Redis/DynamoDB keyed by user+conversation.
- **Local dev only** → the in-memory Map is fine (single process, no cold starts).

## When to load the references (do it before writing that layer)

- **MANDATORY — READ ENTIRE FILE** before writing/altering the route bridge or any frontend card:
  [`references/ai-sdk-bridge.md`](references/ai-sdk-bridge.md) — translation table, every part `type`,
  the start/finish truth, the card-rendering state machine.
- **MANDATORY — READ ENTIRE FILE** before writing/altering the agent or its tools:
  [`references/ag-ui-strands.md`](references/ag-ui-strands.md) — `StrandsAgent` internals, `@tool`
  schema rules, `BedrockModel`, history replay, frontend tools, the gotchas.
- **MANDATORY — READ ENTIRE FILE** before any deploy/infra work:
  [`references/agentcore-deploy.md`](references/agentcore-deploy.md) — the runtime contract, arm64 +
  buildx flags, Terraform, IAM, sessionId, OpenNext streaming, ARN wiring.
- Load [`references/agui-protocol.md`](references/agui-protocol.md) ONLY to verify exact wire-level
  field names (camelCase), the RunAgentInput schema, or the STEP/REASONING/STATE event set. **Do NOT
  load it for the bridge** — `ai-sdk-bridge.md` already has the translation table. **Do NOT load it for
  the agent** — use `ag-ui-strands.md`. Loading it alongside `ai-sdk-bridge.md` for a bridge task just
  duplicates the event table.
- Load [`references/anti-patterns.md`](references/anti-patterns.md) when debugging a silent failure —
  it is indexed by symptom (blank bubble, spinner forever, amnesia, frozen pane, NaN prices…).
- For local dev (run the agent on `:8080` + env wiring + `.envrc` vs `.env`), see the "Local dev"
  section of `references/agentcore-deploy.md`.

## Runtime tools

- `python3 scripts/agui_doctor.py [PROJECT_DIR]` — static scan for the known footguns (buffer flush,
  `runtime="nodejs"`, `maxDuration`, accept header, sessionId length, Dockerfile arm64, buildx
  provenance flags, tool-name↔card-case parity, OpenNext streaming wrapper). Prints PASS/WARN/FAIL.
  Run it after scaffolding and before every deploy.
- `scripts/route_bridge.ts` — drop-in `app/api/chat/route.ts` reference with the translation table
  and all the defensive fixes. Adapt the session strategy for production.
- `scripts/agent_server.py` — drop-in `agent/main.py` reference (FastAPI + `ag_ui_strands`).

## Self-check before declaring done
1. `agui_doctor.py` reports no FAIL.
2. Every Python tool name has a matching card `case` (and vice versa).
3. The route writes `start` … `finish` and flushes the trailing buffer.
4. The AgentCore call sends `accept: text/event-stream`; the route is `runtime="nodejs"`.
5. Deploy uses arm64 + `--provenance=false --sbom=false` and the OpenNext streaming wrapper.
6. Production session id is stable across requests (not the in-memory Map alone).
