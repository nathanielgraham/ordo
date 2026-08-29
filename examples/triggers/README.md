# Trigger jobs (examples)

Calendars start clusters on a **clock**. These jobs start the *next* step when an **event** happens.

Pattern:

```text
cluster: inbound-invoices
  job: wait-for-file      ← long-running; exits 0 when the event is seen
  job: load-csv           ← Needs wait-for-file
```

Or: watcher completes → sibling / dependent cluster runs as usual.

Copy a script into a job body (or `~/ordo_node/scripts/`). Parameters belong in job/cluster **`json`** (see Jobs & Clusters), not in the script. Secrets stay in env on the server, not in `json`.

Set a **max runtime** on watcher jobs so a stuck trigger can fire a handler instead of running forever.

| Script | Event |
|--------|--------|
| `wait-for-file.sh` | File or glob appears on the job's server |
| `wait-for-webhook.sh` | HTTP POST to a port on the server |
| `wait-for-github.sh` | New tag or successful workflow on GitHub |
| `wait-for-slack-poll.sh` | Slack message matching a string (Web API poll) |
