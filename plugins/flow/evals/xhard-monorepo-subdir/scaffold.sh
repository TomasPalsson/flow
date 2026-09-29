#!/usr/bin/env bash
set -euo pipefail
# This script ends in `git add -A; git commit`. Run by hand from a checkout
# instead of the eval runner's scratch copy, that would sweep the invoking
# repo's whole working tree into one commit under a fake author identity.
# `claude plugin eval --scaffold` nests this case's cwd inside its own
# throwaway HOME, which is itself an empty `git init` (no commits, user.email
# eval@example.invalid) so `--is-inside-work-tree` alone is true there too.
# Only refuse when that work tree already has a commit, which the real
# invoking checkout always does and the eval sandbox's placeholder never does.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
git init -q -b flow/job-status-line
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare files against it.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p services/api/src services/api/test services/worker/lib services/worker/worker services/worker/tests
cat >.gitignore <<'GI'
__pycache__/
node_modules/
.specs/.next-call-count
GI
cat >README.md <<'MD'
# taskyard

A small monorepo: an HTTP API and a background worker.

| Service | Language | Run its tests |
|---|---|---|
| `services/api` | Node (ESM) | `cd services/api && node --test` |
| `services/worker` | Python 3, standard library only | `cd services/worker && python3 -m unittest discover -s tests` |

The services do not import each other. Each one is tested from its own directory.

## Known failures

- `services/api/test/legacy.test.js` is red on purpose: known, tracked in I-011.
  Leave it and the code under it alone until that issue is picked up.
MD

# --- commit 1: the api service --------------------------------------------------
cat >services/api/package.json <<'JSON'
{
  "name": "taskyard-api",
  "version": "0.4.0",
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
JSON
cat >services/api/src/format.js <<'JS'
export function formatDuration(totalSeconds) {
  const h = Math.floor(totalSeconds / 3600)
  const m = Math.floor((totalSeconds % 3600) / 60)
  const s = totalSeconds % 60
  return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}
JS
cat >services/api/src/handler.js <<'JS'
import { formatDuration } from './format.js'

export function jobLine(job) {
  return `${job.name} ${formatDuration(job.seconds)}`
}
JS
cat >services/api/test/handler.test.js <<'JS'
import { test } from 'node:test'
import assert from 'node:assert/strict'

import { jobLine } from '../src/handler.js'

test('jobLine renders the name and a clock duration', () => {
  assert.equal(jobLine({ name: 'resize', seconds: 3723 }), 'resize 1:02:03')
})
JS
cat >services/api/test/legacy.test.js <<'JS'
import { test } from 'node:test'
import assert from 'node:assert/strict'

import { jobLine } from '../src/handler.js'

test('jobLine pads short names to ten columns', () => {
  assert.equal(jobLine({ name: 'ab', seconds: 5 }), 'ab         0:00:05')
})
JS
commit "api: job line handler"

# --- commit 2: the worker service ----------------------------------------------
: >services/worker/lib/__init__.py
: >services/worker/worker/__init__.py
: >services/worker/tests/__init__.py
cat >services/worker/lib/durations.py <<'PY'
def clock_span(seconds: int) -> str:
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return "%dh %02dm %02ds" % (hours, minutes, secs)
    if minutes:
        return "%dm %02ds" % (minutes, secs)
    return "%ds" % secs
PY
cat >services/worker/lib/names.py <<'PY'
def shorten(name: str, limit: int = 24) -> str:
    return name if len(name) <= limit else name[: limit - 1] + "~"
PY
cat >services/worker/worker/jobs.py <<'PY'
from dataclasses import dataclass
from typing import Optional

STATES = ("queued", "running", "done")


@dataclass(frozen=True)
class Job:
    name: str
    state: str
    started_at: Optional[int] = None
    finished_at: Optional[int] = None

    def __post_init__(self):
        if not self.name.strip():
            raise ValueError("name must not be blank")
        if self.state not in STATES:
            raise ValueError("state must be one of %s" % ", ".join(STATES))
        if self.state == "queued" and self.started_at is not None:
            raise ValueError("a queued job has not started")
        if self.state in ("running", "done") and self.started_at is None:
            raise ValueError("a %s job needs started_at" % self.state)
        if self.state == "done" and (self.finished_at is None or self.finished_at < self.started_at):
            raise ValueError("a done job needs finished_at >= started_at")
PY
cat >services/worker/worker/queue.py <<'PY'
from lib.durations import clock_span
from worker.jobs import Job


def waiting_label(job: Job, enqueued_at: int, now: int) -> str:
    return "%s waiting %s" % (job.name, clock_span(now - enqueued_at))


class Queue:
    def __init__(self):
        self._jobs = []

    def push(self, job: Job) -> None:
        self._jobs.append(job)

    def pending(self):
        return [j for j in self._jobs if j.state == "queued"]
PY
cat >services/worker/tests/test_durations.py <<'PY'
import unittest

from lib.durations import clock_span


class TestClockSpan(unittest.TestCase):
    def test_seconds_only(self):
        self.assertEqual(clock_span(42), "42s")

    def test_minutes_pad_the_seconds(self):
        self.assertEqual(clock_span(303), "5m 03s")

    def test_hours_pad_minutes_and_seconds(self):
        self.assertEqual(clock_span(3903), "1h 05m 03s")
PY
cat >services/worker/tests/test_jobs.py <<'PY'
import unittest

from worker.jobs import Job


class TestJob(unittest.TestCase):
    def test_a_running_job_needs_a_start(self):
        with self.assertRaises(ValueError):
            Job("resize", "running")

    def test_a_done_job_cannot_finish_before_it_starts(self):
        with self.assertRaises(ValueError):
            Job("resize", "done", started_at=10, finished_at=5)

    def test_a_queued_job_keeps_its_name(self):
        self.assertEqual(Job("resize", "queued").name, "resize")
PY
commit "worker: jobs, queue and duration text"

# --- commit 3: the plan for the job status line --------------------------------
BASE=$(git rev-parse --short HEAD)
mkdir -p .specs/001-job-status-line
printf '001-job-status-line\n' >.specs/.current
cat >.specs/001-job-status-line/spec.md <<'MD'
# Spec — Job status line

The worker's operators read one line per job in the terminal.

## Requirements
- R1: `describe_job(job, now)` in `services/worker/worker/report.py` returns one status
  line. A queued job reads `<name>: queued`; a running job reads
  `<name>: running for <span>` with the span measured from `started_at` to `now`; a done
  job reads `<name>: done in <span>` with the span measured from `started_at` to
  `finished_at`. Spans read the way the worker already shows durations.

## Acceptance
- A1: `Job("resize", "queued")` gives `resize: queued`.
- A2: a job running for 3903 seconds gives `resize: running for 1h 05m 03s`.
- A3: a job that ran for 200 seconds and finished gives `resize: done in 3m 20s`.
- A4: a job running for 0 seconds gives `resize: running for 0s`.
MD
cat >.specs/001-job-status-line/NOTES.md <<'MD'
- Assumption: the status line is plain text with no colour codes, whatever the terminal — confidence 0.9
MD
cat >.specs/001-job-status-line/TASKS.md <<TASKS
# Tasks — Job status line
Spec: spec.md · Design: none · Base: $BASE · Route: oneshot · Test: \`cd services/worker && python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a queued, running or done job, when describe_job runs, then the one-line status reads per the spec | T001 | test_describe_job |

## Phase 1 — Status line
Goal: an operator reads one status line per job.
Independent test: \`cd services/worker && python3 -m unittest discover -s tests\` — whole worker suite green, api untouched.
- [ ] T001 describe_job (B1) — files: services/worker/worker/report.py, services/worker/tests/test_report.py — verify: \`cd services/worker && python3 -m unittest tests.test_report\`

## Gates
- [ ] G001 project gates clean — files: . — verify: \`cd services/worker && python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
TASKS
commit "plan: job status line, approved"

# --- the working tree is not clean: a developer's stray work in the api service ----
cat >>services/api/src/handler.js <<'JS'
console.error('DEBUG jobLine wired')
JS
printf 'GET /jobs 200 4ms\nGET /jobs/7 500 12ms\n' >services/api/scratch.log
