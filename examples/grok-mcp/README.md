# Connect Ordo to Grok Build

Ordo's MCP server is public HTTPS:

```
https://ordoscheduler.com/mcp
```

Auth is a bearer token. Grok Build should send it as a header. Do not put the
token in git, in `.mcp.json`, or in a marketplace plugin file.

## 1. Get a token

In the Ordo UI (Settings / API / MCP token) copy your user token.

It is the same token `read_user` returns as `token`. Treat it like a password.

```bash
export ORDO_TOKEN=your_token_here
```

Put that in `~/.profile` or a secrets manager. Never commit it.

## 2. Add the server (recommended)

```bash
grok mcp add --transport http ordo https://ordoscheduler.com/mcp \
  --header "Authorization: Bearer ${ORDO_TOKEN}"
```

Check it:

```bash
grok mcp doctor ordo
```

In the TUI: `/mcps` → enable `ordo`. Tools show up as `ordo__find_cluster`,
`ordo__read_user`, and so on.

Self-hosted / private deploy: swap the URL for your origin + `/mcp`.

## 3. Or declare it in config

User-wide `~/.grok/config.toml`:

```toml
[mcp_servers.ordo]
url = "https://ordoscheduler.com/mcp"
headers = { Authorization = "Bearer ${ORDO_TOKEN}" }
```

`${ORDO_TOKEN}` expands from the environment when Grok Build loads config.

Project-scoped copy: `examples/grok-mcp/config.toml.example` — copy to
`.grok/config.toml` in a repo and keep the token out of the file.

## 4. Smoke test

```bash
curl -sS -X POST https://ordoscheduler.com/mcp \
  -H "Authorization: Bearer ${ORDO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
```

You want `serverInfo.name` = `Ordo MCP`. Then ask Grok Build: "using Ordo,
list my clusters at /root".

## What not to do

- Do not paste the token into a plugin PR or `marketplace.json`.
- Do not put the token in the URL query string.
- Rotate the token if it leaked in a chat or screenshot.

OAuth (browser login, no env var) is a later slice. This path is enough for
Grok Build and a future marketplace listing that documents `ORDO_TOKEN`.
