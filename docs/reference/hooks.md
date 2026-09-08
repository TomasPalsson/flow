# Hooks

Lifecycle hooks in `plugins/flow/hooks/`, registered by the plugin's `hooks/hooks.json` (`${CLAUDE_PLUGIN_ROOT}` paths). Every hook except `worklog-hook.sh` sources `lib/hookout.sh` — which itself sources `lib/hookpath.sh`, the path/ignore half of the same API, so one `. lib/hookout.sh` still yields the whole surface. Two hooks source one more file of their own, split off purely to stay under the 400-line size limit: `spec-gate.sh` sources `lib/specgate.sh` and `post-bash-write.sh` sources `lib/bashwrite.sh`. (worklog-hook deliberately does not source it, so the raw stdin payload reaches `worklog hook-run`.) Each hook runs with `set -u`, degrades to exit 0 when a tool is missing, and is bash 3.2 / BSD-coreutils safe.

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

### Turning the hooks off for a directory

`flow off [dir]` writes `<dir>/.claude/flow.off` (and excludes it via `.git/info/exclude`, never a tracked file); `flow on` removes it (and `.claude/flow.unsafe`, see below). Every judging hook — format-lint, size-guard, tamper-notice, post-bash-write, spec-gate, stop-gate, codebase-map — calls `hook_skip_if_off` right after sourcing `lib/hookout.sh` and exits 0 when the marker sits in the project directory or any ancestor. Bookkeeping hooks (turn and tool stamps, subagent log, compaction backup, notify, worklog) keep running. The session-start hook prints "hooks are OFF in this directory" as its first line so the state is never invisible.

`git-guard.sh` is deliberately NOT silenced by `.claude/flow.off`: it honours a separate marker, `.claude/flow.unsafe`, written only by `flow off --unsafe` (and removed by `flow on`). `CC_NO_GIT_GUARD=1` disables git-guard for one session; every git-guard deny names both escape hatches.

### Git is the enforcement boundary

`hook_git_managed <file>` in `lib/hookout.sh`: true when the file sits inside a git work tree and is not git-ignored. `format-lint`, `size-guard`, `spec-gate` and `tamper-notice` (except for gate-config files, which are always in scope) skip anything else, so scratch scripts, files under `/tmp`, and ignored build output are never formatted, measured or gated. The ignore exemption is turn-scoped: it is voided only when the ignore file (`.gitignore`, `.git/info/exclude`) is newer than the turn stamp, and then only for files under that ignore file's directory (adding a path to `.gitignore` in the same turn as editing it does not dodge the hooks; an ignore rule already in place before the turn started still exempts). `CC_HOOKS_ALL_FILES=1` enforces everywhere for a session.

## loop-gate.sh

```
loop-gate.sh — Stop hook. See spec 006 K-K.
```

Fast path: exits 0 immediately when `.claude/loop/loop.md` does not exist, so
a project with no active `flow loop` contract never spawns node on Stop. When
a contract exists, it runs `flow loop tick --hook --session <id>` and prints
that command's stdout verbatim — the only thing it consumes or emits; all
loop state-machine logic (block/allow, iteration caps, shape) lives in
`flow loop tick`, never in the hook. Registered after `stop-gate.sh`.

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
tool-stamp.sh — PreToolUse/Bash hook. Runs first, before git-guard.sh (C5).
```

## turn-stamp.sh

```
turn-stamp.sh — UserPromptSubmit hook.
```

## worklog-hook.sh

```
worklog-hook.sh — forwards SessionStart and SessionEnd events to
```

Registered exactly twice (SessionStart, SessionEnd). Never propagates `worklog`'s stdout or exit code — a failing or missing `worklog` binary is always a silent, rc-0 no-op for the turn.

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
            "timeout": 90,
            "statusMessage": "flow: checking bash-written files…"
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
            "timeout": 600,
            "statusMessage": "flow: running gates…"
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
