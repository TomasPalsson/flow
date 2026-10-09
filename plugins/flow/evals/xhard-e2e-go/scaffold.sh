#!/usr/bin/env bash
set -euo pipefail
# This script ends in `git add -A; git commit`. Run by hand from a checkout
# instead of the eval runner's scratch copy, that would sweep the invoking
# repo's whole working tree into one commit under a fake author identity.
# `claude plugin eval --scaffold` nests this case's cwd inside its own
# throwaway HOME, which is itself an empty `git init` (no commits, user.email
# eval@example.invalid) so `--is-inside-work-tree` alone is true there too.
# Only refuse when that work tree already has a commit, which the real
# invoking checkout always does and the eval sandbox's placeholder never does.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
git init -q
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false

_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p internal/textutil internal/members internal/report cmd/clubroll .claude
cat >.gitignore <<'GI'
*.test
.specs/.next-call-count
GI
cat >.claude/flow.config.json <<'JSON'
{
  "requireSpec": true
}
JSON
cat >go.mod <<'MOD'
module example.com/clubroll

go 1.22
MOD
cat >README.md <<'MD'
# clubroll

Membership roster for a small sports club: who is a member and what dues they owe.

- Tests: `go test ./...`
- Static checks: `go vet ./...` (both must be clean before anything lands)
- Standard library only: no third-party modules, no network.
- Layout: `internal/members` (the roster store), `internal/textutil` (shared string
  helpers), `internal/report` (plain-text tables), `cmd/clubroll` (the tool).
MD

# --- commit 1: shared string helpers -------------------------------------------
cat >internal/textutil/textutil.go <<'GO'
package textutil

import "strings"

// Flatten trims s and collapses every run of whitespace, tabs and newlines
// included, into a single space.
func Flatten(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

// PadRight pads s with spaces to n runes; a longer s is returned as it is.
func PadRight(s string, n int) string {
	if gap := n - len([]rune(s)); gap > 0 {
		return s + strings.Repeat(" ", gap)
	}
	return s
}

// Clip cuts s to at most n runes.
func Clip(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}
GO
cat >internal/textutil/textutil_test.go <<'GO'
package textutil

import "testing"

func TestFlattenCollapsesRunsAndTrims(t *testing.T) {
	if got := Flatten("  Ann \t Lee\n"); got != "Ann Lee" {
		t.Fatalf("Flatten = %q, want %q", got, "Ann Lee")
	}
}

func TestPadRightPadsShortText(t *testing.T) {
	if got := PadRight("ab", 4); got != "ab  " {
		t.Fatalf("PadRight = %q", got)
	}
}

func TestClipCutsLongText(t *testing.T) {
	if got := Clip("abcdef", 3); got != "abc" {
		t.Fatalf("Clip = %q", got)
	}
}
GO
commit "textutil: string helpers"

# --- commit 2: the roster store -------------------------------------------------
cat >internal/members/store.go <<'GO'
package members

import (
	"errors"
	"sort"

	"example.com/clubroll/internal/textutil"
)

var (
	ErrBlank    = errors.New("members: blank name")
	ErrExists   = errors.New("members: already a member")
	ErrNotFound = errors.New("members: no such member")
)

type Member struct {
	Name      string
	DuesCents int
}

type Store struct {
	byName map[string]Member
}

func NewStore() *Store {
	return &Store{byName: map[string]Member{}}
}

func (s *Store) Add(name string, duesCents int) error {
	key := textutil.Flatten(name)
	if key == "" {
		return ErrBlank
	}
	if _, ok := s.byName[key]; ok {
		return ErrExists
	}
	s.byName[key] = Member{Name: key, DuesCents: duesCents}
	return nil
}

func (s *Store) Get(name string) (Member, error) {
	m, ok := s.byName[textutil.Flatten(name)]
	if !ok {
		return Member{}, ErrNotFound
	}
	return m, nil
}

func (s *Store) Remove(name string) error {
	key := textutil.Flatten(name)
	if _, ok := s.byName[key]; !ok {
		return ErrNotFound
	}
	delete(s.byName, key)
	return nil
}

func (s *Store) Names() []string {
	names := make([]string, 0, len(s.byName))
	for name := range s.byName {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
GO
cat >internal/members/store_test.go <<'GO'
package members

import (
	"errors"
	"reflect"
	"testing"
)

func TestAddCanonicalizesTheName(t *testing.T) {
	s := NewStore()
	if err := s.Add("  Ann   Lee ", 1200); err != nil {
		t.Fatal(err)
	}
	m, err := s.Get("Ann Lee")
	if err != nil || m.Name != "Ann Lee" || m.DuesCents != 1200 {
		t.Fatalf("Get = %+v, %v", m, err)
	}
}

func TestAddRejectsBlankAndDuplicateNames(t *testing.T) {
	s := NewStore()
	if err := s.Add("   ", 0); !errors.Is(err, ErrBlank) {
		t.Fatalf("blank name: %v", err)
	}
	if err := s.Add("Bo", 0); err != nil {
		t.Fatal(err)
	}
	if err := s.Add("Bo  ", 5); !errors.Is(err, ErrExists) {
		t.Fatalf("duplicate name: %v", err)
	}
}

func TestRemoveDropsTheMember(t *testing.T) {
	s := NewStore()
	if err := s.Add("Bo", 0); err != nil {
		t.Fatal(err)
	}
	if err := s.Remove(" Bo "); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Get("Bo"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Get after Remove: %v", err)
	}
	if err := s.Remove("Bo"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("second Remove: %v", err)
	}
}

func TestNamesAreSorted(t *testing.T) {
	s := NewStore()
	if err := s.Add("Cy", 0); err != nil {
		t.Fatal(err)
	}
	if err := s.Add("Ann", 0); err != nil {
		t.Fatal(err)
	}
	if got := s.Names(); !reflect.DeepEqual(got, []string{"Ann", "Cy"}) {
		t.Fatalf("Names = %v", got)
	}
}
GO
commit "members: the roster store"

# --- commit 3: report and the tool ---------------------------------------------
cat >internal/report/report.go <<'GO'
package report

import (
	"fmt"
	"strings"

	"example.com/clubroll/internal/members"
	"example.com/clubroll/internal/textutil"
)

// Dues renders one row per member: a 20-column name, then the dues in dollars.
func Dues(s *members.Store) string {
	var b strings.Builder
	for _, name := range s.Names() {
		m, _ := s.Get(name)
		fmt.Fprintf(&b, "%s %6.2f\n", textutil.PadRight(textutil.Clip(m.Name, 20), 20), float64(m.DuesCents)/100)
	}
	return b.String()
}
GO
cat >internal/report/report_test.go <<'GO'
package report

import (
	"testing"

	"example.com/clubroll/internal/members"
)

func TestDuesRendersOneRowPerMember(t *testing.T) {
	s := members.NewStore()
	if err := s.Add("Ann Lee", 1250); err != nil {
		t.Fatal(err)
	}
	want := "Ann Lee               12.50\n"
	if got := Dues(s); got != want {
		t.Fatalf("Dues = %q, want %q", got, want)
	}
}
GO
cat >cmd/clubroll/main.go <<'GO'
package main

import (
	"fmt"

	"example.com/clubroll/internal/members"
	"example.com/clubroll/internal/report"
)

func main() {
	s := members.NewStore()
	for name, dues := range map[string]int{"Ann Lee": 1250, "Bo Nyx": 900} {
		if err := s.Add(name, dues); err != nil {
			fmt.Println(err)
			return
		}
	}
	fmt.Print(report.Dues(s))
}
GO
if [ -n "$(gofmt -l .)" ]; then
	echo "scaffold.sh: fixture is not gofmt-clean" >&2
	exit 1
fi
go vet ./... >/dev/null
go test ./... >/dev/null
commit "report: dues table and the tool"
