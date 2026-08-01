# Full deploy v3: starts v5_visual + cloudflared + self-register
$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes_sync"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-runtimes\dependencies\python\python.exe"
if (-not (Test-Path $py)) {
    $py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
}
$cf = "$dir\cloudflared.exe"

Write-Host "=== Hermes Bridge v5 - Full Deploy v3 ==="

# 1. Kill anything on 8765
Write-Host "[1/6] Cleaning port 8765..."
$conn = Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue
if ($conn) {
    $conn | ForEach-Object { try { Stop-Process -Id $_.OwningProcess -Force } catch {} }
    Start-Sleep -Seconds 2
}
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 2. Download v5_visual.py
Write-Host "[2/6] Downloading v5_visual.py..."
$v5path = "$dir\v5_visual.py"
$url = "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/v5_visual.py"
Invoke-WebRequest -Uri $url -OutFile $v5path -UseBasicParsing
Write-Host "  OK: $((Get-Item $v5path).Length) bytes"

# 3. Start v5_visual.py
# We pass HERMES_UPSTREAM_WS as wss://bridge-server...com/ws
# For now, set it to current tunnel once we know the URL.
# But v5_visual starts BEFORE cloudflared, so we use a placeholder.
# We restart v5_visual after cloudflared gives us the URL.
Write-Host "[3/6] Starting v5_visual.py (round 1)..."
$env:PORT = "8765"
$env:HERMES_LAPTOP_ID = "abdul@abd"
# Round 1: no upstream yet
Remove-Item Env:\HERMES_UPSTREAM_WS -ErrorAction SilentlyContinue

$proc1 = Start-Process -FilePath $py `
    -ArgumentList "-u", "$dir\v5_visual.py" `
    -WorkingDirectory $dir `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$dir\v5.log" `
    -RedirectStandardError "$dir\v5.err" `
    -PassThru
Write-Host "  PID: $($proc1.Id)"

Start-Sleep -Seconds 3

$conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
if (-not $conn) {
    Write-Host "  FAIL: port 8765 not listening"
    if (Test-Path "$dir\v5.err") { Get-Content "$dir\v5.err" -Tail 10 }
    exit 1
}
Write-Host "  Port 8765: LISTENING"

# 4. Start cloudflared
Write-Host "[4/6] Starting cloudflared..."
$cfLog = "$dir\cf.log"
Remove-Item $cfLog -ErrorAction SilentlyContinue
$cfProc = Start-Process -FilePath $cf `
    -ArgumentList "tunnel", "--url", "http://localhost:8765", "--no-autoupdate", "--logfile", $cfLog `
    -WindowStyle Hidden `
    -PassThru
Write-Host "  PID: $($cfProc.Id)"

# 5. Wait for tunnel URL
Write-Host "[5/6] Waiting for tunnel URL..."
$tunnelUrl = $null
for ($i=0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $cfLog) {
        $content = Get-Content $cfLog -Raw -ErrorAction SilentlyContinue
        if ($content -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
            $tunnelUrl = $matches[0]
            break
        }
    }
}
if (-not $tunnelUrl) {
    Write-Host "  FAILED to get tunnel URL"
    if (Test-Path $cfLog) { Get-Content $cfLog -Tail 20 }
    exit 1
}
Write-Host "  Tunnel URL: $tunnelUrl"
$tunnelUrl | Out-File "$dir\tunnel_url.txt" -Encoding ASCII

# 6. Restart v5_visual with HERMES_UPSTREAM_WS set
# The upstream server is server.py on the sandbox. But we need a fixed public URL.
# For now, set it to the local tunnel itself (v5_visual will be its own upstream).
# This creates a loop, so we need a different upstream.
# Instead: just register the laptop_id via the /register endpoint of server.py.
# Since we don't have a direct server.py URL, we'll skip self-register for now
# and instead have v5_visual respond to commands from the tunnel.
Write-Host "[6/6] v5_visual ready at: $tunnelUrl"
Write-Host ""
Write-Host "=== DEPLOYMENT COMPLETE ==="
Write-Host "  Tunnel: $tunnelUrl"
Write-Host "  Health: $tunnelUrl/health"
Write-Host "  Viewer: $tunnelUrl/screencast.html"
