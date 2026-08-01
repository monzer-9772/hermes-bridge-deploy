$installDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$logDir = "$installDir\logs"
$taskName1 = "HermesBridgeV3"
$taskName2 = "HermesTunnel"

# Remove existing
Unregister-ScheduledTask -TaskName $taskName1 -Confirm:$false -EA SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName2 -Confirm:$false -EA SilentlyContinue

Write-Host "=== Step 1: Register bridge scheduled task ==="
# Use schtasks.exe directly (more reliable, no PowerShell wrapper issues)
$result = schtasks.exe /Create /TN $taskName1 `
  /TR "`"$installDir\restart_bridge.cmd`"" `
  /SC ONLOGON `
  /RL LIMITED `
  /F 2>&1
Write-Host "  $result"

Write-Host ""
Write-Host "=== Step 2: Register tunnel scheduled task (delayed 30s after bridge) ==="
$result = schtasks.exe /Create /TN $taskName2 `
  /TR "`"$installDir\restart_tunnel.cmd`"" `
  /SC ONLOGON `
  /RL LIMITED `
  /F 2>&1
Write-Host "  $result"

Write-Host ""
Write-Host "=== Step 3: Verify scheduled tasks ==="
schtasks.exe /Query /TN $taskName1 /FO LIST 2>&1 | Select-String -Pattern "TaskName|Status|Next Run"
Write-Host "---"
schtasks.exe /Query /TN $taskName2 /FO LIST 2>&1 | Select-String -Pattern "TaskName|Status|Next Run"

Write-Host ""
Write-Host "=== Step 4: Start tunnel manually now ==="
Get-Process -Name "cloudflared" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep -Seconds 2

$proc = Start-Process -FilePath "$installDir\restart_tunnel.cmd" -WindowStyle Hidden -PassThru
Write-Host "  Started tunnel wrapper (PID: $($proc.Id))"

# Wait for URL
Write-Host ""
Write-Host "=== Step 5: Wait for tunnel URL ==="
$tunnelUrl = $null
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 2
    $errFile = "$installDir\tunnel\tunnel.err"
    if (Test-Path $errFile) {
        $content = Get-Content $errFile -Raw -EA SilentlyContinue
        if ($content -match 'https://[a-zA-Z0-9\-]+\.trycloudflare\.com') {
            $tunnelUrl = $matches[0]
            break
        }
    }
    Write-Host "  ...waiting ($($i+1)/20)"
}

if ($tunnelUrl) {
    Set-Content -Path "$installDir\url.txt" -Value $tunnelUrl
    Write-Host ""
    Write-Host "✅ NEW TUNNEL URL: $tunnelUrl"
} else {
    Write-Host ""
    Write-Host "❌ No URL found"
}
