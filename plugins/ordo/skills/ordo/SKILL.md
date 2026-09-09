---
name: ordo
description: Use when the user wants to list, start, hold, or inspect Ordo jobs, clusters, calendars, or cron on ordoscheduler.com.
---

# Ordo

Talk to the Ordo MCP server (`ordo__*` tools).

1. If `ORDO_TOKEN` is missing, tell the user to export it (Ordo UI token) and rerun `grok mcp doctor ordo`.
2. New session: `ordo__get_documentation` with section `overview` or `api`.
3. Look up work with `ordo__find_cluster` (default `/root`) or `ordo__read_cluster` / `ordo__read_job` by id.
4. Start is fire-and-forget: `ordo__start_cluster` / `ordo__start_job`, then read state if they ask.
5. Do not call `delete_*` or `kill_*` unless the user clearly asked.
