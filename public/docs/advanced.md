# Advanced Topics

This section explores powerful patterns and advanced usage of Ordo.

## Self-Healing Workflows

One of Ordo’s most powerful capabilities is building **self-healing automation** using On Fail clusters.

### Key Limitation

Each cluster can have **only one** `On Fail` cluster assigned. However, that single On Fail cluster can contain **multiple jobs** (and even sub-clusters), allowing you to perform several actions when a failure occurs.

### Basic Self-Healing Pattern

1. Create your main workflow cluster.
2. Create a separate **On Fail** cluster (e.g. "Alert on Failure").
3. In the main cluster, set the **On Fail** field to point to your alert cluster.
4. In the alert cluster, add one or more jobs (send email, log incident, run cleanup, etc.).

### Chained Escalation (Advanced)

You can create escalation ladders by chaining On Fail clusters:

- Main Workflow → On Fail → **Alert Level 1** (Email Team)
- Alert Level 1 → On Fail → **Alert Level 2** (SMS / PagerDuty)
- Alert Level 2 → On Fail → **Alert Level 3** (Wake on-call engineer)

**Important**: For the chain to work as intended, each alert job should **succeed** (exit code `0`) if its notification was delivered successfully. Only if the notification step itself fails should it return a non-zero exit code to trigger the next level.

## Meta-Automation Using Environment Variables

Your scripts can interact with Ordo itself using the built-in `ORDO_*` environment variables. This enables powerful self-managing workflows.

### Available Variables

| Variable              | Description |
|-----------------------|-----------|
| `ORDO_JOB_ID`         | ID of the currently running job |
| `ORDO_CLUSTER_ID`     | ID of the parent cluster |
| `ORDO_SERVER_ID`      | ID of the server the job is running on |
| `ORDO_EMAIL`          | Email address of the job owner |
| `ORDO_TEAM`           | JSON array of team members |
| `ORDO_TOKEN`          | Execution token |
| `ORDO_API`            | Base URL of the Ordo API |
| `ORDO_JSON`           | Custom JSON data attached to the job (if any) |

### Practical Examples

**Example 1: Trigger Another Job**
"""
#!/bin/sh
# Start another job after this one completes
curl -X POST "$ORDO_API" \
  -H "Content-Type: application/json" \
  -d '{
    "command": "run_job",
    "id": 123,
    "token": "'$ORDO_TOKEN'"
  }'
"""

**Example 2: Smart Notification**
"""
#!/bin/sh
if [ "$ORDO_JOB_ID" = "45" ]; then
  email_team.pl "Critical backup job $ORDO_JOB_ID failed on server $ORDO_SERVER_ID"
else
  email_team.pl "Job $ORDO_JOB_ID failed"
fi
"""

**Example 3: Conditional Logic (Perl)**
"""
#!/usr/bin/env perl
if ($ENV{ORDO_CLUSTER_ID} == 27) {
    system("email_team.pl", "Production issue detected");
}
"""

## Advanced Monitoring Setup

For production environments, we recommend:

1. Create a dedicated **Monitoring** cluster.
2. Add a job that runs `update_stats.pl`.
3. Attach a calendar that triggers every 10–30 seconds.
4. (Optional) Add an On Fail cluster that notifies the team if monitoring stops.

## Private Network & Firewall Deployments

Ordo is well-suited for restricted environments. Common approaches include private VPS deployments with strict firewalls, fully on-premise installations, or hybrid setups.

Contact **ordosched@proton.me** for assistance with custom deployments.

## Cloning Strategy

Enable **Clone on Overdue** for long-running jobs where missing a scheduled cycle would be worse than running two instances in parallel.

## Performance & Scaling Tips

- Keep high-frequency jobs lightweight.
- Avoid sub-second schedules on large numbers of clusters.
- Rotate Execution Tokens during low-activity windows.
- Monitor the **Servers** tab regularly for resource usage.

