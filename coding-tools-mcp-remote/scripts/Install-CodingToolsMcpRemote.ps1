param(
    [string]$RepoPath,
    [string]$WorkspacePath,
    [int]$Port = 8767,
    [ValidateSet("quick", "named", "devtunnel")]
    [string]$TunnelMode,
    [switch]$ChooseWorkspace,
    [switch]$InstallStartupTask,
    [switch]$SkipPythonInstall
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$RepoPath = Resolve-CtmRepoPath -RepoPath $RepoPath
$workspace = Resolve-CtmWorkspace -Config (Read-CtmConfig -RepoPath $RepoPath) -WorkspacePath $WorkspacePath -ChooseWorkspace:$ChooseWorkspace

if (-not $SkipPythonInstall) {
    $python = Get-CtmPythonExe
    Write-Host "Installing coding-tools-mcp editable package..."
    & $python -m pip install -e "$RepoPath"
}

$Config = Read-CtmConfig -RepoPath $RepoPath
$Config["workspace_path"] = $workspace
$Config["port"] = $Port
if ($TunnelMode) {
    $Config["tunnel_mode"] = $TunnelMode
} elseif (-not $Config.ContainsKey("tunnel_mode")) {
    $Config["tunnel_mode"] = "quick"
}

$mode = ([string]$Config["tunnel_mode"]).ToLowerInvariant()
if ($mode -eq "devtunnel") {
    Get-CtmDevTunnelExe -RepoPath $RepoPath | Out-Null
} else {
    Get-CtmCloudflaredExe -RepoPath $RepoPath | Out-Null
}
if (-not $Config.ContainsKey("oauth_password")) {
    $Config["oauth_password"] = New-CtmUrlSafeToken -ByteCount 32
}
if (-not $Config.ContainsKey("oauth_token_secret_hex")) {
    $Config["oauth_token_secret_hex"] = New-CtmHexSecret -ByteCount 32
}
$Config["oauth_token_ttl_seconds"] = 604800
$Config["keepalive_seconds"] = 60
Save-CtmConfig -RepoPath $RepoPath -Config $Config | Out-Null

if ($InstallStartupTask) {
    $starter = Join-Path $PSScriptRoot "Start-CodingToolsMcpRemote.ps1"
    $taskName = "CodingToolsMcpRemote"
    $argument = "-NoProfile -ExecutionPolicy Bypass -File `"$starter`" -RepoPath `"$RepoPath`""
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Keep Coding Tools MCP remote tunnel running for ChatGPT" -Force | Out-Null
    Write-Host "Startup task installed: $taskName"
}

Write-Host "Installed configuration:"
& (Join-Path $PSScriptRoot "Show-CodingToolsMcpRemote.ps1") -RepoPath $RepoPath
