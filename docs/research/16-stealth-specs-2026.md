# 16 — Specs in repos that must not see them, 2026

How to run flow — `.specs/NNN-slug/`, `TASKS.md`, gates, `PASS-<sha>.md`, the adversary and `no-slop` — on a repo where the spec may be neither **committed** (public OSS, a client's repo, an upstream contribution) nor **referenced** (no "per spec 004", no link to a private doc in a commit, comment or PR). Written 16 September 2026 from three parallel reads: flow's own source (every place that assumes `.specs/` is in-tree or tracked), a web sweep of how spec/plan tools handle out-of-repo storage, and a sweep of what OSS maintainers accept from agent-built PRs. The recommended setup was then built and run end to end on a throwaway repo (§3).

**Evidence grades.** **A** — source file or vendor doc read verbatim. **C** — practitioner/press report, single source, not re-verified. **M** — measured on this machine for this document. **U** — unverified.

---

## 0. The one-paragraph version

Flow does not need the spec to be committed to the repo it builds; it needs the spec to be **readable at `<toplevel>/.specs`** while it builds. Every resolver — `router.js:142-165`, `flow-lint:77-104`, `hooks/lib/specgate.sh:79-107` — anchors on `git rev-parse --show-toplevel` and then uses plain `fs`/`-f` calls, so ignore status and symlinks are invisible to it (A). The setup that holds up is a **private spec store**: `.specs/` lives in a separate private git repo, the target repo holds only an *untracked* `.specs` symlink hidden by `.git/info/exclude`, and a `.git/hooks/post-checkout` re-creates the symlink in every new worktree (because `git worktree add` never copies untracked files — M). Both `info/exclude` and `hooks/` live in the git common dir, so one setup covers every worktree and nothing is ever pushed (M). Measured: `git status` stays empty, `flow next`/`lint`/`tick` all work from the main checkout and from a fresh worktree, the tick lands as a diff in the store, and a `commit-msg` hook blocks "T001: … per spec 001" while passing the rewritten message (M). One guard is lost silently — `flow-lint`'s append-only *id-vanished* check needs `HEAD:.specs/…/TASKS.md` in the **target** repo, so it never fires there — and it comes back by running `flow lint` from inside the store repo (M). Quality survives because none of flow's guarantees ship in the spec: they ship as tests, code, commit messages and the PR body, which is exactly what a maintainer reads (§4).

---

## 1. What in flow assumes an in-tree, committed `.specs/`

| Where | Assumes | gitignored / `info/exclude` | untracked symlink → outside dir | `$FLOW_SPEC=/abs/path` |
|---|---|---|---|---|
| `bin/flow:2764`, `lib/loop/util.js:86-89` | root = `git rev-parse --show-toplevel` | works (A) | works (M) | — |
| `lib/router.js:137-165` `resolveFeature` | `$FLOW_SPEC` → `.specs/.current` → branch `flow/<slug>`, each a **slug** matched against `readdirSync(<root>/.specs)` | works | works (M) | **does not work** — never opened as a path (A) |
| `scripts/flow-lint:77-104`, `hooks/lib/specgate.sh:79-107` | same order, bash | works | works (M) | does not work (A) |
| `scripts/flow-lint:697-726` id-vanished | `git show HEAD:<rel TASKS.md>` in the target repo | **silently skipped** | **silently skipped** (M) | — |
| `lib/tick.js:41-46`, `flow-lint:649-689` sha joins | `git log -- <files:>` — the task's *source* files | works | works (M) | — |
| `lib/router.js:267-273, 478-498` `PASS-<sha>.md` | `readdirSync(featureDir)` | works | works | — |
| `scripts/new-spec:239-261` `--worktree` | creates the spec dir in the current checkout, then `git worktree add` | fine for a new spec; `--reuse <prep dir>` loses an untracked `PREP.md` in the new worktree | fine — symlink target is shared (M) | — |
| `hooks/lib/specgate.sh:47-49` | `.specs/*` never counts as source | works | works | — |
| `hooks/session-context.sh:82-170` | `REVIEW.md`, `PROGRESS.md` at repo **root** | must be excluded too | symlink them from the store as well | — |
| `lib/publish.js` | mirrors open tasks to **GitHub issues** via `gh` | **leak** on a public/client repo — do not run | same | — |

Nothing in `plugins/flow` ever `git add`s a spec file (A, grep). The only knobs today are `$FLOW_SPEC` (slug), `requireSpec` in `.claude/flow.config.json`, `CC_NO_SPEC_GATE`, `CC_NO_STOP_GATE`. There is no spec-location knob.

---

## 2. Options, cheapest first

| # | Setup | Survives worktrees | Spec history | Team-shareable | Verdict |
|---|---|---|---|---|---|
| 1 | `.specs/` real dir + `.git/info/exclude` | **no** — vanishes in every `git worktree add` (M) | none | no | only for single-checkout, throwaway work |
| 2 | **Private store repo + untracked symlink + `info/exclude` + `post-checkout` hook** | yes (M) | yes, in the store | yes — the store is an ordinary private repo | **recommended** |
| 3 | Bare sidecar repo over the same tree (`git --git-dir=~/.specs.git --work-tree=.`, the yadm/vcsh dotfiles trick) | no — the files are still untracked in the target repo | yes | yes | two git states over one dir; easy to commit to the wrong one (C) |
| 4 | Private fork holding `.specs/`, `git filter-repo --invert-paths --path .specs/` before pushing upstream | yes | yes | yes | one missed strip publishes everything; rewrites history (C) |
| 5 | Orphan `specs` branch / `git notes` | — | yes | — | same remote → still public; notes are commit-sized only (A, git-notes docs) |
| ✗ | **Committed** symlink `.specs -> /abs/path` | yes | — | — | rejected: publishes a home-dir path and a `.specs` entry into the public tree |
| ✗ | Global `core.excludesFile` | as #1 | — | — | hides `.specs` in *every* repo, including ones that should commit it |

Prior art agrees with #2. Beads ships exactly this split: `bd init --stealth` (no git ops, `BEADS_DIR` outside the repo) and `bd init --contributor` (planning routed to a separate repo such as `~/.beads-planning`, role auto-detected from the remote) — built for "contributing to a repo you don't own" (C, github.com/steveyegge/beads README). OpenSpec **Stores** (beta) keep `openspec/` in its own git repo and reach it with `--store` (C, openspec.dev/docs/stores). Spec Kit has no external-dir mode; discussion #1743 proposes a separate specs repo, maintainer "aware" (C). Kiro closed the multi-path specs request (#5061) as not planned (C). Claude Code's own plan mode already writes to `~/.claude/plans/` (`plansDirectory` to move it) — out of every repo by construction (C).

---

## 3. The recommended setup, measured

Run once per clone of the target repo. `$STORE` is a private git repo whose root holds `.specs/` (one store per target repo, or one store with a directory per repo). **(verified locally)** unless noted.

```sh
STORE=~/code/specs-store/<repo-name>        # private git repo
mkdir -p "$STORE/.specs" && git -C "$STORE" init -q
printf '.current\n.next-call-count\n' > "$STORE/.specs/.gitignore"   # per-machine state, not history

cd <target-repo>
ln -s "$STORE/.specs" .specs
printf '.specs\n.claude/\n' >> .git/info/exclude   # never shows in git status; shared by all worktrees

cat > .git/hooks/post-checkout <<'EOF'
#!/bin/sh
# git worktree add never copies untracked files: re-link the private specs
top=$(git rev-parse --show-toplevel)
[ -e "$top/.specs" ] || ln -s "$(git rev-parse --git-common-dir)/../.specs" "$top/.specs" 2>/dev/null
EOF
chmod +x .git/hooks/post-checkout
```

Measured on a throwaway repo (M):

- `git status --short` → empty, in the main checkout and in a fresh `git worktree add ../wt -b feat`.
- `flow next` → `Why: wave T001 — verify: \`true\` (0 of 1 done)` in both checkouts; `flow lint` → `OK TASKS.md — 1 tasks`.
- A code commit in the worktree, then `flow tick T001` → `T001 ticked at 5592f1e`; the store shows ` M .specs/001-demo/TASKS.md`; the target repo's commit touches only `a.js`.
- Deleting the ticked T001 line: `flow lint` from the target repo → `OK … 0 tasks` (guard off); `flow lint` from `$STORE` → `ERROR 0:T001 [id-vanished]` (guard on). **Commit the store after each tick** and lint from the store to keep append-only enforcement.

Caveats:

- **`.specs/.current` is shared** by every worktree through the symlink. Two worktrees on two features must route by branch (`flow/<slug>`, the default) or `FLOW_SPEC=<slug>` per session, not by `.current`.
- **`.claude/` must be excluded too**: `new-spec` writes `.claude/flow.json` into the target repo; without the `.claude/` line it showed as `?? .claude/` (M). The exclude also covers `.claude/flow.config.json` and loop state.
- **Branch names are public on a fork PR** (`you:flow/004-thing`). Push under a neutral name: `git push origin flow/004-thing:fix-empty-slug`.
- `PROGRESS.md`, `REVIEW.md`, `CLAUDE.md`: symlink from the store and add to `info/exclude` too, or use `CLAUDE.local.md` / `~/.claude/CLAUDE.md`. Never add them, `AGENTS.md` or `.claude/` to someone else's repo unless asked (C, Ghostty `AI_POLICY.md`; practitioner consensus).
- An ignored file is **not** a permission boundary: an agent can still read `.specs/` and quote it into a commit or comment. That is what §5 is for (C, HN 47133997).
- Do not run `flow publish` against a public or client remote — it creates issues from task titles.

Alternative wiring without a symlink: `claude --add-dir "$STORE"` gives file access to the store (C, claude-code #21138), but flow's resolvers only look at `<toplevel>/.specs`, so today the symlink is still required.

---

## 4. Keeping quality when the spec never ships

The spec is a build-time scaffold. Every guarantee it gives either lives in the code already or has a native public substitute.

| Flow guarantee | Needs the spec committed to the target? | Public-repo form |
|---|---|---|
| Acceptance criteria visible to a reviewer | no | Behaviors table → **test names and bodies** (`test_rejects_empty_slug`, never `test_T003`); a "How tested" section in the PR |
| `done: <sha>` traceability | no | Clean logical commits; the *why* in the commit body in the project's style; `Fixes #123` to the **upstream** issue |
| Gates G001..N | no | Run the **project's own** lint/test/build (from its `Makefile`, `package.json`, CI workflow) — green on its CI before asking for review |
| `PASS-<sha>.md` / `verify/` evidence | no | Stays in the store; the public evidence is the project's CI run |
| `NOTES.md` `Ruling:` lines | no | Reworded as rationale in the PR body; an ADR only if the project already keeps `docs/decisions/` |
| Stop hook on red gates | no — local hook | Unchanged; optionally a `pre-push` in `.git/hooks` running the project's tests |
| `no-slop` search receipts, WHY-only comments, guard provenance | no | Unchanged — they constrain the code, and receipts were never committed anyway |

Checklist for an agent-built PR to a repo you don't own (sources: Ghostty `AI_POLICY.md`, QEMU code-provenance, Gentoo/NetBSD policies, curl's 2025–26 experience; all C):

1. Read `CONTRIBUTING.md` and any AI policy **first**. Gentoo and NetBSD refuse LLM code; do not submit there. QEMU still requires `Signed-off-by`.
2. Disclose AI use where asked, and be able to explain every line without re-asking the model (Ghostty).
3. Work from an accepted issue; no drive-by PRs (Ghostty's Jan 2026 tightening after a ~10× rise in bad PRs, C).
4. Detect and use the project's tools, formatter and commit style (`git log --oneline -20`); do not impose flow's.
5. One logical change; small diff; tests that prove the behaviors.
6. PR body written for the maintainer: what, why, how tested, trade-offs — with no reference to anything they cannot open.

Context for the bar: curl's valid-report rate fell from ~1 in 6 to ~1 in 20–30 under AI volume and its bounty closed in Jan 2026 (C, The New Stack); GitHub added maintainer PR throttles for the same reason (C, The Register 2026-02-03). A disclosed, tested, convention-matching PR is rare enough to stand out.

---

## 5. Leak prevention

Leak vectors, in the order they actually happen: commit messages ("T003: …", "per spec 004"), PR bodies, code comments (`// see .specs/…`), test names (`it("T3: …")`), branch names, and cross-repo auto-links — a `owner/private#509` in a commit message becomes a timeline event on the other repo (C, wakqasahmed/ai-engineering-workflow-skills #193).

`commit-msg` hook, measured blocking `T001: change a.js per spec 001` and passing `Print 2 instead of 1` (M). It lives in `.git/hooks`, so it covers every worktree and is never pushed:

```sh
#!/bin/sh
# .git/hooks/commit-msg — block flow vocabulary in a public commit message
if grep -Eiq '\b(T|G|CHK)[0-9]{3}\b|\.specs/|TASKS\.md|PASS-[0-9a-f]+|\bspec [0-9]{3}\b|flow (tick|next|lint)' "$1"; then
  echo "commit-msg: flow vocabulary in message — rewrite it for maintainers" >&2; exit 1
fi
```

The same pattern over the outgoing diff belongs in `pre-push` (`git diff @{push}.. | grep -Ei …` on added lines), and over the PR body before `gh pr create`. `\b[TG][0-9]{3}\b` will false-positive on real identifiers in some codebases (e.g. `T100` model numbers) — the hook's message tells the agent to rewrite, and a human can `--no-verify` a genuine one.

---

## 6. What would make this first-class in flow (not built)

Ranked by value per line. None is needed to use §3 today.

1. **`flow stealth <store>`** — does §3's five commands idempotently, prints what it wrote. Removes the only manual part.
2. **id-vanished against the store** — in `flow-lint:697-726`, when the TASKS.md path resolves (after `realpath`) outside `$TOPLEVEL`, diff against `HEAD` of the repo that owns the real file instead of skipping silently. Closes the one guard §1 loses.
3. **Leak lens** — add the §5 pattern to `slop-check` and the adversary `slop` lens when the repo is in stealth mode (the `.specs` entry is untracked), so a leak is caught at review, not only at commit.
4. **`flow publish` refusal** in stealth mode.

Deliberately not proposed: a `FLOW_SPECS_DIR` path knob. It would touch three independent resolvers (`router.js`, `flow-lint`, `specgate.sh`) to do what one symlink already does (M).

---

## 7. Sources

- flow source, read 2026-09-16: `plugins/flow/bin/lib/router.js`, `scripts/flow-lint`, `hooks/lib/specgate.sh`, `bin/lib/tick.js`, `scripts/new-spec`, `bin/lib/publish.js`, `hooks/session-context.sh` (A)
- Beads stealth/contributor modes: https://github.com/steveyegge/beads (C)
- OpenSpec Stores: https://openspec.dev/docs/stores ; commit-specs debate: https://github.com/Fission-AI/OpenSpec discussion #837 (C)
- Spec Kit separate-specs-repo discussion: https://github.com/github/spec-kit discussion #1743 (C)
- Kiro multi-path specs, closed not planned: https://github.com/kirodotdev/Kiro issue #5061 (C)
- Claude Code `--add-dir` CLAUDE.md loading: https://github.com/anthropics/claude-code issue #21138 ; plans dir: issues #14866, #44394 (C)
- git notes not pushed by default: https://git-scm.com/docs/git-notes (A)
- git-filter-repo: https://github.com/newren/git-filter-repo (A)
- worktree untracked-file workarounds: https://github.com/keithamus/git-worktree-share (C)
- Ghostty AI policy: https://github.com/ghostty-org/ghostty/blob/main/AI_POLICY.md (C)
- QEMU code provenance: https://www.qemu.org/docs/master/devel/code-provenance.html (C)
- Gentoo AI policy: https://wiki.gentoo.org/wiki/Project:Council/AI_policy ; NetBSD: https://hackaday.com/2024/05/18/netbsd-bans-ai-generated-code-from-commits/ (C)
- curl and AI slop: https://thenewstack.io/curls-daniel-stenberg-ai-is-ddosing-open-source-and-fixing-its-bugs/ (C)
- GitHub maintainer PR controls: https://www.theregister.com/2026/02/03/github_kill_switch_pull_requests_ai/ (C)
- `.gitignore` is not an agent boundary: https://news.ycombinator.com/item?id=47133997 (C)
- Debian 2026-08 vote against a blanket AI-code ban (U — search snippet only)
