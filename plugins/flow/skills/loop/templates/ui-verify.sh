#!/bin/sh
# ui-verify.sh — boot/assert/teardown wrapper for a UI loop verifier.
#
#   flow loop init "<goal>" --verify "sh tests/ui/verify.sh"
#
# The --verify string above MUST be exactly ONE simple command: no &&, |, or
# ; in it. flow's loop runs it as `sh -c "$verify"` and SIGTERMs that process
# at verify_timeout. With a shell operator in the string, `sh -c` never execs
# into a single child (it stays a shell parsing a list), so the SIGTERM never
# reaches THIS script, the cleanup trap below never fires, and the dev server
# survives into the next iteration -- STILL SERVING THE OLD BUILD. That's a
# silent wrong verdict, not an error. Put composition (build steps, extra
# checks) inside this file, after boot, not in the --verify string.
#
# Exit contract:
#   0 = every assertion passed
#   1 = an assertion failed (the app is up, something on it is wrong)
#   2 = the harness broke (server wouldn't boot, port busy, tool missing) --
#       never a gate failure (1) when we simply couldn't test the app.
set -eu

# ---- config, all overridable by env ----------------------------------
PORT=${PORT:-4173}
SERVE=${SERVE:-"npm run preview -- --port $PORT"}
HEALTH=${HEALTH:-/}
BOOT=${BOOT:-60}
BASE_URL=${BASE_URL:-"http://127.0.0.1:$PORT"}
export BASE_URL
# ui-score ships inside the flow plugin, NOT in your project, so a path
# relative to the repo root only resolves when the loop runs in the flow repo
# itself. Derive it from whatever `flow` is on PATH (it is a symlink into the
# plugin), so this works from any project. Override FLOW_UI_SCORE if `flow`
# is not on PATH. Only used by variant (b) below.
FLOW_UI_SCORE=${FLOW_UI_SCORE:-"$(dirname "$(readlink -f "$(command -v flow)" 2>/dev/null || command -v flow)")/../scripts/ui-score"}
# Every agent-browser call below carries --session "$SESSION". agent-browser
# sessions are machine-global daemons, not per-invocation processes: without
# --session, this script's `open` and a sibling loop's (or a leftover manual)
# `is`/`get` land on the same shared "default" session, so an assertion can
# pass against whatever page someone else last opened -- the app this script
# booted is never actually looked at. Any assertion you add below MUST also
# carry --session "$SESSION" or it silently checks the wrong tab.
SESSION="flow-ui-$$"

# ---- refuse a stale server: the #1 silent-wrong-verdict cause ---------
if curl -sf -o /dev/null --max-time 2 "$BASE_URL$HEALTH"; then
	echo "ui-verify: something already answers $BASE_URL$HEALTH -- kill it before looping (stale server from a previous iteration serves the OLD build)" >&2
	exit 2
fi

# ---- boot: own process group so cleanup can kill the whole tree ------
# ponytail: needs job-control (`set -m`); a tty-less dash (some Linux /bin/sh)
# can't group child procs -- swap in `setsid -w` there if that's your target.
set -m
# SERVE's own stdout/stderr (access logs, "ready in Xms" banners, ...) go
# nowhere: left connected to this script's pipes, they land verbatim in
# verify.js's captured output -- the exact text signatureOf() hashes for
# wedge detection -- and carry real wall-clock timestamps none of its
# masking regexes catch, so two green runs of an unchanged page hash
# differently. ponytail: fully discarded, not logged; redirect to a file
# under .claude/loop/ instead of /dev/null if you need it for debugging.
sh -c "$SERVE" >/dev/null 2>&1 &
SERVE_PID=$!
disown 2>/dev/null || true
set +m

# cleanup() kills BEFORE it prints anything: spawnSync closes this script's
# stdout pipe on timeout, so a stdout write from teardown can itself raise
# SIGPIPE. If the kill happened after a print, that SIGPIPE would take the
# server down with the script -- kill first so the process tree is gone
# regardless of what happens to the pipe.
cleanup() {
	kill -TERM -"$SERVE_PID" 2>/dev/null || kill "$SERVE_PID" 2>/dev/null || true
	agent-browser --session "$SESSION" close >/dev/null 2>&1 || true
}
# PIPE is trapped too: without it, a SIGPIPE from a broken stdout (the case
# above) terminates this script via PIPE's default action BEFORE the EXIT
# trap runs, so cleanup never fires and the dev server leaks.
trap cleanup EXIT INT TERM HUP PIPE

# ---- readiness: poll, never a bare sleep ------------------------------
i=0
while ! curl -sf -o /dev/null --max-time 2 "$BASE_URL$HEALTH"; do
	kill -0 "$SERVE_PID" 2>/dev/null || {
		echo "ui-verify: server process died before it answered $BASE_URL$HEALTH" >&2
		exit 2
	}
	i=$((i + 1))
	[ "$i" -ge "$BOOT" ] && {
		echo "ui-verify: server did not answer $BASE_URL$HEALTH within ${BOOT}s" >&2
		exit 2
	}
	sleep 1
done

# ---- deterministic rendering, set BEFORE the first load ---------------
# All three must precede `open`: media and viewport decide how the initial
# render lays out, and no-cache decides whether that load is a fresh fetch at
# all. Set after `open`, they arrive too late for the one page this script
# ever looks at -- and for the headers that is a silent wrong verdict, not a
# cosmetic one: a 304 against an unchanged Last-Modified/ETag makes every
# assertion below describe the PREVIOUS build while reporting a pass.
# Measured on agent-browser 0.23.4: a second `open` of an unchanged URL does
# not refetch, and `reload` does not either.
agent-browser --session "$SESSION" set media light reduced-motion
agent-browser --session "$SESSION" set viewport 1280 900
agent-browser --session "$SESSION" set headers '{"Cache-Control":"no-cache","Pragma":"no-cache"}'

# ---- navigate the browser to the app this script just booted ----------
agent-browser --session "$SESSION" open "$BASE_URL$HEALTH" || {
	echo "ui-verify: browser could not load $BASE_URL$HEALTH (curl saw it up, agent-browser open failed)" >&2
	exit 2
}

# ---- the one assertion primitive that can't lie -----------------------
# Measured on agent-browser 0.23.4: `is visible` and `get text` BOTH return
# SUCCESS (exit 0, a real value) on a display:none element -- neither can
# carry an assertion, they'll happily pass against a hidden node. A
# non-zero bounding box is the one fact that catches "present but hidden"
# and "collapsed to nothing" at once.
# ui_box_check <selector> -- 0 = box has width>0 and height>0, 1 = it
# doesn't (including "element absent"), 2 = agent-browser's --json output
# didn't parse (a harness break, not a failed assertion -- caller must exit
# 2, not 1, on that code).
ui_box_check() {
	agent-browser --session "$SESSION" --json get box "$1" | node -e '
		let s = "";
		process.stdin.on("data", (d) => { s += d; });
		process.stdin.on("end", () => {
			let j;
			try { j = JSON.parse(s); } catch (e) { process.exit(2); }
			const d = j && j.data;
			process.exit(d && d.width > 0 && d.height > 0 ? 0 : 1);
		});
	'
}

# ===== EDIT BELOW THIS LINE: your assertions ===============================
# `agent-browser is visible` and `agent-browser get count` are QUERIES, not
# assertions: they exit 0 whether the answer is true/0 or false/N. Never
# assert on their exit code -- always capture and compare the PRINTED value.
# Every call MUST carry --session "$SESSION" (see the note near the top).

if ui_box_check '#confirmation'; then rc=0; else rc=$?; fi
if [ "$rc" -eq 2 ]; then
	echo "ui-verify: harness broke: agent-browser get box on #confirmation returned nothing parseable" >&2
	exit 2
elif [ "$rc" -ne 0 ]; then
	echo "ui-verify: FAIL #confirmation box: zero-size or missing"
	exit 1
fi

# h1's text check rides ON TOP OF a box check for the same selector -- a
# text check alone would pass against a display:none h1 (measured, see the
# note above ui_box_check).
if ui_box_check 'h1'; then rc=0; else rc=$?; fi
if [ "$rc" -eq 2 ]; then
	echo "ui-verify: harness broke: agent-browser get box on h1 returned nothing parseable" >&2
	exit 2
elif [ "$rc" -ne 0 ]; then
	echo "ui-verify: FAIL h1 box: zero-size or missing"
	exit 1
fi
v=$(agent-browser --session "$SESSION" get text 'h1')
test "$v" = "Order confirmed" || {
	echo "ui-verify: FAIL h1 text: expected 'Order confirmed' got '$v'"
	exit 1
}

# variant (b): score against a pixel+structure target captured with
# `ui-score capture` (browser-verifier.md rung 4). ui-score never boots the
# server itself -- that's what this wrapper is for. `|| exit $?` forwards
# ui-score's 1-(gate failed)-vs-2-(harness broke) distinction instead of
# collapsing both into this script's own exit 1.
# "$FLOW_UI_SCORE" score --target .loop-target --url "$BASE_URL" || exit $?
# ===== EDIT ABOVE THIS LINE =================================================

# `|| true`: under `set -eu`, a failed write here (closed/broken stdout)
# would exit with the echo's own nonzero status -- turning a real PASS into
# a reported FAIL. Every assertion above already ran and passed; a print
# failure on the way out must not flip that verdict.
echo "ui-verify: PASS" || true
