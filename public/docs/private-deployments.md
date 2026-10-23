# Deployments

Ordo runs as hosted SaaS or on your own machines.

## Options

| Option | Hosting | Who manages it | Notes |
|--------|---------|----------------|-------|
| **SaaS** | Ordo | Ordo | Sign up, magic link, billing |
| **Self-hosted** | You | You | Docker Compose, no license key, no SMTP required |

Self-hosted is the open-source install. See [Self-Hosted](self-hosted.md).

## Self-hosted

- You run the container
- First admin is created on an empty database; the API token is printed in the logs
- Log in at `/token-login`
- Admins create more users and hand over a token or a one-time link
- SMTP is optional

## SaaS

- Sign up with email
- Magic link sets the session
- Team invites and billing use the hosted service

## Polling

Self-hosted is not on the shared SaaS API quota. Poll as often as the machine can handle. On SaaS, stay within your plan.
