# Browser QA Workflows

Specific patterns for testing web applications through the browser. These are the code-to-browser verification loops that make browser QA effective.

## Core Loop: Read Code → Predict → Verify → Compare

### Pattern 1: Form Handler Verification

```bash
# 1. Read the form component to understand validation rules
# 2. Open the form
agent-browser open http://localhost:3000/form-page
agent-browser wait --load networkidle
agent-browser snapshot -i

# 3. Test happy path
agent-browser fill @e1 "Valid Name"
agent-browser fill @e2 "user@example.com"
agent-browser click @e3  # Submit
agent-browser wait --load networkidle
agent-browser snapshot -i  # Verify success state

# 4. Test validation — submit empty form
agent-browser open http://localhost:3000/form-page
agent-browser wait --load networkidle
agent-browser snapshot -i
agent-browser click @e3  # Submit without filling
agent-browser snapshot -i  # Verify error messages appear
# VERIFY: Error messages match what the code defines

# 5. Test edge cases
agent-browser fill @e1 "<script>alert(1)</script>"
agent-browser fill @e2 "not-an-email"
agent-browser click @e3
agent-browser snapshot -i  # Verify proper validation
```

### Pattern 2: API Integration Verification

```bash
# 1. Read the API route to understand expected request/response
# 2. Navigate to the page that calls this API
agent-browser open http://localhost:3000/dashboard
agent-browser wait --load networkidle

# 3. Monitor network while performing action
agent-browser network requests --method POST
# Verify: correct endpoint called, correct payload shape

# 4. Check response handling
agent-browser snapshot -i
# Verify: displayed data matches API response
# Check: loading state appeared during request
# Check: error handling if API returns error
```

### Pattern 3: Authentication Flow Verification

```bash
# 1. Test protected route without auth
agent-browser open http://localhost:3000/dashboard
agent-browser wait --load networkidle
agent-browser get url
# Verify: redirected to login page

# 2. Test login flow
agent-browser snapshot -i
agent-browser fill @e1 "user@test.com"
agent-browser fill @e2 "password"
agent-browser click @e3  # Login button
agent-browser wait --url "**/dashboard"
agent-browser snapshot -i
# Verify: dashboard content visible

# 3. Test invalid credentials
agent-browser open http://localhost:3000/login
agent-browser wait --load networkidle
agent-browser snapshot -i
agent-browser fill @e1 "user@test.com"
agent-browser fill @e2 "wrongpassword"
agent-browser click @e3
agent-browser snapshot -i
# Verify: error message visible, form not cleared, no redirect
```

### Pattern 4: Error State Verification

```bash
# Use network route blocking to simulate API failure
agent-browser network route "**/api/data" --abort
agent-browser open http://localhost:3000/page-that-needs-api
agent-browser wait --load networkidle
agent-browser snapshot -i
# Verify: error message shown, not blank page
# Verify: retry button available
# Verify: no unhandled exception in console

# Test recovery: remove the block and retry
agent-browser network route "**/api/data"  # Remove block
# If there's a retry button, click it
agent-browser snapshot -i
# Verify: data loads correctly after retry
```

### Pattern 5: Responsive Testing Quick Pass

```bash
# Desktop
agent-browser set viewport 1280 720
agent-browser open http://localhost:3000/page
agent-browser wait --load networkidle
agent-browser screenshot .qa-report/screenshots/desktop.png

# Tablet
agent-browser set viewport 768 1024
agent-browser screenshot .qa-report/screenshots/tablet.png

# Mobile
agent-browser set viewport 375 812
agent-browser screenshot .qa-report/screenshots/mobile.png

# Check for horizontal overflow at each viewport
agent-browser eval 'document.documentElement.scrollWidth > document.documentElement.clientWidth'
# If true → horizontal scrollbar exists → likely a responsive bug
```

### Pattern 6: Network Monitoring During Workflows

```bash
# Start monitoring
agent-browser open http://localhost:3000/page
agent-browser wait --load networkidle

# Perform user workflow...
agent-browser click @e1
agent-browser wait --load networkidle

# Check for issues
agent-browser network requests --type xhr,fetch
# Look for:
# - Same endpoint called multiple times (duplicate fetches)
# - 4xx/5xx responses that UI silently swallowed
# - Unexpectedly large responses (>500KB for JSON API)
# - Requests to unexpected domains (third-party tracking?)
# - Missing authorization headers on authenticated endpoints
```

## Assertion Patterns — Verify Content, Not Existence

```bash
# BAD: Only checks element exists
agent-browser snapshot -i  # "I see @e5 exists" ← useless

# GOOD: Verify actual content
agent-browser get text @e5  # Get the actual text
# Compare against expected value from the code/API

# GOOD: Verify state change after action
agent-browser snapshot -i  # Before state
agent-browser click @e3
agent-browser wait --load networkidle
agent-browser diff snapshot  # What changed?
# Verify: expected elements added/removed/changed

# GOOD: Verify computed values
agent-browser eval 'document.querySelector("[data-total]").textContent'
# Compare against expected calculation
```

## Error Recovery Testing Pattern

After EVERY error scenario:

```bash
# 1. Trigger error
agent-browser fill @e1 "invalid-data"
agent-browser click @e2  # Submit
agent-browser snapshot -i
# Verify: error message visible

# 2. Verify recovery
agent-browser fill @e1 "valid-data"  # Fix the input
agent-browser click @e2  # Submit again
agent-browser wait --load networkidle
agent-browser snapshot -i
# Verify: success state reached
# Verify: no stuck error message
# Verify: form accepted the correction
```

## When to Screenshot vs Snapshot

| Situation | Use Snapshot | Use Screenshot |
|-----------|-------------|---------------|
| Check text content | Yes | No |
| Check element existence | Yes | No |
| Check visual layout | No | Yes |
| Check responsive behavior | No | Yes |
| Verify form values | Yes | No |
| Check colors/styling | No | Yes |
| Check overlapping elements | No | Yes |
| Verify accessibility tree | Yes | No |
| Document evidence for report | Maybe | Yes |
