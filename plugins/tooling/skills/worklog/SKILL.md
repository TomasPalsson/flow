---
name: worklog
description: Operate the user's worklog time-tracker — query blocks, assign Jira tickets, fix durations, delete blocks, sync to Tempo, run setup, troubleshoot failures. Invoke when the user mentions "worklog", "timesheet", "Tempo sync", "log my time", "fill out my timesheet", "what did I work on today/yesterday/this week", "when did I last work on TICKET-N", "fix the [time] block", "the [time] block isn't [duration]", "delete the [...] block", "sync to Tempo", "worklog isn't working / no data", "set up worklog / first-time setup", "reclassify personal/work", "worklog doctor", or names any worklog subcommand directly. Also invoke whenever the user asks a time-tracking question that mentions a date, a duration, a Jira ticket key, or a block — worklog is the canonical answer in this environment. The user's standing preference: full operator with confirm-before-writes (read-only commands run freely; writes always confirm; sync ALWAYS confirms).
---

# worklog — full operator

You operate worklog on the user's behalf. worklog is a personal time-tracker that collects activity signals (Claude Code prompts via hook, GitHub commits, Google Calendar events, Jira tickets), clusters them into time blocks, lets the user assign Jira tickets, and syncs to Tempo Cloud.

## When to use

- The user mentions worklog by name, or by any subcommand name (`day`, `sync`, `infer`, `estimate`, `setup`, `doctor`, `web up`, `tag`, `hook`, etc.).
- The user asks a time-tracking question (what did I work on, when did I last work on X, fill out timesheet, sync to Tempo, fix a block, delete a block).
- The user reports a worklog problem (no data, daemon down, sync errors, missing blocks).
- The user wants to set up worklog from scratch.

## When NOT to use

- The user wants to modify worklog's own Rust/Next.js source code. That is a coding task — read CLAUDE.md and edit the repo directly, this skill is for operating the running binary.
- The user wants help with Tempo / Jira / Google Calendar in general, unrelated to worklog. Use the relevant skill or general knowledge.

## Mental model — three things to internalise

### 1. Two surfaces, not one

- **CLI (`worklog <cmd> --json`)** owns the *pipeline*: collect, infer, estimate, sync, tag, setup, doctor, hook/schedule/daemon install, web up/down. Always pass `--json` when parsing.
- **Daemon HTTP API (`http://127.0.0.1:9323`)** owns *single-block mutations*: assign ticket, set duration, set description, delete. There are **no** `worklog block ...` CLI subcommands — block edits MUST go via HTTP. The unix socket `~/.local/share/worklog/api.sock` is an alternative transport; prefer TCP for host-local automation.

### 2. The block lifecycle

```
inferred → (estimated, claude_p) → (assigned, ticket set) → (synced, tempo_worklog_id set)
                                                                       │
                                              (user edits) ──► (dirty=1) ──► (re-synced via PUT, dirty=0)
                                                                       │
                                                                  (deleted, Tempo entry also deleted)
```

`estimated_by` is an enum: `NULL` → `'claude_p'` → `'manual'` (one-way once user edits). `'gap'` means the AI estimator failed and the block needs review.

### 3. The autonomy contract

Read freely. Writes ALWAYS confirm. The user's standing rule:

| Operation | Confirm? |
|-----------|---------|
| `worklog day --no-serve --json`, `collect`, `infer`, `estimate`, all GET endpoints, all `worklog *status`, `worklog tag list`, `worklog doctor`, `worklog secret list`, `worklog version` | **No** |
| `POST /blocks/:id/{ticket,duration,description,delete}`, `worklog tag work/personal <glob>`, `worklog tag reclassify`, `worklog secret set/rm`, `worklog hook/schedule/daemon install/uninstall`, `worklog db purge`, `worklog self-update` | **Yes** |
| `worklog sync` (without `--dry-run`) OR `POST /sync {dry_run: false}` | **ALWAYS** — irreversible Tempo writes; always show dry-run preview first |

## Non-negotiable invariants

Violating any of these breaks the user's data integrity. Treat as physics, not guidelines.

1. **Never clear `tempo_worklog_id`.** Both `""` and `NULL` mean "unsynced." Any `UPDATE blocks SET tempo_worklog_id = NULL` or sync that doesn't carry the existing ID forward will cause a duplicate Tempo entry on the next sync. The skill never writes SQL directly — only via CLI/HTTP, both of which preserve the canary.

2. **Never overwrite `estimated_by = 'manual'`.** Set automatically by `/blocks/:id/duration` and `/blocks/:id/description`. The estimator and merger skip these blocks unconditionally. If the user says "re-estimate everything," explain that manual blocks are skipped by design.

3. **`POST /sync` defaults `dry_run: true`.** This is a safety against accidental double-posting from the web UI. If you POST `{"day": "..."}` without `"dry_run": false`, nothing reaches Tempo. The CLI `worklog sync` is the opposite — without `--dry-run`, it writes. Always be explicit.

4. **Assigning a ticket flips `is_personal = 0`.** Clearing a ticket does NOT touch `is_personal`. The path-classifier or `worklog tag reclassify` decides the personal/work bucket when no ticket is set.

5. **Never invoke `worklog hook-run` as a test.** It reads a raw JSON event from stdin and writes ONLY to stderr — it is wired directly into Claude Code's hook system. If you invoke it interactively or pipe anything to it, it consumes a pending hook event and emits stderr that may appear in the Claude Code session as if it were assistant output. The hook pipeline is the only legitimate caller. Reading `worklog hook status --json` is the safe way to inspect hook state.

6. **Never set `$WORKLOG_TZ` to a named zone** (e.g., `America/New_York`). The TZ parser only understands fixed offsets (`-05:00`, `+01:00`, `UTC`). Named zones fall back to UTC silently — the warning goes to the daemon log, not the terminal. Result: entire days of blocks land on the wrong date and `worklog day --day $TODAY` shows them missing. Always use a fixed offset and update it at DST transitions. The skill should run `echo $WORKLOG_TZ` as a sanity check whenever a day's block count is unexpectedly low.

7. **`worklog day --json` only emits JSON when paired with `--no-serve`.** Without `--no-serve`, the command blocks on `worklog web up` and produces no machine-readable output.

8. **Re-inference resets the dirty flag silently.** `worklog infer` (and `worklog day`, which calls it) deletes all blocks for the day and rebuilds them. The carry mechanism preserves `tempo_worklog_id`, `description`, `estimated_by`, `jira_issue` — but NOT `dirty`. Any pending local edits to a synced block become invisible to the next sync. Always pre-check for dirty blocks before re-infer; if any exist, offer to sync first.

9. **Edits to a synced block always mean "re-sync needed."** After any `POST /blocks/:id/{ticket,duration,description}` on a block whose `tempo_worklog_id` was non-empty before the edit, surface: "this block is now dirty — run `worklog sync` to update Tempo." The daemon sets `dirty = 1` automatically; the user must re-run sync. Without that follow-up, Tempo retains the old values.

## Routing — intent to recipe

Match the user's phrasing left-to-right; first match wins.

| User says | Recipe |
|-----------|--------|
| "fill out my timesheet" / "do my timesheet" / "daily pipeline" / "log my time for today" | **A — Daily timesheet** (inline below) |
| "fix the [time] block" / "[block] should be on TICKET-N" / "wrong ticket" / "reassign" | **B — Edit one block** (inline below) |
| "[block] isn't [N] minutes" / "set [block] to [N]" / "change the duration" | **B** (duration variant) |
| "delete the [time/lunch/coffee] block" / "remove block N" / "get rid of" | **B** (delete variant) |
| "worklog isn't working" / "no data" / "empty" / "daemon down" / "broken" | **C — Troubleshoot** (inline below) |
| "what did I work on [day]" / "show me [day]" / "summary of [day]" | `references/recipes.md` → Recipe 2 |
| "when did I last work on TICKET-N" / "have I worked on X recently" | `references/recipes.md` → Recipe 3 |
| "mark X as work/personal" / "reclassify" / "personal project" | `references/recipes.md` → Recipe 7 |
| "set up worklog" / "first-time setup" / "configure worklog" | `references/recipes.md` → Recipe 8 |
| "re-estimate" / "the AI estimates are wrong" | `references/recipes.md` → Recipe 10 |
| "show me unsynced" / "what's pending sync" / "any dirty blocks" | `references/recipes.md` → Recipe 11 |

If the user names a date ambiguously ("yesterday", "Tuesday"), resolve to `YYYY-MM-DD` before invoking anything: `date +%Y-%m-%d`, `date -v-1d +%Y-%m-%d` (macOS), or `date -d yesterday +%Y-%m-%d` (Linux).

## Recipe A — Daily timesheet [inlined; the most common flow]

User wants: collect → infer → estimate → review unassigned → assign tickets → sync to Tempo.

```bash
# 0. PRE-FLIGHT — check for dirty blocks before re-infer (invariant 8).
curl -s "http://127.0.0.1:9323/days/$DAY" | jq '[.blocks[] | select(.dirty == true)] | length'
# If > 0, STOP and surface to the user:
#   "Day $DAY has N dirty edits not yet synced to Tempo. Re-running the
#    daily pipeline will reset the dirty flag and your local edits won't
#    propagate to Tempo. Sync first, then continue? (worklog sync --day $DAY)"
# Wait for explicit confirmation before proceeding.
```

```bash
# 1. Run the local pipeline (idempotent; no confirm once dirty pre-flight passed).
worklog day --no-serve --json --day "$DAY"
# Output: {"day":"...","blocks":N,"minutes":M,"served":false}
# If any step errors, the command surfaces them inline and continues.
```

```bash
# 2. Read the day to find unassigned work blocks (read-only).
curl -s "http://127.0.0.1:9323/days/$DAY" \
  | jq '.blocks[] | select(.jira_issue == null and .is_personal == false)'
```

For each unassigned block, ASK the user (one confirm per block):

> "Block 09:00–10:30 (90 min, sources: claude×20, github×3) — assign to which ticket?"

On a ticket name from the user:

```bash
# 3. Assign — confirm gate met. Returns the updated Block row.
curl -s -X POST "http://127.0.0.1:9323/blocks/<ID>/ticket" \
  -H 'Content-Type: application/json' \
  -d '{"jira_issue":"GOJ-1310"}' | jq .
```

```bash
# 4. Dry-run sync (no confirm; this writes nothing).
worklog sync --day "$DAY" --dry-run --json
# Surface the result["results"] list to the user with status counts.
```

ASK before writing to Tempo. Even if the user said "fill out my timesheet" at the start, the sync is irreversible and always confirms:

> "Ready to sync N blocks to Tempo for $DAY (P new POST, Q updates PUT, R skipped). Proceed?"

```bash
# 5. Real sync (CONFIRMATION REQUIRED — Tempo writes).
worklog sync --day "$DAY" --json
# Parse {report:{synced,skipped,errors[]}, results:[...]}.
# A 200 with non-empty errors[] is a PARTIAL FAILURE — do not treat as success.
# For each entry in results[] where status == "error":
#   surface "Block <block_id> failed: <reason> (HTTP <http_status>)" verbatim.
# Common partial-failure causes and fixes:
#   - "couldn't resolve numeric issueId" → offer to run `worklog collect jira` then retry.
#   - HTTP 400 "User is invalid"         → jira_account_id not set; see troubleshooting.md §5a.
#   - HTTP 401                            → tempo_api_token expired; see troubleshooting.md §5c.
# Do NOT auto-retry. Ask the user how to proceed.
```

## Recipe B — Edit one block

Three variants share the first two steps: identify the block, then mutate. Each mutation confirms.

**Step 1 — Identify.** If the user named a time, fetch the day and match. Worklog stores `started_at` as UTC RFC3339, but the user names blocks in local time — convert using `$WORKLOG_TZ` (a fixed offset like `-05:00`; default UTC if unset). If multiple blocks match, ask the user to disambiguate by ticket or duration.

```bash
curl -s "http://127.0.0.1:9323/days/$DAY" | jq '.blocks[]'
```

**Step 2 — Confirm with old → new context.** Always show the existing values: ticket, duration, description, sync status.

**Step 3 — Mutate.** Pick one:

```bash
# Assign / reassign / clear ticket
curl -s -X POST "http://127.0.0.1:9323/blocks/<ID>/ticket" \
  -H 'Content-Type: application/json' \
  -d '{"jira_issue":"GOJ-1310"}'   # or {"jira_issue":null} to clear

# Set duration (minutes). Side effect: estimated_by becomes 'manual' (immutable).
curl -s -X POST "http://127.0.0.1:9323/blocks/<ID>/duration" \
  -H 'Content-Type: application/json' \
  -d '{"minutes":45}'

# Set description. Side effect: estimated_by becomes 'manual' (immutable).
curl -s -X POST "http://127.0.0.1:9323/blocks/<ID>/description" \
  -H 'Content-Type: application/json' \
  -d '{"description":"Fixed OAuth token refresh"}'

# Delete. If the block has tempo_worklog_id, the daemon deletes the Tempo
# entry FIRST and only proceeds with the local delete on success. You do
# NOT need to orchestrate the Tempo delete separately. Returns:
#   {"ok":true,"deleted_id":N,"deleted_tempo_id":"...|null"}
curl -s -X POST "http://127.0.0.1:9323/blocks/<ID>/delete"
```

**Step 4 — If the block was synced before the edit, surface the dirty warning.** Check the response: if the returned `Block.tempo_worklog_id` is non-empty AND `Block.dirty == true`, tell the user:

> "Block updated. Already synced as `<tempo_worklog_id>` — it's now marked dirty. Run `worklog sync --day $DAY` to push the update to Tempo."

Offer to run it. The user's standing rule: sync ALWAYS confirms.

## Recipe C — Troubleshoot "worklog isn't working"

`worklog doctor` is NOT comprehensive. It checks DB + schema + secrets only. The full diagnostic flow:

```bash
# 1. Doctor — DB, schema, secrets.
worklog doctor --json

# 2. Daemon liveness (doctor doesn't check).
curl -sf http://127.0.0.1:9323/health || echo "daemon DOWN"

# 3. Hook (doctor doesn't check).
worklog hook status --json

# 4. Schedule (doctor doesn't check).
worklog schedule status --json

# 5. Claude binary (doctor doesn't check) — only needed if estimation is failing.
which claude && claude --version

# 6. Recent event flow — proves the pipeline is alive.
worklog db info --json   # events count
```

Run these in parallel where possible. Then triage:

- Daemon down → `worklog daemon install` (recommended) or `worklog daemon` (foreground).
- Hook missing → `worklog hook install`. Idempotent.
- Schedule missing → `worklog schedule install --interval 15m`.
- No events accumulating → check secret presence in step 1; missing → `worklog setup` (interactive) or per-secret `worklog secret set KEY`.
- `claude` not on PATH → install Claude Code CLI; meanwhile blocks land in `estimated_by = 'gap'` state, recoverable via re-estimate.
- `$WORKLOG_TZ` set to a named zone (`America/New_York`) — silent UTC fallback, mis-buckets blocks. Set to a fixed offset (`-05:00`) and re-infer affected days. **Doctor does not catch this. Check explicitly with `echo $WORKLOG_TZ` if blocks are landing on the wrong day.**

For the full 13-failure catalog and decision tree, load **`references/troubleshooting.md`**.

## When to load a reference

The body covers ~80% of operations. Load a reference proactively when:

| If you need to... | Load |
|-------------------|------|
| Handle an intent not in the routing table (cross-day search, tagging, multi-day sync, retroactive edits, setup walkthrough) | `references/recipes.md` |
| Hit an HTTP endpoint not shown above, or parse a JSON shape (full schemas for Block / Event / JiraTicket / DaySummary / SyncResponse) | `references/api-reference.md` |
| Diagnose a specific known failure (Tempo 400 "User is invalid" / 400 "Issue id cannot be null" / 401 / orphan Tempo / gcal OAuth / WORKLOG_TZ silent fallback / 8 more) | `references/troubleshooting.md` |
| Reason about a block-state transition (especially: re-inference + dirty edits, merge + dirty, the carry mechanism that preserves `tempo_worklog_id` across re-infer) | `references/state-machine.md` |

References use frontmatter; load with: `Read ${CLAUDE_PLUGIN_ROOT}/skills/worklog/references/<file>.md`. The install path is `${CLAUDE_PLUGIN_ROOT}/skills/worklog/` (created by `worklog setup` or `worklog skill install`).

## Quick sanity checks before any write

Before any mutation, in order:

1. **Daemon alive?** `curl -sf http://127.0.0.1:9323/health` — if not, surface "daemon isn't running" and offer `worklog daemon install`. Don't attempt the mutation.
2. **Block actually exists?** The mutation endpoints return 500 (not 404) for missing IDs. The 500 body contains `{"error":"block <id> not found"}` — parse it before reporting "internal server error."
3. **For sync only — credentials present?** `worklog secret list --json` should show `tempo_api_token`, `jira_email` (or `jira_account_id`), `jira_base_url` all `present: true`. Otherwise sync will fail with auth errors at the per-block level (status: 200 with `errors[]` populated — partial failures don't 5xx).

## Common surfaces, summarised

- **Block JSON shape (returned by `/days/:day`, `/blocks/:day`, all mutations):**
  `id, day, jira_issue, started_at, ended_at, duration_seconds, description, estimated_by, flagged, tempo_worklog_id, is_personal, dirty` (the `/days/:day` variant also has `event_count` and `sources[]`).
- **Sync result shape:** `{day, dry_run, synced, skipped, errors[], results: [{block_id, status, tempo_id, reason, http_status}]}`. Status can be `"synced"`, `"dry-run"`, `"skipped"`, `"error"`.
- **`estimated_by`:** `null` | `"claude_p"` | `"manual"` | `"gap"`. NOT `"claude"`.

## The skill is installed

If the user is asking how to install this skill, it lives at `${CLAUDE_PLUGIN_ROOT}/skills/worklog/` and is created by `worklog setup` (interactive) or `worklog skill install` (standalone). Updating worklog binary does not auto-refresh the skill — they must re-run `worklog skill install` after a `worklog upgrade`.
