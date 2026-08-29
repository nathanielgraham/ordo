# Job templates

These files are the source of truth for the job modal **Insert Template** dropdown.

```
examples/job-templates/
  languages/   language starters
  handlers/    on-fail, on-overdue, max-runtime, update-stats
  triggers/    long-running waiters that exit 0 when an event happens
```

## Catalog

`lib/ordo/JobTemplates.pm` scans this tree once (`state` cache) and embeds JSON as `window.ORDO_JOB_TEMPLATES` on the app page. Adding a file here is enough; restart the app to pick it up.

Header comments (optional):

```
# @id watch-path
# @label Watch Path
# @desc Complete when a path/glob appears or changes
```

If omitted, `id` is the filename without extension and `label` is that id with dashes turned into spaces.

## Triggers

A trigger job is a long-running waiter. When it exits 0, dependents start like any other job.

```
cluster: inbound-invoices
  job: wait-for-file     ← trigger
  job: load-csv          ← Needs wait-for-file
```

Parameters belong in job/cluster **`json`** (`ORDO_JOB_JSON` / `ORDO_CLUSTER_JSON`). Secrets belong on the **server environment** (or a token file), not in `json`. `json.token` is only a last-resort fallback.

Set a **max runtime** on watchers so a stuck trigger can fire a handler instead of running forever.

| File | Event |
|------|--------|
| `triggers/watch-path.sh` | Path/glob appears or its mtime changes |
| `triggers/wait-for-webhook.sh` | HTTP POST to a port on the job's server |
| `triggers/wait-for-github.sh` | New tag or successful GitHub Actions run |
| `triggers/wait-for-slack.sh` | Slack message matching a string |
