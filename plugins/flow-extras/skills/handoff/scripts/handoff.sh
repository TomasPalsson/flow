#!/usr/bin/env bash
# handoff.sh - write a redacted handoff file and launch a background agent from it.
#   redact                 stdin -> stdout with secrets and PII masked
#   write <slug>           stdin -> ${TMPDIR:-/tmp}/handoff-<slug>.md (redacted, mode 600); prints the path
#   command <name> <file>  prints the launch command, runs nothing
#   launch <name> <file>   runs it; the summary is passed as one quoted argument
# HANDOFF_CLAUDE overrides the claude binary (used by the tests).
# bash 3.2 / BSD portable.
set -eu

redact() {
	awk '
		/-----BEGIN [A-Z ]*PRIVATE KEY-----/ { if (!skip) print "[REDACTED]"; skip = 1 }
		!skip { print }
		/-----END [A-Z ]*PRIVATE KEY-----/ { skip = 0 }
	' | sed -E \
		-e 's|(://)[^/@?#[:space:]]+@|\1[REDACTED]@|g' \
		-e 's/([?\&;])([Tt]oken|[Aa]ccess_[Tt]oken|[Ss]ig|[Ss]ignature|[Kk]ey|[Aa]pi_?[Kk]ey|[Xx]-[Aa]mz-[A-Za-z0-9-]+|[Xx]-[Gg]oog-[A-Za-z0-9-]+)=[^\&[:space:]#"'"'"')>]*/\1\2=[REDACTED]/g' \
		-e 's/[sr]k_(live|test)_[A-Za-z0-9]{8,}/[REDACTED]/g' \
		-e 's/(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{8,}/\1[REDACTED]/g' \
		-e 's/(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{16,}/[REDACTED]/g' \
		-e 's/github_pat_[A-Za-z0-9_]{16,}/[REDACTED]/g' \
		-e 's/xox[abprs]-[A-Za-z0-9-]{8,}/[REDACTED]/g' \
		-e 's/(AKIA|ASIA)[0-9A-Z]{16}/[REDACTED]/g' \
		-e 's/AIza[0-9A-Za-z_-]{30,}/[REDACTED]/g' \
		-e 's/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*/[REDACTED]/g' \
		-e 's/([Bb][Ee][Aa][Rr][Ee][Rr]|[Bb][Aa][Ss][Ii][Cc]) +[A-Za-z0-9._~+\/=-]{8,}/\1 [REDACTED]/g' \
		-e 's/([A-Za-z0-9_-]*([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww]([Oo][Rr])?[Dd]|_[Kk][Ee][Yy])["'"'"']? *[:=] *)["'"'"']?[^[:space:]"'"'"',;]+/\1[REDACTED]/g' \
		-e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED-EMAIL]/g'
}

slug_of() {
	printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//'
}

# warn_unverified <file>: stderr note when an "Open." step marked (assumed),
# (code read) or a non-zero (run) sits outside the "Verify first:" group.
# Silent on a well-formed draft.
warn_unverified() {
	awk '
		/^Verify first:[[:space:]]*$/ { inverify = 1; next }
		/^[A-Za-z][A-Za-z ]*:[[:space:]]*$/ { inverify = 0 }
		/Open\./ && (/\(assumed\)/ || /\(code read\)/ || /\(run\) exit [1-9]/) && !inverify { n++ }
		END { if (n) printf "handoff: %d step(s) marked (assumed), (code read) or failed (run) are not under \"Verify first:\"; move them there\n", n > "/dev/stderr" }
	' "$1"
}

case "${1:-}" in
redact)
	redact
	;;
write)
	slug=$(slug_of "${2:-}")
	[ -n "$slug" ] || { echo "handoff: write needs a slug" >&2; exit 2; }
	dir="${TMPDIR:-/tmp}"
	file="${dir%/}/handoff-$slug.md"
	umask 077
	rm -f "$file"
	redact >"$file"
	warn_unverified "$file"
	printf '%s\n' "$file"
	;;
command | launch)
	name="${2:-}"
	file="${3:-}"
	[ -n "$name" ] && [ -f "$file" ] || { echo "handoff: $1 needs <name> <existing file>" >&2; exit 2; }
	case "$name" in
	*[\"\$\`\\]*) echo "handoff: name must not contain quotes, \$, backticks or backslashes" >&2; exit 2 ;;
	esac
	if [ "$1" = command ]; then
		printf 'claude --bg -n "%s" -- "$(cat %s)"\n' "$name" "$file"
	else
		command -v "${HANDOFF_CLAUDE:-claude}" >/dev/null 2>&1 || { echo "handoff: claude not on PATH; file is at $file" >&2; exit 0; }
		"${HANDOFF_CLAUDE:-claude}" --bg -n "$name" -- "$(cat "$file")"
	fi
	;;
*)
	echo "usage: handoff.sh redact | write <slug> | command <name> <file> | launch <name> <file>" >&2
	exit 2
	;;
esac
