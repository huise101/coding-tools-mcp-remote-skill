# coding-tools-mcp-remote skill

A Codex skill for running [`xyTom/coding-tools-mcp`](https://github.com/xyTom/coding-tools-mcp) as a remote MCP server for ChatGPT on Windows.

It provides PowerShell scripts for:

- choosing a workspace folder
- starting `coding-tools-mcp` in OAuth mode
- exposing it through Microsoft Dev Tunnels or Cloudflare Tunnel
- keeping the MCP server and tunnel alive with a watchdog
- installing a Windows logon scheduled task
- showing the current `mcp_url` and OAuth password

## Layout

```text
coding-tools-mcp-remote/
  SKILL.md
  agents/openai.yaml
  references/
  scripts/
```

Copy `coding-tools-mcp-remote/` into your Codex skills directory, for example:

```powershell
Copy-Item -Recurse .\coding-tools-mcp-remote "$env:USERPROFILE\.codex\skills\coding-tools-mcp-remote"
```

## Requirements

- Windows PowerShell
- Python 3.11+
- A local checkout of `coding-tools-mcp`
- One tunnel provider:
  - Microsoft Dev Tunnels CLI for the free `*.devtunnels.ms` option
  - Cloudflare `cloudflared` for Cloudflare Quick/Named Tunnel

## Free Dev Tunnels Setup

Download `devtunnel.exe` from Microsoft and put it in the `tools/` folder of your `coding-tools-mcp` checkout, or install it globally.

Then run:

```powershell
cd <portable-root>

.\skills\coding-tools-mcp-remote\scripts\New-CodingToolsMcpDevTunnel.ps1 `
  -RepoPath ".\coding-tools-mcp" `
  -WorkspacePath "C:\path\to\workspace" `
  -TunnelId "coding-tools-mcp-yourname" `
  -GithubLogin `
  -StartAfterCreate
```

Install logon startup:

```powershell
.\skills\coding-tools-mcp-remote\scripts\Install-CodingToolsMcpRemote.ps1 `
  -RepoPath ".\coding-tools-mcp" `
  -WorkspacePath "C:\path\to\workspace" `
  -TunnelMode devtunnel `
  -InstallStartupTask `
  -SkipPythonInstall
```

Dev Tunnels can provide a free account-bound URL, but it may show an expiration window such as 30 days. Renew it with:

```powershell
.\skills\coding-tools-mcp-remote\scripts\Renew-CodingToolsMcpDevTunnel.ps1 `
  -RepoPath ".\coding-tools-mcp" `
  -Expiration "30d"
```

## Cloudflare Named Tunnel Setup

For the most permanent URL, use a Cloudflare-managed hostname:

```powershell
cd <portable-root>

.\skills\coding-tools-mcp-remote\scripts\New-CodingToolsMcpNamedTunnel.ps1 `
  -Hostname "mcp.example.com" `
  -RepoPath ".\coding-tools-mcp" `
  -WorkspacePath "C:\path\to\workspace" `
  -StartAfterCreate
```

## ChatGPT Connector Settings

Read the session file after startup:

```powershell
.\skills\coding-tools-mcp-remote\scripts\Show-CodingToolsMcpRemote.ps1 `
  -RepoPath ".\coding-tools-mcp"
```

Use:

- `mcp_url` as the MCP server URL
- `oauth_password` when the OAuth authorization page asks for it

Recommended ChatGPT settings:

- Authentication: OAuth
- OAuth discovery: automatic
- Client registration: Dynamic Client Registration / DCR

## Do Not Commit

Do not commit runtime state, tunnel credentials, OAuth passwords, logs, or downloaded executables. The `.gitignore` in this repo excludes the common generated files.
