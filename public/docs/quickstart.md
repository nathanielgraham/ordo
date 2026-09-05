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
3. Enter **hostname**, **SSH user**, and **port** (usually 22).
4. **If password login is enabled**, you can enter the password once. Ordo installs its public key automatically, then uses key auth afterward.
5. **If password login is disabled**, install Ordo’s public key on the remote account first, then add the server without a password. See **[FAQ](#docs/faq)** for details.
6. Save.

Agents / API: the same action is **`create_monitor`** (not `create_server`). See [API](#docs/api) and [FAQ](#docs/faq).

## 3. Create a Cluster

1. Go to the **Jobs & Clusters** tab.
2. Open the **Actions** menu on the root cluster.
3. Select **New Cluster** and name it `Bork da Cake`.

## 4. Create the Jobs

Create these four jobs inside `Bork da Cake`. Use short names: `prep`, `mix`, `bake`, `finish`. Assign each job to the server you added.

**Job 1 – Name: `prep`**
```
#!/bin/sh
echo "Bork bork! Pre-heat da oven! Grease-a da pan! Yah!"
sleep 1
```

**Job 2 – Name: `mix`**
```
#!/bin/sh
echo "Meesh da dry ingredients! Creem da buttah! Egg-a inna bowl! Ploosh da milk! Goo goo!"
sleep 1
```

**Job 3 – Name: `bake`**
```
#!/bin/sh
echo "Pour-a da batter! Into da oven you go! Bakey bakey till da toothpick come-a clean!"
sleep 1
```

**Job 4 – Name: `finish`**
```
#!/bin/sh
echo "Let-a da cake rest! Cool-a onna rack! Now froosty and servy! Bork bork bork!"
sleep 1
```

Tip: use the **Insert Template** dropdown in the job modal for a quick shebang and starter script.

## 5. Set Dependencies

In each job modal, set **Needs** so steps run in order:

- `mix` needs `prep`
- `bake` needs `mix`
- `finish` needs `bake`

## 6. Run the Cluster

1. Open the actions menu on `Bork da Cake`.
2. Select **Run** (or **Start**).
3. Watch the Swedish Chef work! Jobs light up in order as dependencies complete.

## 7. View Logs

- Job -> Actions -> **View Log** for the latest output.
- **Log History** for past runs (timestamps, exit codes).

Logs are stored on the **job’s server** under `~/ordo_node/logs/`.

## 8. Schedule the Cake

1. Go to the **Calendars** tab.
2. Create a calendar named `Daily Baking`.
3. Add a cron, e.g. `0 0 9 * * ? *` (every day at 9:00 — see [Calendars & Crons](#docs/calendars-and-crons) for Quartz vs Unix). Confirm timezone on the calendar.
4. Edit `Bork da Cake` -> choose that calendar in the **Calendar** field -> save.

Now the Swedish Chef will bake a cake every morning at 9 AM!

**Congratulations!** You built, ran, and scheduled your first workflow.

### Next steps

- [Core Concepts](#docs/core-concepts) - clusters, dependencies, handlers  
- [Connecting to AI](#docs/connecting-to-ai) - optional MCP / Grok setup  
- [Advanced Topics](#docs/advanced-topics) - on_fail, on_overdue, max runtime, env vars  
