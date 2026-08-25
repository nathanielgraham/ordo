# Agent Protocol

This section is written for AI agents (and for humans who paste it into an agent chat).

Read this once at the start of a session, then operate.

## Goal

Control Ordo jobs and clusters safely:

- Browse structure
- Create / update jobs and clusters
- Start work and know when it finished
- Recover after a connection drop

## Two transports

| Transport | When to use | Completion events |
|-----------|-------------|-------------------|
| **MCP** `https://ordoscheduler.com/mcp` | Browse, create, one-shot start | No — fire-and-forget |
| **WebSocket** `wss://ordoscheduler.com/websocket` via [ordo-wsagent](https://github.com/nathanielgraham/ordo-wsagent) | Start and wait for completion | Yes — `jobs_changed` / `clusters_changed` |

Prefer WebSocket when the user asks you to run something and report when it finishes.

## Human → agent starter prompt

A human can paste something like:

> Read Ordo agent protocol (`get_documentation` section `agent-protocol`), then connect with token `YOUR_TOKEN` using the WebSocket client.

Or, if they already started `wsagent.py` for you:

> Token is already in the client. Follow agent-protocol. Show the job tree, then …

## WebSocket client bootstrap

```bash
git clone https://github.com/nathanielgraham/ordo-wsagent.git
cd ordo-wsagent
pip install websocket-client
export ORDO_TOKEN="YOUR_TOKEN_HERE"
python3 wsagent.py --timeout 300
```

Protocol:

1. Client connects and sends `login_user` with the token.
2. On success it emits an `agent_bootstrap` info event (protocol, examples, notes).
3. You send **one JSON object per line** on stdin.
4. You read **NDJSON** on stdout. Only lines with `"type":"message"` are server data (command replies **and** live broadcasts).
5. When finished, send `quit` (bare word or `{"command":"quit"}`), close stdin, or kill the process.

## First commands

```json
{"command":"get_documentation","section":"agent-protocol","format":"markdown"}
{"command":"find_cluster","name":"/root"}
{"command":"find_monitor"}
```

## Create (minimal, paste-ready)

Prefer plain `script` (JSON-safe). `script_b64` is also accepted.

```json
{"command":"create_cluster","name":"demo","parent_id":1}
```

```json
{"command":"create_job","name":"hello","parent_id":CLUSTER_ID,"server_id":SERVER_ID,"script":"#!/bin/sh\necho hello\nsleep 2\necho done\n"}
```

Replace `CLUSTER_ID` and `SERVER_ID` with real ids from `find_cluster` / `find_monitor` (or `list_servers` on MCP).

## Start-and-wait pattern (WebSocket)

1. Send `{"command":"start_cluster","id":CLUSTER_ID}` (or `"name":"path/to/cluster"`).
2. Keep stdin open. Do **not** quit yet.
3. Watch message payloads for:
   - `command_reply":"start_cluster"` with `success`
   - `broadcast":"jobs_changed"` and `broadcast":"clusters_changed"`
4. Treat the run as done when the **target cluster** reaches a terminal `jobstate`:
   - `complete` — success
   - `failed` / `killed` / `zombie` — failure
5. Then send `quit`.

Filter broadcasts by `id` (cluster id or job id). Ignore other clusters’ updates.

Example terminal check on a `clusters_changed` update:

- `updates[].id == TARGET_ID` and `updates[].jobstate` in `{complete, failed, killed, zombie}`

## Disconnect recovery

Connection lost ≠ job failed.

After a self-deploy, network blip, or 502:

1. Start a **new** client and re-login.
2. `read_cluster` / `find_cluster` for the ids you care about.
3. Decide next action from the **real** state — do not assume the previous run failed.

Do not auto-reconnect inside the transport client; keep transport honest and recover in the agent loop.

## MCP behavior

Starting a cluster via MCP is **fire-and-forget**:

1. Call the tool.
2. Report what started.
3. Stop. Do not poll unless the user asks for status or logs.

For completion events, switch to WebSocket.

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
- `connecting-to-ai` — MCP + WS overview for humans
- `api` — full command reference
