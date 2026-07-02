# Core Concepts

Ordo is a **hierarchical job scheduler** designed from the ground up for both humans and AI agents. Understanding these foundational ideas will help you use Ordo effectively.

## 1. Jobs vs Clusters

- **Job**: The smallest unit of work. It executes a script (shell, Perl, Python, etc.) on a chosen server.
- **Cluster**: A container that can hold jobs and other clusters, forming a tree structure.

Think of clusters as **folders** and jobs as **files** — except these folders have powerful scheduling, dependency, and failure-handling capabilities.

## 2. Two Types of Dependencies

- **Needs** — "AND" logic. All referenced items must complete successfully before this job or cluster can run.
- **Needs Any** — "OR" logic. Only one of the referenced items needs to complete.

## 3. Job States

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

## 4. Calendars & Scheduling

Calendars use **Quartz Cron** expressions and are attached to clusters. When attached, the entire cluster (and all jobs inside it) follows the defined schedule.

Key fields:
- **Begin** — When this schedule becomes active
- **Expire** — When this schedule should stop running

## 5. Cloning

If a cluster is still running when its next scheduled time arrives, Ordo can:
- Skip the new run (default), or
- **Clone** it — launch another parallel copy

Cloning is especially useful for long-running jobs that shouldn’t block the next cycle.

## 6. Environment Variables

Every running job receives special `ORDO_*` variables that allow scripts to interact with Ordo itself. See the [Advanced Topics](#docs/advanced-topics.md) guide for details and examples.

## 7. Stats Polling & Monitoring

Ordo provides optional real-time stats polling for running jobs and servers (CPU, memory, disk usage, load average, ping latency, and more).

**Important:** Stats polling is **completely optional**. The core scheduling engine, dependencies, calendars, and job execution work perfectly without it. The main Dashboard primarily shows scheduling metrics and does not require polling.

For recommended intervals, API impact, best practices, and how to minimize quota usage, see [Stats Polling & Monitoring](#docs/stats-polling).
