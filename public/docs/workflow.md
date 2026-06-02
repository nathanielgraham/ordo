# Building Robust Workflows

Now that you've completed the Quickstart and successfully ran your first workflow, let's turn it into something more robust with failure handling, monitoring, retries, and advanced features.

We'll continue with the fun **"Bork da Cake"** example.

## 1. Understanding Job States

Ordo uses clear job states. The most important ones to know are:

- **ready** — Waiting to be scheduled or triggered
- **waiting** — Waiting for a dependency to be met
- **sleeping** — Has a Delay set and is waiting for that time to elapse
- **running** — Currently executing
- **complete** — Finished successfully
- **failed** — Exited with error
- **overdue** — Missed its scheduled start time (often due to a long-running previous cycle)
- **retrying** — Actively retrying after failure
- **looping** — Repeating according to loop count
- **killed** — Process received an explicit SIGTERM (killed by user or system)
- **zombie** — Scheduler thinks the process is still running, but it cannot be found on the server (orphan process)

**Tip on Zombies**: If a job appears to be running for a very long time, go to the **Dashboard** and click **Resync Servers**. This forces Ordo to check the actual state on your servers. If zombies are found, you can manually mark the job as **Complete**.

## 2. Improve the Cake Workflow with On-Fail Handling

**Best Practice**: Set **On Fail Cluster** at the **cluster level** rather than on individual jobs. This way, if *any* job in the workflow fails, the failure handler will trigger.

1. First, create the failure handler:
   - Go to the **Jobs & Clusters** tab.
   - Click **New Cluster** and name it `Cake Fail Handler`.
   - Inside it, create one job:
     - **Name:** `email-team`
     - **Script:**
       ```
       #!/bin/sh
       email_team.pl "Bork da Cake failed! Check the logs."
       ```

2. Go back to the main `Bork da Cake` cluster.
3. Click the **Actions** (⋯) menu → **Edit**.
4. Set **On Fail Cluster** to `Cake Fail Handler`.

**[Screenshot: Cluster edit modal showing On Fail Cluster setting]**

## 3. Retries, Loops, and Delay

In the job modal you can configure powerful timing controls:

- **Retries** — How many times to retry on failure
- **Loops** — How many times to repeat the job
- **Delay** — Seconds to wait before the job starts

**Tip**: Use **Delay** (e.g. 10–30 seconds) together with Retries to avoid churn — preventing the same job from instantly restarting over and over.

## 4. Overdue Clusters and Cloning

If a cluster is scheduled but can't start because a previous run is still going, it becomes **Overdue**.

- By default, overdue clusters error out.
- If you enable **Cloning** on the cluster, Ordo will automatically create an exact copy that runs in parallel.

This is very useful for time-sensitive workflows that must not be delayed.

## 5. Enable System Monitoring

To see live CPU, memory, disk, and load metrics:

1. Create a cluster named `System Monitoring`.
2. Add a job named `update-stats`:
   ```
   #!/bin/sh
   update_stats.pl
   ```
3. Create a calendar that runs every 15 seconds and attach it.

After a short wait, the **Servers** tab will show rich live metrics.

**[Screenshot: Servers tab with live metrics]**

## 6. Using the Dependency Graph

Click the **Graph** button on any cluster to see a visual representation of all dependencies, including `on_fail` paths.

**[Screenshot: Dependency Graph modal showing complex workflow]**

## 7. Best Practices

- Always start scripts with a proper shebang (`#!/bin/sh`, `#!/usr/bin/env python3`, etc.).
- Use the **Insert Template** dropdown when creating or editing jobs.
- Log important steps with `echo` — they appear in job logs and history.
- Name jobs clearly and keep scripts focused.
- Use **Delay** + **Retries** to build stable, non-churning workflows.
- Set **On Fail Cluster** at the cluster level for cleaner failure handling.
- Periodically click **Resync Servers** on the Dashboard if you suspect zombie processes.

## 8. Grok Integration (Optional)

Once connected via MCP, you can ask Grok to create, modify, and debug entire workflows using natural language.
See the [Connecting to Grok](#docs/mcp.md) guide for details.

## 9. Advanced Topics ##

- Build self-healing workflows with retries + on-fail recovery
- Create complex calendars (holiday calendars, business days, first Friday of month, etc.)
- Use cloning for time-critical parallel execution

### Next Step ###
Building [Calendars & Crons](#docs/calendars-and-crons.md)
