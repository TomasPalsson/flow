import unittest

from worker.jobs import Job
from worker.report import describe_job


class TestDescribeJobHidden(unittest.TestCase):
    def test_queued_job(self):
        self.assertEqual(describe_job(Job("resize", "queued"), 5000), "resize: queued")

    def test_running_job_reads_the_span_since_it_started(self):
        job = Job("resize", "running", started_at=1000)
        self.assertEqual(describe_job(job, 4903), "resize: running for 1h 05m 03s")

    def test_running_for_zero_seconds(self):
        job = Job("resize", "running", started_at=1000)
        self.assertEqual(describe_job(job, 1000), "resize: running for 0s")

    def test_running_for_minutes(self):
        job = Job("index", "running", started_at=0)
        self.assertEqual(describe_job(job, 303), "index: running for 5m 03s")

    def test_done_job_reads_its_own_duration_not_the_time_since(self):
        job = Job("resize", "done", started_at=1000, finished_at=1200)
        self.assertEqual(describe_job(job, 99999), "resize: done in 3m 20s")

    def test_done_in_under_a_minute(self):
        job = Job("resize", "done", started_at=50, finished_at=92)
        self.assertEqual(describe_job(job, 0), "resize: done in 42s")

    def test_done_instantly(self):
        job = Job("resize", "done", started_at=7, finished_at=7)
        self.assertEqual(describe_job(job, 7), "resize: done in 0s")

    def test_the_name_is_printed_in_full(self):
        name = "a-very-long-job-name-that-shorten-would-cut"
        self.assertEqual(describe_job(Job(name, "queued"), 0), name + ": queued")
