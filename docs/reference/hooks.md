# Hooks

Lifecycle hooks in `~/.claude/hooks/` (stowed from `~/.dotfiles/claude/.claude/hooks/`). Every hook sources `lib/hookout.sh`, runs with `set -u`, degrades to exit 0 when a tool is missing, and is bash 3.2 / BSD-coreutils safe.

## codebase-map.sh

```
codebase-map.sh — SessionStart hook (also fires on compact, per the
```

## format-lint.sh

```
format-lint.sh — PostToolUse/Edit|Write|NotebookEdit hook.
```

## git-guard.sh

```
git-guard.sh — PreToolUse/Bash hook.
```

## notify.sh

```
notify.sh — Notification hook (matcher: permission_prompt|idle_prompt).
```

## postcompact-context.sh

```
postcompact-context.sh — PostCompact hook.
```

## pre-compact-backup.sh

```
pre-compact-backup.sh — PreCompact hook.
```

## rtk-fast.sh

```
rtk-fast: optimized wrapper for rtk-rewrite.sh (same protocol, fewer forks). Not managed by rtk.
```

## rtk-rewrite.sh

```
rtk-hook-version: 3
```

## session-context.sh

```
session-context.sh — SessionStart hook.
```

## size-guard.sh

```
size-guard.sh — PostToolUse/Edit|Write|NotebookEdit hook.
```

## stop-gate.sh

```
stop-gate.sh — Stop hook. Exact behavior: SPEC C10.
```

## subagent-log.sh

```
subagent-log.sh — SubagentStop hook (async: true).
```

## tamper-notice.sh

```
tamper-notice.sh — PostToolUse/Edit|Write|NotebookEdit hook.
```

## turn-stamp.sh

```
turn-stamp.sh — UserPromptSubmit hook.
```

## worklog-hook.sh

```
worklog-hook.sh — forwards PreToolUse, PostToolUse, SessionStart,
```

