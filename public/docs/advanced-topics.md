# Advanced Topics

This section explores special patterns and advanced usage of Ordo.

## Self-Healing Workflows

One of Ordo’s most powerful capabilities is building **self-healing automation** using handlers.

### On Fail & On Overdue Handlers

- **On Fail Handler** — Triggered when a cluster fails.
- **On Overdue Handler** — Triggered when a cluster is still not ready at its next scheduled time. Common reasons include still `running` or `looping`, `failed`, `killed`, or `hold`.

**Setup:**
1. Create a handler cluster (e.g. "Alert & Clone").
2. In the main cluster’s edit modal, select the handler in the **On Fail Handler** or **On Overdue Handler** dropdown.
3. In the handler cluster, add jobs for alerting, cloning, cleanup, etc.

**Handler Environment Variables**

Handler jobs receive special variables:
- `ORDO_OVERDUE_CLUSTER_ID`
- `ORDO_FAILED_CLUSTER_ID`

Use these to make intelligent decisions (e.g. clone the original cluster).

### Cloning Strategy

Use an **On Overdue Handler** that calls `clone_cluster` for long-running jobs where missing a cycle would be worse than running two instances in parallel.

**Example Clone Job Template** (available in the job modal):
- "Clone Overdue Cluster" template automatically clones and starts the new instance.

## Max Runtime Watchdog Pattern

For jobs or clusters with strict time limits, use a **Watchdog** job:

1. Create a watchdog job in the same cluster (or a dedicated Watchdogs cluster).
2. Set a **Delay** equal to your max runtime + buffer (e.g. 7260 seconds for a 2-hour limit).
3. Use the **Max Runtime Watchdog** template.
4. Customize the action when the limit is exceeded (alert, kill, trigger handler, etc.).

**Tip:** The watchdog checks completion status of all other jobs and sub-clusters (treating `ice` as complete).

## Meta-Automation Using Environment Variables

Your scripts can interact with Ordo using built-in `ORDO_*` variables.

### Available Variables

| Variable                    | Description |
|-----------------------------|-----------|
| `ORDO_JOB_ID`               | Current job ID |
| `ORDO_CLUSTER_ID`           | Parent cluster ID |
| `ORDO_SERVER_ID`            | Server ID |
| `ORDO_EMAIL`                | Owner email |
| `ORDO_TOKEN`                | Execution token |
| `ORDO_API`                  | API base URL |
| `ORDO_DELAY`                | Delay value set on this job (in seconds) |
| `ORDO_JSON`                 | Custom JSON data attached to the job |
| `ORDO_TEAM`                 | JSON array of team members |
| `ORDO_OVERDUE_CLUSTER_ID`   | Source cluster if triggered by overdue handler |
| `ORDO_FAILED_CLUSTER_ID`    | Source cluster if triggered by on_fail handler |

### Practical Examples

**Trigger Another Job**
```
curl -X POST "$ORDO_API" \
  -H "Content-Type: application/json" \
  -d '{
    "command": "start_job",
    "id": 123,
    "token": "'$ORDO_TOKEN'"
  }'
```

**Smart Notification**
```
if ($ENV{ORDO_OVERDUE_CLUSTER_ID}) {
    system("email_team.pl", "Overdue alert for cluster $ENV{ORDO_OVERDUE_CLUSTER_ID}");
}
```

## Advanced Monitoring Setup

For production environments, we recommend a dedicated **Monitoring** cluster that runs `update_stats.pl` on a regular schedule.

See [Stats Polling & Monitoring](#docs/stats-polling.md) for best practices and quota considerations.
