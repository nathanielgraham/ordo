# Welcome to Ordo

**Where AI stops talking... and starts doing.**

While modern AI has become extraordinarily good at thinking, planning, and reasoning, it has historically been limited by its inability to *execute* real work on your infrastructure.

**Ordo** is the bridge — a modern, hierarchical job scheduler with native MCP support. This allows Grok to directly explore, create, schedule, monitor, and debug jobs running on **your** servers.

---

## Standout Features

- **Natural Language Automation**  
  Ask Grok in plain English to create scripts, build schedules, set up dependencies, and debug failures.

- **Hierarchical Workflows**  
  Organize jobs into nested clusters with powerful dependency logic (`needs`, `needs_any`, `on_fail`).

- **Advanced Scheduling**  
  Full Quartz cron support (including all special tokens) plus flexible calendars with `Begin` and `Expire` dates.

- **Real-Time Observability**  
  Beautiful live dashboard with T+/T- timers, interactive dependency graphs, and system metrics.

- **Self-Healing Automation**  
  Automatic retries, failure routing, hold/ice/release controls, and more.


## Ordo + Grok in Action

You can say things like:

- “Create a script that backs up my database every night at 2 AM with 3 retries on failure”
- “Build a job that checks disk space across all servers and alerts me if anything exceeds 90%”
- “Create a calendar called Monthly Reports that runs on the last business day of each month at 8 AM”
- “Analyze the logs of my last failed deployment job and tell me what went wrong”

  Grok can generate the code, create the calendar, attach it to clusters, and even help debug issues.

---

## Ordo Works With or Without AI

**Ordo is a fully functional, powerful job scheduler on its own.** You can use it perfectly well without any AI integration.

However, when connected to Grok via MCP, it becomes something much more powerful — an **AI-native automation platform** where Grok can directly create, schedule, monitor, and debug jobs using natural language.

---

## Who Ordo Is For

- Organizations that want reliable automation at a reasonable price
- AI enthusiasts who want their agents to take real action
- Data engineers building reliable pipelines
- DevOps and SRE teams

## Ready to Begin?

1. **Sign up for a free account** – No credit card required
2. Read the [Quickstart](#docs/quickstart.md) guide
3. **Start building!**

