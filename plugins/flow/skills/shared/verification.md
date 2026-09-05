---
name: verification
description: Reusable verification workflow — debug log injection with [VERIFY] prefix, dev server lifecycle, tiered browser verification (quick/standard/full), user confirmation, and cleanup
---

# Verification Workflow

Handles verification for both feature development and bug fixes. Uses project environment from `project-detection.md` and browser commands from `agent-browser-reference.md`.

## Prerequisites

- Project detection complete — you need `DEV_CMD`, `TEST_CMD`, `LINT_CMD`, `FORMAT_CMD`, `TYPECHECK_CMD`
- Load `agent-browser-reference.md` only if this tier requires browser work (standard/full for UI changes)

## Step 1: Debug Log Injection

Add temporary debug logs prefixed with `[VERIFY]` at key code paths to confirm the new/fixed code is actually reached.

Convention: `[VERIFY] feature-name: what this confirms` — use the language's standard logging mechanism. The `[VERIFY]` prefix is what matters for cleanup, not the logging function.

Place logs at: entry points of new/modified functions, branch conditions the feature/fix should trigger, state changes that should occur.

## Step 2: Dev Server Lifecycle

**Starting**: If `.claude/scripts/start-dev-server.sh` exists, use it (parse JSON output for port/pid). Otherwise run `$DEV_CMD` in background. Store port as `$PORT`.

**Stopping**: If `.claude/scripts/stop-dev-server.sh` exists, use it. Otherwise kill the background process.

**If dev server won't start**: Check if the port is already in use (`lsof -i :$PORT`). Check for missing env vars or dependencies. Report to user if unresolvable.

## Step 3: Verification Tiers

### Quick (small features / backend-only / infrastructure bugs)

If no UI changes:
- Skip browser entirely
- Run `$TEST_CMD` to confirm tests pass
- Check server logs for `[VERIFY]` lines if a server is running
- Done

If minor UI changes:
```bash
agent-browser open http://localhost:$PORT && agent-browser wait --load networkidle
agent-browser snapshot -i && agent-browser screenshot ./verify-quick.png
agent-browser console && agent-browser close
```

### Standard (medium features / frontend/integration bugs)

1. **Functional check**: Navigate to the feature/fix area, interact with it, verify expected behavior. Screenshot.
2. **Console check**: `agent-browser console` — no errors or warnings
3. **Accessibility snapshot**: `agent-browser snapshot` — semantic HTML, ARIA labels present
4. Close browser

### Full (large features)

1. **Functional check**: Exercise all major code paths, not just the happy path
2. **Responsive review** — 3 viewports (desktop 1280x720, tablet 768x1024, mobile 375x812). Screenshot each.
3. **Console check**: No errors across all viewports
4. **Accessibility audit**: Semantic structure, focus management, keyboard navigation
5. **UX quality check**: No overlaps, proper spacing, consistent typography, clear hover/focus states, adequate touch targets, loading/error states present
6. **Audit report**: Create `.claude/verification-audit.local.md` with findings
7. **Fix issues** found in audit, re-verify affected areas

## Step 4: User Confirmation

**If `--skip-verification`**: Check server logs for `[VERIFY]` lines, rely on test results, proceed to cleanup.

**Otherwise**: Present screenshots, console output, audit findings (if full tier), and dev server URL. Ask: "Does this look correct?" Fix reported issues, re-verify, wait for approval.

## Step 5: Cleanup

1. **Remove debug logs**: Search for `[VERIFY]` strings across all source files, remove those lines
2. **Stop dev server**
3. **Remove artifacts**: `rm -f ./verify-*.png ./bug-before.png ./bug-after.png .claude/verification-audit.local.md`
4. **Run CI checks**: `$LINT_CMD`, `$FORMAT_CMD`, `$TYPECHECK_CMD`, `$TEST_CMD` — fix any failures from cleanup
5. **Commit**: `chore: remove verification artifacts`
