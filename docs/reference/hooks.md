# Hooks

Lifecycle hooks in `plugins/harness/hooks/`, registered by the plugin's `hooks/hooks.json` (`${CLAUDE_PLUGIN_ROOT}` paths). Every hook sources `lib/hookout.sh`, runs with `set -u`, degrades to exit 0 when a tool is missing, and is bash 3.2 / BSD-coreutils safe.

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

## post-bash-write.sh

```
post-bash-write.sh — PostToolUse/Bash hook (C19).
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

## spec-gate.sh

```
spec-gate.sh — PreToolUse/Edit|Write|NotebookEdit hook. SPEC C20.
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

## tool-stamp.sh

```
tool-stamp.sh — PreToolUse/Bash hook. Runs first, before rtk-rewrite.sh and
```

## turn-stamp.sh

```
turn-stamp.sh — UserPromptSubmit hook.
```

## worklog-hook.sh

```
worklog-hook.sh — forwards PreToolUse, PostToolUse, SessionStart,
```

## hooks.json

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/session-context.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/codebase-map.sh",
            "timeout": 20
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/worklog-hook.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/turn-stamp.sh",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/worklog-hook.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/tool-stamp.sh",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/rtk-rewrite.sh",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/git-guard.sh",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/spec-gate.sh",
            "timeout": 15
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/worklog-hook.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/format-lint.sh",
            "timeout": 60
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/size-guard.sh",
            "timeout": 20
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/tamper-notice.sh",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/post-bash-write.sh",
            "timeout": 90
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/worklog-hook.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/stop-gate.sh",
            "timeout": 600
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/worklog-hook.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/subagent-log.sh",
            "timeout": 10,
            "async": true
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/worklog-hook.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/pre-compact-backup.sh",
            "timeout": 20
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/postcompact-context.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/notify.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/worklog-hook.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```
