"""Optional external-tool adapters for slop-check: ruff, tsc, jscpd.

Each run_<tool>(toplevel, base, files, added) returns an empty list of
findings when the tool binary is missing, times out, or emits output that
can't be parsed; anything else is left to raise. Imported lazily by
slop-check only when tool checks are enabled (i.e. --no-tools was not
passed).
"""
import json
import os
import re
import shutil
import subprocess
import tempfile

TIMEOUT = 60


def sh(args, cwd=None):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=TIMEOUT)


def norm_path(p, root):
    if os.path.isabs(p):
        try:
            return os.path.relpath(p, root)
        except ValueError:
            return p
    return p


def run_ruff(toplevel, base, files, added, existing_ns03=frozenset()):
    """NS-11 (unused import/var/arg), NS-12 (complexity), NS-03 (blind except)."""
    findings = []
    if not files or shutil.which("uvx") is None:
        return findings
    select = "F401,F841,ARG001,C901,PLR0913,PLR0915,BLE001,E722"
    try:
        r = sh(["uvx", "ruff", "check", "--select", select, "--output-format", "json"] + files,
               cwd=toplevel)
        if not r.stdout.strip():
            return findings
        items = json.loads(r.stdout)
    except Exception:
        return findings
    for item in items:
        try:
            fpath, row = norm_path(item["filename"], toplevel), item["location"]["row"]
            code, msg = item["code"], item["message"]
        except (KeyError, TypeError):
            continue
        if fpath not in added or row not in added[fpath]:
            continue
        if code in ("F401", "F841", "ARG001"):
            findings.append((fpath, row, "NS-11", f"{code}: {msg}", "ruff"))
        elif code in ("C901", "PLR0913", "PLR0915"):
            findings.append((fpath, row, "NS-12", f"{code}: {msg}", "ruff"))
        elif code in ("BLE001", "E722") and (fpath, row) not in existing_ns03:
            findings.append((fpath, row, "NS-03", f"{code}: {msg}", "ruff"))
    return findings


def run_tsc(toplevel, base, files, added):
    """NS-11: unused locals/params, zero-setup via bundled typescript."""
    findings = []
    if not files or shutil.which("npx") is None:
        return findings
    try:
        r = sh(["npx", "--yes", "-p", "typescript", "tsc", "--noUnusedLocals",
                "--noUnusedParameters", "--noEmit", "--target", "es2021",
                "--module", "esnext"] + files, cwd=toplevel)
    except Exception:
        return findings
    pattern = re.compile(r"^(.+?)\((\d+),(\d+)\): error (TS\d+): (.+)$")
    for line in r.stdout.splitlines():
        m = pattern.match(line)
        if not m:
            continue
        fpath, row, _col, code, msg = m.groups()
        fpath, row = norm_path(fpath, toplevel), int(row)
        if fpath in added and row in added[fpath]:
            findings.append((fpath, row, "NS-11", f"{code}: {msg}", "tsc"))
    return findings


def run_jscpd(toplevel, base, files, added):
    """NS-01: cross-file duplication new since `base`, via --baseline-from-ref."""
    findings = []
    if shutil.which("npx") is None:
        return findings
    tmpdir = tempfile.mkdtemp(prefix="slop-check-jscpd-")
    ignore = "**/node_modules/**,**/.git/**,**/*.min.js"
    base_cmd = ["npx", "--yes", "jscpd", ".", "--min-tokens", "15", "--min-lines", "3",
                "--ignore-identifiers", "--reporters", "json", "--output", tmpdir,
                "--ignore", ignore]
    report_path = os.path.join(tmpdir, "jscpd-report.json")
    try:
        r = sh(base_cmd + ["--baseline-from-ref", base, "--fail-on-new-clones"], cwd=toplevel)
        if not os.path.exists(report_path) and "baseline-from-ref" in (r.stderr or "").lower():
            sh(base_cmd, cwd=toplevel)  # fallback: installed jscpd rejects the flag
        if not os.path.exists(report_path):
            return findings
        with open(report_path) as f:
            data = json.load(f)
        for dup in data.get("duplicates", []):
            for side, other in (("firstFile", "secondFile"), ("secondFile", "firstFile")):
                info = dup.get(side) or {}
                fpath, start, end = info.get("name"), info.get("start"), info.get("end")
                if fpath in added and start is not None and end is not None \
                        and any(start <= ln <= end for ln in added[fpath]):
                    o = dup.get(other) or {}
                    findings.append((fpath, start, "NS-01",
                                      f"new clone: {fpath}:{start}-{end} ~ "
                                      f"{o.get('name')}:{o.get('start')}-{o.get('end')}", "jscpd"))
                    break
    except (OSError, subprocess.SubprocessError, ValueError, TypeError):
        return findings  # tool missing, timed out, or emitted an unreadable report
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    return findings
