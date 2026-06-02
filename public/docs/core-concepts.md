# Core Concepts

Ordo is a **hierarchical job scheduler** designed from the ground up for both humans and AI agents. Understanding these foundational ideas will help you use Ordo effectively.

## 1. Jobs vs Clusters

- **Job**: The smallest unit of work. It executes a script (shell, Perl, Python, etc.) on a chosen server.
- **Cluster**: A container that can hold jobs and other clusters, forming a tree structure.

Think of clusters as **folders** and jobs as **files** — except these folders have powerful scheduling, dependency, and failure-handling capabilities.

## 2. Three Types of Dependencies

- **Needs** — "AND" logic. All referenced items must complete successfully before this job or cluster can run.
- **Needs Any** — "OR" logic. Only one of the referenced items needs to complete.
- **On Fail** — Run this cluster *only if* the parent job or cluster fails.

**Best Practice**: Set `On Fail` at the **cluster level** rather than on individual jobs. This creates cleaner, more maintainable self-healing workflows.

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

Every running job receives special `ORDO_*` variables that allow scripts to interact with Ordo itself. See the [FAQ](../faq) for details and examples.

## 7. The Visual Dependency Graph

Click **View Graph** on any cluster to see a live diagram showing all dependency relationships (Needs, Needs Any, and On Fail). Extremely helpful for understanding and debugging complex workflows.
