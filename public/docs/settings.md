# Settings & Administration

The **Settings** tab is where you manage your Ordo account, team members, security tokens, and subscription details.

## Account Information

This section shows:
- Your email address
- Account creation date
- Current subscription tier (Free / Paid)
- Organization name

## Security Tokens

Ordo uses two distinct types of tokens for different purposes.

### Execution Token

- Used by **remote servers** to authenticate with Ordo when launching jobs.
- The token is automatically encoded and sent with every job execution via `launcher.pl`.
- **You do not need to manually update it** on remote servers after rotating.

**Important**: Rotating the Execution Token will cause any **currently running jobs** to lose the ability to report final status or send logs back to Ordo. New jobs started after rotation will work normally.

You can rotate this token at any time from this page.

### API Token

- Used for **external API access** (custom scripts, tools, or integrations).
- Allows authenticated calls to Ordo’s REST API from outside the web interface.
- Should be kept secret and rotated immediately if compromised.

**Best Practice**: Use the **Execution Token** for server communication and the **API Token** for external scripts or tools.

## Members

Admins (level 3) create users from **Settings → Members**.

1. Enter a name and email.
2. Leave **New org** unchecked to share your job tree. Check it to give them their own org.
3. Click **Create user**.

You get an API token and a one-time `/confirm` link. Hand either to the new user. They paste the token at `/token-login`, or open the link. No email is sent.

The new user is a Member (level 1). Only level 3 can create users.

## Subscription & Upgrading

This section displays:
- Your current plan (Free / Paid)
- Usage limits (API calls, servers, team members)
- Option to upgrade

On SaaS, click **View Plans & Upgrade** to explore tiers and pricing. Self-hosted has no billing tab.

## Rate Limits

Ordo enforces fair usage limits:
- **Per User** — Requests per minute
- **Per Organization** — Total requests per minute

Paid plans offer significantly higher limits.

## Best Practices

- Rotate your **Execution Token** periodically, ideally during planned maintenance windows.
- Keep your **API Token** secure and never expose it in client-side code.
- Monitor your usage in the Settings tab to avoid hitting rate limits.
- Only invite team members you fully trust.

## Need Help?

For questions about your account, billing, tokens, custom deployments (private networks, on-premise, etc.), or anything else, email **ordosched@proton.me**.

