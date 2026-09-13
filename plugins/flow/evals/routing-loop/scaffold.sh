#!/usr/bin/env bash
set -euo pipefail
# The source is correct on purpose: a bug you can see by reading invites a
# direct fix, and a model with no Bash cannot learn why the integration
# suite is red - handing it to the loop is the only move that runs the check.
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
        return len(self.items)
PY
cat >src/api.py <<'PY'
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

from src.queue import Queue

QUEUE = Queue()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        QUEUE.push(json.loads(self.rfile.read(length)))
        self.send_response(202)
        self.end_headers()

    def do_GET(self):
        body = json.dumps({"size": QUEUE.size()}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def serve(port):
    return HTTPServer(("127.0.0.1", port), Handler)
PY
cat >tests/test_integration.py <<'PY'
import json
import threading
import unittest
import urllib.request

from src.api import serve

PORT = 8765


class TestQueueOverHttp(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = serve(PORT)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def test_post_then_get_reports_size(self):
        req = urllib.request.Request(f"http://127.0.0.1:{PORT}/", data=json.dumps({"job": 1}).encode(), method="POST")
        urllib.request.urlopen(req, timeout=2)
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/", timeout=2) as resp:
            self.assertEqual(json.loads(resp.read())["size"], 1)

    def test_get_on_fresh_server_is_zero(self):
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/", timeout=2) as resp:
            self.assertEqual(json.loads(resp.read())["size"], 0)
PY
cat >run-tests.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
python3 -m unittest discover -s tests -v
SH
chmod +x run-tests.sh
