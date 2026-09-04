---
name: qa
description: "Use WHENEVER the user asks to: QA, test, verify, 'does this work?', 'check for bugs', 'is this ready to ship?', 'qa this', 'test this feature', 'run quality checks', 'do a QA pass', 'qa branch X', check accessibility, audit security, find edge cases, review code quality, /qa, /qa <branch>, or any request for quality assurance, testing, or verification. Accepts a branch name as argument — checks out the branch, sets up the environment, runs parallel QA agent swarms (code analysis, live browser testing via agent-browser, accessibility, security, performance, edge cases), presents findings, then offers the user a live browser session to manually verify."
---

# QA — Agent Swarm Quality Assurance

Deploy parallel specialist agents to perform comprehensive QA: code analysis, live browser testing, accessibility auditing, security scanning, and edge case hunting. Produces a structured, actionable QA report. Then hands the user a live browser session for manual verification.

## Step 0: Branch Setup

If the user provides a branch name (e.g., `/qa feature/auth-redesign`):

1. **Stash and checkout**: Save any current work, switch to the target branch
   ```bash
   git stash --include-untracked 2>/dev/null
   git checkout <branch>
   git pull origin <branch>
   ```
2. **Detect changes**: Diff against the base branch to identify what changed
   ```bash
   git diff --name-only main...<branch>  # Changed files
   git diff --stat main...<branch>       # Change summary
   git log --oneline main...<branch>     # Commit history
   ```
3. **Start the dev server**: Detect the start command and launch it in the background
   - Check `package.json` scripts for `dev`, `start`, `serve`
   - Check for `Makefile`, `docker-compose.yml`, or framework-specific configs
   - Run the start command in background: `npm run dev &` (or equivalent)
   - Wait for the server to be ready: poll `curl -s -o /dev/null -w "%{http_code}" http://localhost:<port>` until it returns 200
   - If dependencies need installing (new packages in lockfile diff), run `npm ci` / `pip install -r requirements.txt` first
4. **Capture setup context**: Record the app URL, branch name, base branch, and changed files for the QA agents

If NO branch is provided, skip Step 0 — assess the current working directory state (staged changes, current branch vs main).

---

## QA Mindset — Think Before Testing

Before deploying agents, the orchestrator MUST assess the change:

**5 Pre-Assessment Questions:**
1. **Blast radius** — If this breaks, what else breaks? Map the dependency chain.
2. **Developer blind spots** — What did the developer assume about inputs, state, or timing?
3. **Shared state** — What state does this touch that other features also touch?
4. **Risk zones** — Does this touch auth, payments, data deletion, or user data?
5. **Test coverage** — What existing tests cover this? Where are the gaps?

**Risk Priority Score** = Likelihood × Impact × (1 / Detectability)
- High-risk signals: auth changes, financial calculations, data persistence, no existing tests, recent refactor

**Pre-Assessment → Scope Escalation:** If blast radius touches 3+ unrelated features → escalate scope one tier. If risk zones answer is "yes" (auth/payments/data) → force Large scope. If test coverage gaps are found in changed code → add Edge Case Hunter to the swarm regardless of scope tier.

---

## Project-Aware QA

### Leverage Existing Test Suites

If the project already has tests (Vitest, Jest, Playwright, pytest, etc.), the Test Runner agent MUST run them first and build a coverage map:

1. Run unit tests with JSON output → parse pass/fail per file
2. Run E2E test list (`npx playwright test --list`) → extract tested workflows
3. Build coverage map: changed files with tests vs without
4. Focus manual QA ONLY on gaps — never duplicate what existing tests already cover

### Multi-Stack Detection

If the project has multiple languages (e.g., TypeScript frontend + Python backend):
- Deploy SEPARATE Code Analyzer sub-agents per language (one for TS with Biome/ESLint rules, one for Python with Ruff)
- **Cross-boundary contract check**: The API boundary between frontend and backend is the #1 risk zone. Verify response shapes match — Python snake_case vs TypeScript camelCase, null handling, date formats
- Check for shared contracts: Do API response types in TypeScript match what the Python backend actually sends?

### Infrastructure Changes

If changed files include Terraform, SST, Docker, or CI configs:
- Run `terraform plan -detailed-exitcode` (exit code 2 = drift)
- Trace env var chain: Terraform output → SST config → runtime env var → code usage
- Check IAM permissions scope (flag `*` wildcards)
- Verify Docker builds match CI target platform (ARM64 vs x86)

---

## Agent Swarm Deployment

### Step 1: Detect Scope and Select Agents

Assess the change scope and deploy the appropriate swarm:

| Change Scope | Signal | Agents to Deploy |
|-------------|--------|-----------------|
| **Micro** (1-3 files, cosmetic) | Typo fix, copy change, CSS tweak | Code Analyzer only |
| **Small** (bug fix, minor feature) | 4-10 files, single concern | Code Analyzer + Test Runner + 1 specialist |
| **Medium** (new feature, refactor) | 11-30 files, multiple concerns | Full Wave 1 + targeted Wave 2 (5-6 agents) |
| **Large** (major feature, rewrite) | 30+ files OR touches auth/payments/data | ALL agents, full wave structure (7-8 agents) |

**Override rule:** If ANY change touches authentication, payments, user data deletion, or security-sensitive code → deploy Large regardless of file count.

### Step 2: Execute in Waves

**IMPORTANT:** Create workspace directory `.qa-report/` at project root. Every agent MUST write findings to its own file in this workspace. Set `mode: "bypassPermissions"` on all agent calls.

#### Wave 1: RECONNAISSANCE (all parallel)

**MANDATORY — READ ENTIRE FILE before deploying any agent:** [`references/agent-prompts.md`](references/agent-prompts.md) — contains exact prompt templates with scope boundaries. **PROHIBITED:** Do NOT load `browser-qa-workflows.md` or `qa-checklists.md` during Wave 1.

Deploy these agents simultaneously:

| Agent | Task | Output File | Model |
|-------|------|-------------|-------|
| **Code Analyzer** | Review changed code for logic errors, missing validation, error handling gaps, security issues | `.qa-report/wave-1/code-analysis.md` | sonnet |
| **Test Runner** | Execute existing test suites, report failures and coverage gaps | `.qa-report/wave-1/test-results.md` | sonnet |
| **Project Scanner** | Detect tech stack, find app URL, identify auth requirements, list changed pages/endpoints | `.qa-report/wave-1/project-scan.md` | haiku |

Wait for ALL Wave 1 agents to complete. Read their output files. Extract:
- List of risk areas and changed files (from Code Analyzer)
- Test coverage gaps (from Test Runner)  
- App URL, tech stack, and auth info (from Project Scanner)

#### Wave 2: ACTIVE TESTING (parallel, informed by Wave 1)

Deploy based on scope. Pass Wave 1 FACTS (file lists, URLs, risk areas) to each agent — never pass opinions or severity judgments.

| Agent | Task | Output File | Model | Deploy When |
|-------|------|-------------|-------|-------------|
| **Browser Tester** | Test user workflows, forms, navigation, error states in live app | `.qa-report/wave-2/browser-testing.md` | sonnet | App URL available |
| **Accessibility Auditor** | Keyboard nav, focus management, ARIA, color contrast | `.qa-report/wave-2/accessibility.md` | sonnet | UI changes |
| **Security Scanner** | XSS, injection, auth gaps, exposed secrets, CORS | `.qa-report/wave-2/security.md` | sonnet | Always for Medium+ |
| **Edge Case Hunter** | Boundary values, empty states, unicode, concurrent access, error recovery | `.qa-report/wave-2/edge-cases.md` | sonnet | Coverage gaps found |
| **Performance Checker** | Network requests, payload sizes, load times, unnecessary re-renders | `.qa-report/wave-2/performance.md` | haiku | UI/API changes |
| **Visual Verifier** | Screenshots at desktop/tablet/mobile viewports, layout checks | `.qa-report/wave-2/visual.md` | haiku | UI changes |

**MANDATORY — READ BEFORE deploying Browser Tester or Visual Verifier:** [`references/browser-qa-workflows.md`](references/browser-qa-workflows.md) — QA-specific browser testing patterns. Also read the agent-browser skill — it ships in the separate `web` plugin, at `~/.claude/skills/web/skills/agent-browser/SKILL.md` — for the full CLI reference; if that plugin is not installed, `${CLAUDE_PLUGIN_ROOT}/skills/shared/agent-browser-reference.md` has a quick reference instead. **PROHIBITED:** Do NOT load `qa-checklists.md` during Wave 2.

#### Wave 3: SYNTHESIS (orchestrator only)

**MANDATORY — USE AS VALIDATION CHECKLIST:** [`references/qa-checklists.md`](references/qa-checklists.md) — verify no QA dimension was missed before writing the final report.

Do NOT deploy agents for synthesis. The orchestrator reads ALL wave-1/ and wave-2/ files from disk, then:

1. **Resolve conflicts** — Runtime evidence (browser) beats static analysis (code). See conflict hierarchy below.
2. **Classify using Severity Escalation Ladder** — Apply escalation rules (below) to determine true severity.
3. **Write final report** — `.qa-report/QA-REPORT.md`

**Agent timeout:** If an agent's output file is absent or empty after completion, log it in "Not Tested" with reason "agent failed" and proceed with remaining results. Do NOT block synthesis waiting for a dead agent.

### Step 3: Write the QA Report

Write `.qa-report/QA-REPORT.md` with these required sections:
- **Verdict**: PASS / PASS WITH NOTES / FAIL (FAIL = any ship-blocker; PASS WITH NOTES = should-fix items; PASS = clean)
- **Ship-Blockers**: Each with file:line, reproduction steps, and suggested fix
- **Should Fix** / **Nice to Fix**: Each with evidence
- **Passed Checks**: MANDATORY even when empty — list what was tested and found working
- **Not Tested**: Every gap with reason (agent timeout, no URL, etc.)
- **Conflicting Evidence**: When agents disagree (see Conflict Resolution)
- **Test Evidence**: Links to screenshots and agent reports in `.qa-report/`

---

## Conflict Resolution Hierarchy

When agents disagree on the same issue:
1. **Browser/runtime evidence** beats code analysis (reality > theory)
2. **Multiple agents agreeing** beats single agent's finding
3. **Specific evidence** (file:line, screenshot, network capture) beats general assessment
4. **Tie**: Add a "Conflicting Evidence" subsection in the report with both agents' evidence side-by-side. Label as "Manual verification required before ship." Do NOT average or dismiss either finding.

---

## Severity Escalation Ladder

A "should fix" becomes a **ship blocker** when ANY of these conditions apply:

| Issue Type | Normal Severity | Escalates to Ship-Blocker When |
|------------|----------------|-------------------------------|
| Missing loading indicator | Nice-to-fix | On any submit button that creates/modifies data (double-submission risk) |
| Missing error message | Should-fix | User has no recovery path (no way to know what went wrong or what to do) |
| Console error | Should-fix | Throws on page load OR during core user workflow |
| Performance regression | Nice-to-fix | Response time >3s on critical path (checkout, auth, data save) |
| Accessibility failure | Should-fix | Completely blocks keyboard-only or screen reader users from core workflow |
| Flaky test | Should-fix | Covers security, auth, or payment paths |
| Visual bug | Nice-to-fix | Renders core content unreadable or hides interactive elements |

**The escalation test:** Can a user complete the core workflow? If no → ship blocker. Can the bug cause data loss, incorrect charges, or security exposure? If yes → ship blocker.

---

## AI Chat & Streaming App QA

If the project is a chat/conversational AI app (detected by: Vercel AI SDK, streaming endpoints, LLM integration, component blocks in messages):

### Non-Deterministic Output Testing

You CANNOT assert exact AI text. Instead assert:
- **Structure**: Response contains expected component blocks (e.g., `:::: EducationPathCard {json} ::::`)
- **Schema**: JSON in component blocks validates against required fields and types
- **Behavioral contracts**: AI always asks follow-up after intake, always produces results after sufficient context, never answers off-topic mid-intake
- **Absence**: No raw JSON leaking outside component blocks, no malformed syntax visible to user

### Streaming QA

Streaming creates bugs that don't exist in request/response APIs:
- **Chunk-split vulnerability**: Component block delimiters (`::::`) may split across stream chunks → verify the parser buffers correctly
- **Mid-stream error**: If LLM fails after 3 paragraphs, user should see those paragraphs + error indicator, NOT a blank screen
- **Stream interruption**: Navigate away mid-stream → verify no console errors, no orphaned requests, AbortController fires
- **Submit while streaming**: User sends a new message before previous response completes → verify no duplicate messages, no corrupted history

### Bilingual / i18n QA

If the app supports multiple languages:
- Test with language-specific characters (Icelandic: Þ/þ, Ð/ð, á/é/í/ó/ú/ý/ö/æ — these break regex patterns using `[A-Z]`)
- **Mid-conversation language switch**: Change language setting → verify AI responds in new language, prior messages stay in original language, UI chrome updates
- **Text overflow**: Test with longest translations — Icelandic words are often 30-50% longer than English equivalents
- **Locale formatting**: Dates, numbers, currency must respect active locale (e.g., `1.234,56` vs `1,234.56`)

### Session Persistence

For sessionStorage-backed chat:
- F5 refresh preserves conversation history
- Close tab + reopen loses session (verify this is intentional and communicated)
- Two tabs have independent sessions (verify isolation)
- Clear conversation actually clears storage (check with devtools)

**MANDATORY — READ for AI chat projects:** [`references/ai-chat-qa.md`](references/ai-chat-qa.md) — full streaming, i18n, and session testing patterns.

---

## Code-to-Browser Verification Loop

The most powerful QA pattern: trace from source code to browser behavior and back.

```
Read code → Predict behavior → Verify in browser → Compare network traffic
```

- Read form handler → test the actual form → verify validation messages match code
- Find API endpoint → trigger it through UI → verify response handling matches expectations  
- Spot error boundary → trigger the error → verify graceful degradation
- Check auth guard → attempt unauthorized access → verify redirect works

**The Browser Tester agent must follow this loop**, not just click around randomly. Read `references/browser-qa-workflows.md` for specific patterns.

---

## NEVER Do These

- **NEVER deploy all 8 agents for a typo fix.** Match swarm size to change scope. Overkill on micro changes wastes tokens and produces noise.
- **NEVER skip the Pre-Assessment Questions.** Testing without understanding risk is random clicking — it finds nothing important and misses everything that matters.
- **NEVER test only the happy path.** For every positive test (it works), do a negative test (it fails gracefully). Check error states, empty states, boundary values, and unauthorized access.
- **NEVER assert existence without verifying correctness.** "Element exists" is not a test. "Element displays 'Order #12345 confirmed' and total matches $107.50" is a test.
- **NEVER trust DOM state without checking visual output.** An element can exist in the DOM but be invisible (behind overlay, scrolled off-screen, opacity: 0, clipped by overflow). When in doubt, screenshot.
- **NEVER pass agent opinions between waves.** Pass FACTS (file lists, URLs, error messages). Let each agent form its own severity judgment independently.
- **NEVER synthesize before all agents in a wave complete.** Partial synthesis creates false confidence that poisons the report.
- **NEVER write "no issues found" without listing what was checked.** "Checked and clean" requires evidence. Blank findings = didn't check.
- **NEVER let flaky tests slide.** A flaky test is a test that sometimes lies. Fix it, quarantine it, or delete it — don't just re-run and hope.
- **NEVER forget error recovery testing.** After triggering an error, verify the user CAN recover: retry works, form state preserved, no stuck UI.
- **NEVER assume changed code is isolated.** Verify that unchanged adjacent code wasn't broken by the change — check callers, shared state consumers, and downstream dependencies.
- **NEVER duplicate existing test coverage.** If the project has Playwright E2E tests for a workflow, don't re-click through that same workflow manually. Extend coverage to untested paths.
- **NEVER assert exact text from AI responses.** Assert structure (component blocks present), schema (JSON validates), and behavioral contracts (follow-up question exists). Exact text assertions on LLM output are inherently flaky.
- **NEVER ignore the frontend/backend API boundary.** In multi-stack projects, the boundary between TypeScript and Python (or any cross-language API) is where the most bugs hide — response shape mismatches, null handling, date formats.

---

## Destructive Creativity Techniques

When the Edge Case Hunter agent tests, it should use these expert techniques:

1. **Goldilocks Attack**: Too small, too big, exactly at the boundary. For "max 255 chars": test 0, 1, 254, 255, 256, 1000.
2. **State Pollution**: Do Action A, then Action B. Does A's residual state corrupt B?
3. **The Impatient User**: Double-click submit. Hit back during submission. Refresh during async ops.
4. **The Time Traveler**: Test around timezone boundaries, DST transitions, midnight, month-end.
5. **The Copy-Paster**: Paste rich text into plain fields. Paste multi-line into single-line. Paste HTML/script tags.
6. **Concurrent Access**: Same resource in two tabs. Two "users" editing simultaneously.
7. **The Underprivileged User**: Expired token, revoked permissions, free tier hitting premium features.

---

## Graceful Degradation

Skip agents that lack required access. Note every skip in the "Not Tested" section of the report with the reason. No app URL → skip browser agents. No test suite → skip Test Runner. No agent-browser → code-only QA. Always proceed with available agents rather than blocking.

---

## Step 4: User Testing Handoff

After presenting the QA report, offer the user a live browser session for manual verification.

### 4a: Present the Report Summary

Show the user:
1. The **Verdict** (PASS/PASS WITH NOTES/FAIL)
2. **Ship-blockers** (if any) — these need attention before anything else
3. Key findings count: "Found X critical, Y major, Z minor issues"
4. What was tested and what was NOT tested (gaps)

### 4b: Offer Manual Testing

Ask the user if they want to test the feature themselves. If yes:

1. **Open a headed browser session** so the user can see what's happening:
   ```bash
   agent-browser --headed open <app-url>
   ```
2. **Guide them to the key pages** — list the changed pages/routes with brief descriptions of what to check:
   ```
   Here are the pages affected by this branch:
   1. /dashboard — new data visualization component
   2. /settings/profile — updated form validation
   3. /api/users — modified response shape
   
   Want me to navigate to any of these? Or test something specific?
   ```
3. **Stay interactive** — the user can ask the agent to:
   - Navigate to specific pages: `agent-browser open <url>`
   - Fill forms, click buttons on their behalf
   - Take screenshots of specific states
   - Check network requests for specific interactions
   - Re-run specific tests from the QA report
4. **Accept user-reported issues** — if the user finds something, add it to `.qa-report/QA-REPORT.md` under a new "User-Reported Issues" section

### 4c: Cleanup

When the user is done testing:
1. Close the browser session: `agent-browser close`
2. If a dev server was started in Step 0, inform the user it's still running and offer to stop it
3. If the branch was checked out in Step 0, ask if they want to switch back to their previous branch:
   ```bash
   git checkout <previous-branch>
   git stash pop 2>/dev/null  # Restore stashed work
   ```

---

## References

Loading triggers are embedded inline at each wave. Summary:

| Reference | Trigger Point | PROHIBITED Before |
|-----------|--------------|-------------------|
| [`references/agent-prompts.md`](references/agent-prompts.md) | Wave 1 start (MANDATORY) | — |
| [`references/browser-qa-workflows.md`](references/browser-qa-workflows.md) | Wave 2, browser agents only | Wave 1 |
| [`references/ai-chat-qa.md`](references/ai-chat-qa.md) | Wave 2, AI chat/streaming apps only | Wave 1 |
| [`references/qa-checklists.md`](references/qa-checklists.md) | Wave 3, synthesis validation | Wave 1, Wave 2 |
