#!/usr/bin/env python3
"""size_guard.py — heuristic file/function-length checker for size-guard.sh.

Usage: size_guard.py <file> <maxFileLines> <maxFuncLines>

Counts total lines in <file> and the line-span of every recognised function
signature (def/fn/func/function/method-like), heuristically closed at the
next line whose indentation is <= the signature's own indentation and which
is neither blank nor a comment. A signature line is never one whose first
token is a control-flow keyword (return/if/else/for/while/switch/case/
catch/try/with/match/...), so a bare `return (` opening a multi-line JSX
block is never mistaken for a function.

Prints one line per problem to stderr and exits 2 when any problem is
found; exits 0 otherwise, including on any I/O error, binary/undecodable
content, or bad arguments (this tool must never crash a hook).
"""
import re
import sys

CONTROL_KEYWORDS = {
    "return", "if", "elif", "else", "for", "while", "switch", "case",
    "catch", "try", "with", "match", "except", "finally", "do", "when",
    "default", "break", "continue", "yield", "raise", "throw", "await",
}

# Ordered signature patterns. Each must expose named groups "indent" and
# "name"; "name" is checked against CONTROL_KEYWORDS too so a construct
# like `for (...)` never slips through even if a later pattern would
# otherwise match its shape.
_PATTERNS = [
    # Python def (optionally async)
    re.compile(r"^(?P<indent>[ \t]*)(?:async\s+)?def\s+(?P<name>[A-Za-z_]\w*)\s*\("),
    # Rust fn
    re.compile(r"^(?P<indent>[ \t]*)(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+(?P<name>[A-Za-z_]\w*)\s*[<(]"),
    # Go func (with optional receiver)
    re.compile(r"^(?P<indent>[ \t]*)func\s+(?:\([^)]*\)\s*)?(?P<name>[A-Za-z_]\w*)\s*\("),
    # JS/TS function declarations (optionally exported/default/async/generator)
    re.compile(r"^(?P<indent>[ \t]*)(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s+(?P<name>[A-Za-z_]\w*)\s*\("),
    # JS/TS arrow function assigned to const/let/var, multi-arg or zero-arg
    re.compile(r"^(?P<indent>[ \t]*)(?:export\s+)?(?:const|let|var)\s+(?P<name>[A-Za-z_]\w*)\s*(?::[^=]+)?=\s*(?:async\s+)?\([^)]*\)\s*(?::[^=]+)?=>"),
    # JS/TS arrow function, single bare-identifier argument
    re.compile(r"^(?P<indent>[ \t]*)(?:export\s+)?(?:const|let|var)\s+(?P<name>[A-Za-z_]\w*)\s*=\s*(?:async\s+)?[A-Za-z_]\w*\s*=>"),
    # Method-like: identifier(...) { or identifier(...) : Type {  (class
    # methods, object method shorthand, Go-less brace-language methods).
    re.compile(r"^(?P<indent>[ \t]*)(?:public\s+|private\s+|protected\s+|static\s+|async\s+)*(?P<name>[A-Za-z_]\w*)\s*\([^()]*\)\s*(?:->\s*[^{:]+|:\s*[^{]+)?\{\s*$"),
]

_FIRST_TOKEN_RE = re.compile(r"[A-Za-z_]\w*")


def match_signature(line):
    stripped = line.lstrip(" \t")
    m = _FIRST_TOKEN_RE.match(stripped)
    first_token = m.group(0) if m else ""
    if first_token in CONTROL_KEYWORDS:
        return None
    for pat in _PATTERNS:
        mm = pat.match(line)
        if mm:
            name = mm.group("name")
            if name in CONTROL_KEYWORDS:
                continue
            indent = mm.group("indent")
            return len(indent), name
    return None


def indent_of(line):
    stripped = line.lstrip(" \t")
    return len(line) - len(stripped)


def is_blank_or_comment(line):
    s = line.strip()
    if not s:
        return True
    for prefix in ("#", "//", "/*", "*", "*/"):
        if s.startswith(prefix):
            return True
    return False


def scan(lines):
    problems = []
    n = len(lines)
    i = 0
    while i < n:
        sig = match_signature(lines[i])
        if sig:
            indent, name = sig
            j = i + 1
            while j < n:
                cand = lines[j]
                if is_blank_or_comment(cand):
                    j += 1
                    continue
                if indent_of(cand) <= indent:
                    break
                j += 1
            span = j - i
            problems.append((i + 1, "func", name, span))
        i += 1
    return problems


def main():
    args = sys.argv[1:]
    if "-h" in args or "--help" in args:
        sys.stdout.write(__doc__ or "")
        sys.exit(0)
    if len(args) != 3:
        # Never crash a hook on bad invocation; just decline to judge.
        sys.exit(0)
    path, max_file_s, max_func_s = args
    try:
        max_file = int(max_file_s)
        max_func = int(max_func_s)
    except ValueError:
        sys.exit(0)

    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except Exception:
        sys.exit(0)

    if b"\x00" in raw:
        # Binary file — never judge these.
        sys.exit(0)

    try:
        text = raw.decode("utf-8")
    except Exception:
        sys.exit(0)

    lines = text.splitlines()
    total = len(lines)

    messages = []
    if total > max_file:
        messages.append(
            "{}: file is {} lines (max {}). Consider splitting it into smaller modules.".format(
                path, total, max_file
            )
        )

    for lineno, _kind, name, span in scan(lines):
        if span > max_func:
            messages.append(
                "{}:{}: function '{}' is {} lines (max {}). Consider splitting it.".format(
                    path, lineno, name, span, max_func
                )
            )

    if messages:
        sys.stderr.write("size-guard found issues:\n")
        for m in messages:
            sys.stderr.write(m + "\n")
        sys.stderr.write(
            "Large files and functions are hard to review and test; split before continuing.\n"
        )
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
