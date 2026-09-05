#!/usr/bin/env bash
# audit-recon.sh — Phase 0 reconnaissance for the /audit skill
# Usage: ./audit-recon.sh [project_dir] [since]
# Output: writes summary to stdout; the /audit skill redirects to .audit/recon.txt
set -uo pipefail

PROJECT_DIR="${1:-.}"
SINCE="${2:-6 months ago}"
cd "$PROJECT_DIR"

echo "=== AUDIT RECON ==="
echo "path:  $(pwd)"
echo "date:  $(date)"
echo "since: $SINCE"
echo ""

# ─── STACK DETECTION ────────────────────────────────────────────────────
echo "── Stacks ──"
STACKS=()
test -f pyproject.toml   && STACKS+=("python")
test -f setup.py         && STACKS+=("python")
test -f requirements.txt && STACKS+=("python")
test -f package.json     && STACKS+=("nodejs")
test -f Cargo.toml       && STACKS+=("rust")
test -f go.mod           && STACKS+=("go")
test -f Gemfile          && STACKS+=("ruby")
test -f pom.xml          && STACKS+=("java")
find . -maxdepth 2 -name "build.gradle" -o -name "build.gradle.kts" 2>/dev/null | grep -q . && STACKS+=("java")

# TypeScript upgrade
if printf '%s\n' "${STACKS[@]:-}" | grep -q nodejs; then
  ts_signals=0
  test -f tsconfig.json && ts_signals=$((ts_signals+1))
  grep -q '"typescript"' package.json 2>/dev/null && ts_signals=$((ts_signals+1))
  ts_count=$(find . -name "*.ts" -not -name "*.d.ts" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
  [ "$ts_count" -gt 5 ] && ts_signals=$((ts_signals+1))
  [ "$ts_signals" -ge 1 ] && STACKS+=("typescript")
fi

# Deduplicate
UNIQ_STACKS=$(printf '%s\n' "${STACKS[@]:-unknown}" | sort -u | tr '\n' ' ')
echo "  detected: ${UNIQ_STACKS:-unknown}"

# ─── BUILD TOOLS ────────────────────────────────────────────────────────
JS_BUILD=""; PY_BUILD=""
test -f bun.lockb         && JS_BUILD="bun"
test -f pnpm-lock.yaml    && JS_BUILD="${JS_BUILD:-pnpm}"
test -f yarn.lock         && JS_BUILD="${JS_BUILD:-yarn}"
test -f package-lock.json && JS_BUILD="${JS_BUILD:-npm}"
test -f uv.lock           && PY_BUILD="uv"
test -f poetry.lock       && PY_BUILD="${PY_BUILD:-poetry}"
test -f Pipfile.lock      && PY_BUILD="${PY_BUILD:-pipenv}"
[ -n "$JS_BUILD" ] && echo "  js build: $JS_BUILD"
[ -n "$PY_BUILD" ] && echo "  py build: $PY_BUILD"

# ─── FRAMEWORKS ─────────────────────────────────────────────────────────
FRAMEWORKS=""
find . -name "settings.py" -not -path "*/node_modules/*" -not -path "*/.venv/*" 2>/dev/null | grep -q . && FRAMEWORKS="$FRAMEWORKS django"
grep -rl "from fastapi" --include="*.py" . 2>/dev/null | head -1 | grep -q . && FRAMEWORKS="$FRAMEWORKS fastapi"
grep -rl "from flask" --include="*.py" . 2>/dev/null | head -1 | grep -q . && FRAMEWORKS="$FRAMEWORKS flask"
find . -name "next.config.*"   -not -path "*/node_modules/*" 2>/dev/null | grep -q . && FRAMEWORKS="$FRAMEWORKS nextjs"
find . -name "svelte.config.*" -not -path "*/node_modules/*" 2>/dev/null | grep -q . && FRAMEWORKS="$FRAMEWORKS svelte"
find . -name "nest-cli.json"   -not -path "*/node_modules/*" 2>/dev/null | grep -q . && FRAMEWORKS="$FRAMEWORKS nestjs"
find . -name "vite.config.*"   -not -path "*/node_modules/*" 2>/dev/null | grep -q . && FRAMEWORKS="$FRAMEWORKS vite"
test -f angular.json && FRAMEWORKS="$FRAMEWORKS angular"
grep -rl '"github.com/gin-gonic/gin"' --include="*.go" . 2>/dev/null | head -1 | grep -q . && FRAMEWORKS="$FRAMEWORKS gin"
[ -n "$FRAMEWORKS" ] && echo "  frameworks:$FRAMEWORKS"

# ─── MONOREPO ───────────────────────────────────────────────────────────
MONOREPO=""
test -f nx.json              && MONOREPO="nx"
test -f turbo.json           && MONOREPO="${MONOREPO:-turborepo}"
test -f pnpm-workspace.yaml  && MONOREPO="${MONOREPO:-pnpm-workspace}"
test -f lerna.json           && MONOREPO="${MONOREPO:-lerna}"
test -f go.work              && MONOREPO="${MONOREPO:-go-workspace}"
test -f Cargo.toml && grep -q '^\[workspace\]' Cargo.toml 2>/dev/null && MONOREPO="${MONOREPO:-cargo-workspace}"
[ -n "$MONOREPO" ] && echo "  monorepo: $MONOREPO  (SKILL MUST ASK USER WHICH PACKAGE/WORKSPACE TO AUDIT)"

# ─── SIZE TIER ──────────────────────────────────────────────────────────
echo ""
echo "── Size ──"
total_loc=$(find . -type f \
  \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" \
     -o -name "*.go" -o -name "*.rs" -o -name "*.rb" -o -name "*.java" -o -name "*.kt" \) \
  -not -path "*/node_modules/*" -not -path "*/.venv/*" \
  -not -path "*/vendor/*" -not -path "*/target/*" \
  -not -path "*/dist/*" -not -path "*/build/*" \
  -not -path "*/__pycache__/*" \
  -not -name "*.min.js" -not -name "*.generated.*" -not -name "*.d.ts" \
  2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
total_loc=${total_loc:-0}

file_count=$(find . -type f \
  \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" \) \
  -not -path "*/node_modules/*" -not -path "*/vendor/*" -not -path "*/.venv/*" 2>/dev/null | wc -l | tr -d ' ')

if   [ "$total_loc" -lt 5000 ];   then SIZE_TIER="small"
elif [ "$total_loc" -lt 50000 ];  then SIZE_TIER="medium"
elif [ "$total_loc" -lt 500000 ]; then SIZE_TIER="large"
else                                   SIZE_TIER="huge"; fi

echo "  loc:   $total_loc"
echo "  files: $file_count"
echo "  tier:  $SIZE_TIER"

# Budget implied by tier
case "$SIZE_TIER" in
  small)  echo "  findings budget: 10" ;;
  medium) echo "  findings budget: 15" ;;
  large)  echo "  findings budget: 20" ;;
  huge)   echo "  findings budget: 25 per subsystem (split required)" ;;
esac

# ─── GIT HOT-SPOTS ──────────────────────────────────────────────────────
echo ""
echo "── Hot-Spots (churn × loc, top 20) ──"

if git rev-parse --git-dir > /dev/null 2>&1; then
  tmp_churn=$(mktemp -t audit_churn.XXXXXX)
  git log --since="$SINCE" --name-only --pretty=format: 2>/dev/null \
    | grep -v '^$' \
    | grep -vE '\.(lock|wasm|dylib|so|dll|exe|png|jpg|jpeg|gif|svg|ico|pdf|zip|gz|tar|min\.js|map)$' \
    | grep -vE '(node_modules|vendor/|dist/|build/|target/|__pycache__|\.venv)/' \
    | sort | uniq -c \
    | awk '{print $2, $1}' > "$tmp_churn"

  while IFS=' ' read -r filepath churn; do
    [ -f "$filepath" ] || continue
    loc=$(wc -l < "$filepath" 2>/dev/null || echo 0)
    score=$((churn * loc))
    printf "  %8d  churn=%-4d  loc=%-7d  %s\n" "$score" "$churn" "$loc" "$filepath"
  done < "$tmp_churn" | sort -rn | head -20
  rm -f "$tmp_churn"

  # ─── TEMPORAL COUPLING ────────────────────────────────────────────────
  echo ""
  echo "── Temporal Coupling (co-change ≥3, top 10) ──"
  git log --name-only --pretty='format:%H' 2>/dev/null \
    | grep -vE '\.(lock|wasm|dylib|so|dll)$' \
    | grep -vE '(node_modules|vendor/|dist/|target/|\.venv)' \
    | awk '
        /^[0-9a-f]{40}$/ {
          if (length(files) > 1) {
            n = 0
            for (f in files) arr[++n] = f
            for (i=1;i<=n;i++) for (j=i+1;j<=n;j++) pairs[arr[i] "|||" arr[j]]++
          }
          delete files; delete arr; next
        }
        /^$/ { next }
        { files[$0] = 1 }
        END { for (p in pairs) if (pairs[p]>=3) print pairs[p], p }
      ' | sort -rn | head -10 | while read -r n pair; do
      echo "  $n  ${pair/|||/  ↔  }"
    done

  # ─── COMMIT ACTIVITY ──────────────────────────────────────────────────
  echo ""
  echo "── Commit Activity ──"
  c30=$(git log --since='1 month ago' --oneline 2>/dev/null | wc -l | tr -d ' ')
  c90=$(git log --since='3 months ago' --oneline 2>/dev/null | wc -l | tr -d ' ')
  total=$(git log --oneline 2>/dev/null | wc -l | tr -d ' ')
  echo "  last 30d: $c30  /  last 90d: $c90  /  total: $total"
else
  echo "  (not a git repo — skipping git-based hot-spot analysis)"
fi

# ─── TEST COVERAGE SIGNALS ──────────────────────────────────────────────
echo ""
echo "── Test Signals ──"
find . -name "conftest.py" -not -path "*/.venv/*" 2>/dev/null | head -3 | sed 's/^/  /'
find . \( -name "jest.config.*" -o -name "vitest.config.*" \) -not -path "*/node_modules/*" 2>/dev/null | head -3 | sed 's/^/  /'
find . -type d -name "coverage" -not -path "*/node_modules/*" 2>/dev/null | head -3 | sed 's/^/  /'
find . -name "coverage.xml" -not -path "*/.venv/*" 2>/dev/null | head -3 | sed 's/^/  /'

# Test file count
py_test=$(find . \( -name "test_*.py" -o -name "*_test.py" \) -not -path "*/.venv/*" 2>/dev/null | wc -l | tr -d ' ')
js_test=$(find . \( -name "*.test.ts" -o -name "*.spec.ts" -o -name "*.test.js" -o -name "*.spec.js" \) -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
go_test=$(find . -name "*_test.go" -not -path "*/vendor/*" 2>/dev/null | wc -l | tr -d ' ')
rs_test=$(grep -rl "#\[cfg(test)\]" --include="*.rs" . 2>/dev/null | wc -l | tr -d ' ')
echo "  test files: py=$py_test  js=$js_test  go=$go_test  rs=$rs_test"

# ─── GIT REPO HEALTH ────────────────────────────────────────────────────
echo ""
echo "── Repo Health ──"
if [ -f .gitignore ]; then
  grep -q '\.env' .gitignore 2>/dev/null && echo "  .env ignored: YES" || echo "  .env ignored: NO (SECURITY RISK)"
else
  echo "  .gitignore: MISSING"
fi

# Tracked files that look sensitive
sensitive=$(git ls-files 2>/dev/null | grep -iE '\.env$|\.env\.|credentials|secrets|\.pem$|\.key$' | head -5)
[ -n "$sensitive" ] && echo "  tracked sensitive files:" && echo "$sensitive" | sed 's/^/    /'

# Binary / generated file check
bins=$(git ls-files 2>/dev/null | grep -cE '\.(wasm|so|dylib|exe|bin)$' || echo 0)
[ "$bins" -gt 0 ] && echo "  tracked binary-like files: $bins"

# ─── EXPORT VARS FOR THE SKILL ──────────────────────────────────────────
echo ""
echo "── Export ──"
echo "STACKS=\"$UNIQ_STACKS\""
echo "SIZE_TIER=$SIZE_TIER"
echo "TOTAL_LOC=$total_loc"
echo "JS_BUILD=$JS_BUILD"
echo "PY_BUILD=$PY_BUILD"
echo "MONOREPO=$MONOREPO"
echo "FRAMEWORKS=$FRAMEWORKS"

echo ""
echo "=== RECON DONE ==="
