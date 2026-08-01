$installDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$logDir = "$installDir\logs"
New-Item -ItemType Directory -Path $installDir, $logDir -Force | Out-Null

Write-Host "=== Step 1: Download bridge v2 ==="
$url = "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/laptop_bridge_v2.py"
Invoke-WebRequest -Uri $url -OutFile "$installDir\laptop_bridge_v2.py" -UseBasicParsing
Write-Host "  Saved: $installDir\laptop_bridge_v2.py ($((Get-Item $installDir\laptop_bridge_v2.py).Length) bytes)"

Write-Host ""
Write-Host "=== Step 2: Stop v1 bridge ==="
$v1 = Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.CommandLine -like "*laptop_bridge*version*2*" -or $_.CommandLine -like "*laptop_bridge.py*" }
foreach ($p in $v1) {
    Write-Host "  Stopping PID $($p.Id): $($p.CommandLine.Substring(0, [Math]::Min(80, $p.CommandLine.Length)))"
    Stop-Process -Id $p.Id -Force
}
Start-Sleep -Seconds 2

# Also check for any uvicorn
$uvicorn = Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.CommandLine -like "*uvicorn*" -and $_.CommandLine -like "*8765*" }
foreach ($p in $uvicorn) {
    Write-Host "  Stopping uvicorn PID $($p.Id)"
    Stop-Process -Id $p.Id -Force
}
Start-Sleep -Seconds 2

# Verify port free
$portInUse = Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue
if ($portInUse) {
    Write-Host "  ⚠️  Port 8765 still in use by PID $($portInUse.OwningProcess)"
    Stop-Process -Id $portInUse.OwningProcess -Force
    Start-Sleep -Seconds 2
} else {
    Write-Host "  ✅ Port 8765 free"
}

Write-Host ""
Write-Host "=== Step 3: Create v2 launcher ==="
$launcher = @"
@echo off
cd /d "$installDir"
"C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe" -m uvicorn laptop_bridge_v2:app --host 127.0.0.1 --port 8765 --app-dir "$installDir" > "$logDir\bridge_v2.log" 2>&1
"@
$launcherPath = "$installDir\start_bridge_v2.cmd"
Set-Content -Path $launcherPath -Value $launcher
Write-Host "  Created: $launcherPath"

Write-Host ""
Write-Host "=== Step 4: Start v2 ==="
$proc = Start-Process -FilePath $launcherPath -WindowStyle Hidden -PassThru
Write-Host "  Started PID $($proc.Id)"

Start-Sleep -Seconds 6

Write-Host ""
Write-Host "=== Step 5: Verify ==="
try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/ping" -Method Get
    Write-Host "✅ Bridge v2 alive: version=$($r.version), host=$($r.hostname)"
} catch {
    Write-Host "❌ Bridge not responding: $_"
    if (Test-Path "$logDir\bridge_v2.log") {
        Get-Content "$logDir\bridge_v2.log" -Tail 20
    }
}

Write-Host ""
Write-Host "=== Step 6: Test queue endpoints ==="
$headers = @{ Authorization = "Bearer hm-bridge-2026-secure-token-v3" }
$body = @{ task_type = "shell"; payload = @{ command = "echo hello from v2 queue" } } | ConvertTo-Json
try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/queue/submit" -Method Post -Headers $headers -ContentType "application/json" -Body $body
    Write-Host "✅ Submitted task #$($r.task_id), pending=$($r.pending_count)"
    Start-Sleep -Seconds 4
    $r2 = Invoke-RestMethod -Uri "http://127.0.0.1:8765/queue/result/$($r.task_id)" -Method Get -Headers $headers
    Write-Host "✅ Result: status=$($r2.status), stdout='$($r2.result.stdout.Trim())'"
} catch {
    Write-Host "❌ Queue test failed: $_"
}
