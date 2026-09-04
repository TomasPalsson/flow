---
name: version-audit
description: >-
  Audit every version reference in a repo and check each against the latest SAFE
  version — not just the latest. Use WHENEVER the user wants to find outdated or
  risky dependencies, pins, or actions, e.g. "are my deps up to date", "check for
  outdated packages", "is everything on the latest version", "stop using
  checkout@v4 when v7 exists", "audit my GitHub Actions versions", "find stale /
  deprecated / EOL dependencies", "bump my dependencies safely", "version audit",
  "dependency freshness", "what's outdated". Triggers on any manifest: package.json,
  Cargo.toml, go.mod, pyproject.toml, requirements.txt, Gemfile, Dockerfile FROM,
  .nvmrc, .tool-versions, and .github/workflows. Covers npm/bun, pip/uv, cargo
  (Rust), go modules, Docker base images, GitHub Actions, and runtime pins
  (engines.node, go directive, requires-python). Distinguishes patch/minor (safe) from major
  (breaking — flag, never auto-apply), filters out prereleases/yanked/deprecated,
  flags EOL runtimes, and separates freshness from security (CVEs).
---

# Version Audit — latest ≠ safe

The job: for every version reference in the repo, decide whether it is on the
**latest SAFE version**. "Latest" is easy and wrong. "Safe" is the whole point.

## The four versions (internalize this before doing anything)

Most version mistakes come from collapsing these four into one:

| Term | Meaning | Where it lives |
|------|---------|----------------|
| **resolved** | what is actually installed/running | the **lockfile** |
| **wanted** | highest version the declared range allows | range + registry |
| **latest** | newest published (`dist-tags.latest`) | registry pointer |
| **latest-SAFE** | latest that is non-breaking *for this repo*, non-prerelease, non-yanked, non-deprecated, non-EOL, no known CVE | **your judgement** |

`wanted == resolved` does **not** mean up to date — `latest` may be a new major.
Match CVEs against **resolved** (lockfile), never the manifest range: the manifest
is *policy* (what's allowed), the lockfile is *reality* (what runs).

## Run the scanner first

A self-contained scanner does the mechanical discovery + "latest" lookups across
ecosystems (no local tooling needed beyond node/bun + optional `gh`):

```bash
node scripts/version-audit.mjs [path] [--json] \
  [--actions-only|--deps-only|--runtimes-only] [--no-actions] [--concurrency=8]
```

No `node`/`bun` available (Python/Rust/Go-only box)? Skip the scanner and audit by
hand with the commands in [`references/ecosystem-commands.md`](references/ecosystem-commands.md)
— the decision framework below applies identically.

It scans `.github/workflows/*.yml`, `package.json`, `pyproject.toml`, `Cargo.toml`,
`go.mod`, and runtime pins (`.nvmrc`, `.node-version`, `.python-version`,
`.tool-versions`, `engines.node`, `go` directive, `requires-python`, Dockerfile
`FROM`); queries the live registry/release/EOL APIs; and prints a severity-sorted
table. **Authenticate GitHub first** (`gh auth status` or `GH_TOKEN`) — anonymous
is 60 req/hr and the Actions checks will silently come up short.

The scanner reports the **freshness** axis. It does **not** cover the **security**
axis — run a CVE scanner too (next section). Treat the script's output as the
inventory; apply the decision framework below before recommending anything.

### When the scan is incomplete (recover, don't paper over)

| Symptom | Root cause | What to do |
|---------|-----------|------------|
| Actions rows say `MANUAL`/`?`, few results | anonymous GitHub limit (60/hr) | `gh auth login` or set `GH_TOKEN`, re-run; until then state Actions coverage is partial |
| npm/pypi/cargo row says "not found (private?)" | private registry | confirm via `.npmrc`/`.cargo/config.toml`; report as **unverified**, never as up-to-date |
| security axis empty | `osv-scanner`/`pip-audit`/`cargo-audit` not installed | fall back to `npm audit` + OSV.dev `querybatch` API; say the CVE axis is uncovered if even that fails |
| go.mod findings look truncated | scanner caps Go direct deps at 60 | re-run `--deps-only` per module, or `go list -m -u all` by hand |
| zero findings overall | could be clean — or nothing resolved | check the "Scanned" + auth line before claiming all-clear |

## The two independent axes — never conflate them

A version is risky for two unrelated reasons. Report both:

1. **Freshness / maintenance** — how far behind latest, is it deprecated, is the
   runtime EOL. (The scanner covers this.)
2. **Security** — does the *resolved* version have a known CVE.

Old-but-not-vulnerable is fine. Latest-but-its-only-CVE-fix-is-in-the-next-major
is a real trap. Run a security scanner against lockfiles:

```bash
osv-scanner -r .                  # universal (npm/pip/cargo/go/maven/...) — preferred
npm audit --json                  # needs package-lock.json (bun has NO `audit` in 1.2.x → use npm)
pip-audit -r requirements.txt     # or against the venv
cargo audit                       # RustSec; also flags unmaintained crates
gh api /repos/{owner}/{repo}/dependabot/alerts   # if Dependabot is enabled
```

**The backport nuance:** when a CVE advisory lists fix versions in *two* major
lines (OSV `affected[].ranges[].events[].fixed` has two `fixed` events), a
backport exists — recommend the **in-major patch**, not the breaking major. Node
LTS, Python 3.x, and OpenSSL all backport security fixes to supported old lines.

If `osv-scanner`/`cargo-audit`/`pip-audit` are not installed, say so and fall back
to `npm audit` + the OSV.dev HTTP API (`POST https://api.osv.dev/v1/querybatch`);
do not silently skip the security axis.

## NEVER (the prohibitions, with why)

- **NEVER match a CVE against the manifest range** — only against the **resolved**
  (lockfile) version. `^4.0.0` allowing a vulnerable version ≠ running it.
- **NEVER treat "the tag resolves" as currency** — `setup-node@v4` resolves forever
  while v6 is latest. Compare against `releases/latest`.
- **NEVER auto-apply a major bump** — breaking by definition; flag with the changelog
  and let the user decide.
- **NEVER recommend a prerelease, yanked, or deprecated version** — not the `next`/
  `canary`/`beta` dist-tags, not `yanked:true`/retracted, not a deprecated package
  (recommend its successor instead). And **flag a prerelease that's already pinned**
  in a manifest (`"typescript": "next"`, `^2.0.0-rc.1`) — it's an ongoing risk, not a target.
- **NEVER report a clean bill of health when coverage was partial** — anonymous
  GitHub limits, private registries, or a missing security scanner mean "no findings"
  is "didn't check," not "all good." Say which.
- **NEVER conflate freshness with security** — old-but-unpatched is a *maintenance*
  signal; old-with-a-CVE is a *security* signal. They drive different urgency.
- **NEVER mega-bump everything at once** — one breaking change is unattributable
  among 40 changed deps. Batch small, test between batches.

## Semver tiering — the recommendation policy

This is how you turn "behind" into an action. **Never auto-apply a major.**

| Gap | Default | Why |
|-----|---------|-----|
| **patch** (x.y.Z) | `UPDATE_PATCH` — apply, run tests | almost always safe; exceptions: pre-1.0, bug-compat reliance |
| **minor** (x.Y.0) | `UPDATE_MINOR` — apply, run tests, skim changelog | *should* be additive, but semver lying is real (TS minors break types; Django minors drop Python versions; axios 1.0 changed defaults on a "minor") |
| **major** (X.0.0) | `REVIEW_MAJOR` — flag, link changelog, **do not auto-apply** | breaking by definition; check the new version's `peerDependencies`/`engines` against the repo first |
| **pre-1.0** (0.y.z) | flag *every* bump | maintainer has declared the API unstable; minor/patch can break |

Before recommending any **major**: link the changelog/release notes and the
migration guide, and verify peer/engine constraints are satisfiable. One bump at a
time — never mega-bump everything at once, or you cannot attribute the breakage.

## Never recommend these as "latest"

- **Prereleases**: any version with `-alpha/-beta/-rc/-canary/-next/-dev/-nightly`,
  and the `next`/`canary`/`beta`/`rc` **dist-tags**. Real packages route bleeding
  edge through `next` (React canary, Next.js, TypeScript `next`). Only the `latest`
  dist-tag / PyPI `info.version` / crates `max_stable_version` is safe.
- **Yanked / retracted**: PyPI `yanked:true`, crates `yanked:true`, Go `retract`
  directives. Never a recommendation target.
- **Deprecated**: npm `packument.versions[latest].deprecated` (per-version, NOT
  top-level) → recommend the successor, not a version bump.

## GitHub Actions — the part everyone gets wrong

The user's motivating case (`checkout@v4` when v7 exists) lives here.

- **A floating major tag (`@v4`) is a *mutable pointer*, and its existence is NOT
  a currency signal.** `setup-node@v4` still resolves while latest is v6. Judge
  currency against `releases/latest`, never "the tag resolves." The scanner does
  this; if checking by hand:
  `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name`.
- **`@main`/`@master` in `uses:`** = no version signal, silent live updates → flag
  as HIGH regardless of freshness.
- **SHA-pin third-party actions for security**, with a `# v4.2.2` comment so
  Dependabot/Renovate can bump it. This is not pedantry: see the tj-actions CVE in
  the reference. Tag pins — even `@v45.0.7` — gave zero protection.
- **Deprecation that silently breaks CI**: `upload-artifact@v3`/`download-artifact@v3`
  shut down (2024-11-30, wire-incompatible v4); Node12/16 runtime removals; the
  `set-output`/`set-env` workflow commands.

**MANDATORY — READ ENTIRE FILE** before reporting on any workflow:
[`references/github-actions.md`](references/github-actions.md) — the SHA-pinning
pattern + resolver, the tj-actions CVE-2025-30066 facts, the full deprecation
tables, monorepo/no-release quirks (e.g. `github/codeql-action`), and per-action
breaking changes.

## EOL runtimes are a version category too

`engines.node`, `.nvmrc`, the `go X.Y` directive, `requires-python`, Dockerfile
`FROM`, and `.tool-versions` pin *runtimes*. An EOL runtime gets no security
patches — flag it HIGH even with no CVE today. The scanner cross-references
`https://endoflife.date/api/<product>.json`. Node odd majors (19/21/23) are never
LTS and have ~7-month windows.

## Ecosystem command details

[`references/ecosystem-commands.md`](references/ecosystem-commands.md) holds the
exact CLI invocations, registry HTTP APIs, and JSON shapes per ecosystem.
**MANDATORY — READ ENTIRE FILE** when any of these is true:

| Present in repo / asked about | Why the reference is required |
|-------------------------------|-------------------------------|
| `Dockerfile`, `*.Dockerfile`, compose images | tag/digest lookup (crane/skopeo) + EOL mapping aren't in the scanner |
| `Gemfile`, `pom.xml`, `build.gradle` | Ruby/Maven/Gradle commands the scanner doesn't run |
| user wants the **security/CVE** axis | the OSV.dev batch API + per-ecosystem audit commands |
| `uv.lock`/`pyproject`, lockfile **drift** suspected | `uv lock --check`, `npm ci`, `cargo check --locked` |
| a **private registry** (`.npmrc`, `.cargo/config.toml`, `pip.conf`) | how to detect + warn that public APIs won't resolve |

**Do NOT load** when the scanner already covered the repo cleanly (only
`package.json` + workflows, all resolved) and the user only wants freshness.

Known tooling traps baked into the scanner (do not relearn the hard way):
`bun outdated --json` is a no-op (table only, always exit 0); `bun audit` doesn't
exist in 1.2.x; `bun.lock` is JSONC (not `JSON.parse`-able); `npm outdated --json`
exits **1** when anything is outdated.

## Reporting

Order findings by severity, not by file: **CRITICAL/HIGH CVEs → EOL runtimes →
deprecated/branch-refs → stale majors → minor/patch**. For each, show: ref
location, resolved/current, latest-safe target, breaking?, CVE?, and the action
(`UPDATE_PATCH/MINOR`, `REVIEW_MAJOR`, `REPLACE`, `PLAN_UPGRADE`). Be honest about
coverage: state what could not be resolved (private registries, anonymous GitHub
rate limits, missing security scanner) rather than implying a clean bill of health.

Do not edit files unless the user asks. When they do, apply patch/minor in small
batches and run the test suite after each; hand majors to the user with the
changelog. Respect intentional pins (`# pinned`, Dependabot/Renovate `ignore`).
