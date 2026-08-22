#!/bin/bash
set -euo pipefail
cd /opt/ordo/deploy/saas
LOG=/tmp/ordo-saas-deploy.log
echo "=== $LOG ==="
if [[ -f $LOG ]]; then
  cat "$LOG"
else
  echo "MISSING $LOG" >&2
  exit 1
fi
echo
echo "HEAD=$(git -C /opt/ordo rev-parse --short HEAD)"
echo
echo "=== docker compose ps ==="
docker compose ps
echo
running=$(docker compose ps --status running --format '{{.Name}}' | tr '\n' ' ')
echo "running=$running"
echo "$running" | grep -q 'saas-ordo-1' || { echo "ordo container not running" >&2; exit 1; }
echo "$running" | grep -q 'saas-minion-1' || { echo "minion container not running" >&2; exit 1; }
echo "verify ok"
