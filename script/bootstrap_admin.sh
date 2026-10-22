#!/bin/bash
# Create a level>0 admin if none exists. Prints the API token to stdout.
set -euo pipefail
DB="${1:-/app/db/ordo.db}"

count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM user WHERE level > 0;")
if [ "$count" != "0" ]; then
  exit 0
fi

email="${ORDO_ADMIN_EMAIL:-admin@localhost}"
token="${ORDO_ADMIN_TOKEN:-$(openssl rand -hex 20)}"
exec_token=$(openssl rand -hex 20)
now=$(date +%s)

sqlite3 "$DB" <<SQL
BEGIN;
INSERT INTO org DEFAULT VALUES;
INSERT INTO cluster (org_id, name, state_id)
  SELECT last_insert_rowid(), 'root', id FROM job_states WHERE state = 'immutable';
UPDATE org SET root_cluster_id = (SELECT id FROM cluster WHERE name = 'root' ORDER BY id DESC LIMIT 1)
  WHERE id = (SELECT MAX(id) FROM org);
INSERT INTO user (org_id, base_cluster_id, level, token, execution_token, email, name, creation_time)
  SELECT o.id, o.root_cluster_id, 1, '$token', '$exec_token', '$email', 'admin', $now
  FROM org o ORDER BY o.id DESC LIMIT 1;
COMMIT;
SQL

echo "[bootstrap] Created admin $email"
echo "[bootstrap] API token: $token"
echo "[bootstrap] Paste this token at /token-login"
