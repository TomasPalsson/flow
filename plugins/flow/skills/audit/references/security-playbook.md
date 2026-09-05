---
name: audit-security-playbook
description: Ordered security audit playbook for the /audit skill's security dimension agent. Secrets → CVEs → injection → crypto → auth. Includes what NOT to flag and exact tooling commands. Load by the security agent at Phase 1.
---

# Security Audit Playbook — Ordered by ROI

**The security agent runs this playbook in order. Each step has a different false-positive profile and must be treated differently.** The step ordering matters — secrets first because they require urgent rotation, everything else is future risk.

## Hard Rules for the Security Agent

1. **Secrets and exploited CVEs bypass the findings budget** — always shown, never dropped.
2. **Auth / access-control findings are ALWAYS `propose-only`** (capped at `review-required` fix eligibility). SAST on access control is unreliable regardless of tool.
3. **Dev-dependency CVEs are dropped** unless the compromise scenario is real.
4. **Findings on test files, fixtures, and `.env.example` with placeholder values are dropped**.
5. **Every finding needs a `failure_scenario`** — specific input → specific outcome → specific impact.

## Step 1 — Secrets Scan (highest ROI, always first)

**Tools**:
```bash
# gitleaks — fastest for history scanning
gitleaks detect --source . --log-opts="--all" --report-format json --report-path /tmp/gitleaks.json

# trufflehog — verified live secrets (slower but high-signal)
trufflehog git file://. --only-verified --json

# Current working tree only
gitleaks detect --no-git --report-format json
```

**High-signal patterns** (never suppress):
- AWS `AKIA[A-Z0-9]{16}` — IAM access key IDs
- `ghp_`, `gho_`, `github_pat_` — GitHub PATs
- `sk_live_`, `pk_live_` — Stripe live keys
- Twilio `AC` SID + auth token pair
- `-----BEGIN RSA PRIVATE KEY-----`, `-----BEGIN EC PRIVATE KEY-----`, `-----BEGIN OPENSSH PRIVATE KEY-----`
- `.pem`, `.key` files committed to repo
- Google service account JSON (`"private_key_id"` + `"client_email"`)
- JWT `HS256` with a non-placeholder secret visible in code/config

**High-noise patterns** (deprioritize or suppress):
- UUIDs, base64-encoded images, minified JS hashes
- `EXAMPLE_KEY`, `YOUR_API_KEY_HERE`, `xxx`, `test`, `fake`, `placeholder`
- Fixture files, test data, `examples/`, `testdata/`
- README and documentation files
- `package-lock.json` / `yarn.lock` hashes (high entropy, not secrets)

**Critical rule**: Secrets live in git history even after removal. Always scan history (`--log-opts="--all"`), not just the working tree. Assume any secret committed at any point is compromised — rotation must happen regardless of removal.

**Finding structure**:
```json
{
  "subject": "Live AWS IAM key committed in src/config/aws.ts:23",
  "failure_scenario": "Access key AKIA4EXAMPLE... is committed to git history. Any person with repo access (or anyone after a public mirror) can use it to sign AWS API calls as this IAM user. Verified live by trufflehog API check.",
  "severity": "critical",
  "confidence": 0.99,
  "fix_eligibility": "review-required",
  "auto_fix_blocked_reason": "Requires credential rotation BEFORE code change. Replace in secrets manager, rotate in IAM, then remove from code + history."
}
```

## Step 2 — Dependency CVE Scan (with exploitability filter)

**Tools per stack**:
```bash
# Node.js — production only, high/critical
npm audit --omit=dev --audit-level=high --json

# pnpm — same data, better dev/prod separation
pnpm audit --prod --audit-level high

# Python
pip-audit --output json --skip-editable

# Go — CALL-GRAPH AWARE (huge advantage over generic SCA)
govulncheck -json ./...

# Rust
cargo audit --json
cargo deny check advisories
```

**Why govulncheck is different**: it reports only vulnerabilities in functions your code actually calls. A package can import a vulnerable library and never call the vulnerable function — generic SCA tools flag this (noise); govulncheck doesn't.

**Filtering rules**:
- Direct production dependencies only
- HIGH or CRITICAL severity (not medium, not informational)
- Known exploit exists (CVSS exploitability score > 3.9 OR KEV catalog listing)

**Drop rules**:
- Dev dependencies → never shown (attacker would need dev environment access, different threat model)
- Transitive prod deps where the vulnerable function is not in call graph (where tool supports it)
- Informational CVSS (< 4.0)

**Finding structure**:
```json
{
  "subject": "lodash 4.17.15 in production dependencies has CVE-2021-23337 (command injection)",
  "failure_scenario": "lodash.template() with user-controlled input allows command injection. Call site at src/email/render.ts:34 passes req.body.templateName to lodash.template. An attacker posting a crafted template string achieves RCE on the server.",
  "severity": "critical",
  "confidence": 0.92,
  "fix_eligibility": "review-required",
  "auto_fix_blocked_reason": "Version upgrade may introduce breaking changes; user should test"
}
```

## Step 3 — Injection Patterns (with confidence gating)

Taint analysis on dynamic languages has ~30-60% false positive rate because dynamic dispatch, monkey-patching, and decorators hide control flow. Every finding in this step must have a concrete input/sink/path or be labeled `question`.

**Tools**:
```bash
semgrep --config p/python --config p/javascript --config p/typescript \
  --include="*.py,*.ts,*.js" --severity ERROR --json
# Semgrep is high-recall, medium-precision — expect 30% FP

# CodeQL has the lowest FP rate but requires database setup
codeql database create codeql-db --language=javascript
codeql analyze codeql-db javascript-security-and-quality.qls --format=sarif-latest
```

**Manual grep patterns** (when tool output is insufficient):

**Python**:
```bash
# pickle / yaml / eval
grep -rn "pickle\.loads\|yaml\.load(" --include="*.py" . | grep -v "SafeLoader"
grep -rn "^[^#]*\beval(\|^[^#]*\bexec(" --include="*.py" .
grep -rn "subprocess.*shell=True" --include="*.py" .
grep -rn "Jinja2.*Environment" --include="*.py" . | grep -v "autoescape"
grep -rn "request\.args\.get\|request\.form\.get" --include="*.py" .  # then trace sinks
```

**TypeScript / Node**:
```bash
# exec with concatenation, prototype pollution, JWT none
grep -rn "exec(.*\${" --include="*.ts" --include="*.js" .
grep -rn "\.__proto__\|constructor\.prototype\|prototype\[" --include="*.ts" --include="*.js" .
grep -rn "jwt\.verify\|jwt\.decode" --include="*.ts" --include="*.js" .  # check if algorithms: ['HS256'] is passed
grep -rn "fs\.readFile(\`" --include="*.ts" --include="*.js" .  # path traversal
```

**Go**:
```bash
# SQL injection, html/text template confusion
grep -rn "fmt\.Sprintf.*SELECT\|fmt\.Sprintf.*INSERT\|fmt\.Sprintf.*UPDATE\|fmt\.Sprintf.*DELETE" --include="*.go" .
grep -rn '"text/template"' --include="*.go" .  # confirm not used for HTML
grep -rn "math/rand\b" --include="*.go" . | grep -iE "token|session|nonce|random.*key|password"  # should be crypto/rand
grep -rn "crypto/md5\|crypto/sha1" --include="*.go" . | grep -iE "password|token|hash|sign"
```

**Rust**:
```bash
# panic on untrusted, missing timeouts
grep -rn "\.unwrap()\b" --include="*.rs" . | grep -iE "parse|from_str|deserialize"
grep -rn "reqwest::Client::new\(\)" --include="*.rs" . # check if timeout is set on builder
```

**SQL (all languages)**:
- String concat involving user input in SQL strings → injection
- `LIKE '%' + userInput + '%'` without metacharacter sanitization → enumeration + full-scan DoS
- `ORDER BY` with user input → column names cannot be parameterized, must allowlist

**Finding structure for injection**:
```json
{
  "subject": "SQL injection in user search via fmt.Sprintf",
  "failure_scenario": "db.Query at internal/store/users.go:67 concatenates req.URL.Query().Get('q') into the SELECT statement via fmt.Sprintf. Attacker submitting `q='; DROP TABLE users; --` achieves SQL execution.",
  "severity": "critical",
  "confidence": 0.94,
  "fix_eligibility": "review-required",
  "auto_fix_blocked_reason": "Fix requires converting to parameterized query + verifying all LIKE/ORDER BY siblings"
}
```

## Step 4 — Crypto and Hardcoded Pattern Check (low FP)

Crypto pattern detection has low false-positive rates — if you see `AES.new(key, AES.MODE_ECB)` in production code, it's almost certainly wrong.

**Patterns to grep**:
```bash
# ECB mode
grep -rn "MODE_ECB\|\.ECB\b\|AES\.new.*ECB" --include="*.py" --include="*.ts" --include="*.js" .

# MD5/SHA1 in security contexts
grep -rn "md5\|sha1" --include="*.py" --include="*.go" --include="*.ts" . | grep -iE "password|token|secret|hash|sign|hmac"

# Hardcoded IV / predictable IV
grep -rn "iv = b'\\\\x00'\|iv = bytes(16)\|IV = bytes" --include="*.py" .
grep -rn "Buffer\.alloc(16)\|new Uint8Array(16)" --include="*.ts" . | grep -i "iv"

# Missing constant-time comparison
grep -rn "compare_digest\|ConstantTimeCompare\|subtle\.ConstantTimeCompare" --include="*.py" --include="*.go" --include="*.ts" . | head
# Absence in auth/token/hmac contexts is the concern — cross-reference with hmac/token code

# JWT algorithm confusion
grep -rn 'jwt\.verify\|jwt\.decode' --include="*.ts" --include="*.py" . # check if algorithms parameter is passed
grep -rn '"none"\|"alg".*"none"' --include="*.ts" --include="*.py" .

# PBKDF2 iteration counts (should be ≥210,000 per NIST 2023)
grep -rn "PBKDF2\|pbkdf2_hmac" --include="*.py" --include="*.ts" . -A 2

# Password hashing using wrong function
grep -rn "hashlib\.md5.*password\|hashlib\.sha.*password" --include="*.py" .
```

**Hard flags** (report directly, high confidence):
- ECB mode for anything (penguin problem)
- Fixed IV for CBC/CFB modes
- MD5/SHA1 for auth, tokens, password hashing, signatures
- `==` comparison on HMAC or token values
- JWT with `alg: none` accepted
- PBKDF2 iterations < 100,000
- `math/rand` (Go) / `random` (Python) for tokens, session IDs, nonces

## Step 5 — Auth / Session / Access Control (ALWAYS PROPOSE-ONLY)

**This step is different**. Every finding at this step is capped at `confidence = 0.75, label: suggestion, fix_eligibility: review-required` — regardless of what the agent's analysis concluded. The reason: SAST on access control is inherently unreliable because middleware, infrastructure, and authorization frameworks can't be traced from source alone.

**What to check**:

**CSRF**:
- State-changing endpoints (POST/PUT/DELETE) — does middleware enforce CSRF tokens?
- Cookies set with `SameSite=Strict` or `SameSite=Lax`?
- APIs intended for browser use have CSRF protection?

**Session fixation**:
- Session ID regenerated on successful login? (Django does this by default; Flask often missed)
- Grep for `login(` handlers — is there a `session.regenerate()` / `cycle_key()` after auth success?

**Rate limiting**:
- Auth endpoints (`/login`, `/signin`, `/api/auth`, `/api/token`, `/oauth/token`)
- Password reset and OTP endpoints
- Any endpoint taking username/email as input (enumeration protection)
- Middleware like `express-rate-limit`, `slowapi`, nginx `limit_req`, or custom attempt counters

**Timing attacks**:
- Password comparison constant-time? (`hmac.compare_digest`, `subtle.ConstantTimeCompare`)
- Login endpoint takes the same time whether user exists or not?

**Open redirect in OAuth callback**:
- `redirect_uri` validated against exact-match allowlist, not prefix or domain

**Cookie flags**:
- `HttpOnly` (prevents JS access, blocks XSS session theft)
- `Secure` (HTTPS only)
- `SameSite` (CSRF mitigation)

**Session storage**:
- JWT in localStorage is a smell (XSS steals it); httpOnly cookie is preferred
- Session IDs with insufficient entropy (should be ≥128 bits of random)

**Frame all findings as questions**, not assertions, because the agent can't prove coverage:
```json
{
  "subject": "CSRF protection not visible on POST /api/users",
  "body": "Route handler at src/api/users.ts:45 does not appear to invoke CSRF middleware in the direct file or at the router level. However, CSRF may be enforced globally via middleware registered in src/app.ts or at infrastructure level. This finding requires human verification.",
  "failure_scenario": "If CSRF is not enforced globally, a victim authenticated to the site could be tricked into submitting a form from a malicious site that posts to /api/users with their cookie, creating records on their behalf.",
  "confidence": 0.65,
  "label": "question",
  "fix_eligibility": "review-required",
  "auto_fix_blocked_reason": "Cannot verify middleware coverage statically — requires human check"
}
```

## What the Security Agent MUST NOT Flag

- Dev-dependency CVEs (not actionable without dev environment compromise)
- Informational CVSS (< 4.0) unless directly exploitable in context
- Compliance box-checking (SOC2 "evidence", PCI-DSS controls) — out of scope
- Code style, naming, non-security quality
- `console.log` / `print` statements
- Test files for most patterns (test secrets, test SQL injection strings, intentional eval usage)
- `.env.example` with clearly fake values
- Access control warnings without specific evidence of missing check (high FP)
- SHA256/SHA512 in any context — only SHA1/MD5 are weak, SHA256+ is fine
- `Math.random()` for non-security uses (UI element IDs, logging correlation IDs)
- TLS configuration unless the codebase is its own terminator
- Every single instance of `eval` in test / build / tool files

## Exact Tooling Command Reference

```bash
# ===== SECRETS =====
gitleaks detect --source . --log-opts="--all" --report-format json --report-path .audit/gitleaks.json
gitleaks detect --no-git --report-format json --report-path .audit/gitleaks-worktree.json
trufflehog git file://. --only-verified --json > .audit/trufflehog.json

# ===== DEPENDENCIES =====
# Node
npm audit --omit=dev --audit-level=high --json > .audit/npm-audit.json
pnpm audit --prod --audit-level high --json > .audit/pnpm-audit.json

# Python
pip-audit --output json --skip-editable > .audit/pip-audit.json

# Go (call-graph aware)
govulncheck -json ./... > .audit/govulncheck.json

# Rust
cargo audit --json > .audit/cargo-audit.json

# ===== SAST =====
semgrep --config p/security-audit --config p/secrets --json > .audit/semgrep.json

# ===== SBOM =====
syft . -o cyclonedx-json > .audit/sbom.cyclonedx.json
```
