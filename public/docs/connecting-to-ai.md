# Connecting to AI

Ordo supports **Model Context Protocol (MCP)** and long-lived **WebSocket** access so trusted models can explore, create, schedule, monitor, and debug jobs on your infrastructure using natural language.

## Two ways to connect

### 1. MCP (request/response) – simplest

1. Open **Settings** and copy your **API token**.
2. Point an MCP-capable client at Ordo:

> Connect to Ordo at `https://ordoscheduler.com/mcp` with token `YOUR_TOKEN_HERE`

### 2. ordo-bot (recommended for a full agent + completion)

[ordo-bot](https://github.com/nathanielgraham/ordo-bot) is a downloadable agent that:

- Connects to Ordo over WebSocket with your token
- Uses **your** LLM (Groq, Ollama, OpenRouter, xAI, ... - you pay for tokens)
- Exposes a small frontend WebSocket API (CLI included)
- Registers **broadcast watches** so it can notify you when a job or cluster reaches a **terminal** state (`complete`, `failed`, `killed`, `zombie`) without polling

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

Prefer **ordo-bot** when you want a ready-made agent with tools, history, and notifications.

## What agents can do

- Browse servers, clusters, jobs, and calendars
- Create and update jobs and clusters (shell, Python, Perl, etc.)
- Create calendars and cron entries
- Start, hold, kill, complete, reset jobs and clusters
- Clone clusters (for overdue / catch-up workflows)
- Read logs and help debug failures
- Sync servers and reconcile process state
- Read org usage and limits
- Wire `On Fail`, `On Overdue`, and `Max Runtime` handlers

## Example prompts

### Hello World

> Look at my servers and clusters. If I don’t already have a cluster called demo, create one. On server `panthero`, add a small Hello World job in whatever language you like, run it, and show me the log.

### Scheduled disk check

> I want a simple morning disk check on server `liono`. Put a job in a monitoring cluster (create the cluster if needed) that runs `df -h`. Schedule it for 8:00 AM America/Chicago every day, attach that schedule to the cluster, and tell me the ids you created.

### Start and notify on completion (ordo-bot)

> Start the `deploy-saas` cluster and let me know when it finishes.

(The agent should start the cluster and register a watch that fires on **any terminal** broadcast — `complete` / `failed` / `killed` / `zombie` — unless you asked for success-only.)

### Backup + max runtime

> On `tigra`, set up a nightly backup workflow: a backups cluster with a daily-backup job, 3 retries, and a 2-hour max runtime. If it runs too long, I want a separate “Backup Watchdog” cluster that logs a warning. Schedule backups for 2:00 AM daily, and tell me how to test it without waiting until 2 AM.

## Tips for best results

- Tell the agent to call **`get_documentation`** at the beginning of a new session (section `overview`, `api`, or `agent-protocol`).
- When creating jobs, be specific about purpose, server, cluster, schedule, dependencies, and handlers.
- Optional `request_id` on a command is echoed on that command’s reply only (never on broadcasts). Omit it to keep today’s reply shape.
- Completion lives on `jobs_changed` / `clusters_changed`, not on the start `command_reply`.

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

Server add/update/delete on the **WebSocket / HTTP API** (and ordo-bot) use `create_monitor`, `update_monitor`, `delete_monitor` — there is no `create_server`. MCP currently exposes `find_monitor` for browsing; use the API or ordo-bot for lifecycle. See `api` / `agent-protocol` docs.

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
4. For “tell me when it finishes,” register a **watch** on the live broadcast stream. Default filter is **any terminal state**. Pass `jobstate=complete` only when the user asked for success. Do not busy-poll. Do not treat the start reply as finished.

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
