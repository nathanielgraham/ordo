# Jobs & Clusters

Jobs and Clusters are the core building blocks of Ordo. Mastering them is essential for building reliable automation.

## Jobs

A **Job** is the smallest unit of work in Ordo. Each job:
- Executes a script (shell, Perl, Python, etc.) on a chosen server
- Can have dependencies, retries, loops, delays, and max runtime
- Produces detailed logs stored in `~/ordo_node/logs/`

### Creating and Editing Jobs

1. Click the `Actions` menu on any cluster -> **New Job**
2. Fill in the fields:
   - **Name**: Clear and descriptive
   - **Script**: The actual command or script (always start with a shebang)
   - **Server**: Where the job should run
   - **Dependencies**: Needs, Needs Any
   - **Delay**, **Retries**, **Loops**, and **Max Runtime**

**Pro Tip**: Use the **Insert Template** dropdown in the job modal for common patterns (Shell, Perl, Python, Update Stats, Email Team, etc.).

## Clusters

A **Cluster** is a container that can hold jobs and other clusters, forming a hierarchical tree.
Once started, it runs until every job and sub-cluster reaches a terminal state or is iced.
Exception: if any job fails, the cluster itself is marked failed immediately and the On Fail handler is eligible to run, even while other jobs are still in progress.

Clusters are powerful because you can:
- Attach a **Calendar** to run the entire group on a schedule
- Set **On Fail** and **On Overdue** handlers
- Enable **Cloning** to handle overdue executions

Think of clusters as **folders** and jobs as **files**, with scheduling and dependency intelligence built in.

## Dependencies

Ordo supports two types of dependencies:
- **Needs All**: "AND" logic. All referenced items must complete successfully.
- **Needs Any**: "OR" logic. Only one of the referenced items needs to complete.

Dependencies can be set on both jobs and clusters.

## Handlers

- **On Fail Handler**: Triggered when a cluster fails.
- **On Overdue Handler**: Triggered when a cluster is still not ready at its next scheduled time.
- **Max Runtime Handler** (job-level): Triggered if a job exceeds its time limit.

All handlers point to another cluster.

## Cloning

If a cluster is still running at its next scheduled time, it can be **cloned** (run in parallel).  
This is most commonly triggered via an **On Overdue Handler**.

## Actions Menu (...)

Each job and cluster has an actions menu (...) with the following controls:
- **Run** - Start the job or cluster immediately.
- **Kill** - Stop a currently running job or cluster.
- **Hold** - Pause execution. Downstream jobs will wait until you **Release** it.
- **Release** - Resume a held job or cluster.
- **Ice** - Skip job or cluster without breaking the dependency chain.
- **Melt** - Return an iced job/cluster to normal operation.
- **Reset** - Clear current state and return the job to `ready`.
- **Complete** - Manually mark a job as successfully completed.
- **Delete** - Permanently remove the job or cluster.

## Visual Dependency Graph

Click **View Graph** on any cluster to see a live visual diagram of all dependencies (Needs, Needs Any, and handlers). Useful for understanding and debugging complex workflows.

## Best Practices

- Use descriptive names for both jobs and clusters.
- Group related jobs into clusters.
- Use handlers and cloning for robust automation.
- Keep scripts in `~/ordo_node/scripts/` for reusability.
