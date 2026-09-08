#!/usr/bin/env python3
"""size_guard.py — heuristic file/function-length checker for size-guard.sh.

Usage: size_guard.py <file> <maxFileLines> <maxFuncLines> [--baseline <path>]

Counts total lines in <file> and the line-span of every recognised function
signature (def/fn/func/function/method-like), heuristically closed at the
next line whose indentation is <= the signature's own indentation and which
is neither blank nor a comment. A signature line is never one whose first
token is a control-flow keyword (return/if/else/for/while/switch/case/
catch/try/with/match/...), so a bare `return (` opening a multi-line JSX
block is never mistaken for a function. A function whose whole body is one
`return ( ... )` JSX expression is exempt from the function limit: splitting
markup at an arbitrary line does not make it easier to review.

<--baseline path> is the same file as it looked BEFORE the edit ("" when
there is no baseline, i.e. a new file). Only a problem this edit introduced
is reported: crossing a limit, or growing something that was already over.
An oversized file left alone or made smaller is silent.

Prints one line per problem to stderr and exits 2 when any problem is
found; exits 0 otherwise, including on any I/O error, binary/undecodable
content, or bad arguments (this tool must never crash a hook).
"""

import re
import sys

CONTROL_KEYWORDS = {
    "return",
    "if",
    "elif",
    "else",
    "for",
    "while",
    "switch",
    "case",
    "catch",
    "try",
    "with",
    "match",
    "except",
    "finally",
    "do",
    "when",
    "default",
    "break",
    "continue",
    "yield",
    "raise",
    "throw",
    "await",
}

# Ordered signature patterns. Each must expose named groups "indent" and
# "name"; "name" is checked against CONTROL_KEYWORDS too so a construct
# like `for (...)` never slips through even if a later pattern would
# otherwise match its shape.
_PATTERNS = [
    # Python def (optionally async)
    re.compile(r"^(?P<indent>[ \t]*)(?:async\s+)?def\s+(?P<name>[A-Za-z_]\w*)\s*\("),
    # Rust fn
    re.compile(
        r"^(?P<indent>[ \t]*)(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+(?P<name>[A-Za-z_]\w*)\s*[<(]"
    ),
    # Go func (with optional receiver)
    re.compile(
        r"^(?P<indent>[ \t]*)func\s+(?:\([^)]*\)\s*)?(?P<name>[A-Za-z_]\w*)\s*\("
    ),
    # JS/TS function declarations (optionally exported/default/async/generator)
    re.compile(
        r"^(?P<indent>[ \t]*)(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s+(?P<name>[A-Za-z_]\w*)\s*\("
    ),
    # JS/TS arrow function assigned to const/let/var, multi-arg or zero-arg
    re.compile(
        r"^(?P<indent>[ \t]*)(?:export\s+)?(?:const|let|var)\s+(?P<name>[A-Za-z_]\w*)\s*(?::[^=]+)?=\s*(?:async\s+)?\([^)]*\)\s*(?::[^=]+)?=>"
    ),
    # JS/TS arrow function, single bare-identifier argument
    re.compile(
        r"^(?P<indent>[ \t]*)(?:export\s+)?(?:const|let|var)\s+(?P<name>[A-Za-z_]\w*)\s*=\s*(?:async\s+)?[A-Za-z_]\w*\s*=>"
    ),
    # Method-like: identifier(...) { or identifier(...) : Type {  (class
    # methods, object method shorthand, Go-less brace-language methods).
    re.compile(
        r"^(?P<indent>[ \t]*)(?:public\s+|private\s+|protected\s+|static\s+|async\s+)*(?P<name>[A-Za-z_]\w*)\s*\([^()]*\)\s*(?:->\s*[^{:]+|:\s*[^{]+)?\{\s*$"
    ),
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


_RETURN_OPEN_RE = re.compile(r"^[ \t]*return\s*\($")
_RETURN_CLOSE_RE = re.compile(r"^\)\s*;?$")
_JSX_RE = re.compile(r"<[A-Za-z/>]")


def is_single_jsx_return(lines, start, end):
    """True when the body of the function at <start> is one `return ( <jsx> )`.

    Markup has no meaningful split point, so a component that is nothing but
    its returned tree is exempt from the function-length limit.
    """
    body = [ln for ln in lines[start + 1 : end] if not is_blank_or_comment(ln)]
    if len(body) < 3:
        return False
    if not _RETURN_OPEN_RE.match(body[0].rstrip()):
        return False
    if not _RETURN_CLOSE_RE.match(body[-1].strip()):
        return False
    return any(_JSX_RE.search(ln) for ln in body[1:-1])


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
            # Blank lines and comments between this function and the next one
            # belong to neither: counting them makes a function "grow" when
            # something unrelated is appended after it.
            while j > i + 1 and is_blank_or_comment(lines[j - 1]):
                j -= 1
            if not is_single_jsx_return(lines, i, j):
                problems.append((i + 1, "func", name, j - i))
        i += 1
    return problems


def parse_args(argv):
    """(positionals, baseline). Baseline is "" when the flag is absent."""
    positional = []
    baseline = ""
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--baseline":
            i += 1
            baseline = argv[i] if i < len(argv) else ""
        elif arg.startswith("--baseline="):
            baseline = arg.split("=", 1)[1]
        else:
            positional.append(arg)
        i += 1
    return positional, baseline


def read_lines(path):
    """The file's lines, or None when it cannot or must not be read."""
    if not path:
        return None
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except Exception:
        return None
    if b"\x00" in raw:
        # Binary file — never judge these.
        return None
    try:
        return raw.decode("utf-8").splitlines()
    except Exception:
        return None


def baseline_spans(lines, max_func):
    """{name: over-limit spans before the edit, largest first}.

    A list and not a single number, because one name can belong to several
    functions (`run` on two classes, `main` in two modules). Keeping every
    occurrence is what lets a brand-new over-limit `run` be reported even
    though a different `run` was already too long.
    """
    spans = {}
    for _lineno, _kind, name, span in scan(lines):
        if span > max_func:
            spans.setdefault(name, []).append(span)
    for name in spans:
        spans[name].sort(reverse=True)
    return spans


def _excuse_by_name(over, was):
    """(excused linenos, unmatched functions, per-name spans consumed).

    The current over-limit functions of a name are paired with the baseline's
    ones by rank, largest against largest, so N over-limit `run`s before
    excuse at most N now — the (N+1)-th is something this edit added.
    """
    excused = set()
    unmatched = []
    rank = {}
    used = {}
    for lineno, name, span in sorted(over, key=lambda t: (-t[2], t[0])):
        k = rank.get(name, 0)
        rank[name] = k + 1
        prior = was.get(name, [])
        if k < len(prior) and span <= prior[k]:
            excused.add(lineno)
            used[name] = used.get(name, 0) + 1
        else:
            unmatched.append((lineno, name, span))
    return excused, unmatched, used


def excused_linenos(over, was):
    """Start lines of over-limit functions that were already this long before.

    After the name-keyed pass, whatever is left is matched against the
    baseline spans no name claimed, largest first, one function per span: a
    renamed function is the same code under a new label, and renaming it
    crosses no limit and grows nothing.
    """
    excused, unmatched, used = _excuse_by_name(over, was)
    spare = []
    for name in was:
        spare.extend(was[name][used.get(name, 0) :])
    spare.sort(reverse=True)
    for lineno, _name, span in unmatched:
        for idx in range(len(spare)):
            if span <= spare[idx]:
                excused.add(lineno)
                spare.pop(idx)
                break
    return excused


def problems(path, lines, base_lines, max_file, max_func):
    """The limits THIS edit crossed or made worse, as message lines."""
    messages = []
    total = len(lines)
    base_total = len(base_lines)
    if total > max_file and (base_total <= max_file or total > base_total):
        messages.append(
            "{}: file is {} lines (max {}). Consider splitting it into smaller modules.".format(
                path, total, max_file
            )
        )
    over = [
        (lineno, name, span)
        for lineno, _kind, name, span in scan(lines)
        if span > max_func
    ]
    excused = excused_linenos(over, baseline_spans(base_lines, max_func))
    for lineno, name, span in over:
        if lineno in excused:
            continue
        messages.append(
            "{}:{}: function '{}' is {} lines (max {}). Consider splitting it.".format(
                path, lineno, name, span, max_func
            )
        )
    return messages


def main():
    args = sys.argv[1:]
    if "-h" in args or "--help" in args:
        sys.stdout.write(__doc__ or "")
        sys.exit(0)
    positional, baseline = parse_args(args)
    if len(positional) != 3:
        # Never crash a hook on bad invocation; just decline to judge.
        sys.exit(0)
    path, max_file_s, max_func_s = positional
    try:
        max_file = int(max_file_s)
        max_func = int(max_func_s)
    except ValueError:
        sys.exit(0)

    lines = read_lines(path)
    if lines is None:
        sys.exit(0)
    base_lines = read_lines(baseline)
    if base_lines is None:
        base_lines = []

    messages = problems(path, lines, base_lines, max_file, max_func)
    if messages:
        sys.stderr.write("size-guard found issues:\n")
        for m in messages:
            sys.stderr.write(m + "\n")
        sys.stderr.write(
            "Large files and functions are hard to review and test; split before"
            " continuing. (escape: CC_NO_SIZE_GUARD=1 for this command,"
            ' "sizeGuard": false in .claude/flow.config.json, or raise'
            " maxFileLines/maxFuncLines there)\n"
        )
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
