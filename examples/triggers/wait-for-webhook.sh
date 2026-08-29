#!/bin/sh
# Trigger: listen for one HTTP POST, then exit 0.
# json example: {"port":9876,"token":"change-me","path":"/hook"}
# Point Slack/GitHub/FTP-sidecar at http://<server>:9876/hook
# Header X-Ordo-Token must match token (optional if token empty).
set -eu

PORT=${TRIGGER_PORT:-9876}
TOKEN=${TRIGGER_TOKEN:-}
HOOK_PATH=${TRIGGER_PATH:-/hook}

if command -v python3 >/dev/null 2>&1 && [ -n "${ORDO_JOB_JSON:-}" ]; then
  eval "$(python3 - <<'PY'
import json, os, shlex
d = json.loads(os.environ.get("ORDO_JOB_JSON") or "{}")
for k, env in (("port", "PORT"), ("token", "TOKEN"), ("path", "HOOK_PATH")):
    if k in d and d[k] is not None:
        print(f"{env}={shlex.quote(str(d[k]))}")
PY
)"
fi

export PORT TOKEN HOOK_PATH
echo "webhook listening on 0.0.0.0:${PORT}${HOOK_PATH}"

exec python3 - <<'PY'
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(os.environ.get("PORT", "9876"))
Token = os.environ.get("TOKEN") or ""
path = os.environ.get("HOOK_PATH") or "/hook"

class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()

    def do_POST(self):
        if self.path.split("?", 1)[0] != path:
            self.send_response(404)
            self.end_headers()
            return
        got = self.headers.get("X-Ordo-Token", "")
        if Token and got != Token:
            self.send_response(401)
            self.end_headers()
            return
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        print("trigger webhook:", body[:500].decode("utf-8", "replace"))
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok\n")
        raise SystemExit(0)

    def do_GET(self):
        if self.path.split("?", 1)[0] == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
            return
        self.send_response(404)
        self.end_headers()

HTTPServer(("0.0.0.0", port), H).serve_forever()
PY
