#!/bin/bash
set -euo pipefail

DB="/app/db/ordo.db"
SSH_DIR="${HOME}/.ssh"

# Fail fast if /app/db isn't writable (avoids cryptic SQLite/Minion "readonly database" errors)
if [ ! -d /app/db ]; then
  echo "ERROR: /app/db does not exist or is not a directory."
  echo "Bind-mount ./db and chown it to uid/gid 1000 (container user ordo)."
  exit 1
fi
if ! touch /app/db/.ordo_write_test 2>/dev/null; then
  echo "ERROR: /app/db is not writable by uid $(id -u) ($(id -un 2>/dev/null || echo ordo))."
  echo "Host bind mounts must be owned by uid/gid 1000 (image user ordo), e.g.:"
  echo "  chown -R 1000:1000 ./db ./config ./data ./ssh"
  exit 1
fi
rm -f /app/db/.ordo_write_test

# SSH dir: bind mounts may not be owned by us — don't crash the stack
if mkdir -p "$SSH_DIR" 2>/dev/null; then
  if ! chmod 700 "$SSH_DIR" 2>/dev/null; then
    echo "[entrypoint] WARN: cannot chmod $SSH_DIR (bind mount not owned by uid $(id -u)); continuing"
  fi
else
  echo "[entrypoint] WARN: cannot create $SSH_DIR (parent not writable or mount mismatch); continuing"
fi

if [ -f "$SSH_DIR/id_ed25519" ]; then
  echo "[entrypoint] Using existing SSH key at $SSH_DIR/id_ed25519"
elif [ -d "$SSH_DIR" ] && [ -w "$SSH_DIR" ]; then
  ssh-keygen -t ed25519 -N "" -f "$SSH_DIR/id_ed25519" -C "ordo@container"
  chmod 600 "$SSH_DIR/id_ed25519" 2>/dev/null || true
  chmod 644 "$SSH_DIR/id_ed25519.pub" 2>/dev/null || true
  echo "[entrypoint] Generated SSH keypair"
else
  echo "[entrypoint] WARN: no SSH key and $SSH_DIR is not writable; server SSH features may fail until the mount is owned by uid 1000"
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
