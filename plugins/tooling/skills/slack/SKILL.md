---
name: slack
description: Wait for Slack messages using the `slack-watch` poller — arm a Monitor that wakes Claude when a DM, mention, or channel message arrives, then respond. Use when the user wants Claude to sit and wait on Slack: "wait until someone messages me", "let me know when X replies", "watch Slack", "ping me on a new DM", "monitor #channel", "wake me when they respond". Do NOT use for a one-off "check my Slack now" — read Slack directly with the Slack MCP tools instead.
user-invocable: true
argument-hint: "[who or what to watch for]"
---

# Waiting on Slack with `slack-watch`

`slack-watch` (lives in `bin/.local/bin/`, on PATH after `stow bin`) polls the Slack
Web API and prints **one compact JSON line per new incoming message**. Every line is
a wake event, which makes it a drop-in event source for the `Monitor` tool.

Reach for this when the user wants Claude to **wait**. For a single "what's in my
Slack right now?", use the Slack MCP tools (`slack_read_channel`, `slack_search_*`) —
no polling, no monitor.

## 1. Check auth first, always

```bash
slack-watch --check-auth
```

Success prints `authenticated as <user> (<id>) on team <team>`. Anything else means
setup is incomplete — **say so and stop.** Never arm a monitor that cannot fire; a
broken watch is indistinguishable from a quiet one.

- **exit 2** — no token. Needs a Slack user token (`xoxp-`) in `SLACK_TOKEN` or
  `~/.config/slack-watch/config.json`. The error text lists the exact scopes to request.
- **exit 1** — token rejected (invalid, revoked, or missing a scope).

## 2. Pick the right wake shape

**Every message, indefinitely → `Monitor`** with an unbounded command:

```
Monitor({
  command: "slack-watch --dms --interval 30",
  description: "new Slack DMs",
  persistent: true,
})
```

**Wake once, then stop → `Bash` with `run_in_background`.** `--exit-after 1` makes the
process exit after the first match, which yields exactly one completion notification:

```bash
slack-watch --dms --from @jane --exit-after 1
```

Do **not** use `Monitor` for a one-shot wait — an unbounded poller stays armed long
after the event fired and burns the timeout for nothing.

## 3. Targeting

| Want | Flags |
|---|---|
| Any DM (the default) | `--dms` |
| From specific people | `--from @jane` (repeatable; `@name`, `name`, or `Uxxxx`) |
| A channel | `--channel #eng` (repeatable; `#name` or `Cxxxx`) |
| @-mentions of you | `--mentions` (heavier: polls every channel you belong to) |
| Bots and join/system messages | `--include-bots` (excluded by default) |

`--interval` defaults to 30s. Keep it at 30s or higher — Slack rate-limits.

## 4. The event that wakes you

One line of compact JSON per message:

```json
{"ts","channel","channel_name","channel_type","user","user_name","text","permalink"}
```

`text` is raw Slack markup, so mentions arrive as `<@U123>`. `permalink` jumps
straight to the message. That is usually enough to answer without re-reading Slack;
pull `slack_read_thread` when you need surrounding context.

To reply, use `slack_send_message` — but **draft it for the user and confirm before
sending** unless they have clearly authorised you to send on their behalf. Waking up
and posting to a human's Slack unprompted is not a recoverable mistake.

## 5. Behaviour worth knowing

- **No backlog flood.** The first poll per channel records a baseline and emits
  nothing. Only messages arriving *after* the watch begins wake you.
- **First-ever DMs still fire.** The watch list is rebuilt each poll, so a DM from
  someone with no prior thread is caught (its channel only exists once sent).
- **stdout carries only events.** All diagnostics go to stderr, which Monitor does not
  surface. Silence means "no messages" — it is not proof the watch is healthy. That is
  why step 1 is non-negotiable.
- **Survives blips.** Network errors and rate limits warn and keep polling. Only broken
  auth is fatal (exit 1), which ends the monitor and reports the exit code.
- **State** is per-channel cursors in `~/.config/slack-watch/state.json`. Use
  `--reset-state` to re-baseline, and `--state-file` to give concurrent watches their
  own cursors so they don't consume each other's messages.
- `--once` does a single poll (cron, `until` loops); `--self-test` runs offline
  assertions needing no token or network.
