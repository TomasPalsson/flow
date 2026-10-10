#!/usr/bin/env bash
# Checks for template.sh. Run: bash scripts/test_template.sh [template.sh]
# Stubs the GitHub CLI so no real secret is ever set.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="${1:-$HERE/../template.sh}"
FAILS=0
ok()   { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/gh"; chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# 1. syntax
if bash -n "$TEMPLATE"; then ok "bash -n passes"; else fail "bash -n"; fi

# 2. every stage sits inside run_wizard; the last line invokes it and exits
last=$(tail -n 1 "$TEMPLATE")
if [[ "$last" == 'run_wizard "$@"; exit' ]]; then ok 'last line is run_wizard "$@"; exit'; else fail "last line is: $last"; fi
if grep -q '^run_wizard() {' "$TEMPLATE"; then ok "run_wizard defined"; else fail "run_wizard not defined"; fi

# 3. a double-quoted .env value is read back and re-written single-quoted
printf 'STRIPE_PUBLISHABLE_KEY="pk_x"\n' > "$WORK/.env"
printf '\n\nsk_y\n' | ENV_FILE="$WORK/.env" bash "$TEMPLATE" >/dev/null 2>&1
if grep -qx "STRIPE_PUBLISHABLE_KEY='pk_x'" "$WORK/.env"; then
  ok "double-quoted .env value re-asked and kept"
else
  fail "double-quoted value: $(cat "$WORK/.env")"
fi

# 4. a bogus TERM on a real pty does not stop the wizard at the banner's _clear
if command -v script >/dev/null 2>&1; then
  # util-linux script takes -c; BSD/macOS script takes the command after the file.
  if script --version 2>/dev/null | grep -q util-linux; then
    out=$(cd "$WORK" && printf '\n\n' | ENV_FILE="$WORK/pty.env" script -qec "TERM=bogus bash \"$TEMPLATE\"" /dev/null 2>&1 || true)
  else
    out=$(cd "$WORK" && printf '\n\n' | ENV_FILE="$WORK/pty.env" TERM=bogus script -q /dev/null bash "$TEMPLATE" 2>&1 || true)
  fi
  case "$out" in
    *"Stage 1/1"*) ok "tput clear failure falls back (Stage 1/1 reached)" ;;
    *) fail "stopped at banner" ;;
  esac
else
  printf 'skip script(1) not installed\n'
fi

exit $((FAILS > 0))
