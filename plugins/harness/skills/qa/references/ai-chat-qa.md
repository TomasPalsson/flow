# AI Chat & Streaming App QA Patterns

Detailed testing patterns for AI-powered chat applications with streaming responses, component blocks, and bilingual support.

## Non-Deterministic Output — What to Assert

### Structural Assertions (use these, not exact text)

For component blocks like `:::: EducationPathCard {json} ::::`:
1. Parse response with regex: `/::::\s*(\w+)\s*(\{.*?\})\s*::::/gs`
2. Assert: block type is in the allowed component registry
3. Assert: JSON parses without error
4. Assert: parsed JSON has all required fields with correct types
5. Assert: no raw JSON blobs appear outside recognized block delimiters
6. Assert: component is rendered in the DOM (block consumed, not passed as raw text)

**Schema validation is the highest-value test for AI output.** Malformed JSON in a component block silently fails to render — looks like a loading error but is actually a data bug.

### Behavioral Contract Tests

| Contract | How to Test |
|----------|-------------|
| Always asks follow-up after intake turn | Run intake prompt 3-5x, assert each response contains `?` |
| Displays result card after sufficient context | Script full intake, assert component block appears |
| Never answers off-topic mid-intake | Send off-topic message, assert redirect response |
| Language matches UI setting | Set UI to target language, verify response language matches |
| Incomplete intake → asks for missing fields | Provide N-1 of N required fields, assert AI requests the missing one |

### Repeatability for Non-Deterministic Tests

- Run critical behavioral contracts 3-5 times. Report as fraction (4/5 = soft failure, 1/5 = hard failure)
- Use `temperature=0` or seed parameter when available for regression tests
- Keep separate exploratory suite at default temperature to catch variance bugs
- Classify failures: model structure bug vs test needs updating vs model drift

## Streaming Response Testing

### Chunk-Split Vulnerability

Component block delimiters may split across stream chunks:
```
Chunk 1: "Here is your path: :::: Educatio"
Chunk 2: "nPathCard {\"title\": \"BSc Computer"
Chunk 3: " Science\", \"steps\": [...]} ::::"
```

Tests to write:
- Mock stream where `::::` delimiter splits across chunks → verify block renders after completion
- Mock stream where JSON splits mid-key → verify no partial JSON errors
- Incomplete block at end-of-stream → verify graceful fallback, not raw syntax visible
- Full block arrives → verify no layout shift when block pops in

### Stream Interruption Scenarios

| Scenario | Expected Behavior | How to Test |
|----------|-------------------|-------------|
| User navigates away mid-stream | Stream aborted, no memory leak | Navigate during stream, check console for errors |
| Network drops mid-stream | Partial response shown + error + retry | Throttle network to simulate drop |
| Error after successful chunks | Partial response visible + error indicator | Mock stream that sends text then throws |
| Very fast stream (backpressure) | No dropped chunks, no duplicates | Mock synchronous zero-delay chunks |
| User submits while streaming | Queued or prevented, no duplicate messages | Send message <500ms after previous |

### Vercel AI SDK `useChat` Checks

- `isLoading`: false → true on submit → false on completion/error
- `error`: set correctly on non-2xx status or mid-stream throw
- `stop()`: aborts fetch, sets isLoading false, no ghost empty message in UI
- Messages array: assistant message appended optimistically, hydrated as chunks arrive

### Streaming Performance

- **TTFT** (time-to-first-token): >2000ms is a UX problem
- **Chunk delivery jitter**: gaps >1500ms create jarring experience
- **CLS**: component blocks popping in mid-stream push text down — measure layout shift

## Session Persistence Testing

### sessionStorage-Specific Failure Modes

| Action | Expected | Test |
|--------|----------|------|
| F5 refresh | History preserved | Verify all messages visible |
| Close tab + reopen | Session cleared | Verify empty conversation |
| Duplicate tab (Ctrl+D) | Independent session | Verify Tab B starts fresh |
| Browser back button | History preserved | Messages intact |
| Long inactive session (2h+) | May expire gracefully | No JS error, clean empty state |

### Session Isolation Test (Critical)
1. Tab A: start conversation about Topic 1
2. Tab B: start conversation about Topic 2
3. Verify Tab A not polluted by Tab B
4. Send message in Tab B triggering component block
5. Switch to Tab A — verify state unchanged

### Memory Context Tests
- Turn 1: state a fact. Turn 5: ask question requiring that context → AI should reference it
- Refresh page → send follow-up → AI should still have Turn 1 context (history sent with request)
- Clear conversation → send message → AI should NOT remember prior context

### Conversation Reset
- Clear MUST clear sessionStorage (verify with devtools)
- Clear button hidden/disabled while streaming
- Post-clear message treated as fresh start (no stale history sent)

## Bilingual / i18n Testing

### Icelandic Character Hazards

| Character | What Breaks |
|-----------|------------|
| Þ/þ (Thorn) | Regex `[A-Z]`/`[a-z]` patterns miss it → name validation fails |
| Ð/ð (Eth) | Collation sorting puts it in wrong position |
| á/é/í/ó/ú/ý/ö/æ | URL encoding, form encoding, storage encoding issues |
| Long names (Guðmundur Sigurðarson) | 25+ chars break fixed-width layouts |

### Test Inputs for Icelandic
```
"Þórunn Eiríksdóttir"          — thorn + accented vowels
"Ólafur Björnsson"              — accented O + special chars
"þ"                              — single thorn (search field)
"Í dag er góður dagur"          — accented I at start
"Guðmundur Magnússon Sigurðsson" — multiple special chars + long
```

### Language Switch Mid-Conversation
1. Set UI to Icelandic
2. Complete 2-3 turns in Icelandic
3. Switch UI to English
4. Send message in English
5. Assert: AI responds in English
6. Assert: Prior messages stay in Icelandic
7. Assert: UI chrome (buttons, labels) switches to English
8. Assert: New component blocks display in English

**Common bug**: System prompt sets language once on session start but doesn't update on switch.

### Text Overflow Stress Test

Icelandic words are often 30-50% longer. Test with longest translations:
- Navigation labels: overflow or awkward wrap?
- Button text: expand, clip, or wrap?
- Card titles: long Icelandic titles in constrained widths
- Error messages: Icelandic errors tend to be longer — fit in toast containers?

### Locale Formatting

| Format | English (en-US) | Icelandic (is-IS) |
|--------|-----------------|-------------------|
| Date | December 15, 2025 | 15. desember 2025 |
| Short date | 12/15/2025 | 15.12.2025 |
| Number | 1,234.56 | 1.234,56 |

Verify AI-generated numbers in component blocks use locale-appropriate formatting.

## Cross-Boundary Contract Testing

### The Component Block End-to-End Chain

Each step can fail independently:
```
LLM generates text       → JSON syntax error, wrong fields, wrong block type
Stream delivers chunks    → delimiter split, buffering race
Parser extracts block     → regex too strict/lenient, nested braces
JSON validated            → missing required fields, wrong types, null
React component renders   → crashes on unexpected props, missing handling
User interacts            → click handlers broken, navigation fails
```

Write at least one test for each step. Most commonly untested: first (schema errors from LLM) and last (user interaction with rendered component).

## External API Resilience

### Timeout Chain
```
Browser fetch (30s) → API route/Lambda (30s) → AgentCore (?) → Bedrock (60s+)
```
If inner layer is slower than outer layer's timeout → user sees generic error.

### What to Verify
- Each error source (LiteLLM 429, Bedrock throttle, network error) produces a distinct user-facing message
- Frontend fetch uses AbortController — navigating away cancels the request
- No double-retry (only one layer retries, retries are idempotent)
- Empty results from external APIs handled gracefully (empty state, not error)
