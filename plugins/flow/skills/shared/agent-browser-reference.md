---
name: agent-browser-reference
description: Shared agent-browser CLI quick reference — core commands, viewport control, waiting patterns, and critical rules for browser automation
---

# agent-browser CLI Reference

> If the project has its own full agent-browser skill installed locally under `.claude/skills/`, read that skill's SKILL.md first for complete command reference, patterns, and examples.

agent-browser is a **command-line tool** you run via the Bash tool. It controls a real Chrome browser.
It is NOT a library, NOT an MCP server, NOT Playwright. You call it as shell commands.

## Quick Reference

```bash
# Core workflow: open → snapshot → interact → re-snapshot
agent-browser open http://localhost:$PORT         # Navigate to URL
agent-browser wait --load networkidle             # Wait for page to load
agent-browser snapshot -i                         # Get interactive elements with refs (@e1, @e2...)
agent-browser click @e1                           # Click an element by ref
agent-browser fill @e2 "text"                     # Clear and type into input
agent-browser select @e3 "option"                 # Select dropdown option
agent-browser press Enter                         # Press a key
agent-browser screenshot ./screenshot.png         # Take screenshot
agent-browser screenshot --full                   # Full page screenshot
agent-browser screenshot --annotate               # Screenshot with numbered labels on elements
agent-browser console                             # Check for JS errors/warnings
agent-browser get text @e1                        # Get element text content
agent-browser get url                             # Get current URL
agent-browser close                               # Close browser when done

# Viewport for responsive testing
agent-browser set viewport 1280 720               # Desktop (default)
agent-browser set viewport 375 812                # Mobile
agent-browser set viewport 768 1024               # Tablet

# Waiting
agent-browser wait @e1                            # Wait for element to appear
agent-browser wait --text "Welcome"               # Wait for text
agent-browser wait "#spinner" --state hidden       # Wait for element to disappear
agent-browser wait --url "**/dashboard"            # Wait for URL pattern

# Diffing
agent-browser diff screenshot --baseline ./before.png  # Highlights changed pixels in red
```

## Critical Rules

1. **Refs are ephemeral**: `@e1`, `@e2` etc. are INVALIDATED after ANY page change. Always `snapshot -i` again after clicking, submitting, or navigating.
2. **Always wait after navigation**: Use `wait --load networkidle` after `open`, `click` (on links), or form submissions.
3. **Chain when possible**: Use `&&` to chain commands that don't need intermediate output parsing.
4. **Close when done**: Always `agent-browser close` when finished to avoid leaked Chrome processes.

When instructions say "use agent-browser", it means: run these CLI commands via the Bash tool.
