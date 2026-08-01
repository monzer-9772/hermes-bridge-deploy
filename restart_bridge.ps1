# Hermes Bridge v3.1 Restart Script
# Pure PowerShell - works without batch parsing issues

$ErrorActionPreference = "Continue"
$InstallDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$PythonExe = "C:\Users\abdul\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

Write-Host "=== Hermes Bridge v3.1 Restart ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $PythonExe)) {
    Write-Host "Python not found at $PythonExe" -ForegroundColor Red
    $PythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $PythonExe) {
        Write-Host "No Python in PATH. Aborting." -ForegroundColor Red
        pause
        exit 1
    }
}
Write-Host "Python: $PythonExe" -ForegroundColor Green

# Step 1: Kill existing bridges
Write-Host ""
Write-Host "Step 1: Killing existing bridges..." -ForegroundColor Yellow
$procs = Get-Process python -ErrorAction SilentlyContinue
$killed = 0
foreach ($p in $procs) {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)").CommandLine
        if ($cmd -like '*laptop_bridge*') {
            Write-Host "  Killing PID $($p.Id)"
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $killed++
        }
    } catch {}
}
Write-Host "Killed $killed bridges"
Start-Sleep -Seconds 2

# Step 2: Download v3.1
Write-Host ""
Write-Host "Step 2: Downloading v3.1 from GitHub..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/laptop_bridge_v3.py" -OutFile "$InstallDir\laptop_bridge_v3.py" -UseBasicParsing
    Write-Host "Downloaded"
} catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    pause
    exit 1
}

# Step 3: Verify
Write-Host ""
Write-Host "Step 3: Verifying v3.1..." -ForegroundColor Yellow
$content = Get-Content "$InstallDir\laptop_bridge_v3.py" -Raw
if ($content -like '*navigate.ps1*') {
    Write-Host "v3.1 verified (has navigate.ps1)" -ForegroundColor Green
} else {
    Write-Host "ERROR: v3.1 missing navigate.ps1" -ForegroundColor Red
    pause
    exit 1
}

# Step 4: Start bridge
Write-Host ""
Write-Host "Step 4: Starting bridge..." -ForegroundColor Yellow
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $PythonExe
$psi.Arguments = "-m uvicorn laptop_bridge_v3:app --host 127.0.0.1 --port 8765 --app-dir `"$InstallDir`""
$psi.WorkingDirectory = $InstallDir
$psi.UseShellExecute = $true
$psi.WindowStyle = "Hidden"
[System.Diagnostics.Process]::Start($psi) | Out-Null
Write-Host "Started"

# Step 5: Wait and ping
Write-Host ""
Write-Host "Step 5: Waiting 8s for bridge to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:8765/ping" -UseBasicParsing -TimeoutSec 5
    Write-Host "Bridge status: $($r.StatusCode) $($r.Content)" -ForegroundColor Green
} catch {
    Write-Host "Bridge NOT responding: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Done! Tunnel should auto-connect to: https://genealogy-secondary-rate-aims.trycloudflare.com" -ForegroundColor Cyan
Write-Host "(If tunnel also died, you'll need to restart it too)"
pause
