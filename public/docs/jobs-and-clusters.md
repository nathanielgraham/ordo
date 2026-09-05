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

**Pro Tip**: Use the **Insert Template** dropdown in the job modal. Templates are grouped as **Languages**, **Handlers**, and **Triggers**, and live in `examples/job-templates/` (cached by the app on startup).

### Event triggers

A trigger job is a long-running waiter that exits 0 when an event happens. Dependents then start like any other job.

```
cluster: inbound-invoices
  job: wait-for-file     ← trigger
  job: load-csv          ← Needs wait-for-file
```

Parameters belong in job/cluster **`json`** (`ORDO_JOB_JSON` / `ORDO_CLUSTER_JSON`). Secrets belong on the **server environment** or a `token_file`; `json.token` is only a last-resort fallback. Set a **max runtime** on watchers so a stuck trigger can fire a handler instead of running forever.

See `examples/job-templates/README.md` and the Triggers optgroup (watch path, webhook, GitHub, Slack).

## Clusters

A **Cluster** is a container that can hold jobs and other clusters, forming a hierarchical tree.
Once started, it runs until every job and sub-cluster reaches a terminal state or is iced.
Exception: if any job fails, the cluster itself is marked failed immediately and the On Fail handler is eligible to run, even while other jobs are still in progress.

Clusters are powerful because you can:
- Attach a **Calendar** to run the entire group on a schedule
- Set **On Fail** and **On Overdue** handlers
- Enable **Cloning** to handle overdue executions

Think of clusters as **folders** and jobs as **files**, with scheduling and dependency intelligence built in.

## Attached JSON (`json`)

Jobs and clusters can store an optional **`json`** field — an arbitrary JSON **object** (max 64 KB) used as durable parameters.

**Why use it**

- Keep scripts stable while changing nouns (repo, branch, directories, flags)
- Let agents set parameters via MCP/API without rewriting the script
- Share pipeline defaults on the **cluster**; override per **job** when needed

**Behavior**

- **Durable**: survives reset and a new run cycle (not cleared when the job returns to ready/waiting)
- **Create / update**: set `json` to an object (API may send it as a JSON string; MCP accepts an object)
- **Clear**: send `json: null` or `json: ""` to set the DB column to NULL
- **Omit** on update: leave the existing value unchanged
- **Not for secrets**: tokens and passwords belong in proper secret handling, not this field

**Environment variables at run time**

When a job starts, non-empty values are injected as:

| Variable | Source |
|----------|--------|
| `ORDO_JOB_JSON` | This job's `json` column |
| `ORDO_CLUSTER_JSON` | Parent cluster's `json` column |

Only set when the corresponding column is non-empty. Scripts should treat missing vars as empty.

**Example (Python)**

```python
import json, os
job = json.loads(os.environ["ORDO_JOB_JSON"]) if "ORDO_JOB_JSON" in os.environ else {}
cluster = json.loads(os.environ.get("ORDO_CLUSTER_JSON") or "{}")
# Prefer job key, else cluster (do not smash unknown keys together).
repo = job.get("repo", cluster.get("repo"))
branch = job.get("branch", cluster.get("branch", "master"))
```

**Example (MCP)**

```text
update_cluster     id=<cluster_id>  json={"repo":"myorg/app","dev_dir":"/home/me/app"}
update_job_config  id=<job_id>      json={"branch":"feature/x","test_cmd":"pytest -q"}
start_cluster      id=<cluster_id>
```

## Dependencies

Ordo supports two types of dependencies:
- **Needs All**: "AND" logic. All referenced items must complete successfully.
- **Needs Any**: "OR" logic. Only one of the referenced items needs to complete.

Dependencies can be set on both jobs and clusters.

## Handlers

- **On Fail Handler**: Triggered when a cluster fails.
- **On Overdue Handler**: Triggered when a cluster is still not ready at its next scheduled time.
- **Max Runtime Handler** (job-level): Triggered if a job exceeds its time limit.

All handlers point to another cluster. Shipped Perl handlers talk to Ordo with `OrdoAgent::ordo_post` (core Perl + `curl`).

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
- Prefer `json` for parameters; keep secrets out of `json`.
- Shipped examples use core Perl, POSIX sh, curl, and Python stdlib only. After `upgrade_monitor`, launcher sets `PERL5LIB=~/ordo_node/modules` so jobs can `use OrdoAgent qw(ordo_post)`.
