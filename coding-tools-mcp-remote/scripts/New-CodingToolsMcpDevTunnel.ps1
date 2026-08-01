param(
    [string]$RepoPath,
    [string]$WorkspacePath,
    [int]$Port = 8767,
    [string]$TunnelId,
    [switch]$GithubLogin,
    [switch]$StartAfterCreate
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$RepoPath = Resolve-CtmRepoPath -RepoPath $RepoPath
$workspace = Resolve-CtmWorkspace -Config (Read-CtmConfig -RepoPath $RepoPath) -WorkspacePath $WorkspacePath
$devtunnel = Get-CtmDevTunnelExe -RepoPath $RepoPath

if (-not $TunnelId) {
    $suffix = (New-CtmUrlSafeToken -ByteCount 5).ToLowerInvariant() -replace '[^a-z0-9]', ''
    if (-not $suffix) {
        $suffix = Get-Random -Minimum 10000 -Maximum 99999
    }
    $TunnelId = "coding-tools-mcp-$suffix"
}

Write-Host "Checking Microsoft Dev Tunnels login..."
$loginOk = $false
try {
    & $devtunnel user show | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $loginOk = $true
    }
} catch {
}

if (-not $loginOk) {
    Write-Host "A browser/device-code login is required. Complete the login, then return here."
    if ($GithubLogin) {
        & $devtunnel user login --github --use-device-code-auth
    } else {
        & $devtunnel user login --use-device-code-auth
    }
}

Write-Host "Creating persistent anonymous dev tunnel: $TunnelId"
try {
    & $devtunnel create $TunnelId --allow-anonymous --description "Coding Tools MCP for ChatGPT" | Out-Host
} catch {
    Write-Host "Create command returned an error; continuing in case the tunnel already exists."
}

Write-Host "Creating/updating tunnel port: $Port"
try {
    & $devtunnel port create $TunnelId --port-number $Port --protocol http --host-header unchanged | Out-Host
} catch {
    Write-Host "Port create returned an error; continuing in case the port already exists."
}

$showJson = $null
try {
    $showJson = & $devtunnel show $TunnelId --json | ConvertFrom-Json
} catch {
}
if ($showJson -and $showJson.tunnel -and $showJson.tunnel.tunnelId) {
    $TunnelId = [string]$showJson.tunnel.tunnelId
}

$Config = Read-CtmConfig -RepoPath $RepoPath
$Config["workspace_path"] = $workspace
$Config["port"] = $Port
$Config["tunnel_mode"] = "devtunnel"
$Config["devtunnel_id"] = $TunnelId
if (-not $Config.ContainsKey("oauth_password")) {
    $Config["oauth_password"] = New-CtmUrlSafeToken -ByteCount 32
}
if (-not $Config.ContainsKey("oauth_token_secret_hex")) {
    $Config["oauth_token_secret_hex"] = New-CtmHexSecret -ByteCount 32
}
$Config["oauth_token_ttl_seconds"] = 604800
$Config["keepalive_seconds"] = 60
Save-CtmConfig -RepoPath $RepoPath -Config $Config | Out-Null

Write-Host "Dev Tunnel configured. Start it to read the final mcp_url from the session file."

if ($StartAfterCreate) {
    & (Join-Path $PSScriptRoot "Start-CodingToolsMcpRemote.ps1") -RepoPath $RepoPath -WaitSeconds 60
}
