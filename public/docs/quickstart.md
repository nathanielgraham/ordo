# Quickstart

## Self-hosted

1. Clone and install:

```
git clone https://github.com/nathanielgraham/ordo.git
cd ordo
./install.sh
```

Run it as your user, not with `sudo`. Any account with `sudo` or already in the `docker` group is fine. If you are not in `docker`, the script adds you and continues.

2. Open `http://localhost:3000/token-login` and paste the admin token it printed.

3. Enable SSH (`sudo systemctl enable --now ssh`), add this machine as a server using the LAN address it printed, then build the cake.

See [Self-Hosted](self-hosted.md) for permissions, users, and reset.

## Build a workflow

### 1. Add this machine as a server

`./install.sh` already put Ordo's public key in your `~/.ssh/authorized_keys`. SSH must be running (`sudo systemctl enable --now ssh`).

Do not use `localhost` as the host. That is the container. Use the LAN address `install.sh` printed.

In Ordo: **Servers** → add a server.

- Host: that LAN address (for example `192.168.1.20`)
- User: your account on this machine
- Port: 22
- No password

`api_url` can stay `http://127.0.0.1:3000/api`. The job runs on the host, which can reach the published port.

### 2. Create a cluster

**Jobs & Clusters** → Actions on root → **New Cluster** → name it `Bork da Cake`.

### 3. Create the jobs

Inside that cluster, add `prep`, `mix`, `bake`, `finish`. Point each at the server you added.

**prep**
```
#!/bin/sh
echo "Bork bork! Pre-heat da oven! Grease-a da pan! Yah!"
sleep 1
```

**mix**
```
#!/bin/sh
echo "Meesh da dry ingredients! Creem da buttah! Egg-a inna bowl! Ploosh da milk! Goo goo!"
sleep 1
```

**bake**
```
#!/bin/sh
echo "Pour-a da batter! Into da oven you go! Bakey bakey till da toothpick come-a clean!"
sleep 1
```

**finish**
```
#!/bin/sh
echo "Let-a da cake rest! Cool-a onna rack! Now froosty and servy! Bork bork bork!"
sleep 1
```

### 4. Dependencies

- `mix` needs `prep`
- `bake` needs `mix`
- `finish` needs `bake`

### 5. Run

Actions on `Bork da Cake` → **Run**. Jobs run in order.

### 6. Logs

Job → Actions → **View Log**. History is under **Log History**. Logs live on the job’s server in `~/ordo_node/logs/`.

### 7. Schedule

**Calendars** → create `Daily Baking` → add a cron such as `0 0 9 * * ? *` → attach it to the cluster.

### Next

- [Core Concepts](core-concepts.md)
- [Self-Hosted](self-hosted.md)
- [Connecting to AI](connecting-to-ai.md)
