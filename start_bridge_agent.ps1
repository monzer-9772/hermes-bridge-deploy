# Start bridge_agent.py to connect to server
$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes_sync\v4"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

# Update WS URL to current tunnel
$tunnelUrl = "https://respiratory-humanities-constant-miller.trycloudflare.com"
$wsUrl = $tunnelUrl.Replace("https://", "wss://") + "/ws"

Write-Host "=== Starting bridge_agent.py ==="
Write-Host "  WS URL: $wsUrl"

# Patch the URL in bridge_agent.py (it's hardcoded to dead URL)
$agentPath = "$dir\bridge_agent.py"
$content = Get-Content $agentPath -Raw
$content = $content -replace 'wss://[a-zA-Z0-9-]+\.trycloudflare\.com/ws', $wsUrl
$content | Set-Content $agentPath -Encoding UTF8
Write-Host "  Patched WS URL"

# Start it
$proc = Start-Process -FilePath $py `
    -ArgumentList "-u", "$dir\bridge_agent.py" `
    -WorkingDirectory $dir `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$dir\ba.log" `
    -RedirectStandardError "$dir\ba.err" `
    -PassThru
Write-Host "  PID: $($proc.Id)"

Start-Sleep -Seconds 5

Write-Host ""
Write-Host "=== ba.log (last 20) ==="
if (Test-Path "$dir\ba.log") { Get-Content "$dir\ba.log" -Tail 20 }
Write-Host ""
Write-Host "=== ba.err (last 10) ==="
if (Test-Path "$dir\ba.err") { Get-Content "$dir\ba.err" -Tail 10 }
