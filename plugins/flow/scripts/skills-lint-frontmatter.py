#!/usr/bin/env python3
"""skills-lint-frontmatter.py: frontmatter, orphan, collision and dead-path checks.

Called by skills-lint (kept out of that file to stay under the size guard):
  --frontmatter [--claude-ai] <dir>   name/description/model rules, YAML hazards
  --orphans <dir>                     references/ and scripts/ files nothing reaches
  --collisions [<dir>...]             skill descriptions that read alike (skills-lint-collisions.py)
  --claude-md <root>                  dead backticked paths in CLAUDE.md, rules, PROGRESS.md


--frontmatter [--claude-ai] <dir>: every SKILL.md and agents/*.md under
<dir> needs a kebab-case name of 64 characters or fewer that equals its
directory (skills) or filename (agents), a unique name, a description of
1-1024 characters, no strict-YAML hazard in the frontmatter (unquoted ": ",
tab indent, unclosed quote, leading indicator) and, for model:, sonnet,
opus, haiku, inherit or a claude-* id. Prints YAML/NAME/DUP-NAME/MODEL and
"DESC-LEN <file> <n>"; exit 1 if any. --claude-ai also rejects "<" and ">"
in a description (claude.ai does; Claude Code does not).
--orphans <dir>: prints "ORPHAN <file>" (exit 1) for a references/ or
scripts/ file that SKILL.md does not reach by name, directly or through
another reached file. test_*, *_test.*, fixtures/ and __pycache__ are exempt.
--claude-md <root>: prints "MISSING <file>:<line> <path>" (exit 1) for a
backticked path in CLAUDE.md, .claude/rules/*.md or a PROGRESS.md Ruling
line that does not exist under <root>. Globs, <...> and placeholders skip.
--collisions [<dir>...]: lists skill-description pairs with TF-IDF cosine
>= 0.75, counts pairs >= 0.5. A report only: always exit 0.

Exit 1 when a hit is an error (never for --collisions). Stdlib only.

Credit: adapted from addyosmani/agent-skills scripts/lib/skill-lint.js @ 1be8e34 (MIT).
Credit: adapted from anthropics/claude-plugins-official plugins/skill-creator/skills/skill-creator/scripts/quick_validate.py @ dbd4588 (Apache-2.0).
Credit: adapted from vercel-labs/agent-skills scripts/build-discovery-index.mjs @ a9fd216 (MIT).
"""
import os
import re
import sys

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "dist", ".next", "target"}
MODELS = {"sonnet", "opus", "haiku", "inherit"}
MODEL_ID = re.compile(r"^claude-[a-z0-9.\-]+(\[[0-9a-z]+\])?$")
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
KNOWN_KEYS = {
    "name", "description", "allowed-tools", "model", "license", "metadata",
    "compatibility", "argument-hint", "disable-model-invocation",
    "user-invocable", "tools", "color", "effort", "maxTurns", "memory",
    "version", "source", "risk", "date_added", "context", "agent", "hooks",
    "skills", "paths", "shell", "when_to_use", "disallowedTools",
    "permissionMode", "mcpServers", "isolation", "background", "initialPrompt",
}


def walk(root):
    for d, dirs, files in os.walk(root, followlinks=True):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for f in sorted(files):
            yield os.path.join(d, f)


def in_fixtures(path, root):
    return "/tests/fixtures/" in path and "/tests/fixtures" not in root


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def find_docs(root):
    """SKILL.md files and agents/*.md files under root."""
    skills, agents = [], []
    for p in walk(root):
        if in_fixtures(p, root):
            continue
        if p.endswith("/SKILL.md"):
            skills.append(p)
        elif p.endswith(".md") and os.path.basename(os.path.dirname(p)) == "agents":
            agents.append(p)
    return skills, agents


# ---------------------------------------------------------------- frontmatter

def split_frontmatter(text):
    """Return (list of (lineno, line), end lineno) or None."""
    lines = text.split("\n")
    if not lines or lines[0].rstrip() != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            return [(n + 1, lines[n]) for n in range(1, i)]
    return None


def hazards(value, lineno):
    """Strict-YAML problems in a plain or quoted single-line scalar value."""
    out = []
    v = value.strip()
    if not v:
        return out
    if v[0] in "\"'":
        m = re.match(r'^"(?:[^"\\]|\\.)*"' if v[0] == '"' else r"^'(?:[^']|'')*'", v)
        if not m:
            out.append((lineno, "unclosed quote"))
        elif v[m.end():].strip() and not v[m.end():].lstrip().startswith("#"):
            out.append((lineno, "text after the closing quote"))
        return out
    if v[0] in "|>":
        return out
    if v[0] in "[{&*!%@`":
        out.append((lineno, "value starts with the YAML indicator " + v[0]))
    if ": " in v or v.endswith(":"):
        out.append((lineno, "unquoted ': ' in a plain scalar (quote the value)"))
    if " #" in v:
        out.append((lineno, "unquoted ' #' starts a YAML comment (quote the value)"))
    return out


def parse_fields(entries):
    """Lenient top-level parse -> (fields {key: (lineno, text)}, hazards)."""
    fields, hz = {}, []
    i = 0
    while i < len(entries):
        n, line = entries[i]
        if "\t" in line[: len(line) - len(line.lstrip())]:
            hz.append((n, "tab indentation"))
        m = re.match(r"^([A-Za-z_][\w\-]*):(?:\s+(.*)|\s*)$", line)
        if not m:
            i += 1
            continue
        key, val = m.group(1), (m.group(2) or "")
        j = i + 1
        cont = []
        while j < len(entries) and (not entries[j][1].strip() or entries[j][1][0] in " \t"):
            cont.append(entries[j][1].strip())
            j += 1
        if val[:1] in ("|", ">"):
            val = " ".join(c for c in cont if c)
        else:
            if val[:1] and val[0] in "\"'" and val[0] not in val[1:] and cont:
                val = val + " " + " ".join(c for c in cont if c)
                hz.extend(hazards(val, n))
            else:
                hz.extend(hazards(val, n))
                if val.strip() and cont and val[0] not in "\"'":
                    # plain scalar folded over indented lines: check each, measure whole
                    for k in range(i + 1, j):
                        if entries[k][1].strip():
                            hz.extend(h for h in hazards(entries[k][1], entries[k][0])
                                      if not h[1].startswith("value starts"))
                    val = val + " " + " ".join(c for c in cont if c)
            if val[:1] and val[0] in "\"'" and len(val) > 1 and val[-1] == val[0]:
                val = val[1:-1]
        fields[key] = (n, val.strip())
        i = j
    return fields, hz


def check_frontmatter(root, claude_ai):
    skills, agents = find_docs(root)
    bad = 0
    seen = {}

    def out(tag, path, msg):
        nonlocal bad
        print("%s %s %s" % (tag, path, msg))
        bad += 1

    for path in skills + agents:
        is_agent = path in agents
        entries = split_frontmatter(read(path))
        if entries is None:
            out("YAML", path + ":1", "no frontmatter block")
            continue
        fields, hz = parse_fields(entries)
        for n, msg in hz:
            out("YAML", "%s:%d" % (path, n), msg)
        for k, (n, _) in fields.items():
            if k not in KNOWN_KEYS:
                print("KEY %s:%d unknown key %s (warning)" % (path, n, k))
        expect = (os.path.basename(path)[:-3] if is_agent
                  else os.path.basename(os.path.dirname(path)))
        name = fields.get("name", (0, ""))[1]
        if not NAME_RE.match(name) or len(name) > 64:
            out("NAME", path, "%r is not kebab-case within 64 chars" % name)
        elif name != expect:
            out("NAME", path, "%r differs from %r (the %s)" % (
                name, expect, "filename" if is_agent else "directory"))
        key = ("agent" if is_agent else "skill", name)
        if name and key in seen:
            out("DUP-NAME", path, "%r also in %s" % (name, seen[key]))
        seen.setdefault(key, path)
        desc = fields.get("description", (0, ""))[1]
        if not 1 <= len(desc) <= 1024:
            out("DESC-LEN", path, str(len(desc)))
        if claude_ai and ("<" in desc or ">" in desc):
            out("ANGLE", path, "description has < or > (claude.ai rejects it)")
        model = fields.get("model", (0, None))[1]
        if model is not None and model not in MODELS and not MODEL_ID.match(model):
            out("MODEL", path, "%r is not one of %s or a claude-* id" % (
                model, "/".join(sorted(MODELS))))
    return 1 if bad else 0


# -------------------------------------------------------------------- orphans

def is_excluded(rel):
    base = os.path.basename(rel)
    parts = rel.split("/")
    return (base.startswith("test_") or re.search(r"_test\.[^.]+$", base)
            or re.search(r"\.test\.[^.]+$", base) or "fixtures" in parts
            or "__pycache__" in parts or base.endswith(".pyc")
            or base == ".DS_Store")


def mentions(text, rel):
    stem, ext = os.path.splitext(os.path.basename(rel))
    if ext in (".py", ".mjs", ".js", ".cjs", ".ts") and re.search(
            r"(?:\bimport\b|\bfrom\b|\brequire\()[^\n]*\b" + re.escape(stem) + r"\b", text):
        return True
    for needle in {rel, os.path.basename(rel)}:
        if re.search(r"(?<![\w.\-])" + re.escape(needle) + r"(?![\w\-]|\.\w)", text):
            return True
    return False


def check_orphans(root):
    bad = 0
    for skill_md in find_docs(root)[0]:
        sdir = os.path.dirname(skill_md)
        files = list(walk(sdir))
        files = [p for p in files if p == skill_md or not _in_nested_skill(p, sdir)]
        rels = {p: os.path.relpath(p, sdir) for p in files}
        texts = {p: read(p) for p in files if not is_excluded(rels[p]) or p == skill_md}
        reached, queue = {skill_md}, [skill_md]
        while queue:
            cur = queue.pop()
            for p in files:
                if p in reached or p not in texts:
                    continue
                if mentions(texts[cur], rels[p]):
                    reached.add(p)
                    queue.append(p)
        for p in files:
            rel = rels[p]
            if not rel.startswith(("references/", "scripts/")) or is_excluded(rel):
                continue
            if p not in reached:
                print("ORPHAN %s" % p)
                bad += 1
    return 1 if bad else 0


def _in_nested_skill(path, sdir):
    d = os.path.dirname(path)
    while d != sdir and len(d) > len(sdir):
        if os.path.exists(os.path.join(d, "SKILL.md")):
            return True
        d = os.path.dirname(d)
    return False


# ------------------------------------------------------------------- claude-md

RULING = re.compile(r"^\s*(?:[-*]\s+)?Ruling:\s*(.*?)\s*$")
TICK = re.compile(r"`([^`\n]+)`")
BARE = re.compile(r"[^\s`\"'()<>,;]+")
EXTS = {"md", "json", "js", "mjs", "cjs", "ts", "tsx", "jsx", "py", "sh", "yml", "yaml",
        "toml", "txt", "css", "html", "go", "rs", "lock", "env", "sql", "cfg", "ini"}
PLACEHOLDER_STEMS = {"x", "y", "foo", "bar"}


def candidate(tok):
    """Normalise a token to a repo-relative path to check, or None to skip."""
    tok = tok.strip()
    if tok.endswith(("...", "…")):
        return None
    tok = tok.rstrip(".,;:?!)")
    tok = re.sub(r"(#.*|:\d+(-\d+)?)$", "", tok)
    while tok.startswith("./"):
        tok = tok[2:]
    if not tok or re.search(r"[\s*?\[\]{}<>$~|=&]", tok) or "://" in tok or tok.startswith(("/", "-", "@")):
        return None
    stem = os.path.basename(tok.rstrip("/"))
    stem = stem.rsplit(".", 1)[0] if "." in stem else stem
    if len(stem) <= 1 or stem in PLACEHOLDER_STEMS or "NNN" in tok:
        return None
    ext = tok.rsplit(".", 1)[1].lower() if re.search(r"\.[A-Za-z0-9]+$", tok) else ""
    if "/" not in tok:
        return ("path", tok) if ext in EXTS else None
    if ext not in EXTS and not tok.endswith("/") and not tok.startswith("."):
        return ("dir-prefix", tok)
    return ("path", tok)


def all_files(root):
    """Repo-relative file paths (capped), skipping VCS, deps and nested worktrees."""
    out = []
    for p in walk(root):
        rel = os.path.relpath(p, root)
        if rel.startswith(os.path.join(".claude", "worktrees")):
            continue
        out.append("/" + rel)
        if len(out) >= 50000:
            break
    return out


def resolves_below(files, rel):
    """A cited path may be relative to a subdirectory (a skill, a package)."""
    tail = "/" + rel.rstrip("/")
    return any(f == tail or f.endswith(tail) or f.startswith(tail + "/") or (tail + "/") in f
               for f in files)


def check_claude_md(root):
    files = [os.path.join(root, "CLAUDE.md")]
    rules = os.path.join(root, ".claude", "rules")
    if os.path.isdir(rules):
        files += [p for p in walk(rules) if p.endswith(".md")]
    files.append(os.path.join(root, "PROGRESS.md"))
    bad = 0
    known = None
    for path in files:
        if not os.path.isfile(path):
            continue
        only_ruling = path.endswith("PROGRESS.md")
        fenced = False
        for n, line in enumerate(read(path).split("\n"), 1):
            if line.lstrip().startswith(("```", "~~~")):
                fenced = not fenced
                continue
            if fenced:
                continue
            toks = []
            ruling = RULING.match(line)
            if only_ruling and not ruling:
                continue
            toks += TICK.findall(line)
            if ruling:
                toks += BARE.findall(ruling.group(1))
            seen = set()
            for tok in toks:
                c = candidate(tok)
                if not c or c[1] in seen:
                    continue
                seen.add(c[1])
                kind, rel = c
                target = os.path.join(root, rel)
                if os.path.exists(target):
                    continue
                if known is None:
                    known = all_files(root)
                if resolves_below(known, rel):
                    continue
                if kind == "dir-prefix" and not os.path.isdir(os.path.join(root, rel.split("/")[0])):
                    continue
                print("MISSING %s:%d %s" % (path, n, rel))
                bad += 1
    return 1 if bad else 0


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    mode, rest = argv[0], argv[1:]
    claude_ai = "--claude-ai" in rest
    rest = [a for a in rest if a != "--claude-ai"]
    here = os.path.dirname(os.path.abspath(__file__))
    if mode == "--collisions":
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "skills_lint_collisions", os.path.join(here, "skills-lint-collisions.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.collisions(rest or [os.path.dirname(os.path.dirname(here))], sys.modules[__name__])
    if not rest:
        print("%s needs a directory argument" % mode)
        return 2
    root = rest[0].rstrip("/") or "/"
    if mode == "--frontmatter":
        return check_frontmatter(root, claude_ai)
    if mode == "--orphans":
        return check_orphans(root)
    if mode == "--claude-md":
        return check_claude_md(root)
    print("unknown mode " + mode)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
