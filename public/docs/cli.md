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
Connected to https://api.ordoscheduler.com as your@email.com
Welcome to Ordo - the hierarchical job scheduler
Type 'help' for commands, Ctrl-D to exit.
ordo:root>
```
## Example Session

```
ordo:root> ls                                                                                                                           
Local time is Fri Jul  3 11:59:26 2026
┌────┬─────────────────────────────┬───────────┬──────────┬─────┬────────────────┬──────────┬────────────┬────────────┐
│ ID │ PATH                        │ STATE     │ SERVER   │ PID │ LAST_START     │ DURATION │ NEXT_START │ CALENDAR   │
├────┼─────────────────────────────┼───────────┼──────────┼─────┼────────────────┼──────────┼────────────┼────────────┤
│ 1  │ root/                       │ immutable │          │     │                │          │            │            │
│ 2  │   Bake da Cake/             │ complete  │          │     │ T+00:00:41     │ 00:00:26 │            │            │
│ 1  │   Bake da Cake/Prep         │ complete  │ panthero │     │ T+00:00:30     │ 00:00:05 │            │            │
│ 2  │   Bake da Cake/Mix          │ complete  │ panthero │     │ T+00:00:37     │ 00:00:17 │            │            │
│ 3  │   Bake da Cake/Bake         │ complete  │ panthero │     │                │          │            │            │
│ 4  │   Bake da Cake/Finish       │ complete  │ panthero │     │                │          │            │            │
│ 13 │   Monitoring/               │ hold      │          │     │ T+22:10:26 +1d │ 00:00:01 │ T-00:00:04 │ Monitoring │
│ 5  │   Monitoring/panthero stats │ hold      │ panthero │     │ T+22:10:26 +1d │ 00:00:01 │            │            │
└────┴─────────────────────────────┴───────────┴──────────┴─────┴────────────────┴──────────┴────────────┴────────────┘
ordo:root> cluster run 'Bake da Cake/'                                                                                                  
Cluster started
ordo:root> ls                                                                                                                           
Local time is Fri Jul  3 11:59:52 2026
┌────┬─────────────────────────────┬───────────┬──────────┬───────┬────────────────┬──────────┬────────────┬────────────┐
│ ID │ PATH                        │ STATE     │ SERVER   │ PID   │ LAST_START     │ DURATION │ NEXT_START │ CALENDAR   │
├────┼─────────────────────────────┼───────────┼──────────┼───────┼────────────────┼──────────┼────────────┼────────────┤
│ 1  │ root/                       │ immutable │          │       │                │          │            │            │
│ 2  │   Bake da Cake/             │ running   │          │       │ T+00:00:01     │ 00:00:01 │            │            │
│ 1  │   Bake da Cake/Prep         │ running   │ panthero │ 24595 │ T+00:00:01     │ 00:00:01 │            │            │
│ 2  │   Bake da Cake/Mix          │ sleeping  │ panthero │       │ T+00:00:01     │ 00:00:01 │            │            │
│ 3  │   Bake da Cake/Bake         │ waiting   │ panthero │       │                │          │            │            │
│ 4  │   Bake da Cake/Finish       │ waiting   │ panthero │       │                │          │            │            │
│ 13 │   Monitoring/               │ hold      │          │       │ T+22:10:52 +1d │ 00:00:01 │ T-00:00:08 │ Monitoring │
│ 5  │   Monitoring/panthero stats │ hold      │ panthero │       │ T+22:10:52 +1d │ 00:00:01 │            │            │
└────┴─────────────────────────────┴───────────┴──────────┴───────┴────────────────┴──────────┴────────────┴────────────┘
ordo:root>      
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
