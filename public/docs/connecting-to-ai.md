# Connecting to AI

Ordo supports **Model Context Protocol (MCP)**, so trusted models like **Grok** can explore, create, schedule, monitor, and debug jobs on your infrastructure using natural language.

## Quick start

1. Open **Settings** and copy your **API token**.
2. Tell Grok in the chat:

> Connect to Ordo at `https://ordoscheduler.com/mcp` with token `YOUR_TOKEN_HERE`

Grok will remember the connection for the rest of the conversation.

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
- Create calendars and cron entries
- Start, hold, kill, complete, reset jobs and clusters
- Clone clusters (for overdue / catch-up workflows)
- Read logs and help debug failures
- Sync servers and reconcile process state
- Read org usage and limits
- wire **On Fail**, **On Overdue**, and **Max Runtime** handlers.

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

Tell Grok to call **`get_documentation`** at the beginning of your session.

When asking Grok to create jobs, be specific about:
- The purpose of the job
- Which server it should run on
- Which cluster to place it in
- When you want it to run
- Dependencies if any
- Special handlers if any (`on_fail`, `on_overdue`, `max_runtime`)

## Security

- Connecting an AI gives it real power over your infrastructure. Only connect trusted models.
- Use a **dedicated low-privilege account** on remote hosts; avoid root when possible.  
- **Rotate** tokens regularly. Treat them like passwords and never post them in public channels.  

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
