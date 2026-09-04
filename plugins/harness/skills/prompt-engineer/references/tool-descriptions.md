# Tool Description Engineering

Tool descriptions are the most underinvested, highest-leverage part of agent system prompt design. Anthropic's SWE-bench team reported spending more time optimizing tools than the overall prompt.

## Why Tool Descriptions Matter More Than System Prompts

- 73% of agent failures in audited systems stem from incorrect tool usage
- Tool description improvements alone yielded **40% decrease in task completion time** (Anthropic)
- A single missing constraint in a search tool description ("don't append the year to queries") caused measurable benchmark regression
- Doubling the tool-call budget (10→100) improved accuracy by only 0.2 percentage points — the tool DESCRIPTIONS matter, not the number of calls

## Anatomy of an Expert Tool Description

```json
{
  "name": "search_codebase",
  "description": "Search the project codebase for code patterns, function definitions, class references, and string literals. Use FIRST for any code-related query — prefer over search_web for technical documentation that may exist locally. Returns matching file paths with line numbers and surrounding context. Do NOT use for: binary files, node_modules, or build artifacts (these are excluded by default).",
  "parameters": {
    "query": {
      "type": "string",
      "description": "Search pattern. Supports regex. Examples: 'function handleAuth', 'class.*Repository', 'TODO|FIXME'. Keep queries short and specific — broad queries return too many results."
    },
    "file_type": {
      "type": "string",
      "description": "Optional file extension filter. Examples: 'ts', 'py', 'rs'. Omit to search all text files.",
      "optional": true
    }
  }
}
```

### What Makes This Description Work

1. **WHEN to use it** — "Use FIRST for any code-related query"
2. **WHEN NOT to use it** — "Do NOT use for: binary files, node_modules"
3. **Disambiguation** — "prefer over search_web for technical documentation"
4. **Parameter guidance** — "Keep queries short and specific" prevents the common failure of overly broad searches
5. **Examples** — Concrete parameter examples prevent hallucinated parameter formats

## Tool Disambiguation Pattern

When an agent has multiple tools that could plausibly handle the same input, explicit disambiguation is critical:

```
Available tools and selection logic:
- search_web: Current events, recent data, or when no local knowledge exists
- search_codebase: FIRST choice for any code query; prefer over web for technical docs
- read_file: Use when you have an exact file path; NEVER for discovery
- list_directory: Discovery when path structure is unknown; use before read_file
```

## Minimal Viable Toolsets

Too many tools create ambiguous decision points:
- **3-5 tools per agent**: Optimal. Clear selection logic.
- **6-10 tools**: Acceptable with explicit disambiguation.
- **15+ tools**: Agents choose wrong tools systematically. Split into specialized sub-agents.

## Hidden Token Cost

Every `tools` API call to Claude injects a hidden system prompt of 313-530 tokens BEFORE your system prompt:
- Opus/Sonnet 4.6 with `tool_choice: auto/none`: **346 tokens**
- Opus/Sonnet 4.6 with `tool_choice: any/tool`: **313 tokens**
- Haiku 3.5 with `any/tool`: **340 tokens**

Budget your effective system prompt accordingly — these tokens are invisible but real.

## Tool Result Design

Tools should return minimal, relevant data — not everything available:
- Return only fields needed for the model's next decision
- Use semantic identifiers (human-readable names) instead of UUIDs — reduces hallucination significantly
- Target ~65% token efficiency (tokens returned / tokens useful)
- Absolute file paths eliminate a class of errors vs relative paths

## Self-Improving Tool Descriptions

An advanced pattern: use an LLM to test tools dozens of times, observe failures, and rewrite descriptions based on observed error patterns. This produces better descriptions than human authoring because it captures actual failure modes rather than anticipated ones.
