# QA Checklists

Quick-reference checklists for each QA dimension. Use during synthesis to verify no category was missed.

## Master Checklist — Before Signing Off

```
SHIP-BLOCKER CHECK:
[ ] No critical bugs found (or all critical bugs have fixes)
[ ] No security vulnerabilities (XSS, injection, auth bypass)
[ ] No data loss scenarios
[ ] All error states handled gracefully (no blank pages, no 500s)
[ ] Core user workflows complete successfully

SHOULD-FIX CHECK:
[ ] All form validations work correctly
[ ] Error messages are helpful and accurate
[ ] Loading states exist for async operations
[ ] No console errors in browser
[ ] Responsive layout works at major breakpoints

NICE-TO-FIX CHECK:
[ ] Accessibility basics pass (keyboard nav, focus, alt text)
[ ] Performance is acceptable (no obvious slowness)
[ ] Edge cases handled (empty states, boundary values)
[ ] No unnecessary network requests
```

## Code Analysis Checklist

```
LOGIC:
[ ] Conditionals use correct operators (=== not ==, >= not >)
[ ] Loop boundaries are correct (no off-by-one)
[ ] Null/undefined handled at external boundaries
[ ] Async operations have proper error handling
[ ] Race conditions addressed (concurrent writes, stale closures)

ERROR HANDLING:
[ ] No empty catch blocks
[ ] Errors not silently swallowed
[ ] User-facing error messages are helpful
[ ] Error state doesn't leave app in broken state
[ ] Retry logic exists for transient failures

SECURITY:
[ ] No unsanitized user input in HTML rendering
[ ] No string concatenation in SQL/shell commands
[ ] No hardcoded secrets
[ ] Auth checks present on sensitive endpoints
[ ] Input validation at system boundaries
```

## Browser Testing Checklist

```
FUNCTIONAL:
[ ] Page loads without errors
[ ] All interactive elements respond to clicks
[ ] Forms validate and submit correctly
[ ] Navigation works (links, buttons, back button)
[ ] Data displays correctly (matches API response)

ERROR STATES:
[ ] Invalid form input shows error message
[ ] Failed API calls show error state (not blank page)
[ ] 404/not-found routes handled
[ ] User can recover from error (retry, fix input)
[ ] Loading indicators appear during async operations

EDGE CASES:
[ ] Empty state handled (no data)
[ ] Special characters in inputs (unicode, HTML, quotes)
[ ] Very long text doesn't break layout
[ ] Double-click on submit doesn't create duplicates
[ ] Back button doesn't break state
```

## Accessibility Checklist

```
KEYBOARD:
[ ] All interactive elements reachable via Tab
[ ] Tab order is logical (left-to-right, top-to-bottom)
[ ] Focus indicator visible on all focused elements
[ ] Enter/Space activates buttons and links
[ ] Escape closes modals/dropdowns
[ ] Focus trapped inside open modals

SEMANTIC HTML:
[ ] Heading hierarchy correct (h1 → h2 → h3)
[ ] Form inputs have associated labels
[ ] Images have meaningful alt text (or role="presentation")
[ ] Buttons used for actions, links for navigation
[ ] Lists use ul/ol, not div soup

ARIA:
[ ] Icon-only buttons have aria-label
[ ] Dynamic content has aria-live regions
[ ] Custom components have appropriate roles
[ ] Required fields marked with aria-required
```

## Security Checklist

```
INPUT:
[ ] All user input sanitized before rendering
[ ] Server-side validation (not just client-side)
[ ] File upload restrictions (type, size)
[ ] No eval() or new Function() with user input

AUTH:
[ ] Protected routes require authentication
[ ] Authorization checks on sensitive operations
[ ] Tokens stored securely (httpOnly cookies > localStorage)
[ ] Session expiry handled gracefully

DATA:
[ ] No secrets in source code
[ ] No sensitive data in client-side storage
[ ] HTTPS enforced
[ ] Appropriate CORS configuration
[ ] Security headers present (CSP, X-Frame-Options)
```

## Edge Case Test Data

Use these values to stress-test inputs:

```
STRINGS:
- "" (empty)
- " " (whitespace only)
- "   leading/trailing spaces   "
- "null"
- "undefined"
- "true" / "false"
- "<script>alert(1)</script>"
- "Robert'); DROP TABLE students;--"
- "🎉🔥💀" (emoji)
- "مرحبا" (RTL text)
- "漢字" (CJK)
- "a".repeat(10000) (very long)
- String with newlines: "line1\nline2"
- String with tabs: "col1\tcol2"

NUMBERS:
- 0, -0, -1
- 0.1 + 0.2 (float precision)
- Number.MAX_SAFE_INTEGER + 1
- Infinity, -Infinity, NaN
- "123" (string that looks like number)

EMAILS:
- "test@test" (valid RFC but commonly rejected)
- "test+tag@gmail.com" (valid, often breaks)
- "user@subdomain.example.com"
- "@missing-local.com"
- "spaces in@email.com"

DATES:
- 2024-02-29 (leap year)
- 2025-02-29 (NOT a leap year)
- 2024-12-31 (year boundary)
- timezone-sensitive dates
```

## Report Quality Checklist

Before finalizing the QA report:

```
[ ] Verdict is clear: PASS / PASS WITH NOTES / FAIL
[ ] Every ship-blocker has reproduction steps
[ ] Every issue has file:line or browser evidence
[ ] "Passed Checks" section is populated (what was tested and clean)
[ ] "Not Tested" section explains gaps
[ ] Screenshots linked for visual issues
[ ] No vague issues ("something seems off" → specify what)
[ ] Suggested fixes included where obvious
[ ] Severity levels are honest (don't inflate or minimize)
```
