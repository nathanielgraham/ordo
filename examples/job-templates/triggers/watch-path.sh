#!/bin/sh
# @id watch-path
# @label Watch Path
# @desc Complete when a path/glob appears or its mtime changes
# Trigger: watch a file, directory, or glob on the job's server.
# json example:
#   {"path":"/incoming/invoices/*.csv","mode":"appear","interval_sec":5}
#   {"path":"/var/data/feed.xml","mode":"change","interval_sec":10}
# mode=appear (default): exit 0 when any match exists
# mode=change: snapshot mtimes, exit 0 when any match is new or newer
set -eu

PATH_GLOB=${TRIGGER_PATH:-}
MODE=${TRIGGER_MODE:-appear}
INTERVAL=${TRIGGER_INTERVAL_SEC:-5}

if command -v python3 >/dev/null 2>&1 && [ -n "${ORDO_JOB_JSON:-}" ]; then
  eval "$(python3 - <<'PY'
import json, os, shlex
d = json.loads(os.environ.get("ORDO_JOB_JSON") or "{}")
c = json.loads(os.environ.get("ORDO_CLUSTER_JSON") or "{}")
p = {**c, **d}
for k, env in (("path", "PATH_GLOB"), ("mode", "MODE"), ("interval_sec", "INTERVAL")):
    if k in p and p[k] is not None:
        print(f"{env}={shlex.quote(str(p[k]))}")
PY
)"
fi

if [ -z "$PATH_GLOB" ]; then
  echo "watch-path: set TRIGGER_PATH or json.path" >&2
  exit 2
fi

snapshot() {
  # path<TAB>mtime (or empty)
  # shellcheck disable=SC2086
  ls -1 $PATH_GLOB 2>/dev/null | while IFS= read -r f; do
    [ -e "$f" ] || continue
    mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    printf '%s\t%s\n' "$f" "$mt"
  done
}

echo "watching $PATH_GLOB mode=$MODE every ${INTERVAL}s"
BASE=$(snapshot || true)

while true; do
  NOW=$(snapshot || true)
  if [ "$MODE" = "change" ]; then
    if [ "$NOW" != "$BASE" ] && [ -n "$NOW" ]; then
      echo "trigger change:"
      echo "$NOW"
      exit 0
    fi
  else
    if [ -n "$NOW" ]; then
      echo "trigger appear:"
      echo "$NOW"
      exit 0
    fi
  fi
  sleep "$INTERVAL"
done
