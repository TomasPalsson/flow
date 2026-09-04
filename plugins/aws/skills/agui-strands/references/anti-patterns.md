---
name: anti-patterns
description: Symptom-indexed catalogue of the silent failure modes across the AG-UI/Strands/AgentCore/AI-SDK stack — blank bubble, spinner forever, amnesia, frozen pane, NaN prices, image-not-found. Load when debugging.
---

# Anti-patterns & silent failures (symptom → cause → fix)

The stack has four blind layers; almost every bug is a **silent** blank screen or stuck spinner with
no error. Find your symptom.

## "The chip spins forever / blank space where a card should be"
- **Leftover SSE buffer never flushed.** `buffer = lines.pop()` keeps the partial last line; the loop
  `break`s on `done` before parsing it. If `RUN_FINISHED` (or `TOOL_CALL_RESULT`) lands in the final
  chunk it's dropped → `finish-step`/`tool-output-available` never written → client stuck in
  `streaming`. **Fix:** after the read loop, parse the remaining `buffer`. (In route_bridge.ts.)
- **Malformed tool args.** Partial/interrupted JSON across `TOOL_CALL_ARGS` → `JSON.parse` throws →
  `input:{}` and often no result follows → chip never reaches `output-available`. **Fix:** log it; if
  `toolNames[id]` is missing, skip emitting the tool entirely.
- **No `TOOL_CALL_RESULT`.** Agent crashed after the call. Add a client-side timeout that flips the
  chip to an error state if `input-available` persists too long.

## "Blank assistant bubble, no text, no card, no error"
- **Missing `start-step`/`finish-step` pair.** The route always writes `finish` (finally block) but
  only writes `start-step` on `RUN_STARTED`. If the agent fails before `RUN_STARTED`, the SDK sees
  `start`→`finish` with no step → renders an empty message. **Fix:** track `stepOpen`; in `finally`,
  if a step was opened but not closed, write `finish-step`.
- **Forgot to write `start`/`finish` at all.** The bridge path does NOT auto-inject them (see
  ai-sdk-bridge.md §2). No `start` → no message id → nothing renders.

## "Client throws `AI_UIMessageStreamError: text part <id> not found`"
- **`text-delta` before `text-start`** (same id). Happens when `currentTextId` is `""` because
  `TEXT_MESSAGE_START` was dropped. **Fix:** in the CONTENT case, if no current id, synthesize a
  `text-start` first, then the delta. Don't just generate a new id for the delta alone.

## "Agent forgets everything after the first message" (works in dev, breaks in prod)
- **In-memory `sessions` Map on Lambda.** Module-scope state doesn't survive across Lambda instances /
  cold starts → a new `threadId`+`runtimeSessionId` per request → AgentCore sees a fresh session.
  **Fix:** send a stable id from the client (`useChat` id), derive from a session cookie, or store in
  Redis. Don't rely on the Map alone in production.
- **`messages[0].id` session key collapses to `"default"`** if the first message has no id → all users
  share one session. Validate the id exists.

## "Pane is frozen for 30–60s, then everything appears at once"
- **Missing `accept: "text/event-stream"`** on `InvokeAgentRuntimeCommand` → AgentCore buffers the
  whole response. Streaming pipeline logs look perfect; only the UX is broken.
- **Missing OpenNext `aws-lambda-streaming` wrapper** → the Lambda buffers the SSE response. Add
  `open-next.config.ts` with `override: { wrapper: "aws-lambda-streaming" }`.

## "InvokeAgentRuntime fails / agent unavailable"
- **`runtimeSessionId` < 33 chars** → 400/422. Use one `crypto.randomUUID()` (36) or longer.
- **Wrong IAM:** caller needs `bedrock-agentcore:InvokeAgentRuntime` (NOT `bedrock:*`).
  `AccessDenied` looks like "agent down."
- **Region mismatch:** client region ≠ ARN region → `ResourceNotFoundException`. Derive region from
  the ARN.
- **`runtime` not `"nodejs"`:** edge runtime lacks the AWS SDK / web-stream transform.
- **`maxDuration` too low (60):** multi-tool runs hit the Lambda timeout → truncated stream / hung
  spinner. Raise to ≥120 and bump the SST server timeout.

## "Container deploy fails: image does not exist" / crashes on first invoke
- **Manifest list pushed.** buildx default adds attestation layers AgentCore can't resolve. Add
  `--provenance=false --sbom=false`.
- **amd64 image.** AgentCore is arm64-only; an x86 image health-checks then dies with
  `ELF ... OS ABI invalid` / `Illegal instruction`. Build `--platform linux/arm64`.

## "Agent answers in prose; no card ever renders"
- **System prompt doesn't mandate tool use.** Claude prefers a confident text answer. Make the prompt
  prescriptive: which tool per query type, never fabricate, cards render automatically.

## "Card shows but prices are NaN / fields undefined"
- **Tool↔card output shape drift.** Python renamed a field (e.g. `priceExVat`→`price_ex_vat`);
  TS reads `undefined`. No error because output crosses as `unknown`. **Fix:** shared schema / test.
- **Tool name renamed** without updating the React `case` → `default: return null`, chip flashes and
  vanishes. Keep a shared `TOOL_NAMES` const and an exhaustive switch.

## "Multi-turn history wrong / context bleeds between users / one user sees another's session"
- **`session_manager` set on the template Strands agent** → `StrandsAgent` silently ignores it; all
  threads would share one session (cross-user context bleed). Use
  `StrandsAgentConfig.session_manager_provider` and set `replay_history_into_strands=False`. (The two
  history paths are mutually exclusive.)
- **`_agents_by_thread` never evicts** → memory grows unbounded in a long-lived server. Restart
  periodically or add your own eviction for high traffic.

## "Deployed agent can't reach AWS / credential errors at runtime"
- **AWS creds/profile in `.env` or `.env.local`.** Next.js bundles `.env*` into the Lambda package;
  the profile reference then breaks the SDK credential chain (no `~/.aws/credentials` in Lambda).
  **Fix:** put `AWS_PROFILE`/`AWS_REGION` in `.envrc` (direnv) for local dev; rely on the IAM role
  when deployed — never ship AWS creds in `.env*`.

## "Whole turn errors with a generic message"
- **Non-JSON-serializable tool return** (`Decimal`/`datetime`/float) → `json.dumps` throws →
  `RUN_ERROR`. Cast at the boundary: `round(float(x))`.
- **Missing inference-profile prefix:** bare `anthropic.claude-...` in `eu-west-1` →
  `ValidationException`. Use `eu.`/`us.` matching the region.

## Frontend nits
- Key tool parts by `toolCallId`, not array index, or interactive card state resets on each stream
  update.
- Disable quick-reply chips when `isBusy`, or a click mid-stream fires a concurrent request.

## Priority (kill-probability × invisibility)
1. Leftover buffer not flushed — High, near-invisible
2. Missing start-step/finish-step — High, invisible
3. In-memory sessions on Lambda — High, invisible
4. text-delta before text-start — Med-High, throws (at least visible)
5. accept header / OpenNext buffering — Med, looks frozen
6. malformed tool args — Med, spinner forever
7. arm64 / provenance build — Med, crash on invoke
8. tool-name↔card mismatch — Med, silent null
