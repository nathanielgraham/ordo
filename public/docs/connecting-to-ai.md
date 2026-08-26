# Connecting to AI

Ordo supports **Model Context Protocol (MCP)** and long-lived **WebSocket** access so trusted models can explore, create, schedule, monitor, and debug jobs on your infrastructure using natural language.

**One command vocabulary:** MCP tool names match the native WebSocket/HTTP `command` names (e.g. `find_cluster`, `create_cron`, `start_cluster`). See [API Reference](#docs/api).

## Three ways to connect

### 1. MCP (request/response) – simplest

1. Open **Settings** and copy your **API token**.
2. Point an MCP-capable client at Ordo:

> Connect to Ordo at `https://ordoscheduler.com/mcp` with token `YOUR_TOKEN_HERE`

Good for browse / create / update / one-shot start.  
The agent will **not** see live job or cluster completion events (starts are fire-and-forget).

### 2. ordo-bot (recommended for a full agent + completion)

[ordo-bot](https://github.com/nathanielgraham/ordo-bot) is a downloadable agent that:

- Connects to Ordo over WebSocket with **your** token
- Uses **your** LLM (Groq, Ollama, OpenRouter, xAI, … — you pay for tokens)
- Exposes a small frontend WebSocket API (CLI included)
- Registers **broadcast watches** so it can notify you when a job or cluster reaches a state you care about (e.g. `complete`) without polling

```bash
git clone https://github.com/nathanielgraham/ordo-bot.git
cd ordo-bot
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
cp config.example.toml config.toml
# set ordo_token + llm_* in config.toml
ordo-bot --config config.toml
# other terminal:
python clients/cli.py
```

Architecture and client protocol: see the [ordo-bot README](https://github.com/nathanielgraham/ordo-bot) and `docs/ARCHITECTURE.md` / `docs/PROTOCOL.md` in that repo.

Prefer **ordo-bot** when you want a ready-made agent with tools, history, and completion notifications.

### 3. Thin WebSocket pipe (optional) – ordo-wsagent

[ordo-wsagent](https://github.com/nathanielgraham/ordo-wsagent) (`wsagent.py`) is a **minimal NDJSON stdin/stdout client** with **no LLM**. Use it if you already have an agent loop and only need a transport, or for scripting/debugging raw commands.

```bash
git clone https://github.com/nathanielgraham/ordo-wsagent.git
cd ordo-wsagent
pip install websocket-client
export ORDO_TOKEN="YOUR_TOKEN_HERE"
./wsagent.py --timeout 300
```

Protocol:

- One JSON command per line on stdin (e.g. `{"command":"find_cluster","name":"/root"}`)
- NDJSON on stdout; lines with `"type":"message"` carry server data (replies **and** broadcasts)
- After login, an `agent_bootstrap` info event summarizes first steps
- Keep reading until you see the `command_reply` and any `jobs_changed` / `clusters_changed` you care about

For most “connect my model to Ordo” setups, **use ordo-bot instead**.

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

### Start and notify on completion (ordo-bot)

> Start the concurrent-b cluster and let me know when job sleep-b completes.

(The agent should start the cluster and register a watch with `jobstate=complete` on the live broadcast stream.)

### Backup + max runtime

> On `<SERVER>`, set up a nightly backup workflow: a backups cluster with a daily-backup job, 3 retries, and a 2-hour max runtime. If it runs too long, I want a separate “Backup Watchdog” cluster that logs a warning. Schedule backups for 2:00 AM daily, and tell me how to test it without waiting until 2 AM.

## Tips for best results

- Tell the agent to call **`get_documentation`** at the beginning of a new session (section `overview`, `api`, or `agent-protocol`).
- When creating jobs, be specific about purpose, server, cluster, schedule, dependencies, and handlers.
- For completion, prefer **ordo-bot watches** (or a custom WebSocket client that filters broadcasts). MCP cannot push completion events.

## Security

- Connecting an AI gives it real power over your infrastructure. Only connect trusted models.
- Use a **dedicated low-privilege account** on remote hosts; avoid root when possible.
- **Rotate** tokens regularly. Treat them like passwords and never post them in public channels.

## Available MCP tools (summary)

Tool names match the native API `command` field.

| Area | Tools |
|------|-------|
| Docs | `get_documentation` |
| Browse | `find_cluster`, `read_job`, `read_cluster`, `find_monitor`, `find_cal` |
| Create | `create_job`, `create_cluster`, `create_cal`, `create_cron` |
| Update | `update_job_config`, `update_cluster` |
| Lifecycle | `start_job`, `start_cluster`, `kill_*`, `hold_*`, `release_*`, `ice_*`, `melt_*`, `complete_*`, `delete_*`, `reset_cluster` |
| Clone | `clone_cluster` |
| Logs | `find_log`, `read_log` |
| Ops | `sync` |
| Account | `read_user`, `read_org` |

## Agent behavior

### MCP path (request/response)

**Starting work is fire-and-forget by default.**

1. Agent receives a summary of what was started.
2. It should report that to the user.
3. It should **stop** — do not automatically poll for completion.

Only check status or logs when the user explicitly asks.

### ordo-bot / WebSocket path (live stream)

1. Connect and authenticate (ordo-bot does this with your config token).
2. Call `get_documentation` if this is a new session.
3. Run tools / commands as needed.
4. For “tell me when it finishes,” register a **watch** filtered by id and `jobstate` (e.g. `complete`) so a later broadcast notifies the user — do not busy-poll.
5. Hold is allowed on completed (and most non-running) jobs/clusters; not while **running**.

### MCP request shape

```bash
curl -X POST https://ordoscheduler.com/mcp \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

| Method | Purpose |
|--------|--------|
| `initialize` | Handshake / capabilities |
| `tools/list` | Discover tools |
| `tools/call` | Execute a tool |

## Next

- [Quickstart](#docs/quickstart) — first server and workflow
- [Agent protocol](#docs/agent-protocol) — guidance aimed at agents
- [API Reference](#docs/api) — full command reference
- [Advanced Topics](#docs/advanced-topics) — handlers, cloning, environment variables
- [FAQ](#docs/faq) — SSH, limits, stuck jobs
- [ordo-bot](https://github.com/nathanielgraham/ordo-bot) — recommended full agent
- [ordo-wsagent](https://github.com/nathanielgraham/ordo-wsagent) — optional thin pipe
