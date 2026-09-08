---
event: PostToolUse
tool: Edit
pattern: /vendor/
action: deny
enabled: true
created: 2026-09-08
source: "patched a vendored file"
hits: 0
---
Vendored code is upstream's; patch it in a fork instead.
Undo: flow lesson undo deny-post-edit
