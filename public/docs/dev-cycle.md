# Development cycle: Ordo + GitHub connectors

This is a **pattern**, not a special Ordo feature. An agent with a **GitHub connector** and **Ordo MCP** can own almost every step after you describe a change: write tests and code, run them on a **dev** checkout, open a PR only when green, and after you merge, start a **separate** cluster that applies **master** (or your release branch).

Defaults below can be overridden in the prompt.

## Roles

| Who | Does |
|-----|------|
| You | Describe the change, review the PR, merge, say when to **apply** |
| Agent + GitHub | Feature branch, commits, **one PR when tests are green** |
| Agent + Ordo MCP | Start the **test** cluster on its own; start **apply** only when you ask |
| Ordo on a **dev** tree | Clone/checkout that branch, run the suite |
| Ordo on an **apply** tree | Pull master only (build/recreate only if that is the real deploy) |

The agent must **not** merge and must **not** start prod apply unless you ask.

`get_documentation` may not list this page until it is added to the server catalog. Use the in-app docs hash `#docs/dev-cycle` or this file under `public/docs/`.

## Default process

1. You describe the change.
2. Agent creates a feature branch. **Strict TDD as writing default:** tests that would fail without the change, plus the implementation, in the **same push**. (No extra cluster run whose only job is to prove red.)
3. Agent starts the **test** cluster on the **dev** checkout (reuse the cluster; set `BRANCH` and the test command). Not the apply cluster.
4. Bounded wait / poll (see below).
5. Red → agent may change **code and tests**. Fix code if the test still matches the request; change tests if the test is a bad spec. Never drop coverage of the requested behavior just to pass. **Max 3** failed suite runs, then stop with the log — no PR.
6. Green → **one** PR on that SHA. Link in chat.
7. You review and merge.
8. You: `merged, deploy …` (name the apply cluster).
9. Agent starts the **existing** apply cluster (master only).

Reuse clusters. Do not create a new test/apply tree every change.

## Two clusters, two checkouts

**Test** — feature branch, before a ready PR:

```
clone-if-missing → checkout $BRANCH → suite
```

**Apply** — after merge, default branch only:

```
clone-if-missing → pull master/main
```

Real app deploys may add build → recreate → verify. A dummy apply can be pull-only (useful for a public example repo).

Same droplet is fine if the trees differ (e.g. `/home/ordo/myapp-dev` vs `/home/ordo/myapp` or `/opt/ordo`). Never checkout a feature branch on the prod tree. Never point the saas compose file at a test run.

Public repos can clone over **HTTPS** with no deploy key. Private repos need a deploy key (or equivalent) on that host user.

## What the dev server needs

Ordo only runs what the **job user** already has. First-time setup is usually human.

| Need | Typical failure | Notes |
|------|-----------------|--------|
| `git` + `openssh-client` | `git: command not found` (127) | Install in a real sudo session |
| Passwordless sudo *or* a human for packages | `sudo: a password is required` | Never put a sudo password in a job |
| `~/.ssh/known_hosts` for GitHub | `Host key verification failed` | `ssh-keyscan -t ed25519,rsa github.com >> ~/.ssh/known_hosts` |
| Deploy key for **private** repos | `Permission denied (publickey)` | Read-only is enough to clone/pull. Print only the **public** key. |
| Checkout path ≠ prod tree | Mixed deploys | Separate directories |
| Suite that matches the box | `Can't locate Mojo::Base.pm` | No runtime → file/`git` checks, not `perl -c` on app modules. Python examples can use stdlib `unittest` |

Register the host as an Ordo **server** in the UI first (`add_server` is not an MCP tool).

## Apply on the same host as Docker

Jobs run over SSH as the host user, not inside the container you may replace.

- `docker compose restart` does **not** pick up a newly built image with the same tag. Use `up -d --force-recreate` for app services.
- The node **launcher already daemonizes** (`setsid`). You do not need `nohup` to survive SSH. Detaching compose is only so the job can **POST complete while the API container is still up**. Optional.
- Leave the reverse proxy up if it did not change.
- No calendar on prod apply.

## Polling (until server-side events exist)

MCP start is fire-and-forget. Chat agents should **not** tight-loop.

- Guess duration from the last log of that job, or from the command.
- First wait ≈ expected runtime × 1.2, minimum **5s**, cap **45s** for a chat agent.
- One `get_cluster_details`. Terminal state → `read_log`.
- Still running → one more wait (same cap) and one more poll, then **stop** and give the cluster id.
- Do not poll apply unless the user asked for logs. Long builds are “start and wait for the user.”

CLI agents may use a higher cap. Override in the prompt.

## Worked shapes (not the product)

Test-style cluster:

```
ensure-clone → checkout $BRANCH → unittest or smoke
```

SaaS-style apply (if you deploy an app that way):

```
pull → build → recreate app+worker → delayed verify
```

A public example of the same split (tests on one tree, pull-only apply on another) is [nextwhen](https://github.com/nathanielgraham/nextwhen).

Job bodies can stay inline. An agent can recreate scripts from this page; do not treat files in git as required.

## Security

- No GitHub or Ordo tokens in job scripts.
- `git pull --ff-only` unless you mean to discard host edits.
- Bind-mount data stays outside the image.
- No feature-branch checkout on the prod tree.

## See also

- [Connecting to AI](#docs/connecting-to-ai)
- [Jobs and clusters](#docs/jobs-and-clusters)
- [Self-hosted](#docs/self-hosted)
