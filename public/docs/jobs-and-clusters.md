# Jobs & Clusters

Jobs and Clusters are the core building blocks of Ordo. Mastering them is essential for building reliable automation.

## Jobs

A **Job** is the smallest unit of work. Each job:
- Executes a script (shell, Perl, Python, etc.) on a chosen server
- Can have dependencies, retries, loops, and delays
- Produces detailed logs stored in `~/ordo_node/logs/`

### Creating and Editing Jobs

1. Click the **⋯** (Actions) menu on any cluster → **New Job**
2. Fill in the fields:
   - **Name** — Clear and descriptive
   - **Script** — The actual command or script (always start with a shebang)
   - **Server** — Where the job should run
   - **Dependencies** — Needs, Needs Any, or On Fail
   - **Delay**, **Retries**, and **Loops** (optional but powerful)

**Pro Tip**: Use the **Insert Template** dropdown in the job modal for common patterns (Shell, Perl, Python, Update Stats, Email Team, etc.).

## Clusters

A **Cluster** is a container that can hold jobs and other clusters, forming a hierarchical tree.

Clusters are powerful because you can:
- Attach a **Calendar** to run the entire group on a schedule
- Set **On Fail** behavior for the whole cluster
- Enable **Cloning** to handle overdue executions

Think of clusters as **folders** and jobs as **files** — with scheduling and dependency intelligence built in.

## Dependencies

Ordo supports three types of relationships:

- **Needs** — "AND" logic. All referenced items must complete successfully.
- **Needs Any** — "OR" logic. Only one of the referenced items needs to complete.
- **On Fail** — Run this cluster *only if* the parent fails.

**Best Practice**: Set `On Fail` at the **cluster level** rather than on individual jobs. This creates cleaner, more maintainable self-healing workflows.

## Visual Dependency Graph

Click **View Graph** on any cluster to see a live visual diagram of all dependencies (Needs, Needs Any, and On Fail). Extremely useful for understanding and debugging complex workflows.

## Script Best Practices

- Always begin scripts with a proper **shebang** (`#!/bin/sh`, `#!/usr/bin/env perl`, `#!/usr/bin/env python3`, etc.)
- Place reusable scripts in `~/ordo_node/scripts/` so they can be called by name
- All job output (stdout + stderr) is automatically captured in the job’s log file
- Use the built-in templates in the job modal as starting points

