# Welcome to Ordo

**Where AI stops chatting... and starts doing.**

While modern AI has become extraordinarily good at thinking, planning, and reasoning, it has historically been limited by its inability to *execute* real work on your infrastructure.

**Ordo** is the bridge — a modern, hierarchical job scheduler with native MCP support. This allows Grok to directly explore, create, schedule, monitor, debug, and **heal** jobs running on **your** servers.

## What You Can Do

You can say things like:

- “Create a calendar called `US holidays` that runs at midnight on every major US holiday and attach it to my Send Greeting Card cluster.”

- “Every 15 minutes, check disk space on my servers. Put that in Infrastructure Monitoring and email the team if anything is over 90% full.”

- “Set up a daily backup with a 2-hour time limit. If it runs longer than that, kick off the Backup Watchdog.”

- “The Deployment v2.3 job failed yesterday — look at the logs and tell me what went wrong.”

Grok can create the scripts and schedules on **your** servers, wire dependencies and handlers, and help you debug when something breaks.

## Standout Features

- **Natural Language Automation**  
  Ask Grok in plain English to create scripts, build schedules, setup dependencies, and debug failures.

- **Hierarchical Workflows**  
  Organize jobs into nested clusters with powerful dependency logic.

- **Respond when things go wrong**  
  On Fail, On Overdue, and Max Runtime handlers can alert, clone, escalate, or recover.

- **Clone when a run overlaps the next schedule**  
  If a cluster is still busy when the calendar fires, an On Overdue handler can start a parallel clone.

- **Advanced Scheduling**  
  Full Quartz cron support plus flexible calendars with `Begin` and `Expire` dates.

- **Real-Time Observability**  
  Beautiful live dashboard with T+/T- timers, interactive dependency graphs, and system metrics.

- **Self-Healing Automation**  
  Automatic retries, failure routing, hold/ice/release controls, and escalation chains.

## Ordo Works With or Without AI

**Ordo is a fully functional, powerful job scheduler on its own.** You can use it perfectly well without any AI integration.

However, when connected to Grok via MCP, it becomes something much more powerful — an **AI-native automation platform** where Grok can directly create, schedule, monitor, heal, and debug real work on your infrastructure.

## Who Ordo Is For

- Organizations that want reliable automation at a reasonable price
- AI enthusiasts who want their agents to take real action
- Data engineers building reliable pipelines
- DevOps and SRE teams

## Ready to Begin?

1. **Sign up for a free account** – No credit card required
2. Read the [Quickstart](#docs/quickstart) guide
3. **Start building!**
