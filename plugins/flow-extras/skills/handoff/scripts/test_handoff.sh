#!/usr/bin/env bash
# Tests for handoff.sh. Run: bash plugins/flow-extras/skills/handoff/scripts/test_handoff.sh
set -u
H="$(cd "$(dirname "$0")" && pwd)/handoff.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

T=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

# 1. planted secrets never reach the written file
export TMPDIR="$T"
path=$(printf '%s\n' 'Goal: ship. key sk-test-abcdef1234567890 and ghp_abcdefghijklmnop1234 and API_KEY=hunter2value' \
	'token: "abc123def456" mail me at a.b@example.com; Authorization: Bearer abcdefgh12345678' \
	'AWS AKIAABCDEFGHIJKLMNOP and password = s3cretpw' | "$H" write "My Task!")
if [ "$path" = "$T/handoff-my-task.md" ]; then ok "write path uses TMPDIR and sanitized slug"; else bad "write path: $path"; fi
body=$(cat "$path" 2>/dev/null || true)
for s in sk-test-abcdef ghp_abcdef hunter2value abc123def456 a.b@example.com abcdefgh12345678 AKIAABCDEFGHIJKLMNOP s3cretpw; do
	if has "$body" "$s"; then bad "secret survived: $s"; else ok "redacted: $s"; fi
done
if has "$body" "Goal: ship."; then ok "plain text kept"; else bad "plain text lost"; fi

# 2. unset TMPDIR falls back to /tmp
p2=$(env -u TMPDIR "$H" write "fallback-$$" </dev/null)
if [ "$p2" = "/tmp/handoff-fallback-$$.md" ]; then ok "unset TMPDIR falls back to /tmp"; else bad "fallback: $p2"; fi
rm -f "$p2"

# 3. dry run: $HOME and backticks reach the child unexpanded
printf '%s\n' 'cwd is $HOME and run `touch /tmp/handoff-pwned-'"$$"'` or $(id)' >"$T/sum.md"
cat >"$T/fakeclaude" <<'SH'
#!/bin/sh
printf "%s" "$5" >"$FAKE_OUT"
printf '%s|%s|%s' "$1" "$2" "$3" >"$FAKE_OUT.flags"
SH
chmod +x "$T/fakeclaude"
FAKE_OUT="$T/got" HANDOFF_CLAUDE="$T/fakeclaude" "$H" launch "Fix login" "$T/sum.md"
got=$(cat "$T/got" 2>/dev/null || true)
if has "$got" '$HOME' && has "$got" '`touch' && has "$got" '$(id)'; then ok 'child receives $HOME, backticks, $() unexpanded'; else bad "expanded: $got"; fi
if [ ! -e "/tmp/handoff-pwned-$$" ]; then ok "backtick command did not run"; else bad "backtick ran"; rm -f "/tmp/handoff-pwned-$$"; fi
if [ "$(cat "$T/got.flags" 2>/dev/null)" = "--bg|-n|Fix login" ]; then ok "flags are --bg -n <name>"; else bad "flags: $(cat "$T/got.flags" 2>/dev/null)"; fi

# 4. command prints the exact line and runs nothing
line=$("$H" command "Fix login" "$T/sum.md")
if [ "$line" = "claude --bg -n \"Fix login\" -- \"\$(cat $T/sum.md)\"" ]; then ok "command prints exact launch line"; else bad "line: $line"; fi

# 5. private-key blocks, stripe keys, *_KEY= assignments, mode, quoting, guard
body5=$(printf '%s\n' '-----BEGIN RSA PRIVATE KEY-----' 'MIIEowIBAAKCAQEAzSECRETBODYxyz0123456789abcdef' '-----END RSA PRIVATE KEY-----' \
	'export STRIPE_KEY=rk_live_abcdefghijklmnop' 'stripe sk_live_51HabcdefghijklmnopQRST' 'DEPLOY_KEY=abc999' 'keep max_tokens: 4096 here' | "$H" redact)
for s in MIIEowIBAAK 'END RSA' rk_live_abcdef sk_live_51Habc abc999; do
	if has "$body5" "$s"; then bad "secret survived: $s"; else ok "redacted: $s"; fi
done
if has "$body5" "max_tokens: 4096"; then ok "max_tokens not masked"; else bad "max_tokens masked: $body5"; fi
echo old >"$T/handoff-modetest.md"; chmod 644 "$T/handoff-modetest.md"
echo x | "$H" write modetest >/dev/null
m=$(stat -c %a "$T/handoff-modetest.md" 2>/dev/null || stat -f %Lp "$T/handoff-modetest.md")
if [ "$m" = 600 ]; then ok "existing file reset to mode 600"; else bad "mode $m"; fi
if "$H" command 'Fix "x" $(id)' "$T/sum.md" >/dev/null 2>&1; then bad "unsafe name accepted"; else ok "command rejects quotes and \$ in name"; fi
rc=0; out=$(PATH=/nonexistent "$(command -v bash)" "$H" launch "n" "$T/sum.md" 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && ! has "$out" "not found"; then ok "launch skips quietly without claude"; else bad "launch rc=$rc out=$out"; fi

# 6. URL credentials and signed-URL params
body6=$(printf '%s\n' 'https://u:pw99secret@git.example.com/r.git' 'https://b.s3.amazonaws.com/o?X-Amz-Signature=deadbeef0099&page=2' | "$H" redact)
for s in pw99secret deadbeef0099; do
	if has "$body6" "$s"; then bad "secret survived: $s"; else ok "redacted: $s"; fi
done
if has "$body6" "page=2"; then ok "ordinary query param kept"; else bad "page param lost: $body6"; fi

# 7. provenance markers (F187): a draft with one run step and one assumed step
# survives the write, the assumed step sits under "Verify first:", and the
# script warns when an assumed or failed step is not listed there.
good=$(printf '%s\n' 'Goal: ship' 'Verify first:' '- Open. check the staging path (assumed)' 'Next steps:' '- Open. run the suite (run) exit 0' | "$H" write prov-ok 2>"$T/prov-ok.err")
pb=$(cat "$good")
if has "$pb" "(run) exit 0" && has "$pb" "(assumed)"; then ok "markers survive redaction"; else bad "markers lost: $pb"; fi
vf=${pb%%Next steps:*}
if has "$vf" "(assumed)" && ! has "$vf" "(run) exit 0"; then ok "assumed step sits under Verify first"; else bad "verify-first placement: $pb"; fi
if [ ! -s "$T/prov-ok.err" ]; then ok "well-formed draft writes silently"; else bad "unexpected warning: $(cat "$T/prov-ok.err")"; fi
printf '%s\n' 'Goal: ship' 'Next steps:' '- Open. check the path (assumed)' | "$H" write prov-bad 2>"$T/prov-bad.err" >/dev/null
if has "$(cat "$T/prov-bad.err")" "Verify first"; then ok "warns when an assumed step is not under Verify first"; else bad "no warning for assumed step outside Verify first"; fi
printf '%s\n' 'Goal: ship' 'Next steps:' '- Open. run the suite (run) exit 1' | "$H" write prov-fail 2>"$T/prov-fail.err" >/dev/null
if has "$(cat "$T/prov-fail.err")" "Verify first"; then ok "warns for a failed run step outside Verify first"; else bad "no warning for failed run"; fi

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
