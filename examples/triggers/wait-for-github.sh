#!/bin/sh
# Trigger: poll GitHub until a new tag appears (or a workflow succeeds).
# json example:
#   {"repo":"owner/name","mode":"tag","since_tag":"v1.2.0","interval_sec":30}
#   {"repo":"owner/name","mode":"workflow","workflow":"ci.yml","branch":"main"}
# Token: GITHUB_TOKEN on the server (do not put it in json).
set -eu

REPO=${TRIGGER_REPO:-}
MODE=${TRIGGER_MODE:-tag}
SINCE=${TRIGGER_SINCE_TAG:-}
WORKFLOW=${TRIGGER_WORKFLOW:-}
BRANCH=${TRIGGER_BRANCH:-main}
INTERVAL=${TRIGGER_INTERVAL_SEC:-30}
TOKEN=${GITHUB_TOKEN:-}

if command -v python3 >/dev/null 2>&1 && [ -n "${ORDO_JOB_JSON:-}" ]; then
  eval "$(python3 - <<'PY'
import json, os, shlex
d = json.loads(os.environ.get("ORDO_JOB_JSON") or "{}")
for k, env in (
    ("repo", "REPO"),
    ("mode", "MODE"),
    ("since_tag", "SINCE"),
    ("workflow", "WORKFLOW"),
    ("branch", "BRANCH"),
    ("interval_sec", "INTERVAL"),
):
    if k in d and d[k] is not None:
        print(f"{env}={shlex.quote(str(d[k]))}")
PY
)"
fi

if [ -z "$REPO" ]; then
  echo "wait-for-github: set json.repo or TRIGGER_REPO" >&2
  exit 2
fi
if [ -z "$TOKEN" ]; then
  echo "wait-for-github: GITHUB_TOKEN is required on the server" >&2
  exit 2
fi

api() {
  curl -fsS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"
}

echo "watching GitHub $REPO mode=$MODE"
while true; do
  if [ "$MODE" = "tag" ]; then
    latest=$(api "https://api.github.com/repos/$REPO/tags?per_page=1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['name'] if d else '')")
    if [ -n "$latest" ] && [ "$latest" != "$SINCE" ]; then
      echo "trigger tag: $latest"
      exit 0
    fi
  else
    # latest successful workflow run on branch
    q="https://api.github.com/repos/$REPO/actions/runs?per_page=5&status=success&branch=$BRANCH"
    if [ -n "$WORKFLOW" ]; then
      q="$q&name=$WORKFLOW"
    fi
    id=$(api "$q" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('workflow_runs') or []; print(r[0]['id'] if r else '')")
    if [ -n "$id" ]; then
      marker="/tmp/ordo-gh-run-$ORDO_JOB_ID"
      prev=$(cat "$marker" 2>/dev/null || true)
      if [ -n "$prev" ] && [ "$id" != "$prev" ]; then
        echo "trigger workflow run: $id"
        echo "$id" > "$marker"
        exit 0
      fi
      echo "$id" > "$marker"
    fi
  fi
  sleep "$INTERVAL"
done
