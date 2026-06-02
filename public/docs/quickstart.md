# Quickstart Guide

Let's get your first workflow running in minutes.

## 1. Create an Account

1. Go to the Ordo homepage.
2. Click **Sign Up**.
3. Enter your email and click **Send Magic Link**.
4. Check your email and click the link to log in.

## 2. Add a Server

1. Go to the **Servers** tab.
2. Click **+ Add Server**.
3. Enter hostname, SSH port (usually 22), and credentials.
4. Save.

**[Screenshot: Servers tab with a newly added server]**

## 3. Create a Cluster

1. Go to the **Jobs & Clusters** tab.
2. Click the **Actions** menu in the root cluster.
3. Select **New Cluster** and name it `Bork da Cake`.

## 4. Create the Jobs

1. Now create these four jobs inside `Bord da Cake` and give each job a short name (`prep`, `mix`, `bake`, `finish`)

**Job 1 – Name: `prep`**  
```bash
#!/bin/sh
echo "Bork bork! Pre-heat da oven! Grease-a da pan! Yah!"
sleep 1
```

**Job 2 – Name: `mix`**  
```bash
#!/bin/sh
echo "Meesh da dry ingredients! Creem da buttah! Egg-a inna bowl! Ploosh da milk! Goo goo!"
sleep 1
```

**Job 3 – Name: `bake`**  
```bash
#!/bin/sh
echo "Pour-a da batter! Into da oven you go! Bakey bakey till da toothpick come-a clean!"
sleep 1
```

**Job 4 – Name: `finish`**  
```bash
#!/bin/sh
echo "Let-a da cake rest! Cool-a onna rack! Now froosty and servy! Bork bork bork!"
sleep 1
```

## 5. Set Dependencies

In the job modal, set **Needs Jobs** so the steps run in order:
- `mix` needs `prep`
- `bake` needs `mix`
- `finish` needs `bake`

## 6. Run the Cluster

1. Select **Run** from the `Bork da Cake` cluster menu.
2. Watch the Swedish Chef work — jobs will light up in the correct order.

**[Screenshot: Running cluster with live execution]**

## 7. View Logs 

Right after running:
- Select **view log** on any job to see its output.
- Use **Log History** to view all past runs with timestamps and exit codes.

## 8. Schedule the Cake

1. Go to the **Calendars** tab.
2. Create a new calendar named `Daily Baking`.
3. Add cron: `0 9 * * *` (every day at 9:00 AM).
4. Go back to `Bork da Cake` → **Actions** → **Edit** → Attach calendar.

  Now the Chef will bake automatically every morning.

**Congratulations!** You just built, ran, and scheduled your first automated workflow.

### Next Step ###
[Core Concepts](#docs/core-concepts.md) — Learn the foundational ideas to help you use Ordo effectively.

