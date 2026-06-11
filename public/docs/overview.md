# Welcome to Ordo

**Where AI stops chatting... and starts doing.**

While modern AI has become extraordinarily good at thinking, planning, and reasoning, it has historically been limited by its inability to *execute* real work on your infrastructure.

**Ordo** is the bridge — a modern, hierarchical job scheduler with native MCP support. This allows Grok to directly explore, create, schedule, monitor, and debug jobs running on **your** servers.

![Ordo Main Interface](img/main-table.png)

*Real-time hierarchical job view with live timers, stats, and dependency indicators.*

## Ordo + Grok in Action

You can say things like:

- “Create a new calendar called **US Holidays** that runs at midnight on every major US holiday and then attach it to the **Send Greeting Card** cluster.”
- “Create a monitoring job called **Check Disk Space** that checks disk usage on all servers every 15 minutes, put it in the **Infrastructure Monitoring** cluster, and alert the team if anything exceeds 90%.”
- “Analyze the logs of the job **Deployment v2.3** that failed yesterday and tell me what went wrong.”
- “Create a job called **Daily DB Backup** that runs `pg_dump` on server **prod-db-01**, place it in the **Database Maintenance** cluster, and schedule it to run every night at 2 AM with 3 retries on failure.”

Grok will generate **and test** the code on **your servers**, create the necessary calendars, set up dependencies, and even help debug issues in case something goes wrong.

---

## Standout Features

- **Natural Language Automation**  
  Ask Grok in plain English to create scripts, build schedules, setup dependencies, and debug failures.

- **Hierarchical Workflows**  
  Organize jobs into nested clusters with powerful dependency logic (`needs`, `needs_any`, `on_fail`).

- **Advanced Scheduling**  
  Full Quartz cron support (including all special tokens) plus flexible calendars with `Begin` and `Expire` dates.

- **Real-Time Observability**  
  Beautiful live dashboard with T+/T- timers, interactive dependency graphs, and system metrics.

- **Self-Healing Automation**  
  Automatic retries, failure routing, hold/ice/release controls, and escalation chains.

---

## Ordo Works With or Without AI

**Ordo is a fully functional, powerful job scheduler on its own.** You can use it perfectly well without any AI integration.

However, when connected to Grok via MCP, it becomes something much more powerful — an **AI-native automation platform** where Grok can directly create, schedule, monitor, and debug real work on your infrastructure.

---

## Who Ordo Is For

- Organizations that want reliable automation at a reasonable price
- AI enthusiasts who want their agents to take real action
- Data engineers building reliable pipelines
- DevOps and SRE teams

## Ready to Begin?

1. **Sign up for a free account** – No credit card required
2. Read the [Quickstart](#docs/quickstart) guide
3. **Start building!**

