#!/usr/bin/env bash
# security-patterns.sh — PostToolUse/Edit|Write|NotebookEdit hook.
#
# Reports a security sink in the lines this edit ADDED (innerHTML, eval, pickle
# loads, shell=True, disabled TLS verification, ...): one line per hit,
# "<file>:<line> <rule>: <one-sentence fix>", on stderr with exit 2 so the model
# reads it. Each rule+file is reported once per session. Silent when nothing
# matches. A reminder, never a block; the rule table is gated by file extension
# so docs and prose that mention a sink do not trip it.
#
# Added lines = the new text of the payload (content, new_string, edits[],
# new_source) minus any line already present in the old text (old_string, or
# HEAD's version of the file for a Write). Context the edit left alone is never
# reported.
#
# Off: `flow off` in the directory, or CC_NO_SECURITY_PATTERNS=1. Needs python3;
# without it the hook cannot judge and stays silent.
#
# Credit: adapted from anthropics/claude-plugins-official plugins/security-guidance/hooks/patterns.py @ a9fd216 (Apache-2.0).
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off
[ "${CC_NO_SECURITY_PATTERNS:-}" = "1" ] && hook_ok

file_path=$(hook_field '.tool_input.file_path')
[ -z "$file_path" ] && file_path=$(hook_field '.tool_input.notebook_path')
[ -z "$file_path" ] && hook_ok
case "$file_path" in */node_modules/* | */.git/*) hook_ok ;; esac
have python3 || hook_ok

# shellcheck disable=SC2016 # the python source is data for python3, not shell
PY='
import json, os, re, subprocess, sys

JS = (".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts", ".vue", ".svelte")
PY_ = (".py", ".pyi", ".ipynb")
DOC = (".md", ".mdx", ".txt", ".rst", ".json", ".yaml", ".yml")

# (rule, path filter, regex, one-sentence fix)
RULES = [
    ("child_process_exec", "js", r"child_process\.exec\b|\bexecSync\(|(?<![a-zA-Z0-9_.])exec\(",
     "exec() runs its string through a shell; use execFile() or spawn() with an argument array."),
    ("new_function", "js", r"\bnew\s+Function\s*\(",
     "new Function() with an interpolated string is code injection; use a lookup or a safe expression parser."),
    ("eval", "nodoc", r"(?<![a-zA-Z0-9_.])eval\(",
     "eval() runs arbitrary code; use JSON.parse or ast.literal_eval, or document why it is safe."),
    ("dangerouslySetInnerHTML", "js", r"dangerouslySetInnerHTML",
     "dangerouslySetInnerHTML is an XSS sink; sanitize with DOMPurify or render the content as elements."),
    ("document_write", "js", r"\bdocument\.write\s*\(",
     "document.write() is an XSS sink; build nodes with createElement and appendChild."),
    ("innerHTML", "js", r"\.innerHTML\s*=(?!=)",
     "Assigning innerHTML with untrusted content is an XSS sink; use textContent or sanitize with DOMPurify."),
    ("outerHTML", "js", r"\.outerHTML\s*=(?!=)",
     "Assigning outerHTML is an XSS sink like innerHTML; use textContent or sanitize with DOMPurify."),
    ("insertAdjacentHTML", "js", r"\.insertAdjacentHTML\s*\(",
     "insertAdjacentHTML is an XSS sink; use insertAdjacentText or sanitize with DOMPurify."),
    ("pickle_load", "py", r"(?<![a-zA-Z0-9_])pickle\.(loads?|Unpickler)\b|(?<![a-zA-Z0-9_])pkl_load\(",
     "Unpickling untrusted data runs arbitrary code; use JSON or a schema-validated loader."),
    ("os_system", "py", r"\bos\.system\s*\(",
     "os.system() runs a shell; use subprocess.run([...]) with an argument list."),
    ("subprocess_shell", "py", r"subprocess\.(?:run|call|Popen|check_output|check_call)\(.*shell\s*=\s*True",
     "shell=True enables command injection; pass an argument list without a shell."),
    ("yaml_load", "py", r"\byaml\.load\s*\((?![^)\n]{0,80}\bSafe)",
     "yaml.load() can build arbitrary objects; use yaml.safe_load()."),
    ("torch_load", "py", r"(?:\btorch\.load)\s*\((?![^)\n]{0,200}weights_only\s*=\s*True)",
     "torch.load() unpickles by default; pass weights_only=True."),
    ("tls_verification_disabled", "nodoc",
     r"\bverify\s*=\s*False\b|rejectUnauthorized\s*:\s*false|InsecureSkipVerify\s*:\s*true|NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*[\"\x27]?0|ssl\._create_unverified_context|check_hostname\s*=\s*False",
     "Disabled TLS verification allows man-in-the-middle attacks; trust the CA instead."),
    ("go_exec_shell", "go", r"exec\.Command\(\s*\"(?:sh|bash|/bin/sh|/bin/bash)\"",
     "exec.Command with a shell enables command injection; pass the program and its arguments directly."),
]

def applies(kind, path):
    p = path.lower()
    if kind == "js":
        return p.endswith(JS)
    if kind == "py":
        return p.endswith(PY_)
    if kind == "go":
        return p.endswith(".go")
    return not p.endswith(DOC)

def texts(ti, keys):
    out = []
    for k in keys:
        v = ti.get(k)
        if isinstance(v, str):
            out.append(v)
    for e in ti.get("edits") or []:
        if isinstance(e, dict):
            for k in keys:
                if isinstance(e.get(k), str):
                    out.append(e[k])
    return out

def head_text(path):
    try:
        d = os.path.dirname(path) or "."
        r = subprocess.run(["git", "-C", d, "show", "HEAD:./" + os.path.basename(path)],
                           capture_output=True, text=True)
        return r.stdout if r.returncode == 0 else ""
    except OSError:
        return ""

def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    ti = data.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    new = texts(ti, ("new_string", "content", "new_source"))
    old = texts(ti, ("old_string",))
    if not old and ti.get("content") is not None:
        old = [head_text(path)]
    seen = set(l.strip() for t in old for l in t.splitlines())
    added = [l for t in new for l in t.splitlines() if l.strip() and l.strip() not in seen]
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            body = [l.strip() for l in fh.read().splitlines()]
    except OSError:
        body = []
    hits = {}
    for rule, kind, rx, fix in RULES:
        if not applies(kind, path):
            continue
        cre = re.compile(rx)
        for line in added:
            if cre.search(line):
                n = body.index(line.strip()) + 1 if line.strip() in body else 1
                hits.setdefault(rule, (n, fix, line.strip().replace("\t", " ")))
                break
    for rule, (n, fix, text) in hits.items():
        print("%d\t%s\t%s\t%s" % (n, rule, fix, text))

main()
'

hits=$(printf '%s' "$HOOK_INPUT" | python3 -I -c "$PY" 2>/dev/null)
[ -z "$hits" ] && hook_ok

# Every hit is logged (rule, file, matched text) so `flow digest` can say later
# whether it was fixed; the reminder below is still once per rule and file.
# It lives in the git dir, never the working tree: it holds raw source lines and
# must not show up in `git status` or get committed by a checkpoint.
_sp_log=$(git -C "$(hook_project_dir)" rev-parse --absolute-git-dir 2>/dev/null || true)
[ -n "$_sp_log" ] && _sp_log="$_sp_log/flow-security-hits.tsv"

report=""
while IFS=$'\t' read -r n rule fix text; do
	[ -z "$rule" ] && continue
	if [ -n "$text" ] && [ -n "$_sp_log" ]; then
		_sp_row=$(printf '%s\t%s\t%s' "$rule" "$file_path" "$text")
		if ! grep -qxF "$_sp_row" "$_sp_log" 2>/dev/null; then
			printf '%s\n' "$_sp_row" >>"$_sp_log" 2>/dev/null || true
		fi
	fi
	hook_once "secpat:$rule:$file_path" || continue
	report="${report}${report:+
}$file_path:$n $rule: $fix"
done <<EOF
$hits
EOF
[ -n "$report" ] && hook_feedback "$report"
hook_ok
