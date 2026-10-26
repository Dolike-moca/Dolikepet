"""Exercise real asynchronous HTTP/downloads against a local fixture server."""
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import argparse, hashlib, io, json, os, re, subprocess, threading, time, uuid, zipfile

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / 'Game/Godot'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, default=ROOT / '_tools/runtime/godot-build/godot/Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--pack', type=Path)
    args = parser.parse_args()
    out = ROOT / '_work/tests/auto-update' / uuid.uuid4().hex
    out.mkdir(parents=True)
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as archive:
        archive.writestr('Dolikepet/fixture.txt', b'isolated update test\n' * 16000)
    payload = stream.getvalue()
    digest = hashlib.sha256(payload).hexdigest()
    requests = {}
    current = re.search(r'config/version="([^"]+)"', (GAME/'project.godot').read_text(encoding='utf-8'))[1]
    major, minor, patch = map(int, current.split('.'))
    newer_version = f'{major}.{minor}.{patch+1}'

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args): pass
        def do_GET(self):
            try:
                requests[self.path] = requests.get(self.path, 0) + 1
                category, scenario = self.path.strip('/').split('/')
                if category == 'feed':
                    if scenario == 'offline' and requests[self.path] == 1:
                        self.send_error(503); return
                    version = current if scenario == 'current' else newer_version
                    repo = 'https://github.com/Dolike-moca/Dolikepet'
                    data = dict(schema=1, channel='stable', platform='windows-x86_64', version=version,
                        release_url=repo+'/releases/tag/'+version,
                        download_url=repo+'/releases/download/'+version+'/Dolikepet-'+version+'-windows-x64.zip',
                        size_bytes=len(payload), sha256=digest)
                    if scenario == 'bad-manifest': data['download_url'] = 'http://example.invalid/untrusted.exe'
                    body = json.dumps(data).encode()
                else:
                    if scenario == 'http-error': self.send_error(503); return
                    body = payload
                    if scenario == 'wrong-hash': body = b'X' + body[1:]
                    if scenario == 'oversized': body += b'x'*1000
                    if scenario == 'truncated':
                        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
                        self.wfile.write(body[:100]); self.wfile.flush(); self.close_connection = True; return
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                if scenario == 'slow':
                    for offset in range(0, len(body), 8192):
                        self.wfile.write(body[offset:offset+8192]); self.wfile.flush(); time.sleep(.05)
                else: self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError): pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    command = [str(args.engine), '--headless']
    command += ['--main-pack', str(args.pack)] if args.pack else ['--path', str(GAME)]
    command += ['--script', str(GAME/'tests/test_auto_update.gd'), '--', '--server=http://127.0.0.1:'+str(server.server_port), '--fixture='+str(out/'隔离 更新缓存')]
    try:
        result = subprocess.run(command, cwd=ROOT, env=dict(os.environ, APPDATA=str(out/'appdata')), capture_output=True, timeout=150)
        output = (result.stdout+result.stderr).decode('utf-8', errors='replace')
        (out/'test.log').write_text(output, encoding='utf-8')
        passed = result.returncode == 0 and 'ERROR:' not in output and 'Parse Error:' not in output and re.search(r'AUTO UPDATE: \d+ checks, 0 failures', output) is not None
        report = {'passed': passed, 'exitCode': result.returncode, 'requests': requests, 'log': str(out/'test.log'), 'pack': str(args.pack) if args.pack else None}
        (ROOT/'_work/tests/auto-update-result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(output)
        print(json.dumps(report))
        raise SystemExit(0 if passed else 1)
    finally:
        server.shutdown(); server.server_close()

if __name__ == '__main__': main()
