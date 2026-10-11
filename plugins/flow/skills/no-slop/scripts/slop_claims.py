"""slop_claims: `slop-check --prose --claims` checks that the paths a markdown
document cites exist, that cited lines are in range, and that a backticked
snippet beside a path:line is really near those lines.

Returns (doc, line, kind, reason) tuples; kind is MISSING-PATH,
LINE-OUT-OF-RANGE or SNIPPET-NOT-FOUND. Fenced code is skipped, URLs are
skipped, paths resolve against the root. Counts and commands are not checked
here: a script cannot run them generically (see agents/claim-check.md, doc mode).
"""
import os
import re
import sys

FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
URL_RE = re.compile(r"(?:https?|ftp|file)://\S+")
SPAN_RE = re.compile(r"`([^`\n]+)`")
# path[:N[-M]] — at least one "/" or an alphabetic extension; no glob, template or absolute forms.
PATH_RE = re.compile(
    r"(?<![\w/.~$@:-])((?:[\w.-]+/)+[\w.-]*|[\w-]+(?:\.[\w-]+)*\.[A-Za-z][A-Za-z0-9]{0,5})"
    r"(?::(\d+)(?:-(\d+))?)?(?![\w/@])")
EXT_RE = re.compile(r"\.[A-Za-z][A-Za-z0-9]{0,5}$")
CONTEXT = 3


def _read_lines(cache, path):
    if path not in cache:
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                cache[path] = fh.read().splitlines()
        except OSError:
            cache[path] = None
    return cache[path]


def _doc_lines(text):
    """Yield (lineno, raw) for lines outside fenced code."""
    fence = None
    for n, raw in enumerate(text.splitlines(), 1):
        fm = FENCE_RE.match(raw)
        if fm and (fence is None or (fm.group(1)[0] == fence[0] and len(fm.group(1)) >= len(fence)
                                      and not fm.group(2).strip())):
            fence = fm.group(1) if fence is None else None
            continue
        if not fence:
            yield n, raw


def _is_claim(root, rel, has_line):
    """A token is a path claim when it clearly names a file: first segment exists, or it has an
    extension, or it carries :line. Words like and/or never qualify."""
    if rel.startswith(("-", ".../")) or "//" in rel or "*" in rel:
        return False
    first = rel.split("/", 1)[0]
    if "/" in rel and os.path.exists(os.path.join(root, first)):
        return True
    last = rel.rstrip("/").rsplit("/", 1)[-1]
    return bool(EXT_RE.search(last)) and (has_line or "/" in rel)


def _line_claim(cache, root, rel, lo, hi):
    """Return (kind, reason, window_text) for one path:line cite; kind None when in range."""
    full = os.path.join(root, rel)
    if os.path.isdir(full):
        return "LINE-OUT-OF-RANGE", f"{rel} is a directory, not a file with lines", None
    lines = _read_lines(cache, full)
    if lines is None:
        return "MISSING-PATH", f"{rel} does not exist under {root}", None
    top = hi if hi is not None else lo
    if lo < 1 or top > len(lines) or (hi is not None and hi < lo):
        return "LINE-OUT-OF-RANGE", f"{rel} has {len(lines)} lines; cited {lo}" + (f"-{hi}" if hi else ""), None
    window = lines[max(lo - 1 - CONTEXT, 0):top + CONTEXT]
    return None, "", " ".join(" ".join(window).split())


def _check_line(doc, n, raw, cache, root):
    out, windows, cited = [], [], set()
    for m in PATH_RE.finditer(URL_RE.sub(lambda u: " " * len(u.group(0)), raw)):
        rel, lo, hi = m.group(1), m.group(2), m.group(3)
        if not _is_claim(root, rel, lo is not None):
            continue
        cited.add(m.group(0))
        full = os.path.join(root, rel)
        if lo is None:
            if not os.path.exists(full):
                out.append((doc, n, "MISSING-PATH", f"{rel} does not exist under {root}"))
            continue
        kind, reason, window = _line_claim(cache, root, rel, int(lo), int(hi) if hi else None)
        if kind:
            out.append((doc, n, kind, reason))
        else:
            windows.append(window)
    return out, windows, cited


def _check_snippets(doc, n, raw, windows, cited):
    out = []
    for span in SPAN_RE.findall(raw):
        text = " ".join(span.split())
        if not text or PATH_RE.fullmatch(text) or any(c in text for c in cited):
            continue
        if not any(text in w for w in windows):
            out.append((doc, n, "SNIPPET-NOT-FOUND", f"`{text}` is not within {CONTEXT} lines of the cited lines"))
    return out


def scan_text(doc, text, root, cache=None):
    cache = {} if cache is None else cache
    findings = []
    for n, raw in _doc_lines(text):
        found, windows, cited = _check_line(doc, n, raw, cache, root)
        findings.extend(found)
        if windows:
            findings.extend(_check_snippets(doc, n, raw, windows, cited))
    return findings


def scan_files(paths, root):
    findings, cache = [], {}
    for p in paths:
        try:
            with open(p, encoding="utf-8") as fh:
                findings.extend(scan_text(p, fh.read(), root, cache))
        except (OSError, UnicodeDecodeError) as e:
            sys.stderr.write(f"slop-check: cannot read {p}: {getattr(e, 'strerror', None) or e}\n")
    return findings
