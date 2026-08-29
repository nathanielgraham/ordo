#!/usr/bin/env python3
# @id python
# @label Python Script
# @desc Python starter that dumps ORDO_* env and calls the API (stdlib only)
import json
import os
import urllib.request

# ==================== ORDO ENVIRONMENT VARIABLES ====================
print("=== ORDO Environment ===")
for key in sorted(k for k in os.environ if k.startswith("ORDO_")):
    print(f"{key}={os.environ[key]}")

api = os.getenv("ORDO_API")
token = os.getenv("ORDO_TOKEN")

# Example API call (token in body). urllib is stdlib — no requests.
if api and token:
    payload = json.dumps(
        {
            "command": "read_cluster",
            "id": os.getenv("ORDO_CLUSTER_ID"),
            "token": token,
        }
    ).encode()
    req = urllib.request.Request(
        api, data=payload, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        print("API Response:", resp.read().decode())
