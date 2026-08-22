# Development cycle: Ordo + GitHub connectors

This is a **pattern**, not a special Ordo feature. An agent with a **GitHub connector** and **Ordo MCP** can own almost every step after you type a request: edit code, run checks on a **dev** server, open a PR, and after you merge, start a **separate** cluster that deploys **master** to production.

Do **not** point feature-branch jobs at production. Develop and smoke-test on a dedicated dev/test host. Production deploy pulls `master` (or your release branch) only, after you merge.

## Roles

| Who | Does |
|-----|------|
| You | Describe the change, review the PR, merge, say when to deploy |
| Agent + GitHub | Branch, commit, pull request |
| Agent + Ordo MCP | Start the **test** cluster and, after merge, the **apply** cluster |
| Ordo on a **dev** host | Clone/checkout the feature branch, smoke |
| Ordo on the **prod** host | `git pull` master, image build, container recreate, verify |

The agent must **not** merge and must **not** start prod deploy unless you ask. Merge is the quality gate.

## Two clusters

**Test (dev server)** — before or instead of opening a ready PR:

```
clone-if-missing → checkout $BRANCH → smoke
```

**Apply (prod host)** — after merge, master only:

```
pull → build → detached recreate → delayed verify
```

Same tools; different server, checkout, and risk. A 512 MB droplet can run the test half (git + file checks). It is a poor place to `docker compose build` the full app.

## What the dev server needs

Ordo can only run what is already on the host as the job user. First-time setup is usually **human** (or a one-shot job you trust). Typical gaps:

| Need | Why jobs fail without it | Notes |
|------|--------------------------|--------|
| `git` and `openssh-client` | `git: command not found` (exit 127) | Install with apt/yum as someone with a real sudo session |
| Passwordless sudo *or* a human for packages | `sudo: a password is required` | Do **not** put a sudo password in a job |
| `~/.ssh/known_hosts` for `github.com` | `Host key verification failed` | `ssh-keyscan -t ed25519,rsa github.com >> ~/.ssh/known_hosts` |
| Deploy key (or equivalent) as that user | `Permission denied (publickey)` | Read-only deploy key is enough to clone/pull. Generate the key on the box; add the **public** key in GitHub → repo → Deploy keys. Never log the private key. |
| A checkout path that is not prod | Mixing trees | e.g. `/home/ordo/ordo-dev` on the test box vs `/opt/ordo` on prod |
| Smoke that matches the box | `Can't locate Mojo::Base.pm` | If the host has no app runtime, smoke is `git` identity + file checks — not `perl -c` on application modules |

Register the host as an Ordo **server** in the UI before the agent can target it.

## Why apply jobs run on the prod host

Ordo starts jobs over SSH on a registered server. If that server is the same machine that runs Docker for the app:

- Scripts run as the host user, not inside the container you are about to replace.
- `docker compose restart` does **not** pick up a newly built image with the same tag. Use `up -d --force-recreate` for the app services.
- Recreate kills the app container (and the SSH client that started the job). Detach recreate with `nohup` + a short sleep so the job can exit 0 before the bounce.
- Leave the reverse proxy up if it did not change.

## Example: apply cluster

Manual start only — no calendar on prod deploy.

```
/root/ops/deploy-saas
  pull      →  git pull --ff-only in the repo checkout
  build     →  needs pull; docker compose build
  recreate  →  needs build; nohup compose up --force-recreate app + worker
  verify    →  needs recreate; delay ~20s; log + containers Up
```

Scripts for the SaaS example live in [`deploy/saas/jobs/`](https://github.com/nathanielgraham/ordo/tree/master/deploy/saas/jobs). Point each job at the matching file after the first deploy that adds them:

```sh
#!/bin/bash
exec /opt/ordo/deploy/saas/jobs/pull.sh
```

Keep **pull** runnable even if the new files are not on disk yet (inline script, or the exec form only after they exist).

## Example: test cluster

```
/root/ops/test-feature   (dev server)
  ensure-clone →  git clone if `$DEV_DIR/.git` is missing
  checkout     →  fetch + checkout `$BRANCH` (agent updates BRANCH, default master)
  smoke        →  HEAD + required files; no heavy runtime unless the box has it
```

Use a **separate working tree** from production. Do not checkout feature branches on the prod host.

## Chat loop

1. Agent commits on a **feature branch** (GitHub).
2. Agent (or you) sets `$BRANCH` on the test checkout job and starts the **test** cluster.
3. If smoke is green, agent opens or marks-ready the PR. If red, no ready PR; read the log.
4. You review and merge.
5. You: `merged, deploy saas` (or your apply cluster name).
6. Agent starts the **apply** cluster and stops (fire-and-forget). For jobs that finish in a couple of seconds, the agent may `read_log` immediately.

## Security

- Deploy key or `gh` auth on each **host**. Do not put GitHub or Ordo tokens in job scripts.
- Register hosts in the UI (`add_server` is not available over MCP).
- `git pull --ff-only` — no hard reset unless you intend to discard host edits.
- Bind-mount data (`db`, `config`, `.env`, host SSH keys) stays outside the image.
- No calendar on prod apply. No feature-branch checkout on prod.

## See also

- [Connecting to AI](#docs/connecting-to-ai) — MCP tools and fire-and-forget starts
- [Jobs and clusters](#docs/jobs-and-clusters)
- [Self-hosted](#docs/self-hosted)
