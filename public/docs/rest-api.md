# REST API Reference

Ordo provides a full REST API for scripting, automation, and meta-automation (e.g. watchdog jobs, custom handlers, etc.).

**Base URL**  
`https://ordoscheduler.com/api`

**Authentication**  
All requests require a valid user token in the body:

```
{
  "token": "your-user-token-from-account-tab"
}
```

**Content-Type**  
`application/json`

**Response Format**

Every response follows this structure:

```
{
  "success": 1,                     // 1 = success, 0 = error
  "command_reply": "command_name",  // echoes the command you sent
  "message": "human-readable text"  // optional status or error message
  // ... command-specific data ...
}
```

---

## Most Useful Commands for Scripting

**Note**: Many commands accept either `id` or `name` (path). Example: `"name": "/root/Bork da Cake/Prep"`.

### Practical Examples

**1. Clone and start a cluster (common in On Overdue Handlers)**
```
curl -X POST https://your-ordo.com/api \
  -H "Content-Type: application/json" \
  -d '{
    "command": "clone_cluster",
    "id": 7,
    "token": "your-token-here"
  }'
```

**2. Get full cluster hierarchy (very useful for watchdog scripts)**
```
curl -X POST https://your-ordo.com/api \
  -H "Content-Type: application/json" \
  -d '{
    "command": "find_cluster",
    "id": 7,
    "token": "your-token-here"
  }'
```

**3. Start a cluster immediately**
```
curl -X POST https://your-ordo.com/api \
  -H "Content-Type: application/json" \
  -d '{
    "command": "start_cluster",
    "id": 7,
    "token": "your-token-here"
  }'
```

**4. Read latest log of a job**
```
curl -X POST https://your-ordo.com/api \
  -H "Content-Type: application/json" \
  -d '{
    "command": "read_log",
    "id": 2,
    "token": "your-token-here"
  }'
```

### Key Commands

- `find_cluster` — Get full hierarchy
- `read_cluster` — Get details of one cluster
- `clone_cluster` — Clone a cluster
- `start_cluster` — Run a cluster immediately
- `start_job` — Run a single job
- `read_log` — Get latest log of a job
- `find_log` — Get log history for a job
- `update_cluster` — Update cluster settings (e.g. on_fail_id, on_overdue_id)
- `sync` — Resync servers and handle zombies

---

**Best Practices for Scripting**

- Prefer `id` when available — more reliable.
- Use `name` (path) when you only know the hierarchy.
- Always check `success` in responses.
- Keep tokens secure and rotate regularly.
