# Ordo Overview

**A modern hierarchical job scheduler with real-time monitoring, powerful dependencies, Quartz scheduling, and self-healing automation.**

Ordo was built to replace outdated tools like cron, AutoSys, and Control-M — giving you enterprise-grade capabilities with a beautiful, intuitive interface and full AI integration.

## Core Concepts

- **Clusters** act like folders — organize your workflows logically
- **Jobs** are the actual scripts (Shell, Python, Perl, etc.)
- **Calendars** provide powerful recurring schedules (Quartz cron)
- **Dependencies** let you build reliable pipelines
- **MCP Connector** lets Grok directly control Ordo

## Key Features

- Real-time updates (no manual refresh needed)
- Self-healing workflows with `on_fail`
- Hierarchical design with visual dependency graphs
- Full Quartz scheduling (advanced rules, holidays, business days)
- Self-hosted and private by default
- Beautiful web UI + powerful CLI + REST API

## Quick Links

- [Quickstart →](quickstart.md)
- [MCP Connector for Grok →](mcp.md)
- [Web UI Guide →](web-ui.md)
- [REST API Reference →](rest-api.md)
- [CLI Reference →](cli.md)

---

**2. quickstart.md** (short & friendly)

```markdown
# Quickstart

Get your first job running in under 5 minutes.

## 1. Sign In
Open Ordo and log in.

## 2. Create a Cluster
- Go to **Jobs & Clusters**
- Click the ellipsis (...) next to `root/` → **Create Cluster**
- Name it (e.g. `quickstart`) and save

## 3. Add a Job
- Open your new cluster
- Click ellipsis → **Create Job**
- Name: `hello-world`
- Script: `echo "Hello from Ordo at $(date)"`
- Save

## 4. Run It
- Click the ellipsis on your job → **Run**
- Watch the state change in real time
- Click **View Log** to see the output

**Congratulations!** You've run your first Ordo job.

Next: [Web UI Guide →](web-ui.md)
