param(
    [string]$RepoPath,
    [int]$IntervalSeconds = 10
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$RepoPath = Resolve-CtmRepoPath -RepoPath $RepoPath
$Config = Read-CtmConfig -RepoPath $RepoPath
if (-not $Config.ContainsKey("workspace_path")) {
    $Config["workspace_path"] = Resolve-CtmWorkspace -Config $Config
}
if (-not $Config.ContainsKey("port")) {
    $Config["port"] = 8767
}
if (-not $Config.ContainsKey("tunnel_mode")) {
    $Config["tunnel_mode"] = "quick"
}
if (-not $Config.ContainsKey("oauth_password")) {
    $Config["oauth_password"] = New-CtmUrlSafeToken -ByteCount 32
}
if (-not $Config.ContainsKey("oauth_token_secret_hex")) {
    $Config["oauth_token_secret_hex"] = New-CtmHexSecret -ByteCount 32
}
if (-not $Config.ContainsKey("oauth_token_ttl_seconds")) {
    $Config["oauth_token_ttl_seconds"] = 604800
}
if (-not $Config.ContainsKey("keepalive_seconds")) {
    $Config["keepalive_seconds"] = 60
}
$Config["watcher_pid"] = $PID
Save-CtmConfig -RepoPath $RepoPath -Config $Config | Out-Null

$runtimeDir = Get-CtmRuntimeDir -RepoPath $RepoPath
$serverStdoutLog = Join-Path $runtimeDir "mcp-server-last.stdout.log"
$serverStderrLog = Join-Path $runtimeDir "mcp-server-last.stderr.log"
$cloudflaredStdoutLog = Join-Path $runtimeDir "cloudflared-last.stdout.log"
$cloudflaredStderrLog = Join-Path $runtimeDir "cloudflared-last.stderr.log"

$serverProcess = $null
$cloudflaredProcess = $null
$tunnelUrl = ""
$mcpUrl = ""
$serverPid = 0
$publicFailures = 0
$lastPublicCheck = [DateTime]::MinValue

function Test-ProcessAlive {
    param($Process)
    return ($null -ne $Process -and -not $Process.HasExited)
}

function Stop-TrackedProcess {
    param($Process)
    if (Test-ProcessAlive -Process $Process) {
        try {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
}

function Get-QuickTunnelUrlFromLogs {
    $text = ""
    foreach ($path in @($cloudflaredStdoutLog, $cloudflaredStderrLog)) {
        if (Test-Path -LiteralPath $path) {
            $text += "`n" + (Get-Content -Raw -Encoding UTF8 -LiteralPath $path -ErrorAction SilentlyContinue)
        }
    }
    if (-not $text) {
        return ""
    }
    $matches = [regex]::Matches($text, 'https://[a-z0-9-]+\.trycloudflare\.com')
    if ($matches.Count -eq 0) {
        return ""
    }
    return $matches[$matches.Count - 1].Value
}

function Start-McpServer {
    Set-Content -Encoding UTF8 -LiteralPath $serverStdoutLog -Value ""
    Set-Content -Encoding UTF8 -LiteralPath $serverStderrLog -Value ""

    $python = Get-CtmPythonExe
    $oauthStateFile = Join-Path $runtimeDir "oauth-state.json"
    $envVars = @{
        "CODING_TOOLS_MCP_OAUTH_PASSWORD" = [string]$Config["oauth_password"]
        "CODING_TOOLS_MCP_OAUTH_TOKEN_SECRET" = [string]$Config["oauth_token_secret_hex"]
        "CODING_TOOLS_MCP_OAUTH_TOKEN_TTL" = [string]$Config["oauth_token_ttl_seconds"]
        "CODING_TOOLS_MCP_OAUTH_STATE_FILE" = $oauthStateFile
    }
    if (([string]$Config["tunnel_mode"]).ToLowerInvariant() -eq "named" -and $Config.ContainsKey("named_hostname")) {
        $envVars["CODING_TOOLS_MCP_SERVER_URL"] = "https://$($Config["named_hostname"])"
    } elseif (([string]$Config["tunnel_mode"]).ToLowerInvariant() -eq "devtunnel" -and $Config.ContainsKey("devtunnel_url")) {
        $envVars["CODING_TOOLS_MCP_SERVER_URL"] = [string]$Config["devtunnel_url"]
    }
    $serverArgs = @(
        "-m",
        "coding_tools_mcp",
        "--workspace",
        [string]$Config["workspace_path"],
        "--host",
        "127.0.0.1",
        "--port",
        [string]$Config["port"],
        "--oauth-mode"
    )

    Write-CtmLog -RepoPath $RepoPath -Message "starting MCP server on port $($Config["port"]) for workspace $($Config["workspace_path"])"
    $script:serverProcess = Start-CtmNativeProcess -FilePath $python -Arguments $serverArgs -WorkingDirectory $RepoPath -StdoutPath $serverStdoutLog -StderrPath $serverStderrLog -Environment $envVars
}

function Start-Tunnel {
    Set-Content -Encoding UTF8 -LiteralPath $cloudflaredStdoutLog -Value ""
    Set-Content -Encoding UTF8 -LiteralPath $cloudflaredStderrLog -Value ""

    $mode = ([string]$Config["tunnel_mode"]).ToLowerInvariant()
    if ($mode -eq "named") {
        $cloudflared = Get-CtmCloudflaredExe -RepoPath $RepoPath
        if (-not $Config.ContainsKey("named_tunnel_name") -or -not $Config.ContainsKey("named_config_path") -or -not $Config.ContainsKey("named_hostname")) {
            throw "Named tunnel mode requires named_tunnel_name, named_config_path, and named_hostname in config."
        }
        $script:tunnelUrl = "https://$($Config["named_hostname"])"
        $script:mcpUrl = "$script:tunnelUrl/mcp"
        $tunnelArgs = @("tunnel", "--config", [string]$Config["named_config_path"], "run", [string]$Config["named_tunnel_name"])
    } elseif ($mode -eq "devtunnel") {
        if (-not $Config.ContainsKey("devtunnel_id") -or -not [string]$Config["devtunnel_id"]) {
            throw "Dev Tunnel mode requires devtunnel_id in config. Run New-CodingToolsMcpDevTunnel.ps1 first."
        }
        $devtunnel = Get-CtmDevTunnelExe -RepoPath $RepoPath
        $script:tunnelUrl = ""
        $script:mcpUrl = ""
        $tunnelArgs = @("host", [string]$Config["devtunnel_id"])
        Write-CtmLog -RepoPath $RepoPath -Message "starting $mode tunnel"
        $script:cloudflaredProcess = Start-CtmNativeProcess -FilePath $devtunnel -Arguments $tunnelArgs -WorkingDirectory $RepoPath -StdoutPath $cloudflaredStdoutLog -StderrPath $cloudflaredStderrLog
        return
    } else {
        $cloudflared = Get-CtmCloudflaredExe -RepoPath $RepoPath
        $script:tunnelUrl = ""
        $script:mcpUrl = ""
        $tunnelArgs = @("tunnel", "--url", "http://127.0.0.1:$($Config["port"])")
    }

    Write-CtmLog -RepoPath $RepoPath -Message "starting $mode Cloudflare tunnel"
    $script:cloudflaredProcess = Start-CtmNativeProcess -FilePath $cloudflared -Arguments $tunnelArgs -WorkingDirectory $RepoPath -StdoutPath $cloudflaredStdoutLog -StderrPath $cloudflaredStderrLog
}

function Update-Session {
    param([string]$Status, [string]$Message = "")

    $cloudPid = 0
    if (Test-ProcessAlive -Process $cloudflaredProcess) {
        $cloudPid = $cloudflaredProcess.Id
    }
    $watcherPid = $PID
    Write-CtmSession -RepoPath $RepoPath -Config $Config -Status $Status -TunnelUrl $tunnelUrl -McpUrl $mcpUrl -WatcherPid $watcherPid -ServerPid $serverPid -CloudflaredPid $cloudPid -Message $Message | Out-Null
}

Write-CtmLog -RepoPath $RepoPath -Message "watcher started pid=$PID"
Update-Session -Status "starting" -Message "watcher started"

while ($true) {
    try {
        $localOk = Test-CtmLocalServer -Port ([int]$Config["port"])
        if (-not $localOk) {
            $owner = Get-CtmPortOwner -Port ([int]$Config["port"])
            if ($owner) {
                Write-CtmLog -RepoPath $RepoPath -Message "port $($Config["port"]) is unhealthy; stopping owner pid=$owner"
                Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue
            }
            Stop-TrackedProcess -Process $serverProcess
            Start-McpServer
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Seconds 1
                if (Test-CtmLocalServer -Port ([int]$Config["port"])) {
                    break
                }
            }
        }
        $serverPid = 0
        $ownerPid = Get-CtmPortOwner -Port ([int]$Config["port"])
        if ($ownerPid) {
            $serverPid = $ownerPid
        }

        if (-not (Test-ProcessAlive -Process $cloudflaredProcess)) {
            Start-Tunnel
        }

        $mode = ([string]$Config["tunnel_mode"]).ToLowerInvariant()
        if ($mode -ne "named") {
            if ($mode -eq "devtunnel") {
                $logText = ""
                foreach ($path in @($cloudflaredStdoutLog, $cloudflaredStderrLog)) {
                    if (Test-Path -LiteralPath $path) {
                        $logText += "`n" + (Get-Content -Raw -Encoding UTF8 -LiteralPath $path -ErrorAction SilentlyContinue)
                    }
                }
                $matches = [regex]::Matches($logText, 'https://[a-z0-9.-]+\.devtunnels\.ms')
                $foundUrl = ""
                foreach ($match in $matches) {
                    $candidate = $match.Value.TrimEnd("/")
                    if ($candidate -notmatch '-inspect\.') {
                        $foundUrl = $candidate
                        break
                    }
                }
                if (-not $foundUrl -and $matches.Count -gt 0) {
                    $foundUrl = $matches[0].Value.TrimEnd("/")
                }
            } else {
                $foundUrl = Get-QuickTunnelUrlFromLogs
            }
            if ($foundUrl) {
                $tunnelUrl = $foundUrl
                $mcpUrl = "$tunnelUrl/mcp"
                if ($mode -eq "devtunnel" -and (-not $Config.ContainsKey("devtunnel_url") -or [string]$Config["devtunnel_url"] -ne $tunnelUrl)) {
                    $Config["devtunnel_url"] = $tunnelUrl
                    Save-CtmConfig -RepoPath $RepoPath -Config $Config | Out-Null
                }
            }
        }

        $now = Get-Date
        $keepaliveSeconds = [int]$Config["keepalive_seconds"]
        if ($tunnelUrl -and (($now - $lastPublicCheck).TotalSeconds -ge $keepaliveSeconds)) {
            $lastPublicCheck = $now
            try {
                $healthUrl = "$tunnelUrl/.well-known/oauth-authorization-server"
                $response = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 10
                if ($response.StatusCode -eq 200) {
                    $publicFailures = 0
                } else {
                    $publicFailures += 1
                }
            } catch {
                $publicFailures += 1
                Write-CtmLog -RepoPath $RepoPath -Message "public health check failed $publicFailures time(s): $($_.Exception.Message)"
            }
            if ($publicFailures -ge 3) {
                Write-CtmLog -RepoPath $RepoPath -Message "public tunnel failed repeatedly; restarting tunnel"
                Stop-TrackedProcess -Process $cloudflaredProcess
                $cloudflaredProcess = $null
                $publicFailures = 0
                if ($mode -ne "named") {
                    $tunnelUrl = ""
                    $mcpUrl = ""
                }
            }
        }

        if ($mcpUrl) {
            Update-Session -Status "running" -Message "ready"
        } else {
            Update-Session -Status "starting" -Message "waiting for tunnel URL"
        }
    } catch {
        Write-CtmLog -RepoPath $RepoPath -Message "watcher error: $($_.Exception.Message)"
        Update-Session -Status "error" -Message $_.Exception.Message
    }

    Start-Sleep -Seconds $IntervalSeconds
}
