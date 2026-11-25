---
name: recon
description: How to read a repo for a moonshot brief - delight signals, raw material, and how to read recon.mjs output for accepted constraints and priced-out wishes (signal families, the load-bearing test, the stall signature).
---

# Recon: what is fun here, what it is made of, what it puts up with

The brief has three parts, in this order of weight. Recon.mjs helps with the third only; the first two come from
reading.

## Delight signals

What the owner built that nobody needed, and what they said they like. These set the taste every card must hit.
- Side features with no requirement behind them: easter eggs, widgets, a lab, generated art, a voice, a puzzle, a
  custom look. `git log --oneline | grep -i -E "fun|toy|easter|widget|art|sound|voice|game"` and the README's tour.
- Words in commits, docs and rulings: "fun", "love", "I like", "cool", and the opposite ("hates", "boring",
  "no X blocks"). Quote them with `path:line`; a dislike is as useful as a like.
- Where effort went past what the task needed (a hand-tuned design system, 60 variants of one small thing).
- The owner's reactions recorded in notes ("Lgtm", "I like A", "go for B") show what they pick when shown options.

## Raw material

What this project has that a generic idea could not use. Count it; the generator only knows what the brief says.
- The archive: how many issues, days, records, images, audio files, since when (`ls | wc -l`, sizes).
- The owner's own data: marks, votes, labels, reading history, a taste profile, logs of every model call.
- The machine: hardware named in the docs (a graphics card, a home server, devices on the network), models that
  run locally, voices, schedulers, anything physical.
- Existing organs that could be repurposed: a renderer, a narrator, a collector, a judge, a puzzle generator.
- The setting: language, place, the owner's field.

## Accepted constraints and priced-out wishes


The target is a **layer or dependency**, not a file: hotspot tools find the expensive file, but a moonshot replaces
a boundary (CEF, a hand-rolled ORM, a runtime, a pipeline stage). Roll file evidence up to the directory or
dependency that owns the constraint.

## The signal families

A candidate needs evidence from at least 2 (a default, not a law; say which fired and which were not measured).
One family alone is how cosmetic ugliness gets nominated. On a repo with under about 6 months of history, churn,
stall and aged workarounds cannot fire; the first row, weight and drift carry it, and that is enough.

| Family | Where | Fires when |
|---|---|---|
| Rulings and stated limits | the owner's docs: README, PROGRESS, ADRs, design notes, specs | a ruling turns a limitation into policy ("X is a first-class outcome", "under 1 GB, not under 500 MB"), or a stated number caps the product (0.33 conversions a month, 100 clips a day). The clearest receipt there is, and recon cannot see it |
| Priced-out wishes | `priced-out` (lines in the owner's docs that defer, cap or do by hand), then read the docs around each hit | the owner wanted something and wrote down why not: "for now", "would need", "too slow", "by hand", "blocked by". The price was set in human time; ask what it costs with agents. A wish with a cost attached is the closest thing to the owner asking for the moonshot. The list is a keyword match, so most hits are noise: keep the ones where a capability was given up |
| Fix churn | `directories`, `files` | fix share high relative to the repo, not just many commits. Raw churn ranks manifests, docs and tests; recon already excludes those, and lists directories with no code file last, flagged `data-only` (generated content, images): ignore their commit counts |
| Stall | `directories` STALL rows | fixes in 4+ distinct months with flat net growth: "months of small tweaks went nowhere" |
| Aged workarounds with fan-in | `workarounds` | markers older than a year that survived nearby edits, in 3+ directories that name the same component |
| Dependency weight vs used surface | `dependencies` HEAVY-NARROW, `large-files` | a large dependency imported from a handful of files: the CEF shape. A heavy dependency used everywhere is not a candidate. Manifests are read from the root and up to three levels down. Recon assumes a Python import name equals the package name, so grep before trusting an `unused` entry (`google-ads` imports as `google.ads`, Pillow as `PIL`) |
| Performance layer share | not in recon; only if the app runs | profile grouped by library (`perf report --sort dso`, the language profiler's per-package view): "40% of samples in libX" fires, "top function 3%" does not |
| Baseline drift | manual: `git log -p -S'<key>' -- <config>` on timeout, retry, interval, max_ keys | a knob that only ever goes up (5s, 15s, 60s), CI retries, "if it fails, rerun" in docs: each deviation became the new normal |

Name each constraint at the level of what the product can or cannot do ("the loop cannot tell whether a change
worked", "every voice line waits on a 100-a-day quota"), then the code that holds it there. A constraint named at the
code level ("two copies of `_http.py`") yields a cleanup. Do not ask the owner an open "what is ugly?"; the people closest to it
stopped seeing it. Show them the 3 to 5 you found, with what each costs, and let them say which one is worth losing.

For each constraint also write down **what it costs the owner**, from the docs and the data, not from taste: minutes
of waiting, runs that fail, steps done by hand, things the product declines to do. A constraint with no cost anyone
pays is cosmetic however large the code behind it.

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
- The constraint is one the owner chose (who the project is for, what stays private, what must not cost money): it is
  a ruling, not a candidate. List it in the brief and leave it.
- The hottest constraint is dull (a flaky fetcher, a slow build): note it as a quick win and move on. The brief
  wants the constraints whose removal would be fun to watch.
- The constraint is real (regulation, a contract, physics): a moonshot that deletes it is fantasy. Ask who imposes it
  and whether that can change; "unlimited engineering" does not buy outside cooperation.
- Solo repos: ownership signals cannot fire; do not print zeros as evidence.
