### FAQ

**Q: How do I set up SSH so Ordo can reach my server?**  
**A:** Ordo connects **from the scheduler to your host** over SSH using **key-based auth**. You can install the key **automatically** (if password login is allowed) or **manually**.

**Ordo’s public key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFteavF5RjZ19R2m/el3nXhsBK7q8sQTxUxye5bNUY2l ordo@ordoscheduler.com
```

### Option 1 - Automatic (password enabled)

If the remote user can log in with a **password** over SSH:

1. In Ordo: **Servers → Add server**.
2. Enter **host**, **SSH user**, **port** (usually 22), and the user’s **password**.
3. Ordo connects once with the password, installs its **public key** in that user’s `~/.ssh/authorized_keys`, then uses the key for all future connections.

You can disable password authentication on the server afterward if you want key-only access. Ordo does not need the password again for normal job runs.

### Option 2 - Manual (key only)

If password login is disabled, or you prefer to provision keys yourself, install Ordo’s public key on the remote account:

```
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFteavF5RjZ19R2m/el3nXhsBK7q8sQTxUxye5bNUY2l ordo@ordoscheduler.com' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Then in Ordo enter **host**, **SSH user**, and **port** only (no password).

### Checklist

- The SSH user can write under its home directory (`~/ordo_node` is created on first use).
- Firewall allows SSH from Ordo’s scheduler to your host.
- Prefer a dedicated user (e.g. `ordo`) over root when possible.

**Test:** run a simple job (`#!/bin/sh` + `echo ok`). If there is no log output, re-check `authorized_keys`, username, port, and firewall.

**Security notes**

- Remove that line from `authorized_keys` anytime to revoke access.
- If you used automatic setup, treat the password as one-time bootstrap; prefer key-only SSH after the key is installed.

---

**Q: What is the `~/ordo_node` directory?**  
**A:** When you add a server, Ordo creates this directory on the remote host:
```
ordo_node/
├── bin/      # Core tools (launcher.pl, update_stats.pl, email_team.pl, ...)
├── scripts/  # Optional custom scripts on the server
├── logs/     # Job output
└── modules/  # Perl helper modules
```
Job scripts can live in the job definition in the UI; `scripts/` is useful for shared helpers. See [Jobs & Clusters](#docs/jobs-and-clusters).  

---

**Q: Where do scripts actually run?**  
**A:** On the **server assigned to the job**, via SSH from the Ordo scheduler — not on the Ordo web/scheduler host itself. Choose the correct server in the job modal. Logs and `~/ordo_node` paths are always on that remote machine.  

---

**Q: How do I write multi-line scripts?**  
**A:** Start with a shebang (`#!/bin/sh`, `#!/usr/bin/env perl`, etc.). Use **Insert Template** in the job modal for common patterns (shell, stats, email, handlers). See [Jobs & Clusters](#docs/jobs-and-clusters).  

---

**Q: What do the ORDO_* environment variables do?**  
**A:** Every job run gets `ORDO_*` variables (job id, cluster id, API URL, token, server id, and handler context such as overdue/failed/max-runtime ids when applicable). Scripts can call the Ordo API or branch on context. Full list: [Advanced Topics](#docs/advanced-topics).  

---

**Q: What is the difference between Needs and Needs any?**  
**A:**
- **Needs** — all listed dependencies must be satisfied (**AND**).
- **Needs any** — at least one listed dependency must be satisfied (**OR**).

Dependencies are evaluated before a job (or cluster) starts. See [Core Concepts](#docs/core-concepts).  

---

**Q: What is the difference between Needs, On Fail, and On Overdue?**  
**A:**
- **Needs / Needs any** — normal dependencies before start (AND / OR).
- **On Fail** — cluster to start when this cluster **fails**.
- **On Overdue** — cluster to start when a calendar (or start attempt) finds this cluster **not startable** (e.g. still running, unsatisfied dependencies, or on hold). Often used to **clone** and run a parallel cycle.

Best practice: use separate **handler clusters** with **auto_start off**, and point `on_fail` / `on_overdue` at them. Prefer **different** handler clusters for fail vs overdue so context stays clear. See [Core Concepts](#docs/core-concepts) and [Advanced Topics](#docs/advanced-topics).  

---

**Q: Can I use the same cluster for both On Fail and On Overdue?**  
**A:** Technically yes, but it’s easy to mix failed vs overdue context. **Prefer two handler clusters** — one for fail, one for overdue — especially if scripts use `ORDO_FAILED_CLUSTER_ID` or `ORDO_OVERDUE_CLUSTER_ID`.  

---

**Q: How do I limit how long a job can run (max runtime)?**  
**A:** Max runtime is set **on the job** (not the cluster):

- **max runtime (seconds)** — how long the job may run
- **max runtime handler (cluster)** — cluster to start when that limit is exceeded

When the limit fires, Ordo can start your handler cluster (alert, kill/cleanup, etc.). Job scripts may also see related `ORDO_MAX_RUNTIME_*` environment variables.

For setup patterns and examples, see [Advanced Topics](#docs/advanced-topics).

---

**Q: What is auto_start?**  
**A:** When a **parent** cluster starts, children with **auto_start enabled** start automatically. Turn **auto_start off** for handler clusters (on_fail / on_overdue targets) so they only run when the handler fires.  

---

**Q: I cloned a cluster and it disappeared after it ran. Is that a bug?**  
**A:** No. Clones are meant for a **single cycle** (e.g. overdue catch-up). After the clone finishes, Ordo removes it so the tree does not fill with copies. The original cluster remains. See [Advanced Topics](#docs/advanced-topics).  

---

**Q: Why can’t I start the root cluster?**  
**A:** The root cluster is the organization tree anchor. It is **not** runnable. Create a child cluster under root and start that instead.  

---

**Q: A job is stuck in starting or running but nothing is on the server. What do I do?**  
**A:** Often a **zombie**: the process exited (or the host was unreachable) while the scheduler still thought it was running.  
1. Use **Sync** (reconciles scheduler state with processes on remote servers).
2. If a job is still wrong, **Complete** it manually from the UI (or the API) after you’ve confirmed nothing is running.
3. Re-check SSH connectivity and that the job’s server is online.

See also the SSH setup question above.  

---

**Q: How do I schedule jobs?**  
**A:** Create a **Calendar**, add one or more **cron** expressions, then attach the calendar to a **cluster** (calendar picker / `cal_id` on the cluster). Scheduling is at the cluster level. See [Calendars & Crons](#docs/calendars-and-crons).  

---

**Q: How do I view job logs?**  
**A:** Job row → **⋯** → **View Log**. Via MCP/API: `find_logs` then `read_log`. Files live under `~/ordo_node/logs/` on the **job’s server**.  

---

**Q: MCP returned “Monthly API limit reached”. What do I do?**  
**A:** MCP and API calls share your org’s monthly quota. Open **Billing** to see usage or upgrade. Limits reset on the date shown in org details (`read_org` / Settings).  

---

**Q: My servers are behind a firewall or private network. What are my options?**  
**A:** Common case. Email **ordosched@proton.me** about private VPS, on-premise, or hybrid options.  

---

**Q: How do I contact support?**  
**A:** **ordosched@proton.me**  

---

**Q: Is Ordo open source?**  
**A:** Some core pieces are open source (e.g. [Cron::Toolkit](https://metacpan.org/pod/Cron::Toolkit) on CPAN). The hosted product, web UI, and advanced features are proprietary.  
