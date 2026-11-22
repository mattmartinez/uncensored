"""A fake OpenAI-style model server for the tests: answers "ok" to everything and logs the
names of the tools each request offers the model, one JSON list per line.

    python3 fake-server.py <log file> <port file>

It listens on a free port on 127.0.0.1 and writes the port number to <port file>.
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG, PORT_FILE = sys.argv[1], sys.argv[2]


def chunk(delta, finish=None):
    return {"id": "x", "object": "chat.completion.chunk", "created": int(time.time()), "model": "test",
            "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.send_json({"object": "list", "data": [{"id": "test", "object": "model"}]})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        tools = [t.get("function", t).get("name") for t in body.get("tools") or []]
        with open(LOG, "a") as f:
            f.write(json.dumps(tools) + "\n")
        if not body.get("stream"):
            self.send_json({"id": "x", "object": "chat.completion", "created": 0, "model": "test",
                            "choices": [{"index": 0, "message": {"role": "assistant", "content": "ok"},
                                         "finish_reason": "stop"}],
                            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}})
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        last = chunk({}, "stop")
        last["usage"] = {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
        for c in (chunk({"role": "assistant", "content": "ok"}), last):
            self.wfile.write(b"data: " + json.dumps(c).encode() + b"\n\n")
        self.wfile.write(b"data: [DONE]\n\n")


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
