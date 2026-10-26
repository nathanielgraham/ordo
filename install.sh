#!/bin/bash
# Fresh self-hosted install. Run as your user, not with sudo.
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run ./install.sh with sudo. Run it as your user."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed. Install Docker and Docker Compose, then run ./install.sh again."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "This user cannot talk to Docker yet."
  sudo usermod -aG docker "$USER"
  echo "Added $USER to the docker group."
  echo "Log out, back in, and run ./install.sh again."
  exit 0
fi

mkdir -p config db data
docker compose up -d --build

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
pub=$(docker compose exec -T ordo cat /home/ordo/.ssh/id_ed25519.pub)
auth="$HOME/.ssh/authorized_keys"
touch "$auth"
chmod 600 "$auth"
if ! grep -qxF "$pub" "$auth"; then
  echo "$pub" >> "$auth"
  echo "Installed Ordo's public key in $auth"
else
  echo "Ordo's public key already in $auth"
fi

ip=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
echo "Add this machine as a server in Ordo:"
echo "  Host: ${ip:-<LAN address from hostname -I>}"
echo "  User: $USER"
echo "  Port: 22"
echo "  No password"
echo
echo "Admin token:"
docker compose logs ordo 2>/dev/null | grep bootstrap || true
echo
echo "Open http://localhost:3000/token-login and paste the token."
