# Open-Source Model System Prompt Guidance

## Chat Templates Are Mandatory and Model-Specific

Each fine-tuned variant expects a specific token sequence. Wrong delimiters cause silent instruction-ignoring.

| Model Family | System Prompt Format | Delimiter |
|---|---|---|
| Llama 2 Chat | Inside `[INST]` block with `<<SYS>>`/`<</SYS>>` | `<s>`, `</s>` |
| Llama 3 | `<|begin_of_text|>` + `<|start_header_id|>system<|end_header_id|>` | Model-specific |
| Mistral | Inside `[INST]`/`[/INST]` block | `<s>`, `</s>` (differs from Llama) |
| ChatML variants | `<|im_start|>system\n...<|im_end|>` | OpenAI-style |

**Critical:** ChatML format is used by many community fine-tunes but is NOT the default for base Llama/Mistral. Assuming ChatML compatibility without checking the model card is a common production bug.

**Always use `apply_chat_template()`** from the Hugging Face tokenizer — it encodes the correct template programmatically.

## No Trust Hierarchy

Unlike hosted providers, open-source models have no architectural separation between operator and user authority. The system prompt is just more text concatenated before the user message. There is no trained bias giving system instructions higher weight.

**Implication:** System prompt constraints are easier to override via user messages on open-source models. Defense-in-depth (output validation, guardrails) is more important than with hosted APIs.

## Placement Matters

Some fine-tunes expect the system prompt inside `[INST]`, others before it. Incorrect placement causes instruction-ignoring with no error signal. Always check the model card.

## Format Preferences

Plain text or minimal Markdown is safest. Open-source models don't have strong training signal for XML parsing (unlike Claude). Avoid complex structural formatting unless the specific model's training data includes it.

## Older Models Without System Role

Some older fine-tunes have no concept of a "system" role. Passing a system message causes it to be ignored or concatenated incorrectly. Verify role support before deployment.
