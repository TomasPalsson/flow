---
name: ecosystem-version-commands
description: Exact CLI commands, registry HTTP APIs, JSON shapes, and gotchas per ecosystem (npm/bun, pip/uv, cargo, go, docker, ruby, java) plus security scanners. Load when you need precise invocations or an ecosystem the scanner does not fully cover.
---

# Ecosystem command & API reference

> Every concrete "latest" below is a worked example to re-query, never a constant.

## npm / bun (JavaScript)

```bash
npm outdated --json            # {pkg:{current,wanted,latest,...}}. EXIT 1 if any outdated, 0 if clean.
                               # `current` absent in lockfile-only mode (no node_modules).
npm view <pkg> dist-tags --json
npm view <pkg> deprecated      # empty stdout = not deprecated; string = deprecated
npm view <pkg> peerDependencies --json
npm view <pkg>@<range> version # latest version matching a range (e.g. express@4 -> latest 4.x)
```

Registry HTTP API (no auth):

```bash
curl https://registry.npmjs.org/<pkg>/latest           # {version: "..."} latest STABLE
curl -H 'Accept: application/vnd.npm.install-v1+json' \
     https://registry.npmjs.org/<pkg>                  # light packument: {dist-tags, versions, modified}
# scoped: @types/node -> @types%2Fnode
```

**`deprecated` is per-version:** `packument.versions[ packument["dist-tags"].latest ].deprecated`
— NOT a top-level field. Only `dist-tags.latest` is safe; `next`/`canary`/`beta`/`rc`
are prerelease lanes (react `latest=19.2.7` vs `next=19.3.0-canary`).

**bun traps (1.2.x, verified):** `bun outdated --json` ignores the flag (prints the
table, always exit 0) — drive it with `bun x npm-check-updates --target minor|patch
--jsonUpgraded` instead. `bun audit` does not exist → use `npm audit`. `bun.lock` is
**JSONC** (trailing commas) — parse with a JSONC parser, not `JSON.parse`.

Manifest spots to check beyond `dependencies`/`devDependencies`: `peerDependencies`,
`optionalDependencies`, `overrides`/`resolutions` (force transitive versions — can
hide drift), `engines.node`, `packageManager` (corepack `bun@1.2.4`), `volta`. Plus
`.nvmrc` / `.node-version`.

## Python (uv preferred)

```bash
uv lock --check                # non-zero if uv.lock is out of sync with pyproject (uv >=0.3)
uv lock --upgrade-package <pkg>
uv pip list --outdated         # VERIFY in your uv version; fall back to the API
pip index versions <pkg>       # all versions on PyPI (pip 21.2+)
```

PyPI JSON API:

```bash
curl -s https://pypi.org/pypi/<pkg>/json | jq '.info.version'   # latest stable (excludes prerelease)
# per-release yank flag: .releases["<ver>"][0].yanked  (true = never recommend)
# .info.requires_python is the package's Python floor
```

`pyproject.toml`: `[project].dependencies`, `requires-python` (the runtime floor —
flag if EOL), `[tool.uv].constraint-dependencies`.

## Rust (cargo)

```bash
cargo update --dry-run         # built-in; shows lockfile changes (no install of cargo-outdated needed)
cargo outdated --format json   # third-party (cargo install cargo-outdated) — may be absent
cargo audit --json             # RustSec; also "warnings" for unmaintained/unsound crates
```

crates.io API (**requires a `User-Agent` header or 403**):

```bash
curl -s -H 'User-Agent: audit/1.0' https://crates.io/api/v1/crates/<name> | jq '.crate.max_stable_version'
# .crate.max_version includes prereleases; .versions[].yanked must be excluded
```

`Cargo.toml`: `[dependencies]`, `[workspace.dependencies]`, `rust-version` (MSRV),
`edition` (2015/2018/2021/2024 — a syntax switch, NOT a toolchain version).
`rust-toolchain.toml` `channel` pins the toolchain. Rust has no toolchain EOL.

## Go

```bash
go list -m -u all                       # all deps with [latest] annotation
go list -m -u -versions <module>        # all available versions
go get -u=patch ./...                   # patch-only upgrade (safer than -u)
curl -s https://proxy.golang.org/<module>/@latest   # {"Version":"v...","Time":...}
govulncheck ./...                       # call-graph-aware vuln check (only reachable vulns)
```

`go.mod`: the `go 1.xx` directive is a MINIMUM (enforced since 1.21) — flag if EOL
(Go supports N and N-1). **v2+ modules have a different import path** (`.../v2`) —
check the v1 and v2+ paths separately. `+incompatible` = pre-modules major. `retract`
directives hide versions from `go get` by default.

## Docker base images

```bash
crane ls <image>                        # list tags (lightweight)
crane digest <image>:<tag>              # current registry digest for a tag
skopeo list-tags docker://<image>       # alternative, respects auth
docker scout cves <image>:<tag>         # CVEs in image layers (or: trivy image / grype)
curl -s 'https://hub.docker.com/v2/repositories/library/<image>/tags?page_size=100&name=<prefix>' | jq '.results[].name'
```

Pin pattern: `FROM node:20-alpine@sha256:...` (tag for humans + digest for
immutability). `:latest` and bare floating tags (`node:20`) are flaggable. Map the
base OS/runtime to `endoflife.date/api/<product>.json`.

## Ruby / Java (brief)

```bash
bundle outdated --strict                # only updates within the Gemfile spec
curl -s https://rubygems.org/api/v1/gems/<name>.json | jq '.version'   # latest stable
bundler-audit check --update            # ruby-advisory-db

mvn versions:display-dependency-updates # Maven (also :display-plugin-updates)
./gradlew dependencyUpdates             # Gradle (ben-manes versions plugin)
```

## Security scanners (the axis the freshness scan does NOT cover)

```bash
osv-scanner -r . --format json          # UNIVERSAL — reads all lockfiles; preferred. May be absent.
npm audit --json                        # needs package-lock.json
pip-audit -r requirements.txt --format json
cargo audit --json
gh api '/repos/{o}/{r}/dependabot/alerts?state=open&severity=critical,high'
```

OSV.dev HTTP API (no install needed — the universal fallback):

```bash
curl -s -X POST https://api.osv.dev/v1/querybatch -H 'Content-Type: application/json' \
  -d '{"queries":[{"package":{"name":"lodash","ecosystem":"npm"},"version":"4.17.20"}]}'
# ecosystem strings (exact): npm, PyPI, crates.io, Go, RubyGems, Maven, NuGet, Packagist, Pub
# Backport check: if affected[].ranges[].events[] has TWO `fixed` events in different
# major lines, the in-major patch is enough — don't force the breaking major.
```

## EOL runtimes

```bash
curl -s https://endoflife.date/api/<product>.json   # nodejs, python, go, ruby, java, php, ubuntu, alpine, debian, postgresql, ...
# per cycle: {cycle, eol (date|false), support (active-support end), lts, latest}
# eol in the past  -> EOL, no security patches (flag HIGH)
# support past, eol future -> security-only phase (flag MEDIUM)
```

## Lockfile vs manifest, and what to read

Manifest = policy (allowed range); lockfile = reality (resolved version). Always
read the lockfile for CVE matching. Lockfile sync checks: `npm ci` (fails on drift),
`uv lock --check`, `cargo check --locked`, `go mod verify`. Detect private registries
(`.npmrc`, `.cargo/config.toml`, `pip.conf`, `--index-url`) and warn that public-API
version data may be unavailable. Watch package aliases (`"x": "npm:y@^1"`,
cargo `package = "..."`) — query the underlying name.
