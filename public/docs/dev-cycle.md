# How agents use GitHub and Ordo together

Ordo does not replace GitHub. GitHub keeps the history of a change. Ordo runs that change on a machine you already have.

If an agent can use both, it can help from the first description through tests, a review, and (only when you say so) updating the live copy. You can change any of these defaults in the chat.

This page is also at `#docs/dev-cycle`. It may not appear in the `get_documentation` list until that catalog is updated.

## In plain terms

You say what you want. The agent writes tests and code on a **side branch** (not the live branch). Ordo runs those tests on a **practice copy** of the project. If the tests fail, the agent may fix the code or the tests a few times. If they still fail, it stops and shows you the log — it does **not** ask you to merge broken work.

When the tests pass, the agent sends you **one** review (a pull request). You read it and merge if you like it. Then you say something like `merged, deploy`. Only then does the agent ask Ordo to update the **live copy** from the main branch.

The agent does not merge for you. It does not update production unless you ask.

## Who does what

| You | The agent | Ordo |
|-----|-----------|------|
| Describe the change | Writes tests and code on a branch | Runs the test jobs on the practice copy |
| Review and merge | Opens a review only after tests pass | After you say deploy, updates the live copy |
| Say when to deploy | Starts test runs on its own | Does not invent git history |

Keep one reusable **test** workflow and one reusable **apply** (live update) workflow. Do not spin up a new pair of folders for every small change.

## Default steps (agents)

1. Create a feature branch.
2. In the same push: tests that would fail without the change, plus the implementation. No extra run whose only purpose is to prove the tests start red.
3. Start the **test** cluster on the practice checkout. Set the branch name and the test command. Do not start apply.
4. Wait/poll with the budget below.
5. On failure: change code and/or tests. Prefer fixing code if the test still matches what the user asked. Change tests when the test is the wrong spec. Do not delete the meaning of the request just to pass. **At most three** failed test runs, then stop with the log and no pull request.
6. On success: **one** pull request at that commit. Paste the link.
7. Wait until the user merges and names the apply cluster (`merged, deploy …`).
8. Start that **existing** apply cluster so it pulls **main** / **master** only.

## Two copies of the code

**Practice (test)** — the feature branch, before a review:

clone if needed → check out the branch → run the tests

**Live (apply)** — after merge, main branch only:

clone if needed → pull main/master

A real app deploy can also build images, restart containers, and check they came back. A simple apply can be pull-only (enough for a public demo repo).

The same computer can host both copies if the folders are different, for example `/home/ordo/myapp-dev` and `/home/ordo/myapp`. Never check out a feature branch in the live folder. Never run production Docker Compose as a test.

Public GitHub repos can clone with HTTPS (no special key). Private repos need a deploy key (or similar) for that user on that machine.

## What the practice machine needs

Ordo can only use tools already installed for the job user. First-time setup is usually a person, not the agent.

| If this is missing | What you will see | What to do |
|--------------------|-------------------|------------|
| `git` and `openssh-client` | `git: command not found` | Install in a normal admin session |
| Sudo without a password, or a person to install packages | `sudo: a password is required` | Do not put a sudo password in a job |
| GitHub in `~/.ssh/known_hosts` | `Host key verification failed` | `ssh-keyscan -t ed25519,rsa github.com >> ~/.ssh/known_hosts` |
| Deploy key, for a private repo | `Permission denied (publickey)` | Read-only key is enough to clone and pull. Log only the public half |
| A folder that is not the live tree | Tests and live mixed together | Two directories |
| Tests the box can actually run | Missing libraries (`Mojo::Base`, and so on) | If the box has no app runtime, check files and `git` only. Python demos can use stdlib `unittest` |

Add the machine as an Ordo **server** in the web UI first. That step is not an MCP tool.

## If apply restarts Docker on the same machine

Jobs run as the host user over SSH, not inside the container you may replace.

- `docker compose restart` will not pick up a newly built image with the same name. Recreate the app services (`up -d --force-recreate`).
- The Ordo launcher already detaches from SSH. `nohup` is optional. Use it only if you want the job to report “done” before the API container goes down.
- Leave the web proxy running if it did not change.
- Do not put a calendar on production apply — start it by hand (or by the agent after you ask).

## How long the agent should wait

Starting a cluster does not keep a live notification channel. Chat agents should not check status in a tight loop.

- Estimate how long the run should take from the last log or from the command.
- Wait a little longer than that (about 1.2×), at least 5 seconds, at most **45 seconds** in a chat.
- Check status once. If it finished, read the log.
- If it is still going, wait once more (same cap) and check once more, then **stop** and tell the user the cluster name/id.
- Do not keep checking a live deploy unless the user asked for the log. Long builds: start them and wait for the user.

Other kinds of agents may wait longer. The user can say so.

## Examples

Test-style jobs: clone → check out the branch → `unittest` or a small smoke check.

App-style live update: pull → build → recreate the app and worker → check they are up.

[nextwhen](https://github.com/nathanielgraham/nextwhen) is a small public example: tests on one folder, pull-only apply on another.

Job scripts can live in the Ordo job text. They do not have to be files in git.

## Safety

- Do not put GitHub or Ordo tokens in job scripts.
- Pull with `--ff-only` unless you mean to throw away edits on the machine.
- Keep databases and secrets on the host, not baked into an image, when that is how you already deploy.
- Do not check out feature branches in the live folder.

## See also

- [Connecting to AI](#docs/connecting-to-ai)
- [Jobs and clusters](#docs/jobs-and-clusters)
- [Self-hosted](#docs/self-hosted)
