#!/bin/sh
# Trigger: poll Slack conversations.history until a message contains NEEDLE.
# json example: {"channel":"C012345","needle":"deploy prod","interval_sec":15}
# Token: SLACK_BOT_TOKEN on the server (conversations:history).
set -eu

CHANNEL=${TRIGGER_CHANNEL:-}
NEEDLE=${TRIGGER_NEEDLE:-}
INTERVAL=${TRIGGER_INTERVAL_SEC:-15}
TOKEN=${SLACK_BOT_TOKEN:-}

if command -v python3 >/dev/null 2>&1 && [ -n "${ORDO_JOB_JSON:-}" ]; then
  eval "$(python3 - <<'PY'
import json, os, shlex
d = json.loads(os.environ.get("ORDO_JOB_JSON") or "{}")
for k, env in (("channel", "CHANNEL"), ("needle", "NEEDLE"), ("interval_sec", "INTERVAL")):
    if k in d and d[k] is not None:
        print(f"{env}={shlex.quote(str(d[k]))}")
PY
)"
fi

if [ -z "$CHANNEL" ] || [ -z "$NEEDLE" ]; then
  echo "wait-for-slack-poll: set json.channel and json.needle" >&2
  exit 2
fi
if [ -z "$TOKEN" ]; then
  echo "wait-for-slack-poll: SLACK_BOT_TOKEN is required on the server" >&2
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
