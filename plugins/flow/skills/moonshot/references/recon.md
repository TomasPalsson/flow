---
name: recon
description: How to read recon.mjs output and nominate the accepted constraint - the six signal families, the load-bearing test, the stall signature, and when to say no moonshot was found.
---

# Recon: finding the accepted constraint

The target is a **layer or dependency**, not a file: hotspot tools find the expensive file, but a moonshot replaces
a boundary (CEF, a hand-rolled ORM, a runtime, a pipeline stage). Roll file evidence up to the directory or
dependency that owns the constraint.

## The signal families

A candidate needs evidence from at least 3 (a default, not a law; say which fired and which were not measured).
One family alone is how cosmetic ugliness gets nominated. On a repo with under about 6 months of history, churn,
stall and aged workarounds cannot fire; the first row, weight and drift carry it, and that is enough.

| Family | Where | Fires when |
|---|---|---|
| Rulings and stated limits | the owner's docs: README, PROGRESS, ADRs, design notes, specs | a ruling turns a limitation into policy ("X is a first-class outcome", "under 1 GB, not under 500 MB"), or a stated number caps the product (0.33 conversions a month, 100 clips a day). The clearest receipt there is, and recon cannot see it |
| Fix churn | `directories`, `files` | fix share high relative to the repo, not just many commits. Raw churn ranks manifests, docs and tests; recon already excludes those |
| Stall | `directories` STALL rows | fixes in 4+ distinct months with flat net growth: "months of small tweaks went nowhere" |
| Aged workarounds with fan-in | `workarounds` | markers older than a year that survived nearby edits, in 3+ directories that name the same component |
| Dependency weight vs used surface | `dependencies` HEAVY-NARROW, `large-files` | a large dependency imported from a handful of files: the CEF shape. A heavy dependency used everywhere is not a candidate. Recon assumes a Python import name equals the package name, so grep before trusting an `unused` entry (`google-ads` imports as `google.ads`, Pillow as `PIL`) |
| Performance layer share | not in recon; only if the app runs | profile grouped by library (`perf report --sort dso`, the language profiler's per-package view): "40% of samples in libX" fires, "top function 3%" does not |
| Baseline drift | manual: `git log -p -S'<key>' -- <config>` on timeout, retry, interval, max_ keys | a knob that only ever goes up (5s, 15s, 60s), CI retries, "if it fails, rerun" in docs: each deviation became the new normal |

Name the constraint at the level of what the product can or cannot do ("the loop cannot tell whether a change
worked", "every voice line waits on a 100-a-day quota"), then the code that holds it there. A constraint named at the
code level ("two copies of `_http.py`") yields a cleanup. Do not ask the owner what is ugly; the people closest to it
stopped seeing it.

## The load-bearing test

All three, or it is cosmetic:
1. Removing it deletes workarounds, rulings or manual steps in other places (3+ directories, or a process the owner
   runs by hand).
2. It has resisted: fixes spread across months, or a ruling that gave up on it. One burst of fixes is not resistance.
3. Its used surface is bounded and enumerable (the features, calls or formats actually used). Unbounded surface
   means the replacement is unbounded: split it or downgrade it.

Then name the **structural cause**: the property incremental work cannot reach (a data model without stable ids, a
runtime's garbage collector over a big cache, a dependency's footprint). "Old", "ugly" or "buggy" is not a cause:
older code has had more of its bugs fixed, so replacing it for bug counts buys little.

## Disconfirming evidence

Odd-looking code often encodes a real fix. List what in the history looks like one (comments citing an issue,
a regression test nearby, a revert followed by a narrower change). Those behaviours become oracle entries in the
plan, never "cleanup".

## Edge cases

- Thin history (recon WARN): churn and stall cannot fire; rely on rulings, stated limits, weight and drift, and say so.
  Thin history never means "no moonshot".
- The hottest code is the product's reason to exist: do not nominate it; look at what it depends on.
- The constraint lives outside the repo (a vendor, a database, a CI system): git shows only the workarounds around it;
  grep for the product's name in workaround lines.
- The constraint is real (regulation, a contract, physics): a moonshot that deletes it is fantasy. Ask who imposes it
  and whether that can change; "unlimited engineering" does not buy outside cooperation.
- Solo repos: ownership signals cannot fire; do not print zeros as evidence.
