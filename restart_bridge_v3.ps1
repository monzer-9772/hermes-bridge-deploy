# Hermes Bridge v3.1 Restart v3 - With diagnostic
$ErrorActionPreference = "Continue"
$InstallDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$PythonExe = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe"
$LogFile = "$env:TEMP\bridge_v3.log"

Write-Host "=== Hermes Bridge v3.1 v3 ===" -ForegroundColor Cyan
Write-Host "Log: $LogFile" -ForegroundColor Gray
"=== Started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $LogFile

if (-not (Test-Path $PythonExe)) {
    Write-Host "Python not found at $PythonExe" -ForegroundColor Red
    pause
    exit 1
}
Write-Host "Python: $PythonExe" -ForegroundColor Green
"Python: $PythonExe" | Out-File $LogFile -Append

# Test imports
Write-Host ""
Write-Host "Test imports..." -ForegroundColor Yellow
$testOutput = & $PythonExe -c "import sys; print('Python:', sys.version); import httpx; print('httpx:', httpx.__version__); import uvicorn; print('uvicorn:', uvicorn.__version__); import fastapi; print('fastapi:', fastapi.__version__)" 2>&1
$testOutput | Out-File $LogFile -Append
$testOutput | ForEach-Object { Write-Host "  $_" }

# Kill existing
Write-Host ""
Write-Host "Killing existing bridges..." -ForegroundColor Yellow
Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
        if ($cmd -like '*laptop_bridge*') {
            Write-Host "  Killing PID $($_.Id)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}
Start-Sleep -Seconds 2

# Verify bridge file
Write-Host ""
Write-Host "Verifying bridge file..." -ForegroundColor Yellow
$bridgePath = "$InstallDir\laptop_bridge_v3.py"
$content = Get-Content $bridgePath -Raw
if ($content -notlike '*navigate.ps1*') {
    Write-Host "Downloading v3.1..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/laptop_bridge_v3.py" -OutFile $bridgePath -UseBasicParsing
}
$content = Get-Content $bridgePath -Raw
if ($content -like '*navigate.ps1*') {
    Write-Host "v3.1 OK" -ForegroundColor Green
} else {
    Write-Host "FAILED" -ForegroundColor Red
    pause
    exit 1
}

# Start bridge with log capture
Write-Host ""
Write-Host "Starting bridge with log capture..." -ForegroundColor Yellow
Set-Location $InstallDir
$proc = Start-Process -FilePath $PythonExe `
    -ArgumentList "-m", "uvicorn", "laptop_bridge_v3:app", "--host", "127.0.0.1", "--port", "8765" `
    -WorkingDirectory $InstallDir `
    -NoNewWindow `
    -RedirectStandardOutput "$env:TEMP\bridge_v3_out.log" `
    -RedirectStandardError "$env:TEMP\bridge_v3_err.log" `
    -PassThru
Write-Host "Started PID $($proc.Id)" -ForegroundColor Green
"Started PID $($proc.Id) at $(Get-Date)" | Out-File $LogFile -Append

# Wait longer - 15s
Write-Host ""
Write-Host "Waiting 15s for bridge to start..." -ForegroundColor Yellow
for ($i = 1; $i -le 15; $i++) {
    Start-Sleep -Seconds 1
    Write-Host "." -NoNewline
}
Write-Host ""

# Check if process still running
if ($proc.HasExited) {
    Write-Host "PROCESS EXITED with code $($proc.ExitCode)" -ForegroundColor Red
    "PROCESS EXITED with code $($proc.ExitCode)" | Out-File $LogFile -Append
} else {
    Write-Host "Process still running (PID $($proc.Id))" -ForegroundColor Green
    "Process still running" | Out-File $LogFile -Append
}

# Show logs
Write-Host ""
Write-Host "STDOUT:" -ForegroundColor Yellow
if (Test-Path "$env:TEMP\bridge_v3_out.log") { Get-Content "$env:TEMP\bridge_v3_out.log" | Out-File $LogFile -Append; Get-Content "$env:TEMP\bridge_v3_out.log" }
Write-Host ""
Write-Host "STDERR:" -ForegroundColor Yellow
if (Test-Path "$env:TEMP\bridge_v3_err.log") { Get-Content "$env:TEMP\bridge_v3_err.log" | Out-File $LogFile -Append; Get-Content "$env:TEMP\bridge_v3_err.log" }

# Try ping
Write-Host ""
Write-Host "Testing /ping..." -ForegroundColor Yellow
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:8765/ping" -UseBasicParsing -TimeoutSec 5
    Write-Host "Bridge: $($r.StatusCode) $($r.Content)" -ForegroundColor Green
    "Bridge: $($r.StatusCode) $($r.Content)" | Out-File $LogFile -Append
} catch {
    Write-Host "Bridge NOT responding: $($_.Exception.Message)" -ForegroundColor Red
    "Bridge error: $($_.Exception.Message)" | Out-File $LogFile -Append
}

Write-Host ""
Write-Host "Full log: $LogFile" -ForegroundColor Cyan
pause
