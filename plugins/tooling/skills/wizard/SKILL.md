---
name: wizard
description: Generate an interactive bash wizard that walks a human through steps only they can perform. Use when provisioning infrastructure, setting up credentials or CI secrets, walking an unfamiliar third-party dashboard, or running a one-off migration or cutover. Not for steps the agent can do itself.
---

# Wizard

A wizard is a bash script that walks a human, step by step, through a manual procedure that is tedious to do by hand and tedious to re-explain to an AI every time. It opens each URL, says what to click and copy, captures the values, writes them where they belong (`.env`, GitHub secrets), confirms at every stage, and shows how many stages are left.

[template.sh](template.sh) already provides the interface: stage-by-stage progress, confirmation gates, cross-platform URL opening (including WSL), hidden secret entry, idempotent `.env` upserts, `gh secret` and `gh variable` writes, and a closing summary. Your job is only to scope the procedure and author its stages. The library above the `STAGES` marker is identical in every wizard. Never hand-edit it.

A wizard is ephemeral by default: write it to a scratch path, and delete it when the job is done. Commit it only when the user wants a repeatable setup path that lives in the repo.

## Process

### 1. Scope the procedure

Work out every manual step the human must take and every value captured along the way. Read the repo first, do not ask cold:

- For setup: `.env`, `.env.example`, `.env.*`, `README`, `docker-compose*`, framework config, and `.github/workflows/*` (every `secrets.*` and `vars.*` reference is a value the wizard must produce).
- For a migration or cutover: the current state, the target state, and the irreversible actions between them.

Show the user the ordered list of stages and the values each produces, and confirm. They may add, drop, or reorder.

**Done when:** every stage is named in order, and for each captured value you know (a) where the human gets it, (b) where it is written (`.env`, a GitHub secret, both, or nowhere, since some stages are pure actions), and (c) whether it is secret (hidden entry) or public.

### 2. Map each stage's journey

For each stage, write the precise path a human follows: which URL to open, what to do there, where a value is shown, and which variable it fills. For example: "Dashboard, Developers, API keys, Reveal test key, copy". Where you do not know the current UI or the exact command, say so and ask the user or check the docs. Never invent steps that may not exist.

**Done when:** every stage traces to concrete instructions a stranger could follow.

### 3. Author from template.sh

Copy `template.sh` to the target path. Replace the example stage with one `stage` per step, in dependency order. Use the library helpers: `stage`, `say`/`step`, `open_url`, `ask`/`ask_secret`, `write_env`, `set_secret`/`set_var`, `pause`/`confirm`. Set `TOTAL_STAGES` to the number of stages you wrote.

Keep every authored stage inside `run_wizard` and leave the last line as `run_wizard "$@"; exit`: bash then parses the whole file before the first prompt, so an edit made while the wizard runs cannot break it.

Hold the bar the template sets: open the URL before asking for its value, use `ask_secret` for anything secret, `write_env` every persisted value, `set_secret` only the values CI actually needs, and `confirm` before any irreversible action. Each `stage` clears the screen so only the current step is visible. Keep a stage to one focused task so nothing the human needs scrolls away.

**Done when:** the script has one stage per step from steps 1 and 2, `TOTAL_STAGES` matches, and the library above the marker is unchanged.

### 4. Verify statically and hand off

- Run `bash -n <script>`, and `shellcheck` if available.
- Run `chmod +x <script>`.
- When you change `template.sh` itself, run [scripts/test_template.sh](scripts/test_template.sh).
- Do not run it end to end yourself: it opens browsers and blocks on human input. Trace it statically instead. Every value from step 1 is captured and lands where step 1 said, and every `set_secret` name exactly matches a `secrets.*` reference in CI.
- Tell the user how to run it. If it is a repeatable setup path, commit it and link it from the README so the next person runs the script instead of asking an AI.

**Done when:** `bash -n` passes, the trace finds no missing or misplaced value, and the user has the run command.

Adapted from mattpocock/skills wizard @ f3fc563 (MIT).
