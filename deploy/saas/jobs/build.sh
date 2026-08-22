#!/bin/bash
set -euo pipefail
cd /opt/ordo/deploy/saas
echo "building ordo:1.0.0 from $(git -C /opt/ordo rev-parse --short HEAD)"
docker compose build
docker image inspect ordo:1.0.0 --format 'image={{.Id}} created={{.Created}}'
