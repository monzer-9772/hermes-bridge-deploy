# Hermes Bridge v5 - Self-contained deploy script
# Downloads v5_visual.py from GitHub and starts it

$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes-sync"
$url = "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/v5_visual.py"

# Create dir if missing
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-Host "Created: $dir"
}

# Download v5_visual.py
Write-Host "Downloading v5_visual.py..."
Invoke-WebRequest -Uri $url -OutFile "$dir\v5_visual.py" -UseBasicParsing
Write-Host "  Size: $((Get-Item "$dir\v5_visual.py").Length) bytes"

# Stop existing bridge agents
Write-Host "Stopping existing bridge agents..."
Get-Process python -ErrorAction SilentlyContinue | Where-Object { 
    try { $_.CommandLine -like "*bridge_agent*" } catch { $false }
} | ForEach-Object {
    Write-Host "  Stopping PID $($_.Id)"
    Stop-Process -Id $_.Id -Force
}
Start-Sleep -Seconds 2

# Start v5_visual.py
Write-Host "Starting v5_visual.py..."
$env:PORT = "8765"
$proc = Start-Process -FilePath "python" `
    -ArgumentList "$dir\v5_visual.py" `
    -WorkingDirectory $dir `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$dir\v5.log" `
    -RedirectStandardError "$dir\v5.err" `
    -PassThru
Write-Host "  PID: $($proc.Id)"

# Wait and verify
Start-Sleep -Seconds 4
Write-Host ""
Write-Host "=== Health check ==="
try {
    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:8765/health" -TimeoutSec 5
    Write-Host "  Response: $resp"
} catch {
    Write-Host "  Server not responding yet. Check $dir\v5.log"
    if (Test-Path "$dir\v5.log") {
        Write-Host "  --- v5.log (last 10 lines) ---"
        Get-Content "$dir\v5.log" -Tail 10
    }
}
