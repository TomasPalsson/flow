"""Optional external-tool adapters for slop-check: ruff, tsc, jscpd, lizard.

Each run_<tool>(toplevel, base, files, added) returns an empty list of
findings when the tool binary is missing, times out, or emits output that
can't be parsed; anything else is left to raise. Imported lazily by
slop-check only when tool checks are enabled (i.e. --no-tools was not
passed).
"""
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slop_diff import sh, show_file

TIMEOUT = 60
LIZARD_CCN_LIMIT = 10  # matches ruff C901's default max-complexity


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
               cwd=toplevel, timeout=TIMEOUT)
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


def _lizard_write_old_sources(toplevel, mb, files, tmpdir):
    """Old-side sources at the merge-base, written to tmpdir (one subdir per
    file to dodge basename clashes). Returns (new_paths, old_paths, path_map),
    path_map keyed by realpath -> (repo path, "new"/"old")."""
    new_paths, old_paths, path_map = [], [], {}
    for i, f in enumerate(files):
        new_path = os.path.abspath(os.path.join(toplevel, f))
        new_paths.append(new_path)
        path_map[os.path.realpath(new_path)] = (f, "new")
        old_src = show_file(toplevel, mb, f)
        if old_src is None:
            continue  # file didn't exist at base: nothing to compare against
        subdir = os.path.join(tmpdir, str(i))
        os.makedirs(subdir)
        old_path = os.path.join(subdir, os.path.basename(f))
        with open(old_path, "w", encoding="utf-8") as fh:
            fh.write(old_src)
        old_paths.append(old_path)
        path_map[os.path.realpath(old_path)] = (f, "old")
    return new_paths, old_paths, path_map


def _lizard_functions_by_file_side(csv_text, path_map):
    """{(repo path, side): {name: [(ccn, start, end), ...]}} in CSV row order."""
    by_file_side = {}
    for row in csv.reader(csv_text.splitlines()):
        if len(row) < 11:
            continue
        ccn, file_col, name, start, end = row[1], row[6], row[7], row[9], row[10]
        loc = path_map.get(os.path.realpath(os.path.abspath(file_col)))
        if loc is None:
            continue
        by_file_side.setdefault(loc, {}).setdefault(name, []).append(
            (int(ccn), int(start), int(end)))
    return by_file_side


def _lizard_growth_findings(files, by_file_side, added):
    findings = []
    for f in files:
        new_funcs, old_funcs = by_file_side.get((f, "new"), {}), by_file_side.get((f, "old"), {})
        for name, new_list in new_funcs.items():
            old_list = old_funcs.get(name, [])
            for idx, (after, start, end) in enumerate(new_list):
                if idx >= len(old_list):
                    continue  # no counterpart at base: a new overload/def, not growth
                before = old_list[idx][0]
                if after > LIZARD_CCN_LIMIT and after > before \
                        and any(start <= ln <= end for ln in added[f]):
                    findings.append((f, start, "NS-17",
                                      f"complexity grew in existing function '{name}': "
                                      f"CC {before}->{after} (limit {LIZARD_CCN_LIMIT})", "lizard"))
    return findings


def run_lizard(toplevel, base, files, added):
    """NS-17: cyclomatic complexity growth in a function that already existed
    at base, old side = merge-base(base, HEAD). New functions, untouched
    functions, and functions that got simpler are silent (ImpactGate's rule:
    growing already-complex code costs more than adding new code)."""
    if not files or base is None or shutil.which("uvx") is None:
        return []
    mb = sh(["git", "merge-base", base, "HEAD"], cwd=toplevel)
    if mb.returncode != 0:
        return []
    mb = mb.stdout.strip()
    tmpdir = tempfile.mkdtemp(prefix="slop-check-lizard-")
    try:
        new_paths, old_paths, path_map = _lizard_write_old_sources(toplevel, mb, files, tmpdir)
        if not old_paths:
            return []
        r = sh(["uvx", "lizard", "--csv"] + new_paths + old_paths, cwd=toplevel, timeout=TIMEOUT)
        by_file_side = _lizard_functions_by_file_side(r.stdout, path_map)
        return _lizard_growth_findings(files, by_file_side, added)
    except (OSError, subprocess.SubprocessError, ValueError, csv.Error, IndexError):
        return []
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def run_tsc(toplevel, base, files, added):
    """NS-11: unused locals/params, zero-setup via bundled typescript."""
    findings = []
    if not files or shutil.which("npx") is None:
        return findings
    try:
        r = sh(["npx", "--yes", "-p", "typescript", "tsc", "--noUnusedLocals",
                "--noUnusedParameters", "--noEmit", "--target", "es2021",
                "--module", "esnext"] + files, cwd=toplevel, timeout=TIMEOUT)
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


def run_jscpd(toplevel, base, files, added, all_lines=False):
    """NS-01: cross-file duplication new since `base`, via --baseline-from-ref.

    Under --all-lines there is no base ref (no git repo required), so the
    scan runs plain, over the whole current directory, and any clone that
    touches a listed file is reported.
    """
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
        if all_lines:
            sh(base_cmd, cwd=toplevel, timeout=TIMEOUT)
        else:
            r = sh(base_cmd + ["--baseline-from-ref", base, "--fail-on-new-clones"],
                   cwd=toplevel, timeout=TIMEOUT)
            if not os.path.exists(report_path) and "baseline-from-ref" in (r.stderr or "").lower():
                sh(base_cmd, cwd=toplevel, timeout=TIMEOUT)  # fallback: installed jscpd rejects the flag
        if not os.path.exists(report_path):
            return findings
        with open(report_path) as f:
            report = json.load(f)
        for dup in report.get("duplicates", []):
            for side, other in (("firstFile", "secondFile"), ("secondFile", "firstFile")):
                clone_side = dup.get(side) or {}
                fpath, start, end = clone_side.get("name"), clone_side.get("start"), clone_side.get("end")
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
