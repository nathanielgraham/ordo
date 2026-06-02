### FAQ

**Q: What is the `~/ordo_node` directory?**  
**A:** When you add a server, Ordo automatically creates this directory structure on the remote server:

```
ordo_node/
├── bin/              # Core tools (launcher.pl, update_stats.pl, email_team.pl, etc.)
├── scripts/          # Your custom scripts go here
├── logs/             # All job output is stored here
└── modules/          # Perl helper modules
```

**Q: What are the ORDO_* environment variables for?**  
**A:** They let your scripts interact with Ordo itself. Useful examples:

- `ORDO_JOB_ID` — Use it inside a script to start, stop, or update another job.
- `ORDO_TEAM` — JSON array of team members; perfect for sending notifications with `email_team.pl`.
- `ORDO_CLUSTER_ID` / `ORDO_SERVER_ID` — Build self-aware automation that knows its context.
- `ORDO_API` + `ORDO_TOKEN` — Make authenticated API calls back to Ordo from within a job.

This enables powerful meta-automation patterns.

**Q: How do I write multi-line scripts?**  
**A:** Always start with a proper shebang line:

```
#!/bin/sh
echo "Hello from Ordo!"
sleep 2
```

```
#!/usr/bin/env perl
print "Hello from Perl at job $ENV{ORDO_JOB_ID}\n";
```

**Q: What are the main job states?**  
**A:** 
- `ready` — waiting to run
- `waiting` — waiting for dependencies
- `running` — currently executing
- `complete` — finished successfully
- `failed` — finished with error
- `sleeping` — waiting due to Delay setting
- `retrying` / `looping` — in retry or loop cycle
- `zombie` — scheduler lost track of the process (use **Resync Servers**)
- `killed` — manually stopped

**Q: What is the difference between "Needs" and "On Fail"?**  
**A:** 
- **Needs** = normal dependencies (a job or cluster must finish before this one runs)
- **On Fail** = run this cluster *only if* the parent fails

**Best practice:** Set `On Fail` at the **cluster level**.

**Q: How do I make jobs run on a schedule?**  
**A:** Create a **Calendar** with cron expressions, then attach it to a cluster.

**Q: How do I view job logs?**  
**A:** Click the **⋯** (Actions) menu on any job → **View Log**.

**Q: My servers are behind a firewall or private network. What are my options?**  
**A:** Email **ordosched@proton.me** for custom deployment options (private VPS, on-premise, etc.).

**Q: How do I contact support?**  
**A:** Email **ordosched@proton.me**

**Q: Is Ordo open source?**  
**A:** Some core components are open source (including `Cron::Toolkit` on CPAN). The full web UI and advanced features are currently proprietary.
