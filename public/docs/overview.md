# Welcome to Ordo
**Where AI stops chatting... and starts doing.**

While modern AI has become extraordinarily good at thinking, planning, and reasoning, it has historically been limited by its inability to *execute* real work on your infrastructure.

**Ordo** is the bridge — a modern, hierarchical job scheduler with native MCP support. This allows Grok to directly explore, create, schedule, monitor, debug, and **heal** jobs running on **your** servers.

## Standout Features

- **Natural Language Automation**  
  Ask Grok in plain English to create scripts, build schedules, setup dependencies, and debug failures.

- **Hierarchical Workflows**  
  Organize jobs into nested clusters with powerful dependency logic (`needs`, `needs_any`).

- **Self-Healing with Handlers**  
  **On Fail**, **On Overdue**, and **Max Runtime** handlers let you automatically alert, clone, escalate, or recover from problems.

- **Cloning**  
  Automatically run parallel instances when a long-running cluster misses its next scheduled window.

- **Advanced Scheduling**  
  Full Quartz cron support plus flexible calendars with `Begin` and `Expire` dates.

- **Real-Time Observability**  
  Beautiful live dashboard with T+/T- timers, interactive dependency graphs, and system metrics.

- **Self-Healing Automation**  
  Automatic retries, failure routing, hold/ice/release controls, and escalation chains.

---

## Ordo + Grok in Action

You can say things like:

- “Create a new calendar called **US Holidays** that runs at midnight on every major US holiday and then attach it to the **Send Greeting Card** cluster.”
- “Create a monitoring job called **Check Disk Space** that checks disk usage on all servers every 15 minutes, put it in the **Infrastructure Monitoring** cluster, and alert the team if anything exceeds 90%.”
- “Create a daily backup job with a 2-hour max runtime. If it exceeds the limit, trigger the Backup Watchdog handler.”
- “Analyze the logs of the job **Deployment v2.3** that failed yesterday and tell me what went wrong.”

Grok will generate **and test** the code on **your servers**, create the necessary calendars, set up dependencies and handlers, and even help debug issues.

---

## Ordo Works With or Without AI

**Ordo is a fully functional, powerful job scheduler on its own.** You can use it perfectly well without any AI integration.

However, when connected to Grok via MCP, it becomes something much more powerful — an **AI-native automation platform** where Grok can directly create, schedule, monitor, heal, and debug real work on your infrastructure.

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
