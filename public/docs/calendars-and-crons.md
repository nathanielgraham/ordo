# Calendars & Cron

Calendars let you define reusable, recurring schedules using **Quartz-style cron expressions** and attach them to clusters so that entire workflows run automatically.

## What is a Calendar?

A **Calendar** is a collection of one or more cron schedules.  
You create a calendar, add one or more cron expressions to it, then **attach** the calendar to a cluster. Once attached, the entire cluster (and all jobs inside it) follows that schedule.

## Creating a Calendar

1. Go to the **Calendars** tab.
2. Click **+ Create Calendar**.
3. Fill in:
   - **Name** – descriptive name (e.g. `Daily Reports`, `US Holidays`)
   - **Timezone** – IANA timezone (e.g. `America/Chicago`). Defaults to browser timezone.
   - **Description** – optional notes
4. Click **Save**.

## Adding Cron Expressions

After creating a calendar:

1. Click the **⋯** menu on the calendar → **Add Cron** (or **View Crons**).
2. Fill in:
   - **Cron Expression** – the schedule itself
   - **Description** – human-readable label (strongly recommended)
   - **Begin** (optional) – when this cron becomes active
   - **Expire** (optional) – when this cron stops

## Cron Expression Format

Ordo uses a **7-field Quartz-style** format (seconds are required):

```
seconds  minutes  hours  day-of-month  month  day-of-week  [year]
```


You can also use classic 5-field cron; Ordo will expand it.

### Day-of-Week Numbering (Important)

Ordo follows the **standard Unix/cron convention**, **not** classic Quartz:

| Day       | Number |
|-----------|--------|
| Monday    | 1      |
| Tuesday   | 2      |
| Wednesday | 3      |
| Thursday  | 4      |
| Friday    | 5      |
| Saturday  | 6      |
| Sunday    | 7      |

This is the opposite of classic Quartz (where Sunday = 1).  
When in doubt, prefer day **names** (`MON`, `TUE`, `WED`...) - Ordo accepts them and will normalize correctly.

### Special Characters

| Character | Meaning |
|-----------|---------|
| `*`       | every value |
| `?`       | no specific value (required in either day-of-month **or** day-of-week) |
| `-`       | range (`1-5`) |
| `,`       | list (`1,3,5`) |
| `/`       | increments (`*/15` = every 15) |
| `L`       | last (day-of-month = last day of month) |
| `nL`      | last *n*th weekday of the month (`1L` = last Monday; prefer `1L` over `MONL`) |
| `LW`      | last weekday of the month |
| `nW`      | nearest weekday to day *n* |
| `#`       | *n*th occurrence of a weekday (`1#3` = 3rd Monday) |

Month and day names are supported: `JAN`, `FEB`, `MON`, `TUE`, etc.

### Common Examples (correct for Ordo)

| Expression              | Meaning                                      |
|-------------------------|----------------------------------------------|
| `0 0 9 ? * 1-5 *`       | Every weekday at 09:00                       |
| `0 0 9 ? * MON-FRI *`   | Same as above (preferred form)               |
| `0 */15 * * * ? *`      | Every 15 minutes                             |
| `0 0 0 L * ? *`         | Last day of every month at midnight          |
| `0 0 0 ? * 1#1 *`       | First Monday of every month                  |
| `0 0 0 ? * MON#1 *`     | Same as above (preferred)                    |
| `0 0 0 ? 5 1L *`        | Last Monday in May (Memorial Day)            |
| `0 0 0 ? 11 4#4 *`      | 4th Thursday in November (Thanksgiving)      |
| `0 0 0 1 1 ? *`         | New Year’s Day (Jan 1)                       |
| `0 0 0 25 12 ? *`       | Christmas Day                                |
| `0 0 2 ? * MON-FRI *`   | Weekdays at 02:00                            |

> **Tip**: After you create a cron, always check the auto-generated English description. It is the fastest way to confirm the expression was interpreted the way you intended.

## Begin and Expire Fields

- **Begin** – date/time when this particular cron becomes active  
- **Expire** – date/time when it stops running  

Useful for temporary campaigns, maintenance windows, or phased rollouts.

## Attaching a Calendar to a Cluster

1. Go to the **Jobs & Clusters** tab.
2. Edit the cluster you want to schedule.
3. In the **Calendar** dropdown, select the calendar.

Once attached, the **Next Run** column shows live countdowns.

## Best Practices

- Give both calendars and individual crons clear, descriptive names.
- Attach calendars to **clusters**, not individual jobs.
- Prefer day **names** (`MON`, `THU`, ...) over numbers when writing expressions.
- Use `Begin` / `Expire` for temporary schedules.
- Always verify the English description after creating a cron.
- For complex schedules (holidays, “third Monday”, etc.) let Grok generate the expression via MCP.

## Pro Tip (MCP / Grok)

If you are connected via MCP you can simply say:

- “Create a calendar called Daily Reports that runs every weekday at 9 AM America/Chicago”
- “Add the major US federal holidays at midnight to a calendar named US Holidays”
- “Add a cron to the Backup calendar that runs every 4 hours”

Grok will create the calendar and the correct expressions for you.
