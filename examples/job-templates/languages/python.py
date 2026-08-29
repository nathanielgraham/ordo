#!/usr/bin/env python3
# @id python
# @label Python Script
# @desc Python starter that dumps ORDO_* env and calls the API
import os
import requests

# ==================== ORDO ENVIRONMENT VARIABLES ====================
print("=== ORDO Environment ===")
for key in sorted(k for k in os.environ if k.startswith("ORDO_")):
    print(f"{key}={os.environ[key]}")

api = os.getenv("ORDO_API")
token = os.getenv("ORDO_TOKEN")

# Example API call (token in body)
if api and token:
    payload = {
        "command": "read_cluster",
        "id": os.getenv("ORDO_CLUSTER_ID"),
        "token": token
    }
    resp = requests.post(api, json=payload)
    print("API Response:", resp.json())
