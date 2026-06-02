### FAQ

**Q: What is the `~/ordo_node` directory?**  
**A:** When you add a server, Ordo automatically creates this directory on the remote server:

```
ordo_node/
├── bin/        # Core tools (launcher.pl, update_stats.pl, email_team.pl, etc.)
├── scripts/    # Your custom scripts go here
├── logs/       # All job output is stored here
└── modules/    # Perl helper modules
```

See [Jobs & Clusters](#docs/jobs-and-clusters) for more details.

**Q: How do I write multi-line scripts?**  
**A:** Always start with a proper shebang line (`#!/bin/sh`, `#!/usr/bin/env perl`, etc.). Use the **Insert Template** dropdown in the job modal for common patterns. See [Jobs & Clusters](#docs/jobs-and-clusters).

**Q: What do the ORDO_* environment variables do?**  
**A:** They allow your scripts to interact with Ordo itself (e.g. trigger other jobs, send notifications, make decisions based on context). See [Advanced Topics](#docs/advanced-topics) for the full list and examples.

**Q: What is the difference between Needs and On Fail?**  
**A:** 
- **Needs** = normal dependencies (AND/OR logic)
- **On Fail** = run only if the parent fails

**Best practice**: Set On Fail at the **cluster level**. See [Core Concepts](#docs/core-concepts).

**Q: How do I schedule jobs?**  
**A:** Create a **Calendar** with cron expressions, then attach it to a cluster. See [Calendars & Cron](#docs/calendars-and-cron).

**Q: How do I view job logs?**  
**A:** Click the **⋯** (Actions) menu on any job → **View Log**. Logs are stored in `~/ordo_node/logs/` on the server.

**Q: My servers are behind a firewall or private network. What are my options?**  
**A:** This is common. Email **ordosched@proton.me** to discuss private VPS, on-premise, or hybrid deployment options.

**Q: How do I contact support?**  
**A:** Email **ordosched@proton.me**

**Q: Is Ordo open source?**  
**A:** Some core components are open source. The full web UI and advanced features are currently proprietary.
