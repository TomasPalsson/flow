---
name: verify-skill
description: Generates or maintains a project-local verify-NAME skill, stored under the project's own skills directory, that launches the real app, drives each user feature, and captures evidence, for web, CLI and API projects. Use when asked to "prove it works", "make a verify skill" or "how do we test this end to end", when a project has no repeatable way to prove behaviour, when agents skip verifying UI or CLI changes, or when an existing verify skill has drifted from the app (renamed routes, changed login, new env vars). Not for verifying one change right now (use flow's shared verification.md) or for writing Playwright test suites (use flow's shared e2e-testing.md).
---

# Verify-skill

A verify skill is a runbook the next agent reads cold, mid-task, having never seen the app. Its value is that every step was run once by you and the evidence is on disk. Two modes; declare which before starting.

- **create**: no `.claude/skills/verify-*/` exists, or the user asks for a new one.
- **maintain**: one exists and the app has changed since it was written.

## Create

1. **Look for an existing mechanism first.** Search for `.claude/skills/verify-*`, Playwright/Cypress config, Makefile or package scripts named `verify`/`e2e`/`smoke`, CI jobs, and `.claude/scripts/start-dev-server.sh`. Reuse what exists; a second mechanism that disagrees with the first is worse than none. If one exists and is current, stop and say so.
2. **Interview the repo, not the user.** Answer from the code: surface (web, CLI, API; pick a primary), start command, port, env vars, DB and seed data, auth provider, how to reset state. Ask only what the code cannot tell you (a test-account secret, a 2FA bypass). Never write a secret into the skill; name the env var or file that holds it.
3. **Get the base running.** Start the app yourself. If it will not start, report exactly why and stop: a skill written against a broken base teaches wrong steps.
4. **Build the feature map from the app, not from memory.** Enumerate routes or commands from the router, `--help`, or the OpenAPI file, and pick the top 3 to 5 user features. Rank: auth and any money path first, then the paths that change most in the commit history, then what the README leads with. Read [`references/skill-template.md`](references/skill-template.md) before writing; it holds the generated skill's shape and the per-feature fields (reach it, reset, states to check, evidence).
5. **Write the generated skill** to `.claude/skills/verify-<project>/SKILL.md` from that template. Describe each feature from what you saw on screen or in output, never from what a page probably contains; an invented expectation fails the first honest run.
6. **Run it once.** Follow your own generated skill on one feature: launch, doctor, drive, capture evidence, clean up. Done means the evidence file exists at the path the skill names, after cleanup. A skill that was never run is a draft; say "draft, not run" if you cannot run it, with the reason.
7. **Check the artifact mechanically.** Grep the generated file for leftover placeholders (`<word>` angle brackets, `TODO`, `TBD`); none may remain. Every path and env var it names must exist (`ls`, grep the code). Frontmatter must carry `name` and `description`.
8. **Report**: files written, the feature you ran with the evidence path, features not yet run, and what could not be verified (auth, payments, external services).

Create-mode traps, each with its mechanism:
- **Auth lockout**: repeated failed logins from retries lock the test account, and every later run fails for a reason that looks like a regression. Run the doctor's auth check once, and stop after one failure instead of retrying.
- **Seed data passes the happy path falsely**: a seeded row makes "list shows items" pass even if create is broken. Reset to empty first, then create through the UI or command and check the new row.
- **claude-in-chrome unavailable** (extension not connected, headless box): fall back to agent-browser and name the tool actually used in the skill; if neither runs, write the skill as "draft, not run".
- **Multi-app repo**: one verify skill per deployable app (or one per surface), each with its own Launch; do not merge two start commands into one skill.

No web, CLI or API surface (library, worker, mobile, desktop)? Drive the nearest real entry point: an example script, a queue message in and the row or file out, or the simulator. If none can be driven, say "could not verify" with the reason instead of inventing a map.

Tool choice for the web surface: claude-in-chrome or agent-browser per flow's shared references; selector rules are in flow's `shared/e2e-testing.md`.

## Maintain

Read [`references/maintain.md`](references/maintain.md) before starting; it holds the pass. Outcome is one of `clean` (nothing to fix, no PR), `changed` (at most one PR of corrections you proved), or `blocked` (say what blocked it). Edit only the verify skill's own directory; a behaviour the map describes that the app no longer has is either doc drift (fix the map) or a product regression (report it).

## Why a skill and not a line in CLAUDE.md

A "please verify" line is advisory and agents skip it silently. The generated skill makes the done-state concrete: a named evidence file, and a rule that "could not verify" is reported, not omitted. Enforcement beyond that (a hook or CI gate) is the user's call; offer it, do not add it.

Credit: adapted from cursor/plugins pstack create-verification-skill and maintain-verification-skill (MIT).
