#!/bin/sh
# @id wait-for-webhook
# @label Wait for Webhook
# @desc Listen for one HTTP POST, then exit 0
# Trigger: listen for one HTTP POST, then exit 0.
# json example: {"port":9876,"path":"/hook","token_file":"/etc/ordo/webhook.token"}
# Point Slack/GitHub/FTP-sidecar at http://<server>:9876/hook
# Header X-Ordo-Token must match token (optional if token empty).
# Token: TRIGGER_TOKEN or WEBHOOK_TOKEN env, then token_file, then json.token.
set -eu

PORT=${TRIGGER_PORT:-9876}
TOKEN=${TRIGGER_TOKEN:-${WEBHOOK_TOKEN:-}}
TOKEN_FILE=${TRIGGER_TOKEN_FILE:-}
HOOK_PATH=${TRIGGER_PATH:-/hook}

if command -v python3 >/dev/null 2>&1 && [ -n "${ORDO_JOB_JSON:-}${ORDO_CLUSTER_JSON:-}" ]; then
  eval "$(python3 - <<'PY'
import json, os, shlex
d = json.loads(os.environ.get("ORDO_JOB_JSON") or "{}")
c = json.loads(os.environ.get("ORDO_CLUSTER_JSON") or "{}")
p = {**c, **d}
for k, env in (("port", "PORT"), ("path", "HOOK_PATH"), ("token_file", "TOKEN_FILE")):
    if k in p and p[k] is not None:
        print(f"{env}={shlex.quote(str(p[k]))}")
json_token = p.get("token")
if json_token:
    print(f"JSON_TOKEN={shlex.quote(str(json_token))}")
PY
)"
fi

if [ -z "$TOKEN" ] && [ -n "$TOKEN_FILE" ] && [ -r "$TOKEN_FILE" ]; then
  TOKEN=$(tr -d '\n' < "$TOKEN_FILE")
fi
if [ -z "$TOKEN" ] && [ -n "${JSON_TOKEN:-}" ]; then
  TOKEN=$JSON_TOKEN
fi

export PORT TOKEN HOOK_PATH
echo "webhook listening on 0.0.0.0:${PORT}${HOOK_PATH}"

exec python3 - <<'PY'
import os, sys
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
