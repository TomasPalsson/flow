---
name: worklog-troubleshooting
description: Full failure catalog (13 categories) with symptom/detection/root-cause/fix/prevention rows, plus a decision tree, plus the gaps in `worklog doctor`. Load when a worklog problem doesn't resolve via the inline Recipe C in SKILL.md, or when any specific symptom matches one of the 13 categories below.
---

# Troubleshooting

## Why this exists separately from SKILL.md

`worklog doctor` covers DB + schema + secrets. It does NOT check:
- Daemon socket liveness
- Hook installation status
- Schedule installation status
- `claude` binary presence on PATH
- Tempo / Jira / Gcal API reachability
- `WORKLOG_TZ` validity
- Web UI (bun) process liveness
- Tempo orphan worklogs

For each of those, compose multiple commands. The catalog below is the recipe.

## Master decision tree

```
User: "no data" / "broken" / "empty"
│
├─ worklog doctor --json
│   ├─ db_exists: false        → worklog db migrate (or worklog setup)
│   ├─ schema_version < 6      → worklog db migrate (idempotent)
│   ├─ events: 0               → branch to "no events" subtree
│   └─ secrets[*].present:false → "missing secret <key>"  → see category 6/7
│
├─ "no events" subtree:
│   ├─ worklog schedule status → not installed → worklog schedule install --interval 15m
│   ├─ worklog hook status     → not installed → worklog hook install
│   └─ worklog collect all     → triggers manual collect; check errors per source
│
├─ Events exist but no blocks
│   └─ worklog infer --day $DAY
│       └─ blocks on wrong day → $WORKLOG_TZ misconfig → category 8
│
├─ Blocks exist but Tempo empty
│   └─ worklog sync --day $DAY --dry-run
│       ├─ HTTP 400 "User is invalid"      → category 5a
│       ├─ HTTP 400 "Issue id null"        → category 5b (worklog collect jira)
│       ├─ HTTP 401                        → category 5c (tempo_api_token)
│       └─ status:"skipped" no_jira_issue  → assign tickets first
│
├─ Web UI not loading
│   └─ worklog web status
│       ├─ not running         → worklog web down && worklog web up
│       └─ running, blank page → daemon down → category 1
│
├─ Estimation producing 'gap'
│   └─ which claude            → category 4 (install Claude Code CLI)
│
└─ Daemon API unreachable
    └─ curl http://127.0.0.1:9323/health → category 1
```

## Failure catalog

### 1. Daemon not running

**Symptom:** `worklog web up` hangs / "connection refused"; web UI blank; `curl http://127.0.0.1:9323/health` ECONNREFUSED; API mutations error with "couldn't reach daemon."

**Detection:**
```bash
curl -sf http://127.0.0.1:9323/health   # success → daemon up
ls -la ~/.local/share/worklog/api.sock  # missing → daemon never ran
worklog daemon status                   # service unit state
```

**Root causes:**
- Never installed as a service unit (ran `worklog daemon` in a terminal, terminal closed).
- DB migration failed on startup, daemon exited.
- Stale `api.sock` from a crash — `serve_at` removes it on next start, so a present-but-unresponsive socket means the daemon started then died.

**Fix:**
```bash
worklog daemon install    # supervised; recommended
worklog daemon status     # verify
# Or foreground (debugging):
worklog daemon
```

**Prevention:** Always `worklog daemon install` during setup, not bare `worklog daemon`.

---

### 2. Schedule not running — events table not growing

**Symptom:** `worklog doctor` shows `events` count unchanged across days; `worklog day` produces no blocks for days the user worked.

**Detection:**
```bash
worklog schedule status   # "not installed" or stale interval
sqlite3 ~/.local/share/worklog/worklog.db "SELECT MAX(started_at) FROM events;"
```

**Root causes:**
- Never installed.
- Uninstalled by hand.
- The scheduled `worklog collect all` exits with an error every tick (credentials issue).

**Fix:**
```bash
worklog schedule install --interval 15m
worklog collect all      # verify manual collect works before relying on schedule
worklog doctor           # confirm event count grew
```

**Prevention:** `worklog setup` includes the schedule step. Run a manual `worklog collect all` after any credential rotation.

---

### 3. Claude Code hook not installed — no `claude` source events

**Symptom:** All blocks are sourced from `github` / `gcal` only. Estimator quality is poor (no prompt context). `worklog day --json` blocks lack `"source":"claude"` in their `sources[]`.

**Detection:**
```bash
worklog hook status   # installed: false → run install
sqlite3 ~/.local/share/worklog/worklog.db "SELECT COUNT(*) FROM events WHERE source='claude';"
```

**Root causes:**
- Never ran `worklog hook install`.
- `~/.claude/settings.json` overwritten by another tool.
- worklog binary moved (e.g., reinstalled to a different prefix) and the absolute path in settings.json no longer resolves. The hook fires but silently fails.

**Fix:**
```bash
worklog hook install   # idempotent — replaces stale path
worklog hook status    # confirm all 5 events: SessionStart, UserPromptSubmit, Stop, SubagentStop, SessionEnd
```

**Prevention:** After any `worklog upgrade` that changes the binary path, re-run `worklog hook install` to refresh.

---

### 4. `claude` binary missing — estimator fails

**Symptom:** `worklog estimate` errors with `spawning 'claude': No such file or directory` or `claude -p exited -1`. All blocks land in `estimated_by = 'gap'`.

**Detection:**
```bash
which claude && claude --version
sqlite3 ~/.local/share/worklog/worklog.db \
  "SELECT COUNT(*) FROM blocks WHERE estimated_by='gap';"
```

**Root causes:**
- Claude Code CLI not installed.
- Subprocess timed out (60s) due to network/auth issue.

**Fix:**
```bash
# Install: https://claude.ai/download
which claude && claude --version
# Re-estimate previously gap blocks:
worklog estimate --day "$DAY"
# To force re-estimate of 'gap' blocks while preserving manual:
sqlite3 ~/.local/share/worklog/worklog.db \
  "UPDATE blocks SET estimated_by=NULL WHERE estimated_by='gap';"
worklog estimate --day "$DAY"
```

**Prevention:** `worklog setup` probes for the `claude` binary in preflight.

**Note:** `estimated_by = 'manual'` blocks are never re-estimated regardless. That shield is permanent.

---

### 5. Tempo auth / contract errors

#### 5a. 400 "User is invalid" — email used as authorAccountId

**Symptom:** Every block in a sync returns HTTP 400. Error body mentions "User is invalid" or similar.

**Root cause:** Tempo v4 requires the Atlassian `accountId` (format `557058:abc-def-123`), not an email. `TempoAuth::from_secrets` falls back to `jira_email` if `jira_account_id` is unset. The sync self-heals by calling Jira `/myself` IF Jira credentials are configured.

**Detection:**
```bash
worklog secret get jira_account_id   # should be present and contain ':'
worklog secret get jira_email        # legacy fallback
```

**Fix:**
```bash
# Option A: let self-heal (needs valid Jira creds)
worklog sync --day "$DAY" --dry-run

# Option B: set explicitly
worklog secret set jira_account_id 557058:abc-def-123
```

#### 5b. 400 "Issue id cannot be null"

**Symptom:** `worklog sync` results show `status:"error"` with `reason:"couldn't resolve numeric issueId for PROJ-123"`. Suggests `worklog collect jira`.

**Root cause:** Tempo v4 requires numeric `issueId` (not the string key). The resolver checks the local `jira_tickets.issue_id` cache, then falls back to Jira's `/issue/{key}`. If both miss, sync fails for that block.

**Fix:**
```bash
worklog collect jira          # refreshes cache including issue_id
worklog sync --day "$DAY" --dry-run    # verify resolution
```

#### 5c. 401 Unauthorized — tempo_api_token wrong/expired

**Symptom:** All sync blocks return 401.

**Detection:**
```bash
worklog secret get tempo_api_token
# Sanity test against Tempo:
TOKEN=$(worklog secret get tempo_api_token)
curl -H "Authorization: Bearer $TOKEN" https://api.tempo.io/4/worklogs?limit=1
```

**Fix:**
```bash
# Generate new token: Tempo → My Work → Tempo Settings → API integration
worklog secret set tempo_api_token <new-token>
worklog sync --day "$DAY" --dry-run
```

#### 5d. 404 on Tempo DELETE — not an error

The daemon's `delete_worklog` treats Tempo 404 as success — the worklog is already gone. No action needed.

#### 5e. No Tempo credentials during block delete — orphan created

**Symptom:** Local block deleted via UI / API; Tempo entry remains. Daemon log shows: "no tempo auth — deleting locally but Tempo entry will remain."

**Fix:** Manual cleanup in Tempo UI. No automated recovery.

**Prevention:** Ensure `tempo_api_token` is set BEFORE deleting any synced block. The skill should pre-flight check credentials before any delete on a synced block.

---

### 6. Jira auth — 401 on ticket fetch

**Symptom:** `worklog collect jira` errors with "jira search at <url>: HTTP 401". `jira_tickets` table empty or stale.

**Root causes:**
- `jira_email` wrong (not the Atlassian account email).
- `jira_api_token` revoked.
- `jira_base_url` wrong format (must include `https://`, not just `company.atlassian.net`).
- On-prem Jira Server (not Cloud) — the code targets `/rest/api/3/search/jql`, which is Cloud-only.

**Fix:**
```bash
worklog secret set jira_email you@company.com
worklog secret set jira_api_token <token from id.atlassian.com>
worklog secret set jira_base_url https://company.atlassian.net
worklog collect jira
```

---

### 7. Gcal OAuth failures

**Symptom:** `worklog collect gcal` fails with one of:
- `gcal: missing <credentials_path>`
- `gcal: token at <path> is expired and has no refresh_token`
- `gcal: token refresh failed (401)`

**Root causes:**
1. `google_credentials.json` never downloaded from Google Cloud Console.
2. `google_token.json` missing (never auth'd) or has no `refresh_token` (first-auth missed `offline` scope).
3. Refresh token revoked by Google (user revoked app, or 6-month idle policy fired).
4. OAuth app deleted from Cloud Console.

**Fix:**
```bash
# Download credentials.json → ~/.config/worklog/google_credentials.json

# Trigger interactive OAuth (browser opens):
worklog collect gcal --auth

# Verify:
worklog collect gcal
```

**Prevention:** `WORKLOG_GOOGLE_CALENDARS` env limits to relevant calendars (reduces quota). Re-auth every 6 months if gcal collection is idle.

---

### 8. `WORKLOG_TZ` misconfigured — silent mis-bucketing

**Symptom:** Evening events appear on the next day; early-morning events on the previous day. `worklog day --day $TODAY` shows no blocks even though user worked. The blocks are on the adjacent day.

**Detection:**
```bash
echo $WORKLOG_TZ   # should be a fixed offset like -05:00, NOT "America/New_York"

# Cross-check raw timestamps:
sqlite3 ~/.local/share/worklog/worklog.db \
  "SELECT started_at, day FROM blocks ORDER BY started_at DESC LIMIT 5;"
```

**Root cause:** `tz.rs::day_offset()` parses only fixed offsets. Named zones like `America/New_York` silently fall back to UTC. A `tracing::warn!` is logged to the daemon log, NOT to the terminal — entirely invisible to the user.

**Fix:**
```bash
# Set to your offset (update at DST transitions if applicable):
export WORKLOG_TZ=-05:00   # EST
export WORKLOG_TZ=-04:00   # EDT
# Persist:
echo 'set -x WORKLOG_TZ -05:00' >> ~/.config/fish/config.fish
# (or the equivalent for bash/zsh)

# Re-infer the affected days:
worklog infer --day "$BROKEN_DAY"
```

**This is the most dangerous silent failure in worklog.** The skill should proactively check `echo $WORKLOG_TZ` whenever a day shows fewer blocks than the user expects.

---

### 9. Schema mismatch — old binary or copied DB

**Symptom:** `worklog doctor` shows `schema: v3` (or any version < 6). Some queries fail with "no such column: dirty" or similar.

**Detection:**
```bash
worklog db info   # schema_version field
sqlite3 ~/.local/share/worklog/worklog.db "PRAGMA user_version;"
```

**Root causes:**
- DB created by old binary, never opened with new one.
- DB copied from another machine running an older version.

**Fix:**
```bash
worklog db migrate
worklog doctor   # verify v6
```

**Prevention:** Migrations are idempotent — safe to run any time. `db::open` calls migrate automatically, so this is rare.

---

### 10. Stale binary — `worklog upgrade` not run

**Symptom:** `worklog version` is old; new flags/endpoints don't exist.

**Detection:**
```bash
worklog version
worklog self-update --check
```

**Fix:**
```bash
worklog upgrade   # atomic swap, auto-rolls-back on smoke test failure
worklog version
```

**Prevention:** Schedule periodic `worklog self-update --check`. Note: skill files are bundled in the binary — after upgrade, run `worklog skill install` to refresh `${CLAUDE_PLUGIN_ROOT}/skills/worklog/`.

---

### 11. Web UI down — bun crashed / stale PID

**Symptom:** `worklog web status` shows "not running"; `http://localhost:3333` ECONNREFUSED; PID file may exist but process dead.

**Detection:**
```bash
worklog web status
cat ~/.local/share/worklog/web.pid
kill -0 $(cat ~/.local/share/worklog/web.pid) 2>&1
tail -50 ~/.local/share/worklog/log/web.log
```

**Root causes:**
- bun process crashed (check `web.log`).
- `bun run build` failed (Next.js build error).
- Port 3333 in use.
- bun binary not on PATH.
- `node_modules` missing — `bun install` failed.
- Web context (`web/`) couldn't be resolved (no local clone + auto-fetch failed).

**Fix:**
```bash
worklog web down   # clean up stale PID + kill zombie
worklog web up     # restarts; build output inline

# If bun missing:
curl -fsSL https://bun.sh/install | bash

# If web context missing:
worklog web fetch   # pre-warm GitHub archive cache
worklog web up
```

---

### 12. Orphan Tempo worklog — local block deleted, Tempo entry survives

**Symptom:** Tempo daily total > local daily total. A Tempo entry exists for a day/ticket that's no longer in the local DB.

**Detection:** No CLI command — manual cross-reference in Tempo UI. Daemon log will have "no tempo auth — deleting locally" if the cause was missing creds at delete time.

**Root cause:** `web.rs::delete_block` handler — if `TempoAuth::from_secrets()` fails, the handler logs a WARN and proceeds with local-only delete.

**Fix:** Delete the orphan in Tempo UI directly. No automated recovery.

**Prevention:** Configure Tempo credentials BEFORE deleting any synced block. The skill should pre-flight credentials before delete on a synced block (`worklog secret get tempo_api_token` non-empty).

---

### 13. Dirty edits not syncing

**Symptom:** User edited a block in the UI. Tempo still shows old values. `worklog sync --dry-run` shows the block needing PUT.

**Root cause:** The sync WHERE clause includes `dirty = 1`, but sync must be run after the edit. If not run, Tempo retains stale data indefinitely.

**Detection:**
```bash
sqlite3 ~/.local/share/worklog/worklog.db \
  "SELECT id, jira_issue, dirty, tempo_worklog_id FROM blocks WHERE dirty=1;"
worklog sync --day "$DAY" --dry-run
```

**Fix:**
```bash
worklog sync --day "$DAY"   # PUTs all dirty=1 blocks; clears flag on success
```

**Prevention:** The skill should always surface the dirty nudge after editing a synced block (this is one of the inline rules in SKILL.md). Consider end-of-day automation: `worklog sync --day $(date +%Y-%m-%d)`.

---

## Doctor output reference

`worklog doctor` (text mode) shows two sections:

**1. Environment table**
| check | value |
|-------|-------|
| home  | `~/.worklog` |
| db    | `~/.local/share/worklog/worklog.db` ("present" or "missing — run `worklog db migrate`") |
| schema | `v6` (with "N events, M blocks, K sessions, J tickets") |

**2. Secrets table** — presence/absence only, never values, for each `secrets::audit()` key.

**Gaps in doctor (what it does NOT check):**
- Daemon socket liveness
- Hook install status
- Schedule install status
- `claude` binary on PATH
- Tempo / Jira / Gcal API reachability
- `WORKLOG_TZ` validity
- Web UI (bun) liveness
- Tempo orphans

For all of those, compose the dedicated commands above.

## The 8 most important gotchas

1. **Never clear `tempo_worklog_id`.** Causes duplicate Tempo entries.
2. **`POST /sync` defaults `dry_run: true`.** Must explicitly send `{"dry_run": false}` to actually sync.
3. **`worklog sync` (CLI) is the opposite — without `--dry-run` it writes.**
4. **`WORKLOG_TZ` named zones silently fall back to UTC.** Use fixed offsets.
5. **`worklog day --json` is silent unless paired with `--no-serve`.**
6. **Hook `status` reports installed even when the binary path is stale.** Re-run `hook install` after any binary path change.
7. **Personal blocks are excluded from sync entirely** — not even surfaced as "skipped".
8. **`POST /blocks/:id/delete` may orphan in Tempo if credentials are missing.** Pre-flight check before delete.
