#!/usr/bin/env bash
# What a perfect run leaves on disk: spec + TASKS drafted around go test / go vet,
# approved at the gate, three committed tasks ticked through `flow tick`, the new
# code built on textutil.Flatten with every error wrapped, gates green, PASS for
# HEAD, and NO Verified: line (that fact is the human's).
set -euo pipefail
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
TODAY=$(date +%F)
BASE=$(git rev-parse --short HEAD)

bash "$EVAL_PLUGIN_ROOT/scripts/new-spec" "Roster renames" --dir .specs --current --no-branch >/dev/null
SPEC=.specs/001-roster-renames
mkdir -p "$SPEC"

cat >"$SPEC/spec.md" <<'MD'
# Spec: Roster renames

**Created**: 2026-09-29 · **Route**: dispatch

## TL;DR

**Problem**: Club secretaries fix misspelt names by removing and re-adding a member, which loses their dues.
**Solution**: A rename that moves a member to a new name and keeps their dues, plus a bulk form driven by a text list.
**Who it's for**: The club secretary.
**Key decision**: Names are matched the way the roster already canonicalizes them; every failure keeps the roster's own sentinel error visible through errors.Is.

## 2. Scope

### 2.1 In scope
- `members.Rename`, `members.ParsePairs`, `members.RenameAll`, `members.Pair` and `members.ErrBadLine`.

### 2.2 Non-goals
- No change to the existing Store API, to textutil or to the report.
- No new dependencies.

## 4. Requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | Rename moves a member and keeps their dues; a failed rename changes nothing | test on success and on each failure |
| FR-02 | MUST | Rename to the same canonical name is a no-op returning nil | test with extra whitespace |
| FR-03 | MUST | Rename failures wrap ErrNotFound, ErrExists or ErrBlank with context | errors.Is test |
| FR-04 | MUST | ParsePairs reads one `old -> new` per line, canonicalizes both sides, skips blank lines | test on messy input |
| FR-05 | MUST | A malformed line stops ParsePairs with an error wrapping ErrBadLine and naming `line N` | test per malformation |
| FR-06 | MUST | RenameAll applies pairs in order, stops at the first failure wrapped with `pair N` | test with a failing middle pair |

## 7. Assumptions

| # | Assumption | Confidence | Blast radius if wrong |
|---|------------|-----------|-----------------------|
| A1 | textutil.Flatten is the roster's canonical name form | High | Renames disagree with Add and Get |
MD

cat >"$SPEC/TASKS.md" <<MD
# Tasks — Roster renames
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`go vet ./... && go test ./...\`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a member, when renamed, then the new name carries the dues and the old is gone | T001 | TestRenameMovesMember |
| B2 (P0) | Given a rename that cannot happen, when it runs, then the roster's sentinel error is wrapped and nothing changes | T001 | TestRenameFailuresWrapSentinels |
| B3 (P0) | Given a text list, when parsed, then pairs come back canonical and a bad line names itself | T002 | TestParsePairs |
| B4 (P0) | Given pairs, when applied, then they run in order and stop at the first failure | T003 | TestRenameAll |

## Phase 1 — Rename and parse
Goal: a single member can be renamed and a rename list can be read.
Independent test: \`go test ./internal/members -run 'TestRename|TestParsePairs'\` — green with RenameAll absent.
- [ ] T001 Rename (B1, B2) — files: internal/members/rename.go, internal/members/rename_test.go — verify: \`go test ./internal/members -run TestRename\`
- [ ] T002 [P] ParsePairs, Pair and ErrBadLine (B3) — files: internal/members/pairs.go, internal/members/pairs_test.go — verify: \`go test ./internal/members -run TestParsePairs\`

## Phase 2 — Bulk rename
Goal: a whole list of renames applies to the roster in one call.
Independent test: \`go test ./...\` — whole module green.
- [ ] T003 RenameAll (B4) — files: internal/members/renameall.go, internal/members/renameall_test.go — verify: \`go test ./internal/members -run TestRenameAll\` — after: T001, T002

## Gates
- [ ] G001 project gates clean — files: . — verify: \`go vet ./... && go test ./...\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD

# approval gate: the user said go
{ head -2 "$SPEC/TASKS.md"; echo "Approved: $TODAY by user"; tail -n +3 "$SPEC/TASKS.md"; } >"$SPEC/TASKS.new"
mv "$SPEC/TASKS.new" "$SPEC/TASKS.md"

# ---- T001
cat >internal/members/rename.go <<'GO'
package members

import (
	"fmt"

	"example.com/clubroll/internal/textutil"
)

func Rename(s *Store, from, to string) error {
	m, err := s.Get(from)
	if err != nil {
		return fmt.Errorf("rename %q: %w", from, err)
	}
	if textutil.Flatten(from) == textutil.Flatten(to) {
		return nil
	}
	if err := s.Add(to, m.DuesCents); err != nil {
		return fmt.Errorf("rename %q to %q: %w", from, to, err)
	}
	if err := s.Remove(from); err != nil {
		return fmt.Errorf("rename %q: %w", from, err)
	}
	return nil
}
GO
cat >internal/members/rename_test.go <<'GO'
package members

import (
	"errors"
	"reflect"
	"testing"
)

func renameFixture(t *testing.T) *Store {
	t.Helper()
	s := NewStore()
	if err := s.Add("Ann Lee", 1200); err != nil {
		t.Fatal(err)
	}
	if err := s.Add("Bo Nyx", 900); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestRenameMovesMemberAndKeepsDues(t *testing.T) {
	s := renameFixture(t)
	if err := Rename(s, " Ann  Lee", "Anne Lee"); err != nil {
		t.Fatal(err)
	}
	m, err := s.Get("Anne Lee")
	if err != nil || m.DuesCents != 1200 {
		t.Fatalf("Get(Anne Lee) = %+v, %v", m, err)
	}
	if _, err := s.Get("Ann Lee"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("the old name is still a member: %v", err)
	}
}

func TestRenameToTheSameCanonicalNameChangesNothing(t *testing.T) {
	s := renameFixture(t)
	if err := Rename(s, "Ann Lee", "Ann   Lee "); err != nil {
		t.Fatalf("Rename to itself: %v", err)
	}
	if got := s.Names(); !reflect.DeepEqual(got, []string{"Ann Lee", "Bo Nyx"}) {
		t.Fatalf("Names = %v", got)
	}
}

func TestRenameFailuresWrapSentinelsAndChangeNothing(t *testing.T) {
	cases := []struct {
		name     string
		from, to string
		want     error
	}{
		{"missing member", "Zed", "Cy", ErrNotFound},
		{"name taken", "Ann Lee", "Bo  Nyx", ErrExists},
		{"blank target", "Ann Lee", "  ", ErrBlank},
	}
	for _, c := range cases {
		s := renameFixture(t)
		err := Rename(s, c.from, c.to)
		if !errors.Is(err, c.want) || err == c.want {
			t.Fatalf("%s: error %v does not wrap %v with context", c.name, err, c.want)
		}
		if got := s.Names(); !reflect.DeepEqual(got, []string{"Ann Lee", "Bo Nyx"}) {
			t.Fatalf("%s: roster changed to %v", c.name, got)
		}
	}
}
GO
go vet ./... >/dev/null
go test ./internal/members -run TestRename >/dev/null
git add internal/members/rename.go internal/members/rename_test.go
git commit -q -m "members: Rename keeps a member's dues under the new name"
$FLOW tick T001

# ---- T002
cat >internal/members/pairs.go <<'GO'
package members

import (
	"errors"
	"fmt"
	"strings"

	"example.com/clubroll/internal/textutil"
)

var ErrBadLine = errors.New("members: bad roster line")

type Pair struct {
	From, To string
}

func ParsePairs(text string) ([]Pair, error) {
	var pairs []Pair
	for i, line := range strings.Split(text, "\n") {
		if textutil.Flatten(line) == "" {
			continue
		}
		sides := strings.Split(line, "->")
		if len(sides) != 2 {
			return nil, fmt.Errorf("line %d: %w: want one \"old -> new\"", i+1, ErrBadLine)
		}
		from, to := textutil.Flatten(sides[0]), textutil.Flatten(sides[1])
		if from == "" || to == "" {
			return nil, fmt.Errorf("line %d: %w: a name is blank", i+1, ErrBadLine)
		}
		pairs = append(pairs, Pair{From: from, To: to})
	}
	return pairs, nil
}
GO
cat >internal/members/pairs_test.go <<'GO'
package members

import (
	"errors"
	"reflect"
	"strings"
	"testing"
)

func TestParsePairsCanonicalizesAndSkipsBlankLines(t *testing.T) {
	got, err := ParsePairs("Ann  Lee -> Anne\tLee\n\n  \n Bo   Nyx ->  Bea \n")
	if err != nil {
		t.Fatal(err)
	}
	want := []Pair{{From: "Ann Lee", To: "Anne Lee"}, {From: "Bo Nyx", To: "Bea"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ParsePairs = %#v, want %#v", got, want)
	}
}

func TestParsePairsRejectsBadLinesWithTheirNumber(t *testing.T) {
	cases := map[string]string{
		"no arrow":    "Ann -> Bea\nAnn Bea\n",
		"blank left":  "Ann -> Bea\n -> Cy\n",
		"blank right": "Ann -> Bea\nCy -> \n",
		"two arrows":  "Ann -> Bea\nCy -> Di -> Ed\n",
	}
	for name, text := range cases {
		got, err := ParsePairs(text)
		if !errors.Is(err, ErrBadLine) || !strings.Contains(err.Error(), "line 2") {
			t.Fatalf("%s: error %v does not wrap ErrBadLine and name line 2", name, err)
		}
		if got != nil {
			t.Fatalf("%s: returned pairs %v alongside the error", name, got)
		}
	}
}
GO
go vet ./... >/dev/null
go test ./internal/members -run TestParsePairs >/dev/null
git add internal/members/pairs.go internal/members/pairs_test.go
git commit -q -m "members: ParsePairs reads a rename list"
$FLOW tick T002

# ---- Phase 1 boundary: its Independent test, executed
go test ./internal/members -run 'TestRename|TestParsePairs' >/dev/null

# ---- T003
cat >internal/members/renameall.go <<'GO'
package members

import "fmt"

func RenameAll(s *Store, pairs []Pair) error {
	for i, p := range pairs {
		if err := Rename(s, p.From, p.To); err != nil {
			return fmt.Errorf("pair %d: %w", i+1, err)
		}
	}
	return nil
}
GO
cat >internal/members/renameall_test.go <<'GO'
package members

import (
	"errors"
	"reflect"
	"strings"
	"testing"
)

func TestRenameAllAppliesPairsInOrder(t *testing.T) {
	s := renameFixture(t)
	pairs := []Pair{{From: "Ann Lee", To: "Anne Lee"}, {From: "Anne Lee", To: "Ann"}}
	if err := RenameAll(s, pairs); err != nil {
		t.Fatal(err)
	}
	if got := s.Names(); !reflect.DeepEqual(got, []string{"Ann", "Bo Nyx"}) {
		t.Fatalf("Names = %v", got)
	}
}

func TestRenameAllStopsAtTheFirstFailure(t *testing.T) {
	s := renameFixture(t)
	pairs := []Pair{
		{From: "Ann Lee", To: "Anne Lee"},
		{From: "Zed", To: "Cy"},
		{From: "Bo Nyx", To: "Bea"},
	}
	err := RenameAll(s, pairs)
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("error %v does not wrap ErrNotFound", err)
	}
	if got := s.Names(); !reflect.DeepEqual(got, []string{"Anne Lee", "Bo Nyx"}) {
		t.Fatalf("Names = %v: pair 1 stays applied, pair 3 must not run", got)
	}
}

func TestRenameAllNamesTheFailingPair(t *testing.T) {
	s := renameFixture(t)
	err := RenameAll(s, []Pair{{From: "Ann Lee", To: "Bo Nyx"}})
	if !errors.Is(err, ErrExists) {
		t.Fatalf("error %v does not wrap ErrExists", err)
	}
	if !strings.HasPrefix(err.Error(), "pair 1") {
		t.Fatalf("error %q does not lead with the pair number", err)
	}
}
GO
go vet ./... >/dev/null
go test ./... >/dev/null
git add internal/members/renameall.go internal/members/renameall_test.go
git commit -q -m "members: RenameAll applies a list of renames in order"
$FLOW tick T003

# ---- gates
go vet ./... >/dev/null
go test ./... >/dev/null
HEAD_SHA=$(git rev-parse --short HEAD)
cat >"$SPEC/PASS-$HEAD_SHA.md" <<MD
# PASS $HEAD_SHA
- G001 \`go vet ./...\` — exit 0
- G001 \`go test ./...\` — exit 0
- G002 branch review — no findings above threshold
MD
$FLOW tick G001
$FLOW tick G002
git add "$SPEC"
git commit -q -m "specs: roster renames plan, tasks ticked, PASS"
