---
name: coding-tools-mcp-remote
description: Set up, repair, migrate, and operate a Windows Coding Tools MCP server for ChatGPT remote MCP access. Use when the user wants ChatGPT to edit local files through xyTom/coding-tools-mcp, choose a workspace folder, expose it with Cloudflare Tunnel or Microsoft Dev Tunnels, keep it running with a watchdog, configure startup persistence, create a stable Named Tunnel/devtunnels.ms URL, or move the setup to another computer.
---

# Coding Tools MCP Remote

## Core Rule

Use Cloudflare Named Tunnel for requests that require indefinite permanence. If the user insists on a free solution, use Microsoft Dev Tunnels mode: it provides an account-bound stable `*.devtunnels.ms` URL without buying a domain, but it may show a 30-day expiration window and should be renewed periodically. Cloudflare Quick Tunnel is only a temporary fallback: it can be restarted automatically, but the public `trycloudflare.com` URL may change and ChatGPT will need reconnecting.

## Scripts

All scripts live in `scripts/` and are written for Windows PowerShell.

- `Install-CodingToolsMcpRemote.ps1`: install editable Python package, validate `cloudflared`, save config, optionally register logon startup task.
- `New-CodingToolsMcpNamedTunnel.ps1`: create/login/configure a Cloudflare Named Tunnel for a fixed hostname.
- `New-CodingToolsMcpDevTunnel.ps1`: create/login/configure a free Microsoft Dev Tunnel stable URL.
- `Renew-CodingToolsMcpDevTunnel.ps1`: renew the free Dev Tunnel expiration window.
- `Start-CodingToolsMcpRemote.ps1`: save the selected workspace and start the watchdog.
- `Watch-CodingToolsMcpRemote.ps1`: keep the local MCP server and tunnel running, perform health checks, and update `.runtime/chatgpt-mcp-last-session.txt`.
- `Stop-CodingToolsMcpRemote.ps1`: stop watcher, MCP server, and repo-local cloudflared.
- `Show-CodingToolsMcpRemote.ps1`: print current config/session status.

## Standard Workflow

1. Resolve the repo path. Prefer the user's `coding-tools-mcp` checkout; otherwise use the portable layout where this skill is inside `<root>/skills/coding-tools-mcp-remote` and the repo is `<root>/coding-tools-mcp`.
2. Ask whether the user accepts a paid/custom domain. Use Cloudflare Named Tunnel for best permanence, or Microsoft Dev Tunnels for free stable `devtunnels.ms` URLs.
3. Run `New-CodingToolsMcpNamedTunnel.ps1 -Hostname <host> -RepoPath <repo> -WorkspacePath <workspace> -StartAfterCreate` after the user has a Cloudflare account and a domain/subdomain available. For free mode, run `New-CodingToolsMcpDevTunnel.ps1 -RepoPath <repo> -WorkspacePath <workspace> -StartAfterCreate`.
4. Run `Install-CodingToolsMcpRemote.ps1 -RepoPath <repo> -WorkspacePath <workspace> -InstallStartupTask` to persist startup on logon.
5. Use `Start-CodingToolsMcpRemote.ps1 -ChooseWorkspace` when the user wants to pick a folder interactively, or `-WorkspacePath <path>` for deterministic setup.
6. Read `.runtime/chatgpt-mcp-last-session.txt` and give the user `mcp_url` and `oauth_password`.

## Stable Mode Requirements

For a stable ChatGPT connector:

- The user must own or control a domain/subdomain in Cloudflare DNS.
- The hostname must be routed to a Cloudflare Named Tunnel.
- The MCP server should run with `CODING_TOOLS_MCP_SERVER_URL=https://<hostname>`.
- The OAuth token secret should persist across restarts.
- OAuth dynamic client and refresh token state should persist at `.runtime/oauth-state.json`.
- The watchdog should be started at logon with Windows Task Scheduler.

The bundled scripts implement these requirements.

## Quick Commands

Stable setup:

```powershell
cd <portable-root>
.\skills\coding-tools-mcp-remote\scripts\New-CodingToolsMcpNamedTunnel.ps1 -Hostname "mcp.example.com" -RepoPath ".\coding-tools-mcp" -WorkspacePath "C:\path\to\workspace" -StartAfterCreate
.\skills\coding-tools-mcp-remote\scripts\Install-CodingToolsMcpRemote.ps1 -RepoPath ".\coding-tools-mcp" -WorkspacePath "C:\path\to\workspace" -InstallStartupTask
```

Free Dev Tunnels setup:

```powershell
cd <portable-root>
.\skills\coding-tools-mcp-remote\scripts\New-CodingToolsMcpDevTunnel.ps1 -RepoPath ".\coding-tools-mcp" -WorkspacePath "C:\path\to\workspace" -TunnelId "coding-tools-mcp-yourname" -GithubLogin -StartAfterCreate
.\skills\coding-tools-mcp-remote\scripts\Install-CodingToolsMcpRemote.ps1 -RepoPath ".\coding-tools-mcp" -WorkspacePath "C:\path\to\workspace" -TunnelMode devtunnel -InstallStartupTask -SkipPythonInstall
```

Choose a folder and start:

```powershell
.\skills\coding-tools-mcp-remote\scripts\Start-CodingToolsMcpRemote.ps1 -RepoPath ".\coding-tools-mcp" -ChooseWorkspace
```

Show status:

```powershell
.\skills\coding-tools-mcp-remote\scripts\Show-CodingToolsMcpRemote.ps1 -RepoPath ".\coding-tools-mcp"
```

Stop:

```powershell
.\skills\coding-tools-mcp-remote\scripts\Stop-CodingToolsMcpRemote.ps1 -RepoPath ".\coding-tools-mcp"
```

## Migration

Copy the whole portable root containing both `coding-tools-mcp/` and `skills/coding-tools-mcp-remote/` to the new computer. Then run install again. Named Tunnel credentials under `.runtime/cloudflared/` are copied with the repo; if they are missing, rerun `New-CodingToolsMcpNamedTunnel.ps1`.
