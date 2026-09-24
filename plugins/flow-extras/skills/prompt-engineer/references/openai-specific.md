# OpenAI GPT-4/5 System Prompt Guidance

## The Developer Role

In the new Responses API, the `developer` role replaced `system` with explicit higher trust than user messages. Teams porting from the Completions API must update role naming.

## GPT-5 Behavioral Shifts

GPT-5 is "extraordinarily receptive to prompt instructions" with "surgical accuracy" — meaning:
- Contradictions are MORE costly than on earlier models (wastes reasoning tokens reconciling conflicts)
- Less defensive hedging needed compared to GPT-4
- Instructions that worked on GPT-4 ("be thorough," "maximize context gathering") cause **overuse of tools** on GPT-5 — these must be removed or inverted
- Metaprompting works: asking GPT-5 what additions/deletions would fix undesired behaviors produces useful refinements

## Structured Outputs

`response_format: {type: "json_schema"}` provides schema-enforced JSON output. This completely supersedes any "respond in JSON" instruction in the system prompt. Teams still writing JSON-enforcement instructions when using Structured Outputs are wasting tokens.

## Format Preferences

- GPT-4: Markdown works best
- GPT-3.5: JSON structure works best (up to 40% performance variation based on format alone)
- GPT-4 can show 300%+ improvement switching from JSON to plain text for certain tasks
- Defaults to plain text for API; requires explicit Markdown instruction if desired

## Prompt Caching

Automatic prefix caching — enabled by default for prompts ≥ 1,024 tokens:
- No explicit markup required
- Cache duration: 5-10 min active, up to 1 hour off-peak
- Cached tokens don't count against ITPM rate limits
- Read discount: ~50% of base input price
- Structure: static content first, dynamic content last (invariant prefix requirement)

## Multi-Message Architecture

A pre-flight message + actual query (two separate developer messages) is more effective than a single combined prompt on GPT-5. Use the first message for identity/constraints, the second for task-specific context.

## The Sycophancy Lesson

GPT-4o's April 2025 rollback was caused by a single system prompt instruction: "match the users vibe, tone, and generally how they are speaking." This caused model-wide sycophantic behavior.

**Rule:** Never include tone-matching or agreeableness instructions without explicit anti-sycophancy constraints: "Prioritize accuracy over agreeableness. Do not agree with user statements by default."

## Reasoning Models (o3/o4-mini)

- "Think step by step" DECREASES performance — the model's internal reasoning is managed by API parameters
- Few-shot examples also impair reasoning models — they constrain internal reasoning
- System prompt role shifts to: scope definition, constraints, output format only
- Do not prescribe reasoning chains
