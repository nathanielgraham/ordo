#!/bin/bash
set -euo pipefail
cd /opt/ordo/deploy/saas
LOG=/tmp/ordo-saas-deploy.log
: > "$LOG"
echo "scheduling recreate of ordo+minion; log=$LOG"
nohup bash -c 'sleep 8; cd /opt/ordo/deploy/saas && docker compose up -d --no-deps --force-recreate ordo minion' >>"$LOG" 2>&1 &
echo "recreate scheduled pid=$!"
