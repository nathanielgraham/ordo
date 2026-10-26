# Ordo

Hierarchical job scheduler. Jobs, clusters, calendars, and recovery when something fails, misses its window, or runs too long.

Licensed under the [GNU AGPL v3](LICENSE).

## Self-hosted

```bash
git clone https://github.com/nathanielgraham/ordo.git
cd ordo
docker compose up -d --build
docker compose logs ordo | grep bootstrap
```

Open `http://localhost:3000/token-login` and paste the token. You need to be in the `docker` group (or use `sudo`).

To run a job on this machine, enable SSH and install the container key:

```bash
sudo systemctl enable --now ssh
docker compose exec ordo cat /home/ordo/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
```

Add the LAN address from `hostname -I` as a server. Do not use `localhost`.

Full guide: [public/docs/self-hosted.md](public/docs/self-hosted.md).

## Add users

Settings → Members (admins only). You get an API token and a one-time `/confirm` link. No email required.

## Optional

- `ORDO_ADMIN_EMAIL` / `ORDO_ADMIN_TOKEN` — override the bootstrap admin
- SMTP in `config/ordo.json` — only if you want mail
- `public_url` in `config/ordo.json` — must match the URL users use, or confirm links are wrong

## Docs

After login: **Docs** in the app, or the files in `public/docs/`.

- [Quickstart](public/docs/quickstart.md)
- [Self-hosted](public/docs/self-hosted.md)
- [Core concepts](public/docs/core-concepts.md)

## Bugs

Report bugs and feature requests on [GitHub Issues](https://github.com/nathanielgraham/ordo/issues).

