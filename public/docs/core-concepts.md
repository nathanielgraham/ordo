# Core Concepts

Ordo is a **hierarchical job scheduler** designed for both humans and AI agents. Understanding these foundational ideas will help you use Ordo effectively.

## 1. Jobs vs Clusters

- **Job**: The smallest unit of work. Executes a script on a chosen server.
- **Cluster**: A container that can hold jobs and other clusters, forming a tree structure.

Think of clusters as **folders** and jobs as **files** - except these folders have powerful scheduling, dependency, and failure-handling capabilities.

## 2. Dependencies

- **Needs All**: "AND" logic. All referenced items must complete successfully.
- **Needs Any**: "OR" logic. Only one referenced item needs to complete.

## 3. Handlers

- **On Fail Handler**: Triggered when a cluster fails.
- **On Overdue Handler**: Triggered when a cluster is still not ready at its next scheduled time.

Handlers point to another cluster and can be set in the Cluster Edit Modal.

## 4. Job States

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

## 5. Calendars & Scheduling

Calendars use Quartz Cron expressions and are attached to clusters. The entire cluster follows the schedule.

## 6. Cloning

If a cluster is still running at its next scheduled time, it can be **cloned** (run in parallel). Use an On Overdue Handler for automatic cloning.

## 7. Environment Variables

Every running job receives special `ORDO_*` variables that allow scripts to interact with Ordo itself. See the [Advanced Topics](#docs/advanced-topics.md) guide for details and examples.

## 8. Stats Polling (Optional)

Real-time monitoring of CPU, memory, disk, etc. is **optional**. Core scheduling works without it.
For recommended intervals, API impact, best practices, and how to minimize quota usage, see [Stats Polling & Monitoring](#docs/stats-polling).
