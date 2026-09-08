---
event: PreToolUse
tool: Bash
pattern: git[[:space:]]+push[^;&|]*--force
action: deny
enabled: true
created: 2026-09-08
source: "force-pushed main"
hits: 0
---
Force-pushing overwrites remote history. Use --force-with-lease.
Undo: flow lesson undo no-force-push
