# Google Gemini System Prompt Guidance

## System Instruction Architecture

Gemini uses `system_instruction` as a separate API field, not embedded in messages. This affects caching strategy: system instructions can be part of an explicit cache object with configurable TTL.

## Minimal Prompting

Gemini 3 "picks up structure from a small cue" — elaborate formatting is increasingly unnecessary. Direct, minimal formatting with a clear goal statement often outperforms verbose structured prompts. Prompts that were "safe" for Gemini 2.x feel like overkill for 3.x.

Google's official framework: **PTCF** (Persona, Task, Context, Format).

## Out-of-Domain Persona Refusal

**Unique failure mode:** Out-of-domain expert personas cause Gemini to REFUSE TO ANSWER. In testing, Gemini 2.5 Flash refused an average of 10.56 out of 25 trials per question when given an out-of-domain expert persona. This is not observed in Claude or GPT.

**Rule:** If using personas on Gemini, ensure the persona domain matches the task domain exactly.

## Caching — Storage Costs

Gemini is the only major provider that charges for storing cached content (fixed TTL cost, separate from read/write). For low-frequency use cases with large system prompts, explicit caching may INCREASE total cost compared to no caching.

**Cache types:**
- **Implicit:** Automatic for Gemini 2.5+ models, no markup needed
- **Explicit:** Requires cache object creation, configurable TTL (default 1 hour), storage charged

Calculate break-even request frequency before enabling explicit Gemini caching.

## Structured Output

`responseSchema` parameter enforces strict JSON output at the API level (equivalent to OpenAI's Structured Outputs). `tool_choice` allow-list restricts Gemini to approved functions.

## Thought Signatures

Encrypted representations of Gemini's internal reasoning state, preserved across multi-turn function calling. Teams cannot inspect or modify these — they are opaque infrastructure. Do not attempt to parse or reference them.

## Tone Mirroring

Gemini prioritizes natural conversation through "mirroring" — adjusting tone to match user style. This can create sycophancy unless explicitly countered.

## Multimodal Strength

Gemini has the strongest multimodal reasoning and large-context handling among major providers. For tasks involving image/video/audio analysis combined with text, Gemini-specific prompting can leverage these strengths.
