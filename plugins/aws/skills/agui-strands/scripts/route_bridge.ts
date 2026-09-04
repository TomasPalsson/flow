// app/api/chat/route.ts — AG-UI → Vercel AI SDK v5/v6 bridge.
// Golden reference: the translation table + the defensive fixes that prevent the
// silent failures (buffer flush, synthetic text-start, balanced steps, post-error finish).
// Adapt the session strategy for production (the in-memory Map breaks on Lambda — see below).

import {
  createUIMessageStream,
  createUIMessageStreamResponse,
  type UIMessage,
  type UIMessageStreamWriter,
} from "ai";
import {
  BedrockAgentCoreClient,
  InvokeAgentRuntimeCommand,
} from "@aws-sdk/client-bedrock-agentcore";

export const runtime = "nodejs";          // NOT edge — needs Node streams + AWS SDK
export const dynamic = "force-dynamic";
export const maxDuration = 120;           // raise for multi-tool runs

const AGENT_RUNTIME_ARN = process.env.AGENT_RUNTIME_ARN;
// Derive region from the ARN (arn:aws:bedrock-agentcore:<region>:...) to avoid mismatch.
const ARN_REGION = AGENT_RUNTIME_ARN?.split(":")[3];
const REGION = ARN_REGION ?? process.env.AGENT_REGION ?? process.env.AWS_REGION ?? "eu-west-1";
const client = new BedrockAgentCoreClient({ region: REGION });

// NOTE: in-memory only — survives within one warm Lambda but NOT across instances/cold starts.
// For production send a stable id from the client or persist in Redis/DynamoDB.
const sessions = new Map<string, { threadId: string; sessionId: string }>();

interface AgUIEvent {
  type: string;
  messageId?: string;
  delta?: string;
  toolCallId?: string;
  toolCallName?: string;
  content?: string;
  message?: string;
}

export async function POST(req: Request) {
  let body: { messages: UIMessage[] };
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid request" }, { status: 400 });
  }
  if (!body.messages?.length) {
    return Response.json({ error: "Invalid request" }, { status: 400 });
  }

  const firstMsgId = body.messages[0]?.id ?? "default";
  let session = sessions.get(firstMsgId);
  if (!session) {
    session = {
      threadId: crypto.randomUUID(),
      sessionId: crypto.randomUUID(), // 36 chars ≥ the 33-char AgentCore minimum
    };
    sessions.set(firstMsgId, session);
  }

  // Flatten AI SDK UIMessages → AG-UI RunAgentInput (text parts only; the agent owns history).
  const agMessages = body.messages.map((m) => ({
    id: m.id,
    role: m.role as string,
    content:
      m.parts
        ?.filter((p): p is { type: "text"; text: string } => p.type === "text")
        .map((p) => p.text)
        .join("") ?? "",
  }));
  const agInput = {
    threadId: session.threadId,
    runId: crypto.randomUUID(),
    messages: agMessages,
    tools: [],
    state: {},
    context: [],
    forwardedProps: {},
  };

  const stream = createUIMessageStream({
    execute: async ({ writer }) => {
      writer.write({ type: "start" }); // REQUIRED — SDK back-fills messageId; it does NOT auto-write this
      const ctx: Ctx = { toolArgs: {}, toolNames: {}, currentTextId: "", n: 0, stepOpen: false };
      try {
        if (!AGENT_RUNTIME_ARN) {
          writeFallbackText(writer, "Agent not configured (missing AGENT_RUNTIME_ARN).");
          return;
        }
        let sse: ReadableStream<Uint8Array> | undefined;
        try {
          const result = await client.send(
            new InvokeAgentRuntimeCommand({
              agentRuntimeArn: AGENT_RUNTIME_ARN,
              runtimeSessionId: session!.sessionId,
              contentType: "application/json",
              accept: "text/event-stream", // omit → AgentCore buffers the whole response
              payload: new TextEncoder().encode(JSON.stringify(agInput)),
            }),
          );
          sse = result.response?.transformToWebStream();
        } catch (err) {
          console.error("[chat] InvokeAgentRuntime failed:", err);
          writer.write({ type: "error", errorText: "Agent unavailable" });
          return;
        }
        if (!sse) {
          writer.write({ type: "error", errorText: "No response stream" });
          return;
        }
        await pipeSse(sse, writer, ctx);
      } finally {
        if (ctx.stepOpen) writer.write({ type: "finish-step" }); // balance a dangling start-step
        writer.write({ type: "finish" });                         // REQUIRED — close the envelope
      }
    },
    onError: (err) => {
      console.error("[chat] onError:", err);
      return "Agent service error";
    },
  });

  return createUIMessageStreamResponse({ stream }); // adds SSE framing + [DONE]; never write [DONE]
}

interface Ctx {
  toolArgs: Record<string, string>;
  toolNames: Record<string, string>;
  currentTextId: string;
  n: number;
  stepOpen: boolean;
}

async function pipeSse(sse: ReadableStream<Uint8Array>, writer: UIMessageStreamWriter, ctx: Ctx) {
  const reader = sse.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  const handleLine = (line: string) => {
    if (line.startsWith(":")) return;          // SSE comment / keep-alive
    if (!line.startsWith("data:")) return;
    const data = line.slice(5).trim();          // hardcode "data:".length, not indexOf
    if (!data || data === "[DONE]") return;
    let ev: AgUIEvent;
    try { ev = JSON.parse(data); } catch { return; }
    translateEvent(ev, writer, ctx);
  };
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true }); // stream:true → no split multibyte chars
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";                          // keep partial last line
      for (const line of lines) handleLine(line);
    }
    if (buffer.trim()) for (const line of buffer.split("\n")) handleLine(line); // FLUSH leftover
  } catch (e) {
    console.error("[chat] stream read error:", e);
    writer.write({ type: "error", errorText: "Agent stream failed" });
  } finally {
    reader.releaseLock();
  }
}

function translateEvent(ev: AgUIEvent, writer: UIMessageStreamWriter, ctx: Ctx) {
  switch (ev.type) {
    case "RUN_STARTED":
      ctx.stepOpen = true;
      writer.write({ type: "start-step" });
      break;
    case "TEXT_MESSAGE_START": {
      ctx.currentTextId = ev.messageId ?? `msg_${++ctx.n}`;
      writer.write({ type: "text-start", id: ctx.currentTextId });
      break;
    }
    case "TEXT_MESSAGE_CONTENT": {
      if (!ev.delta) break;
      if (!ctx.currentTextId) {                 // synthesize a start so the SDK doesn't throw
        ctx.currentTextId = `msg_${++ctx.n}`;
        writer.write({ type: "text-start", id: ctx.currentTextId });
      }
      writer.write({ type: "text-delta", id: ctx.currentTextId, delta: ev.delta });
      break;
    }
    case "TEXT_MESSAGE_END":
      if (ctx.currentTextId) writer.write({ type: "text-end", id: ctx.currentTextId });
      ctx.currentTextId = "";
      break;
    case "TOOL_CALL_START": {
      const id = ev.toolCallId ?? `tool_${++ctx.n}`;
      ctx.toolArgs[id] = "";
      ctx.toolNames[id] = ev.toolCallName ?? "unknown";
      writer.write({ type: "tool-input-start", toolCallId: id, toolName: ctx.toolNames[id] });
      break;
    }
    case "TOOL_CALL_ARGS": {
      const id = ev.toolCallId ?? "";
      if (!ev.delta) break;
      ctx.toolArgs[id] = (ctx.toolArgs[id] ?? "") + ev.delta;
      writer.write({ type: "tool-input-delta", toolCallId: id, inputTextDelta: ev.delta });
      break;
    }
    case "TOOL_CALL_END": {
      const id = ev.toolCallId ?? "";
      if (!ctx.toolNames[id]) break;            // never saw START → skip a phantom tool
      let input: unknown = {};
      try { input = JSON.parse(ctx.toolArgs[id] ?? "{}"); } catch { input = {}; }
      writer.write({ type: "tool-input-available", toolCallId: id, toolName: ctx.toolNames[id], input });
      break;
    }
    case "TOOL_CALL_RESULT": {
      const id = ev.toolCallId ?? "";
      let output: unknown = {};
      if (ev.content) { try { output = JSON.parse(ev.content); } catch { output = ev.content; } }
      writer.write({ type: "tool-output-available", toolCallId: id, output });
      break;
    }
    case "RUN_ERROR":
      writer.write({ type: "error", errorText: ev.message ?? "Agent error" });
      break;
    case "RUN_FINISHED":
      if (ctx.stepOpen) { writer.write({ type: "finish-step" }); ctx.stepOpen = false; }
      break;
  }
}

function writeFallbackText(writer: UIMessageStreamWriter, text: string) {
  const id = crypto.randomUUID();
  writer.write({ type: "start-step" });
  writer.write({ type: "text-start", id });
  writer.write({ type: "text-delta", id, delta: text });
  writer.write({ type: "text-end", id });
  writer.write({ type: "finish-step" });
}
