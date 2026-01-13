# Ordo Video Tutorial Scripts

## Video #1: Ordo Quickstart – Your First Job in 5 Minutes

**Length:** ~5 minutes

**Script:**

[Opening - 0:00-0:20]  
(Show Ordo logo or landing page, upbeat background music fades in)

"Hi everyone! Welcome to Ordo — the hierarchical job scheduler that makes running scripts, ETL pipelines, and automated workflows simple and powerful.

Today, in just 5 minutes, I'm going to show you how to get started with Ordo: sign in, create your first cluster and job, run it, and view the log. Let's dive in!"

[Section 1: Sign In - 0:20-0:40]  
(Show browser opening to your Ordo URL)

"First, open Ordo in your browser. If you're new, you'll see the welcome screen with a 'Sign In / Free Trial' button. Click that to log in.

Once you're in, you'll land on the Jobs & Clusters tab — this is your main dashboard."

[Section 2: Explore the Interface - 0:40-1:10]  
(Pan over the UI slowly)

"Here's what you're looking at:
- The navbar at the top lets you switch between Account, Jobs & Clusters, Calendars, Servers, and Docs.
- On the left, you have your job hierarchy — clusters act like folders, and jobs are the actual scripts.
- Each row shows real-time status: state, server, last start time, duration, and more — all updating live.

Notice the ellipsis button on the right — that's your actions menu. We'll use it a lot."

[Section 3: Create a Cluster - 1:10-2:00]  
(Click ellipsis on root/ or demonstrate creating one)

"By default, you have a 'root/' cluster. Let's create our own.

Click the ellipsis next to root/, then choose 'Create Cluster'.  
Name it 'quickstart', add an optional description, and hit Create.

Great! Now we have a new cluster called quickstart/."

[Section 4: Add Your First Job - 2:00-3:30]  
(Click into quickstart cluster)

"Now let's add a job — the thing that actually runs.

Click the ellipsis on the quickstart cluster → 'Create Job'.

Fill in:
- Name: hello-world
- Script: echo "Hello from Ordo! My first job ran at $(date)"

(Type it slowly so viewers can follow)

That's it! Click Create.

You now have your first job: hello-world inside quickstart cluster."

[Section 5: Run the Job - 3:30-4:00]  
(Highlight the job row)

"Time to run it!

Click the ellipsis on hello-world → 'Run'.

Watch the state change from 'ready' to 'running'... and back to 'complete' in just a second.

The Last Start and Duration columns update live — awesome!"

[Section 6: View the Log - 4:00-4:40]  
(Click View Log)

"Now, let's see what happened.

Click 'View Log' on the job.

Here’s the output: 'Hello from Ordo! My first job ran at [timestamp]'

You can refresh to reload, or click 'View History' to see past runs (we’ll cover that in a future video)."

[Closing - 4:40-5:00]  
(Show full UI again, smile at camera)

"And that's it! In under 5 minutes, you created a cluster, added a job, ran it, and viewed the log.

Ordo makes automation simple, scalable, and visual.

Next time, we'll cover dependencies, calendars for scheduling, and real-world ETL examples.

If you found this helpful, like and subscribe — and drop a comment: what do you want to see next?

Thanks for watching — happy automating!"

## Video #2: Building Workflows with Dependencies

**Length:** ~7 minutes

**Script:**

[Opening - 0:00-0:25]  
(Show the quickstart cluster from video 1)

"Welcome back to Ordo! In the last video, we created and ran our first job. Today, we're leveling up: we'll build a real workflow with job dependencies — where one job only runs after another finishes successfully.

This is the core power of Ordo — turning simple scripts into reliable pipelines."

[Section 1: Why Dependencies Matter - 0:25-1:00]  
(Show a simple diagram or on-screen text: extract → transform → load)

"Imagine a typical ETL pipeline:
1. Extract data from an API or database
2. Transform/clean it
3. Load it into your warehouse

You don't want step 2 to start if step 1 fails — Ordo handles this automatically with dependencies."

[Section 2: Create a New Pipeline Cluster - 1:00-1:30]  
(Create a new cluster)

"Let's create a dedicated cluster for this.

Click the ellipsis on root/ → Create Cluster → name it 'etl-pipeline'.

Now we have etl-pipeline/ — this will hold our three jobs."

[Section 3: Add the Extract Job - 1:30-2:30]  
(Create first job)

"First job: extract.

Click ellipsis on etl-pipeline → Create Job.

- Name: extract-data
- Script:  
echo "Extracting data..."
# Simulate API call
curl -s https://api.example.com/data > /tmp/raw-data.json
echo "Extract complete"

Click Create.

This job will run first."

[Section 4: Add Transform Job with Dependency - 2:30-4:00]  
(Create second job, show dependency setup)

"Next: transform — but only after extract succeeds.

Create Job:
- Name: transform-data
- Script:  
echo "Transforming data..."
# Simulate processing
jq '.' /tmp/raw-data.json > /tmp/clean-data.json
echo "Transform complete"

Now the key part: dependencies.

In the job creation form, find the "Needs" field.

Type the path of the extract job: ../extract-data (or select it from autocomplete if available).

This means: "only run me if extract-data completes successfully".

Click Create.

Watch the Needs column — it now shows the dependency."

[Section 5: Add Load Job (Multiple Dependencies Demo) - 4:00-5:00]  
(Create third job)

"Final job: load.

Create Job:
- Name: load-data
- Script:  
echo "Loading data to warehouse..."
# Simulate load
cp /tmp/clean-data.json /data/warehouse/
echo "Load complete"

Needs: ../transform-data

Create it.

Now we have a full chain: extract → transform → load."

[Section 6: Run the Pipeline - 5:00-6:00]  
(Run the first job, watch cascade)

"Time to run!

Click Run on extract-data only.

Watch what happens:
- extract runs → completes
- transform automatically starts
- load starts after transform finishes

All three jobs run in perfect sequence — no manual triggering needed!"

[Section 7: What If Something Fails? - 6:00-6:40]  
(Simulate failure)

"Let's see error handling.

Edit extract-data script to: echo "Extract failed" && exit 1

Run it again.

Extract fails → transform and load never start.

Perfect — prevents bad data from propagating."

[Closing - 6:40-7:00]  
(Show successful pipeline again)

"And that's dependencies in Ordo! You just built a reliable, automated ETL pipeline.

Next video: Scheduling with calendars — run this daily at 2 AM automatically.

If this helped, like and subscribe! Comment below: what kind of workflow are you building?

Thanks for watching — see you next time!"

## Video #3: Scheduling Jobs with Calendars

**Length:** ~6 minutes

**Script:**

[Opening - 0:00-0:25]  
(Show the etl-pipeline cluster from video 2)

"Welcome back to Ordo! Last time, we built an ETL pipeline with dependencies that runs perfectly on demand.

Today, we’ll make it run automatically — every day, every week, or even on tricky schedules like 'the last Friday of the month'.

Ordo uses powerful cron syntax (the same as Quartz scheduler), so you can do almost anything."

[Section 1: Calendars Overview - 0:25-0:50]  
(Quick glance at Calendars tab)

"Calendars in Ordo are simple:  
Create one, add one or more cron rules, then attach it to a cluster.

When any rule matches, the whole cluster runs — automatically."

[Section 2: Create a Calendar - 0:50-1:40]  
(Go to Calendars tab → Create)

"Let’s create one for our ETL pipeline.

Go to Calendars → Create Calendar → name it `daily-etl`.

Ordo auto-detects your timezone — perfect.

Create it."

[Section 3: Add Everyday at 2 AM - 1:40-2:30]  
(Add first cron)

"First rule: run every day at 2 AM.

Add Cron → 0 2 * * *

That’s standard cron: minute 0, hour 2, every day/month/weekday.

Add it."

[Section 4: Pro Tip — Fancy Quartz Syntax - 2:30-3:40]  
(Add second cron, smile at camera)

"Here’s where Ordo gets fun: it supports extended Quartz cron — the same powerful syntax used in big enterprise schedulers.

Want to run only on weekdays? Easy: 0 2 * * 1-5

But let’s do something cool: every last Friday of the month — great for monthly reports.

Use: 0 2 ? * 6L

The L means 'last', 6 is Friday, and ? says “no specific day of month”.

Ordo handles all the special characters: L, W, #, etc.

Add that one too."

[Section 5: Attach to Cluster - 3:40-4:20]  
(Back to Jobs & Clusters)

"Now attach the calendar.

Go to Jobs & Clusters → find etl-pipeline → ellipsis → Attach Calendar → select `daily-etl`.

Done!

The Next Start column now shows the countdown to 2 AM tomorrow — or the next last Friday if that's sooner."

[Section 6: Verify & Test - 4:20-5:20]  
(Show Next Start updating)

"Watch the Next Start column — it counts down in real time.

When the time hits, Ordo automatically runs extract → transform → load — no babysitting.

Want to test now? Just click Run — it behaves exactly the same as scheduled."

[Section 7: Real-World Ideas - 5:20-6:00]  
(Quick examples on screen)

"Some ideas:
- Daily backups: 0 3 * * *
- Weekends only: 0 4 * * 6,0
- First business day of month: 0 9 1-7 * * (with Quartz magic)
- Hourly during work hours: 0 9-17 * * 1-5

Mix and match — if any rule matches, it runs."

[Closing - 6:00-6:30]  
(Show scheduled cluster with countdown)

"And that’s automatic scheduling in Ordo — simple for daily jobs, powerful enough for complex enterprise rules.

Next video: Advanced control — Hold, Ice, Complete, and Reset — when things go wrong or you need to pause.

If you’re already thinking about your first scheduled job, drop a comment below!

Thanks for watching — see you next time!"

## Video #4: Advanced Control – Hold, Ice, Complete & Reset

**Length:** ~7 minutes

**Script:**

[Opening - 0:00-0:30]  
(Show a failed job in the etl-pipeline)

"Welcome back to Ordo! We've built reliable pipelines with dependencies and scheduling.

But when things go wrong — and they will — you need powerful recovery tools.

Today: Hold, Ice, Complete, Reset, and the game-changer: on_fail — Ordo’s secret weapon for self-healing workflows."

[Section 1: The Problem - 0:30-1:00]  
(Show a failed job)

"Imagine your nightly ETL fails because the API is down.

Without recovery, you wake up to bad data or manual fixes.

Ordo gives you automated, programmable responses."

[Section 2: Hold & Release – Pause Future Runs - 1:00-2:00]  
(Demonstrate on a scheduled cluster)

"Hold pauses future runs.

Click ellipsis → Hold on a cluster or job.

- Scheduled runs are skipped.
- Running jobs finish normally.
- Great for planned maintenance.

Release resumes everything."

[Section 3: Ice & Melt – Skip This Run - 2:00-2:50]  
(Show icing a ready job)

"Ice skips just this run — without blocking dependents.

Use when a temporary issue occurs.

Click Ice → state becomes 'ice'.

- This scheduled execution is skipped.
- Future runs proceed.
- Melt to undo."

[Section 4: Complete – Force Success - 2:50-3:40]  
(Show completing a failed job)

"Complete forces a job or cluster to 'complete' state.

Use when:
- You fixed it manually
- Testing
- Recovery

Dependents trigger immediately.

Works on jobs and entire clusters."

[Section 5: Reset – Clean Slate (Cluster Only) - 3:40-4:20]  
(Show resetting a partially failed cluster)

"Reset — cluster only.

Wipes current run state:
- All jobs back to 'ready'
- History preserved
- Next run starts fresh

Perfect after fixing a systemic issue."

[Section 6: on_fail – The Real Power Move - 4:20-6:30]  
(This is the big one — slow down, emphasize)

"Now the best part: on_fail.

This isn't just 'send an email when it fails'.

When a job or cluster fails, Ordo can automatically run an entire other cluster.

That cluster can do anything Ordo can do.

Examples:

1. Alerting  
   Create `alerts` cluster:  
   - Job: send Slack message  
   - Job: send email  
   - Job: page on-call  

   Set on_fail: alerts

2. Self-Healing  
   `recovery` cluster:  
   - Restart service  
   - Clear cache  
   - Retry with backoff  

3. Fallback Data  
   If API extract fails → run `use-cached-data` cluster

4. Escalation  
   First failure → Slack  
   Second → page team  

You define the recovery logic — Ordo executes it automatically.

No more waking up to failed jobs."

[Section 7: Quick Demo - 6:30-7:20]  
(Show setting on_fail)

"Let's set it up.

Create `alert-slack` cluster with one job: curl webhook.

On your main cluster → edit → on_fail: `alert-slack`

Now any failure automatically notifies your team.

Powerful, right?"

[Closing - 7:20-7:50]  
(Show on_fail in action — simulated failure → alert cluster runs)

"With Hold, Ice, Complete, Reset, and especially on_fail — Ordo doesn't just run jobs...

It manages failures like a pro.

Your workflows become truly resilient.

Next: Real-world examples — ETL, monitoring, backups, and more.

If on_fail just blew your mind, comment below!

Thanks for watching — go build something unbreakable!"

## Video #5: Real-World Use Cases & Examples

**Length:** ~8 minutes

**Script:**

[Opening - 0:00-0:30]  
(Montage: quick clips from all previous videos)

"Welcome to the final video in our Ordo tutorial series!

We've covered the fundamentals: jobs, dependencies, scheduling, advanced controls, and the CLI.

Now it's time to see Ordo in action — real-world workflows you can build today.

Whether you're in data, ops, dev, or just automating your life — these examples will spark ideas."

[Section 1: Daily Data Pipeline (ETL) - 0:30-2:00]  
(Show etl-pipeline cluster)

"Most common: daily ETL.

Cluster: `data-pipeline`

Jobs:
1. `extract` — pull from API or database
2. `transform` — clean, enrich, aggregate
3. `load` — push to warehouse (BigQuery, Snowflake, Postgres)

Dependencies ensure order.

Calendar: every day at 3 AM.

on_fail: alert cluster → Slack + email.

Result: fresh, reliable data every morning — hands-free."

[Section 2: System Monitoring & Health Checks - 2:00-3:30]  
(Show monitoring cluster)

"Next: infrastructure monitoring.

Cluster: `health-checks`

Parallel jobs (no dependencies):
- `disk-space` — check free space
- `api-ping` — curl your endpoints
- `db-connection` — simple query
- `cert-check` — SSL expiry

Calendar: every 5 minutes.

on_fail: `alerts` cluster → PagerDuty page.

Now you have proactive monitoring — catch issues before users do."

[Section 3: Automated Backups - 3:30-4:40]  
(Show backup workflow)

"Classic ops task: database backups.

Cluster: `nightly-backup`

Jobs in sequence:
1. `dump` — pg_dump or mysqldump
2. `compress` — gzip
3. `upload` — to S3 or Backblaze
4. `verify` — checksum check
5. `cleanup` — delete >30 days old

Calendar: weekly Sunday 2 AM.

on_fail: immediate Slack alert.

Your data is safe — automatically."

[Section 4: Monthly Reporting & Batch Jobs - 4:40-5:50]  
(Show reporting cluster)

"Business favorite: monthly reports.

Cluster: `monthly-finance`

Jobs:
- Gather data from multiple sources (parallel)
- Generate PDF/Excel report
- Email to stakeholders

Use Quartz cron for "last business day of month":
0 18 L * MON-FRI

Or "first Monday":
0 9 ? * MON#1

Fully automated board-ready reports."

[Section 5: CI/CD & Deployment Orchestration - 5:50-7:00]  
(Show deploy cluster)

"DevOps love: deployment pipelines.

Cluster per environment: `deploy-staging`, `deploy-prod`

Jobs:
- Build Docker image
- Run tests
- Deploy to Kubernetes
- Smoke test
- Notify Slack

Trigger manually or via:
- GitHub Actions webhook
- CLI from your CI server

Safe rollouts with Hold/Release if issues found."

[Section 6: Personal Automation Bonus - 7:00-7:40]  
(Light-hearted example)

"Even for personal use:

Cluster: `daily-routine`
- `weather-report` → email forecast
- `news-summary` → top headlines
- `habit-tracker` → remind goals

Calendar: every morning.

Ordo isn't just for work — automate anything!"

[Closing - 7:40-8:20]  
(Show montage of all examples running)

"That's Ordo in the real world — from critical data pipelines to personal reminders.

Simple building blocks, infinite possibilities.

You now have everything to build reliable, scheduled, self-healing automation.

What will you build first?

Drop it in the comments — I can't wait to hear.

If this series helped you, please like, subscribe, and share.

Thanks for watching — now go make something awesome with Ordo!"

## Video #6: Mastering the CLI – Power User Guide

**Length:** ~7-8 minutes

**Script:**

[Opening - 0:00-0:30]  
(Terminal window open, Ordo CLI prompt visible)

"Welcome back to Ordo! We've built workflows in the web UI — clusters, dependencies, calendars, advanced controls.

But many of us live in the terminal.

Today, we're going full power user: the Ordo CLI.

It's fast, scriptable, and gives you everything the web UI does — plus more.

Let's see why you'll want to use it every day."

[Section 1: Why the CLI Rocks - 0:30-1:20]  
(Split screen: web UI vs CLI doing same action)

"The CLI is:
- Faster — no mouse clicks, just commands.
- Scriptable — put it in shell scripts, cron, CI/CD.
- Remote-friendly — SSH into your server and manage Ordo directly.
- Full-featured — every web action has a CLI equivalent.

You can do everything from the terminal — or mix web and CLI."

[Section 2: Basic Navigation - 1:20-2:20]  
(Terminal demo)

"First: navigation.

Start Ordo CLI:

ordo

You're at root/.

Commands:
- ls — list clusters/jobs
- cd jag — enter cluster
- pwd — current path
- cd .. — go up
- cd /root/quickstart — absolute path

Just like a filesystem — because Ordo is a hierarchy."

[Section 3: Creating & Managing - 2:20-4:00]  
(Rapid fire commands)

"Create stuff fast.

Cluster:
cluster create reports --desc "Monthly reports"

Job:
job create extract --script "curl api > data.json"

Add dependency:
job edit transform --needs ../extract

Calendar:
cal create nightly
cal cron add nightly "0 3 * * *"
cal attach nightly reports

All in seconds."

[Section 4: Running & Controlling - 4:00-5:30]  
(Show actions)

"Run anything:
job run extract
cluster run reports — runs whole tree

Advanced controls:
job hold extract / job release extract
job ice extract / job melt extract
job complete extract
cluster reset reports

Kill stuck jobs:
job kill j1

View logs:
job log j1 — latest
job log j1 42 — specific run

Pro tip: pipe to less
job log j1 | less"

[Section 5: Power Features - 5:30-6:50]  
(Show on_fail and sync)

"Two killer features:

on_fail — run another cluster on failure
cluster edit reports --on_fail alerts

Now any failure in reports automatically runs your alerts cluster.

sync — refresh state from servers
sync

Use after manual fixes or server restarts."

[Section 6: Scripting & Automation - 6:50-7:30]  
(Show a shell script)

"Put it in scripts:

#!/bin/bash
ordo << EOF
cd /root/etl
cluster run daily
EOF

Or one-liners in cron:
0 3 * * * ordo cluster run /root/backups

Trigger from GitHub Actions, Jenkins, anywhere."

[Closing - 7:30-8:00]  
(Terminal with ordo prompt, smile)

"The CLI turns Ordo from a great web tool into a true automation powerhouse.

Whether you're scripting, debugging at 2 AM, or just love the terminal — the CLI has you covered.

Next video: Real-world examples — ETL, monitoring, backups, and more.

Comment: are you a CLI or web UI person?

Thanks for watching — now go open a terminal and try it!"

## Video #7: Real-World Use Cases & Examples

**Length:** ~8 minutes

**Script:**

[Opening - 0:00-0:30]  
(Montage: quick clips from all previous videos)

"Welcome to the final video in our Ordo tutorial series!

We've covered the fundamentals: jobs, dependencies, scheduling, advanced controls, and the CLI.

Now it's time to see Ordo in action — real-world workflows you can build today.

Whether you're in data, ops, dev, or just automating your life — these examples will spark ideas."

[Section 1: Daily Data Pipeline (ETL) - 0:30-2:00]  
(Show etl-pipeline cluster)

"Most common: daily ETL.

Cluster: `data-pipeline`

Jobs:
1. `extract` — pull from API or database
2. `transform` — clean, enrich, aggregate
3. `load` — push to warehouse (BigQuery, Snowflake, Postgres)

Dependencies ensure order.

Calendar: every day at 3 AM.

on_fail: alert cluster → Slack + email.

Result: fresh, reliable data every morning — hands-free."

[Section 2: System Monitoring & Health Checks - 2:00-3:30]  
(Show monitoring cluster)

"Next: infrastructure monitoring.

Cluster: `health-checks`

Parallel jobs (no dependencies):
- `disk-space` — check free space
- `api-ping` — curl your endpoints
- `db-connection` — simple query
- `cert-check` — SSL expiry

Calendar: every 5 minutes.

on_fail: `alerts` cluster → PagerDuty page.

Now you have proactive monitoring — catch issues before users do."

[Section 3: Automated Backups - 3:30-4:40]  
(Show backup workflow)

"Classic ops task: database backups.

Cluster: `nightly-backup`

Jobs in sequence:
1. `dump` — pg_dump or mysqldump
2. `compress` — gzip
3. `upload` — to S3 or Backblaze
4. `verify` — checksum check
5. `cleanup` — delete >30 days old

Calendar: weekly Sunday 2 AM.

on_fail: immediate Slack alert.

Your data is safe — automatically."

[Section 4: Monthly Reporting & Batch Jobs - 4:40-5:50]  
(Show reporting cluster)

"Business favorite: monthly reports.

Cluster: `monthly-finance`

Jobs:
- Gather data from multiple sources (parallel)
- Generate PDF/Excel report
- Email to stakeholders

Use Quartz cron for "last business day of month":
0 18 L * MON-FRI

Or "first Monday":
0 9 ? * MON#1

Fully automated board-ready reports."

[Section 5: CI/CD & Deployment Orchestration - 5:50-7:00]  
(Show deploy cluster)

"DevOps love: deployment pipelines.

Cluster per environment: `deploy-staging`, `deploy-prod`

Jobs:
- Build Docker image
- Run tests
- Deploy to Kubernetes
- Smoke test
- Notify Slack

Trigger manually or via:
- GitHub Actions webhook
- CLI from your CI server

Safe rollouts with Hold/Release if issues found."

[Section 6: Personal Automation Bonus - 7:00-7:40]  
(Light-hearted example)

"Even for personal use:

Cluster: `daily-routine`
- `weather-report` → email forecast
- `news-summary` → top headlines
- `habit-tracker` → remind goals

Calendar: every morning.

Ordo isn't just for work — automate anything!"

[Closing - 7:40-8:20]  
(Show montage of all examples running)

"That's Ordo in the real world — from critical data pipelines to personal reminders.

Simple building blocks, infinite possibilities.

You now have everything to build reliable, scheduled, self-healing automation.

What will you build first?

Drop it in the comments — I can't wait to hear.

If this series helped you, please like, subscribe, and share.

Thanks for watching — now go make something awesome with Ordo!"

**End of Series**

You've got a complete 7-part professional tutorial series ready to record!

Let me know when you start filming — I'd love to hear how it goes. You've built something really special with Ordo. 🚀
