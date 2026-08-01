param(
    [string]$RepoPath,
    [string]$WorkspacePath,
    [int]$Port = 8767,
    [ValidateSet("quick", "named", "devtunnel")]
    [string]$TunnelMode,
    [string]$NamedHostname,
    [string]$NamedTunnelName,
    [string]$NamedConfigPath,
    [switch]$ChooseWorkspace,
    [switch]$ResetPassword,
    [switch]$KeepExisting,
    [int]$WaitSeconds = 45
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$RepoPath = Resolve-CtmRepoPath -RepoPath $RepoPath
$Config = Read-CtmConfig -RepoPath $RepoPath

$workspace = Resolve-CtmWorkspace -Config $Config -WorkspacePath $WorkspacePath -ChooseWorkspace:$ChooseWorkspace
$Config["workspace_path"] = $workspace
$Config["port"] = $Port
if ($TunnelMode) {
    $Config["tunnel_mode"] = $TunnelMode
} elseif (-not $Config.ContainsKey("tunnel_mode")) {
    $Config["tunnel_mode"] = "quick"
}
if ($NamedHostname) {
    $Config["named_hostname"] = $NamedHostname
    $Config["tunnel_mode"] = "named"
}
if ($NamedTunnelName) {
    $Config["named_tunnel_name"] = $NamedTunnelName
}
if ($NamedConfigPath) {
    $Config["named_config_path"] = (Resolve-Path -LiteralPath $NamedConfigPath).Path
}
if (-not $Config.ContainsKey("oauth_password") -or $ResetPassword) {
    $Config["oauth_password"] = New-CtmUrlSafeToken -ByteCount 32
}
if (-not $Config.ContainsKey("oauth_token_secret_hex")) {
    $Config["oauth_token_secret_hex"] = New-CtmHexSecret -ByteCount 32
}
$Config["oauth_token_ttl_seconds"] = 604800
$Config["keepalive_seconds"] = 60

if (([string]$Config["tunnel_mode"]).ToLowerInvariant() -eq "named") {
    foreach ($required in @("named_hostname", "named_tunnel_name", "named_config_path")) {
        if (-not $Config.ContainsKey($required) -or -not [string]$Config[$required]) {
            throw "Named tunnel mode requires '$required'. Run New-CodingToolsMcpNamedTunnel.ps1 first or pass -NamedHostname/-NamedTunnelName/-NamedConfigPath."
        }
    }
}

Save-CtmConfig -RepoPath $RepoPath -Config $Config | Out-Null

if (-not $KeepExisting) {
    & (Join-Path $PSScriptRoot "Stop-CodingToolsMcpRemote.ps1") -RepoPath $RepoPath | Out-Null
}

$watcher = Join-Path $PSScriptRoot "Watch-CodingToolsMcpRemote.ps1"
$watcherCmd = "& $(Quote-CtmPowerShellString $watcher) -RepoPath $(Quote-CtmPowerShellString $RepoPath)"
$watcherProcess = Start-CtmHiddenPowerShell -Command $watcherCmd -WorkingDirectory $RepoPath
$Config["watcher_pid"] = $watcherProcess.Id
Save-CtmConfig -RepoPath $RepoPath -Config $Config | Out-Null

$sessionPath = Write-CtmSession -RepoPath $RepoPath -Config $Config -Status "starting" -TunnelUrl "" -McpUrl "" -WatcherPid $watcherProcess.Id -Message "watcher launched"

$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    if (Test-Path -LiteralPath $sessionPath) {
        $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath $sessionPath
        if ($raw -match '(?m)^mcp_url=(https?://\S+)$') {
            Write-Host $raw
            exit 0
        }
    }
}

Write-Host "Watcher started, but MCP URL is not ready yet. Check session file:"
Write-Host $sessionPath
if (Test-Path -LiteralPath $sessionPath) {
    Get-Content -Encoding UTF8 -LiteralPath $sessionPath
}
