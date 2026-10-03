package members_test

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"example.com/clubroll/internal/members"
)

func hiddenRoster(t *testing.T) *members.Store {
	t.Helper()
	s := members.NewStore()
	for name, dues := range map[string]int{"Ann Lee": 1200, "Bo Nyx": 900} {
		if err := s.Add(name, dues); err != nil {
			t.Fatal(err)
		}
	}
	return s
}

func hiddenUnchanged(t *testing.T, s *members.Store) {
	t.Helper()
	if got := s.Names(); !reflect.DeepEqual(got, []string{"Ann Lee", "Bo Nyx"}) {
		t.Fatalf("roster changed: %v", got)
	}
	if m, _ := s.Get("Ann Lee"); m.DuesCents != 1200 {
		t.Fatalf("Ann Lee's dues changed: %+v", m)
	}
	if m, _ := s.Get("Bo Nyx"); m.DuesCents != 900 {
		t.Fatalf("Bo Nyx's dues changed: %+v", m)
	}
}

func hiddenWrapped(t *testing.T, err, sentinel error) {
	t.Helper()
	if !errors.Is(err, sentinel) {
		t.Fatalf("error %v does not wrap %v", err, sentinel)
	}
	if err == sentinel {
		t.Fatalf("error %v is the bare sentinel: it carries no context", err)
	}
	if !strings.Contains(err.Error(), sentinel.Error()) {
		t.Fatalf("error %q lost the sentinel text", err)
	}
}

func TestHiddenRenameMovesMemberAndKeepsDues(t *testing.T) {
	s := hiddenRoster(t)
	if err := members.Rename(s, "  Ann   Lee ", "Anne\tLee"); err != nil {
		t.Fatal(err)
	}
	if got := s.Names(); !reflect.DeepEqual(got, []string{"Anne Lee", "Bo Nyx"}) {
		t.Fatalf("Names = %v", got)
	}
	if m, err := s.Get("Anne Lee"); err != nil || m.DuesCents != 1200 || m.Name != "Anne Lee" {
		t.Fatalf("Get(Anne Lee) = %+v, %v", m, err)
	}
	if _, err := s.Get("Ann Lee"); !errors.Is(err, members.ErrNotFound) {
		t.Fatalf("old name still present: %v", err)
	}
}

func TestHiddenRenameToSameCanonicalNameIsANoOp(t *testing.T) {
	s := hiddenRoster(t)
	if err := members.Rename(s, "Ann Lee", "  Ann    Lee\n"); err != nil {
		t.Fatalf("renaming to the same canonical name: %v", err)
	}
	hiddenUnchanged(t, s)
}

func TestHiddenRenameFromMissingMemberWrapsErrNotFound(t *testing.T) {
	s := hiddenRoster(t)
	err := members.Rename(s, "Zed", "Cy")
	hiddenWrapped(t, err, members.ErrNotFound)
	hiddenUnchanged(t, s)
	err = members.Rename(s, "Zed", "Zed")
	hiddenWrapped(t, err, members.ErrNotFound)
}

func TestHiddenRenameOntoExistingMemberWrapsErrExists(t *testing.T) {
	s := hiddenRoster(t)
	err := members.Rename(s, "Ann Lee", " Bo   Nyx")
	hiddenWrapped(t, err, members.ErrExists)
	hiddenUnchanged(t, s)
}

func TestHiddenRenameToBlankWrapsErrBlank(t *testing.T) {
	s := hiddenRoster(t)
	err := members.Rename(s, "Ann Lee", " \t ")
	hiddenWrapped(t, err, members.ErrBlank)
	hiddenUnchanged(t, s)
}

func TestHiddenParsePairsCanonicalizesBothSidesAndSkipsBlankLines(t *testing.T) {
	text := "Ann  Lee -> Anne\tLee\n\n   \n  Bo   Nyx  ->  Bea  \n"
	got, err := members.ParsePairs(text)
	if err != nil {
		t.Fatal(err)
	}
	want := []members.Pair{{From: "Ann Lee", To: "Anne Lee"}, {From: "Bo Nyx", To: "Bea"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ParsePairs = %#v, want %#v", got, want)
	}
}

func TestHiddenParsePairsRejectsMalformedLinesWithTheLineNumber(t *testing.T) {
	cases := map[string]string{
		"no arrow":      "Ann -> Bea\nAnn Bea\n",
		"blank left":    "Ann -> Bea\n -> Cy\n",
		"blank right":   "Ann -> Bea\nCy ->   \n",
		"two arrows":    "Ann -> Bea\nCy -> Di -> Ed\n",
		"after a blank": "\n\nAnn Bea\n",
	}
	lines := map[string]string{"no arrow": "line 2", "blank left": "line 2", "blank right": "line 2", "two arrows": "line 2", "after a blank": "line 3"}
	for name, text := range cases {
		got, err := members.ParsePairs(text)
		if !errors.Is(err, members.ErrBadLine) {
			t.Fatalf("%s: error %v does not wrap ErrBadLine", name, err)
		}
		if err == members.ErrBadLine || !strings.Contains(err.Error(), lines[name]) {
			t.Fatalf("%s: error %q does not name %s", name, err, lines[name])
		}
		if got != nil {
			t.Fatalf("%s: got pairs %v with an error", name, got)
		}
	}
}

func TestHiddenParsePairsOfNothingIsEmpty(t *testing.T) {
	got, err := members.ParsePairs("\n  \n")
	if err != nil || len(got) != 0 {
		t.Fatalf("ParsePairs(blank) = %v, %v", got, err)
	}
}

func TestHiddenRenameAllAppliesPairsInOrder(t *testing.T) {
	s := hiddenRoster(t)
	pairs := []members.Pair{{From: "Ann Lee", To: "Anne Lee"}, {From: "Anne  Lee", To: "Ann"}}
	if err := members.RenameAll(s, pairs); err != nil {
		t.Fatal(err)
	}
	if got := s.Names(); !reflect.DeepEqual(got, []string{"Ann", "Bo Nyx"}) {
		t.Fatalf("Names = %v", got)
	}
	if m, _ := s.Get("Ann"); m.DuesCents != 1200 {
		t.Fatalf("dues lost along the chain: %+v", m)
	}
}

func TestHiddenRenameAllStopsAtTheFirstFailureAndNamesThePair(t *testing.T) {
	s := hiddenRoster(t)
	pairs := []members.Pair{
		{From: "Ann Lee", To: "Anne Lee"},
		{From: "Zed", To: "Cy"},
		{From: "Bo Nyx", To: "Bea"},
	}
	err := members.RenameAll(s, pairs)
	hiddenWrapped(t, err, members.ErrNotFound)
	if !strings.Contains(err.Error(), "pair 2") {
		t.Fatalf("error %q does not name pair 2", err)
	}
	if got := s.Names(); !reflect.DeepEqual(got, []string{"Anne Lee", "Bo Nyx"}) {
		t.Fatalf("after the failure Names = %v: pair 1 must stay applied and pair 3 must not run", got)
	}
}

func TestHiddenRenameAllWrapsErrExists(t *testing.T) {
	s := hiddenRoster(t)
	err := members.RenameAll(s, []members.Pair{{From: "Ann Lee", To: "Bo Nyx"}})
	hiddenWrapped(t, err, members.ErrExists)
	if !strings.Contains(err.Error(), "pair 1") {
		t.Fatalf("error %q does not name pair 1", err)
	}
	hiddenUnchanged(t, s)
}
