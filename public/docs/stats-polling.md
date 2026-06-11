# Stats Polling & Monitoring

Stats polling is one of Ordo's most powerful optional features, providing real-time visibility into your jobs and servers.

### What is Stats Polling?

Stats polling refers to periodic calls (usually from `update_stats.pl`) that fetch real-time statistics about running jobs and servers.

**Data collected includes:**

**Job-level metrics:**
- CPU usage (%)
- Memory usage (%)
- RSS (Resident Set Size)
- PID, PPID, command name
- Start time and runtime

**Server-level metrics:**
- CPU cores and load average (1/5/15 min)
- Memory and Swap usage
- Disk usage (total + root filesystem)
- Network I/O (total bytes)
- Open file handles
- Process count and zombies
- Uptime
- Ping latency (from servers tab)

This data primarily powers the **Stats column**, CPU/memory badges, and detailed tooltips in the **Jobs & Clusters** tab, as well as server monitoring views. The main **Dashboard** tab focuses on scheduling and job execution metrics and does **not** require stats polling.

### Key Point: Polling is Optional

You do **not** need to enable stats polling to use Ordo.

Core features — job scheduling, dependencies, calendars, self-healing, and execution — work fully without any monitoring. Many users run Ordo successfully with polling disabled or set to very low frequency.

### Pro Tier Limits

- **500,000 API calls per month**
- Up to **10 servers**

### Why It Matters

More frequent polling consumes significantly more API quota. For example, polling every 10 seconds on multiple servers can exhaust your monthly allowance very quickly, while 60-second intervals are much more sustainable.

### Expected Monthly API Usage (per server)

| Polling Interval | Approx. Calls per Server / Month |
|------------------|----------------------------------|
| 10 seconds       | ~259,000                         |
| **30 seconds**   | ~86,000                          |
| **60 seconds**   | ~43,000                          |
| 5 minutes        | ~8,600                           |

**With the Pro tier (500,000 calls):**
- You can comfortably run **~10–11 servers** at 60-second polling
- Or **~5 servers** at 30-second polling

### Recommended Polling Intervals

| Scenario                       | Recommended Interval     | Notes |
|--------------------------------|--------------------------|-------|
| Most Pro users                 | **30 – 60 seconds**      | Best balance of freshness and cost |
| Cost / bandwidth sensitive     | **2 – 5 minutes**        | Minimizes API usage |
| High-frequency monitoring      | 10 seconds or less       | Only recommended in Managed Private, Self-Hosted, or Enterprise deployments |

### Saving API Quota

To minimize unnecessary API usage when you are not actively monitoring:

- Put your **Monitoring** cluster (or the job running `update_stats.pl`) on **Hold** before you log off.
- **Important:** Putting a cluster on Hold only affects jobs in that specific cluster. All your other jobs and clusters will continue to run and schedule normally.
- Release the monitoring job from Hold when you want to resume real-time stats.

**Tip:** Many users create a dedicated "Monitoring" cluster just for stats collection and keep it on Hold by default, releasing it only when they need live visibility.

### Best Practices

- Start with **60-second** intervals and increase frequency only if needed.
- Monitor your actual usage in **Settings → Billing**.
- In **Managed Private**, **Self-Hosted**, and **Enterprise** deployments, you can safely poll much more frequently since it does not count against shared SaaS quota.

### Technical Note

The polling mechanism is handled by `update_stats.pl` (or your own custom scripts). It uses standard API calls and integrates cleanly with the real-time dashboard.
