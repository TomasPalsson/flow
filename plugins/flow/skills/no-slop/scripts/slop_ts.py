"""slop_ts: NS-30 TypeScript partiality tells for slop-check.

Flags, on an added .ts/.tsx line: a non-null assertion followed by `.`, `(`
or `[`; `as <Type>` directly after `]`; and "should never happen" in a throw
or a comment. React ref access (`ref.current!`) is exempt.

Credit: adapted from cursor/plugins pstack skills/typescript-best-practices/references/patterns.md @ ccb5507 (MIT).
"""
import re

NONNULL_RE = re.compile(r"[\w)\]]!(?=[.(\[])")
REF_RE = re.compile(r"\b\w*[Rr]ef\.current!")
INDEX_CAST_RE = re.compile(r"\]\s+as\s+(?!const\b)[A-Za-z_$]")
NEVER_RE = re.compile(r"should\s+never\s+happen", re.I)
STRING_RE = re.compile(r"""'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|`(?:\\.|[^`\\])*`""")


def _blank(m):
    return "_" * len(m.group(0))


def ts_partiality(text):
    """Return a list of message strings for one added line (empty when clean)."""
    out = []
    code = STRING_RE.sub(_blank, text)
    code = code.split("//", 1)[0]
    code = REF_RE.sub(_blank, code)
    if NONNULL_RE.search(code):
        out.append("non-null assertion; narrow the value or handle the missing case")
    if INDEX_CAST_RE.search(code):
        out.append("cast after an index read; the element may be undefined")
    comment = text.split("//", 1)[1] if "//" in text else ""
    if NEVER_RE.search(comment) or (re.search(r"\bthrow\b", text) and NEVER_RE.search(text)):
        out.append("'should never happen'; make the state unrepresentable or handle it")
    return out
