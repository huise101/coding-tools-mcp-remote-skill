param(
    [string]$RepoPath,
    [string]$Expiration = "30d"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$RepoPath = Resolve-CtmRepoPath -RepoPath $RepoPath
$Config = Read-CtmConfig -RepoPath $RepoPath
if (-not $Config.ContainsKey("devtunnel_id") -or -not [string]$Config["devtunnel_id"]) {
    throw "No devtunnel_id found in config. Run New-CodingToolsMcpDevTunnel.ps1 first."
}

$devtunnel = Get-CtmDevTunnelExe -RepoPath $RepoPath
& $devtunnel update ([string]$Config["devtunnel_id"]) --expiration $Expiration
& $devtunnel show ([string]$Config["devtunnel_id"])
