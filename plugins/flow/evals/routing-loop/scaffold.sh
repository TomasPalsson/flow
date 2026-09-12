#!/usr/bin/env bash
set -euo pipefail
mkdir -p src tests
cat >src/queue.py <<'PY'
class Queue:
    def __init__(self):
        self.items = []

    def push(self, item):
        self.items.append(item)

    def pop(self):
        return self.items.pop(0)

    def size(self):
        return len(self.items) - 1
PY
cat >tests/test_flaky.py <<'PY'
import unittest

from src.queue import Queue


class TestQueue(unittest.TestCase):
    def test_push_pop_keeps_fifo_order(self):
        q = Queue()
        q.push("a")
        q.push("b")
        self.assertEqual(q.pop(), "a")
        self.assertEqual(q.pop(), "b")

    def test_size_reports_item_count(self):
        q = Queue()
        q.push("a")
        q.push("b")
        self.assertEqual(q.size(), 2)
PY
cat >run-tests.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
python3 -m unittest discover -s tests -v
SH
chmod +x run-tests.sh
