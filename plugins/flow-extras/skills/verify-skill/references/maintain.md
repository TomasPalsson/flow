---
name: maintain
description: The maintain-mode pass for a project's verify skill.
---

# Maintain pass

1. **Locate the target.** One `.claude/skills/verify-*/`. Several: ask which. None: switch to create mode.
2. **Diff the map against the code.** Re-run the command the skill names for its route or command list and compare. Read `git log --since=<Last verified date> --name-only` for user-facing churn. A route counts as missing only with a concrete source path.
3. **Check renames across the repo.** For each renamed path, search for redirects, nav links, tests, docs and other skills that still use the old one.
4. **Live pass.** Required even when the source looks clean. Run doctor, then drive every feature once. Evidence survives every cleanup, checked at its path. A feature you cannot reach is `verified-unreachable` only with the concrete prerequisite and the route you tried; if the skill omits that prerequisite, that is drift.
5. **Triage.** Wrong user-facing description: fix the map. Working behaviour the harness cannot drive: fix the harness and re-drive it. Broken app behaviour: report it, keep it out of the PR.
6. **Update the signals.** Set `Last verified`, keep frontmatter and structure, update the description for new pages.
7. **Ship or stop.** Changed: one PR of corrections, re-read each changed file first. Clean or blocked: no PR. The report lists what changed, what was driven live, what could not be verified, and remaining uncertainty.

## Drift and failure cases

- **Stale seed data**: an empty-state check passes or fails falsely because state was never reset; confirm Reset really empties it.
- **Auth expiry mid-run**: stored state dies partway, later features land on the login page and a redirect looks like a pass. Re-run doctor between features.
- **Port owned by another process**: you drive someone else's server or an old build. Doctor must check the PID and build, not just that the port answers.
- **Renamed route with a redirect**: the old URL still returns 200 and hides the rename; compare the final URL.
- **New required env var**: boot succeeds, the feature fails later; diff `.env.example` and config loaders against Launch.
- **Evidence deleted by cleanup**: the skill claims a file that is gone; check the path, not the claim.

Load this file only in maintain mode; create mode never needs it.

Credit: adapted from cursor/plugins pstack maintain-verification-skill (MIT).
