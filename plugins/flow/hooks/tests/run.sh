#!/usr/bin/env bash
# tests/run.sh — runs every t_* function from every test_*.sh beside it, then
# two static checks over the parent directory's bash files:
#   1. portability grep (bash 3.2 / BSD coreutils safe), lines marked
#      "portable-ok" are exempt (use it only for guarded fallbacks);
#   2. shellcheck -S warning, when shellcheck is installed.
# Prints "N passed, M failed"; exit 1 when M > 0.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
SCAN_DIR=$(cd "$HERE/.." && pwd -P)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

for f in "$HERE"/test_*.sh; do
	[ -e "$f" ] || continue
	# TEST_ONLY=test_x.sh restricts the run to one test file (static checks still cover the whole dir)
	if [ -n "${TEST_ONLY:-}" ] && [ "$(basename "$f")" != "$TEST_ONLY" ]; then continue; fi
	# shellcheck disable=SC1090
	. "$f"
done

for fn in $(declare -F | awk '{print $3}' | grep '^t_' | sort); do
	printf '%s\n' "$fn"
	"$fn"
done

# ---------- static checks ----------
bash_files() {
	find "$SCAN_DIR" -type f \( -name '*.sh' -o ! -name '*.*' \) \
		! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/fixtures/*' 2>/dev/null |
		while IFS= read -r f; do
			if head -1 "$f" 2>/dev/null | grep -q 'bash'; then printf '%s\n' "$f"; fi
		done
}

BANNED='mapfile|readarray|declare -A|\$\{[A-Za-z_]+,,|\$\{[A-Za-z_]+\^\^|readlink -f|stat -c|stat -f|sed -i |grep -P|date -d|date -v|(^|[^A-Za-z_-])timeout |realpath|xargs -r|mktemp -p|mktemp --tmpdir|sed -r' # portable-ok
printf 'portability\n'
port_bad=0
for f in $(bash_files); do
	hits=$(grep -nE "$BANNED" "$f" | grep -v 'portable-ok' | grep -vE '^[0-9]+:[[:space:]]*#' || true)
	if [ -n "$hits" ]; then
		port_bad=1
		_fail "portable: ${f#"$SCAN_DIR"/}" "$(printf '%s' "$hits" | head -3 | tr '\n' ' ')"
	fi
done
[ "$port_bad" -eq 0 ] && _pass "no non-portable constructs under ${SCAN_DIR##*/}/"

printf 'shellcheck\n'
if command -v shellcheck >/dev/null 2>&1; then
	for f in $(bash_files); do
		if out=$(shellcheck -S warning "$f" 2>&1); then
			_pass "shellcheck: ${f#"$SCAN_DIR"/}"
		else
			_fail "shellcheck: ${f#"$SCAN_DIR"/}" "$(printf '%s' "$out" | grep -E '^In |SC[0-9]+' | head -3 | tr '\n' ' ')"
		fi
	done
else
	printf '  skip shellcheck not installed\n'
fi

summary
