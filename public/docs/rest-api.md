# REST / HTTP API

The HTTP endpoint is the same JSON command protocol as WebSocket, posted to:

`https://ordoscheduler.com/api`

Full command tables, response shape, clear-semantics, and broadcasts: **[API Reference](#docs/api)** (`get_documentation` section `api`).

## Auth and curl

Every HTTP request includes your user token in the JSON body:

```bash
curl -X POST https://ordoscheduler.com/api \
  -H "Content-Type: application/json" \
  -d '{
    "command": "find_cluster",
    "name": "/root",
    "token": "your-user-token"
  }'
```

Always check `success` in the reply. Many commands accept either `id` or `name` (path).

For long-lived agents that wait on completion broadcasts, prefer [ordo-bot](https://github.com/nathanielgraham/ordo-bot) or WebSocket — see [Connecting to AI](#docs/connecting-to-ai) and [Agent protocol](#docs/agent-protocol).
