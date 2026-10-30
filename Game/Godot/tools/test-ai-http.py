"""Exercise the Godot streaming transport with isolated local HTTP responses.

Usage: python test-ai-http.py --godot <console.exe> [--pack <candidate.pck>]
No real credentials, paid requests, or player data are used.
"""
from argparse import ArgumentParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import subprocess
import threading
import time


def sse(kind, **values):
    return ("data: " + json.dumps({"type": kind, **values}, ensure_ascii=False) + "\n\n").encode("utf-8")


class Fixture(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    received = []
    errors = []

    def log_message(self, *_args):
        pass

    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass  # Cancellation/early error rejection deliberately closes TCP.

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        data = json.loads(body)
        self.received.append(self.path)
        if self.headers.get("Authorization") != "Bearer fixture-key-never-real":
            self.errors.append("Unexpected fixture authorization")
        if data.get("stream") is not True or data.get("store") is not False:
            self.errors.append("Request must be streaming and store=false")
        if self.path == "/empty-status/401":
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path.startswith("/status/"):
            code = int(self.path.rsplit("/", 1)[-1])
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            if code == 302:
                self.send_header("Location", f"http://127.0.0.1:{self.server.server_port}/must-not-follow")
            self.send_header("Content-Length", "15")
            self.end_headers()
            self.wfile.write(b"raw-server-body")
            return
        if self.path in ("/cancel", "/timeout"):
            time.sleep(1)
        if self.path == "/wrong-type":
            chunks = [b'{"wrong":"type"}']
            content_type = "application/json"
        elif self.path == "/truncated":
            chunks = [sse("response.output_text.delta", delta="半句话")]
            content_type = "text/event-stream"
        else:
            chunks = [sse("response.created", response={"status": "in_progress"}),
                      sse("response.output_text.delta", delta="你好喵！"),
                      sse("response.output_text.delta", delta="陪你一会儿。"),
                      sse("response.completed", response={"status": "completed"})]
            content_type = "text/event-stream; charset=utf-8"
        try:
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(sum(map(len, chunks))))
            self.end_headers()
            for chunk in chunks:
                # UTF-8 characters deliberately cross HTTPClient reads.
                for offset in range(0, len(chunk), 7):
                    self.wfile.write(chunk[offset:offset+7])
                    self.wfile.flush()
                    time.sleep(.002)
                time.sleep(.06)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass


def main():
    parser = ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--pack")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    out = project.parents[1] / "_work" / "ai-gpt" / "http-fixture"
    out.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    command = [args.godot, "--headless", "--path", str(project)]
    if args.pack:
        command += ["--main-pack", args.pack]
    command += ["--script", str(project / "tests" / "test_ai_http_fixture.gd"),
                "--log-file", str(out / "godot.log"), "--", f"--endpoint=http://127.0.0.1:{server.server_port}"]
    environment = os.environ.copy()
    environment["APPDATA"] = str(out / "appdata")
    try:
        result = subprocess.run(command, env=environment, capture_output=True, text=True, encoding="utf-8", timeout=90)
    finally:
        server.shutdown()
        server.server_close()
    (out / "output.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    errors = Fixture.errors.copy()
    if "/must-not-follow" in Fixture.received:
        errors.append("Redirect followed with a credential")
    if Fixture.received.count("/stream") != 2:
        errors.append("Streaming fixture request was duplicated or missing")
    report = {"exitCode": result.returncode, "requests": Fixture.received, "fixtureErrors": errors}
    (out / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(result.stdout)
    print(result.stderr)
    print(json.dumps(report))
    raise SystemExit(result.returncode or int(bool(errors)))


if __name__ == "__main__":
    main()
