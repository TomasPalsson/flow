#!/usr/bin/env python3
"""agui_doctor.py — static scan for the known footguns of the AG-UI × Strands × AgentCore ×
Vercel AI SDK stack. Heuristic, best-effort, dependency-free (Python stdlib only).

Usage:
    python3 agui_doctor.py [PROJECT_DIR]      # defaults to the current directory

Reports PASS / WARN / FAIL per check. Exit code 1 if any FAIL. Heuristics can false-positive —
treat WARN as "look here," not "definitely broken."
"""
import os
import re
import sys

RESET, RED, YEL, GRN, DIM = "\033[0m", "\033[31m", "\033[33m", "\033[32m", "\033[2m"
results = []  # (level, title, detail)


def add(level, title, detail=""):
    results.append((level, title, detail))


def find_files(root, names=None, suffixes=None, skip=("node_modules", ".next", ".git", ".sst",
                                                      ".open-next", "__pycache__", ".terraform",
                                                      ".venv", "venv", "site-packages", ".uv",
                                                      "dist-info", ".mypy_cache")):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip]
        for fn in filenames:
            if names and fn in names:
                out.append(os.path.join(dirpath, fn))
            elif suffixes and fn.endswith(suffixes):
                out.append(os.path.join(dirpath, fn))
    return out


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def find_route(root):
    """The /api/chat route — the AG-UI → AI SDK bridge."""
    for p in find_files(root, suffixes=("route.ts", "route.tsx", "route.js")):
        src = read(p)
        if "createUIMessageStream" in src or "InvokeAgentRuntime" in src or "ag" in src.lower():
            if "/chat" in p.replace(os.sep, "/") or "createUIMessageStream" in src:
                return p, src
    return None, ""


def check_route(root):
    path, src = find_route(root)
    if not path:
        add("WARN", "Bridge route not found", "no app/api/chat/route.ts with createUIMessageStream")
        return
    rel = os.path.relpath(path, root)
    uses_agentcore = "InvokeAgentRuntime" in src

    if re.search(r'runtime\s*=\s*["\']nodejs["\']', src):
        add("PASS", "route: runtime = 'nodejs'", rel)
    else:
        add("FAIL", "route: missing runtime = 'nodejs'", f"{rel} — edge runtime lacks AWS SDK / web streams")

    if uses_agentcore:
        if re.search(r'accept\s*:\s*["\']text/event-stream["\']', src):
            add("PASS", "route: accept 'text/event-stream'", rel)
        else:
            add("FAIL", "route: InvokeAgentRuntime without accept:'text/event-stream'",
                f"{rel} — response will buffer instead of streaming")

    if re.search(r'type:\s*["\']start["\']', src) and re.search(r'type:\s*["\']finish["\']', src):
        add("PASS", "route: writes start + finish envelope", rel)
    else:
        add("FAIL", "route: missing manual start/finish",
            f"{rel} — the createUIMessageStream bridge path does NOT auto-write these")

    # Buffer flush after the read loop: look for a second pass over `buffer` outside the while.
    if "lines.pop()" in src or ".split(\"\\n\")" in src or ".split('\\n')" in src:
        if re.search(r'buffer\.trim\(\)|for\s*\(.*buffer\.split', src):
            add("PASS", "route: flushes leftover SSE buffer", rel)
        else:
            add("WARN", "route: may not flush leftover SSE buffer after loop",
                f"{rel} — final RUN_FINISHED can be dropped → client hangs in 'streaming'")

    m = re.search(r'maxDuration\s*=\s*(\d+)', src)
    if m:
        val = int(m.group(1))
        if val < 120:
            add("WARN", f"route: maxDuration = {val}", f"{rel} — raise to >=120 for multi-tool runs")
        else:
            add("PASS", f"route: maxDuration = {val}", rel)

    if uses_agentcore and re.search(r'sessions?\s*=\s*new\s+Map', src):
        add("WARN", "route: in-memory session Map",
            f"{rel} — breaks on Lambda (per-instance/cold starts) → agent forgets context in prod")


def check_docker(root):
    dfs = find_files(root, names=("Dockerfile",))
    agent_dfs = [p for p in dfs if "agent" in p.replace(os.sep, "/").lower()]
    targets = agent_dfs or dfs
    if not targets:
        add("WARN", "No agent Dockerfile found", "")
        return
    for p in targets:
        src, rel = read(p), os.path.relpath(p, root)
        if re.search(r'--platform[=\s]+linux/arm64', src):
            add("PASS", "Dockerfile: linux/arm64", rel)
        else:
            add("FAIL", "Dockerfile: not pinned to linux/arm64", f"{rel} — AgentCore is arm64-only")


def check_build_scripts(root):
    scripts = [p for p in find_files(root, suffixes=(".sh",)) if "build" in os.path.basename(p).lower()]
    buildx = [(p, read(p)) for p in scripts if "buildx" in read(p)]
    if not buildx:
        add("WARN", "No buildx build script found", "skipping provenance/sbom check")
        return
    for p, src in buildx:
        rel = os.path.relpath(p, root)
        if "--provenance=false" in src and "--sbom=false" in src:
            add("PASS", "buildx: --provenance=false --sbom=false", rel)
        else:
            add("FAIL", "buildx: missing --provenance=false --sbom=false",
                f"{rel} — manifest list rejected by CreateAgentRuntime ('image does not exist')")


def check_opennext(root):
    cfgs = find_files(root, names=("open-next.config.ts", "open-next.config.js"))
    if not cfgs:
        add("WARN", "No open-next.config.ts", "SSE will buffer on Lambda without aws-lambda-streaming")
        return
    for p in cfgs:
        src, rel = read(p), os.path.relpath(p, root)
        if "aws-lambda-streaming" in src:
            add("PASS", "OpenNext: aws-lambda-streaming wrapper", rel)
        else:
            add("FAIL", "OpenNext: missing aws-lambda-streaming wrapper",
                f"{rel} — SSE response will be buffered")


def check_tool_card_parity(root):
    # Python @tool names
    tool_names = set()
    for p in find_files(root, suffixes=(".py",)):
        if "agent" not in p.replace(os.sep, "/").lower():
            continue
        src = read(p)
        for m in re.finditer(r'@tool\s*(?:\([^)]*\))?\s*\n\s*(?:async\s+)?def\s+(\w+)', src):
            tool_names.add(m.group(1))
    if not tool_names:
        add("WARN", "No Python @tool functions found", "skipping tool↔card parity check")
        return
    # Frontend card switch cases. Skip the bridge route (its switch maps AG-UI events, not tools)
    # and ignore SCREAMING_SNAKE cases (AG-UI event names) — tool names are snake_case lowercase.
    card_cases = set()
    for p in find_files(root, suffixes=(".tsx", ".ts")):
        src = read(p)
        if "createUIMessageStream" in src or "InvokeAgentRuntime" in src:
            continue  # this is the route bridge, not a card renderer
        if "toolName" in src or "ToolInvocation" in src or "dynamic-tool" in src:
            # switch/case form (garri) and if (toolName === "...") form (elko)
            for m in re.finditer(r'case\s*["\'](\w+)["\']', src):
                name = m.group(1)
                if name and not name.isupper():  # drop AG-UI event-name cases
                    card_cases.add(name)
            for m in re.finditer(r'toolName\s*===\s*["\'](\w+)["\']', src):
                name = m.group(1)
                if name and not name.isupper():
                    card_cases.add(name)
    missing = tool_names - card_cases
    extra = card_cases - tool_names - {"text", "dynamic-tool", "step-start"}
    if not card_cases:
        add("WARN", "No frontend card switch found", f"tools: {sorted(tool_names)}")
        return
    if missing:
        add("FAIL", "Tools with no frontend card case", f"{sorted(missing)} → card returns null silently")
    else:
        add("PASS", "Every Python tool has a card case", f"{sorted(tool_names)}")
    if extra:
        add("WARN", "Card cases with no matching tool", f"{sorted(extra)} (maybe renamed?)")


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    if not os.path.isdir(root):
        print(f"{RED}Not a directory: {root}{RESET}")
        return 2
    print(f"{DIM}agui_doctor — scanning {root}{RESET}\n")
    for chk in (check_route, check_docker, check_build_scripts, check_opennext, check_tool_card_parity):
        try:
            chk(root)
        except Exception as e:  # never crash the whole scan on one check
            add("WARN", f"{chk.__name__} errored", str(e))

    color = {"PASS": GRN, "WARN": YEL, "FAIL": RED}
    for level, title, detail in results:
        line = f"{color[level]}[{level}]{RESET} {title}"
        if detail:
            line += f"  {DIM}{detail}{RESET}"
        print(line)

    fails = sum(1 for r in results if r[0] == "FAIL")
    warns = sum(1 for r in results if r[0] == "WARN")
    passes = sum(1 for r in results if r[0] == "PASS")
    print(f"\n{GRN}{passes} pass{RESET}  {YEL}{warns} warn{RESET}  {RED}{fails} fail{RESET}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
