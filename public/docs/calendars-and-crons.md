# Calendars & Cron

Calendars allow you to define reusable, recurring schedules using Quartz cron expressions (including full 7-field support and special tokens like L, W, #, etc.). 
Each calendar can contain multiple cron entries, supports custom timezones, and can be attached to clusters so that all jobs inside them automatically follow the defined schedule. You can also set optional Begin and Expire dates to control exactly when a schedule becomes active or stops

## Using Grok to Create Calendars

**One of the easiest ways to create calendars and cron schedules is to simply ask Grok.**

If you are connected to Grok via MCP, you can say things like:

- “Create a calendar called US Holidays that runs at midnight on every major US holiday.”
- “Create a calendar called Daily Reports that runs every weekday at 9 AM”
- “Add a cron to the Backup calendar that runs every 4 hours starting next Monday”
- “Create a calendar for month-end reports that runs on the last day of every month at 2 AM”

Grok can generate proper Quartz cron expressions for you, suggest good `Begin`/`Expire` dates, and even explain what it created.

**This is often the recommended way** for users who don’t want to memorize cron syntax.

## 1. Important Concepts

- One **Calendar** can contain many **Crons**.
- You attach a **Calendar** (not individual crons) to a **Cluster**.
- The **Next Run** column only appears for calendars that are attached to at least one cluster.
- Timezones are per-calendar — make sure you select the correct one.
- Standard 5-field unix cron expressions are automatically converted to Quartz.

## 2. Creating a Calendar and Adding Cron Expressions

### Step-by-step:

1. Go to the **Calendars** tab.
2. Click **+ Create Calendar**.
3. Fill in:
   - **Name** — A descriptive name (e.g., "Daily Reports")
   - **Timezone** — Usually your local timezone (defaults to browser timezone)
   - **Description** — Optional notes
4. Click **Save**.

### Adding Cron Expressions

After creating a calendar:

1. Click the **Actions** menu (⋯) on the calendar row.
2. Select **Add Cron**.
3. Fill in:
   - **Cron Expression** — e.g., `*/15 * * * * ? *`
   - **Description** — "Run every 15 minutes" (optional)
   - **Begin** (optional) — When the schedule should start
   - **Expire** (optional) — When the schedule should stop
4. Click **Save**.

## 3. Supported Cron Formats

Ordo supports **two** cron formats:

- **Quartz 7-field cron** (default, most powerful)
- **Standard 5-field cron** (for easy import of existing crontabs)

### Quartz Cron (7 fields)

`seconds minutes hours day-of-month month day-of-week year`

### Standard 5-field Cron

`minutes hours day-of-month month day-of-week`

When using 5-field cron, Ordo assumes `seconds = 0` and `year = *`.

## 4. Quartz Cron Expression Reference

### Special Characters

- `*` → every value
- `?` → no specific value (used in Day-of-Month or Day-of-Week)
- `-` → range (`1-5`)
- `,` → list (`1,3,5`)
- `/` → increments (`*/15` = every 15)
- `L` → last (`L` in day-of-month = last day of month)
- `L-n` → n to last day of the month
- `nL` → last n-day of the month
- `LW` → last weekday of month
- `nW` → nearest weekday to n
- `W` → nearest weekday
- `#` → nth occurrence (`2#3` = third Monday)

**Note**: Month and Day names are supported: `JAN`, `FEB`, ..., `MON`, `TUE`, `WED`, `THU`, `FRI`, `SAT`, `SUN`.

### Common Examples

| Expression                        | Meaning |
|----------------------------------|--------|
| `0 0 9 * * MON-FRI *`            | Every weekday at 9:00 AM |
| `0 */15 * * * ? *`               | Every 15 minutes |
| `0 0 0 1 * ? *`                  | First day of every month |
| `0 0 0 ? * MON#1 *`              | First Monday of every month |
| `0 0 0 L * ? *`                  | Last day of every month |
| `0 0 0 ? * 6L *`                 | Last Friday of every month |

## 5. Begin and Expire Fields

These two fields give you precise control over when a cron becomes active and when it stops.

- **Begin** — The date/time when this cron schedule should **start** being evaluated.
- **Expire** — The date/time when this cron schedule should **stop** being evaluated.

**Use cases:**
- Schedule a report to begin running every day starting next Monday (`Begin`).
- Run a promotion campaign only during December (`Expire`).
- Create temporary maintenance jobs that automatically disable themselves after a certain date.

If `Begin` is not set → the cron starts immediately.  
If `Expire` is not set → the cron runs indefinitely.

---

### Best Practices
- Use descriptive names for both calendars and crons.
- Set `Begin` and `Expire` when the schedule is temporary.
- To verify your expression is correct, check the english description in the calendar table.
- Group related schedules into the same calendar.
