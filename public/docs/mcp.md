# Connecting to Grok

Ordo now supports **Model Context Protocol (MCP)**, allowing Grok to directly control your job scheduler.

## Quick Start

1. Copy your API token from the Settings → Account tab
2. Tell Grok in the chat:

> Connect to my Ordo at `https://your-ordo.example.com/mcp` with token `YOUR_TOKEN_HERE`

Grok will remember the connection for the rest of the conversation.

```Screenshot: /mcp_connect page showing endpoint and example prompt```

---

## What Grok Can Do

- View and monitor all jobs and clusters in real time
- Create complex jobs (Shell, Python, Perl, etc.)
- Build advanced recurring schedules using powerful calendars
- Manage calendars and cron schedules
- Start, stop, hold, kill, or reset jobs/clusters
- Read log output and debug failures
- Sync servers and fix zombie processes
- Check organization usage and rate limits

```Screenshot: Grok discovering Ordo tools```

---

## Creating Jobs – Examples

### Disk Space Alert (Daily at 8 AM)
**Prompt:**
> Create a job called "disk-alert-snarf" in the "monitoring" cluster on server "snarf" that runs every day at 8 AM and emails me if disk usage goes above 80%.

### Python System Report (Hourly)
**Prompt:**
> Create a Python job called "memory-report" in the "health-checks" cluster on server "tigra" that runs every hour and logs memory and disk usage to /tmp

### Daily Backup (Every Night at 2 AM)
**Prompt:**
> Create a job called "daily-backup" in the "backups" cluster on server "liono" that runs every night at 2 AM and performs a full backup

```Screenshot: Example conversation with Grok creating a job```

---

## Tips for Best Results

When asking Grok to create a **script**, try to mention these four key things:
- The **purpose** of the script
- **Which server** (or `server_id`) it should run on
- **When** you want it to run (recurring schedule or one-time)
- **Which cluster** you want the job created in (jobs cannot be placed directly in the root cluster)

Other tips:
- Ask Grok to show you the script before creating the job

---

## Ordo Calendar Advantage (Quartz Cron)

Ordo uses **Quartz Cron** syntax, which is significantly more powerful than standard cron:

- Supports **7 fields** (seconds + years) instead of the usual 5
- Advanced tokens like: `3rd Monday in January`, `last Friday of month`, etc.
- Multiple crons per calendar

This allows complex schedules (e.g. US Holidays calendar) that tools like Google Cloud Scheduler cannot do.

```Screenshot: Calendar creation and attachment interface```

---

## Important Notes About Scripts

- For multi-line scripts, wrap with `/bin/sh -c "..."`  
- Use only single or double quotes (no `q{}` outside of `perl -e`)
- You can use `python3 -c '...'`, `perl -e '...'`, or regular shell commands
- STDIN / STDOUT output is automatically captured in `$HOME/ordo_node/logs`
- Scripts in `$HOME/ordo_node/scripts` can be called by name only
- Scripts elsewhere must use the full filesystem path

```Good Example:```
```bash
/bin/sh -c 'USAGE=$(df / | tail -1 | awk "{print \$5}" | sed "s/%//"); if [ "$USAGE" -lt 25 ]; then echo "Low disk on $(hostname): ${USAGE}%" >> /tmp/disk-alerts.log; fi'
```

---

## Available Tools

**Browsing**  
`list_jobs`, `get_job_details`, `get_cluster_details`

**Creation**  
`create_job`, `create_cluster`, `create_calendar`

**Management**  
`manage_job`, `manage_cluster`, `update_job`, `update_cluster`

**Scheduling**  
`list_calendars`, `create_calendar`, `add_cron`, `attach_calendar`, `detach_calendar`

**Logs**  
`read_log`, `find_logs`

**Servers & Maintenance**  
`list_servers`, `sync`

**Info**  
`read_user`, `read_org`

---

## Security

- Your token is required for every connection
- Never share your token publicly
- You can revoke or regenerate tokens in Ordo settings at any time

---

**Ready to automate?**  
Just tell Grok you're connected and start giving it tasks!
