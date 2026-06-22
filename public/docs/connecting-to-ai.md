# Connecting to AI 

Ordo supports **Model Context Protocol (MCP)**, allowing trusted AI models like Grok to directly explore, create, schedule, monitor, and debug jobs on your infrastructure using natural language.

## Quick Start

1. Go to **Settings** → copy your **API Token**.
2. Tell Grok in the chat:

> Connect to Ordo at `https://ordoscheduler.com/mcp` with token `YOUR_TOKEN_HERE`

Grok will remember the connection for the rest of the conversation.

---

## What Grok Can Do

- View and navigate your full job tree in real time
- Create complex jobs and clusters (Shell, Python, Perl, etc.)
- Build and attach calendars with Quartz cron
- Read logs and help debug failures
- Start, stop, hold, kill, reset jobs and clusters
- Sync servers and manage state
- Check organization usage and rate limits

---

## Creating Jobs – Examples

### Disk Space Alert (Daily at 8 AM)
**Prompt:**
> Create a job called "disk-alert-snarf" in the "monitoring" cluster on server "snarf" that runs every day at 8 AM and emails me if disk usage goes above 80%.

### Python System Report (Hourly)
**Prompt:**
> Create a Python job called "memory-report" in the "health-checks" cluster on server "tigra" that runs every hour and logs memory and disk usage to /tmp.

### Daily Backup (Every Night at 2 AM)
**Prompt:**
> Create a job called "daily-backup" in the "backups" cluster on server "liono" that runs every night at 2 AM and performs a full backup.

---

## Tips for Best Results

When asking Grok to create jobs, be specific about:
- The **purpose** of the job
- **Which server** it should run on
- **Which cluster** to place it in
- **When** you want it to run (schedule)

**Pro Tip**: Ask Grok to show you the script before creating the job.

---

## Security Best Practices

Connecting an AI gives it real power over your infrastructure. Follow these best practices:

- **Only connect trusted models** — Currently **Grok** is the recommended model due to its strong truth-seeking design. 
- **Use dedicated low-privilege accounts** on remote servers. Never use root. Create a specific user (e.g. `ordo`) with minimal permissions.
- **Rotate tokens regularly** — Use the **Rotate** buttons in Settings for both Execution Token and API Token.
- **Rotate immediately** if you no longer trust a connection.
- **Never share your token** publicly or with untrusted models.

**Important**: The security of your servers ultimately depends on responsible use. Only give access to models you fully trust.

---

## Available Tools

**Browsing** — `list_jobs`, `get_job_details`, `get_cluster_details`  
**Creation** — `create_job`, `create_cluster`, `create_calendar`  
**Management** — `manage_job`, `manage_cluster`, `update_job`, `update_cluster`  
**Scheduling** — `list_calendars`, `create_calendar`, `add_cron`, `attach_calendar`, `detach_calendar`  
**Logs** — `read_log`, `find_logs`  
**Servers** — `list_servers`, `sync`  
**Info** — `read_user`, `read_org`, `get_documentation`

---

## Quick Test

```bash
curl -X POST https://ordoscheduler.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"token": "YOUR_TOKEN_HERE"}'
