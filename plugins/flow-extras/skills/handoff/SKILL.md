---
name: handoff
description: "Write a redacted handoff summary of the current conversation and, on the user's yes, start a fresh background agent seeded with it. Use when the user asks to hand off, continue in a new session, or pass this work to a background agent. Not for flow runs (flow keeps its own state in the spec and PROGRESS.md; use /flow:next to resume), not for saving a lesson (use /flow:lesson)."
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

# Handoff

A fresh agent continues the work from one file. The file becomes its whole prompt, so it holds pointers and decisions, never copied content, and never a secret.

## 1. Draft the summary

Cover, in this order: goal, current state, artifact paths, open decisions, and `Suggested skills:` naming the skills the next agent should call through the Skill tool. If the user passed an argument, treat it as the focus of the next session and tailor the summary to it.

Point to specs, plans, ADRs, issues, commits and diffs by path or URL. Copying them duplicates what the next agent can read itself and goes stale.

## 2. Write it through the script

Pipe the draft to `scripts/handoff.sh` beside this SKILL.md. It masks API keys, tokens, passwords, private keys and email addresses, because the file becomes a prompt and sits in a temp dir. It writes `${TMPDIR:-/tmp}/handoff-<slug>.md` (`$TMPDIR` is often unset on Linux) and prints the path:

```bash
bash <this skill dir>/scripts/handoff.sh write <slug> <<'EOF'
...summary...
EOF
```

Read the written file once and remove anything the patterns missed: unusual secret shapes (keys, tokens, connection strings), customer names, internal hostnames. The script handles the common shapes only, so do not quote secrets in the draft at all.

## 3. Offer the launch

Print the exact line with `scripts/handoff.sh command "<name>" <file>` and ask. The name is short and descriptive (for example `Fix login bug`) and holds no quotes, `$`, backticks or backslashes (the script refuses them); it shows in the job list and terminal title.

Only on a yes, run `scripts/handoff.sh launch "<name>" <file>`. It runs `claude --bg -n "<name>" -- "$(cat <file>)"` in the current directory and returns at once; the user manages the job with `claude agents`. The file is passed inside double quotes, so the shell does not expand `$` or run backticks in the summary. On a no, leave the file in place and stop.

Skip quietly when `claude` is not on PATH (`launch` also exits 0 with a note): report the file path and stop.

Tests: `bash scripts/test_handoff.sh`.

Credit: adapted from mattpocock/skills skills/in-progress/claude-handoff/SKILL.md @ 49dd158 (MIT).
