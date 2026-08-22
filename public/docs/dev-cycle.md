# Development cycle: Ordo + GitHub connectors

This is a **pattern**, not a special Ordo feature. An agent with a **GitHub connector** and **Ordo MCP** can own almost every step after you type a request: edit code, open a PR, and after you merge, start an Ordo cluster that pulls, builds, and restarts the app.

ordoscheduler.com uses this loop on the SaaS host. Copy the shape for any repo + any host Ordo already SSHes to.

## Roles

| Who | Does |
|-----|------|
| You | Describe the change, review the PR, merge, say when to deploy |
| Agent + GitHub | Branch, commit, pull request |
| Agent + Ordo MCP | Create or start the deploy cluster |
| Ordo on the **host** | `git pull`, image build, container recreate, verify |

The agent must **not** merge to the deploy branch and must **not** start deploy unless you ask. Merge is the quality gate.

## Why jobs run on the host

Ordo starts jobs over SSH on a registered server. If that server is the same machine that runs Docker for the app:

- Scripts run as the host user (`ordo` in the SaaS example), not inside the container you are about to replace.
- `docker compose restart` does **not** pick up a newly built image with the same tag. Use `up -d --force-recreate` for the app services.
- Recreate kills the app container (and the SSH client that started the job). Detach recreate with `nohup` + a short sleep so the job can exit 0 before the bounce.
- Leave the reverse proxy up if it did not change.

## Example cluster

Manual start only — no calendar.

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

## Chat loop

1. Agent opens a PR (GitHub connector).
2. You review and merge.
3. You: `merged, deploy saas` (or your cluster name).
4. Agent starts that cluster via `manage_cluster` / `start` and stops (fire-and-forget).
5. You watch the UI, or ask the agent to `read_log` when it finishes.

Same pattern for tests, docs publishes, schema applies, or “restart minion only” — different cluster, same split: GitHub for git, Ordo for the host.

## Security

- Deploy key or `gh` auth on the **host**. Do not put GitHub or Ordo tokens in job scripts.
- Register the host as an Ordo server in the UI (`add_server` is not available over MCP).
- `git pull --ff-only` — no hard reset unless you intend to discard host edits.
- Bind-mount data (`db`, `config`, `.env`, host SSH keys) stays outside the image.

## See also

- [Connecting to AI](#docs/connecting-to-ai) — MCP tools and fire-and-forget starts
- [Jobs and clusters](#docs/jobs-and-clusters)
- [Self-hosted](#docs/self-hosted)
