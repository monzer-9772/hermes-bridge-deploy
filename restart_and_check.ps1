$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"
$logDir = "C:\Users\abdul\AppData\Local\hermes\logs"
$env:PATH = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts;$env:PATH"

Write-Host "=== Logs dir contents ==="
if (Test-Path $logDir) {
    Get-ChildItem $logDir -EA SilentlyContinue | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
}

Write-Host ""
Write-Host "=== All logs in hermes install ==="
Get-ChildItem "C:\Users\abdul\AppData\Local\hermes\" -Recurse -Filter "*.log" -EA SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize

Write-Host ""
Write-Host "=== gateway-service dir ==="
$gsDir = "C:\Users\abdul\AppData\Local\hermes\gateway-service"
if (Test-Path $gsDir) {
    Get-ChildItem $gsDir -EA SilentlyContinue | Format-Table -AutoSize
    Write-Host ""
    Write-Host "=== Hermes_Gateway.cmd content ==="
    Get-Content "$gsDir\Hermes_Gateway.cmd" -EA SilentlyContinue
}

Write-Host ""
Write-Host "=== Running gateway process ==="
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" } | Format-Table Id, ProcessName, StartTime, Path
Get-Process -Name "hermes*" -EA SilentlyContinue | Format-Table Id, ProcessName, StartTime, Path

Write-Host ""
Write-Host "=== Scheduled task ==="
Get-ScheduledTask -TaskName "Hermes_Gateway" -EA SilentlyContinue | Format-List

Write-Host ""
Write-Host "=== Stop and restart manually ==="
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" -or $_.CommandLine -like "*hermes*" } | Stop-Process -Force
Start-Sleep -Seconds 3

# Test gateway foreground 15 sec
$proc = Start-Process -FilePath $hermes -ArgumentList "gateway" -WorkingDirectory $envDir -WindowStyle Hidden -RedirectStandardOutput "$envDir\test_gw.out" -RedirectStandardError "$envDir\test_gw.err" -PassThru
Start-Sleep -Seconds 15
$alive = -not $proc.HasExited
Write-Host "  Gateway alive after 15s: $alive"
if (-not $alive) {
    Write-Host "  stderr:"
    if (Test-Path "$envDir\test_gw.err") { Get-Content "$envDir\test_gw.err" -Tail 30 }
}
Write-Host "  stdout:"
if (Test-Path "$envDir\test_gw.out") { Get-Content "$envDir\test_gw.out" -Tail 30 }
Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
