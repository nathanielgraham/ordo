# API Reference

Ordo’s native API is a JSON command protocol.  
You can speak it over:

- the WebSocket at `wss://ordoscheduler.com/websocket` (preferred for agents)
- the HTTP endpoint `https://ordoscheduler.com/api` (classic REST-style)
- **MCP** at `https://ordoscheduler.com/mcp` (same command names as tools)

All three use the **same command names** and the same JSON shapes. MCP tool names match the `command` field below (e.g. `find_cluster`, `create_cron`, `start_cluster`).

---

## For AI agents (read this first)

### Preferred transport

Use the public client **[ordo-wsagent](https://github.com/nathanielgraham/ordo-wsagent)**.

It gives you:
- immediate command replies, **and**
- live broadcasts (`jobs_changed`, `clusters_changed`, …) so you can wait for real completion.

After you connect and log in, call:

```json
{"command":"get_documentation","section":"api"}
```

(or `"section":"all"`) so you always have the current reference.

### When to keep the WebSocket open vs one-shot

**Keep the connection open (long-lived)** when:
- you start a job or cluster and need to know when it actually finished
- you are driving a multi-step workflow (inspect → change → start → wait → read logs)
- you want to react to failures or state changes in real time

**One-shot is enough** when:
- you are only reading (`read_org`, `find_cluster`, `read_job`, `read_log`, `get_documentation`, …)
- you are making a simple update that does not require waiting for a side-effect

**Rule of thumb:** if the next thing you need depends on a job or cluster reaching a terminal state, keep the WebSocket open and wait for the broadcast. Otherwise a short-lived connection is fine.

### MCP as fallback

MCP tools use the **same names** as this reference.  
Use MCP when a full WebSocket client is impractical or when you only need simple request/response operations.  
For anything that requires waiting on completion events, prefer `ordo-wsagent`.

---

## Authentication

### WebSocket (preferred for agents)

Authenticate **once** at the start of the connection:

```json
{"command":"login_user","token":"your-user-token"}
```

After a successful `login_user` reply, every subsequent command on that same WebSocket is already authenticated. You do **not** send the token again.

(`ordo-wsagent` does the login step for you automatically.)

### HTTP REST endpoint

Every request must include the token:

```json
{
  "command": "…",
  "token": "your-user-token",
  …
}
```

Base URL: `https://ordoscheduler.com/api`

---

## Response shape

```json
{
  "success": 1,
  "command_reply": "command_name",
  "message": "optional human text"
}
```

Always check `success`.

---

## Clear semantics (important)

When updating jobs or clusters:

- **Omit** a field → leave it unchanged
- Send `null`, `""`, or `[]` → **clear** the field

This applies to:

- `json`
- `cal_id` / `cal`
- `needs_ids` / `needs`
- `needs_any_ids` / `needs_any`
- `on_fail_id` / `on_fail`, `on_overdue_id` / `on_overdue`
- `server_id` / `server`
- `max_runtime_seconds` + `max_runtime_cluster_id` (both must be cleared together)
- `description`

Special cases:
- `needs_ids` and `needs_any_ids` are independent. Clearing one does not touch the other.
- The max-runtime pair must be cleared together (both null/0) or both set; mixing is rejected.

---

## Inspection commands

### get_documentation

Retrieve Ordo documentation.  
**Call this first** in a new agent session (section `"api"` or `"all"`).

| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| section   | string | no       | Documentation section. One of: overview, quickstart, core-concepts, jobs-and-clusters, calendars-and-crons, advanced-topics, connecting-to-ai, faq, api, agent-protocol, rest-api, cli, dashboard, stats-polling, settings, private-deployments, self-hosted, all. Default: overview. |
| format    | string | no       | markdown (default) or summary. |

Example:
```json
{"command":"get_documentation","section":"api"}
```

---

### find_cluster

Return the hierarchical tree of clusters and jobs under a path.  
Primary discovery command.

| Parameter | Type   | Required | Description |
|-----------|--------|----------|-------------|
| name      | string | no       | Path starting with /root. Default: /root. |
| filter    | string | no       | Optional state filter: all, running, failed, waiting. |

Example:
```json
{"command":"find_cluster","name":"/root/ops"}
```

Returns a `clusters` array. Each cluster contains its nested `jobs` and child clusters.

---

### read_cluster

Full details for one cluster (state, handlers, needs, jobs, etc.).

| Parameter | Type    | Required | Description |
|-----------|---------|----------|-------------|
| id        | integer | yes*     | Cluster ID. |
| name      | string  | yes*     | Path (alternative to id). |

* One of `id` or `name` is required.

Example:
```json
{"command":"read_cluster","id":24}
```

---

### read_job

Full details for one job (script, needs, server, state, runtime limits, json, etc.).

| Parameter | Type    | Required | Description |
|-----------|---------|----------|-------------|
| id        | integer | yes      | Job ID. |

Example:
```json
{"command":"read_job","id":10}
```

---

### read_log

Most recent log output for a job (stdout/stderr, timestamps, exit code, signal).

| Parameter | Type    | Required | Description |
|-----------|---------|----------|-------------|
| id        | integer | yes      | Job ID. |

Example:
```json
{"command":"read_log","id":10}
```

Useful fields: `out`, `exit_code`, `signal`, `started`, `ended`, `job_path`, `server_name`.

---

### find_log

History of past runs for a job (timestamps + exit codes).

| Parameter | Type    | Required | Description |
|-----------|---------|----------|-------------|
| id        | integer | yes      | Job ID. |

---

### read_org

Current organisation information (tier, limits, member list, usage, etc.).

No parameters required (beyond the authenticated WebSocket session).

Example:
```json
{"command":"read_org"}
```

---

### read_user

Current authenticated user (name, email, org, level).

No parameters required.

---

### find_monitor

Live server list with metrics (CPU, memory, disk, load, uptime).  
Call this before creating a job so you can pick a valid `server_id`.

No parameters required.

Example:
```json
{"command":"find_monitor"}
```

---

### find_cal / read_cal

`find_cal` lists all calendars, their cron expressions, and which clusters are attached.

`read_cal` returns one calendar by `id` or `name`.

```json
{"command":"find_cal"}
{"command":"read_cal","id":3}
{"command":"read_cal","name":"monitoring"}
```

---

### sync

Reconcile scheduler state with actual processes on servers (zombie detection / revival).

```json
{"command":"sync"}
```

---

## Lifecycle commands

After a successful `start_*` keep the WebSocket open and wait for a `jobs_changed` / `clusters_changed` broadcast to know when the work actually finished.

### start_cluster / start_job

| Parameter | Type    | Required | Description |
|-----------|---------|----------|-------------|
| id        | integer | yes*     | Cluster or job ID. |
| name      | string  | yes*     | Path (start_cluster only; alternative to id). |

```json
{"command":"start_cluster","id":17}
{"command":"start_job","id":42}
```

### kill_cluster / kill_job

Stop a running cluster or job.

| Parameter | Type    | Required | Description |
|-----------|---------|----------|-------------|
| id        | integer | yes      | Cluster or job ID. |

### reset_cluster

Reset a cluster back to a clean state (ready to be started again).

| Parameter | Type    | Required | Description |
|-----------|---------|----------|-------------|
| id        | integer | yes      | Cluster ID. |

### Hold / release / ice / melt / complete

All take a required `id`:

| Command | Effect |
|---------|--------|
| `hold_cluster` / `hold_job` | Soft hold |
| `release_cluster` / `release_job` | Release hold |
| `ice_cluster` / `ice_job` | Stronger hold |
| `melt_cluster` / `melt_job` | Un-ice |
| `complete_cluster` / `complete_job` | Mark complete |

### clone_cluster

Create an identical copy of a cluster (does **not** start it).

| Parameter | Type    | Required | Description |
|-----------|---------|----------|-------------|
| id        | integer | yes      | Cluster ID to clone. |

---

## Create commands

### create_cluster

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | yes | Cluster name. |
| parent_id | integer | no | Parent cluster ID (defaults to root). |
| description | string | no | Free-text description. |
| auto_start | boolean | no | Default true. |
| cal_id / cal | integer/string | no | Calendar to attach. |
| on_fail_id / on_fail | integer/string | no | Failure handler. |
| on_overdue_id / on_overdue | integer/string | no | Overdue handler. |
| needs_ids / needs | array of integers | no | AND dependencies. |
| needs_any_ids / needs_any | array of integers | no | OR dependencies. |
| loops | integer | no | Loop count. |
| json | object | no | Durable JSON (max 64 KB). Pass null to clear. |

### create_job

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | yes | Short job name. |
| script_b64 | string | yes* | Base64-encoded script. |
| script | string | yes* | Plain-text script (accepted on WebSocket). |
| parent_id | integer | yes | Cluster that will own the job. |
| server_id / server | integer/string | yes | Server to run on. |
| description | string | no | Free-text description. |
| needs_ids / needs | array | no | AND dependencies. |
| needs_any_ids / needs_any | array | no | OR dependencies. |
| retrys | integer | no | Retry count. |
| loops | integer | no | Loop count. |
| delay | integer | no | Delay in seconds. |
| max_runtime_seconds | integer | no | Runtime limit. |
| max_runtime_cluster_id | integer | no | Handler when limit exceeded. |
| json | object | no | Durable JSON (max 64 KB). |

* One of `script` or `script_b64` is required.

### create_cal

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | yes | Calendar name. |
| tz | string | yes | IANA timezone, e.g. America/Chicago. |
| description | string | no | Free-text description. |

### create_cron

Add a Quartz cron expression to an existing calendar.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| name | string | yes | The **cron expression string** (e.g. `0 0 8 * * ? *`). |
| cal_id | integer | yes | Calendar id from `find_cal` / `read_cal`. |

Example:
```json
{"command":"create_cron","name":"0 0 8 * * ? *","cal_id":3}
```

---

## Update commands

All update commands obey clear-semantics: omit = no change; null / "" / [] = clear.

### update_cluster

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| id | integer | yes | Cluster ID. |
| newname | string | no | Rename. |
| description | string | no | null/"" clears. |
| auto_start | boolean | no | |
| cal_id / cal | integer/string/null | no | Attach or clear calendar. |
| on_fail_id / on_fail | integer/string/null | no | |
| on_overdue_id / on_overdue | integer/string/null | no | |
| needs_ids / needs | array/null | no | Empty array or null clears. |
| needs_any_ids / needs_any | array/null | no | Independent of needs_ids. |
| loops | integer | no | |
| json | object/null | no | |

### update_job_config

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| id | integer | yes | Job ID. |
| newname | string | no | Rename. |
| script / script_b64 | string | no | Replace script. |
| description | string | no | null/"" clears. |
| server_id / server | integer/string/null | no | Move or clear assignment. |
| needs_ids / needs | array/null | no | |
| needs_any_ids / needs_any | array/null | no | Independent. |
| retrys | integer | no | |
| loops | integer | no | |
| delay | integer | no | |
| max_runtime_seconds | integer/null | no | Must be paired with max_runtime_cluster_id. |
| max_runtime_cluster_id | integer/null | no | Must be paired. |
| json | object/null | no | |

### update_cal

Change calendar name / timezone / description (`id` required).

---

## Delete commands

| Command | Parameter | Notes |
|---------|-----------|-------|
| `delete_job` | `id` | Permanent |
| `delete_cluster` | `id` | Permanent |
| `delete_cron` | `id` | Cron entry id |
| `delete_cal` | `id` | Calendar id |

---

## Broadcasts

Broadcasts are unsolicited messages pushed over the WebSocket whenever something changes.

Shape:

```json
{
  "broadcast": "jobs_changed",
  "updates": [ ... ],
  "deletes": [ {"id": 18} ]
}
```

Possible values of `broadcast`:

- `jobs_changed` – job created, updated, started, finished, or deleted. Fields match `read_job`.
- `clusters_changed` – cluster state or membership changed. Fields match `read_cluster`.
- `servers_changed` – server metrics/status updated. Fields match `find_monitor`.
- `cals_changed` – calendar created, updated, or deleted.

**Agent waiting pattern**

1. Send `start_job` or `start_cluster`.
2. Receive the immediate `command_reply`.
3. Keep reading the stream.
4. When a broadcast’s `updates` array contains the job/cluster with a terminal `jobstate` (`complete`, `failed`, …) or `state_id` 5, the work is finished.
5. Optionally call `read_log`, then continue or disconnect.

---

## Command summary

| Area | Commands |
|------|----------|
| Inspect | `get_documentation`, `find_cluster`, `read_cluster`, `read_job`, `find_monitor`, `find_cal`, `read_cal`, `find_log`, `read_log`, `read_org`, `read_user`, `sync` |
| Create | `create_cluster`, `create_job`, `create_cal`, `create_cron` |
| Update | `update_cluster`, `update_job_config`, `update_cal` |
| Lifecycle | `start_*`, `kill_*`, `hold_*`, `release_*`, `ice_*`, `melt_*`, `complete_*`, `reset_cluster`, `clone_cluster` |
| Delete | `delete_job`, `delete_cluster`, `delete_cron`, `delete_cal` |

If you need a parameter not listed here, call `get_documentation` section `api` again after upgrades, or probe with a minimal command and read the `message` on failure.
