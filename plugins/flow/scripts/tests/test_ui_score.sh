#!/usr/bin/env bash
# test_ui_score.sh — plugins/flow/scripts/ui-score: capture/score a page
# against a real localhost page via agent-browser + Chrome. Needs both, so
# every t_* here skips cleanly (house SKIP convention, see t_mkt_claude_*
# in test_marketplace.sh) when agent-browser is not on PATH.
# Sourced by run.sh; HERE and SCAN_DIR are set.

UIS_BIN="$SCAN_DIR/ui-score"
UIS_HAS_AB=1
command -v agent-browser >/dev/null 2>&1 || UIS_HAS_AB=0

# _uis_need_ab <test-name> — print+skip (no PASS/FAIL either way) and tell the
# caller to bail out, or say nothing and let the caller proceed.
_uis_need_ab() {
	if [ "$UIS_HAS_AB" -eq 0 ]; then
		printf '  skip %s (agent-browser not installed)\n' "$1"
		return 1
	fi
	return 0
}

UIS_PID=""
UIS_PORT=""

# _uis_serve <dir> — python3's http.server on an ephemeral 127.0.0.1 port,
# sets $UIS_PORT once it is actually listening.
_uis_serve() {
	local dir=$1 log tries
	log=$(mktemp "${TMPDIR:-/tmp}/flow-uis-log.XXXXXX")
	python3 -u -m http.server -d "$dir" -b 127.0.0.1 0 >"$log" 2>&1 &
	UIS_PID=$!
	UIS_PORT=""
	tries=0
	while [ "$tries" -lt 50 ]; do
		UIS_PORT=$(grep -o 'port [0-9]*' "$log" 2>/dev/null | head -1 | awk '{print $2}')
		[ -n "$UIS_PORT" ] && break
		sleep 0.1
		tries=$((tries + 1))
	done
	rm -f "$log"
}

_uis_stop() {
	[ -n "$UIS_PID" ] && kill "$UIS_PID" >/dev/null 2>&1
	wait "$UIS_PID" 2>/dev/null
	UIS_PID=""
	UIS_PORT=""
}

# _uis_fixtures <dir> — good/broken/cheat/hidden.html. cheat.html reproduces
# good.html's h1/p/a pixel-for-pixel with three plain, absolutely-positioned
# <div>s at the exact box measured for each real element (identical at both
# 1280 and 480 — nothing here wraps) and carries no h1/p/a at all: the
# regression test for the whole design, a pixel-identical page with no
# semantics must still fail.
_uis_fixtures() {
	local dir=$1
	cat >"$dir/good.html" <<'EOF'
<!doctype html><html><head><title>t</title></head>
<body>
<h1>Hello World</h1>
<p>some text</p>
<a href="#">link</a>
</body></html>
EOF
	cat >"$dir/hidden.html" <<'EOF'
<!doctype html><html><head><title>t</title></head>
<body>
<h1 style="display:none">Hello World</h1>
<p>some text</p>
<a href="#">link</a>
</body></html>
EOF
	cat >"$dir/broken.html" <<'EOF'
<!doctype html><html><head><title>t</title></head>
<body>
<h1>Hello World</h1>
<p>some text</p>
<a href="#">link</a>
<div style="position:absolute;top:0;left:0;width:600px;height:600px;background:red;"></div>
</body></html>
EOF
	cat >"$dir/cheat.html" <<'EOF'
<!doctype html><html><head><title>t</title></head>
<body>
<div style="position:absolute;left:8px;top:21.4375px;font-family:Times;font-size:32px;font-weight:700;color:rgb(0,0,0);margin:0;">Hello World</div>
<div style="position:absolute;left:8px;top:79.875px;font-family:Times;font-size:16px;font-weight:400;color:rgb(0,0,0);margin:0;">some text</div>
<div style="position:absolute;left:8px;top:113.875px;font-family:Times;font-size:16px;font-weight:400;color:rgb(0,0,238);text-decoration:underline;margin:0;">link</div>
</body></html>
EOF
}

# ---------------------------------------------------------------------------
# capture
# ---------------------------------------------------------------------------

t_uis_capture_writes_baseline_and_never_overwrites_expect() {
	_uis_need_ab "t_uis_capture_writes_baseline_and_never_overwrites_expect" || return 0
	local dir
	dir=$(tmp_dir)
	_uis_fixtures "$dir"
	_uis_serve "$dir"

	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_capture_writes_baseline_and_never_overwrites_expect rc"
	assert_file_exists "$dir/target/1280.png" "t_uis_capture_writes_baseline_and_never_overwrites_expect 1280png"
	assert_file_exists "$dir/target/480.png" "t_uis_capture_writes_baseline_and_never_overwrites_expect 480png"
	assert_file_exists "$dir/target/expect.json" "t_uis_capture_writes_baseline_and_never_overwrites_expect expectjson"
	assert_contains "$OUT" "next: ui-score score" "t_uis_capture_writes_baseline_and_never_overwrites_expect next-command"

	printf '{"edited":true}\n' >"$dir/target/expect.json"
	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_capture_writes_baseline_and_never_overwrites_expect recapture-rc"
	assert_eq "$(cat "$dir/target/expect.json")" '{"edited":true}' "t_uis_capture_writes_baseline_and_never_overwrites_expect expect-untouched"

	_uis_stop
	rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# score
# ---------------------------------------------------------------------------

t_uis_score_good_page_passes() {
	_uis_need_ab "t_uis_score_good_page_passes" || return 0
	local dir
	dir=$(tmp_dir)
	_uis_fixtures "$dir"
	_uis_serve "$dir"
	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_score_good_page_passes capture-rc"

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_score_good_page_passes rc"
	assert_contains "$OUT" "ui-score: PASS" "t_uis_score_good_page_passes pass-line"

	_uis_stop
	rm -rf "$dir"
}

t_uis_score_broken_page_fails_pixel_gate() {
	_uis_need_ab "t_uis_score_broken_page_fails_pixel_gate" || return 0
	local dir
	dir=$(tmp_dir)
	_uis_fixtures "$dir"
	_uis_serve "$dir"
	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_score_broken_page_fails_pixel_gate capture-rc"

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/broken.html"
	assert_rc 1 "t_uis_score_broken_page_fails_pixel_gate rc"
	assert_contains "$OUT" "pixel: FAIL" "t_uis_score_broken_page_fails_pixel_gate names-pixel-gate"
	assert_contains "$OUT" "ui-score: FAIL" "t_uis_score_broken_page_fails_pixel_gate summary"

	_uis_stop
	rm -rf "$dir"
}

# THE regression test for the whole design: a pixel-identical page with no
# semantics must fail. If this passes, the implementation is wrong.
t_uis_score_cheat_page_fails_missing_h1() {
	_uis_need_ab "t_uis_score_cheat_page_fails_missing_h1" || return 0
	local dir
	dir=$(tmp_dir)
	_uis_fixtures "$dir"
	_uis_serve "$dir"
	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_score_cheat_page_fails_missing_h1 capture-rc"

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/cheat.html"
	assert_rc 1 "t_uis_score_cheat_page_fails_missing_h1 rc"
	assert_contains "$OUT" "h1: MISSING" "t_uis_score_cheat_page_fails_missing_h1 names-missing-h1"

	_uis_stop
	rm -rf "$dir"
}

# Proves the visibility gate reads the bounding box, not just the count: a
# display:none h1 still counts as present.
t_uis_score_hidden_page_fails_not_visible() {
	_uis_need_ab "t_uis_score_hidden_page_fails_not_visible" || return 0
	local dir
	dir=$(tmp_dir)
	_uis_fixtures "$dir"
	_uis_serve "$dir"
	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_score_hidden_page_fails_not_visible capture-rc"

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/hidden.html"
	assert_rc 1 "t_uis_score_hidden_page_fails_not_visible rc"
	assert_contains "$OUT" "NOT VISIBLE" "t_uis_score_hidden_page_fails_not_visible names-not-visible"

	_uis_stop
	rm -rf "$dir"
}

t_uis_score_deleted_target_dir_is_harness_break() {
	_uis_need_ab "t_uis_score_deleted_target_dir_is_harness_break" || return 0
	local dir
	dir=$(tmp_dir)
	_uis_fixtures "$dir"
	_uis_serve "$dir"
	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_score_deleted_target_dir_is_harness_break capture-rc"
	rm -rf "$dir/target"

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 2 "t_uis_score_deleted_target_dir_is_harness_break rc"

	_uis_stop
	rm -rf "$dir"
}

# A down server is a harness break (exit 2), never a gate failure (exit 1) —
# the model cannot fix a server that never started.
t_uis_score_server_down_is_harness_break_not_gate_failure() {
	_uis_need_ab "t_uis_score_server_down_is_harness_break_not_gate_failure" || return 0
	local dir url
	dir=$(tmp_dir)
	_uis_fixtures "$dir"
	_uis_serve "$dir"
	url="http://127.0.0.1:$UIS_PORT/good.html"
	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "$url"
	assert_rc 0 "t_uis_score_server_down_is_harness_break_not_gate_failure capture-rc"
	_uis_stop

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "$url"
	assert_rc 2 "t_uis_score_server_down_is_harness_break_not_gate_failure rc"
	assert_not_contains "$OUT" "ui-score: FAIL" "t_uis_score_server_down_is_harness_break_not_gate_failure never-a-gate-failure"

	rm -rf "$dir"
}

# The wedge-detector stability requirement: no timings, temp paths, or random
# ids leaking into the output.
t_uis_score_repeated_runs_are_byte_identical() {
	_uis_need_ab "t_uis_score_repeated_runs_are_byte_identical" || return 0
	local dir url first
	dir=$(tmp_dir)
	_uis_fixtures "$dir"
	_uis_serve "$dir"
	url="http://127.0.0.1:$UIS_PORT/good.html"
	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "$url"
	assert_rc 0 "t_uis_score_repeated_runs_are_byte_identical capture-rc"

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "$url"
	first="$OUT"
	run_cmd "$UIS_BIN" score --target "$dir/target" --url "$url"
	assert_eq "$OUT" "$first" "t_uis_score_repeated_runs_are_byte_identical stdout-run2"
	run_cmd "$UIS_BIN" score --target "$dir/target" --url "$url"
	assert_eq "$OUT" "$first" "t_uis_score_repeated_runs_are_byte_identical stdout-run3"

	_uis_stop
	rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# capture --from-image (F6: seed a target from a design mock)
# ---------------------------------------------------------------------------

# _uis_mock_image <path> <w> <h> — a plain Pillow-generated PNG, standing in
# for a design mock export.
_uis_mock_image() {
	python3 -c 'from PIL import Image; import sys; Image.new("RGB", (int(sys.argv[2]), int(sys.argv[3])), "white").save(sys.argv[1])' "$1" "$2" "$3"
}

t_uis_capture_from_image_scales_and_writes_empty_must() {
	_uis_need_ab "t_uis_capture_from_image_scales_and_writes_empty_must" || return 0
	local dir width height must
	dir=$(tmp_dir)
	_uis_mock_image "$dir/mock.png" 2560 3284

	run_cmd "$UIS_BIN" capture --target "$dir/target" --from-image "$dir/mock.png" --viewports 1280
	assert_rc 0 "t_uis_capture_from_image_scales_and_writes_empty_must rc"
	assert_file_exists "$dir/target/1280.png" "t_uis_capture_from_image_scales_and_writes_empty_must png"
	assert_contains "$OUT" "height 1642 came from the mock aspect ratio" "t_uis_capture_from_image_scales_and_writes_empty_must height-line"

	width=$(python3 -c "from PIL import Image; print(Image.open('$dir/target/1280.png').size[0])")
	assert_eq "$width" "1280" "t_uis_capture_from_image_scales_and_writes_empty_must width"

	height=$(python3 -c "import json; print(json.load(open('$dir/target/expect.json'))['height'])")
	assert_eq "$height" "1642" "t_uis_capture_from_image_scales_and_writes_empty_must expect-height"

	must=$(python3 -c "import json; print(json.load(open('$dir/target/expect.json'))['must'])")
	assert_eq "$must" "[]" "t_uis_capture_from_image_scales_and_writes_empty_must must-empty"

	rm -rf "$dir"
}

t_uis_capture_from_image_two_viewports_is_error() {
	_uis_need_ab "t_uis_capture_from_image_two_viewports_is_error" || return 0
	local dir
	dir=$(tmp_dir)
	_uis_mock_image "$dir/mock.png" 2560 3284

	run_cmd "$UIS_BIN" capture --target "$dir/target" --from-image "$dir/mock.png" --viewports 1280,480
	assert_rc 2 "t_uis_capture_from_image_two_viewports_is_error rc"
	assert_contains "$OUT" "exactly one --viewports value" "t_uis_capture_from_image_two_viewports_is_error message"

	rm -rf "$dir"
}

t_uis_capture_from_image_with_url_is_error() {
	_uis_need_ab "t_uis_capture_from_image_with_url_is_error" || return 0
	local dir
	dir=$(tmp_dir)
	_uis_mock_image "$dir/mock.png" 2560 3284

	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:1/x" --from-image "$dir/mock.png"
	assert_rc 2 "t_uis_capture_from_image_with_url_is_error rc"

	rm -rf "$dir"
}

# _uis_fakebin — a no-op agent-browser stub, echoes the scratch dir. Only
# needed to get main()'s `shutil.which("agent-browser")` gate past `score`;
# the crashes these tests target happen before any agent-browser call.
_uis_fakebin() {
	local d
	d=$(tmp_dir)
	printf '#!/bin/sh\nexit 0\n' >"$d/agent-browser"
	chmod +x "$d/agent-browser"
	printf '%s' "$d"
}

# A malformed expect.json is a harness break (exit 2, a die() message), not
# an uncaught JSONDecodeError traceback exiting 1 (Python's default) -- the
# code this file's own docstring defines as "a gate failed".
t_uis_score_malformed_expect_json_is_harness_break() {
	local dir fakebin
	dir=$(tmp_dir)
	mkdir -p "$dir/target"
	printf '{ this is not json\n' >"$dir/target/expect.json"
	fakebin=$(_uis_fakebin)

	PATH="$fakebin:$PATH" run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:1/x"
	assert_rc 2 "t_uis_score_malformed_expect_json_is_harness_break rc"
	assert_contains "$OUT" "not valid JSON" "t_uis_score_malformed_expect_json_is_harness_break message"
	assert_not_contains "$ERR" "Traceback" "t_uis_score_malformed_expect_json_is_harness_break no-traceback"

	rm -rf "$dir" "$fakebin"
}

# _uis_fakebin_ok <fixed-png> — an agent-browser stub that answers every
# structure gate as present/visible and hands back <fixed-png> for
# 'screenshot' -- enough to drive cmd_score's structure checks through to
# pixel_pct() without a real browser. Echoes the scratch dir.
_uis_fakebin_ok() {
	local png=$1 d
	d=$(tmp_dir)
	{
		printf '#!/bin/sh\n'
		printf 'case "$*" in\n'
		printf '*"get count"*) printf %%s '"'"'{"success":true,"data":{"count":1}}'"'"'; exit 0 ;;\n'
		printf '*"get box"*) printf %%s '"'"'{"success":true,"data":{"width":10,"height":10}}'"'"'; exit 0 ;;\n'
		printf '*screenshot*) dst=$(printf %%s "$*" | awk "{print \\$NF}"); cp %s "$dst" 2>/dev/null; printf %%s '"'"'{"success":true,"data":{}}'"'"'; exit 0 ;;\n' "$png"
		printf 'esac\n'
		printf 'printf %%s '"'"'{"success":true,"data":{}}'"'"'\n'
		printf 'exit 0\n'
	} >"$d/agent-browser"
	chmod +x "$d/agent-browser"
	printf '%s' "$d"
}

# A corrupt/unreadable baseline PNG is a harness break (exit 2), not an
# uncaught PIL.UnidentifiedImageError traceback exiting 1.
t_uis_score_corrupt_baseline_png_is_harness_break() {
	local dir fakebin
	dir=$(tmp_dir)
	mkdir -p "$dir/target"
	printf '{"viewports":[100],"height":100,"must":[{"sel":"body","min":1}]}\n' >"$dir/target/expect.json"
	printf 'not a png' >"$dir/target/100.png"
	fakebin=$(_uis_fakebin_ok "$dir/target/100.png")

	PATH="$fakebin:$PATH" run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:1/x"
	assert_rc 2 "t_uis_score_corrupt_baseline_png_is_harness_break rc"
	assert_contains "$OUT" "cannot read baseline/screenshot image" "t_uis_score_corrupt_baseline_png_is_harness_break message"
	assert_not_contains "$ERR" "Traceback" "t_uis_score_corrupt_baseline_png_is_harness_break no-traceback"

	rm -rf "$dir" "$fakebin"
}

t_uis_score_refuses_empty_must() {
	_uis_need_ab "t_uis_score_refuses_empty_must" || return 0
	local dir
	dir=$(tmp_dir)
	mkdir -p "$dir/target"
	printf '{"viewports":[1280],"height":900,"must":[]}\n' >"$dir/target/expect.json"

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:1/x"
	assert_rc 2 "t_uis_score_refuses_empty_must rc"
	assert_contains "$OUT" "empty 'must' list" "t_uis_score_refuses_empty_must message"

	rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# session isolation (BUG 1) / stale-cache (BUG 2) regressions
# ---------------------------------------------------------------------------

# BUG 2: a page swapped at the SAME url with an unchanged mtime must not let
# ui-score reuse agent-browser's cached (old) DOM and PASS against a page
# that no longer has the CTA a 'must' entry requires. `touch -t` pins the
# mtime back so http.server's Last-Modified is identical across the swap and
# a conditional GET 304s -- the exact reproduction from the bug report.
t_uis_score_stale_cache_after_swap_fails() {
	_uis_need_ab "t_uis_score_stale_cache_after_swap_fails" || return 0
	local dir
	dir=$(tmp_dir)
	cat >"$dir/index.html" <<'EOF'
<!doctype html><html><head><title>t</title></head>
<body>
<h1>Hello World</h1>
<p>some text</p>
<a href="#">link</a>
</body></html>
EOF
	touch -t 202001010000 "$dir/index.html"
	_uis_serve "$dir"
	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/index.html"
	assert_rc 0 "t_uis_score_stale_cache_after_swap_fails capture-rc"

	cat >"$dir/index.html" <<'EOF'
<!doctype html><html><head><title>t</title></head>
<body>
<h1>Simple pricing</h1>
<p>no anchor here</p>
</body></html>
EOF
	touch -t 202001010000 "$dir/index.html"

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/index.html"
	assert_rc 1 "t_uis_score_stale_cache_after_swap_fails rc"
	assert_contains "$OUT" "a: MISSING" "t_uis_score_stale_cache_after_swap_fails names-missing-a"
	assert_contains "$OUT" "ui-score: FAIL" "t_uis_score_stale_cache_after_swap_fails summary"

	_uis_stop
	rm -rf "$dir"
}

# BUG 1: SESSION embeds this process's pid and must never reach stdout --
# flow's wedge detector sha1s ui-score's output, and a changing pid there
# would defeat it.
t_uis_score_stdout_never_leaks_session_name() {
	_uis_need_ab "t_uis_score_stdout_never_leaks_session_name" || return 0
	local dir
	dir=$(tmp_dir)
	_uis_fixtures "$dir"
	_uis_serve "$dir"

	run_cmd "$UIS_BIN" capture --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_score_stdout_never_leaks_session_name capture-rc"
	assert_not_contains "$OUT" "ui-score-" "t_uis_score_stdout_never_leaks_session_name capture-stdout-no-session"

	run_cmd "$UIS_BIN" score --target "$dir/target" --url "http://127.0.0.1:$UIS_PORT/good.html"
	assert_rc 0 "t_uis_score_stdout_never_leaks_session_name score-rc"
	assert_not_contains "$OUT" "ui-score-" "t_uis_score_stdout_never_leaks_session_name score-stdout-no-session"

	_uis_stop
	rm -rf "$dir"
}
