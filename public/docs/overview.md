# Welcome to Ordo

**Where AI stops chatting... and starts doing.**

While modern AI has become extraordinarily good at thinking, planning, and reasoning, it has historically been limited by its inability to *execute* real work on your infrastructure.

**Ordo** is the bridge — a modern, hierarchical job scheduler with native MCP support. This allows Grok to directly explore, create, schedule, monitor, debug, and **repair** jobs running on **your** servers.

## What You Can Do

You can say things like:

- “Create a calendar called `US holidays` that runs at midnight on every major US holiday and then attach it to the Send Greeting Card cluster.”

- “Create a job that checks disk space on all my servers every 15 minutes. Put it in `Infrastructure Monitoring` and email the team if anything exceeds 90%.”

- “Set up a daily backup with a 2-hour time limit. If it runs longer than that, start the Backup Watchdog.”

- “The Deployment v2.3 job failed yesterday — look at the logs and tell me what went wrong.”

Grok will create the scripts and schedules on **your** servers, wire dependencies and handlers, and help you debug when something breaks.

## Standout Features

- **Natural Language Automation**  
  Ask Grok in plain English to create scripts, build schedules, setup dependencies, and debug failures.

- **Hierarchical Workflows**  
  Organize jobs into nested clusters with powerful dependency logic.

- **Respond when things go wrong**  
  `On Fail`, `On Overdue`, and `Max Runtime` handlers can alert, clone, escalate, or recover.

- **Cloning**  
  Cloning creates an identical copy of a cluster that can be run in parallel if the original is still busy at the next scheduled time.

- **Advanced Scheduling**  
  Full Quartz cron support plus flexible calendars with `Begin` and `Expire` dates.

- **Real-Time Observability**  
  Beautiful live dashboard with T+/T- timers, interactive dependency graphs, and system metrics.

- **Self-Healing Automation**  
  Automatic retries, failure routing, hold/ice/release controls, and escalation chains.

## Ordo Works With or Without AI

**Ordo is a fully functional, powerful job scheduler on its own.** You can use it perfectly well without any AI integration.

However, when connected to Grok via MCP, it becomes something much more powerful — an **AI-native automation platform** where Grok can directly create, schedule, monitor, repair, and debug real work on your infrastructure.

## Who Ordo Is For

- AI enthusiasts who want their agents to take real action
- Organizations that want reliable automation at a reasonable price
- Data engineers building reliable pipelines
- DevOps and SRE teams

## Ready to Begin?

1. **Sign up for a free account** – No credit card required
2. Read the [Quickstart](#docs/quickstart) guide
3. **Start building!**
