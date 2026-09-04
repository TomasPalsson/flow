---
name: worklog-state-machine
description: Block lifecycle, the five invariants, and the subtle carry/dirty/merge interactions. Load when reasoning about block state transitions — especially around re-inference, the dirty flag, the manual shield, and the tempo_worklog_id canary.
---

# Block lifecycle and invariants

## The five tables (one-liners)

| Table | Purpose |
|-------|---------|
| `events` | Raw activity signals. Deduped on `(source, source_id)`. Sources: `claude`, `github_commit`, `gcal`, `jira`. |
| `blocks` | Time blocks. The primary work unit. 13 columns. |
| `block_events` | Junction. `ON DELETE CASCADE` both ways. |
| `sessions` | Claude Code session boundaries (populated by hook). |
| `jira_tickets` | Open-ticket cache. `issue_id` is the numeric Atlassian ID required by Tempo v4. |

`PRAGMA user_version = 6` is the current schema version. All migrations are idempotent (`ALTER TABLE ... ADD COLUMN IF NOT EXISTS`).

## The block columns

| Column | Type | What it means |
|--------|------|---------------|
| `id` | INTEGER PK | Use this for cross-session references. `started_at` is NOT stable. |
| `day` | TEXT | `YYYY-MM-DD` in user's local TZ (via `$WORKLOG_TZ` fixed offset, default UTC). |
| `jira_issue` | TEXT? | NULL = unassigned, not ready for Tempo. |
| `started_at` | TEXT | UTC RFC3339, e.g. `2026-05-12T09:00:00+00:00`. Shifts on re-infer if earlier event appears. |
| `ended_at` | TEXT | UTC RFC3339. Kept in sync with `duration_seconds`. |
| `duration_seconds` | INTEGER | Authoritative duration. Estimator rounds UP to nearest 15 min. `set_duration` is verbatim. |
| `description` | TEXT? | Tempo worklog description. |
| `estimated_by` | TEXT? | `NULL` / `'claude_p'` / `'gap'` / `'manual'`. See states below. |
| `flagged` | INT | `1` when duration > 4h. UI warning only — NOT a sync gate. |
| `tempo_worklog_id` | TEXT? | The double-sync canary. Never clear. `""` and NULL both mean "unsynced". |
| `is_personal` | INT | `1` = personal, excluded from estimator + sync. |
| `dirty` | INT | `1` = edited since last sync. Triggers PUT instead of POST. Reset by successful PUT. |
| `created_at` | TEXT | Row insertion timestamp. |

## `estimated_by` states (the only valid values)

| Value | Set by | Meaning |
|-------|--------|---------|
| `NULL` | `infer` (initial) | Newly clustered; estimator hasn't run yet. |
| `'claude_p'` | `estimate` | `claude -p` filled in jira_issue / description / duration. |
| `'gap'` | `estimate` | `claude -p` errored or timed out. Block needs manual review. |
| `'manual'` | block_service writes via `/duration` or `/description` | User override. One-way — never overwritten by estimator or merger. |

The literal is `'claude_p'`, NOT `'claude'`.

## Lifecycle diagram

```
[events ingested by collectors]
        │
        ▼
   ┌────────────┐  worklog infer / POST /infer
   │  INFERRED  │  estimated_by = NULL
   └─────┬──────┘
         │
         ├── is_personal=1 (auto-classified) ──► [PERSONAL — skipped by estimator + sync]
         │
         ▼
   ┌─────────────────┐  worklog estimate / POST /estimate
   │   ESTIMATING    │  fills jira_issue, description, duration
   │   (subprocess)  │  rounds duration UP to 15-min increments
   └────────┬────────┘  validates jira_issue against jira_tickets cache
            │
            ├── success ─► estimated_by = 'claude_p'
            └── failure ─► estimated_by = 'gap'
         │
         ▼
   ┌─────────────┐  POST /blocks/:id/ticket  (jira_issue ← key, is_personal ← 0)
   │  ASSIGNED   │
   └──────┬──────┘
          │
          ▼
   ┌──────────────────┐  worklog sync / POST /sync {dry_run: false}
   │     SYNCING      │  POST /worklogs → tempo_worklog_id ← response.tempoId
   │ (or dry-run if   │  PUT  /worklogs/<id> if dirty=1 → dirty ← 0
   │  dry_run=true)   │
   └────────┬─────────┘
            │
            ▼
   ┌────────────┐  (steady state until edits)
   │   SYNCED   │
   └─────┬──────┘
         │
         │ POST /blocks/:id/{ticket,duration,description}
         │ MARK_DIRTY_IF_SYNCED: dirty ← 1 (only if was synced)
         ▼
   ┌────────────┐  worklog sync → PUT /worklogs/<tempo_worklog_id>
   │   DIRTY    │  → dirty ← 0 on 2xx
   └─────┬──────┘
         │
         │ POST /blocks/:id/delete
         │ daemon: DELETE Tempo first (if synced), then local DELETE
         ▼
      [DELETED]
       (block_events cascade)
```

## The five invariants (in priority order)

### 1. `tempo_worklog_id` is the double-sync canary

**Rule:** Never clear `tempo_worklog_id` once set. Both `""` (empty string) and `NULL` are normalised to "unsynced" by `tempo::normalise_tempo_id`.

**Why it matters:** The sync layer's WHERE clause selects blocks for POST/PUT based on:

```sql
WHERE day = ?
  AND is_personal = 0
  AND (tempo_worklog_id IS NULL OR tempo_worklog_id = '' OR dirty = 1)
```

A block whose `tempo_worklog_id` is cleared becomes a candidate for POST again → duplicate Tempo entry.

**Who can write it:** `tempo::sync_day` (after successful POST), and `tempo::delete_worklog` (clears local row after successful Tempo DELETE). Nothing else.

**Implication for the skill:** Never run raw SQL. Always use CLI or HTTP API.

### 2. `estimated_by = 'manual'` is an immutable shield

**Rule:** Any block with `estimated_by = 'manual'` is skipped by:
- `estimate::estimate_day_with` (WHERE clause excludes them)
- `estimate::merge_same_ticket_adjacent` (refuses to merge if either side is manual)
- Re-inference carries `estimated_by` through the carry mechanism

**How it gets set:** Automatically, by `block_service::set_duration` and `block_service::set_description`. The CASE is in `block_service.rs:73,101`. The user does not see "manual" being set — it happens silently when they edit.

**Implication for the skill:** Tell the user when they edit a block: "this will mark it as manual; re-estimation won't change it back."

### 3. `dirty` flag and `MARK_DIRTY_IF_SYNCED`

The mutation functions wrap `dirty` in a CASE:

```sql
dirty = CASE
  WHEN tempo_worklog_id IS NOT NULL AND tempo_worklog_id != ''
  THEN 1
  ELSE dirty
END
```

This means:
- **Unsynced block edited** → `dirty` stays at 0. The next sync picks it up via `tempo_worklog_id IS NULL` anyway, so no flag is needed.
- **Synced block edited** → `dirty` set to 1. Next sync does a PUT (update) instead of POST (which would create a duplicate Tempo entry).
- **Successful PUT** → `dirty` reset to 0.

**Implication for the skill:** After any mutation, check the returned `Block.dirty`. If `true`, surface "re-sync to update Tempo." Without that follow-up, Tempo retains the old values.

### 4. Assigning a ticket flips `is_personal = 0`

**Rule:** `POST /blocks/:id/ticket {jira_issue: "PROJ-1"}` sets BOTH `jira_issue = 'PROJ-1'` AND `is_personal = 0`. Clearing a ticket (`jira_issue: null`) does NOT touch `is_personal`.

**Why:** A block with a real ticket is, by definition, work. The path-classifier (which decides personal/work from the dominant project_path) might disagree, but the user-supplied ticket overrides. This is the same rule `personal::reclassify_blocks` and `infer::persist_blocks` use: `new_personal = path_personal && jira_issue.is_none()`.

**Implication for the skill:** If the user assigns a ticket to a block that was personal, the personal pill disappears. Tell them.

### 5. `started_at` shifts across re-inference

**Rule:** Re-running `worklog infer` for a day **deletes all blocks for that day and re-inserts**. The carry mechanism (in `infer::persist_blocks`) preserves columns from prior rows:
- **Strict match:** new block's `started_at` matches old block's `started_at` exactly.
- **Overlap fallback:** find any unclaimed prior block whose time range overlaps the new block's range.

Columns carried: `tempo_worklog_id`, `description`, `estimated_by`, `jira_issue`. **Not carried: `dirty`.**

**Implication for the skill:** If the user has dirty edits and you re-infer, `dirty = 1` becomes `dirty = 0`. `tempo_worklog_id` is preserved (so no duplicate), but the local edit is "forgotten" by the dirty filter. The PUT will not fire. **Never re-infer when blocks are dirty without confirming with the user first.**

Also: `started_at` is not a stable identifier across re-infer runs. Always use `id` for cross-session block references.

## The carry mechanism (re-infer safety) — detail

`infer::persist_blocks` runs in two phases when re-clustering events into blocks:

1. **Build new blocks** from raw events (deletes existing blocks for the day first).
2. **Carry forward** from the OLD blocks (which it captured into a HashMap before delete):
   - First pass: try strict `started_at` match. Mark prior row "claimed."
   - Second pass for unmatched new blocks: try overlap match against unclaimed priors.
   - Third pass: leave new block as-is (no carry).

Failure modes:
- Two new blocks both overlap the same prior → only the first claims it; the second loses its `tempo_worklog_id`.
- Backfilled earlier event shifts a block's `started_at` enough to break exact match → overlap fallback usually catches it.

## Merge logic (post-estimate)

After the estimator runs, `merge_same_ticket_adjacent` folds consecutive blocks with the same `jira_issue` into one. Safety gates:

- Both blocks must be unsynced (`tempo_worklog_id IS NULL OR ''`).
- Neither block can be `estimated_by = 'manual'`.

Merged block takes `min(started_at)`, `max(ended_at)`, recomputed `duration_seconds`. Junction rows in `block_events` are re-pointed via `INSERT OR IGNORE`. The merged block's `dirty` flag is NOT set by the merge (this is an open question — if the surviving block was previously synced, the merge changes duration without flagging it). Currently the safety gate prevents this case by requiring both blocks to be unsynced.

## Sync query (verbatim from `tempo.rs`)

```sql
SELECT id, jira_issue, started_at, duration_seconds, description, tempo_worklog_id, dirty
FROM blocks
WHERE day = ?1
  AND is_personal = 0
  AND (tempo_worklog_id IS NULL OR tempo_worklog_id = '' OR dirty = 1)
ORDER BY started_at
```

Blocks where `jira_issue IS NULL` are skipped INSIDE the loop (logged as `"skipped"`, reason `"no jira_issue"`). They are NOT excluded by the WHERE clause — this is intentional so the dry-run can list them.

## Personal block subtleties

- `is_personal = 1` blocks have `estimated_by = NULL` after infer (the estimator skips them WITHOUT stamping `gap`). This is so reclassify-to-work can recover them later: the next `estimate` run will pick them up because `estimated_by IS NULL`.
- Reclassify (`worklog tag reclassify`) updates `is_personal` based on the current path config + ticket rule. It does NOT flip blocks that have a `jira_issue` set (the ticket override always wins).
- Personal blocks never appear in sync results — they're excluded by the WHERE clause, not surfaced as "skipped."

## Secret keys (`secrets::KNOWN_KEYS`)

All 11 stored in OS keychain under service `"worklog"`. Read priority: env var → keychain → legacy `~/.config/worklog/.env`.

| Key | Env var | Used by |
|-----|---------|---------|
| `jira_email` | `WORKLOG_JIRA_EMAIL` | Jira auth; fallback for `authorAccountId` |
| `jira_api_token` | `WORKLOG_JIRA_TOKEN` | Jira REST API Basic auth |
| `jira_base_url` | `WORKLOG_JIRA_BASE_URL` | Jira instance URL |
| `jira_account_id` | `WORKLOG_JIRA_ACCOUNT_ID` | Tempo `authorAccountId` (preferred over jira_email) |
| `github_token` | `WORKLOG_GITHUB_TOKEN` | GitHub collector |
| `github_user` | `WORKLOG_GITHUB_USER` | GitHub collector |
| `tempo_api_token` | `WORKLOG_TEMPO_TOKEN` | Tempo Bearer auth |
| `google_client_id` | `WORKLOG_GOOGLE_CLIENT_ID` | gcal OAuth |
| `google_client_secret` | `WORKLOG_GOOGLE_CLIENT_SECRET` | gcal OAuth |
| `google_refresh_token` | `WORKLOG_GOOGLE_REFRESH_TOKEN` | gcal OAuth |
| `anthropic_api_key` | `ANTHROPIC_API_KEY` | `claude -p` subprocess |
