# Ordo REST API Reference

Ordo provides a full-featured REST API for programmatic control — perfect for CI/CD integration, custom dashboards, or automation scripts.

**Base URL**  
https://your-ordo-instance.com/api

**Authentication**  
All requests require a valid user token in the request body:

    {
      "token": "your-user-token-from-account-tab"
    }

Tokens are returned on login and visible in the Account tab.

**Content-Type**  
application/json

## Response Format

Every response follows this structure:

    {
      "success": 1,                     // 1 = success, 0 = error
      "command_reply": "command_name",  // echoes the command you sent
      "message": "human-readable text"  // optional status or error message
      // ... command-specific data ...
    }

**Success Example**

    {
      "success": 1,
      "command_reply": "start_job",
      "message": "Job started"
    }

**Error Example**

    {
      "success": 0,
      "command_reply": "start_job",
      "message": "Job is already running"
    }

## Command vs Command Reply

- **command** (your request): the action you want Ordo to perform (e.g., "start_job")
- **command_reply** (response): echoes the command name so you can match responses in async environments

This pattern makes it easy to handle multiple concurrent requests.

## Real-Time Updates via WebSocket (Broadcasts)

For live status without polling, connect to the WebSocket:

wss://your-ordo.com/websocket

After sending your token, you'll receive **broadcast** messages when state changes:

    {
      "broadcast": "jobs_changed" | "clusters_changed" | "cals_changed" | "servers_changed" | "org_changed",
      "updates": [ ... changed objects ... ],
      "deletes": [ ... deleted IDs ... ]
    }

**Common broadcasts**:
- jobs_changed — a job started, completed, failed, etc.
- clusters_changed — cluster state or structure changed
- org_changed — team or permissions updated

Use these to update your UI in real time — just like the web interface does.

## Core Endpoint: /api

**POST** /api

All commands are sent here.

**Generic Request Example**

    {
      "token": "abc123...",
      "command": "start_job",
      "id": "5"
    }

## Commands

### Job Commands

| Command         | Description                              | Required Params              | Example Request |
|-----------------|------------------------------------------|------------------------------|-----------------|
| start_job       | Run a job immediately                    | id                           | See below |
| kill_job        | Kill a running job                       | id                           | See below |
| hold_job        | Prevent future runs                      | id                           | See below |
| release_job     | Resume after hold                        | id                           | See below |
| ice_job         | Skip this scheduled run                  | id                           | See below |
| melt_job        | Undo ice                                 | id                           | See below |
| complete_job    | Force job to complete state              | id                           | See below |
| delete_job      | Permanently delete job                   | id                           | See below |
| read_log        | Get latest log output                    | id                           | See below |
| read_log        | Get specific historical log              | id, log_id                   | See below |

### Cluster Commands

| Command            | Description                                   | Required Params | Example |
|--------------------|-----------------------------------------------|-----------------|---------|
| start_cluster      | Run entire cluster now                        | id              | See below |
| hold_cluster       | Hold all future runs                          | id              | See below |
| release_cluster    | Resume after hold                             | id              | See below |
| ice_cluster        | Skip this run of cluster                      | id              | See below |
| melt_cluster       | Undo ice                                      | id              | See below |
| complete_cluster   | Force entire cluster to complete              | id              | See below |
| reset_cluster      | Reset all jobs to ready (clean slate)         | id              | See below |
| delete_cluster     | Permanently delete cluster and contents       | id              | See below |

### Data Retrieval

| Command         | Description                           | Params                  | Returns |
|-----------------|---------------------------------------|-------------------------|---------|
| find_cluster    | Get full hierarchy                    | none (optional name)    | clusters array with nested jobs |
| find_cal        | List all calendars                    | none                    | cals array |
| find_monitor    | List connected servers                | none                    | servers array |
| find_log        | Get log history for job               | id                      | logs array (id, started, ended, exit_code) |
| read_user       | Get current user info                 | none                    | user object + token |
| read_org        | Get organization + team members       | none                    | org object |

## Examples

**Run a job**

    curl -X POST https://your-ordo.com/api/command \
      -H "Content-Type: application/json" \
      -d '{
        "token": "abc123...",
        "command": "start_job",
        "id": "5"
      }'

**Get full hierarchy**

    curl -X POST https://your-ordo.com/api/command \
      -H "Content-Type: application/json" \
      -d '{
        "token": "abc123...",
        "command": "find_cluster"
      }'

**View specific log run**

    curl -X POST https://your-ordo.com/api/command \
      -H "Content-Type: application/json" \
      -d '{
        "token": "abc123...",
        "command": "read_log",
        "id": "3",
        "log_id": 127
      }'

## Tips for Integration

- Prefer id over path names — more reliable.
- All commands are idempotent where possible.
- Errors return success: 0 + message.
- Rate limiting: be reasonable (Ordo is self-hosted).

Happy automating!

[← Back to Documentation](/docs)
