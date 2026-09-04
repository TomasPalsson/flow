---
name: worklog-recipes
description: Full command sequences for every common user intent — daily timesheet, day reads, cross-day ticket search, single-block edits, deletes, personal/work tagging, setup, troubleshooting, re-estimation, unsynced scan. Load when the SKILL.md routing table points here, or when the user's intent doesn't match recipes A/B/C in the body.
---

# Recipe catalog

Each recipe: example phrasings → command sequence → confirmation gates → user-facing summary template.

Conventions:
- `$DAY` is `YYYY-MM-DD`. Resolve from natural language before invoking.
- Daemon address: `http://127.0.0.1:9323` (TCP) or `--unix-socket ~/.local/share/worklog/api.sock http://worklog` (unix).
- Always pass `--json` to CLI commands you'll parse.
- Tag legend: `[R]` = read-only, no confirm; `[W-L]` = write-local, confirm; `[W-R]` = write-remote (Tempo), ALWAYS confirm.

---

## Recipe 1 — Daily timesheet (inlined in SKILL.md body — refer there)

The five-step flow is in SKILL.md under "Recipe A — Daily timesheet". This entry exists so the routing table can link consistently.

---

## Recipe 2 — "What did I work on today / yesterday / this week" [R]

**Phrasings:** "what did I work on today?" / "show me yesterday" / "summary of Tuesday" / "what was I doing this week?"

**Day resolution:**
- `today` → `date +%Y-%m-%d`
- `yesterday` → macOS `date -v-1d +%Y-%m-%d`; Linux `date -d yesterday +%Y-%m-%d`
- `this week` → iterate Mon → today
- Named day ("Tuesday") → compute offset from today, resolve

**Single day:**

```bash
curl -s "http://127.0.0.1:9323/days/$DAY" | jq .
```

Response: `{ day, total_seconds, blocks: [{ id, jira_issue, started_at, ended_at, duration_seconds, description, estimated_by, flagged, tempo_worklog_id, is_personal, dirty, event_count, sources: [{source, n}] }] }`.

**Multi-day (week):** loop `$DAY` from Mon → today, aggregate. There is no cross-day endpoint.

**Format for the user (local time using `$WORKLOG_TZ`):**

```
Tuesday 2026-05-12 — 6h 30m work (3 blocks) · 30m personal
  09:00–10:30  90m  GOJ-1310   "Fixed OAuth token refresh"     [synced]
  11:00–12:00  60m  GOJ-1405   "Code review – PR #42"          [synced]
  14:00–15:45  105m (unassigned)                                [pending]
  16:00–16:30  30m  (personal)
```

Render rules:
- Synced + clean → `[synced]`
- Synced + dirty → `[unsynced edits — re-sync to update Tempo]`
- Unsynced + has ticket → `[pending sync]`
- Unsynced + no ticket → `[needs ticket]`
- Personal → `(personal)` and collapse if the user didn't explicitly ask

---

## Recipe 3 — "When did I last work on TICKET-N" [R]

**Phrasings:** "when did I last work on GOJ-1310?" / "have I worked on PROJ-42 recently?" / "what days did I log time to GENAI-1219?"

**Strategy:** There is no cross-day search endpoint. Walk backward from today.

```bash
for offset in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
  DAY=$(date -v-${offset}d +%Y-%m-%d)   # macOS
  curl -s "http://127.0.0.1:9323/days/$DAY" \
    | jq --arg ticket "$TICKET" \
      '.blocks[] | select(.jira_issue == $ticket) | {DAY: "'"$DAY"'", started_at, ended_at, duration_seconds, description, tempo_worklog_id}'
done
```

Stop at the first match (unless the user asked "what days" → collect all). If nothing in 14 days, offer to extend.

**Format for the user:**

```
Last worked on GOJ-1310:
  2026-05-10 (Sat)  09:00–10:30   90m  "OAuth fix"          [synced]
  Also: 2026-05-08 (Thu)  14:00–15:00  60m  "Review"        [synced]
```

If a result has `tempo_worklog_id == null` and `dirty == false`, prefix with `[not synced]`.

---

## Recipe 4 — "Fix the [time] block — should be on TICKET-N" [W-L]

**Phrasings:** "the 11:15 block should be on GOJ-1310" / "reassign the morning block to PROJ-42" / "fix block 47 — ticket is PROJ-9" / "wrong ticket on that 2-hour block"

**Step 1 — Identify the block.** If named by time, convert local → UTC using `$WORKLOG_TZ` (fixed offset like `-05:00`; default UTC) and match on `started_at`. If named by ID, skip the lookup.

```bash
curl -s "http://127.0.0.1:9323/days/$DAY" \
  | jq '.blocks[] | select(.started_at | startswith("'"$DAY"'T'"$LOCAL_HH:MM"'")) | {id, jira_issue, duration_seconds, description, tempo_worklog_id, dirty}'
```

If multiple blocks match (overlapping starts or close-by), disambiguate with the user:

> "I found 2 blocks around 11:15 — block 47 (10:45–11:30, 45m, GOJ-100) and block 48 (11:15–12:00, 45m, unassigned). Which one?"

**Step 2 — Verify the ticket exists in the Jira cache** (avoid typos):

```bash
curl -s "http://127.0.0.1:9323/tickets" | jq --arg k "$TICKET" '.tickets[] | select(.key == $k)'
```

Empty result → warn the user but allow override: "GOJ-1310 isn't in your ticket cache. Assign anyway?"

**Step 3 — Confirm.**

> "Block 11:15–13:15 (120m, currently GOJ-999) → reassign to GOJ-1310?"

**Step 4 — Assign.**

```bash
curl -s -X POST "http://127.0.0.1:9323/blocks/$ID/ticket" \
  -H 'Content-Type: application/json' \
  -d "{\"jira_issue\":\"$TICKET\"}" | jq .
```

**Step 5 — If returned `Block.dirty == true`**, surface the re-sync nudge (and offer to run sync, which confirms separately).

**Summary template:**

> "Block 11:15–13:15 reassigned GOJ-999 → GOJ-1310. {Block is now marked dirty — re-sync to update Tempo entry tw-12345.}"

---

## Recipe 5 — "That block isn't [duration]" [W-L]

**Phrasings:** "the 14:00 block is only 45 minutes" / "set block 47 to 30 minutes" / "fix the duration — was only 30m" / "change the 2-hour block to 1 hour"

**Step 1 — Identify** (same as Recipe 4).

**Step 2 — Warn early if synced.**

> "This block was synced to Tempo (id: tw-12345). Changing the duration will mark it 'manual' (the AI won't auto-overwrite it) AND dirty (re-sync will PUT to Tempo)."

**Step 3 — Confirm with explicit before / after.**

> "Block 14:00–15:30 (currently 90m, GOJ-1310) → set to 45m (will end at 14:45)?"

**Step 4 — Apply.**

```bash
curl -s -X POST "http://127.0.0.1:9323/blocks/$ID/duration" \
  -H 'Content-Type: application/json' \
  -d "{\"minutes\":$MINUTES}" | jq .
```

Side effects in the response: `duration_seconds` = `MINUTES * 60`, `ended_at` recomputed, `estimated_by = "manual"`, `dirty = 1` if was synced.

**Step 5 — If was synced, offer re-sync.** Always confirms separately.

**Summary template:**

> "Block 14:00–14:45 — 45m, marked manual. {Re-sync to update Tempo tw-12345.}"

### Setting the description follows the same pattern

```bash
curl -s -X POST "http://127.0.0.1:9323/blocks/$ID/description" \
  -H 'Content-Type: application/json' \
  -d "{\"description\":\"Refactored token refresh to use rotating secrets\"}"
```

Same `estimated_by = 'manual'` and dirty-on-synced semantics.

---

## Recipe 6 — "Delete the [...] block" [W-L for unsynced, W-R for synced]

**Phrasings:** "delete the lunch block" / "remove the 12:00 block" / "get rid of block 47" / "coffee break block is wrong, delete it"

**Step 1 — Identify** (same as Recipe 4).

**Step 2 — Read sync status from the block.** If `tempo_worklog_id` is non-empty:

> "Block 12:00–13:00 (60m, GOJ-lunch, synced as tw-12345) — deleting this also DELETES the Tempo worklog. Cannot be undone. Confirm?"

If unsynced:

> "Block 12:00–13:00 (60m, unassigned) — delete? (local only, not in Tempo yet.)"

**Step 3 — Delete.**

```bash
curl -s -X POST "http://127.0.0.1:9323/blocks/$ID/delete"
```

Response: `{"ok": true, "deleted_id": N, "deleted_tempo_id": "tw-12345"|null}`.

**Critical:** The daemon handles the Tempo DELETE first. If Tempo fails, the local block is preserved and the response is 500 with `{"error": "..."}`. Do NOT separately orchestrate the Tempo delete.

If `deleted_tempo_id` is `null` AND the block previously had a `tempo_worklog_id`, the daemon ran the local delete but skipped Tempo because credentials were missing — the Tempo entry orphaned. Tell the user explicitly so they can clean it up in Tempo's UI.

**Summary template:**

> "Deleted block 12:00–13:00. {Tempo worklog tw-12345 also removed. | Local only — Tempo credentials were missing, the Tempo entry remains and must be cleaned up manually.}"

---

## Recipe 7 — "Mark X as work/personal" [W-L, two confirms]

**Phrasings:** "mark ~/Desktop/Projects/sjukra as work" / "everything in sjukra/ is work" / "add ~/Desktop/personal-stuff as personal" / "the ai-news project is personal"

**Step 1 — Show current rules** (read-only).

```bash
worklog tag list --json
```

Output: `{ config_path, work: [globs], personal: [globs], default_rule }`. Default rule: any project_path under `~/Desktop/Work/**` is work; everything else is personal.

**Step 2 — Resolve and confirm the glob.**

> "Will add `~/Desktop/Projects/sjukra/**` to the work patterns. OK?"

**Step 3 — Add the pattern.**

```bash
worklog tag work "~/Desktop/Projects/sjukra/**" --json
# OR
worklog tag personal "~/Desktop/Projects/hobby/**" --json
```

Response: `{ status: "added"|"noop", kind, glob, config_path }`.

**Step 4 — Offer to reclassify existing blocks.** This is a separate confirmation.

> "Apply to existing blocks too? This re-evaluates is_personal for past blocks. Note: blocks with an assigned ticket are NEVER flipped to personal (the ticket override always wins)."

```bash
worklog tag reclassify --json
# Or scoped to a single day:
worklog tag reclassify --day "$DAY" --json
```

Response: `{ total, changed_to_personal, changed_to_work, unchanged }`.

**Summary template:**

> "Added `~/Desktop/Projects/sjukra/**` to work patterns. Reclassified 12 blocks: 5 → work, 0 → personal, 7 unchanged (had tickets)."

---

## Recipe 8 — "Set up worklog / first-time install" [W-L, multi-step]

**Phrasings:** "help me set up worklog" / "first-time setup" / "configure worklog" / "I just installed worklog"

**Step 1 — Doctor the current state** (read-only).

```bash
worklog doctor --json
```

Surface what's already present so the user knows what's new vs idempotent.

**Step 2 — Explain what's about to happen** BEFORE invoking the wizard. The wizard is interactive — Claude should not drive it through stdin. Explain each secret:

| Secret | Where to get it |
|--------|-----------------|
| `jira_email` | The user's Atlassian account email. |
| `jira_api_token` | https://id.atlassian.com → Security → API tokens. Atlassian tokens don't expire unless revoked. |
| `jira_base_url` | `https://<workspace>.atlassian.net` (include the scheme). |
| `jira_account_id` | The wizard skips this — sync auto-resolves via Jira `/myself` and caches. Skip in the wizard. |
| `github_token` | GitHub PAT with `repo` + `read:user` scopes. https://github.com/settings/tokens |
| `tempo_api_token` | Tempo UI → My Work → Tempo Settings → API integration. |
| `anthropic_api_key` | https://console.anthropic.com — for `claude -p` estimation. |
| `google_client_*` + `refresh_token` | OAuth client from Google Cloud Console. Setting these up is a 10-step exercise — optional, skip if user doesn't use Google Calendar. |

**Step 3 — Hand off to the wizard.** Confirm with the user that they're ready.

```bash
worklog setup
```

The wizard runs six steps: (1) db migrate, (2) preflight (docker/claude/git probes), (3) secret capture, (4) Claude Code hook install, (5) scheduled collection install (default every 15m), (6) daemon auto-start install. The user drives the interactive prompts; Claude waits.

**Step 4 — Verify and first run.**

```bash
worklog doctor --json
worklog day --no-serve --json --day "$(date +%Y-%m-%d)"
worklog web up
```

Then explain how to review at `http://localhost:3333`.

**Summary template:**

> "Setup complete. Schema v6, X secrets configured, hook installed, daemon running. Run `worklog day` daily to refresh, or let the schedule do it every 15m."

---

## Recipe 9 — "worklog isn't working / no data" [R then triage]

Inlined in SKILL.md as Recipe C. The full failure catalog with detection commands and recovery paths is in **references/troubleshooting.md**.

---

## Recipe 10 — "Re-estimate today's blocks" [W-L, no confirm]

**Phrasings:** "re-estimate today" / "the Claude estimates are wrong, redo them" / "estimate yesterday's blocks"

**Important caveat:** `worklog estimate` SKIPS blocks where `estimated_by = 'manual'`. It never clobbers manual edits. If the user explicitly set duration or description via the UI/API, those blocks stay frozen.

**Step 1 — Show current state.**

```bash
curl -s "http://127.0.0.1:9323/days/$DAY" \
  | jq '.blocks | {
      total: length,
      already_estimated: [.[] | select(.estimated_by == "claude_p")] | length,
      manual: [.[] | select(.estimated_by == "manual")] | length,
      gaps: [.[] | select(.estimated_by == "gap")] | length,
      unestimated: [.[] | select(.estimated_by == null and .is_personal == false)] | length
    }'
```

Tell the user how many will be skipped vs estimated.

**Step 2 — Re-estimate.**

```bash
worklog estimate --day "$DAY" --json
```

Response: `{ estimated, skipped, failed }`. `skipped` includes manual + personal + already-estimated blocks.

**Step 3 — Show the result.** Re-fetch `/days/$DAY` and surface the diff.

**Force re-estimation of `'gap'` blocks only.** There's no `--force` flag. The targeted SQL below is safe — it touches ONLY `'gap'` blocks and explicitly excludes `'manual'` and `'claude_p'`:

```bash
sqlite3 ~/.local/share/worklog/worklog.db \
  "UPDATE blocks SET estimated_by = NULL WHERE estimated_by = 'gap';"
worklog estimate --day "$DAY" --json
```

Confirm with the user before running. This is the one SQL path the skill is allowed to execute, because:
- The WHERE clause is narrow and verified — it can't hit a `manual` block.
- The estimator skips blocks where `estimated_by IS NOT NULL OR estimated_by = 'manual'`, so the next run picks up exactly the cleared rows.
- Same SQL appears in troubleshooting.md §4 for the post-`claude`-install recovery flow.

Never run any other SQL through the skill. Block edits go via the HTTP API; everything else goes via the CLI.

---

## Recipe 11 — "Show me unsynced blocks" [R]

**Phrasings:** "what blocks haven't been synced?" / "show me pending sync" / "what needs to go to Tempo?" / "any dirty blocks?"

```bash
curl -s "http://127.0.0.1:9323/days/$DAY" | jq '{
  unsynced_with_ticket: [.blocks[] | select((.tempo_worklog_id == null or .tempo_worklog_id == "") and .jira_issue != null and .is_personal == false)],
  dirty: [.blocks[] | select(.dirty == true)],
  needs_ticket: [.blocks[] | select((.tempo_worklog_id == null or .tempo_worklog_id == "") and .jira_issue == null and .is_personal == false)],
  personal_skipped: [.blocks[] | select(.is_personal == true)]
}'
```

**Format for the user:**

```
2026-05-12 sync status:
  Will POST to Tempo (unsynced + has ticket):
    09:00–10:30  90m  GOJ-1310  "OAuth fix"
    14:00–15:45  105m GOJ-1405  "Code review"

  Will PUT to Tempo (dirty — edited after sync):
    11:00–12:00  60m  GOJ-500   "Meeting"  [was 90m, edited to 60m]

  Skipped (no ticket — needs assignment):
    12:30–13:00  30m  (unassigned)

  Skipped (personal):
    16:00–16:30  30m

Run `worklog sync --day 2026-05-12 --dry-run` to preview, or sync (always confirms).
```

For a multi-day view, loop days and aggregate.

---

## Recipe 12 — Bonus: "Is worklog up to date?" / "Update worklog" [R then W-L]

**Phrasings:** "is worklog up to date?" / "update worklog" / "any new versions?"

**Step 1 — Check** (read-only, no confirm).

```bash
worklog self-update --check --json
```

Response: `{ current, latest, up_to_date, notes }`.

**Step 2 — If update available, confirm.**

> "worklog 0.7.0 available (current: 0.6.0). Notes: <changelog snippet>. Update now? Binary will be atomically replaced and the daemon restarted."

**Step 3 — Upgrade.**

```bash
worklog upgrade --json
```

Response: `{ from, to, used_delta, asset_bytes, dry_run, rolled_back, daemon_restart }`. If `rolled_back: true`, the smoke test failed and worklog reverted automatically.

**Step 4 — After upgrade, refresh the skill itself.** The bundled skill files don't auto-refresh on `worklog upgrade`. Run `worklog skill install` to refresh `${CLAUDE_PLUGIN_ROOT}/skills/worklog/`.

---

## Decision tree (full version of the routing in SKILL.md)

```
User phrasing
│
├─ "set up" / "install" / "first time" / "configure"
│   └─ Recipe 8
│
├─ "not working" / "no data" / "broken" / "empty" / "daemon down"
│   └─ Recipe 9 (then troubleshooting.md)
│
├─ "what did I work on" / "show me" / "summary"
│   ├─ + a ticket key
│   │   └─ Recipe 3
│   └─ Recipe 2
│
├─ "timesheet" / "fill out" / "daily" / "run the pipeline"
│   └─ Recipe 1 (SKILL.md Recipe A)
│
├─ "estimate" / "re-estimate"
│   └─ Recipe 10
│
├─ "unsynced" / "pending" / "dirty" / "what to sync"
│   └─ Recipe 11
│
├─ Block referenced by time/id/description
│   ├─ + "delete" / "remove"               → Recipe 6
│   ├─ + "minutes" / "duration" / "hours"  → Recipe 5
│   ├─ + ticket key / "wrong ticket"       → Recipe 4
│   └─ ambiguous → ask
│
├─ "personal" / "work" / "classify"
│   ├─ + path/project                      → Recipe 7
│   └─ vague → ask
│
├─ "up to date" / "update" / "upgrade"
│   └─ Recipe 12
│
└─ "fix yesterday" / "something's wrong with..."
    └─ ask: which day? which block? what's wrong? → Recipe 4/5/6
```

## Confirmation wording patterns

**Ticket assignment:**
> "Assign block 11:15–13:15 (120m, currently GOJ-999) → GOJ-1310?"

**Duration change:**
> "Block 14:00–15:30 (currently 90m, GOJ-1310) → 45m (ends at 14:45)? This marks it 'manual' — the estimator won't change it back."

**Delete (unsynced):**
> "Delete block 12:00–13:00 (60m, unassigned)? Local only."

**Delete (synced):**
> "Delete block 12:00–13:00 (60m, GOJ-500, Tempo tw-12345)? This also deletes the Tempo entry. Cannot be undone."

**Tempo sync (always confirms):**
> "Sync 6 blocks to Tempo for 2026-05-12? POST 4 new, PUT 2 dirty, 2 skipped (1 unassigned, 1 personal). [Dry-run output above.] Proceed?"

**Reclassify retroactively:**
> "Apply the new work/personal rules to all existing blocks? Blocks with assigned tickets won't change."

**Dirty nudge (always after a local write to a synced block):**
> "Note: this block was previously synced (tw-12345). Now marked dirty — run `worklog sync --day 2026-05-12` to push the update to Tempo."
