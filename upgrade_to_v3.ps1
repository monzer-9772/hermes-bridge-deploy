$installDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$logDir = "$installDir\logs"

Write-Host "=== Step 1: Download bridge v3 ==="
$url = "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/laptop_bridge_v3.py"
Invoke-WebRequest -Uri $url -OutFile "$installDir\laptop_bridge_v3.py" -UseBasicParsing
Write-Host "  Saved: $installDir\laptop_bridge_v3.py ($((Get-Item $installDir\laptop_bridge_v3.py).Length) bytes)"

Write-Host ""
Write-Host "=== Step 2: Stop v2 bridge ==="
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.CommandLine -like "*laptop_bridge*" } | ForEach-Object {
    Write-Host "  Stopping PID $($_.Id)"
    Stop-Process -Id $_.Id -Force
}
Start-Sleep -Seconds 3
$portInUse = Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue
if ($portInUse) {
    Stop-Process -Id $portInUse.OwningProcess -Force -EA SilentlyContinue
    Start-Sleep -Seconds 2
}
Write-Host "  ✅ Port 8765 free"

Write-Host ""
Write-Host "=== Step 3: Create v3 launcher ==="
$launcher = @"
@echo off
cd /d "$installDir"
"C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe" -m uvicorn laptop_bridge_v3:app --host 127.0.0.1 --port 8765 --app-dir "$installDir" > "$logDir\bridge_v3.log" 2>&1
"@
$launcherPath = "$installDir\start_bridge_v3.cmd"
Set-Content -Path $launcherPath -Value $launcher
Write-Host "  Created: $launcherPath"

Write-Host ""
Write-Host "=== Step 4: Start v3 ==="
$proc = Start-Process -FilePath $launcherPath -WindowStyle Hidden -PassThru
Write-Host "  Started PID $($proc.Id)"

Start-Sleep -Seconds 6

Write-Host ""
Write-Host "=== Step 5: Verify ==="
try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/ping" -Method Get
    Write-Host "✅ Bridge v3 alive: version=$($r.version), host=$($r.hostname)"
} catch {
    Write-Host "❌ Bridge not responding: $_"
    if (Test-Path "$logDir\bridge_v3.log") {
        Get-Content "$logDir\bridge_v3.log" -Tail 20
    }
}

Write-Host ""
Write-Host "=== Step 6: Submit + wait for result ==="
$headers = @{ Authorization = "Bearer hm-bridge-2026-secure-token-v3" }
$body = @{ task_type = "shell"; payload = @{ command = "echo v3 queue working" } } | ConvertTo-Json
$r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/queue/submit" -Method Post -Headers $headers -ContentType "application/json" -Body $body
Write-Host "✅ Submitted task #$($r.task_id)"
Start-Sleep -Seconds 4
$r2 = Invoke-RestMethod -Uri "http://127.0.0.1:8765/queue/result/$($r.task_id)?wait=10" -Method Get -Headers $headers
Write-Host "✅ Result: status=$($r2.status), result=$($r2.result)"
