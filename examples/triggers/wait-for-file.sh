#!/bin/sh
# Trigger: complete when a local file matching PATH/GLOB exists.
# json example: {"path":"/incoming/invoices/*.csv","interval_sec":5,"remove":0}
set -eu

PATH_GLOB=${TRIGGER_PATH:-}
INTERVAL=${TRIGGER_INTERVAL_SEC:-5}
REMOVE=${TRIGGER_REMOVE:-0}

if [ -n "${ORDO_JOB_JSON:-}" ]; then
  # Tiny parse without requiring jq: only used if env not already set.
  :
fi

if command -v python3 >/dev/null 2>&1 && [ -n "${ORDO_JOB_JSON:-}" ]; then
  eval "$(python3 - <<'PY'
import json, os, shlex
d = json.loads(os.environ.get("ORDO_JOB_JSON") or "{}")
for k, env in (("path", "PATH_GLOB"), ("interval_sec", "INTERVAL"), ("remove", "REMOVE")):
    if k in d and d[k] is not None:
        print(f"{env}={shlex.quote(str(d[k]))}")
PY
)"
fi

if [ -z "$PATH_GLOB" ]; then
  echo "wait-for-file: set TRIGGER_PATH or json.path" >&2
  exit 2
fi

echo "watching $PATH_GLOB every ${INTERVAL}s"
while true; do
  # shellcheck disable=SC2086
  found=$(ls -1 $PATH_GLOB 2>/dev/null | head -n 1 || true)
  if [ -n "$found" ]; then
    echo "trigger: $found"
    if [ "$REMOVE" = "1" ] || [ "$REMOVE" = "true" ]; then
      rm -f "$found"
    fi
    exit 0
  fi
  sleep "$INTERVAL"
done
