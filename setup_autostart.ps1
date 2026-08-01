$installDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$logDir = "$installDir\logs"
$taskName1 = "HermesBridgeV3"
$taskName2 = "HermesTunnel"

# Remove existing if any
Unregister-ScheduledTask -TaskName $taskName1 -Confirm:$false -EA SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName2 -Confirm:$false -EA SilentlyContinue

Write-Host "=== Step 1: Create restart wrapper scripts ==="

# Bridge restart wrapper (kills existing, starts fresh)
$bridgeWrapper = @"
@echo off
:loop
taskkill /F /FI "WINDOWTITLE eq bridge_v3*" 2>nul
timeout /t 2 /nobreak >nul
cd /d "$installDir"
"C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe" -m uvicorn laptop_bridge_v3:app --host 127.0.0.1 --port 8765 --app-dir "$installDir" > "$logDir\bridge_v3.log" 2>&1
timeout /t 5 /nobreak >nul
goto loop
"@
$wrapper1 = "$installDir\restart_bridge.cmd"
Set-Content -Path $wrapper1 -Value $bridgeWrapper
Write-Host "  Created: $wrapper1"

# Tunnel restart wrapper (extracts new URL, saves to file)
$tunnelWrapper = @"
@echo off
:loop
cd /d "$installDir\tunnel"
del tunnel.log tunnel.err 2>nul
cloudflared tunnel --url http://127.0.0.1:8765 --no-autoupdate > tunnel.log 2> tunnel.err
timeout /t 10 /nobreak >nul
goto loop
"@
$wrapper2 = "$installDir\restart_tunnel.cmd"
Set-Content -Path $wrapper2 -Value $tunnelWrapper
Write-Host "  Created: $wrapper2"

Write-Host ""
Write-Host "=== Step 2: Create scheduled tasks ==="

# Bridge: every 1 minute, restart if dead
$action1 = New-ScheduledTaskAction -Execute $wrapper1
$trigger1 = New-ScheduledTaskTrigger -AtLogOn
$principal1 = New-ScheduledTaskPrincipal -UserId "abdul" -LogonType Interactive
$settings1 = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName1 -Action $action1 -Trigger $trigger1 -Principal $principal1 -Settings $settings1 -Description "Hermes Bridge v3 - laptop control" | Out-Null
Write-Host "  ✅ Registered: $taskName1 (at logon)"

# Tunnel: every 1 minute after bridge
$action2 = New-ScheduledTaskAction -Execute $wrapper2
$trigger2 = New-ScheduledTaskTrigger -AtLogOn
$settings2 = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Delay "00:00:30"
Register-ScheduledTask -TaskName $taskName2 -Action $action2 -Trigger $trigger2 -Principal $principal1 -Settings $settings2 -Description "Hermes Cloudflare tunnel" | Out-Null
Write-Host "  ✅ Registered: $taskName2 (at logon, 30s delay)"

Write-Host ""
Write-Host "=== Step 3: Verify tasks ==="
Get-ScheduledTask -TaskName $taskName1, $taskName2 | Format-Table TaskName, State, TaskPath

Write-Host ""
Write-Host "=== Step 4: URL sync helper ==="
# Create script to push current tunnel URL to GitHub gist
$syncScript = @"
# Reads current tunnel URL from tunnel.log and pushes to GitHub gist
# Run this every 5 minutes from cloud (via cron)
`$url = Select-String -Path "$installDir\tunnel\tunnel.err" -Pattern 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' -EA SilentlyContinue | Select-Object -First 1
if (`$url) {
    `$tunnelUrl = `$url.Matches.Value
    Write-Host "Current URL: `$tunnelUrl"
    `$env:BRIDGE_URL = `$tunnelUrl
    # Cloud can read this from GitHub gist
    `$body = @{
        description = "hermes-bridge-url"
        public = `$false
        files = @{ "url.txt" = @{ content = `$tunnelUrl } }
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "https://api.github.com/gists" -Method Post -Body `$body -ContentType "application/json"
}
"@
Set-Content -Path "$installDir\sync_url.ps1" -Value $syncScript
Write-Host "  Created: $installDir\sync_url.ps1"

Write-Host ""
Write-Host "=== Step 5: Manual test - start tunnel now ==="
# Stop existing
Get-Process -Name "cloudflared" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep -Seconds 2

# Start fresh
$proc = Start-Process -FilePath "$installDir\restart_tunnel.cmd" -WindowStyle Hidden -PassThru
Write-Host "  Started tunnel wrapper (PID: $($proc.Id))"

Write-Host ""
Write-Host "✅ AUTO-START CONFIGURED"
Write-Host "Tasks will run on next logon."
