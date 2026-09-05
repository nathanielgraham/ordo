# Self-Hosted Setup Guide

This guide walks you through installing and running Ordo on your own infrastructure using Docker.

## Package Contents

The distribution contains:

- `ordo-image.tar` — Pre-built Docker image
- `docker-compose.yml` — Service definition
- `install.sh` — One-command installer
- `README.md` — Quick reference

## 1. Prerequisites

- Debian or Ubuntu server (other Linux distributions also work)
- At least 2 GB of RAM recommended
- Docker + Docker Compose
- A valid Ordo license key

## 2. Unpack the Package

```
tar -xzf ordo-selfhosted-v1.tar.gz
cd ordo-selfhosted
```

## 3. Install Docker (if needed)

```
sudo apt update
sudo apt install docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

Log out and log back in so the group change takes effect.

## 4. Install Ordo

The easiest way:

```
./install.sh
```

The installer will:

1. Load the Docker image (if `ordo-image.tar` is present)
2. Ask for your license key
3. Create a `.env` file
4. Create required directories (`config/`, `db/`, `data/`)
5. Start the services

### Manual Install

If you prefer to do it step by step:

```
# Load the image
docker load -i ordo-image.tar

# Create license file
echo "ORDO_LICENSE_KEY=your-license-key-here" > .env

# Create directories
mkdir -p config db data

# Start
docker compose up -d
```

## 5. Access the Application

Open your browser to:

```
http://localhost:3000
```

Or, if running on a remote server:

```
http://YOUR_SERVER_IP:3000
```

## 6. Email Configuration

Ordo needs email for user invitations, password resets, and notifications.

### Recommended: External SMTP

Create or edit `config/ordo.json`:

```
{
  "deploy_mode": "selfhosted",
  "smtp_user": "your-email@gmail.com",
  "smtp_pass": "your-app-password"
}
```

Then restart:

```
docker compose restart
```

### Alternative: Local Postfix

If you prefer a local mail server:

```
docker exec -it ordo-ordo-1 bash
dpkg-reconfigure postfix
```

Choose “Internet Site” and enter your domain, then exit the container.

### Notes

- Gmail requires an [App Password](https://support.google.com/accounts/answer/185833)
- Most other providers (SendGrid, Mailgun, SES, etc.) also work with `smtp_user` / `smtp_pass`
- The Minion worker must be running for email to be delivered

## 7. Services

| Service  | Purpose                              |
|----------|--------------------------------------|
| `ordo`   | Web application                      |
| `minion` | Background job worker (required)     |

The Minion worker is required for email delivery and other asynchronous tasks.

## 8. Adding Servers

When adding servers in the UI:

- Use the host’s real IP address, or
- Use `host.docker.internal` (works on most Docker setups)

SSH key authentication is strongly recommended.


## Docker bind-mount UIDs

The container runs as **uid/gid 1000**. Host bind mounts for `config/`, `db/`, `data/`, and `ssh/` must be owned by that user, or the stack can fail (readonly SQLite, SSH key write errors). After creating the directories:

```bash
mkdir -p config db data ssh
chown -R 1000:1000 config db data ssh
```

See `deploy/saas/README.md` in the Ordo repo for the same requirement on SaaS compose.

## Troubleshooting

| Task                    | Command                              |
|-------------------------|--------------------------------------|
| View all logs           | `docker compose logs -f`             |
| View only app logs      | `docker compose logs -f ordo`        |
| View only worker logs   | `docker compose logs -f minion`      |
| Restart everything      | `docker compose restart`             |
| Stop everything         | `docker compose down`                |
| Enter main container    | `docker exec -it ordo-ordo-1 bash`   |

## Updating

1. Download the new package
2. Load the new image:
   ```
   docker load -i ordo-image.tar
   ```
3. Restart:
   ```
   docker compose up -d
   ```

## License

Self-hosted Ordo requires a valid license key.  
The key is stored in the `.env` file as `ORDO_LICENSE_KEY`.

Without a valid key the application will not start.

## Support

For questions or issues with self-hosted deployments, email us at `ordosched@proton.me`.
