# Overview

**Ordo is a hierarchical job scheduler for both humans and AI agents.**

It schedules work across servers with explicit dependencies and a defined recovery path when a job fails, misses its window, or runs too long.

## How it works

- A **Job** is the smallest unit of work. It runs a script on a chosen server.
- **Clusters** are containers for jobs and other clusters, forming a tree.
- **Calendars** are collections of **cron** expressions that decide when clusters start.
- **Handlers** define what happens next when a job fails, misses its window, or runs too long.

## Natural Language Automation

Ordo supports Model Context Protocol and long-lived WebSocket access so agents can explore, create, monitor, schedule, and debug jobs using natural language. WebSocket agents can also **respond to events as they happen** (for example, when a job completes). See [ordo-bot](https://github.com/nathanielgraham/ordo-bot).

You can say things like:

- “Create a calendar for the third Monday of every month and month-end, and attach it to the finance close cluster.”
- “Check disk space on all servers every 15 minutes. If anything’s over 90%, email the team.”
- “Run a daily backup with a 2-hour limit. If it’s still going, start the Backup Watchdog.”
- “Deployment v2.3 failed last night. Look at the logs and tell me what went wrong.”
- “Start the saas-deploy cluster and notify me when it completes.”

The agent can create scripts and schedules on **your** servers, wire dependencies and handlers, and help debug when something breaks. See [Connecting to AI](#docs/connecting-to-ai).

## Who Ordo Is For

- Teams that have outgrown cron and need dependencies, recovery, and a single place to see what ran
- DevOps teams running scheduled work across multiple servers
- Small teams that want reliable automation without babysitting a heavy orchestrator
- AI enthusiasts who want their agents to take real action.

## What You Get

- **Hierarchical workflows**  
  Organize jobs into nested clusters with scheduling and dependency logic built in. See the full chain on a dependency graph instead of reconstructing it from memory.

- **Natural language automation with AI**  
  Describe the job, schedule, or recovery path in plain English. An agent can build it on your servers; you still get real jobs and clusters you can open, edit, and run with or without AI.

- **Automatically respond when things go wrong**  
  `On Fail`, `On Overdue`, and `Max Runtime` handlers can alert, clone, escalate, or recover. The next step is defined before you have a major incident.

- **Cloning**  
  When the previous run is still busy at the next scheduled time, spin up an identical copy instead of skipping, colliding, or hoping.

- **Advanced scheduling**  
  Supports rich Quartz cron syntax plus calendars that can hold multiple cron expressions, so you can define schedules that plain cron can’t express, e.g. the third Monday of February and month-end, with begin/expire windows.

- **Real-time observability**  
  Live dashboard, T+/T− timers, dependency graphs, and server metrics. See whether it ran, when, and what happened. Run history and logs live in one place, so “did it run?” isn’t a research project across hosts.

- **Recovery controls**  
  Retries, hold/ice/release, and escalation paths you own, without standing up an enterprise orchestration stack.

## Works With or Without AI

Ordo is a full job scheduler on its own. MCP and agent clients are optional power, not a requirement.

## Open source

Ordo is free software under the [GNU AGPL v3](https://github.com/nathanielgraham/ordo/blob/master/LICENSE).

- Source: [github.com/nathanielgraham/ordo](https://github.com/nathanielgraham/ordo)
- Run it yourself: [Self-Hosted](#docs/self-hosted)

## Ready to Begin?

1. **[Clone and run it](https://github.com/nathanielgraham/ordo)** — or sign up on the hosted service  
2. Read the [Quickstart](#docs/quickstart) guide  
3. Optionally [connect an AI client](#docs/connecting-to-ai)
