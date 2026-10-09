"""slop_prose: NP-04 to NP-08 prose-tell detectors for `slop-check --prose`.

Reads markdown, masks fenced and inline code, and returns
(path, line, id, message, "prose") tuples in the shape slop-check emits.
"""
import re
import sys

AI_WORDS = (
    "additionally", "crucial", "delve", "delves", "delving", "enduring",
    "enhance", "enhances", "fostering", "garner", "interplay", "intricate",
    "landscape", "pivotal", "showcase", "showcases", "tapestry", "testament",
    "underscore", "underscores", "vibrant", "utilize", "utilizes", "leverage",
    "leverages", "facilitate", "facilitates",
)
AI_RE = re.compile(r"\b(" + "|".join(AI_WORDS) + r"|serves as|stands as)\b", re.I)
HEDGE_RE = re.compile(
    r"\b(might|may|could|possibly|potentially|perhaps|arguably|somewhat|"
    r"seemingly|conceivably|probably)\b", re.I)
NOT_BUT_RES = (
    re.compile(r"\bnot (?:just|only|merely|simply)\b.{0,80}?\bbut\b", re.I),
    re.compile(r"\b(?:it|this|that)(?:'s| is| isn't) not\b[^.!?;,]{1,60}[,;] "
               r"(?:it|this|that)(?:'s| is)\b", re.I),
)
FILLER_RE = re.compile(
    r"^(?:it(?:'s| is) (?:important|worth) (?:to note|noting)|certainly[!,]|"
    r"of course[!,]|great question|in conclusion|in summary|to sum up|"
    r"to summari[sz]e|i hope this helps|let me know if)", re.I)
MAX_WORDS = 30
UNREADABLE = []

FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
BLOCK_RE = re.compile(r"^\s*(?:[-*+]\s+|\d+[.)]\s+|#+\s+)")
HEADING_RE = re.compile(r"^\s*#+\s")
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
URL_RE = re.compile(r"https?://\S+")
SENT_END_RE = re.compile(r"(?<=[.!?])\s+")
LEAD_RE = re.compile(r"^\s*(?:[-*+]\s+|\d+[.)]\s+|>\s*|#+\s+)")


def _mask(line):
    """Replace code and URLs with same-length underscores (one word each)."""
    line = INLINE_CODE_RE.sub(lambda m: "_" * len(m.group(0)), line)
    line = LINK_RE.sub(lambda m: m.group(1) + "_" * (len(m.group(0)) - len(m.group(1))), line)
    return URL_RE.sub(lambda m: "_" * len(m.group(0)), line)


def _paragraphs(text):
    """Yield paragraphs as lists of (lineno, masked_text); code, tables and blanks split them."""
    para, fence, in_front = [], None, False
    for n, raw in enumerate(text.splitlines(), 1):
        if n == 1 and raw.strip() == "---":
            in_front = True
            continue
        if in_front:
            in_front = raw.strip() != "---"
            continue
        fm = FENCE_RE.match(raw)
        if fm and (fence is None or (fm.group(1)[0] == fence[0] and len(fm.group(1)) >= len(fence)
                                      and not fm.group(2).strip())):
            fence = fm.group(1) if fence is None else None
            if para:
                yield para
            para = []
            continue
        if fence or not raw.strip() or raw.lstrip().startswith("|"):
            if para:
                yield para
            para = []
            continue
        if BLOCK_RE.match(raw) and para:
            yield para
            para = []
        para.append((n, LEAD_RE.sub("", _mask(raw), count=1)))
        if HEADING_RE.match(raw):
            yield para
            para = []
    if para:
        yield para


def _sentences(para):
    """Yield (lineno, sentence); lineno is the line where the sentence starts."""
    joined, starts = "", []
    for n, txt in para:
        starts.append((len(joined), n))
        joined += txt + " "
    pos = 0
    for part in SENT_END_RE.split(joined):
        idx = joined.find(part, pos)
        pos = idx + len(part)
        line = para[0][0]
        for off, n in starts:
            if off <= idx:
                line = n
        yield line, part.strip()


def _sentence_findings(path, line, sent):
    out = []
    for m in AI_RE.finditer(sent):
        out.append((path, line, "NP-04", f"AI-tell word '{m.group(0).lower()}'; use the plain word", "prose"))
    hedges = {m.group(0).lower() for m in HEDGE_RE.finditer(sent)}
    if len(hedges) >= 2:
        out.append((path, line, "NP-05", f"stacked hedges ({', '.join(sorted(hedges))}); keep one or give the number", "prose"))
    if any(r.search(sent) for r in NOT_BUT_RES):
        out.append((path, line, "NP-06", "'not X, but Y' reflex; state Y directly", "prose"))
    if FILLER_RE.match(sent):
        out.append((path, line, "NP-07", "throat-clearing opener or summary closer; start with the point", "prose"))
    words = len(sent.split())
    if words > MAX_WORDS:
        out.append((path, line, "NP-08", f"sentence has {words} words (limit {MAX_WORDS}); split it", "prose"))
    return out


def scan_text(path, text):
    findings = []
    for para in _paragraphs(text):
        for line, sent in _sentences(para):
            if sent:
                findings.extend(_sentence_findings(path, line, sent))
    return findings


def scan_files(paths):
    findings = []
    for p in paths:
        try:
            with open(p, encoding="utf-8") as fh:
                findings.extend(scan_text(p, fh.read()))
        except (OSError, UnicodeDecodeError) as e:
            UNREADABLE.append(p)
            sys.stderr.write(f"slop-check: cannot read {p}: {getattr(e, 'strerror', None) or e}\n")
    return findings
