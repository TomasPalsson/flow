# Spec: Cross-worktree spec numbers + zellij pane name

> **One-sentence summary**: `new-spec` allocates a spec number no other worktree or branch already holds, and names the zellij pane after it.

**Status**: Approved · **Size**: Small · **Author**: Mr Claude (flow run) · **Created**: 2026-09-05 · **Version**: 1.0

## TL;DR

**Problem**: `new-spec` computes `NNN` from the current checkout's `.specs/` only. Every agent started from `main` sees no specs and gets `001`; three worktrees hold a `001-*` today. A user running several agents in zellij panes has no pane label telling which flow is where.

**Solution**: `next_number` takes the max over the current dir, every git worktree's `<dir>/`, and every local/remote ref's committed `<dir>/` tree. After allocation, when running inside zellij, the pane is renamed to `NNN-slug`.

**Who it's for**: the developer running two or more `/flow` sessions in parallel in zellij panes.

**Non-goals (v1)**:
- Not fixing `.claude/flow.json` being written into the main checkout under `--worktree` (parallel agents still overwrite it) — follow-up.
- Not renaming the zellij tab, and not renaming on session resume (only at allocation).
- Not adding a lock or counter file; two agents allocating within the same few milliseconds can still collide.
- Not changing the `agents` fish function.

**Key decision**: scan rather than count — worktree filesystems for uncommitted specs, refs for committed ones — so nothing new has to be kept in sync.

## 1. Context

**Current workaround**: the user renumbers by hand after the collision, or starts each flow only after the previous one committed and merged.

| Role | Description | Volume | Key characteristic |
|------|-------------|--------|--------------------|
| Parallel flow user | Starts `/flow` in several zellij panes of one repo | 1 person, 2–4 sessions | Each session runs `new-spec --worktree` from `main` |

**Hidden stakeholders**: `flow next` and the `agents` alias read `.claude/flow.json`; its shape must not change.

## 2. Scope

**In**: `plugins/flow/scripts/new-spec` (`next_number`, post-allocation pane rename), its tests in `scripts/tests/test_flow.sh`, the usage text.
**Out**: everything under Non-goals; hooks; the `flow` CLI.

| System | Relationship | Constraint |
|--------|-------------|------------|
| git worktrees / refs | Reads from | Read-only; `git worktree list --porcelain`, `git for-each-ref`, `git ls-tree` |
| zellij CLI | Writes to | `zellij action rename-pane <name>`; failure must not change exit code or stdout |
| `.claude/flow.json` consumers | Reads from | JSON keys and stdout unchanged |

## 3. User Journeys

### Journey 1 — Two agents allocate from `main` (P1)
**Happy path**: agent A runs `new-spec --worktree` → `001` in worktree A (uncommitted). Agent B runs it from `main` → scans worktree A → gets `002`.
**Error path — worktree removed, branch kept with committed `.specs/003-x`**: agent C scans refs → gets `004`.
**Edge cases**: a ref with no `<dir>/` prints nothing and is skipped; `--no-branch` outside a git repo scans the current dir only; a non-`NNN-*` entry is ignored as today.

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-001 | worktree holds uncommitted `.specs/001-a`, main has no `.specs` | `new-spec` runs from main | number is `002` | MUST |
| AC-002 | branch `b` has committed `.specs/003-b`, no worktree for it | `new-spec` runs on main | number is `004` | MUST |
| AC-003 | not a git repo | `new-spec --no-branch` runs | rc 0, number from local dir | MUST |

### Journey 2 — Pane rename (P1)
**Happy path**: inside zellij, allocation succeeds → pane title becomes `002-cross-worktree-spec-numbers-zellij-pane`.
**Error path — `zellij` missing or the rename fails**: nothing printed to stdout, rc unchanged.

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| AC-004 | `ZELLIJ_PANE_ID` set, stub `zellij` on PATH | `new-spec` runs | stub received `action rename-pane NNN-slug`; stdout JSON unchanged | MUST |
| AC-005 | `ZELLIJ_PANE_ID` set, `zellij` exits 1 | `new-spec` runs | rc 0, JSON printed | MUST |
| AC-006 | `ZELLIJ_PANE_ID` unset | `new-spec` runs | stub never invoked | MUST |

## 4. Functional Requirements

| ID | Actor | Requirement | Priority | AC |
|----|-------|-------------|----------|----|
| FR-001 | System | MUST compute `NNN` as 1 + max over current `<dir>`, every worktree's `<dir>`, every `refs/heads` and `refs/remotes` ref's committed `<dir>/` | MUST | AC-001, AC-002 |
| FR-002 | System | MUST fall back to the current dir when git is unavailable | MUST | AC-003 |
| FR-003 | System | MUST run `zellij action rename-pane <NNN-slug>` when `ZELLIJ_PANE_ID` is non-empty, after the spec dir is created | MUST | AC-004 |
| FR-004 | System | MUST keep rc and stdout independent of the rename's outcome | MUST | AC-005, AC-006 |

## 5. Non-Functional Requirements

**Performance**: allocation under 1 s wall clock with 50 refs and 5 worktrees, measured with `time` on this repo.
**Security**: no new inputs beyond ref names and paths git itself produced; names are never `eval`ed. `--dir` is passed to `git ls-tree` after `--`.
**Reliability**: scanning failures (missing worktree path, deleted ref) degrade to "not counted"; the script never fails because of the scan.
**Error handling**: `zellij` absent → silent skip; `git` absent → local-dir scan; bash 3.2 portability rules of `tests/run.sh` hold (no `mapfile`, `realpath`, `readlink -f`).

## 6. Success Criteria
- [ ] AC-001..006 pass in `scripts/tests/test_flow.sh`; full `tests/run.sh` green including shellcheck.
- [ ] Run from this repo's `main`, `new-spec --no-branch "probe"` prints `003` (two `001` worktrees plus this run's `002`).
**Failure looks like**: numbers are unique but the user still cannot tell panes apart because the pane title is truncated to the number-less tail; validate by eye in a real pane.

## 7. Constraints & Assumptions

| ID | Assumption | Confidence | How to validate |
|----|-----------|------------|-----------------|
| A-001 | `zellij action rename-pane` targets the invoking pane via `ZELLIJ_PANE_ID` from inside a Claude Code Bash tool call | High | run it in step 5 and look at the pane |
| A-002 | Same-millisecond allocation by two agents is rare enough to leave unlocked | Medium | revisit if a collision recurs after this ships |

**Dependencies**: git ≥ 2.x (`worktree list --porcelain`), zellij 0.45 (present).

## 8. Open Questions
None.

## Appendix A — Glossary
| Term | Definition |
|------|------------|
| worktree | a checkout registered by `git worktree add`, sharing the repo's `.git` |
| ref | a local branch (`refs/heads/*`) or remote-tracking branch (`refs/remotes/*`) |
