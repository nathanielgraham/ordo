# Connecting to AI

Ordo supports **Model Context Protocol (MCP)** and a long-lived **WebSocket agent client**, so trusted models like **Grok** can explore, create, schedule, monitor, and debug jobs on your infrastructure using natural language.

## Two ways to connect

### 1. MCP (request/response) – simplest

1. Open **Settings** and copy your **API token**.
2. Tell the agent:

> Connect to Ordo at `https://ordoscheduler.com/mcp` with token `YOUR_TOKEN_HERE`

Good for browse / create / update / one-shot start.  
The agent will **not** see live job or cluster completion events.

### 2. WebSocket client (live stream) – preferred when you need completion events

Use this when the agent must start work and know when it finished.

Client: [ordo-wsagent](https://github.com/nathanielgraham/ordo-wsagent)

```bash
git clone https://github.com/nathanielgraham/ordo-wsagent.git
cd ordo-wsagent
pip install websocket-client   # or: python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt

export ORDO_TOKEN="YOUR_TOKEN_HERE"
./wsagent.py --timeout 300
```

Protocol:

- Send one JSON command per line on stdin  
  e.g. `{"command":"find_cluster","name":"/root/ops"}`
- Read NDJSON on stdout
- Only lines with `"type":"message"` contain server data (command replies **and** live broadcasts)
- After `login_user` success the client emits an `agent_bootstrap` info event with protocol, first steps, useful commands, and doc sections — enough for a fresh agent to start with no prior knowledge
- First useful call is usually `{"command":"get_documentation","section":"overview"}`
- Keep reading until you see the `command_reply` (and any `jobs_changed` / `clusters_changed` broadcasts) you care about
- When finished, **just exit** — the agent owns the connection lifetime; there is no special quit command required

If the agent has a shell tool it can run `wsagent.py` itself.  
If not, the user can start the client and paste or pipe the NDJSON stream into the conversation.

## What agents can do

- Browse servers, clusters, jobs, and calendars
- Create and update jobs and clusters (shell, Python, Perl, etc.)
- Create calendars and cron entries
- Start, hold, kill, complete, reset jobs and clusters
- Clone clusters (for overdue / catch-up workflows)
- Read logs and help debug failures
- Sync servers and reconcile process state
- Read org usage and limits
- Wire **On Fail**, **On Overdue**, and **Max Runtime** handlers

## Example prompts

### Hello World

> Look at my servers and clusters. If I don’t already have a cluster called demo, create one. On server `<SERVER>`, add a small Hello World job in whatever language you like, run it, and show me the log.

### Scheduled disk check

> I want a simple morning disk check on `<SERVER>`. Put a job in a monitoring cluster (create the cluster if needed) that runs `df -h`. Schedule it for 8:00 AM America/Chicago every day, attach that schedule to the cluster, and tell me the ids you created.

### Backup + max runtime

> On `<SERVER>`, set up a nightly backup workflow: a backups cluster with a daily-backup job, 3 retries, and a 2-hour max runtime. If it runs too long, I want a separate “Backup Watchdog” cluster that logs a warning. Schedule backups for 2:00 AM daily, and tell me how to test it without waiting until 2 AM.

### Overdue + clone

> Walk me through overdue-and-clone, then build a minimal version. When the scheduled start can’t run because the cluster is still busy or on hold, a handler should clone it and start the clone. Show me what you created.

## Tips for best results

- Tell the agent to call **`get_documentation`** at the beginning of a new session (section `overview` or `quickstart`).
- When creating jobs, be specific about:
  - Purpose of the job
  - Which server it should run on
  - Which cluster to place it in
  - When you want it to run
  - Dependencies (if any)
  - Special handlers (`on_fail`, `on_overdue`, `max_runtime`)

## Security

- Connecting an AI gives it real power over your infrastructure. Only connect trusted models.
- Use a **dedicated low-privilege account** on remote hosts; avoid root when possible.
- **Rotate** tokens regularly. Treat them like passwords and never post them in public channels.

## Available MCP tools (summary)

| Area     | Tools                                                                 |
|----------|-----------------------------------------------------------------------|
| Docs     | `get_documentation`                                                   |
| Browse   | `list_jobs`, `get_job_details`, `get_cluster_details`, `list_servers`, `list_calendars` |
| Create   | `create_job`, `create_cluster`, `create_calendar`, `add_cron`         |
| Update   | `update_job`, `update_cluster`                                        |
| Control  | `manage_job`, `manage_cluster`                                        |
| Clone    | `clone_cluster`                                                       |
| Logs     | `find_logs`, `read_log`                                               |
| Ops      | `sync`                                                                |
| Account  | `read_user`, `read_org`                                               |

## Agent behavior

### MCP path (request/response)

**Starting work is fire-and-forget by default.**

When an agent starts a cluster or job via MCP:

1. It receives a clear summary of what was started.
2. It should report that result to the user.
3. It should **stop** — do not automatically poll for completion.

Only check status or logs when the user explicitly asks  
(e.g. “did it finish?”, “show me the logs”, “what failed?”).

### WebSocket path (live stream)

When using `ordo-wsagent`:

1. After login, read the `agent_bootstrap` info event.
2. Call `get_documentation` if this is a new session.
3. Send commands; keep reading NDJSON for `command_reply` and broadcasts (`jobs_changed`, `clusters_changed`, …).
4. When the job or cluster reaches a terminal state, the agent is done — **just exit**.
5. The agent owns disconnect timing; `--timeout` is only a safety net.

### MCP request shape

Ordo speaks standard MCP over JSON-RPC. Preferred auth is a Bearer token:

```
curl -X POST https://ordoscheduler.com/mcp \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Core methods:

| Method        | Purpose                          |
|---------------|----------------------------------|
| `initialize`  | Handshake / capabilities         |
| `tools/list`  | Discover available tools         |
| `tools/call`  | Execute a tool                   |

Example tool call:

```
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "list_servers",
    "arguments": {}
  }
}
```

## Next

- [Quickstart](#docs/quickstart) - first server and workflow
- [Advanced Topics](#docs/advanced-topics) - handlers, cloning, environment variables
- [FAQ](#docs/faq) - SSH, limits, stuck jobs
- [ordo-wsagent](https://github.com/nathanielgraham/ordo-wsagent) - live WebSocket agent client
