#!/usr/bin/env bash
# test_postinc_lint.sh — F25: run.sh fails any bash file under hooks/ or
# scripts/ that has `set -e` and a bare ((n++)). The post-increment of 0 is a
# false status, so the first increment kills a `set -e` script (upstream
# anthropics/claude-plugins-official validate-agent.sh does exactly this).
# The check itself is `postinc_hits <file>` in lib.sh.

_t_pi_file() {
	local d f
	d=$(tmp_dir)
	f="$d/x.sh"
	printf '%s\n' "$@" >"$f"
	printf '%s' "$f"
}

t_postinc_flags_post_increment_under_set_e() {
	local f
	f=$(_t_pi_file '#!/usr/bin/env bash' 'set -euo pipefail' 'n=0' '((n++))')
	assert_contains "$(postinc_hits "$f")" "((n++))" "t_postinc_flags_post_increment_under_set_e"
	assert_contains "$(postinc_hits "$f")" 'n=$((n+1))' "t_postinc_flags_post_increment_under_set_e names the fix"
	f=$(_t_pi_file '#!/usr/bin/env bash' 'set -e' 'n=0' 'if true; then (( error_count++ )); fi')
	assert_contains "$(postinc_hits "$f")" "error_count" "t_postinc_flags_post_increment_under_set_e spaced form"
	rm -rf "$(dirname "$f")"
}

t_postinc_ignores_files_without_set_e() {
	local f
	f=$(_t_pi_file '#!/usr/bin/env bash' 'set -u' 'n=0' '((n++))')
	assert_eq "$(postinc_hits "$f")" "" "t_postinc_ignores_files_without_set_e set -u only"
	rm -rf "$(dirname "$f")"
}

t_postinc_ignores_safe_forms_comments_and_marked_lines() {
	local f
	f=$(_t_pi_file '#!/usr/bin/env bash' 'set -e' 'n=0' 'n=$((n+1))' '((n+=1))' '# ((n++)) is the bug' '((n++)) || true # portable-ok')
	assert_eq "$(postinc_hits "$f")" "" "t_postinc_ignores_safe_forms_comments_and_marked_lines"
	rm -rf "$(dirname "$f")"
}

t_postinc_none_in_hooks_or_scripts() {
	local f hits=""
	for f in $(find "$SCAN_DIR" "$SCAN_DIR/../scripts" -type f \( -name '*.sh' -o ! -name '*.*' \) ! -path '*/fixtures/*' 2>/dev/null); do
		head -1 "$f" 2>/dev/null | grep -q 'bash' || continue
		hits="$hits$(postinc_hits "$f")"
	done
	assert_eq "$hits" "" "t_postinc_none_in_hooks_or_scripts"
}
