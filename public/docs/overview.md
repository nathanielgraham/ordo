# Overview of Ordo

**Ordo** is a modern, hierarchical job scheduler that combines powerful automation capabilities with real-time visibility and deep AI integration. It is designed for teams that need reliable, observable, and intelligent automation — going far beyond traditional cron jobs or basic schedulers.

## Standout Features

### Grok AI Integration (Natural Language Automation)

One of Ordo’s most powerful capabilities is its seamless integration with **Grok via MCP**.

You can create jobs, scripts, and schedules using plain English:



- "Create a job called "daily-backup" in the "backups" cluster on server "liono" that runs every night at 2 AM and performs a full backup."
- “Create a job that backs up my database and schedule it to run every night at 2 AM with 3 retries on failure.”
- “Write a Python script that checks all servers for high memory usage and alerts me if anything exceeds 85%.”
- “Add a job to the Monthly Reports calendar that runs on the first Monday of every month at 8 AM.”
- “Analyze the logs of my last failed deployment job and tell me what went wrong.”

**Grok can**:
- Generate the actual script code
- Create appropriate calendars and cron expressions
- Set up dependencies and failure handling
- **Read job logs and help debug failures** in natural language

This makes sophisticated automation accessible to both technical and non-technical users.

### Hierarchical Workflows

Organize jobs into nested **Clusters** — like folders, but with powerful scheduling and dependency logic. This allows you to build complex, tree-structured workflows that are easy to manage and visualize.

### Real-Time Observability

- Live T+ / T- timers
- Real-time dashboard with running jobs, durations, and KPIs
- Beautiful cyberpunk-style web UI with instant updates

### Advanced Scheduling & Self-Healing

- Full Quartz cron support (plus standard 5-field cron)
- Flexible calendars with `Begin` and `Expire` dates
- Automatic retries, on-fail routing, hold/ice/release controls

### Interactive Dependency Graph

Ordo includes a powerful **visual dependency graph** for any cluster:

- See the full relationships between jobs and sub-clusters
- Color-coded nodes based on current jobstate (running, complete, failed, etc.)
- Click any node to instantly open the edit modal
- Clear legend for `needs`, `needs_any`, and `on_fail` relationships

This makes it much easier to understand and debug complex, nested workflows at a glance.

### Other Powerful Capabilities

- Sophisticated dependency management (`needs`, `needs_any`, `on_fail`)
- Centralized logging and job history
- Multi-server fleet management with real-time stats
- Team collaboration and permission system

## Who Ordo Is For

- DevOps and SRE teams managing production workloads
- Data engineers building reliable pipelines
- Development teams that need dependable recurring automation
- Organizations that want to combine human-friendly AI assistance with industrial-grade scheduling

## Where Ordo Fits in the Ecosystem

Ordo occupies a unique position:
- **More powerful and observable** than basic cron or systemd timers
- **More lightweight and beautiful** than heavy orchestrators like Airflow or Prefect
- **Enhanced with modern AI** (Grok) for natural language job creation and log analysis

It gives teams **enterprise reliability** with modern usability and AI superpowers.
