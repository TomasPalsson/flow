#!/usr/bin/env bash
# tests/lib.sh — minimal, dependency-free test helpers (bash 3.2 compatible).
# Source from run.sh. Tests are functions named t_<name> inside test_*.sh files.
#
#   run_hook <script> <json> [VAR=val ...]   → RC, OUT (stdout), ERR (stderr)
#   run_cmd <cmd> [args...]                  → RC, OUT, ERR
#   assert_rc <expected> "<name>"
#   assert_contains "<haystack>" "<needle>" "<name>"
#   assert_not_contains "<haystack>" "<needle>" "<name>"
#   assert_eq "<actual>" "<expected>" "<name>"
#   assert_file_exists <path> "<name>"
#   assert_file_missing <path> "<name>"
#   tmp_dir                                  → echoes a fresh temp dir
#   tmp_repo                                 → echoes a fresh git repo with one commit
#   summary                                  → prints "N passed, M failed"; exit 1 if M>0

PASS=0
FAIL=0
FAILED_NAMES=""
RC=0
OUT=""
ERR=""

_pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
_fail() {
  FAIL=$((FAIL + 1))
  FAILED_NAMES="$FAILED_NAMES
  - $1"
  printf '  FAIL %s\n' "$1"
  if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi
}

tmp_dir() { mktemp -d "${TMPDIR:-/tmp}/flow-test.XXXXXX"; }

tmp_repo() {
  local d
  d=$(tmp_dir)
  (
    cd "$d" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "harness-test"
    git config commit.gpgsign false
    printf '# fixture\n' >README.md
    git add README.md
    git commit -q -m "init"
  ) >/dev/null 2>&1
  printf '%s' "$d"
}

run_hook() {
  local script=$1 json=$2 errf
  shift 2
  errf=$(mktemp "${TMPDIR:-/tmp}/flow-err.XXXXXX")
  if [ $# -gt 0 ]; then
    OUT=$(printf '%s' "$json" | env "$@" bash "$script" 2>"$errf")
  else
    OUT=$(printf '%s' "$json" | bash "$script" 2>"$errf")
  fi
  RC=$?
  ERR=$(cat "$errf")
  rm -f "$errf"
}

run_cmd() {
  local errf
  errf=$(mktemp "${TMPDIR:-/tmp}/flow-err.XXXXXX")
  OUT=$("$@" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf")
  rm -f "$errf"
}

assert_rc() {
  if [ "$RC" -eq "$1" ]; then _pass "$2"; else _fail "$2" "expected rc=$1 got rc=$RC; stderr: $(printf '%s' "$ERR" | head -3 | tr '\n' ' ')"; fi
}

assert_contains() {
  case "$1" in
  *"$2"*) _pass "$3" ;;
  *) _fail "$3" "missing '$2' in: $(printf '%s' "$1" | head -5 | tr '\n' ' ')" ;;
  esac
}

assert_not_contains() {
  case "$1" in
  *"$2"*) _fail "$3" "unexpected '$2' in: $(printf '%s' "$1" | head -5 | tr '\n' ' ')" ;;
  *) _pass "$3" ;;
  esac
}

assert_eq() {
  if [ "$1" = "$2" ]; then _pass "$3"; else _fail "$3" "expected '$2' got '$1'"; fi
}

assert_file_exists() {
  if [ -e "$1" ]; then _pass "$2"; else _fail "$2" "no such file: $1"; fi
}

assert_file_missing() {
  if [ ! -e "$1" ]; then _pass "$2"; else _fail "$2" "file exists: $1"; fi
}

summary() {
  printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
  if [ "$FAIL" -gt 0 ]; then
    printf 'failed:%s\n' "$FAILED_NAMES"
    exit 1
  fi
  exit 0
}
