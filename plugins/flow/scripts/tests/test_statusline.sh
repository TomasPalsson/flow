#!/usr/bin/env bash
# test_statusline.sh — flow statusline (spec 008-flow-statusline): the badge
# table's exhaustiveness against router.js's STATE_NO, the ✋/human_gate
# parity, zero writes under .specs/, the never-waits and single-refresh
# guarantees, and the render/install/print/doctor surface of `flow
# statusline`. T001 and T002 shipped the code; this file is the proof.
#
# Sourced by run.sh; every t_statusline_* function below is discovered and
# run. Self-contained: TEST_ONLY can restrict a run to this one file, so it
# must not depend on any other test_*.sh having been sourced first.
set -u

SL_PLUGIN=$(cd "$SCAN_DIR/.." && pwd -P)
SL_CLI="$SL_PLUGIN/bin/flow"
SL_LIB="$SL_PLUGIN/bin/lib/statusline.js"
SL_ROUTER="$SL_PLUGIN/bin/lib/router.js"
NODE_BIN=""
NODE_BIN=$(command -v node)

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# sl_realdir <dir> — the symlink-resolved absolute path, so a cache path
# this file computes and the one `flow statusline` computes from the same
# cwd agree (macOS' /tmp -> /private/tmp would otherwise disagree).
sl_realdir() {
	(cd "$1" 2>/dev/null && pwd -P)
}

# sl_bare_dir — a plain resolved tmp dir: no git, no .specs.
sl_bare_dir() {
	local d
	d=$(tmp_dir)
	sl_realdir "$d"
}

# sl_repo_with_feature <approved:0|1> — a resolved repo with one feature,
# 001-x, one open task, and an Approved: line only when asked for one.
sl_repo_with_feature() {
	local approved=$1 d base
	d=$(tmp_repo)
	d=$(sl_realdir "$d")
	base=$(cd "$d" && git rev-parse --short HEAD)
	mkdir -p "$d/.specs/001-x"
	printf '# Spec\n' >"$d/.specs/001-x/spec.md"
	printf '001-x\n' >"$d/.specs/.current"
	{
		printf '# Tasks — x\n'
		printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n' "$base"
		[ "$approved" = "1" ] && printf 'Approved: 2026-09-10 by user\n'
		printf '\n## Behaviors\n'
		printf '| ID | Given / When / Then | Task | Proven by |\n'
		printf '|----|---------------------|------|-----------|\n'
		printf '| B1 | given / when / then | T001 | t1 |\n'
		printf '\n## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 open task — files: a.py — verify: `true`\n'
	} >"$d/.specs/001-x/TASKS.md"
	(cd "$d" && git add -A && git commit -qm feature) >/dev/null 2>&1
	printf '%s' "$d"
}

# sl_write_cache <repo> <tmp> <ageMs> <resultJSON> — writes a cache entry
# directly, bypassing the router entirely. This is the render/cache boundary
# the whole file is testing (NAMES: entry, cachePath, readCache, writeCache).
sl_write_cache() {
	local repo=$1 tmp=$2 age=$3 result=$4
	TMPDIR="$tmp" "$NODE_BIN" -e '
		const s = require(process.argv[1]);
		const fs = require("fs");
		const path = require("path");
		const repo = process.argv[2];
		const age = parseInt(process.argv[3], 10);
		const result = JSON.parse(process.argv[4]);
		const p = s.cachePath(repo);
		fs.mkdirSync(path.dirname(p), { recursive: true });
		fs.writeFileSync(p, JSON.stringify({ result: result, at: Date.now() - age }));
	' "$SL_LIB" "$repo" "$age" "$result"
}

# sl_cache_rewrite_age <repo> <tmp> <ageMs> — keeps the stored result, moves
# only "at", so "one cache period passed" never needs a real sleep (§5's own
# "fixture clock" method).
sl_cache_rewrite_age() {
	local repo=$1 tmp=$2 age=$3
	TMPDIR="$tmp" "$NODE_BIN" -e '
		const s = require(process.argv[1]);
		const fs = require("fs");
		const repo = process.argv[2];
		const age = parseInt(process.argv[3], 10);
		const p = s.cachePath(repo);
		const e = JSON.parse(fs.readFileSync(p, "utf8"));
		e.at = Date.now() - age;
		fs.writeFileSync(p, JSON.stringify(e));
	' "$SL_LIB" "$repo" "$age"
}

# sl_cache_at <repo> <tmp> — echoes the cache entry's "at" in ms, or "" when
# there is no cache file yet.
sl_cache_at() {
	local repo=$1 tmp=$2
	TMPDIR="$tmp" "$NODE_BIN" -e '
		const s = require(process.argv[1]);
		const fs = require("fs");
		try {
			const e = JSON.parse(fs.readFileSync(s.cachePath(process.argv[2]), "utf8"));
			process.stdout.write(String(e.at));
		} catch {
			process.stdout.write("");
		}
	' "$SL_LIB" "$repo"
}

# sl_wait_cache_after <repo> <tmp> <sinceMs> <timeoutSec> — polls until the
# cache's "at" is newer than <sinceMs>, or the timeout elapses. Returns 1 on
# timeout.
sl_wait_cache_after() {
	local repo=$1 tmp=$2 since=$3 timeout=$4 i=0 at
	while [ "$i" -lt "$timeout" ]; do
		at=$(sl_cache_at "$repo" "$tmp")
		if [ -n "$at" ] && [ "$at" -gt "$since" ] 2>/dev/null; then
			return 0
		fi
		i=$((i + 1))
		sleep 1
	done
	return 1
}

# sl_tree_hash <dir> — a stable hash of every regular file's name and
# content under <dir> (FR-05: 50 renders must leave this byte-identical).
sl_tree_hash() {
	find "$1" -type f -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
		cksum "$f"
	done | cksum
}

# sl_char_len <string> — the JS string length (UTF-16 code units), the same
# metric flowSegment's own elision budget is computed in.
sl_char_len() {
	printf '%s' "$1" | "$NODE_BIN" -e 'process.stdout.write(String(require("fs").readFileSync(0, "utf8").length))'
}

# sl_has_escape <string> — "1" when <string> contains an ANSI escape, "0"
# otherwise.
sl_has_escape() {
	case "$1" in
	*$'\033'*) printf '1' ;;
	*) printf '0' ;;
	esac
}

# sl_render <cwd> <home> <tmp> <stdin> [argv...] — runs `flow statusline`,
# feeding <stdin> on fd 0. Sets RC/OUT/ERR.
sl_render() {
	local cwd=$1 home=$2 tmp=$3 stdin=$4
	shift 4
	run_cmd bash -c 'cwd=$1; home=$2; tmp=$3; stdin=$4; shift 4; cd "$cwd" || exit 1; export HOME="$home" TMPDIR="$tmp"; printf "%s" "$stdin" | "$@"' \
		_ "$cwd" "$home" "$tmp" "$stdin" "$NODE_BIN" "$SL_CLI" statusline "$@"
}

# sl_refresh <cwd> <home> <tmp> [scriptsDir] — runs `flow statusline
# --refresh` directly. Sets RC/OUT/ERR.
sl_refresh() {
	local cwd=$1 home=$2 tmp=$3 scripts=${4:-}
	run_cmd bash -c 'cwd=$1; home=$2; tmp=$3; scripts=$4; shift 4; cd "$cwd" || exit 1; export HOME="$home" TMPDIR="$tmp"; [ -n "$scripts" ] && export FLOW_SCRIPTS_DIR="$scripts"; exec "$@"' \
		_ "$cwd" "$home" "$tmp" "$scripts" "$NODE_BIN" "$SL_CLI" statusline --refresh
}

# ---------------------------------------------------------------------------
# B1 — FR-01, the model segment
# ---------------------------------------------------------------------------

t_statusline_model_segment() {
	local proj home tmp
	proj=$(sl_bare_dir)
	tmp=$(tmp_dir)
	home=$(tmp_dir)

	sl_render "$proj" "$home" "$tmp" '{"model":{"display_name":"Opus 5"},"rate_limits":{},"context_window":{"used_percentage":34}}'
	assert_rc 0 "the model segment renders exit 0"
	assert_eq "$OUT" "Opus 5 | ✨ MAX | 📊 ctx 34%" "FR-01: the exact model segment"

	sl_render "$proj" "$home" "$tmp" '{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":34}}'
	assert_eq "$OUT" "Opus 5 | ⚡ API | 📊 ctx 34%" "absent rate_limits renders the API badge"

	sl_render "$proj" "$home" "$tmp" '{"rate_limits":{},"context_window":{"used_percentage":34}}'
	assert_eq "$OUT" "✨ MAX | 📊 ctx 34%" "an absent model name drops just that field"

	sl_render "$proj" "$home" "$tmp" '{"model":{"display_name":"Opus 5"},"rate_limits":{}}'
	assert_eq "$OUT" "Opus 5 | ✨ MAX" "an absent context_window drops just that field"

	rm -rf "$proj" "$home" "$tmp"
}

# ---------------------------------------------------------------------------
# B2 — FR-02, all 21 state names, literally
# ---------------------------------------------------------------------------

t_statusline_all_states() {
	local proj tmp home state glyph label
	proj=$(sl_bare_dir)
	tmp=$(tmp_dir)
	home=$(tmp_dir)

	# §4.2, literal — the whole rendering contract for FR-02.
	while IFS='|' read -r state glyph label; do
		[ -z "$state" ] && continue
		sl_write_cache "$proj" "$tmp" 0 "$(printf '{"state":"%s","feature":{"slug":"008-x"}}' "$state")"
		sl_render "$proj" "$home" "$tmp" '{}'
		assert_rc 0 "$state renders exit 0"
		assert_contains "$OUT" "$glyph $label" "$state renders its §4.2 glyph and label"
		assert_contains "$OUT" "008-x" "$state renders the feature slug"
	done <<'STATES'
scan-failed|⚠|scan failed
blocked|⛔|blocked
disagreement|⛔|disagreement
looping|⛔|looping
invalid|⛔|invalid tasks
lying|⛔|unreachable done
loop-active|◍|loop running
no-project|○|no project
prep-interviewing|✎|prep
prep-ready|✎|prep ready
ambiguous|?|pick a feature
drafting|✎|drafting
unapproved|✋|approve
building|▸|building
checkpoint|✋|checkpoint
gating|⚙|gates
unverified|✋|verify
stale-pass|⚠|stale pass
shippable|⇧|ship
shipped|✓|shipped
idle|○|idle
STATES

	# the unknown-state fallback — a 22nd state renders "●" and its own name.
	sl_write_cache "$proj" "$tmp" 0 '{"state":"a-future-state","feature":{"slug":"008-x"}}'
	sl_render "$proj" "$home" "$tmp" '{}'
	assert_contains "$OUT" "● a-future-state" "an unknown state renders the ● fallback and its own name verbatim"

	rm -rf "$proj" "$home" "$tmp"
}

# t_statusline_badge_exhaustive — every STATE_NO key in router.js has a
# BADGES row, as a set comparison (T001's own verify checked this once in
# isolation; this re-proves it from inside the suite the launch criteria
# names as the full-coverage set).
t_statusline_badge_exhaustive() {
	local out badges states
	out=$("$NODE_BIN" -e '
		const s = require(process.argv[1]);
		const r = require(process.argv[2]);
		console.log(Object.keys(s.BADGES).sort().join(","));
		console.log(Object.keys(r.STATE_NO).sort().join(","));
	' "$SL_LIB" "$SL_ROUTER")
	badges=$(printf '%s\n' "$out" | sed -n '1p')
	states=$(printf '%s\n' "$out" | sed -n '2p')
	assert_eq "$badges" "$states" "BADGES' key set equals router.js's STATE_NO key set"
}

# ---------------------------------------------------------------------------
# B3 — FR-03, the running wave
# ---------------------------------------------------------------------------

t_statusline_wave() {
	local proj tmp home
	proj=$(sl_bare_dir)
	tmp=$(tmp_dir)
	home=$(tmp_dir)

	sl_write_cache "$proj" "$tmp" 0 '{"state":"building","feature":{"slug":"008-x"},"wave":{"ids":["T001"]}}'
	sl_render "$proj" "$home" "$tmp" '{}'
	assert_contains "$OUT" "▸ T001" "one running task id renders ▸ T001"

	sl_write_cache "$proj" "$tmp" 0 '{"state":"building","feature":{"slug":"008-x"},"wave":{"ids":["T003","T004"]}}'
	sl_render "$proj" "$home" "$tmp" '{}'
	assert_contains "$OUT" "▸ T003 +1" "two running task ids render ▸ T003 +1"

	rm -rf "$proj" "$home" "$tmp"
}

# ---------------------------------------------------------------------------
# B4 — FR-04, the ✋/human_gate parity, asserted as sets
# ---------------------------------------------------------------------------

t_statusline_human_gate_parity() {
	local out warn gate
	out=$("$NODE_BIN" -e '
		const fs = require("fs");
		const s = require(process.argv[1]);
		const src = fs.readFileSync(process.argv[2], "utf8");

		const warnHand = Object.keys(s.BADGES)
			.filter((k) => s.BADGES[k].glyph === "✋" && s.BADGES[k].tone === "warn")
			.sort();

		// every mk(\x27name\x27, ...) call in router.js, and whether its own
		// span (up to the next mk( call) sets human_gate: true.
		const re = /mk\(\x27([a-z-]+)\x27/g;
		const marks = [];
		let m;
		while ((m = re.exec(src))) marks.push({ name: m[1], idx: m.index });
		const gate = [];
		for (let i = 0; i < marks.length; i++) {
			const start = marks[i].idx;
			const end = i + 1 < marks.length ? marks[i + 1].idx : src.length;
			if (/human_gate:\s*true/.test(src.slice(start, end)) && gate.indexOf(marks[i].name) === -1) {
				gate.push(marks[i].name);
			}
		}
		console.log(warnHand.join(","));
		console.log(gate.sort().join(","));
	' "$SL_LIB" "$SL_ROUTER")
	warn=$(printf '%s\n' "$out" | sed -n '1p')
	gate=$(printf '%s\n' "$out" | sed -n '2p')
	assert_eq "$warn" "checkpoint,unapproved,unverified" "the ✋/warn badge set is exactly the three human gates"
	assert_eq "$warn" "$gate" "the ✋/warn set equals the set router.js's mk() calls mark human_gate: true, compared as sets"
}

# ---------------------------------------------------------------------------
# B5 — FR-05, a render never writes
# ---------------------------------------------------------------------------

t_statusline_never_writes() {
	local proj tmp home before after i failures nextcount_before nextcount_after
	proj=$(sl_repo_with_feature 1)
	tmp=$(tmp_dir)
	home=$(tmp_dir)
	printf '2 deadbeef\n' >"$proj/.specs/.next-call-count"
	nextcount_before=$(cat "$proj/.specs/.next-call-count")

	sl_refresh "$proj" "$home" "$tmp"
	assert_rc 0 "warming the cache once exits 0"

	before=$(sl_tree_hash "$proj/.specs")

	failures=0
	i=0
	while [ "$i" -lt 50 ]; do
		sl_render "$proj" "$home" "$tmp" '{}'
		[ "$RC" -eq 0 ] || failures=$((failures + 1))
		i=$((i + 1))
	done
	assert_eq "$failures" "0" "all 50 renders exit 0"

	after=$(sl_tree_hash "$proj/.specs")
	assert_eq "$after" "$before" "50 renders leave .specs/ byte-identical (FR-05)"

	nextcount_after=$(cat "$proj/.specs/.next-call-count")
	assert_eq "$nextcount_after" "$nextcount_before" ".next-call-count is untouched by 50 renders"

	rm -rf "$proj" "$home" "$tmp"
}

# ---------------------------------------------------------------------------
# B6 — FR-06, no flow project
# ---------------------------------------------------------------------------

t_statusline_no_project() {
	local proj tmp home
	proj=$(tmp_repo)
	tmp=$(tmp_dir)
	home=$(tmp_dir)

	sl_render "$proj" "$home" "$tmp" '{"model":{"display_name":"Test"},"context_window":{"used_percentage":10}}'
	assert_rc 0 "a repo with no .specs/ still exits 0"
	assert_eq "$OUT" "Test | ⚡ API | 📊 ctx 10%" "only the model segment is printed"
	assert_not_contains "$OUT" "🌊" "no flow segment, no placeholder, when there is no .specs/"

	rm -rf "$proj" "$home" "$tmp"
}

# ---------------------------------------------------------------------------
# B7 — FR-07, four fault injections, each exit 0
# ---------------------------------------------------------------------------

t_statusline_never_fails() {
	local proj tmp home stubpath

	# (1) malformed stdin
	proj=$(tmp_repo)
	tmp=$(tmp_dir)
	home=$(tmp_dir)
	sl_render "$proj" "$home" "$tmp" 'this is not json {{{'
	assert_rc 0 "malformed stdin still exits 0"
	assert_contains "$OUT" "API" "malformed stdin still prints a model segment"
	rm -rf "$proj" "$tmp" "$home"

	# (2) missing binary — git absent from PATH, so the toplevel lookup fails
	proj=$(tmp_repo)
	tmp=$(tmp_dir)
	home=$(tmp_dir)
	run_cmd bash -c 'cwd=$1; home=$2; tmp=$3; shift 3; cd "$cwd" || exit 1; export HOME="$home" TMPDIR="$tmp" PATH="/flow-test-no-such-dir"; printf "{}" | "$@"' \
		_ "$proj" "$home" "$tmp" "$NODE_BIN" "$SL_CLI" statusline
	assert_rc 0 "git missing from PATH still exits 0"
	assert_contains "$OUT" "API" "a missing git binary still prints a model segment"
	rm -rf "$proj" "$tmp" "$home"

	# (3) unreadable .specs
	proj=$(tmp_repo)
	tmp=$(tmp_dir)
	home=$(tmp_dir)
	mkdir -p "$proj/.specs"
	chmod 000 "$proj/.specs"
	sl_render "$proj" "$home" "$tmp" '{}'
	assert_rc 0 "an unreadable .specs/ still exits 0"
	chmod 755 "$proj/.specs"
	rm -rf "$proj" "$tmp" "$home"

	# (4) router throw — flow-lint unresolved beneath a repo that has a
	# feature to lint; computeNext's own throw must not escape --refresh, and
	# the render layer (which never even calls the router) is unaffected.
	stubpath=$(tmp_dir) # deliberately kept empty: no flow-lint inside it
	proj=$(sl_repo_with_feature 0)
	tmp=$(tmp_dir)
	home=$(tmp_dir)
	sl_refresh "$proj" "$home" "$tmp" "$stubpath"
	assert_rc 0 "a router that cannot even find flow-lint still leaves --refresh at exit 0"
	sl_render "$proj" "$home" "$tmp" '{}'
	assert_rc 0 "the render layer is unaffected either way"
	rm -rf "$proj" "$tmp" "$home" "$stubpath"
}

# ---------------------------------------------------------------------------
# B8/B9 — FR-08, the three install paths of Journey 3
# ---------------------------------------------------------------------------

t_statusline_install() {
	local home settings backup
	home=$(tmp_dir)
	mkdir -p "$home/.claude"
	settings="$home/.claude/settings.json"
	printf '{\n  "foo": "bar"\n}\n' >"$settings"

	run_cmd bash -c 'home=$1; shift; export HOME="$home"; "$@"' \
		_ "$home" "$NODE_BIN" "$SL_CLI" statusline --install
	assert_rc 0 "flow statusline --install exits 0 against a settings.json with no statusLine"
	assert_contains "$OUT" "installed into" "the install receipt names the file"
	assert_contains "$OUT" "backup:" "and prints the backup path"

	assert_contains "$(cat "$settings")" '"command": "flow statusline"' "statusLine is merged in"
	assert_contains "$(cat "$settings")" '"foo": "bar"' "every other key is untouched"

	backup=$(find "$home/.claude" -name 'settings.json.pre-flow-statusline.*' -print 2>/dev/null | head -1)
	assert_file_exists "$backup" "the prior file was copied aside first"

	rm -rf "$home"
}

t_statusline_install_refuses() {
	local home settings before

	home=$(tmp_dir)
	mkdir -p "$home/.claude"
	settings="$home/.claude/settings.json"
	printf '{ not json' >"$settings"
	before=$(cat "$settings")
	run_cmd bash -c 'home=$1; shift; export HOME="$home"; "$@"' \
		_ "$home" "$NODE_BIN" "$SL_CLI" statusline --install
	assert_rc 1 "a settings.json that does not parse exits 1"
	assert_contains "$ERR" "does not parse" "the parse error is named"
	assert_contains "$OUT" "flow statusline" "the snippet to paste by hand is printed"
	assert_eq "$(cat "$settings")" "$before" "nothing is written when the file does not parse"
	rm -rf "$home"

	home=$(tmp_dir)
	mkdir -p "$home/.claude"
	settings="$home/.claude/settings.json"
	printf '{"statusLine": {"type": "command", "command": "some-other-cmd"}}' >"$settings"
	before=$(cat "$settings")
	run_cmd bash -c 'home=$1; shift; export HOME="$home"; "$@"' \
		_ "$home" "$NODE_BIN" "$SL_CLI" statusline --install
	assert_rc 1 "an existing statusLine refuses without --force"
	assert_contains "$ERR" "some-other-cmd" "the existing command is quoted back"
	assert_contains "$ERR" "--force" "and --force is named as the way to replace it"
	assert_eq "$(cat "$settings")" "$before" "nothing is written on the refusal"

	run_cmd bash -c 'home=$1; shift; export HOME="$home"; "$@"' \
		_ "$home" "$NODE_BIN" "$SL_CLI" statusline --install --force
	assert_rc 0 "--force replaces an existing statusLine"
	assert_contains "$(cat "$settings")" '"command": "flow statusline"' "the key is replaced"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# B10 — FR-09, --print writes nothing
# ---------------------------------------------------------------------------

t_statusline_print() {
	local home before after
	home=$(tmp_dir)
	mkdir -p "$home/.claude"
	printf '{"foo": "bar"}\n' >"$home/.claude/settings.json"
	before=$(sl_tree_hash "$home")

	run_cmd bash -c 'home=$1; shift; export HOME="$home"; "$@"' \
		_ "$home" "$NODE_BIN" "$SL_CLI" statusline --print
	assert_rc 0 "flow statusline --print exits 0"
	assert_contains "$OUT" '"type": "command"' "the snippet is valid JSON — type"
	assert_contains "$OUT" '"command": "flow statusline"' "the snippet is valid JSON — command"

	after=$(sl_tree_hash "$home")
	assert_eq "$after" "$before" "--print writes nothing under HOME"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# B11 — FR-10, the doctor check
# ---------------------------------------------------------------------------

t_statusline_doctor() {
	local home status
	home=$(tmp_dir)
	mkdir -p "$home/.claude"
	printf '{"statusLine": {"type": "command", "command": "flow-statusline-does-not-resolve-xyz"}}' >"$home/.claude/settings.json"

	run_cmd bash -c 'home=$1; shift; export HOME="$home"; "$@"' \
		_ "$home" "$NODE_BIN" "$SL_CLI" doctor --json
	# flow doctor's own exit code is 1 whenever ANY check fails (by design —
	# this fixture deliberately makes the statusline check fail); the check
	# under test here is that the statusline check itself is FAIL, not PASS.
	assert_rc 1 "flow doctor reports overall failure when the statusline check fails"

	status=$(printf '%s' "$OUT" | "$NODE_BIN" -e '
		const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
		const c = d.checks.find((x) => x.id === "statusline");
		console.log(c ? c.status : "MISSING");
	')
	assert_eq "$status" "FAIL" "the statusline doctor check is FAIL when the configured command cannot resolve"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# B12 — FR-11, --no-color / NO_COLOR=1
# ---------------------------------------------------------------------------

t_statusline_no_color() {
	local proj tmp home
	proj=$(sl_bare_dir)
	tmp=$(tmp_dir)
	home=$(tmp_dir)
	sl_write_cache "$proj" "$tmp" 0 '{"state":"unapproved","feature":{"slug":"008-x"}}'

	sl_render "$proj" "$home" "$tmp" '{}'
	assert_eq "$(sl_has_escape "$OUT")" "1" "colour is on by default (baseline for the two checks below)"

	sl_render "$proj" "$home" "$tmp" '{}' --no-color
	assert_eq "$(sl_has_escape "$OUT")" "0" "--no-color renders no escape sequence (FR-11)"

	run_cmd bash -c 'cwd=$1; home=$2; tmp=$3; shift 3; cd "$cwd" || exit 1; export HOME="$home" TMPDIR="$tmp" NO_COLOR=1; printf "{}" | "$@"' \
		_ "$proj" "$home" "$tmp" "$NODE_BIN" "$SL_CLI" statusline
	assert_eq "$(sl_has_escape "$OUT")" "0" "NO_COLOR=1 renders no escape sequence (FR-11)"

	rm -rf "$proj" "$tmp" "$home"
}

# ---------------------------------------------------------------------------
# B13 — FR-12, elision never drops the badge
# ---------------------------------------------------------------------------

t_statusline_elide() {
	local proj tmp home flow len ok
	proj=$(sl_bare_dir)
	tmp=$(tmp_dir)
	home=$(tmp_dir)
	sl_write_cache "$proj" "$tmp" 0 '{"state":"building","feature":{"slug":"002-cross-worktree-spec-numbers-zellij-pane"}}'

	sl_render "$proj" "$home" "$tmp" '{}' --no-color
	assert_rc 0 "a long slug still renders"

	flow=${OUT#*🌊 }
	len=$(sl_char_len "$flow")
	if [ "$len" -le 40 ]; then ok=1; else ok=0; fi
	assert_eq "$ok" "1" "FR-12: the flow segment is <= 40 characters ($len)"

	case "$flow" in
	*"▸ building") ok=1 ;;
	*) ok=0 ;;
	esac
	assert_eq "$ok" "1" "the state badge is never dropped, even when the slug is elided"

	rm -rf "$proj" "$tmp" "$home"
}

# ---------------------------------------------------------------------------
# B14 — FR-13, a render never waits
# ---------------------------------------------------------------------------

# t_statusline_never_waits — with the router stubbed to sleep 10 s, a render
# still returns well inside the §5 budget. Node measures elapsed wall time
# itself, since bash's `date` has no portable sub-second resolution.
t_statusline_never_waits() {
	local proj tmp home stubdir binpath measured rc ms out fast
	proj=$(sl_repo_with_feature 0)
	tmp=$(tmp_dir)
	home=$(tmp_dir)
	stubdir=$(tmp_dir)
	binpath=$(tmp_dir)

	# a flow-lint that sleeps 10s beneath this repo's own feature
	{
		printf 'sleep 10\n'
		printf 'printf "%%s\\n" "{\\"header\\":{\\"approved\\":false},\\"tasks\\":[],\\"waves\\":[]}"\n'
	} >"$stubdir/flow-lint"
	# a `flow` on PATH that sleeps 10s — per the brief's own hostile fixture:
	# any accidental PATH-based shell-out to `flow` cannot pass this test either.
	{
		printf '#!/bin/sh\n'
		printf 'sleep 10\n'
	} >"$binpath/flow"
	chmod +x "$binpath/flow"

	measured=$("$NODE_BIN" -e '
		const { spawnSync } = require("child_process");
		const cwd = process.argv[1];
		const home = process.argv[2];
		const tmp = process.argv[3];
		const scripts = process.argv[4];
		const pathPrefix = process.argv[5];
		const cli = process.argv[6];
		const env = Object.assign({}, process.env, {
			HOME: home,
			TMPDIR: tmp,
			FLOW_SCRIPTS_DIR: scripts,
			PATH: pathPrefix + require("path").delimiter + (process.env.PATH || ""),
		});
		const t0 = Date.now();
		const r = spawnSync(process.execPath, [cli, "statusline"], { cwd, env, input: "{}", encoding: "utf8", timeout: 20000 });
		const ms = Date.now() - t0;
		console.log(JSON.stringify({ rc: r.status, ms: ms, out: (r.stdout || "").trim() }));
	' "$proj" "$home" "$tmp" "$stubdir" "$binpath" "$SL_CLI")

	rc=$(printf '%s' "$measured" | "$NODE_BIN" -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0,"utf8")).rc))')
	ms=$(printf '%s' "$measured" | "$NODE_BIN" -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0,"utf8")).ms))')
	out=$(printf '%s' "$measured" | "$NODE_BIN" -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0,"utf8")).out))')

	assert_eq "$rc" "0" "a render exits 0 even with the router stubbed to sleep 10s"
	assert_contains "$out" "API" "and still prints a usable line"
	# 1000ms, not 5000: at 5000 this would still pass if the render had waited
	# 4.9s of the 10s stub, which is the exact failure it exists to catch.
	# Observed here is ~48ms, so this leaves 20x of headroom for a loaded CI box.
	if [ "$ms" -lt 1000 ]; then fast=1; else fast=0; fi
	assert_eq "$fast" "1" "the render returned in ${ms}ms, nowhere near the 10s stub (§5 budget, FR-13)"

	rm -rf "$proj" "$tmp" "$home" "$stubdir" "$binpath"
}

# ---------------------------------------------------------------------------
# B15 — FR-14, the badge catches up within one cache period
# ---------------------------------------------------------------------------

t_statusline_refreshes() {
	local proj tmp home t1 waited
	proj=$(sl_repo_with_feature 0)
	tmp=$(tmp_dir)
	home=$(tmp_dir)

	# render #1: cold cache — a refresh is spawned in the background
	sl_render "$proj" "$home" "$tmp" '{}'
	assert_rc 0 "a cold-cache render still exits 0"

	sl_wait_cache_after "$proj" "$tmp" 0 15
	waited=$?
	assert_eq "$waited" "0" "the detached refresh populates the cache"

	sl_render "$proj" "$home" "$tmp" '{}'
	assert_contains "$OUT" "✋ approve" "the first real state is visible: unapproved"

	# change the state on disk — approve the feature
	printf 'Approved: 2026-09-10 by user\n' >>"$proj/.specs/001-x/TASKS.md"

	# the cache is still fresh — the badge has NOT changed yet
	sl_render "$proj" "$home" "$tmp" '{}'
	assert_contains "$OUT" "✋ approve" "within the same cache period, the old badge is still shown"

	# age the cache past one period without a real sleep (§5's own fixture-clock method)
	t1=$(sl_cache_at "$proj" "$tmp")
	sl_cache_rewrite_age "$proj" "$tmp" 6000

	sl_render "$proj" "$home" "$tmp" '{}'
	assert_contains "$OUT" "✋ approve" "the render that trips the refresh still shows the OLD cache, not a wait"

	sl_wait_cache_after "$proj" "$tmp" "$t1" 15
	waited=$?
	assert_eq "$waited" "0" "the refresh writes a new cache entry"

	sl_render "$proj" "$home" "$tmp" '{}'
	assert_contains "$OUT" "▸" "the badge is current within one cache period, with no command typed (FR-14)"
	assert_not_contains "$OUT" "✋ approve" "and the old badge is gone"

	rm -rf "$proj" "$tmp" "$home"
}

# ---------------------------------------------------------------------------
# B16 — FR-15, one live refresh at a time
# ---------------------------------------------------------------------------

# t_statusline_one_refresh — ten renders against a cold cache produce at
# most one live refresh child, proven by counting how many times a
# deliberately slow flow-lint actually ran, not by inspecting timing.
t_statusline_one_refresh() {
	local proj tmp home scriptsdir counter i hits
	proj=$(sl_repo_with_feature 0)
	tmp=$(tmp_dir)
	home=$(tmp_dir)
	scriptsdir=$(tmp_dir)
	counter="$scriptsdir/hits"
	: >"$counter"

	{
		printf 'printf "x\\n" >> "%s"\n' "$counter"
		printf 'sleep 3\n'
		printf 'printf "%%s\\n" "{\\"header\\":{\\"approved\\":false},\\"tasks\\":[],\\"waves\\":[]}"\n'
	} >"$scriptsdir/flow-lint"

	i=0
	while [ "$i" -lt 10 ]; do
		(
			cd "$proj" || exit 1
			HOME="$home" TMPDIR="$tmp" FLOW_SCRIPTS_DIR="$scriptsdir" "$NODE_BIN" "$SL_CLI" statusline --refresh >/dev/null 2>&1
		) &
		i=$((i + 1))
	done
	wait

	hits=$(wc -l <"$counter" | tr -d ' ')
	assert_eq "$hits" "1" "ten renders fired back to back against a cold cache produce exactly one live refresh child (FR-15)"

	rm -rf "$proj" "$tmp" "$home" "$scriptsdir"
}

# ---------------------------------------------------------------------------
# B17 — FR-16, the staleness marker
# ---------------------------------------------------------------------------

# t_statusline_stale_marker — §5: asserted at 4s, 6s and 61s of age; only
# past the 60s bound does the trailing ~ appear.
t_statusline_stale_marker() {
	local proj tmp home
	proj=$(sl_bare_dir)
	tmp=$(tmp_dir)
	home=$(tmp_dir)

	# --no-color: withTone wraps the badge text alone, so a coloured render
	# has a reset code between "idle" and "~" — --no-color keeps this a
	# single contiguous substring to assert on.
	sl_write_cache "$proj" "$tmp" 4000 '{"state":"idle","feature":{"slug":"008-x"}}'
	sl_render "$proj" "$home" "$tmp" '{}' --no-color
	assert_not_contains "$OUT" "○ idle~" "a 4s-old cache carries no stale marker"

	sl_write_cache "$proj" "$tmp" 6000 '{"state":"idle","feature":{"slug":"008-x"}}'
	sl_render "$proj" "$home" "$tmp" '{}' --no-color
	assert_not_contains "$OUT" "○ idle~" "a 6s-old cache — stale enough to trigger a refresh, not stale enough to mark — carries no ~"

	sl_write_cache "$proj" "$tmp" 61000 '{"state":"idle","feature":{"slug":"008-x"}}'
	sl_render "$proj" "$home" "$tmp" '{}' --no-color
	assert_contains "$OUT" "○ idle~" "a 61s-old cache carries the trailing ~ (FR-16)"

	rm -rf "$proj" "$tmp" "$home"
}
