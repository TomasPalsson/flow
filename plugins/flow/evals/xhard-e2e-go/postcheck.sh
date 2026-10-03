#!/usr/bin/env bash
set -u
# slop-check with every finding fatal except NS-16 (advisory: spelling similarity only)
slop_check() {
	local out rc
	out=$("$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" "$@") || rc=$?
	[ "${rc:-0}" -eq 0 ] || { printf '%s\n' "$out"; return "$rc"; }
	out=$(printf '%s\n' "$out" | grep -v ': NS-16 ')
	[ -z "$out" ] || { printf '%s\n' "$out"; return 1; }
}
# Whole pipeline on a Go module: artifacts and gate discipline (Go gates, not
# python), the diff lane, gofmt/vet/test, reuse of textutil.Flatten proven by
# grep AND by breaking the helper, errors wrapped and never swallowed (hidden
# errors.Is tests), mutants of the new code against the MODEL's own tests.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
die() { echo "$1"; exit 1; }
TMPS=()
cleanup() { [ ${#TMPS[@]} -eq 0 ] || rm -rf "${TMPS[@]}"; }
trap cleanup EXIT
command -v go >/dev/null 2>&1 || die "go is not installed"

# ---- pipeline artifacts --------------------------------------------------------
CUR=$(tr -d '[:space:]' <.specs/.current 2>/dev/null)
{ [ -n "$CUR" ] && [ -d ".specs/$CUR" ]; } || die "no .specs/.current pointing at a feature dir"
FEAT=.specs/$CUR
[ -f "$FEAT/TASKS.md" ] || die "no $FEAT/TASKS.md: the pipeline never drafted a plan"
$FLOW lint "$FEAT/TASKS.md" --json >/tmp/xgo-lint.$$ 2>/dev/null
python3 - /tmp/xgo-lint.$$ "$FEAT" <<'PY'
import json, os, sys
lint = json.load(open(sys.argv[1]))
feat = sys.argv[2]
def bad(msg):
    print(msg)
    sys.exit(1)
if lint.get("errors"):
    bad("flow lint ERROR: " + lint["errors"][0].get("message", "?"))
tasks = lint["tasks"]
work = [t for t in tasks if t["kind"] == "task"]
gates = [t for t in tasks if t["kind"] == "gate"]
if not work:
    bad("plan has no tasks")
open_ids = [t["id"] for t in tasks if t["state"] == "open"]
if open_ids:
    bad("tasks still open at the end: " + ", ".join(open_ids))
if not gates:
    bad("no ## Gates in TASKS.md")
h = lint["header"]
if not h.get("approved"):
    bad("no Approved: line: the plan was never approved at the gate")
if h.get("verified"):
    bad("Verified: is written; that fact is the human's, the run must stop at unverified")
if h.get("route") == "dispatch" and not os.path.isfile(os.path.join(feat, "spec.md")):
    bad("Route: dispatch but no spec.md")
PY
rc=$?
rm -f /tmp/xgo-lint.$$
[ "$rc" -eq 0 ] || exit 1
if grep -rE '^[[:space:]]*Verified:' .specs --include='*.md' >/dev/null 2>&1; then die "a Verified: line exists under .specs"; fi
$FLOW pass >/dev/null 2>&1 || die "no PASS-<sha>.md covers HEAD"
ls "$FEAT"/PASS-*.md >/dev/null 2>&1 || die "no PASS file in $FEAT"
grep -qi 'exit' "$FEAT"/PASS-*.md || die "PASS file names no exit codes"
STATE=$($FLOW next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
[ "$STATE" = "unverified" ] || die "final router state is '$STATE', expected unverified"
if git status --porcelain | grep -v -E ' \.specs/| \.claude/' | grep . >/dev/null; then
	die "source changes left uncommitted (PASS would not describe HEAD)"
fi

# ---- the gates are Go's, not python's ------------------------------------------
sed -n '1,4p' "$FEAT/TASKS.md" | grep -E 'Test:' | grep -q 'go test' || die "TASKS.md header Test: is not go test"
if grep -E 'verify:' "$FEAT/TASKS.md" | grep -Ei 'python|pytest|unittest|npm |node ' | grep . >/dev/null; then
	die "a verify: command belongs to another stack"
fi
grep -Eqi 'go (test|vet)|flow check' "$FEAT"/PASS-*.md || die "the PASS file does not name a Go gate (go test, go vet or flow check)"
if grep -Ei 'python|pytest|unittest' "$FEAT"/PASS-*.md | grep . >/dev/null; then die "the PASS file names a python gate"; fi

# ---- the diff stayed in its lane ----------------------------------------------
BASEC=$(git log --format=%h --grep='^report: dues table and the tool$' -n 1)
[ -n "$BASEC" ] || die "scaffold history missing"
CHANGED=$(git diff --diff-filter=DM --name-only "$BASEC" -- . ':!.specs' ':!.claude')
[ -z "$CHANGED" ] || die "an existing file was edited or deleted: $(printf '%s' "$CHANGED" | head -1)"
for f in $(git diff --diff-filter=A --name-only "$BASEC" -- . ':!.specs' ':!.claude'); do
	case "$f" in
	internal/members/*.go) ;;
	*) die "added a file outside internal/members: $f" ;;
	esac
done
NEW_SRC=$(git diff --diff-filter=A --name-only "$BASEC" -- internal/members | grep '\.go$' | grep -v '_test\.go$')
NEW_TESTS=$(git diff --diff-filter=A --name-only "$BASEC" -- internal/members | grep '_test\.go$')
[ -n "$NEW_SRC" ] || die "no new source file in internal/members"
[ -n "$NEW_TESTS" ] || die "no new test file in internal/members"

# ---- Go's own gates: gofmt, vet, test -------------------------------------------
[ -z "$(gofmt -l .)" ] || die "gofmt reports unformatted files: $(gofmt -l . | head -1)"
go vet ./... >/dev/null 2>&1 || die "go vet is red after the pipeline"
go test -count=1 ./... >/dev/null 2>&1 || die "go test is red after the pipeline"

# ---- code: helper reused not reimplemented, errors wrapped not swallowed ---------
CODE=$(for f in $NEW_SRC; do sed -E 's://.*$::' "$f"; done)
printf '%s\n' "$CODE" | grep -q 'textutil\.Flatten(' || die "the new code never calls textutil.Flatten"
printf '%s\n' "$CODE" | grep -q 'example.com/clubroll/internal/textutil' || die "the new code does not import internal/textutil"
if printf '%s\n' "$CODE" | grep -E 'strings\.Fields\(|regexp|unicode\.IsSpace' | grep . >/dev/null; then
	die "the new code re-implements whitespace canonicalization instead of textutil.Flatten"
fi
if printf '%s\n' "$CODE" | grep -E '(^|[[:space:];])_ *(, *_)? *(:=|=) ' | grep . >/dev/null; then
	die "the new code discards a value with the blank identifier: an error is swallowed"
fi
printf '%s\n' "$CODE" | grep -q '%w' || die "no fmt.Errorf with %w: the roster's sentinel errors are not wrapped"
NEWERR=$(printf '%s\n' "$CODE" | grep -c 'errors\.New(')
[ "$NEWERR" -le 1 ] || die "the new code mints $NEWERR fresh errors; only ErrBadLine is new"
if printf '%s\n' "$CODE" | grep -E 'panic\(|recover\(' | grep . >/dev/null; then die "the new code panics or recovers"; fi
if git diff "$BASEC" -- '*_test.go' | grep -E '^-[^-]' | grep . >/dev/null; then die "an existing test line was removed or edited"; fi

# ---- mutants: the model's OWN tests (no hidden file yet) must catch each ---------
wrap() { # <name> <func> <real name> <wrapper source>
	local name=$1 fn=$2 real=$3 body=$4 dir f
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	f=$(grep -l "^func $fn(" "$dir"/t/internal/members/*.go 2>/dev/null | grep -v '_test\.go$' | head -1)
	[ -n "$f" ] || die "mutant '$name' cannot apply: no top-level func $fn in a source file"
	sed -i "s/^func $fn(/func $real(/" "$f"
	printf '%s\n' "$body" >"$dir/t/internal/members/zz_mutant.go"
	(cd "$dir/t" && go test -count=1 -run '^$' ./internal/members/ >/dev/null 2>&1) ||
		die "mutant '$name' does not compile against this solution's layout"
	if (cd "$dir/t" && go test -count=1 ./internal/members/ >/dev/null 2>&1); then
		die "mutant survived ($name): the model's tests do not pin it"
	fi
}
wrap "Rename swallows a missing member" Rename renameReal 'package members

import "errors"

func Rename(s *Store, from, to string) error {
	err := renameReal(s, from, to)
	if errors.Is(err, ErrNotFound) {
		return nil
	}
	return err
}'
wrap "Rename swallows a taken name" Rename renameReal 'package members

import "errors"

func Rename(s *Store, from, to string) error {
	err := renameReal(s, from, to)
	if errors.Is(err, ErrExists) {
		return nil
	}
	return err
}'
wrap "Rename treats its own name as taken" Rename renameReal 'package members

import (
	"fmt"

	"example.com/clubroll/internal/textutil"
)

func Rename(s *Store, from, to string) error {
	if textutil.Flatten(from) == textutil.Flatten(to) {
		return fmt.Errorf("rename: %w", ErrExists)
	}
	return renameReal(s, from, to)
}'
wrap "Rename leaves the old name behind" Rename renameReal 'package members

func Rename(s *Store, from, to string) error {
	err := renameReal(s, from, to)
	if err == nil {
		_ = s.Add(from, 0)
	}
	return err
}'
wrap "RenameAll swallows a missing member" RenameAll renameAllReal 'package members

import "errors"

func RenameAll(s *Store, pairs []Pair) error {
	err := renameAllReal(s, pairs)
	if errors.Is(err, ErrNotFound) {
		return nil
	}
	return err
}'
wrap "RenameAll keeps going after a failure" RenameAll renameAllReal 'package members

import "fmt"

func RenameAll(s *Store, pairs []Pair) error {
	var first error
	for i, p := range pairs {
		if err := Rename(s, p.From, p.To); err != nil && first == nil {
			first = fmt.Errorf("pair %d: %w", i+1, err)
		}
	}
	return first
}'
wrap "ParsePairs skips bad lines" ParsePairs parsePairsReal 'package members

import "errors"

func ParsePairs(text string) ([]Pair, error) {
	pairs, err := parsePairsReal(text)
	if errors.Is(err, ErrBadLine) {
		return nil, nil
	}
	return pairs, err
}'
wrap "ParsePairs leaves a trailing space" ParsePairs parsePairsReal 'package members

func ParsePairs(text string) ([]Pair, error) {
	pairs, err := parsePairsReal(text)
	for i := range pairs {
		pairs[i].To += " "
	}
	return pairs, err
}'

# ---- hidden behaviour ---------------------------------------------------------
run_hidden() { # <tree dir> [go test -run pattern]
	cp "$CASE_DIR/hidden/zz_hidden_test.go" "$1/internal/members/zz_hidden_test.go"
	(cd "$1" && go test -count=1 ${2:+-run "$2"} ./internal/members/ >/tmp/xgo-hidden.$$ 2>&1)
	local rc=$?
	rm -f "$1/internal/members/zz_hidden_test.go"
	return $rc
}
if ! run_hidden .; then
	tail -n 12 /tmp/xgo-hidden.$$
	rm -f /tmp/xgo-hidden.$$
	die "hidden behaviour tests failed"
fi
# reuse is real: with Flatten broken (upper-casing), ParsePairs must follow it
dir=$(mktemp -d)
TMPS+=("$dir")
cp -a . "$dir/t"
cat >"$dir/t/internal/textutil/textutil.go" <<'GO'
package textutil

import "strings"

func Flatten(s string) string {
	return strings.ToUpper(strings.Join(strings.Fields(s), " "))
}

func PadRight(s string, n int) string { return s }

func Clip(s string, n int) string { return s }
GO
if run_hidden "$dir/t" 'TestHiddenParsePairs'; then
	rm -f /tmp/xgo-hidden.$$
	die "ParsePairs does not depend on textutil.Flatten: reuse is faked"
fi
rm -f /tmp/xgo-hidden.$$

# ---- slop ---------------------------------------------------------------------
# shellcheck disable=SC2086
slop_check --all-lines --no-tools --files $NEW_SRC $NEW_TESTS
