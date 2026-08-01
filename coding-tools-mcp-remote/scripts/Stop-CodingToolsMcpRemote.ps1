param(
    [string]$RepoPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$RepoPath = Resolve-CtmRepoPath -RepoPath $RepoPath
$Config = Read-CtmConfig -RepoPath $RepoPath
$sessionPath = Get-CtmSessionPath -RepoPath $RepoPath

$ids = New-Object System.Collections.Generic.List[int]
if ($Config.ContainsKey("watcher_pid")) {
    $ids.Add([int]$Config["watcher_pid"])
}
if (Test-Path -LiteralPath $sessionPath) {
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $sessionPath) {
        if ($line -match '^(watcher_pid|server_pid|cloudflared_pid)=(\d+)$') {
            $ids.Add([int]$Matches[2])
        }
    }
}

foreach ($id in ($ids | Select-Object -Unique)) {
    if ($id -gt 0) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

$port = 8767
if ($Config.ContainsKey("port")) {
    $port = [int]$Config["port"]
}
$owner = Get-CtmPortOwner -Port $port
if ($owner) {
    Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue
}

$repoCloudflared = Join-Path $RepoPath "tools\cloudflared.exe"
if (Test-Path -LiteralPath $repoCloudflared) {
    $resolved = (Resolve-Path -LiteralPath $repoCloudflared).Path
    Get-Process -Name cloudflared -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $resolved } |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
}

Write-CtmSession -RepoPath $RepoPath -Config $Config -Status "stopped" -TunnelUrl "" -McpUrl "" -Message "stopped by Stop-CodingToolsMcpRemote.ps1" | Out-Null
Write-Host "Stopped Coding Tools MCP remote processes for repo: $RepoPath"
