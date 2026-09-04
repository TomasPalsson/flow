#!/usr/bin/env python3
"""Introspect the *installed* strands-agents SDK and print ground truth for steering hooks.

The Strands SDK ships weekly and renames things; this skill's docs are a snapshot. Run this
first and trust its output over any document if they disagree.

    python introspect_strands_hooks.py

It reports: installed version; every hook event and its WRITABLE fields (the steering levers,
read straight from each event's `_can_write` allowlist); the `HookOrder` constants; whether
steering is at the stable `strands.vended_plugins.steering` or only the deprecated
`strands.experimental.steering`; and the Intervention/Plugin entry points. Pure stdlib +
strands; no other dependencies. Never hard-crashes — it reports what it can and what it can't.
"""
from __future__ import annotations

import importlib
import inspect
import re
import warnings

GREEN, YELLOW, RED, DIM, BOLD, END = "\033[32m", "\033[33m", "\033[31m", "\033[2m", "\033[1m", "\033[0m"


def _h(title: str) -> None:
    print(f"\n{BOLD}== {title} =={END}")


def _try(fn, default=None):
    try:
        return fn()
    except Exception as exc:  # noqa: BLE001 — diagnostic tool, report not raise
        return ("__err__", exc) if default is None else default


def version() -> None:
    _h("Installed version")
    try:
        from importlib.metadata import version as v

        print(f"  strands-agents {GREEN}{v('strands-agents')}{END}")
    except Exception as exc:  # noqa: BLE001
        print(f"  {RED}could not read version: {exc}{END}")
        print(f"  {DIM}is strands-agents installed in this environment?{END}")


def _writable_fields(cls) -> str:
    """Extract the writable-field allowlist from a class's own _can_write override."""
    can = cls.__dict__.get("_can_write")
    if can is None:
        return f"{DIM}none (inherits read-only){END}"
    src = _try(lambda: inspect.getsource(can), default="")
    if not src:
        return f"{DIM}(override present; source unavailable){END}"
    names = re.findall(r"""["']([A-Za-z_][A-Za-z0-9_]*)["']""", src)
    return f"{GREEN}{', '.join(dict.fromkeys(names))}{END}" if names else f"{DIM}(dynamic){END}"


def events() -> None:
    _h("Hook events + writable steering levers (from strands.hooks)")
    mod = _try(lambda: importlib.import_module("strands.hooks"))
    if not mod or isinstance(mod, tuple):
        print(f"  {RED}cannot import strands.hooks{END}")
        return
    names = [n for n in dir(mod) if n.endswith("Event")]
    if not names:
        print(f"  {YELLOW}no *Event names exported{END}")
    for name in sorted(names):
        cls = getattr(mod, name)
        if not inspect.isclass(cls):
            continue
        interruptible = any(b.__name__ == "_Interruptible" for b in inspect.getmro(cls))
        tag = f"  {DIM}+interrupt(){END}" if interruptible else ""
        print(f"  {BOLD}{name}{END}: {_writable_fields(cls)}{tag}")


def hook_order() -> None:
    _h("HookOrder constants (lower runs first; After* reverse within a group)")
    mod = _try(lambda: importlib.import_module("strands.hooks"))
    HO = getattr(mod, "HookOrder", None) if mod and not isinstance(mod, tuple) else None
    if HO is None:
        print(f"  {YELLOW}HookOrder not found{END}")
        return
    consts = {k: getattr(HO, k) for k in dir(HO) if k.isupper() and isinstance(getattr(HO, k), int)}
    for k, val in sorted(consts.items(), key=lambda kv: kv[1]):
        print(f"  {val:>5}  {k}")


def steering() -> None:
    _h("Steering subsystem location (where to import from TODAY)")
    stable = _try(lambda: importlib.import_module("strands.vended_plugins.steering"))
    if stable and not isinstance(stable, tuple):
        print(f"  {GREEN}stable:{END} from strands.vended_plugins.steering import "
              "LLMSteeringHandler, SteeringHandler, LedgerProvider, Proceed, Guide, Interrupt")
    else:
        print(f"  {YELLOW}strands.vended_plugins.steering not importable in this version{END}")
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        exp = _try(lambda: importlib.import_module("strands.experimental.steering"))
        if exp and not isinstance(exp, tuple):
            dep = any(issubclass(w.category, DeprecationWarning) for w in caught)
            state = f"{YELLOW}DEPRECATED shim{END}" if dep else f"{DIM}present{END}"
            print(f"  experimental.steering: {state} {DIM}(avoid; use vended_plugins.steering){END}")


def higher_tiers() -> None:
    _h("Interventions + Plugin entry points")
    iv = _try(lambda: importlib.import_module("strands.interventions"))
    if iv and not isinstance(iv, tuple):
        actions = [n for n in ("Proceed", "Deny", "Guide", "Confirm", "Transform") if hasattr(iv, n)]
        print(f"  {GREEN}interventions:{END} Agent(interventions=[...]); actions: {', '.join(actions)}")
        meth = _try(lambda: [m for m, _ in inspect.getmembers(
            iv.InterventionHandler, predicate=inspect.isfunction)
            if m.startswith(("before_", "after_"))], default=[])
        if meth:
            print(f"            lifecycle methods: {', '.join(sorted(meth))}")
    else:
        print(f"  {YELLOW}strands.interventions not importable{END}")
    pl = _try(lambda: importlib.import_module("strands.plugins"))
    if pl and not isinstance(pl, tuple):
        have = [n for n in ("Plugin", "hook") if hasattr(pl, n)]
        print(f"  {GREEN}plugins:{END} Agent(plugins=[...]); from strands.plugins import {', '.join(have)}")


def main() -> None:
    print(f"{BOLD}Strands steering-hooks introspection{END}")
    version()
    events()
    hook_order()
    steering()
    higher_tiers()
    print(f"\n{DIM}If anything above differs from the skill docs, the SDK changed — trust this output.{END}")


if __name__ == "__main__":
    main()
