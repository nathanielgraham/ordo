#!/bin/sh
# @id shell
# @label Shell Script
# @desc POSIX starter that prints Ordo env and shows an API call
# ==================== ORDO ENVIRONMENT VARIABLES ====================
# ORDO_JOB_ID, ORDO_CLUSTER_ID, ORDO_SERVER_ID, ORDO_EMAIL, ORDO_TEAM
# ORDO_TOKEN, ORDO_API, ORDO_JOB_JSON, ORDO_CLUSTER_JSON + handler vars

echo "Starting job $ORDO_JOB_ID in cluster $ORDO_CLUSTER_ID"

# Example API call (token in body):
# curl -s "$ORDO_API" \
#   -H "Content-Type: application/json" \
#   -d '{
#     "command": "read_cluster",
#     "id": "'"$ORDO_CLUSTER_ID"'",
#     "token": "'"$ORDO_TOKEN"'"
#   }'
