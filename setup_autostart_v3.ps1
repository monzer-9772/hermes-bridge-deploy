$installDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$logDir = "$installDir\logs"

# Find Startup folder for current user
$startup = [Environment]::GetFolderPath('Startup')
Write-Host "Startup folder: $startup"

Write-Host ""
Write-Host "=== Step 1: Create bridge wrapper ==="
$bridgeVbs = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run chr(34) & "$installDir\restart_bridge.cmd" & chr(34), 0, False
Set WshShell = Nothing
"@
$bridgeVbsPath = "$installDir\run_bridge_silent.vbs"
Set-Content -Path $bridgeVbsPath -Value $bridgeVbs
Write-Host "  Created: $bridgeVbsPath"

# Create shortcut in Startup folder
$bridgeShortcut = "$startup\HermesBridgeV3.lnk"
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($bridgeShortcut)
$sc.TargetPath = $bridgeVbsPath
$sc.WorkingDirectory = $installDir
$sc.WindowStyle = 7  # Minimized
$sc.Save()
Write-Host "  Created shortcut: $bridgeShortcut"

Write-Host ""
Write-Host "=== Step 2: Create tunnel wrapper (delayed) ==="
$tunnelVbs = @"
WScript.Sleep 30000
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run chr(34) & "$installDir\restart_tunnel.cmd" & chr(34), 0, False
Set WshShell = Nothing
"@
$tunnelVbsPath = "$installDir\run_tunnel_silent.vbs"
Set-Content -Path $tunnelVbsPath -Value $tunnelVbs
Write-Host "  Created: $tunnelVbsPath"

$tunnelShortcut = "$startup\HermesTunnel.lnk"
$sc = $ws.CreateShortcut($tunnelShortcut)
$sc.TargetPath = $tunnelVbsPath
$sc.WorkingDirectory = "$installDir\tunnel"
$sc.WindowStyle = 7
$sc.Save()
Write-Host "  Created shortcut: $tunnelShortcut"

Write-Host ""
Write-Host "=== Step 3: Verify startup items ==="
Get-ChildItem $startup | Format-Table Name, Length

Write-Host ""
Write-Host "=== Step 4: Also try Task Scheduler with /RU SYSTEM ==="
# This needs admin but try
$result = schtasks.exe /Create /TN "HermesBridgeV3_System" `
  /TR "`"$installDir\restart_bridge.cmd`"" `
  /SC ONLOGON `
  /RU SYSTEM `
  /F 2>&1
Write-Host "  SYSTEM bridge: $result"

Start-Sleep -Seconds 2

Write-Host ""
Write-Host "=== Step 5: Start tunnel now (manually) ==="
Get-Process -Name "cloudflared" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep -Seconds 2

$proc = Start-Process -FilePath "$installDir\restart_tunnel.cmd" -WindowStyle Hidden -PassThru
Write-Host "  Started tunnel wrapper (PID: $($proc.Id))"

Write-Host ""
Write-Host "=== Step 6: Wait for URL ==="
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

Write-Host ""
Write-Host "=== Summary ==="
Write-Host "Auto-start method: Startup folder shortcuts (HermesBridgeV3.lnk, HermesTunnel.lnk)"
Write-Host "These run at user logon, no admin needed."
Write-Host "Tunnel URL: $tunnelUrl"
