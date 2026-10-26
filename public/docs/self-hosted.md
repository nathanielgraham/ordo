# Self-Hosted Setup

Run Ordo on your own machine with Docker. No license key and no SMTP required.

## Prerequisites

- Linux (Debian/Ubuntu is the common case)
- Docker and Docker Compose
- About 2 GB of RAM

## 1. Install

```
git clone https://github.com/nathanielgraham/ordo.git
cd ordo
./install.sh
```

Run it as your user, not with `sudo`. You need `sudo` once, or to already be in the `docker` group. If you are not, it adds you and continues.

The script starts the stack, installs Ordo's SSH public key in your `~/.ssh/authorized_keys`, and prints the admin token and the LAN address to add as a server.

## 3. First admin

On a fresh database the entrypoint creates an admin (level 3) and prints the API token:

```
sudo docker compose logs ordo | grep bootstrap
```

```
[bootstrap] Created admin admin@localhost
[bootstrap] API token: <40-char token>
[bootstrap] Paste this token at /token-login
```

Optional overrides:

- `ORDO_ADMIN_EMAIL`
- `ORDO_ADMIN_TOKEN`

## 4. Log in

Open:

```
http://localhost:3000/token-login
```

Paste the token from the logs. You land in the app. There is no public signup.

Without a valid token, self-hosted redirects to `/token-login`. Docs and the rest of the app are available after login.

## 5. Add users

Settings → Members (admins only):

- **Name** and **email**
- Leave **New org** unchecked to share your job tree
- Check it to give them their own org and tree

You get:

- An **API token** to paste at `/token-login`
- A **one-time link** (`/confirm?jwt=...`, 7 days)

Hand either to the new user. No email is sent.

## 6. Email (optional)

SMTP is not required. Set it only if you want magic-link mail or notifications.

In `config/ordo.json`:

```
{
  "deploy_mode": "selfhosted",
  "public_url": "http://localhost:3000",
  "smtp_user": "you@example.com",
  "smtp_pass": "app-password"
}
```

`public_url` must match how users reach the app, or confirm links point at the wrong host.

## Reachable address

`localhost` only works in the browser on the machine running Ordo. Jobs on other servers call `api_url`. They cannot reach `http://localhost:3000`.

Find this machine’s LAN address:

```
hostname -I
```

Set both URLs in `config/ordo.json` to that address (or a hostname the servers can resolve):

```
{
  "public_url": "http://192.168.1.20:3000",
  "api_url": "http://192.168.1.20:3000/api"
}
```

Restart:

```
docker compose restart
```

From another machine, `curl http://192.168.1.20:3000/` should answer. If it does not, open port 3000 on the host firewall.

`localhost` is fine only when every job runs on the same box as Ordo.

Restart:

```
docker compose restart
```


## Use this machine as a server

You can run jobs on the same box that runs Ordo. `./install.sh` already installed the public key for your user. SSH must be running (`sudo systemctl enable --now ssh`).

Do not add it as `localhost`. From inside the container that is the container itself. Use the LAN address the script printed.

In **Servers**, add that address, your username, and port 22. No password.

`api_url` may stay `http://127.0.0.1:3000/api` while jobs run on this host. Other machines need a reachable address. See [Reachable address](#reachable-address).

## 7. Services

| Service | Purpose        |
|---------|----------------|
| `ordo`  | Web app        |
| `minion`| Background jobs|

## 8. Reset

```
docker compose down
rm -f db/ordo.db db/ordo.db-wal db/ordo.db-shm
docker compose up -d
```

Bootstrap creates a new admin and prints a new token.

## Locked out

If the admin user is gone, restart. Bootstrap creates one if no level > 0 user exists and prints the token.

## Production with Caddy

For a hostname and HTTPS, put Caddy in front of Ordo. Remote jobs and confirm links then use `https://ordo.example.com` instead of an IP and port.

Point DNS at this machine, then a Caddyfile:

```
ordo.example.com {
	reverse_proxy localhost:3000
}
```

Run Caddy on the host (or another container) so it can reach port 3000. Open 80 and 443. Caddy gets the certificate.

In `config/ordo.json`:

```
{
  "public_url": "https://ordo.example.com",
  "api_url": "https://ordo.example.com/api"
}
```

Restart Ordo. Browsers and remote servers both use that URL. Do not put `localhost` in `api_url` once jobs run on other machines.
