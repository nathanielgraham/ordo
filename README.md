# Ordo

Hierarchical job scheduler. Jobs, clusters, calendars, and recovery when something fails, misses its window, or runs too long.

Licensed under the [GNU AGPL v3](LICENSE).

## Self-hosted

```bash
git clone https://github.com/nathanielgraham/ordo.git
cd ordo
sudo docker compose up -d --build
sudo docker compose logs ordo | grep bootstrap
```

Open `http://localhost:3000/token-login` and paste the token from the logs.

`sudo` is there so this works before your user is in the `docker` group. To drop it later:

```bash
sudo usermod -aG docker $USER
```

Log out and back in, then `groups` should include `docker`.

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

