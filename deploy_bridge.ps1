$installDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$envDir = "$env:USERPROFILE\.hermes"

# Kill any existing bridge
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.CommandLine -like "*laptop_bridge*" } | Stop-Process -Force
Start-Sleep -Seconds 2

# Create bridge dir
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path "$installDir\logs" -Force | Out-Null

# Download the bridge code
$code = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/laptop_bridge.py" -UseBasicParsing).Content
Set-Content -Path "$installDir\laptop_bridge.py" -Value $code -Encoding UTF8
Write-Host "Downloaded laptop_bridge.py"

# Install deps (FastAPI, uvicorn, mss, pillow)
$py = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe"
Write-Host "Installing bridge dependencies..."
& $py -m pip install --quiet fastapi uvicorn[standard] mss pillow httpx 2>&1 | Select-Object -Last 5
Write-Host "  Done"

# Create start script
@"
@echo off
set "BRIDGE_PORT=8765"
set "BRIDGE_TOKEN=hm-bridge-2026-secure-token-v3"
set "BRIDGE_WORKDIR=C:\Users\abdul"
cd /d C:\Users\abdul\AppData\Local\hermes\bridge
C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe laptop_bridge.py >> logs\bridge.log 2>&1
"@ | Set-Content "$installDir\start_bridge.cmd" -Encoding UTF8

# Start bridge
$proc = Start-Process -FilePath "$installDir\start_bridge.cmd" -WindowStyle Hidden -PassThru
Write-Host "  Started bridge (PID: $($proc.Id))"

Start-Sleep -Seconds 5

# Test
try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/ping" -Method Get
    Write-Host ""
    Write-Host "✅ Bridge alive: $($r.pong), host=$($r.hostname), user=$($r.user)"
} catch {
    Write-Host ""
    Write-Host "❌ Bridge not responding: $_"
    Write-Host "  Last log:"
    Get-Content "$installDir\logs\bridge.log" -Tail 20
}
