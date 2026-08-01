param(
    [Parameter(Mandatory = $true)]
    [string]$Hostname,
    [string]$RepoPath,
    [string]$WorkspacePath,
    [int]$Port = 8767,
    [string]$TunnelName = "coding-tools-mcp",
    [switch]$SkipLogin,
    [switch]$OverwriteDns,
    [switch]$StartAfterCreate
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$RepoPath = Resolve-CtmRepoPath -RepoPath $RepoPath
$workspace = Resolve-CtmWorkspace -Config (Read-CtmConfig -RepoPath $RepoPath) -WorkspacePath $WorkspacePath
$cloudflared = Get-CtmCloudflaredExe -RepoPath $RepoPath
$runtimeDir = Get-CtmRuntimeDir -RepoPath $RepoPath
$tunnelDir = Join-Path $runtimeDir "cloudflared"
if (-not (Test-Path -LiteralPath $tunnelDir)) {
    New-Item -ItemType Directory -Path $tunnelDir | Out-Null
}

if (-not $SkipLogin) {
    Write-Host "Cloudflare login will open a browser. Choose the Cloudflare account that owns: $Hostname"
    & $cloudflared tunnel login
}

$listText = (& $cloudflared tunnel list 2>&1 | Out-String)
if ($listText -notmatch [regex]::Escape($TunnelName)) {
    & $cloudflared tunnel create $TunnelName
}

$infoText = (& $cloudflared tunnel info $TunnelName 2>&1 | Out-String)
$tunnelId = ""
foreach ($pattern in @('ID:\s*([0-9a-fA-F-]{36})', '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')) {
    $match = [regex]::Match($infoText, $pattern)
    if ($match.Success) {
        $tunnelId = $match.Groups[1].Value
        break
    }
}
if (-not $tunnelId) {
    throw "Could not determine tunnel UUID from cloudflared tunnel info output."
}

$userCloudflaredDir = Join-Path $env:USERPROFILE ".cloudflared"
$credentialCandidate = Join-Path $userCloudflaredDir "$tunnelId.json"
if (-not (Test-Path -LiteralPath $credentialCandidate)) {
    $foundCredential = Get-ChildItem -Path $userCloudflaredDir -Filter "$tunnelId.json" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $foundCredential) {
        throw "Tunnel credential file not found for $tunnelId under $userCloudflaredDir."
    }
    $credentialCandidate = $foundCredential.FullName
}

$localCredential = Join-Path $tunnelDir "$tunnelId.json"
Copy-Item -LiteralPath $credentialCandidate -Destination $localCredential -Force

$configPath = Join-Path $tunnelDir "config.yml"
$yaml = @(
    "tunnel: $tunnelId",
    "credentials-file: $localCredential",
    "ingress:",
    "  - hostname: $Hostname",
    "    service: http://127.0.0.1:$Port",
    "  - service: http_status:404"
)
$yaml | Set-Content -Encoding UTF8 -LiteralPath $configPath

if ($OverwriteDns) {
    & $cloudflared tunnel route dns --overwrite-dns $TunnelName $Hostname
} else {
    & $cloudflared tunnel route dns $TunnelName $Hostname
}
& $cloudflared tunnel --config $configPath ingress validate

$Config = Read-CtmConfig -RepoPath $RepoPath
$Config["workspace_path"] = $workspace
$Config["port"] = $Port
$Config["tunnel_mode"] = "named"
$Config["named_hostname"] = $Hostname
$Config["named_tunnel_name"] = $TunnelName
$Config["named_tunnel_id"] = $tunnelId
$Config["named_config_path"] = $configPath
if (-not $Config.ContainsKey("oauth_password")) {
    $Config["oauth_password"] = New-CtmUrlSafeToken -ByteCount 32
}
if (-not $Config.ContainsKey("oauth_token_secret_hex")) {
    $Config["oauth_token_secret_hex"] = New-CtmHexSecret -ByteCount 32
}
$Config["oauth_token_ttl_seconds"] = 604800
$Config["keepalive_seconds"] = 60
Save-CtmConfig -RepoPath $RepoPath -Config $Config | Out-Null

Write-Host "Named tunnel configured."
Write-Host "Hostname: https://$Hostname/mcp"
Write-Host "Config: $configPath"

if ($StartAfterCreate) {
    & (Join-Path $PSScriptRoot "Start-CodingToolsMcpRemote.ps1") -RepoPath $RepoPath -WaitSeconds 60
}
