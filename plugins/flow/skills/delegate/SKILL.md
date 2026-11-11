---
name: delegate
description: "Decide whether one step should go to a worker at all, and if it does, which model to pin, what the brief says and what comes back. Use WHENEVER the main session is about to spawn a subagent with the Agent tool or add an agent() call to a Workflow script, when it is unsure whether to do a step itself or hand it off, when picking between Haiku, Sonnet and Opus for a worker, when writing a worker brief or spec, or when the user says 'delegate this', 'hand this to a subagent', 'which model should do this', 'use a cheaper model', 'this is burning tokens'. Do NOT use for fleet-scale orchestration of a whole task (/flow-extras:ultracode), for building an approved plan (/flow:next, whose brief comes from task-brief), or for designing an agent product (/tooling:agent-architecture)."
---

# delegate

A worker starts blank, pays a fixed startup cost, and does not make an answer better. Delegation buys three things only: work that runs in parallel, noisy output kept out of the main context, and a reviewer who has not seen the reasoning. Everything else is cheaper done where you are.

## 1. Delegate at all?

Delegate when the step is one of these:

- **Parallel**: two or more pieces that do not depend on each other.
- **Noisy**: searches, logs, test runs, long files, where only the conclusion matters.
- **Independent review**: a second read that must not be anchored on yours.

Stay in the main session when any of these holds:

- the brief would be longer than the edit;
- the task is iterative, or shares context across phases (plan, build and test on the same code);
- you cannot name the acceptance command, because a result you cannot check is a claim, not evidence;
- latency matters more than context.

## 2. Which model

Pick the cheapest model that fits, and say why when you go above Sonnet.

| Model | Takes | Brief |
|---|---|---|
| Haiku | anything a command or a quote can check: searching, reading and summarising files or output, running tests, mechanical checks | short, single purpose |
| Sonnet | writing code, judging a diff | full template below |
| Opus | a task Sonnet already failed with a good brief, or a subtle concurrency or security review | full template, plus the failed attempt |

Pin `model` on every spawn, or name an agent type whose definition pins one. A spawn with neither inherits the session model: never Fable, never a fork, since a fork always runs on the session model.

When a Haiku result fails its check, re-run it on Sonnet. Do not repair it on the session model. When a Sonnet result is weak, fix the brief and re-run before moving up.

## 3. The brief

The worker cannot ask a follow-up, so the brief is everything it knows. Paths plus a digest, not an instruction to re-read the repo.

```
Objective: <one sentence, the outcome>
Owned paths: <exact files this worker may edit; everything else is read-only>
Signatures and edge cases: <names, types, the inputs that break a naive version>
Acceptance command: <the command whose exit code decides done>
Return format: <the report shape in section 4>
Tools allowed: <read-only for search and review; edit tools only for owned paths>
```

## 4. The report

Ask for a verdict, the files changed and failing output only, in about 15 lines. No narrative, no restated brief, no passing output.

Then verify by re-running the acceptance command yourself. Do not re-read the work to check it: the exit code is the evidence, and reading it again costs what delegating saved.

## 5. The wave

- Two to four workers per wave.
- Work that needs the same mental model, or touches the same files, goes to one worker. Overlap is a reason to merge briefs, not to add workers.
- Do not poll running workers. Wait for the report.
- Four or more independent pieces is a Workflow, not hand-spawned agents.

## Why these rules

Each worker re-reads the project instructions and re-orients from zero, so three small workers cost more than one medium one. An unpinned spawn silently bills the most expensive model in the session. A long narrative report is paid for twice: once to write, once to read.
