---
name: e2e-testing
description: Expert-level Playwright E2E testing guidance — what to test, what to avoid, common pitfalls that cause flaky tests, and project integration patterns. Assumes Claude already knows Playwright basics.
---

# E2E Testing with Playwright

Check if the project has its own `/e2e` command, skill, or test conventions first — always follow project patterns over these generic guidelines.

## What to Test in E2E

- Page/component renders correctly with mocked data
- User can interact with the feature (click, type, navigate)
- Expected outcomes after interaction (content appears, URL changes, state updates)
- Error states handled gracefully (API failures, empty data)
- Navigation flows work end-to-end

## What NOT to Test in E2E

- Component rendering logic in isolation (unit tests)
- Utility function behavior (unit tests)
- State management internals
- Third-party service availability
- Exact pixel-level styling (visual regression tools)

## Critical Patterns

**Mock BEFORE navigating** — set up `page.route()` before `page.goto()`. Pages load with real (or missing) data if mocks arrive late.

**Use auto-retrying assertions** — `await expect(locator).toBeVisible()` retries automatically. `expect(await locator.isVisible()).toBe(true)` evaluates once and is inherently flaky.

**Import from project fixtures** — use `import { test, expect } from "./fixtures"` not `@playwright/test`. Project fixtures provide mock helpers, auth setup, and other shared context.

**Clear stale mocks** — when re-mocking within a test, call `page.unrouteAll({ behavior: "ignoreErrors" })` first.

**Prefer role-based selectors** — `getByRole` > `getByLabel`/`getByText` > `getByTestId` > CSS selectors. Use `exact: true` when names overlap ("Like" vs "Dislike"). Use `.first()` / `.nth(n)` when multiple elements match.

## Common Pitfalls

1. **Mocks after navigation** — page loads with real data, then mocks kick in too late
2. **Non-retrying assertions** — `expect(await ...)` evaluates once; always use `await expect(...)`
3. **Ambiguous selectors** — "Submit" matches "Submit Form"; use `exact: true` or more specific locators
4. **Fixed timeouts** — `waitForTimeout(3000)` is flaky and slow; use locator waits or `waitForResponse()`
5. **Testing implementation details** — verify user-visible behavior, not internal state or CSS classes
6. **Stale route handlers** — forgetting `unrouteAll()` before re-mocking causes mysterious failures

## File Organization

```
e2e/
├── fixtures/index.ts    # Custom fixture with mockApi and helpers
├── helpers/*.ts          # Shared interaction helpers (login, sendMessage, etc.)
└── *.spec.ts             # One per feature area
```

After writing tests: run the project's E2E command, prefer `test.skip` with a comment over fragile workarounds for flaky tests, keep tests independent with their own mocks and state.
