# Hooks

Lifecycle hooks in `plugins/flow/hooks/`, registered by the plugin's `hooks/hooks.json` (`${CLAUDE_PLUGIN_ROOT}` paths). Every hook except `worklog-hook.sh` sources `lib/hookout.sh` — which itself sources `lib/hookpath.sh`, the path/ignore half of the same API, so one `. lib/hookout.sh` still yields the whole surface. Two hooks source one more file of their own, split off purely to stay under the 400-line size limit: `spec-gate.sh` sources `lib/specgate.sh` and `post-bash-write.sh` sources `lib/bashwrite.sh`. (worklog-hook deliberately does not source it, so the raw stdin payload reaches `worklog hook-run`.) Each hook runs with `set -u`, degrades to exit 0 when a tool is missing, and is bash 3.2 / BSD-coreutils safe.

## codebase-map.sh

```
codebase-map.sh — SessionStart hook (also fires on compact, per the
```

## context-pressure.sh

```
context-pressure.sh — PreToolUse hook.
```

Registered on both the `Bash` and `Edit|Write|NotebookEdit` matcher groups. Warns once per 60k-token bucket that the context window is filling — read from the session transcript's last usage-bearing record — so the model finishes the current step and records where it left off (in TASKS.md / PROGRESS.md) before `/compact` or `/clear` loses the thread. Never blocks and never writes anything else to stdout.

Escape hatch: `flow off` for the directory (via `hook_skip_if_off`).

## finish-gate.sh

```
finish-gate.sh — Stop hook for /flow:next --finish.
```

Fast path: exits 0 with no output when no `.specs/*/FINISH.md` exists, so a
repo that never armed finish mode never spawns node on Stop. When one exists,
it runs `flow finish check --hook --session <id>` and prints that command's
stdout verbatim: a block while the armed spec sits in a work state (drafting
through shippable), silence on a hard stop, auto-disarm once the spec is done,
and a release after 3 identical blocks with no progress. Registered after
`loop-gate.sh`.

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

## infra-guard.sh

```
infra-guard.sh — PreToolUse/Bash hook. Asks the user (permissionDecision
"ask") before a command that destroys infrastructure or data, or that hides
what it runs. It never refuses and prints nothing for any other command.
```

Asks (never denies) before `terraform destroy`, `terraform apply -destroy`, `sst remove`, `aws s3 rm --recursive`, `aws s3 rb --force`, `DROP TABLE` / `DROP DATABASE`, a `${IFS}` in the command, and `base64 -d` piped to a shell. Each ask names the command and says why, so the user can approve it in the permission prompt. It matches the raw command string rather than git-guard's per-part view, because git-guard splits on `|` and `base64 -d | sh` never reaches one part there. Like git-guard it is a regex over a string: it raises the bar against a slip and is not a security boundary.

Escape hatches match git-guard: `CC_NO_GIT_GUARD=1` for one session, or `.claude/flow.unsafe` here or in any ancestor (`flow off --unsafe`). It is not silenced by `.claude/flow.off`.

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

## search-first.sh

```
search-first.sh — UserPromptSubmit hook.
```

A prompt that asks to add/implement/create/introduce a new symbol (a property, field, method, function, helper, endpoint, route, class or attribute) gets one line of model-facing context: search the repo before writing new code. Slash commands are left alone.

Escape hatch: `CC_SEARCH_FIRST=0` for one command (any other value forces it on, env always wins), else `searchFirst: false` in `.claude/flow.config.json`, else on by default.

## security-patterns.sh

```
security-patterns.sh — PostToolUse/Edit|Write|NotebookEdit hook.
```

Reports a security sink in the lines an edit ADDED (`innerHTML`, `eval`, pickle loads, `shell=True`, disabled TLS verification, and similar): one line per hit, `<file>:<line> <rule>: <one-sentence fix>`, on stderr with exit 2 so the model reads it. Each rule and file is reported once per session. Added lines are the new text of the payload (`content`, `new_string`, `edits[]`, `new_source`) minus any line already in the old text (`old_string`, or HEAD's version of the file for a Write), so context the edit left alone is never reported. The rule table is gated by file extension, so docs and prose that mention a sink do not trip it. It is a reminder, never a block, and prints nothing when nothing matches.

Escape hatch: `flow off` in the directory, or `CC_NO_SECURITY_PATTERNS=1`. Needs `python3`; without it the hook cannot judge and stays silent.

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

A hook script, a skill/agent doc, or a hooks/mcp config (`*/hooks/*.sh`, `*/skills/*/SKILL.md`, `*/agents/*.md`, `hooks.json`, `.mcp.json`) also gets a hidden-unicode scan: the lines this edit *added* are checked for zero-width space/joiner (U+200B–U+200D), bidi-control (U+200E/U+200F, U+202A–U+202E, U+2066–U+2069), word-joiner/invisible-operator (U+2060–U+2064) and BOM (U+FEFF) code points — any of which can hide text from a human reviewer. A hit reports the offending line and its code point (escape: state why it must stay, or `flow off` in the directory).

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
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/search-first.sh",
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
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/infra-guard.sh",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/context-pressure.sh",
            "timeout": 5
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
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/context-pressure.sh",
            "timeout": 5
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
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/security-patterns.sh",
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
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/loop-gate.sh",
            "timeout": 660,
            "statusMessage": "flow: loop tick…"
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/finish-gate.sh",
            "timeout": 30,
            "statusMessage": "flow: finish check…"
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
