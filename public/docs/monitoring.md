# Scripts & System Monitoring

This guide covers how to write effective scripts in Ordo and how to enable full system monitoring.

## 1. Writing Scripts in Ordo

Ordo is very flexible — you can run shell commands, Python, Perl, or any executable.

### Important Notes About Scripts

- For **multi-line scripts**, wrap the entire command with `/bin/sh -c "..."`.
- Use only single or double quotes. Avoid Perl-style quoting like `q{}` outside of `perl -e`.
- You can use `python3 -c '...'`, `perl -e '...'`, or regular shell commands.
- All STDOUT and STDERR output is automatically captured and stored in `$HOME/ordo_node/logs`.
- Scripts placed in `$HOME/ordo_node/scripts/` can be called by **name only** (no full path needed).
- Scripts located elsewhere must use the full filesystem path.

### Included Scripts

Ordo comes with two helpful scripts already in the `ordo_node/scripts` directory:

1. **`update_stats.pl`** – Gathers detailed server metrics (CPU, memory, disk, load average, open files, processes, etc.) and per-process stats. Required for rich monitoring on the Servers tab.
2. **`email_team.pl`** – Sends an email to you and your team. Takes the message as the first positional argument. Very useful for failure notifications when used in an `on_fail` job.

You can call both by name only.

### Examples

**Simple Shell Script:**
```
echo "Hello from Ordo!"
```

**Multi-line Script (Recommended):**
```
/bin/sh -c "
  echo 'Starting backup...';
  mysqldump -u root mydatabase > /backups/db.sql;
  echo 'Backup completed at $(date)';
"
```

**Using an Included Script:**
```
update_stats.pl
```

**Using email_team.pl in an on_fail job:**
```
email_team.pl "Backup job failed on server prod-1"
```

## 2. Enabling System Monitoring

To see rich real-time metrics (CPU, memory, disk, etc.) on the **Servers** tab:

### Step-by-Step Setup

1. Go to **Jobs & Clusters** tab.
2. Create a new cluster named `System Monitoring`.
3. Inside it, create one job:

**Job Name:** `update-stats`

**Script:**
```
update_stats.pl
```

**Recommended Settings:**
- Retries: `2`
- Delay: `0`

### Step 3: Schedule the Stats Job

1. Go to **Calendars** tab.
2. Create a new calendar named `System Stats`.
3. Add this cron expression:
   ```
   */10 * * * * ? *    # Every 10 seconds (adjust to taste)
   ```
4. Save the calendar.
5. Return to the `System Monitoring` cluster → Edit → Attach the `System Stats` calendar.

### Step 4: Verify Monitoring

- After 5-10 seconds, go to the **Servers** tab.
- You should now see live updating metrics for your servers.

### Next Steps
- Learn more about [Calendars & Cron Expressions](/#docs/calendars-and-crons.md)
- Connect Ordo to Grok via MCP for natural language script creation

