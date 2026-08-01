param(
    [string]$RepoPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$RepoPath = Resolve-CtmRepoPath -RepoPath $RepoPath
$sessionPath = Get-CtmSessionPath -RepoPath $RepoPath
$configPath = Get-CtmConfigPath -RepoPath $RepoPath

Write-Host "Repo: $RepoPath"
Write-Host "Config: $configPath"
Write-Host "Session: $sessionPath"
Write-Host ""

if (Test-Path -LiteralPath $sessionPath) {
    Get-Content -Encoding UTF8 -LiteralPath $sessionPath
} else {
    Write-Host "No session file found."
}

Write-Host ""
$Config = Read-CtmConfig -RepoPath $RepoPath
if ($Config.ContainsKey("port")) {
    $owner = Get-CtmPortOwner -Port ([int]$Config["port"])
    if ($owner) {
        Write-Host "Local port $($Config["port"]) is listening; owner pid=$owner"
    } else {
        Write-Host "Local port $($Config["port"]) is not listening."
    }
}
