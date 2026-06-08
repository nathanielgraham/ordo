# Jobs & Clusters

Jobs and Clusters are the core building blocks of Ordo. Mastering them is essential for building reliable automation.

## Jobs

A **Job** is the smallest unit of work in Ordo. Each job:
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

Ordo supports two types of dependencies:

- **Needs** — "AND" logic. All referenced items must complete successfully.
- **Needs Any** — "OR" logic. Only one of the referenced items needs to complete.

![Setting Job Dependencies](img/job-dependencies.png)

*Configuring job dependencies (needs) in the modal.*

## On Fail Handling

**On Fail** is a **cluster-level** feature only.

- You can assign an `On Fail` cluster to any cluster.
- Individual jobs no longer support a direct `On Fail` setting.

If you need specific failure handling for a single job, wrap that job in its own small cluster and set the `On Fail` target on that cluster.

## Actions Menu (...)

Each job and cluster has an actions menu (...) with the following controls:

- **Run** — Start the job or cluster immediately.
- **Kill** — Stop a currently running job or cluster.
- **Hold** — Pause execution. Downstream jobs will wait until you **Release** it.
- **Release** — Resume a held job or cluster.
- **Ice** — Skip job or cluster without breaking the dependency chain.
- **Melt** — Return an iced job/cluster to normal operation.
- **Reset** — Clear current state and return the job to `ready`.
- **Complete** — Manually mark a job as successfully completed.
- **Delete** — Permanently remove the job or cluster.

![Actions Dropdown Menu](img/attach-calendar.png)

*Actions menu (ellipses) available on each job and cluster row.*

## Visual Dependency Graph

Click **View Graph** on any cluster to see a live visual diagram of all dependencies (Needs, Needs Any, and On Fail). Extremely useful for understanding and debugging complex workflows.

![Dependency Graph Example](img/dependency-graph.png)

*Visual dependency graph showing needs (red), needs_any (green dashed), and on_fail (orange) relationships.*

## SSH Key Authentication 

Ordo supports two ways to set up secure SSH access.

#### Option 1: Automatic Setup

1. In the **Add Server** modal, enter:
   - Hostname / IP
   - An existing username on the remote server
   - The password for that user (used only once)
2. Ordo will automatically copy its public key using `ssh-copy-id`.

After successful setup, you can leave the password field blank.

#### Option 2: Manual Setup

Use this option if you prefer not to enter any password into Ordo.

1. Add Ordo’s public SSH key to the user's authorized_keys file:

```
mkdir -p ~/.ssh
cat >> ~/.ssh/authorized_keys << 'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX ordo@scheduler
EOF
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

2. In Ordo, enter the username and leave the password field blank.

**Best Practice**: Create a dedicated low-privilege user (e.g. `ordo`) on the remote server specifically for Ordo instead of using `root` or your personal account.

## Script Best Practices

- Always begin scripts with a proper **shebang** (`#!/bin/sh`, `#!/usr/bin/env perl`, `#!/usr/bin/env python3`, etc.)
- Place reusable scripts in `~/ordo_node/scripts/` so they can be called by name only
- All job output (stdout + stderr) is automatically captured in the job’s log file
- Use the built-in templates in the job modal as starting points
