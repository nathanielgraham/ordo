# Calendars & Cron

Calendars let you define reusable, recurring schedules using **Quartz Cron** expressions and attach them to clusters so that entire workflows run automatically.

## What is a Calendar?

A **Calendar** is a collection of one or more cron schedules. You create a calendar, define when it should run, then **attach** it to a cluster. Once attached, the entire cluster (and all jobs inside it) follows that schedule.

## Creating a Calendar

1. Go to the **Calendars** tab.
2. Click **+ Create Calendar**.
3. Fill in:
   - **Name**: Descriptive name (e.g., "Daily Reports", "Hourly Monitoring")
   - **Timezone**: Usually your local timezone (defaults to browser timezone)
   - **Description**: Optional notes
4. Click **Save**.

## Adding Cron Expressions

After creating a calendar:
1. Click the **⋯** menu on the calendar → **Add Cron** (or **View Crons**).
2. Fill in:
   - **Cron Expression**: e.g. `0 */15 * * * ? *`
   - **Description**: Human-readable note (optional)
   - **Begin** (optional): When this cron should start being active
   - **Expire** (optional): When this cron should stop

## Quartz Cron Syntax

Ordo supports full **Quartz 7-field cron** (and standard 5-field cron for compatibility).

**Format**: `seconds minutes hours day-of-month month day-of-week [year]`

### Special Characters

- `*` -> every value
- `?` -> no specific value (used in Day-of-Month or Day-of-Week)
- `-` -> range (`1-5`)
- `,` -> list (`1,3,5`)
- `/` -> increments (`*/15` = every 15)
- `L` -> last (`L` in day-of-month = last day of month)
- `L-n` -> n days before the last day of the month
- `nL` -> last nth occurrence of a day (e.g. `6L` = last Friday)
- `LW` -> last weekday of the month
- `nW` -> nearest weekday to day n
- `W` -> nearest weekday
- `#` -> nth occurrence (`2#3` = third Monday)

**Note**: Month and day names are supported: `JAN`, `FEB`, `MON`, `TUE`, etc.

### Common Examples

| Expression               | Meaning |
|--------------------------|---------|
| `0 0 9 * * MON-FRI *`    | Every weekday at 9:00 AM |
| `0 */15 * * * ? *`       | Every 15 minutes |
| `0 0 0 L * ? *`          | Last day of every month |
| `0 0 0 ? * MON#1 *`      | First Monday of every month |
| `0 0 2 ? * MON-FRI *`    | Weekdays at 2:00 AM |

## Begin and Expire Fields

- **Begin**: Date/time when this cron becomes active
- **Expire**: Date/time when this cron stops running

These are very useful for temporary campaigns, maintenance windows, or phased rollouts.

## Attaching a Calendar to a Cluster

1. Go to **Jobs & Clusters** tab.
2. Click the cluster you want to schedule -> **Edit**.
3. In the **Calendar** dropdown, select the calendar.

Once attached, the **Next Run** column will show live countdowns.

## Best Practices

- Use descriptive names for both calendars and individual crons.
- Attach calendars to **clusters**, not individual jobs.
- Set `Begin`/`Expire` for temporary or one-time schedules.
- Use Grok (via MCP) to generate complex cron expressions naturally.
- Always check the auto-generated English description to verify correctness.

## Pro Tip

If connected to Grok via MCP, you can simply ask:
- “Create a calendar called Daily Reports that runs every weekday at 9 AM”
- “Add a cron to the Backup calendar that runs every 4 hours”

Grok will create the calendar and proper Quartz expressions for you.
