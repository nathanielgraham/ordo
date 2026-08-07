# Connecting to AI

Ordo supports **Model Context Protocol (MCP)**, so trusted models like **Grok** can explore, create, schedule, monitor, and debug jobs on your infrastructure using natural language.

## Quick start

1. Open **Settings** and copy your **API token**.
2. In chat, tell Grok:

> Connect to Ordo at `https://ordoscheduler.com/mcp` with token `YOUR_TOKEN_HERE`

Grok can reuse that connection for the rest of the conversation.

### Request shape

Every call is a JSON `POST` to `/mcp`:

```
{
  "token": "YOUR_TOKEN_HERE",
  "name": "read_org",
  "params": {}
}
```

## What Grok can do

- Browse servers, clusters, jobs, and calendars
- Create and update jobs and clusters (shell, Python, Perl, etc.)
- Create calendars and cron entries; attach a calendar by setting cal_id on a cluster
- Start, hold, kill, complete, reset jobs and clusters
- Clone clusters (for overdue / catch-up workflows)
- Read logs and help debug failures
- Sync servers and reconcile process state
- Read org usage and limits
- wire **On Fail**, **On Overdue**, and **Max Runtime** handlers.

## Example prompts

Replace `<SERVER>` with a name from your **Servers** tab, or ask Grok to list servers first.

### Hello World
> Look at my servers and clusters. If I don’t already have a cluster called demo, create one. On server `<SERVER>`, add a small Hello World job in whatever language you like, run it, and show me the log.

### Scheduled disk check
> I want a simple morning disk check on `<SERVER>`. Put a job in a monitoring cluster (create the cluster if needed) that runs `df -h`. Schedule it for 8:00 AM America/Chicago every day, attach that schedule to the cluster, and tell me the ids you created.

### Backup + max runtime
> On `<SERVER>`, set up a nightly backup workflow: a backups cluster with a daily-backup job (placeholder script is fine), 3 retries, and a 2-hour max runtime. If it runs too long, I want a separate “Backup Watchdog” cluster that only logs a warning — keep auto-start off on the watchdog and point max runtime at it. Schedule backups for 2:00 AM daily, and tell me how to test it without waiting until 2 AM.

### Overdue + clone
> Walk me through overdue-and-clone, then build a minimal version. When the scheduled start can’t run because the cluster is still busy or on hold, a handler should clone it and start the clone. Handler cluster should have auto-start off, use `ORDO_OVERDUE_CLUSTER_ID`, fire only once per overdue stretch, and not clone forever. Show me what you created.

## Tips

- Specify the purpose, server, parent cluster, schedule (cron + timezone), handlers if needed.
- Ask for the **script text** before `create_job`.
- New session: call **`get_documentation`** first.
- Calendars: `create_calendar` → `add_cron` → `update_cluster` with `cal_id`.
- Handler clusters: **auto_start off**.

SSH: [FAQ](#docs/faq). Handlers / `ORDO_*`: [Advanced Topics](#docs/advanced-topics).

## Security

- Connect **only trusted** models (Grok is the recommended integration).  
- Use a **dedicated low-privilege SSH user** on remote hosts; avoid root when possible.  
- **Rotate** tokens from Settings; never commit tokens or post them in public channels.  
- MCP has real power over your org’s jobs and servers — treat the token like a password.  
- Job workers receive runtime environment for API calls; don’t log secrets in scripts.

## Available tools (summary)

| Area | Tools |
|------|--------|
| Docs | `get_documentation` |
| Browse | `list_jobs`, `get_job_details`, `get_cluster_details`, `list_servers`, `list_calendars` |
| Create | `create_job`, `create_cluster`, `create_calendar`, `add_cron` |
| Update | `update_job`, `update_cluster` |
| Control | `manage_job`, `manage_cluster` |
| Clone | `clone_cluster` |
| Logs | `find_logs`, `read_log` |
| Ops | `sync` |
| Account | `read_user`, `read_org` |

Full parameter schemas: `POST /mcp` with **only** your token (no `name`), or ask Grok to list tools.

## Quick test

```
curl -X POST https://ordoscheduler.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_TOKEN_HERE","name":"read_org","params":{}}'
```

Expect `success`, org fields, and `tool` / `command_reply` of `read_org` — and **no** token fields in the body.

List tools:

```
curl -X POST https://ordoscheduler.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_TOKEN_HERE"}'
```

## Next

- [Quickstart](#docs/quickstart) — first server and workflow  
- [Advanced Topics](#docs/advanced-topics) — handlers, cloning, environment variables  
- [FAQ](#docs/faq) — SSH, limits, stuck jobs  
