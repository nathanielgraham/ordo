# Core Concepts

Ordo is a **hierarchical job scheduler** designed for both humans and AI agents. Understanding these foundational ideas will help you use Ordo effectively.

## 1. Jobs vs Clusters

- **Job**: The smallest unit of work. Executes a script on a chosen server.
- **Cluster**: A container that can hold jobs and other clusters, forming a tree structure.

Think of clusters as **folders** and jobs as **files** — except these folders have powerful scheduling, dependency, failure-handling, and self-healing capabilities.

## 2. Dependencies

- **Needs All**: "AND" logic. All referenced items must complete successfully.
- **Needs Any**: "OR" logic. Only one referenced item needs to complete.

Dependencies can be set on both jobs and clusters.

## 3. Handlers

Handlers let you automatically respond to problems.

- **On Fail Handler**: Triggered when a cluster fails.
- **On Overdue Handler**: Triggered when a cluster is still not ready at its next scheduled time.
- **Max Runtime Handler** (job-level): Triggered if a job exceeds its `max_runtime_seconds` limit.

All handlers point to another cluster and can be set in the edit modal.

## 4. Cloning

If a cluster is still running at its next scheduled time, it can be **cloned** (run in parallel).  
This is most commonly triggered via an **On Overdue Handler**.

## 5. Calendars & Scheduling

A **Calendar** is a collection of one or more Quartz Cron expressions.  
**To attach a calendar**: edit the target cluster and select it in the **Calendar** dropdown.

The entire cluster follows the attached calendar's schedule.

## 6. Job States

- `ready` — Waiting to run
- `waiting` — Blocked by dependencies
- `running` — Currently executing
- `complete` — Finished successfully
- `failed` — Finished with error
- `sleeping` — Waiting due to Delay setting
- `retrying` — Actively retrying after failure
- `looping` — In a repeating loop
- `zombie` — Scheduler lost track of the process (use **Resync Servers**)
- `killed` — Manually stopped

## 7. Environment Variables

Every running job receives special `ORDO_*` variables that allow scripts to interact with Ordo itself. See the [Advanced Topics](#docs/advanced-topics.md) guide for the full list and examples.

## 8. Stats Polling (Optional)

Real-time monitoring of CPU, memory, disk, etc. is **optional**. Core scheduling works without it.

For recommended intervals, API impact, best practices, and how to minimize quota usage, see [Stats Polling & Monitoring](#docs/stats-polling).
