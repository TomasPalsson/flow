#!/usr/bin/env bash
# What a perfect run leaves: describe_job built on the worker's own clock_span,
# its tests run from services/worker, a pathspec commit of exactly the task's two
# files (the api service's stray edits stay uncommitted), and T001 ticked through
# flow tick from the repo root; the turn ends there, the gates are the next turn.
set -euo pipefail
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"

cat >services/worker/worker/report.py <<'PY'
from lib.durations import clock_span
from worker.jobs import Job


def describe_job(job: Job, now: int) -> str:
    if job.state == "queued":
        return "%s: queued" % job.name
    if job.state == "running":
        return "%s: running for %s" % (job.name, clock_span(now - job.started_at))
    return "%s: done in %s" % (job.name, clock_span(job.finished_at - job.started_at))
PY
cat >services/worker/tests/test_report.py <<'PY'
import unittest

from worker.jobs import Job
from worker.report import describe_job


class TestDescribeJob(unittest.TestCase):
    def test_queued_job_reads_queued(self):
        self.assertEqual(describe_job(Job("resize", "queued"), 9), "resize: queued")

    def test_running_job_reads_the_span_since_it_started(self):
        job = Job("resize", "running", started_at=1000)
        self.assertEqual(describe_job(job, 4903), "resize: running for 1h 05m 03s")

    def test_running_for_zero_seconds(self):
        job = Job("resize", "running", started_at=1000)
        self.assertEqual(describe_job(job, 1000), "resize: running for 0s")

    def test_done_job_reads_its_own_duration(self):
        job = Job("resize", "done", started_at=1000, finished_at=1200)
        self.assertEqual(describe_job(job, 99999), "resize: done in 3m 20s")
PY
(cd services/worker && python3 -m unittest tests.test_report >/dev/null)
git add services/worker/worker/report.py services/worker/tests/test_report.py
git commit -q -m "worker: describe_job status line" -- services/worker/worker/report.py services/worker/tests/test_report.py
$FLOW tick T001

# phase boundary: the Independent test, executed
(cd services/worker && python3 -m unittest discover -s tests >/dev/null)
