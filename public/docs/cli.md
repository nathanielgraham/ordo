# Ordo Command-Line Interface (CLI)

The official terminal client for Ordo — giving you full control from the command line.

## Status Note

**This CLI is currently out of date** (last major update was several months ago).  
It is still useful for basic operations and interactive exploration, but some newer features (handlers, cloning, max runtime, etc.) may not be fully supported yet.

We plan to refresh the CLI soon. In the meantime, the Web UI and MCP (AI) are the most up-to-date interfaces.

## Overview

The `ordo` CLI is a fast, powerful way to manage your job scheduler without leaving the terminal. It features:

- A rich interactive shell with colored output
- Hierarchical navigation (`ls` / `cd`)
- Full job and cluster management
- Real-time status and log viewing
- Server monitoring and sync tools

## Installation

```
cpanm App::Ordo
```

Or see the [GitHub repository](https://github.com/nathanielgraham/App-Ordo) for manual install.

## Getting Started

Run:

```
ordo
```

You’ll be dropped into an interactive shell:

```
Connected to https://ordoscheduler.com as your@email.com
Welcome to Ordo - the hierarchical job scheduler
Type 'help' for commands, Ctrl-D to exit.
ordo:root>
```

## Example Session

```
ordo:root> ls
... (table output) ...
ordo:root> cluster run 'Bake da Cake/'
Cluster started
```

## Key Commands

- `ls` — List jobs/clusters in current path
- `cd <path>` — Navigate between clusters
- `job create ...` — Create new job
- `cluster run <name>` — Execute a cluster
- `sync` — Resync servers and handle zombies
- `help` — Show all commands

Type `help <command>` inside the shell for detailed usage.

## Configuration

The CLI stores its config at:

`~/.config/App-ordo/ordo_config.json`
