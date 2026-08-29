# Agent Protocol

This section is written for AI agents (and for humans who paste it into an agent chat).

Read this once at the start of a session, then operate.

## Goal

Control Ordo jobs and clusters safely:

- Browse structure
- Create / update jobs and clusters
- Start work and know when it finished
- Recover after a connection drop

## Transports

| Transport | When to use | Completion events |
|-----------|-------------|-------------------|
| **MCP** `https://ordoscheduler.com/mcp` | Browse, create, one-shot start | No — fire-and-forget |
| **ordo-bot** ([github.com/nathanielgraham/ordo-bot](https://github.com/nathanielgraham/ordo-bot)) | Full agent: your LLM, tools, CLI/frontend WS | Yes — broadcast **watches** |
| **WebSocket pipe** via [ordo-wsagent](https://github.com/nathanielgraham/ordo-wsagent) | Custom agent loop or scripting | Yes — you filter `jobs_changed` / `clusters_changed` yourself |

Prefer **ordo-bot** when the user wants a ready-made agent that can run work and report completion. Prefer **MCP** for simple tool calls without a long-lived process. Use **ordo-wsagent** only as a thin transport.

## Human → agent starter prompt

> Read Ordo agent protocol (`get_documentation` section `agent-protocol`), then use ordo-bot (or MCP) with my token. Show the job tree, then …

If they already run ordo-bot:

> ordo-bot is running. Follow agent-protocol. Start concurrent-b and tell me when sleep-b completes.

## ordo-bot pattern (recommended)

1. User runs `ordo-bot` with `ordo_token` + LLM config; talks via `clients/cli.py` or another frontend client.
2. You call tools with the same names as the API (`find_cluster`, `start_cluster`, …).
3. **Start-and-notify:** after `start_cluster` / `start_job`, call `watch_job` or `watch_cluster` (or `watch_event`) with an explicit filter. If the user asked for completion, pass **`jobstate=complete`**. Watches listen to Ordo broadcasts only — do not poll.
4. The user receives a notification message when a matching broadcast arrives.

Example tool intent:

```text
start_cluster(id=20)
watch_job(id=13, jobstate="complete", label="sleep-b")
```

## Thin WebSocket client (ordo-wsagent)

```bash
git clone https://github.com/nathanielgraham/ordo-wsagent.git
cd ordo-wsagent
pip install websocket-client
export ORDO_TOKEN="YOUR_TOKEN_HERE"
python3 wsagent.py --timeout 300
```

1. Client connects and sends `login_user`.
2. On success it may emit an `agent_bootstrap` info event.
3. You send **one JSON object per line** on stdin.
4. You read **NDJSON** on stdout (`"type":"message"` = server data including broadcasts).
5. Filter broadcasts by `id` and `jobstate` yourself; then `quit`.

## Optional request_id

The client may generate an optional `request_id` on each command JSON (a short string you choose). The server copies that same value onto the **command_reply** only (HTTP, WebSocket, wsagent, ordo-bot). Broadcasts (`jobs_changed`, `clusters_changed`, …) never include `request_id`. Omit the field and the reply is unchanged — today’s protocol.

```json
{"command":"find_cluster","name":"/root","request_id":"loop-1"}
```

## First commands

```json
{"command":"get_documentation","section":"agent-protocol","format":"markdown"}
{"command":"find_cluster","name":"/root"}
{"command":"find_monitor"}
```

## Create (minimal)

```json
{"command":"create_cluster","name":"demo","parent_id":1}
```

```json
{"command":"create_job","name":"hello","parent_id":CLUSTER_ID,"server_id":SERVER_ID,"script":"#!/bin/sh\necho hello\nsleep 2\necho done\n"}
```

## Start-and-wait (raw WebSocket)

1. Send `{"command":"start_cluster","id":CLUSTER_ID}`.
2. Keep the connection open.
3. Watch `jobs_changed` / `clusters_changed` for `updates[].id` and `jobstate`.
4. Terminal examples: `complete` (success), `failed` / `killed` / `zombie` (failure).
5. Then disconnect.

## Hold / release notes

- You **can** hold completed (and most non-running) clusters and jobs.
- You **cannot** hold while a job/cluster is **running**.
- After release, state is typically `ready`, not the previous terminal state.

## Disconnect recovery

Connection lost ≠ job failed.

1. Reconnect / restart the client and re-login.
2. `read_cluster` / `find_cluster` for the ids you care about.
3. Decide from **real** state — do not assume the previous run failed.

## MCP behavior

Starting via MCP is **fire-and-forget**: report what started, then stop unless the user asks for status or logs. For completion events, use ordo-bot or a WebSocket client.

## Clear semantics

- **Omit** a field → leave unchanged.
- Send `null` / `""` / `[]` → clear that field.

## Security

- Only connect trusted models.
- Prefer low-privilege SSH accounts on remote hosts.
- Treat API tokens like passwords; rotate if exposed.

## Related docs

- `overview` / `quickstart` — product intro
- `jobs-and-clusters` — hierarchy and dependencies
- `connecting-to-ai` — MCP + ordo-bot + optional wsagent
- `api` — full command reference
