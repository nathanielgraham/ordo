ordo - workload automation and job scheduler

## Prerequisite debian packages
sudo apt-get install libreadline-dev

## Prerequisite CPAN modules
Mojo::SQLite

## Grok Build / MCP

Remote MCP: `https://ordoscheduler.com/mcp`

Auth is `Authorization: Bearer $ORDO_TOKEN` (token from the Ordo UI).
Do not commit the token. Setup: [examples/grok-mcp/README.md](examples/grok-mcp/README.md).
