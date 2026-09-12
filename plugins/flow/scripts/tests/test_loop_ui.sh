#!/usr/bin/env bash
# test_loop_ui.sh — plugins/flow/skills/loop/templates/ui-verify.sh, the
# boot/assert/teardown wrapper a loop's `--verify` points at. t_loop_ui_*
# prefix. Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent,
# "scripts/") are set there.
#
# We never invoke the REAL agent-browser here (it needs Chrome + a daemon):
# a no-op stub shadows it on PATH so the template's deterministic-rendering
# calls succeed without a browser. What this test guards is the wrapper's
# LIFECYCLE (refuse-if-busy, boot, poll, teardown, exit codes), so the
# assertions block is swapped for a plain curl probe against a stashed
# python3 http.server standing in for the dev server.
set -u

UI_TEMPLATE=$(cd "$SCAN_DIR/../skills/loop/templates" && pwd -P)/ui-verify.sh

# _ui_fakebin — a scratch dir with a no-op `agent-browser` stub; echoes the dir.
_ui_fakebin() {
	local d
	d=$(tmp_dir)
	printf '#!/bin/sh\nexit 0\n' >"$d/agent-browser"
	chmod +x "$d/agent-browser"
	printf '%s' "$d"
}

# _ui_webroot — a scratch dir with probe.txt=ok for the stand-in server; echoes the dir.
_ui_webroot() {
	local d
	d=$(tmp_dir)
	printf 'ok' >"$d/probe.txt"
	printf '%s' "$d"
}

# _ui_variant <assertion-line> — copies UI_TEMPLATE with the fenced assertions
# block replaced by <assertion-line>; echoes the path to the copy.
_ui_variant() {
	local out start end
	out=$(tmp_dir)/verify.sh
	start=$(grep -n 'EDIT BELOW THIS LINE' "$UI_TEMPLATE" | head -1 | cut -d: -f1)
	end=$(grep -n 'EDIT ABOVE THIS LINE' "$UI_TEMPLATE" | head -1 | cut -d: -f1)
	{
		sed -n "1,${start}p" "$UI_TEMPLATE"
		printf '%s\n' "$1"
		sed -n "${end},\$p" "$UI_TEMPLATE"
	} >"$out"
	chmod +x "$out"
	printf '%s' "$out"
}

# _ui_run <port> <serve> <boot> <script> — runs <script> with the stub
# agent-browser on PATH and PORT/SERVE/HEALTH/BOOT set for the probe server.
_ui_run() {
	local port=$1 serve=$2 boot=$3 script=$4 fakebin
	fakebin=$(_ui_fakebin)
	run_cmd env "PORT=$port" "SERVE=$serve" "HEALTH=/probe.txt" "BOOT=$boot" \
		"PATH=$fakebin:$PATH" sh "$script"
}

# _ui_port_free <port> — true (rc 0) if nothing answers on <port>.
_ui_port_free() {
	! curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:$1/probe.txt" 2>/dev/null
}

# ---------------------------------------------------------------------------

t_loop_ui_template_exists_and_parses() {
	assert_file_exists "$UI_TEMPLATE" "t_loop_ui_template_exists_and_parses file"
	run_cmd sh -n "$UI_TEMPLATE"
	assert_rc 0 "t_loop_ui_template_exists_and_parses sh -n"
}

t_loop_ui_green_path_exits_0() {
	local port=58991 web script
	web=$(_ui_webroot)
	script=$(_ui_variant 'test "$(curl -s "$BASE_URL/probe.txt")" = "ok" || { echo "ui-verify: FAIL probe: expected ok"; exit 1; }')
	_ui_run "$port" "python3 -m http.server $port --directory $web" 10 "$script"
	assert_rc 0 "t_loop_ui_green_path_exits_0 rc"
	assert_contains "$OUT" "ui-verify: PASS" "t_loop_ui_green_path_exits_0 pass-line"
	if _ui_port_free "$port"; then _pass "t_loop_ui_green_path_exits_0 no orphan"; else _fail "t_loop_ui_green_path_exits_0 no orphan" "still listening on $port"; fi
}

# SERVE's own stdout/stderr (http.server's access log, with a real
# wall-clock timestamp on every line) must not leak into the wrapper's
# output -- that's the exact text verify.js's signatureOf() hashes for
# wedge detection, and a timestamp isn't covered by its masking regexes.
t_loop_ui_serve_output_not_captured() {
	local port=58981 web script
	web=$(_ui_webroot)
	script=$(_ui_variant 'test "$(curl -s "$BASE_URL/probe.txt")" = "ok" || { echo "ui-verify: FAIL probe: expected ok"; exit 1; }')
	_ui_run "$port" "python3 -m http.server $port --directory $web" 10 "$script"
	assert_rc 0 "t_loop_ui_serve_output_not_captured rc"
	assert_not_contains "$OUT$ERR" "GET /probe.txt" "t_loop_ui_serve_output_not_captured no access-log leak"
}

# A real, fully-passed verification must still exit 0 even when the write
# of the final "ui-verify: PASS" line itself fails (closed stdout) -- under
# `set -eu` an unguarded echo there turns a true pass into a reported fail.
t_loop_ui_pass_survives_closed_stdout() {
	local port=58982 web script
	web=$(_ui_webroot)
	script=$(_ui_variant 'test "$(curl -s "$BASE_URL/probe.txt")" = "ok" || { echo "ui-verify: FAIL probe: expected ok"; exit 1; }')
	local fakebin
	fakebin=$(_ui_fakebin)
	env "PORT=$port" "SERVE=python3 -m http.server $port --directory $web" \
		"HEALTH=/probe.txt" "BOOT=10" "PATH=$fakebin:$PATH" \
		sh "$script" >&- 2>/dev/null
	# shellcheck disable=SC2034  # RC is the global assert_rc reads
	RC=$?
	assert_rc 0 "t_loop_ui_pass_survives_closed_stdout rc"
}

t_loop_ui_red_path_exits_1() {
	local port=58992 web script
	web=$(_ui_webroot)
	script=$(_ui_variant 'test "$(curl -s "$BASE_URL/probe.txt")" = "nope" || { echo "ui-verify: FAIL probe: expected nope"; exit 1; }')
	_ui_run "$port" "python3 -m http.server $port --directory $web" 10 "$script"
	assert_rc 1 "t_loop_ui_red_path_exits_1 rc"
	assert_contains "$OUT" "ui-verify: FAIL probe: expected nope" "t_loop_ui_red_path_exits_1 stable-message"
}

t_loop_ui_port_busy_exits_2() {
	local port=58993 web script busy_pid
	web=$(_ui_webroot)
	python3 -m http.server "$port" --directory "$web" >/dev/null 2>&1 &
	busy_pid=$!
	disown 2>/dev/null || true
	local i=0
	while ! curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:$port/probe.txt"; do
		i=$((i + 1))
		[ "$i" -ge 20 ] && break
		sleep 0.2
	done
	script=$(_ui_variant 'echo unreachable')
	_ui_run "$port" "false" 10 "$script"
	assert_rc 2 "t_loop_ui_port_busy_exits_2 rc"
	assert_contains "$OUT$ERR" "already answers" "t_loop_ui_port_busy_exits_2 remedy"
	kill "$busy_pid" 2>/dev/null || true
	wait "$busy_pid" 2>/dev/null || true
}

t_loop_ui_serve_dies_fast_exits_2() {
	local port=58994 script start end elapsed
	script=$(_ui_variant 'echo unreachable')
	start=$SECONDS
	_ui_run "$port" "false" 60 "$script"
	end=$SECONDS
	elapsed=$((end - start))
	assert_rc 2 "t_loop_ui_serve_dies_fast_exits_2 rc"
	if [ "$elapsed" -le 10 ]; then
		_pass "t_loop_ui_serve_dies_fast_exits_2 fast (${elapsed}s, not a 60s hang)"
	else
		_fail "t_loop_ui_serve_dies_fast_exits_2 fast" "took ${elapsed}s"
	fi
}

# _ui_fakebin_box <json> <rc> — stub agent-browser: any invocation whose
# args contain "get box" prints <json> and exits <rc>; every other
# subcommand (open/set/close/...) is a silent no-op success. Echoes the dir.
_ui_fakebin_box() {
	local json=$1 rc=$2 d
	d=$(tmp_dir)
	{
		printf '#!/bin/sh\n'
		printf 'case "$*" in\n'
		printf '*"get box"*) printf %%s '"'"'%s'"'"'; exit %s ;;\n' "$json" "$rc"
		printf 'esac\n'
		printf 'exit 0\n'
	} >"$d/agent-browser"
	chmod +x "$d/agent-browser"
	printf '%s' "$d"
}

# _ui_box_run <fakebin> <script> <port> — runs <script> with <fakebin> on
# PATH against a stand-in server (needed for boot to reach the assertions
# block); each caller passes its own port so back-to-back tests never race
# a just-freed listener.
_ui_box_run() {
	local fakebin=$1 script=$2 port=$3 web
	web=$(_ui_webroot)
	run_cmd env "PORT=$port" "SERVE=python3 -m http.server $port --directory $web" \
		"HEALTH=/probe.txt" "BOOT=10" "PATH=$fakebin:$PATH" sh "$script"
}

t_loop_ui_box_helper_zero_box_is_1() {
	local script fakebin
	script=$(_ui_variant 'rc=0; ui_box_check "sel" || rc=$?; echo "BOXRC=$rc"; exit 0')
	fakebin=$(_ui_fakebin_box '{"success":true,"data":{"height":0,"width":0}}' 0)
	_ui_box_run "$fakebin" "$script" 58996
	assert_contains "$OUT" "BOXRC=1" "t_loop_ui_box_helper_zero_box_is_1"
}

t_loop_ui_box_helper_nonzero_box_is_0() {
	local script fakebin
	script=$(_ui_variant 'rc=0; ui_box_check "sel" || rc=$?; echo "BOXRC=$rc"; exit 0')
	fakebin=$(_ui_fakebin_box '{"success":true,"data":{"height":37,"width":1264}}' 0)
	_ui_box_run "$fakebin" "$script" 58997
	assert_contains "$OUT" "BOXRC=0" "t_loop_ui_box_helper_nonzero_box_is_0"
}

t_loop_ui_box_helper_unparseable_is_2() {
	local script fakebin
	script=$(_ui_variant 'rc=0; ui_box_check "sel" || rc=$?; echo "BOXRC=$rc"; exit 0')
	fakebin=$(_ui_fakebin_box 'not json' 1)
	_ui_box_run "$fakebin" "$script" 58998
	assert_contains "$OUT" "BOXRC=2" "t_loop_ui_box_helper_unparseable_is_2"
}

t_loop_ui_trap_line_has_pipe() {
	if grep -n '^trap cleanup' "$UI_TEMPLATE" | grep -q 'PIPE'; then
		_pass "t_loop_ui_trap_line_has_pipe"
	else
		_fail "t_loop_ui_trap_line_has_pipe" "trap line does not list PIPE"
	fi
}

t_loop_ui_cleanup_kills_before_print_on_sigpipe() {
	local port=58999 web script fakebin
	web=$(_ui_webroot)
	script=$(_ui_variant 'echo unreachable')
	fakebin=$(_ui_fakebin)
	# Pipe the wrapper's stdout into `:`, which exits immediately and closes
	# its read end -- the "ui-verify: PASS" write at the end then hits a
	# broken pipe (SIGPIPE). If cleanup doesn't run (or dies before the
	# kill), the stand-in server orphans on $port.
	env "PORT=$port" "SERVE=python3 -m http.server $port --directory $web" \
		"HEALTH=/probe.txt" "BOOT=10" "PATH=$fakebin:$PATH" \
		sh "$script" | :
	if _ui_port_free "$port"; then
		_pass "t_loop_ui_cleanup_kills_before_print_on_sigpipe no orphan"
	else
		_fail "t_loop_ui_cleanup_kills_before_print_on_sigpipe no orphan" "still listening on $port"
	fi
}

t_loop_ui_no_orphan_after_sigterm_mid_flight() {
	local port=58995 web script out
	web=$(_ui_webroot)
	script=$(_ui_variant 'echo unreachable')
	out=$(tmp_dir)/out.txt
	local fakebin
	fakebin=$(_ui_fakebin)
	env "PORT=$port" "SERVE=sh -c 'sleep 5; exec python3 -m http.server $port --directory $web'" \
		"HEALTH=/probe.txt" "BOOT=30" "PATH=$fakebin:$PATH" \
		sh "$script" >"$out" 2>&1 &
	local vpid=$!
	sleep 1
	kill -TERM "$vpid" 2>/dev/null || true
	sleep 1
	if kill -0 "$vpid" 2>/dev/null; then
		_fail "t_loop_ui_no_orphan_after_sigterm_mid_flight exited" "still running after SIGTERM"
		kill -9 "$vpid" 2>/dev/null || true
	else
		_pass "t_loop_ui_no_orphan_after_sigterm_mid_flight exited"
	fi
	if _ui_port_free "$port"; then _pass "t_loop_ui_no_orphan_after_sigterm_mid_flight no orphan"; else _fail "t_loop_ui_no_orphan_after_sigterm_mid_flight no orphan" "still listening on $port"; fi
}
