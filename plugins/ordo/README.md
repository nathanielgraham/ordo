# Ordo plugin for Grok Build

Connects Grok Build to the hosted Ordo MCP server.

- **Endpoint:** `https://ordoscheduler.com/mcp` (HTTPS only)
- **Auth:** `Authorization: Bearer ${ORDO_TOKEN}`
- **Credential:** Ordo user API token from the Ordo UI. Not stored in this plugin.

## Install (after marketplace listing)

```bash
export ORDO_TOKEN=your_token_here
grok plugin install ordo --trust
```

Until it is in the official catalog:

```bash
export ORDO_TOKEN=your_token_here
grok mcp add --transport http ordo https://ordoscheduler.com/mcp \
  --header "Authorization: Bearer ${ORDO_TOKEN}"
grok mcp doctor ordo
```

See also `examples/grok-mcp/README.md` in this repo.

## What it can do

List/start/hold/kill clusters and jobs, calendars and cron, servers (`*_monitor`).
Call `get_documentation` (section `overview` or `api`) in a new session.

Destructive tools (`delete_*`, `kill_*`) exist on the server. Confirm with the user first.
