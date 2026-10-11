#!/usr/bin/env bash
# audit-coverage.sh — Phase 0 coverage ledger check for the /audit skill.
# Usage: audit-coverage.sh [plan.md] [repo_dir]
# Compares the dirs listed under "Scanned" and "Skipped" in plan.md with the
# top-level entries of `git ls-files`. Prints one line per problem and exits 1:
#   UNLISTED:<dir>        in the repo, in neither table
#   NO_REASON:<dir>       listed under Skipped with an empty reason cell
# Root-level files (no directory) are covered by a row named "." in either table.
# Exit 0 when the ledger covers the repo; 2 on a usage error.
set -uo pipefail

PLAN="${1:-.audit/plan.md}"
REPO="${2:-.}"

if [ ! -f "$PLAN" ]; then
  echo "audit-coverage: no plan file at $PLAN" >&2
  exit 2
fi
if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "audit-coverage: $REPO is not a git work tree" >&2
  exit 2
fi

# Rows of the Scanned/Skipped tables -> "<section>|<dir>|<second cell>"
rows=$(awk -F'|' '
  /^#+[ \t]*(Scanned|Skipped)/ { sec = ($0 ~ /Scanned/) ? "scanned" : "skipped"; next }
  /^[ \t]*([-*][ \t]+)?\**(Scanned|Skipped)\**:?\**[ \t]*$/ { sec = ($0 ~ /Scanned/) ? "scanned" : "skipped"; next }
  /^#+[ \t]/ { sec = ""; next }
  sec != "" && /^[ \t]*\|/ {
    d = $2; r = $3
    gsub(/^[ \t`]+|[ \t`]+$/, "", d)
    gsub(/^[ \t]+|[ \t]+$/, "", r)
    sub(/\/+$/, "", d)
    if (d == "" || d ~ /^-+$/ || tolower(d) ~ /^(dir|path|directory)$/) next
    print sec "|" d "|" r
  }' "$PLAN")

listed=$(printf '%s\n' "$rows" | cut -d'|' -f2)
status=0

# Top-level names; a bare file name means a root file, tracked as ".".
tops=$(git -C "$REPO" -c core.quotePath=false ls-files | awk -F/ 'NF > 1 { print $1; next } { print "." }' | LC_ALL=C sort -u)
while IFS= read -r top; do
  [ -n "$top" ] || continue
  if ! printf '%s\n' "$listed" | grep -qxF -- "$top"; then
    echo "UNLISTED:$top"
    status=1
  fi
done <<EOF
$tops
EOF

noreason=$(printf '%s\n' "$rows" | awk -F'|' '$1 == "skipped" && $3 == "" { print "NO_REASON:" $2 }')
if [ -n "$noreason" ]; then
  printf '%s\n' "$noreason"
  status=1
fi
exit "$status"
