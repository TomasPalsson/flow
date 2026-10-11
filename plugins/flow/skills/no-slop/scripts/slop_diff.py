"""Diff and added-lines machinery for slop-check: git helpers, unified-diff
hunk parsing, and the --all-lines file reader. Imported by path the same
way slop_tools.py is (sys.path insert of the script's own directory).
"""
import re
import subprocess
import sys


def sh(args, cwd=None, timeout=None):
    """timeout=None matches subprocess.run's own default; slop_tools.py passes one."""
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)


class Unavailable(Exception):
    """The diff could not be computed; a silent '0 findings' would read as clean."""


def resolves(root, ref):
    return sh(["git", "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"], cwd=root).returncode == 0


def repo_root():
    r = sh(["git", "rev-parse", "--show-toplevel"])
    if r.returncode != 0:
        raise Unavailable("not a git repository")
    return r.stdout.strip()


def default_base(root):
    if resolves(root, "origin/main"):
        return "origin/main"
    if resolves(root, "HEAD~1"):
        return "HEAD~1"
    raise Unavailable("no origin/main and no parent commit; pass --base")


class Hunk:
    __slots__ = ("added", "removed")

    def __init__(self):
        self.added = []    # list of (lineno, text)
        self.removed = []  # list of (lineno, text)


def parse_diff(root, base, head, pathspecs):
    """Returns (added_by_file, hunks_by_file, file_status) keyed by path."""
    for ref in (base, head):
        if not resolves(root, ref):
            raise Unavailable(f"ref '{ref}' does not resolve")
    cmd = ["git", "diff", "-U0", f"{base}...{head}", "--"] + list(pathspecs)
    r = sh(cmd, cwd=root)
    if r.returncode != 0:
        raise Unavailable("git diff failed: " + (r.stderr.strip().splitlines() or ["unknown error"])[0])
    out = r.stdout
    added_by_file, hunks_by_file, file_status = {}, {}, {}
    cur = cur_hunk = None
    new_lineno = old_lineno = None
    is_new_file = False
    for line in out.splitlines():
        if line.startswith("diff --git "):
            cur = None
        elif line.startswith("--- "):
            is_new_file = line.startswith("--- /dev/null")
        elif line.startswith("+++ b/"):
            cur = line[6:]
            added_by_file.setdefault(cur, {})
            hunks_by_file.setdefault(cur, [])
            file_status[cur] = "added" if is_new_file else "modified"
        elif line.startswith("@@") and cur:
            m = re.search(r"-(\d+)(?:,\d+)?\s+\+(\d+)", line)
            old_lineno, new_lineno = (int(m.group(1)), int(m.group(2))) if m else (1, 1)
            cur_hunk = Hunk()
            hunks_by_file[cur].append(cur_hunk)
        elif cur and cur_hunk is not None and line.startswith("+") and not line.startswith("+++"):
            added_by_file[cur][new_lineno] = line[1:]
            cur_hunk.added.append((new_lineno, line[1:]))
            new_lineno += 1
        elif cur and cur_hunk is not None and line.startswith("-") and not line.startswith("---"):
            cur_hunk.removed.append((old_lineno, line[1:]))
            old_lineno += 1
    return added_by_file, hunks_by_file, file_status


def repo_ls(root, head):
    return sh(["git", "ls-tree", "-r", "--name-only", head], cwd=root).stdout.splitlines()


def show_file(root, head, path):
    r = sh(["git", "show", f"{head}:{path}"], cwd=root)
    return r.stdout if r.returncode == 0 else None


def read_file_direct(path):
    """--all-lines source read: straight off disk, no git involved."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def build_all_lines(files):
    """--all-lines: every line of each listed file counts as added."""
    added_by_file, hunks_by_file, file_status = {}, {}, {}
    for path in files:
        text = read_file_direct(path)
        if text is None:
            continue
        added = {i + 1: line for i, line in enumerate(text.splitlines())}
        added_by_file[path] = added
        hunk = Hunk()
        hunk.added = sorted(added.items())
        hunks_by_file[path] = [hunk]
        file_status[path] = "added"
    return added_by_file, hunks_by_file, file_status


def added_text_blob(added):
    """Join added lines into one blob plus an offset->lineno table."""
    lines = sorted(added.items())
    blob = "\n".join(t for _, t in lines)
    offsets, pos = [], 0
    for lineno, t in lines:
        offsets.append((pos, lineno))
        pos += len(t) + 1
    return blob, offsets


def line_for_pos(offsets, pos):
    ln = offsets[0][1] if offsets else 1
    for start, no in offsets:
        if start <= pos:
            ln = no
        else:
            break
    return ln
