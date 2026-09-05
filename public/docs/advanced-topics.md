# Advanced Topics

This section explores special patterns and advanced usage of Ordo.

## Special Handlers

### On Fail Handler
Triggered when a cluster enters a `failed` state.  
Common use: alerting, cleanup, or escalation.

### On Overdue Handler
Triggered when a cron start is attempted but the cluster **cannot be started** because it is still busy or on hold.

### Max Runtime Handler (Job-level)
Set on individual jobs via `max_runtime_seconds` and `max_runtime_cluster_id`.  
If the job exceeds the time limit, the specified handler cluster is automatically started.

**Setup (all handlers):**
1. Create a dedicated handler cluster.
2. In the source cluster/job edit modal, select the handler in the appropriate dropdown.
3. (Optional) Set `auto_start = false` on handler clusters to prevent accidental execution.

## Cloning

Cloning creates an identical copy of a cluster that can be run in parallel if the original is still busy at the next scheduled time.

**Recommended Pattern:**
- Create an **On Overdue Handler** cluster.
- In that handler, add a job that calls `clone_cluster` using the `ORDO_OVERDUE_CLUSTER_ID` environment variable.

**Clone Job Template** (available in job modal):
```
#!/bin/sh
# Purpose: Clone the overdue cluster
curl -X POST "$ORDO_API" \
  -H "Content-Type: application/json" \
  -d '{
    "command": "clone_cluster",
    "id": '"$ORDO_OVERDUE_CLUSTER_ID"',
    "token": '"$ORDO_TOKEN"'
  }'
```

## Attached JSON and parameterization

Jobs and clusters support a durable `json` object (see [Jobs & Clusters](#docs/jobs-and-clusters.md)).

Typical pattern for reusable pipelines:

1. Put shared defaults on the **cluster** (`repo`, `dev_dir`, …).
2. Put step overrides on the **job** (`branch`, `test_cmd`, …).
3. In the script, read `ORDO_CLUSTER_JSON` and `ORDO_JOB_JSON` and merge (job wins).

This keeps one script body while agents change parameters via MCP `update_job_config` / `update_cluster` without editing code.

**Limits:** top-level JSON object only; max 64 KB; not for secrets. Clear with `json: null`.

## Environment Variables

All running jobs receive these `ORDO_*` variables:

| Variable                        | Description |
|---------------------------------|-----------|
| `ORDO_JOB_ID`                   | Current job ID |
| `ORDO_CLUSTER_ID`               | Parent cluster ID |
| `ORDO_SERVER_ID`                | Server ID |
| `ORDO_EMAIL`                    | Owner email |
| `ORDO_TOKEN`                    | Execution token |
| `ORDO_API`                      | API base URL |
| `ORDO_JOB_JSON`                 | Job `json` column (if set) |
| `ORDO_CLUSTER_JSON`             | Parent cluster `json` column (if set) |
| `ORDO_TEAM`                     | JSON array of team members |
| `ORDO_OVERDUE_CLUSTER_ID`       | Set when triggered by On Overdue handler |
| `ORDO_FAILED_CLUSTER_ID`        | Set when triggered by On Fail handler |
| `ORDO_MAX_RUNTIME_CLUSTER_ID`   | Set on jobs with max runtime handler |
| `ORDO_MAX_RUNTIME_JOB_ID`       | The job ID that exceeded max runtime |

**Example Usage in a handler job:**
```
if [ -n "$ORDO_OVERDUE_CLUSTER_ID" ]; then
    echo "Overdue cluster: $ORDO_OVERDUE_CLUSTER_ID"
    # clone or alert logic here
fi
```

## Meta-Automation Using Environment Variables

Your scripts can interact with Ordo using built-in `ORDO_*` variables (see table above).

**Trigger Another Job**
```
curl -X POST "$ORDO_API" \
  -H "Content-Type: application/json" \
  -d '{
    "command": "start_job",
    "id": 123,
    "token": '"$ORDO_TOKEN"'
  }'
```

**Smart Notification**
```
if [ -n "$ORDO_OVERDUE_CLUSTER_ID" ]; then
    echo "Overdue alert for cluster $ORDO_OVERDUE_CLUSTER_ID"
fi
```

## Advanced Monitoring Setup

For production environments, we recommend a dedicated **Monitoring** cluster that runs `update_stats.pl` on a regular schedule.

See [Stats Polling & Monitoring](#docs/stats-polling.md) for best practices and quota considerations.
