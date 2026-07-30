#!/bin/bash
set -euo pipefail

DB="/app/db/ordo.db"
SSH_DIR="${HOME}/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
if [ ! -f "$SSH_DIR/id_ed25519" ]; then
  ssh-keygen -t ed25519 -N "" -f "$SSH_DIR/id_ed25519" -C "ordo@container"
  chmod 600 "$SSH_DIR/id_ed25519"
  chmod 644 "$SSH_DIR/id_ed25519.pub"
  echo "[entrypoint] Generated SSH keypair"
fi

# Always ensure config exists (volume may be empty)
if [ ! -f /app/config/ordo.json ]; then
  mkdir -p /app/config
  cp /app/config.default/ordo.json /app/config/ordo.json
  echo "Seeded /app/config/ordo.json from default"
fi

if [ ! -f "$DB" ]; then
  echo "Cleaning up any leftover SQLite files..."
  rm -f /app/db/*.db /app/db/*.db-wal /app/db/*.db-shm

  echo "Initializing Ordo database..."
  shopt -s nullglob
  schemas=(/app/schemas/*.schema)
  if [ ${#schemas[@]} -eq 0 ]; then
    echo "ERROR: No schema files found in /app/schemas/"
    exit 1
  fi

  for schema in "${schemas[@]}"; do
    echo "  Applying $(basename "$schema")"
    sqlite3 "$DB" < "$schema"
  done

  if [ ! -f /app/config/ordo.json ]; then
    mkdir -p /app/config
    cp /app/config.default/ordo.json /app/config/ordo.json
  fi

  if [ ! -f "$DB" ]; then
    echo "ERROR: Database was not created"
    exit 1
  fi

  echo "Database initialized successfully."
else
  echo "Database already exists — skipping schema init."
fi

exec "$@"
