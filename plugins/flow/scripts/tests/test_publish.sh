#!/usr/bin/env bash
# test_publish.sh — `flow publish` dedupes on a feature-scoped marker in the
# issue body, never on the title or the bare task id, and accepts task ids of
# any width (T1000). gh is a stub on PATH; nothing touches the network.
set -u

PB_CLI="$(cd "$SCAN_DIR/.." && pwd -P)/bin/flow"

# pb_stub <dir> — a gh stub: `issue list` prints $GH_LIST (a JSON file) and
# `issue create` appends its --title and --body to $GH_LOG.
pb_stub() {
	local dir=$1
	mkdir -p "$dir"
	cat >"$dir/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "issue" ] && [ "$2" = "list" ]; then
	cat "$GH_LIST"
	exit 0
fi
if [ "$1" = "issue" ] && [ "$2" = "create" ]; then
	shift 2
	while [ $# -gt 0 ]; do
		case "$1" in
		--title) printf 'TITLE %s\n' "$2" >>"$GH_LOG"; shift 2 ;;
		--body) printf 'BODY %s\n' "$2" >>"$GH_LOG"; shift 2 ;;
		*) shift ;;
		esac
	done
	exit 0
fi
exit 1
STUB
	chmod +x "$dir/gh"
}

# pb_repo <slug> <tasks-lines...> — a repo whose active feature has TASKS.md.
pb_repo() {
	local slug=$1 d
	shift
	d=$(tmp_repo)
	mkdir -p "$d/.specs/$slug"
	printf '# Spec\n' >"$d/.specs/$slug/spec.md"
	printf '%s\n' "$slug" >"$d/.specs/.current"
	{
		printf '# Tasks\n\n'
		printf '%s\n' "$@"
	} >"$d/.specs/$slug/TASKS.md"
	printf '%s' "$d"
}

# pb_publish <repo> <listfile> <logfile> — runs publish with the stub first on PATH.
pb_publish() {
	local repo=$1 list=$2 log=$3 stubdir
	stubdir=$(dirname "$list")/bin
	pb_stub "$stubdir"
	: >"$log"
	run_cmd bash -c 'cd "$1" || exit 1; export PATH="$2:$PATH" GH_LIST="$3" GH_LOG="$4"; node "$5" publish' \
		_ "$repo" "$stubdir" "$list" "$log" "$PB_CLI"
}

t_publish_retitled_task_not_duplicated() {
	local repo work list log
	repo=$(pb_repo 001-alpha '- [ ] T001 Renamed title after the fact')
	work=$(tmp_dir)
	list="$work/list.json"
	log="$work/log"
	printf '%s' '[{"title":"T001 Old title","body":"flow:001-alpha/T001\nFrom the tasks file."}]' >"$list"
	pb_publish "$repo" "$list" "$log"
	assert_rc 0 "publish exits 0"
	assert_eq "$(cat "$log")" "" "a retitled task creates no new issue"
	rm -rf "$repo" "$work"
}

t_publish_wide_task_id() {
	local repo work list log
	repo=$(pb_repo 001-alpha '- [ ] T1000 The thousandth task')
	work=$(tmp_dir)
	list="$work/list.json"
	log="$work/log"
	printf '[]' >"$list"
	pb_publish "$repo" "$list" "$log"
	assert_rc 0 "publish exits 0"
	assert_contains "$(cat "$log")" "TITLE T1000 The thousandth task" "T1000 is created"
	assert_contains "$(cat "$log")" "flow:001-alpha/T1000" "the body carries the marker"
	rm -rf "$repo" "$work"
}

t_publish_same_id_other_feature() {
	local repo work list log
	repo=$(pb_repo 002-beta '- [ ] T001 First task of beta')
	work=$(tmp_dir)
	list="$work/list.json"
	log="$work/log"
	printf '%s' '[{"title":"T001 First task of alpha","body":"flow:001-alpha/T001"}]' >"$list"
	pb_publish "$repo" "$list" "$log"
	assert_rc 0 "publish exits 0"
	assert_contains "$(cat "$log")" "TITLE T001 First task of beta" "T001 of feature 2 is created though feature 1 has a T001"
	rm -rf "$repo" "$work"
}

t_publish_marker_prefix_not_a_match() {
	local repo work list log
	repo=$(pb_repo 001-alpha '- [ ] T001 Short id')
	work=$(tmp_dir)
	list="$work/list.json"
	log="$work/log"
	printf '%s' '[{"title":"T0010 Longer id","body":"flow:001-alpha/T0010"}]' >"$list"
	pb_publish "$repo" "$list" "$log"
	assert_contains "$(cat "$log")" "TITLE T001 Short id" "T001 is not mistaken for T0010"
	rm -rf "$repo" "$work"
}

t_publish_legacy_issue_still_dedupes() {
	local repo work list log
	repo=$(pb_repo 001-alpha '- [ ] T001 Same title')
	work=$(tmp_dir)
	list="$work/list.json"
	log="$work/log"
	printf '%s' '[{"title":"T001 Same title","body":"From `.specs/001-alpha/TASKS.md`. The build does not read this issue."}]' >"$list"
	pb_publish "$repo" "$list" "$log"
	assert_rc 0 "publish exits 0"
	assert_eq "$(cat "$log")" "" "an issue made before markers existed is still recognised"
	rm -rf "$repo" "$work"
}
