#!/bin/sh
# @id wait-for-slack
# @label Wait for Slack
# @desc Poll Slack until a message contains a needle
# Trigger: poll Slack conversations.history until a message contains NEEDLE.
# json example: {"channel":"C012345","needle":"deploy prod","interval_sec":15}
# Token: SLACK_BOT_TOKEN env, then token_file, then json.token (last resort).
# Needs conversations:history.
set -eu

CHANNEL=${TRIGGER_CHANNEL:-}
NEEDLE=${TRIGGER_NEEDLE:-}
INTERVAL=${TRIGGER_INTERVAL_SEC:-15}
TOKEN=${SLACK_BOT_TOKEN:-}
TOKEN_FILE=${SLACK_TOKEN_FILE:-${TRIGGER_TOKEN_FILE:-}}

if command -v python3 >/dev/null 2>&1 && [ -n "${ORDO_JOB_JSON:-}${ORDO_CLUSTER_JSON:-}" ]; then
  eval "$(python3 - <<'PY'
import json, os, shlex
d = json.loads(os.environ.get("ORDO_JOB_JSON") or "{}")
c = json.loads(os.environ.get("ORDO_CLUSTER_JSON") or "{}")
p = {**c, **d}
for k, env in (("channel", "CHANNEL"), ("needle", "NEEDLE"), ("interval_sec", "INTERVAL"), ("token_file", "TOKEN_FILE")):
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

if [ -z "$CHANNEL" ] || [ -z "$NEEDLE" ]; then
  echo "wait-for-slack: set json.channel and json.needle" >&2
  exit 2
fi
if [ -z "$TOKEN" ]; then
  echo "wait-for-slack: SLACK_BOT_TOKEN, token_file, or json.token required" >&2
  exit 2
fi

OLDEST=${TRIGGER_OLDEST:-$(date +%s)}
export NEEDLE

echo "watching Slack $CHANNEL for '$NEEDLE' after ts=$OLDEST"
while true; do
  hit=$(curl -fsS -H "Authorization: Bearer $TOKEN" \
    "https://slack.com/api/conversations.history?channel=$CHANNEL&oldest=$OLDEST&limit=20" \
    | python3 -c 'import json,os,sys
needle=os.environ["NEEDLE"].lower()
d=json.load(sys.stdin)
if not d.get("ok"):
    print("slack error:", d, file=sys.stderr)
    sys.exit(0)
for m in d.get("messages") or []:
    text=(m.get("text") or "").lower()
    if needle and needle in text:
        print(m.get("ts",""))
        break
')
  if [ -n "$hit" ]; then
    echo "trigger slack ts=$hit"
    exit 0
  fi
  sleep "$INTERVAL"
done
