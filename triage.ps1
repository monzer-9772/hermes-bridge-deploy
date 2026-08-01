# Triage: find what went wrong
$ErrorActionPreference = "Continue"
$InstallDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$PythonExe = "C:\Users\abdul\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

Write-Host "=== TRIAGE ===" -ForegroundColor Cyan

# 1. Check Python
Write-Host ""
Write-Host "1. Python version:" -ForegroundColor Yellow
& $PythonExe --version 2>&1

# 2. Try to import bridge manually
Write-Host ""
Write-Host "2. Test bridge import:" -ForegroundColor Yellow
Set-Location $InstallDir
$importResult = & $PythonExe -c "import laptop_bridge_v3; print('OK', dir(laptop_bridge_v3))" 2>&1
Write-Host $importResult

# 3. Try to start in foreground for 3s
Write-Host ""
Write-Host "3. Try foreground start (3s):" -ForegroundColor Yellow
$proc = Start-Process -FilePath $PythonExe -ArgumentList "-m", "uvicorn", "laptop_bridge_v3:app", "--host", "127.0.0.1", "--port", "8765" -WorkingDirectory $InstallDir -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\bridge_out.log" -RedirectStandardError "$env:TEMP\bridge_err.log"
Start-Sleep -Seconds 4
if (-not $proc.HasExited) {
    Write-Host "Process still running (PID $($proc.Id))" -ForegroundColor Green
    Stop-Process -Id $proc.Id -Force
} else {
    Write-Host "Process exited with code $($proc.ExitCode)" -ForegroundColor Red
}

# 4. Show output
Write-Host ""
Write-Host "4. STDOUT:" -ForegroundColor Yellow
if (Test-Path "$env:TEMP\bridge_out.log") { Get-Content "$env:TEMP\bridge_out.log" }
Write-Host ""
Write-Host "5. STDERR:" -ForegroundColor Yellow
if (Test-Path "$env:TEMP\bridge_err.log") { Get-Content "$env:TEMP\bridge_err.log" }

# 6. Check port
Write-Host ""
Write-Host "6. Port 8765:" -ForegroundColor Yellow
$conn = Test-NetConnection -ComputerName 127.0.0.1 -Port 8765 -WarningAction SilentlyContinue
Write-Host "TcpTestSucceeded: $($conn.TcpTestSucceeded)"

Write-Host ""
Write-Host "=== Press Enter to close ==="
pause
