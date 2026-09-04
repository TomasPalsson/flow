---
name: worklog-api-reference
description: Full reference for the worklog daemon HTTP API + CLI subcommand JSON shapes. Load when you need to hit an endpoint not shown in SKILL.md, parse a response shape, or look up the precise CLI flag for a given operation.
---

# API reference

## Daemon HTTP API

Two transports bound simultaneously:
- **TCP:** `127.0.0.1:9323` (preferred for host-local automation).
- **Unix socket:** `~/.local/share/worklog/api.sock` (override via `WORKLOG_HOME=<dir>` → `<dir>/api.sock`, or `WORKLOG_SOCKET=<path>`). Default perms `0666`; override with `WORKLOG_SOCKET_MODE`.

No auth. Security boundary = localhost-only TCP + filesystem ACL on the socket directory.

Error shape on every endpoint: `{"error": "human-readable message"}`. There is **no 404 in this API** — missing block IDs return `500` with `{"error":"block <id> not found"}`. `GET /blocks/:id/events` doesn't validate block existence at all; it returns `[]` for a nonexistent ID.

### Liveness

#### `GET /health`
```
→ 200 {"ok":true,"version":"0.6.0"}
```
No DB touch. If down, connection itself fails (ECONNREFUSED for TCP, ENOENT/ECONNREFUSED for socket).

### Reads

#### `GET /days/:day` — primary read endpoint (v0.6)
```
→ 200 {
    "day": "2026-05-12",
    "total_seconds": 21600,
    "blocks": [
      {
        "id": 42, "day": "2026-05-12", "jira_issue": "PROJ-42",
        "started_at": "2026-05-12T09:00:00+00:00",
        "ended_at": "2026-05-12T10:30:00+00:00",
        "duration_seconds": 5400,
        "description": "Implement OAuth", "estimated_by": "claude_p",
        "flagged": false, "tempo_worklog_id": null,
        "is_personal": false, "dirty": false,
        "event_count": 5,
        "sources": [{"source":"claude","n":3},{"source":"github_commit","n":2}]
      }
    ]
  }
```
Empty day → `{"day":"...","total_seconds":0,"blocks":[]}`. Never 404.

#### `GET /blocks/:day` — legacy flat read
Returns `[Block, ...]` without `event_count` or `sources`. Prefer `/days/:day`. Same `:day` format.

#### `GET /blocks/:id/events`
```
→ 200 [Event, ...]
```
Ordered by `started_at` ASC. Returns `[]` for any ID — does NOT validate block existence.

#### `GET /tickets`
```
→ 200 {
    "tickets": [{
      "key":"PROJ-1","summary":"...","status":"In Progress",
      "project_key":"PROJ","updated":"2026-05-12T10:00:00Z",
      "issue_id":"10001"
    }],
    "meta": {"count":1,"last_fetched":"2026-05-12T10:00:00Z"}
  }
```
Cold cache → `{"tickets":[],"meta":{"count":0,"last_fetched":null}}`. `issue_id` is the numeric Atlassian ID required by Tempo v4.

### Block mutations (always return the updated Block row)

#### `POST /blocks/:id/ticket`
```
body: {"jira_issue":"PROJ-1"}  // or {"jira_issue":null} to clear
→ 200 Block
```
Side effects: sets `jira_issue`; if non-null, also sets `is_personal = 0`; sets `dirty = 1` IF was synced.

#### `POST /blocks/:id/duration`
```
body: {"minutes":45}  // u32, non-negative
→ 200 Block
```
Side effects: sets `duration_seconds = minutes*60`; recomputes `ended_at = started_at + duration`; sets `estimated_by = 'manual'`; sets `dirty = 1` IF was synced.

#### `POST /blocks/:id/description`
```
body: {"description":"Refactored token refresh"}  // empty string = clear
→ 200 Block
```
Side effects: sets `description`; sets `estimated_by = 'manual'`; sets `dirty = 1` IF was synced.

#### `POST /blocks/:id/delete`
```
body: (none — empty body OR {} OR no Content-Type all accepted)
→ 200 {"ok":true,"deleted_id":N,"deleted_tempo_id":"tw-12345"|null}
→ 500 if Tempo delete failed (local block preserved)
```
The daemon calls Tempo DELETE first if the block has a `tempo_worklog_id`. Tempo 404 is treated as success. If credentials are absent, daemon logs a WARN and proceeds with local-only delete — `deleted_tempo_id` will be `null` but the Tempo entry orphans.

### Operations

#### `POST /infer`
```
body: {"day":"2026-05-12"}
→ 200 {"day":"...","blocks":N,"minutes":M}
→ 400 {"error":"invalid day '<val>': ..."}
```
Re-clusters events for the day. Deletes existing blocks for the day first; carry mechanism preserves `tempo_worklog_id`, `description`, `estimated_by`, `jira_issue` from prior rows. Does NOT carry `dirty`. Web client timeout: 30s.

#### `POST /jira/refresh`
```
body: (none)
→ 200 {"tickets_written":N,"source":"jira-api"}
→ 500 if credentials missing or Jira unreachable
```
Refreshes the open-ticket cache. Holds the daemon mutex while the HTTP call runs — can block other endpoints for 10–30s.

#### `POST /estimate`
```
body: {"day":"2026-05-12","model":"claude-haiku-4-5"}  // model optional
→ 200 {"day":"...","estimated":N,"skipped":M,"failed":F}
→ 400 invalid day
→ 500 DB / spawn error
```
Shells out to `claude -p` per un-estimated block. Skips `'manual'`, `'claude_p'`, personal. Failures land in `estimated_by = 'gap'`. Web client timeout: 60s. CLI has no timeout — `worklog estimate` can run 5+ minutes on a 20-block backlog.

#### `POST /sync`
```
body: {"day":"2026-05-12","dry_run":false}
→ 200 {
    "day":"...","dry_run":false,
    "synced":N,"skipped":M,"errors":[...],
    "results":[
      {"block_id":1,"status":"synced","tempo_id":"67890"},
      {"block_id":3,"status":"skipped","reason":"no jira_issue"}
    ]
  }
```

**CRITICAL:** `dry_run` defaults to `true` if the field is omitted. To actually sync, **explicitly send `{"dry_run": false}`.**

`status` enum: `"synced"` / `"dry-run"` / `"skipped"` / `"error"`. Per-block failures land in `results[].status = "error"` AND `errors[]` — they do NOT cause a 5xx. Status code 200 with non-empty `errors[]` is the normal partial-failure shape.

WHERE clause for the sync iterator:
```sql
WHERE day = ?1 AND is_personal = 0
  AND (tempo_worklog_id IS NULL OR tempo_worklog_id = '' OR dirty = 1)
```

Blocks without `jira_issue` are skipped inside the loop (status `"skipped"`, reason `"no jira_issue"`). Web client timeout: 30s.

---

## Block JSON shape (canonical)

```typescript
interface Block {
  id: number;
  day: string;                  // "YYYY-MM-DD"
  jira_issue: string | null;
  started_at: string;           // ISO-8601 UTC, "+00:00" suffix
  ended_at: string;
  duration_seconds: number;
  description: string | null;
  estimated_by: "claude_p" | "manual" | "gap" | null;
  flagged: boolean;             // duration > 4h
  tempo_worklog_id: string | null;
  is_personal: boolean;
  dirty: boolean;
  // present only on GET /days/:day:
  event_count?: number;
  sources?: { source: string; n: number }[];
}
```

`estimated_by` values: NOT `"claude"` — it's `"claude_p"`. The TS type narrows it but the API will accept any string the DB has.

## Event JSON shape

```typescript
interface Event {
  id: number;
  source: string;               // "claude" | "github_commit" | "gcal" | "jira" | ...
  source_id: string;
  started_at: string;
  ended_at: string | null;
  duration_seconds: number | null;
  title: string;
  details: string | null;       // Claude prompts include full text (≤4KiB)
  repo: string | null;
  project_path: string | null;  // working directory; only on `claude` events
  jira_issue: string | null;
  session_id: string | null;
  tempo_worklog_id: string | null;
  raw_json: string | null;
}
```

## JiraTicket JSON shape

```typescript
interface JiraTicket {
  key: string;                  // "PROJ-1"
  summary: string;
  status: string | null;
  project_key: string | null;
  updated: string | null;
  issue_id: string | null;      // Atlassian numeric ID — required by Tempo v4
}
```

---

## CLI JSON shapes

Pass `--json` on any subcommand. Globally available flags: `--home <PATH>` (or `WORKLOG_HOME`), `--json`.

### `worklog version --json`
```
{"version":"0.6.0","core":"..."}
```

### `worklog doctor --json`
```
{
  "version":"0.6.0",
  "home":"/Users/you/.worklog",
  "db_path":"...",
  "db_exists":true,
  "db":{"schema_version":6,"events":1234,"blocks":89,"sessions":45,"jira_tickets":67},
  "secrets":[{"key":"jira_email","present":true}, ...]
}
```
Does NOT check: daemon liveness, hook install, schedule install, `claude` binary, `WORKLOG_TZ` validity. Cover those gaps with the dedicated `*status` subcommands + `curl /health`.

### `worklog db info --json`
```
{"schema_version":6,"events":1234,"blocks":89,"sessions":45,"jira_tickets":67}
```

### `worklog db migrate --json`
```
{"ok":true,"path":"...","schema_version":6}
```

### `worklog db purge --json`
```
{
  "cutoff_date":"2025-04-12",
  "blocks_deleted":12,"events_deleted":145,
  "blocks_kept_unsynced":3,"blocks_kept_manual":1,
  "dry_run":false
}
```
Safety rails baked in: never deletes unsynced blocks, never deletes `estimated_by = 'manual'`. Always run with `--dry-run` first.

### `worklog secret list --json`
```
[{"key":"jira_email","present":true}, ...]
```
Never exposes values.

### `worklog collect --json`
```
[
  {"source":"jira","tickets_written":5,"events_written":0,"synced":0,"skipped":0,"errors":[]},
  {"source":"github","tickets_written":0,"events_written":12,"synced":0,"skipped":0,"errors":[]}
]
```
Missing credentials → that source is silently skipped (info message, not error).

### `worklog infer --json`
```
[
  {
    "day":"2026-05-12","started_at":"...","ended_at":"...",
    "duration_seconds":5400,"event_count":23,"event_ids":[1,2,3],
    "jira_issue":"PROJ-42","flagged":false
  }
]
```
`is_calendar` and `events` are `#[serde(skip)]` — don't expect them.

### `worklog estimate --json`
```
{"estimated":3,"skipped":1,"failed":0}
```

### `worklog day --json --no-serve`
```
{"day":"2026-05-12","blocks":5,"minutes":240,"served":false}
```
**Without `--no-serve`, no JSON is emitted** — the command blocks on `worklog web up`. Always pair `--json --no-serve` for scripting.

### `worklog sync --json`
```
{
  "report":{"source":"tempo","tickets_written":0,"events_written":0,"synced":2,"skipped":1,"errors":[]},
  "results":[
    {"block_id":42,"status":"synced","reason":null,"tempo_id":"12345","payload":{...},"http_status":200},
    {"block_id":43,"status":"skipped","reason":"no jira_issue","tempo_id":null,"payload":null,"http_status":null}
  ]
}
```
Pass `--dry-run` to preview. The CLI sync is the OPPOSITE of `POST /sync`: without `--dry-run`, the CLI actually writes.

### `worklog tag list --json`
```
{
  "config_path":"~/.config/worklog/personal.toml",
  "work":["~/Desktop/Work/client-a/**"],
  "personal":["~/Desktop/Projects/hobby/**"],
  "default_rule":"any project_path under ~/Desktop/Work/** is work; everything else is personal"
}
```

### `worklog tag personal|work <GLOB> --json`
```
{"status":"added"|"noop","kind":"work","glob":"...","config_path":"..."}
```

### `worklog tag reclassify --json`
```
{"total":20,"changed_to_personal":3,"changed_to_work":1,"unchanged":16}
```

### `worklog hook status --json`
```
{
  "settings_path":"~/.claude/settings.json",
  "installed":true,
  "events":["SessionStart","UserPromptSubmit","Stop","SubagentStop","SessionEnd"],
  "command":"worklog hook-run"
}
```

### `worklog schedule status --json`
```
{
  "platform":"launchd",
  "installed":true,
  "interval_secs":900,
  "command":"worklog collect all",
  "unit_path":"...",
  "extra_paths":[],
  "notes":[]
}
```
Same shape for `install` / `uninstall`. Interval formats accepted by `--interval`: `5m`, `15m`, `30m`, `1h`, `4h`, `daily`, or raw seconds.

### `worklog daemon status --json`
Same general shape (`{"installed":bool,"platform":...,...}`).

### `worklog web up --json`
```
{"ok":true,"url":"http://localhost:3333","pid":12345,"context":"...","log":"..."}
```
Auto-installs the daemon if not running (unless `--no-daemon`). Default port 3333.

### `worklog self-update --check --json`
```
{"current":"0.6.0","latest":"0.7.0","up_to_date":false,"notes":"changelog snippet"}
```

### `worklog self-update --json` (full upgrade)
```
{"from":"0.6.0","to":"0.7.0","used_delta":true,"asset_bytes":1234567,"dry_run":false,"rolled_back":false,"daemon_restart":"Restarted"}
```

## CLI flag matrix (which command supports what)

| Subcommand | `--json` | `--day` | `--dry-run` | Other notable |
|------------|----------|---------|-------------|---------------|
| `version` | ✅ | — | — | — |
| `doctor` | ✅ | — | — | — |
| `setup` | — | — | — | `--non-interactive`, `--skip-validate` |
| `db migrate/info` | ✅ | — | — | — |
| `db path` | — | — | — | always prints raw path |
| `db purge` | ✅ | — | ✅ | `--days N` (default 30) |
| `secret list/set/get/rm` | list✅ | — | — | `secret set --value` is insecure (use stdin) |
| `hook install/uninstall/status` | ✅ | — | — | `install --command <CMD>` |
| `schedule install/uninstall/status` | ✅ | — | — | `install --interval <I>`, `--command <CMD>` |
| `collect` | ✅ | — | — | `[all\|jira\|github\|gcal]`, `--days N` |
| `infer` | ✅ | ✅ | — | — |
| `estimate` | ✅ | ✅ | — | `--model <M>` (default claude-haiku-4-5) |
| `day` | ✅ (with `--no-serve`) | ✅ | — | `--no-serve`, `--model <M>` |
| `sync` | ✅ | ✅ | ✅ | — |
| `tag list/personal/work/reclassify` | ✅ | reclassify ✅ | — | personal/work `<GLOB>` |
| `daemon` (foreground) | — | — | — | `--socket <P>`, `--tcp <ADDR>` |
| `daemon install/uninstall/status` | ✅ | — | — | `install --command <CMD>` |
| `web up/down/status/build/fetch` | ✅ | — | — | `up --port <N>`, `--no-daemon` |
| `web logs` | — | — | — | `--tail N`, blocks until Ctrl-C |
| `self-update` (alias `upgrade`) | ✅ | — | ✅ | `--check`, `--force`, `--manifest-url <URL>` |

## Detecting transport

The web client (`web/lib/daemon.ts`) chooses transport in this order:
1. `WORKLOG_DAEMON_URL` set → TCP at that base URL.
2. `WORKLOG_SOCKET` set → that unix socket.
3. Default → `~/.local/share/worklog/api.sock`.

For host-local shell scripts, just use `http://127.0.0.1:9323`. It always works.

## curl recipe templates

```bash
# Liveness
curl -sf "http://127.0.0.1:9323/health"

# Read a day
curl -s "http://127.0.0.1:9323/days/2026-05-12"

# Block edit
curl -s -X POST "http://127.0.0.1:9323/blocks/42/ticket" \
  -H 'Content-Type: application/json' \
  -d '{"jira_issue":"PROJ-1"}'

# Dry-run sync (the default if dry_run is omitted; explicit is clearer)
curl -s -X POST "http://127.0.0.1:9323/sync" \
  -H 'Content-Type: application/json' \
  -d '{"day":"2026-05-12","dry_run":true}'

# Real sync — only after explicit user confirmation
curl -s -X POST "http://127.0.0.1:9323/sync" \
  -H 'Content-Type: application/json' \
  -d '{"day":"2026-05-12","dry_run":false}'
```
