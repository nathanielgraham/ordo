# How agents use GitHub and Ordo together

Ordo does not replace GitHub. GitHub is the source of truth for code, branches, pull requests, and review. Ordo runs tests and (only when you ask) apply on machines you already have.

A fresh agent should call `get_documentation` with section `dev-cycle` (or `connecting-to-ai`) at the start of a session that will write code.

You can change any of these defaults in the chat.

## In plain terms

You describe a feature (include the GitHub repo and which test server to use). The agent writes tests and code on a **side branch**. Ordo runs those tests on a **practice checkout**. If tests fail, the agent may repair at most three times. If they still fail, it stops and shows the log — it does **not** open a PR of broken work.

When tests pass, the agent opens **one** pull request. You review and merge. Then you say something like `merged, deploy`. Only then does the agent start the existing **apply** cluster so the live checkout pulls **main** / **master**.

The agent does not merge for you. It does not update production unless you ask.

## Who does what

| You | The agent | Ordo |
|-----|-----------|------|
| Describe the change (repo + test server) | Writes tests and code on a branch | Runs the test jobs on the practice copy |
| Review and merge | Opens a review only after tests pass | After you say deploy, updates the live copy |
| Say when to deploy | Starts the reusable test cluster | Does not invent git history |

## Hosts (this org)

| Server | RAM | Use |
|--------|-----|-----|
| **panthero** | ~4 GB | Default for feature tests and anything heavier than a tiny script |
| **snarf** | ~512 MB | Light jobs only; may be underpowered for builds or fat test suites |

Hard rules:

- Never write, checkout, or run feature work under `/opt/ordo` (the Ordo product tree).
- Never treat the Ordo repo checkout as a scratch pad for other projects.
- Prefer **panthero** when in doubt.
- Keep two folders per app on the test host: a **practice** tree (feature branch) and a **live** tree (main only). Example: `/home/ordo/nextwhen-dev` and `/home/ordo/nextwhen`.

## Reuse clusters — do not invent a new graph per feature

Keep **one** reusable test cluster and **one** reusable apply cluster per product (same idea as `ops/deploy-saas`: pull → build → recreate → verify, wired with `needs_ids`).

Parameterize with environment or a tiny env file on the host, not by cloning the whole tree:

- `REPO` — `owner/name`
- `BRANCH` — feature branch for test; apply always uses main/master
- `DEV_DIR` — practice checkout
- `LIVE_DIR` — live checkout
- `TEST_CMD` — e.g. `python3 -m unittest discover -s tests -v`

Update the job script or a `~/ordo_node/env/<app>.env` file, then start the **same** cluster. Do not create `test-feature-foo`, `test-feature-bar` for every ticket.

## Default steps (agents)

1. Call `get_documentation` section `dev-cycle` if this is a new session.
2. `list_servers` and `list_jobs` so you know panthero/snarf ids and existing test/apply clusters.
3. Create a feature branch from the repo default branch.
4. In the same push: tests that would fail without the change, plus the implementation. No extra run whose only purpose is to prove the tests start red.
5. Point the **existing** test cluster at `BRANCH` + `TEST_CMD`. Start it on **panthero** unless the user named another host. Do not start apply.
6. Wait/poll with the budget below.
7. On failure: change code and/or tests. Prefer fixing code if the test still matches what the user asked. Change tests when the test is the wrong spec. Do not delete the meaning of the request just to pass. **At most three** failed test runs, then stop with the log and no pull request.
8. On success: **one** pull request at that commit. Paste the link.
9. Wait until the user merges and names the apply cluster (`merged, deploy …`).
10. Start that **existing** apply cluster so it pulls **main** / **master** only.

## Two copies of the code

**Practice (test)** — the feature branch, before a review:

clone if needed → fetch → check out the branch → run the tests

**Live (apply)** — after merge, main branch only:

clone if needed → pull main/master (`--ff-only`)

A real app deploy can also build images, restart containers, and check they came back. A simple apply can be pull-only (enough for a public demo repo).

Never check out a feature branch in the live folder. Never run production Docker Compose as a test.

## How the machine talks to GitHub

The **agent** uses the GitHub connector (in the chat) to open branches and reviews. That is separate from how **Ordo jobs** on the server run `git clone` / `git pull`.

- **Public repo:** HTTPS clone is enough. No key or token on the box.
- **Private repo (preferred):** an SSH **deploy key** for that one repo, installed as the job user. Read-only is enough to clone and pull.
- **Private repo (alternative):** a fine-grained token stored on the host — never in the job script, clone URL, or chat.

## What the practice machine needs

Ordo can only use tools already installed for the job user. First-time setup is usually a person, not the agent.

| If this is missing | What you will see | What to do |
|--------------------|-------------------|------------|
| `git` and `openssh-client` | `git: command not found` | Install in a normal admin session |
| Sudo without a password | `sudo: a password is required` | Do not put a sudo password in a job |
| GitHub in `~/.ssh/known_hosts` | `Host key verification failed` | `ssh-keyscan` once as the job user |
| Deploy key or host token, for a private repo | `Permission denied` or HTTPS 401 | Prefer a read-only deploy key |
| A folder that is not the live tree | Tests and live mixed together | Two directories |
| Tests the box can actually run | Missing libraries | If the box has no app runtime, check files and `git` only. Python demos can use stdlib `unittest` |

Add the machine as an Ordo **server** in the web UI first. That step is not an MCP tool.

## How long the agent should wait

Starting a cluster does not keep a live notification channel. Chat agents should not check status in a tight loop.

- Estimate how long the run should take from the last log or from the command.
- Wait a little longer than that (about 1.2×), at least 5 seconds, at most **45 seconds** in a chat.
- Check status once. If it finished, read the log.
- If it is still going, wait once more (same cap) and check once more, then **stop** and tell the user the cluster name/id.
- Do not keep checking a live deploy unless the user asked for the log.

## Example: nextwhen

[nextwhen](https://github.com/nathanielgraham/nextwhen) is a small public example: frozen-clock API, stdlib `unittest`, tests on one folder, pull-only apply on another.

A later rehearsal can use a sibling project (for example **openwhen**) with the **same** reusable test/apply clusters, parameterized by `REPO` / `BRANCH` / `DEV_DIR`.

Job scripts can live in the Ordo job text. They do not have to be files in git.

## Safety

- Do not put GitHub or Ordo tokens in job scripts or clone URLs.
- Pull with `--ff-only` unless you mean to throw away edits on the machine.
- Do not check out feature branches in the live folder.
- Do not touch `/opt/ordo`.
- Do not put a calendar on production apply — start it by hand (or by the agent after you ask).

## See also

- [Connecting to AI](#docs/connecting-to-ai)
- [Jobs and clusters](#docs/jobs-and-clusters)
- [Self-hosted](#docs/self-hosted)
