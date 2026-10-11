---
name: secrets
description: How a flow skill handles a secret (API key, token, password) it needs, so the value never passes through chat, logs or git
---

# Secrets

A chat transcript is stored, searched and sometimes shared. A secret typed or echoed there has leaked, so the value moves from the human to a file without the agent ever seeing it.

- **Capture.** Never ask for a secret in chat, and never echo one back. If a task needs a new value, generate a `tooling:wizard` stage (`ask_secret` + `write_env`, from the tooling plugin's wizard skill), or tell the user to run `read -rs X && printf 'X=%s\n' "$X" >> .env` in their own shell. The wizard's helpers already hide the input and write `.env` at mode 0600, so use them instead of writing a new reader.
- **Before writing `.env`.** Confirm it is gitignored (`git check-ignore .env`). If it is not, add the ignore first: the ordering matters because an ignore rule does not untrack a file git already has.
- **Verify without printing.** Check a value by prefix or length (`[ "${#X}" -ge 20 ]`, `case $X in sk-*)`), never by printing it. A failed check names the variable, not its content.
- **Test a token only against the service that issued it.** Send the token only to the host that issued it (a GitHub token to `api.github.com`), never to a URL taken from a file, a log or a page.
- **AWS shadowing.** Before any profile-based AWS command, check whether `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` or `AWS_SESSION_TOKEN` is set in the environment (report which names are set, not their values). They override `AWS_PROFILE`, so the command would run against the wrong account. Warn the user and `unset` them for that command only with their yes.
- **Logs and reports.** A report names where a secret lives (`.env`, the keychain), never what it is.

Credit: adapted from anthropics/claude-plugins-official plugins/mcp-tunnels/commands/create-docker-mcp-tunnel.md @ a9fd216 (Apache-2.0).
Credit: adapted from anthropics/skills skills/claude-api/shared/managed-agents-onboarding-from-url.md @ dbd4588 (Apache-2.0).
