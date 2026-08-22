#!/bin/bash
set -euo pipefail
cd /opt/ordo
echo "cwd=$(pwd) user=$(id -un)"
git status --porcelain=v1
git pull --ff-only
echo "HEAD=$(git rev-parse --short HEAD) $(git log -1 --pretty=%s)"
