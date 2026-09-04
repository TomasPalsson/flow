---
name: github-actions-version-audit
description: SHA-pinning security, the tj-actions CVE, deprecation tables, per-action breaking changes, and the gh resolver for auditing GitHub Actions versions. Load when auditing any .github/workflows file.
---

# GitHub Actions — version & supply-chain reference

## Resolving "latest" correctly

```bash
# Standard path — latest release tag:
gh api repos/<owner>/<repo>/releases/latest --jq .tag_name      # actions/checkout -> v7.0.0

# Actions with NO usable release (tags only, or a bundle release object).
# github/codeql-action is the canonical trap: releases/latest -> "codeql-bundle-vX".
gh api "repos/<owner>/<repo>/tags?per_page=100" \
  --jq '[.[] | select(.name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | .[0].name'

# Monorepo subdir actions: uses: github/codeql-action/init@v4
# -> repo is the FIRST TWO segments only (github/codeql-action); strip the subdir.

# Batch many in ONE request (rate-limit win):
gh api graphql -f query='{
  checkout:  repository(owner:"actions", name:"checkout")   { latestRelease { tagName } }
  setupNode: repository(owner:"actions", name:"setup-node") { latestRelease { tagName } } }' --jq .data

gh api rate_limit --jq '.resources.core'   # authed 5000/hr, anon 60/hr
```

**The floating-major trap:** `@v4` is a mutable tag maintainers force-push to the
newest `v4.x`. It keeps resolving forever — `setup-node@v4` works fine while latest
is v6. Currency MUST be judged against `releases/latest`, never tag existence.

## SHA pinning — the security control

```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

A 40-char commit SHA is immutable (git is content-addressable). A tag — `@v4`,
even `@v4.2.2` — is a mutable ref the owner *or an attacker with write access* can
repoint. The `# v4.2.2` comment is what Dependabot/Renovate parse to bump the SHA.

Resolve a tag to the commit SHA to pin (dereference annotated tags):

```bash
ref=$(gh api repos/$OWNER/$REPO/git/refs/tags/$TAG)
type=$(jq -r .object.type <<<"$ref"); sha=$(jq -r .object.sha <<<"$ref")
[ "$type" = tag ] && sha=$(gh api repos/$OWNER/$REPO/git/tags/$sha --jq .object.sha)
echo "$sha"   # this is the commit to pin to
```

`actions/*` use lightweight tags (`type:commit`). Third-party actions may use
annotated tags — the resolver above handles both.

### tj-actions/changed-files — CVE-2025-30066 (why tags aren't enough)

- Active **March 14–15, 2025**. An attacker **retroactively repointed all version
  tags `v1.0.0`…`v45.0.7`** to one malicious commit.
- Payload scraped the runner process memory for secrets and printed them to the
  build log — publicly visible on public-repo runs. ~**23,000 repos** affected.
- **SHA-pinned users were immune** (their pinned commit was untouched). Tag-pinned
  users — including `@v45.0.7` — ran the payload with zero change on their side.
- Patched in `v46.0.0`. **Audit rule:** any tj-actions ref by tag, or a SHA pinned
  to a pre-March-2025 commit, must be flagged.

Tooling: OpenSSF Scorecard `Pinned-Dependencies` check; `step-security/harden-runner`
(runtime egress monitor; `egress-policy: audit|block`) would have caught the exfil.
`@main`/`@master` is worse than any tag — no version signal, no audit trail, no
rollback point.

## Deprecation history (must-flag)

| Item | Status / date | Fix |
|------|---------------|-----|
| Node12 actions (`checkout@v1/v2`, `setup-node@v1/v2`) | Node12 removed from runner **2023-08-14** | bump major |
| Node16 actions (`checkout@v3`, `setup-python@v3/v4`) | deprecated, warns in logs | bump to Node20 major |
| `upload-artifact@v1/v2` | **shut down 2024-06-30** | v4+ |
| `upload-artifact@v3`, `download-artifact@v3` | **shut down 2024-11-30** (github.com; `v3.2.2` is GHES-only) | v4+ — mind the immutability breaking change |
| `github/codeql-action@v1/v2` | deprecated | v3/v4 |

Deprecated **workflow commands** (scan `run:` blocks):

| Command | Replacement | Note |
|---------|-------------|------|
| `::set-output name=k::v` | `echo "k=v" >> $GITHUB_OUTPUT` | warns since runner v2.298.0 (Oct 2022) |
| `::save-state name=k::v` | `echo "k=v" >> $GITHUB_STATE` | same |
| `::set-env name=k::v` | `echo "k=v" >> $GITHUB_ENV` | **disabled Sep 2020, CVE-2020-15228** |
| `::add-path::p` | `echo "p" >> $GITHUB_PATH` | disabled Sep 2020 (same CVE) |

`ACTIONS_ALLOW_UNSECURE_COMMANDS=true` re-enables the disabled-for-CVE commands —
itself a red flag if present.

## Per-action breaking changes to flag on a major bump

| Action | Breaking change |
|--------|-----------------|
| `actions/checkout` | v2: shallow clone default (`fetch-depth:1`) — set `fetch-depth:0` for full history/`git describe`. v7: restricts fork-PR checkout under `pull_request_target`/`workflow_run`. |
| `actions/setup-python` | v4+: `python-version` (or `-version-file`) is **required** — step fails without it. |
| `actions/setup-java` | v2+: `distribution` input **required** (temurin/corretto/zulu). |
| `actions/setup-go` | v4+: module caching ON by default — conflicts with a manual `actions/cache` for Go (`cache:false`). |
| `actions/upload-artifact` | v4: artifacts immutable — can't upload the same name twice in a run (`overwrite:true` or unique names); v3↔v4 wire-incompatible; **upload and download majors must match.** |
| `actions/cache` | `cache-hit` is `'true'` only on an EXACT key match; a `restore-keys` partial hit reports `cache-hit:false`. |

## Other workflow version refs (don't miss these)

- `jobs.<id>.container.image` and `services.<x>.image`: container tags (`node:20`,
  `postgres:16`) are version refs — `:latest` and missing digests are the same
  mutable risk.
- Reusable workflows: `uses: owner/repo/.github/workflows/x.yml@ref` — the `@ref`
  gets the same tag/SHA/branch analysis; `@main` here is equally dangerous.
- Runner labels: `ubuntu-latest` silently migrates OS (currently `ubuntu-24.04`); a
  pinned old label (`ubuntu-20.04`, EOL Apr 2025) can break overnight when removed.
- Local/composite actions (`uses: ./...`) have no external version — skip, but
  recurse into any third-party `uses:` they wrap.
