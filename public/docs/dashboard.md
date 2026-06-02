# Dashboard

The **Dashboard** is your real-time command center for Ordo. It focuses on **job scheduling health**, upcoming work, recent activity, and high-level system performance.

## Overview

The Dashboard updates automatically and gives you a consolidated view of orchestration activity.

### KPI Bar (Top)

Shows high-level statistics for the current day:
- **Success Rate** — Percentage of jobs that completed successfully
- **Runs Today** — Total number of job executions
- **Failed Runs Today** — Number of failed jobs

### Live Cards

**Running Now**  
Live list of currently executing jobs with T+ (how long they’ve been running).

**Recently Failed**  
Most recent failed jobs with how long ago they failed.

**Next Scheduled**  
Upcoming jobs and clusters with live T- countdowns.

**Overdue Clusters**  
Clusters that missed their scheduled start time — high priority items.

### Recent Activity

Live table of recent job executions with timestamps, names, actions, and servers.

## Server Health

**Note**: Detailed per-server metrics (CPU %, memory, disk usage, load averages, etc.) are available in the **Servers** tab.

For continuous monitoring, we recommend creating a dedicated "Monitoring" cluster that runs `update_stats.pl` on a regular schedule (every 10–30 seconds).

## Key Features & Tips

- **Resync Servers** — Forces fresh data collection from all monitored servers. Useful when you suspect zombie processes or want updated stats.
- All timers (T+ and T-) update every second.
- Use **Cloning** on long-running clusters to prevent them from becoming overdue.
- The Dashboard is job-centric. Switch to the **Servers** tab for infrastructure-level visibility.

