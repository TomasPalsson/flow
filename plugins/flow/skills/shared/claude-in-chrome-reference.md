---
name: claude-in-chrome-reference
description: Shared claude-in-chrome MCP quick reference — tool loading, tab workflow, interaction primitives, and critical rules for in-browser automation via the Claude Chrome extension
---

# claude-in-chrome MCP Reference

claude-in-chrome is an **MCP server** backed by the Claude Chrome extension. It drives the user's real Chrome window — the one they are sitting in front of. It is NOT a CLI, NOT Playwright, NOT chrome-devtools-mcp. You call it as tool calls, not shell commands.

## Tool Loading (required every session)

claude-in-chrome tools are **deferred** — they appear by name but have no schema until loaded. Before the first call, run:

```
ToolSearch query="select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__find,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__form_input,mcp__claude-in-chrome__read_console_messages,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__javascript_tool"
```

Add `gif_creator`, `read_network_requests`, `resize_window`, `get_page_text` if the verification plan needs them. Calling a tool without loading it first returns `InputValidationError`.

## Core Workflow

```
tabs_context_mcp              → snapshot current window: see existing tabs, pick or create
tabs_create_mcp(url=...)      → open a new tab for verification (prefer this — do NOT hijack user tabs)
navigate(url=...)             → move the active tab to a URL
read_page                     → accessibility snapshot with element refs for interaction
find(query="Submit button")   → locate an element by description, returns a ref
computer(action, ref, ...)    → click / type / scroll against a ref
form_input(ref, value)        → fill a single input (use javascript_tool for long text — types char-by-char)
read_console_messages          → check JS errors; pass `pattern` to filter (e.g. "[MyApp]")
javascript_tool(code=...)     → evaluate JS in the page (use `document.querySelector(...).value = "..."` for long strings)
resize_window(w, h)           → responsive-mode verification
gif_creator                   → record multi-step flows for later review
```

## Critical Rules

1. **ALWAYS call `tabs_context_mcp` first.** Never reuse a tab id from a previous session or another conversation — ids are per-session. If a later call errors with "tab does not exist," re-run `tabs_context_mcp` and pick a fresh id.
2. **Prefer a new tab over reusing an existing one.** Only operate on an existing tab if the user explicitly says so — the user may be mid-task in their other tabs.
3. **Never trigger `alert` / `confirm` / `prompt` or native file dialogs.** These freeze the extension and no further commands land until the user dismisses manually. If a button might trigger one, warn first or use `javascript_tool` to intercept.
4. **For long-form inputs, set `.value` via `javascript_tool`.** `form_input` and `computer` type character by character and may time out.
5. **Refs are transient.** After a navigation, click, or form submission, re-run `read_page` / `find` before interacting again.
6. **Bail out fast.** If a tool call fails 2–3 times, stop and surface the error — do not loop. The extension is a live system with a real user behind it.

When instructions say "use claude-in-chrome" or "Browser Verification via claude-in-chrome," it means: load the MCP tools above, then drive verification through tool calls (not bash).
