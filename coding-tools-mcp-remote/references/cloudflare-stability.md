# Cloudflare Tunnel Stability Notes

Use these facts when explaining tradeoffs:

- Quick Tunnel is an account-less temporary tunnel. It is useful for testing but its hostname is not a stable contract.
- Microsoft Dev Tunnels can provide a free account-bound `*.devtunnels.ms` URL without a purchased domain, but the tunnel may have an expiration window such as 30 days. Use it when the user prioritizes free over indefinite permanence.
- Named Tunnel creates a tunnel UUID and routes a DNS hostname to `<UUID>.cfargotunnel.com`; the DNS record remains even when the local process restarts.
- For a stable ChatGPT MCP connector, route a fixed hostname such as `mcp.example.com` to the Named Tunnel and configure the MCP OAuth issuer as `https://mcp.example.com`.
- Persist the MCP OAuth state file so dynamic client registrations and refresh tokens survive local MCP process restarts.
- On Windows, persistence can be handled either by `cloudflared service install` or by a user logon scheduled task. This skill uses a scheduled task because the MCP Python server and tunnel need to be coordinated together.
- The watchdog can restart local processes after transient failures, but no watchdog can prevent a public connection outage caused by power loss, shutdown, ISP outage, DNS failure, or Cloudflare service outage.
