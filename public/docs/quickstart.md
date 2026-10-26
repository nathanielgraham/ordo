# Quickstart

## Self-hosted

1. Clone and start:

```
git clone https://github.com/nathanielgraham/ordo.git
cd ordo
sudo docker compose up -d --build
```

2. Get the admin token:

```
sudo docker compose logs ordo | grep bootstrap
```

3. Open `http://localhost:3000/token-login` and paste the token.

4. Add this machine as a server (below), then build the cake.

See [Self-Hosted](self-hosted.md) for permissions, users, and reset.

## SaaS

1. Open the app and click **Sign Up**.
2. Enter your email and send the magic link.
3. Click the link. You are logged in.

## Build a workflow

### 1. Add this machine as a server

Ordo runs in Docker, so do not use `localhost` as the SSH host. That is the container. Use the host's LAN address.

On the host:

```
sudo systemctl enable --now ssh
hostname -I
sudo docker compose exec ordo cat /home/ordo/.ssh/id_ed25519.pub
```

Put the public key in your account's `~/.ssh/authorized_keys`:

```
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'PASTE_THE_PUBKEY' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

In Ordo: **Servers** → add a server.

- Host: the address from `hostname -I` (for example `192.168.1.20`)
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
