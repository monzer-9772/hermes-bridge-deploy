# Full deployment: download v5_visual.py + start cloudflared + report URL
$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes_sync"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$cf = "$dir\cloudflared.exe"

Write-Host "=== Hermes Bridge v5 Visual - Full Deploy ==="

# 1. Kill anything on 8765
Write-Host "[1/6] Killing port 8765 processes..."
$conn = Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue
if ($conn) {
    $conn | ForEach-Object {
        Write-Host "  Killing PID $($_.OwningProcess)"
        try { Stop-Process -Id $_.OwningProcess -Force } catch {}
    }
    Start-Sleep -Seconds 2
}

# 2. Kill any cloudflared
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 3. Download v5_visual.py
Write-Host "[2/6] Downloading v5_visual.py..."
$v5path = "$dir\v5_visual.py"
$url = "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/v5_visual.py"
try {
    Invoke-WebRequest -Uri $url -OutFile $v5path -UseBasicParsing
    Write-Host "  OK: $((Get-Item $v5path).Length) bytes"
} catch {
    Write-Host "  FAIL: $_"
    exit 1
}

# 4. Install deps
Write-Host "[3/6] Installing deps..."
$req = "$dir\requirements.txt"
@("aiohttp", "websockets", "requests", "Pillow", "mss") | ForEach-Object {
    & $py -m pip install --quiet $_
}
Write-Host "  OK"

# 5. Start v5_visual.py
Write-Host "[4/6] Starting v5_visual.py..."
$env:PORT = "8765"
$env:AUTH_TOKEN = "hm-bridge-2026-secure-token-v3"
$env:DEFAULT_LAPTOP_ID = "abdul@abd"
$proc = Start-Process -FilePath $py `
    -ArgumentList "-u", "$dir\v5_visual.py" `
    -WorkingDirectory $dir `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$dir\v5.log" `
    -RedirectStandardError "$dir\v5.err" `
    -PassThru
Write-Host "  PID: $($proc.Id)"

Start-Sleep -Seconds 4

# 6. Verify port
$conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
if ($conn) {
    Write-Host "  Port 8765: LISTENING"
} else {
    Write-Host "  Port 8765: NOT listening - check v5.err"
    if (Test-Path "$dir\v5.err") { Get-Content "$dir\v5.err" | Select-Object -First 20 }
    exit 1
}

# 7. Start cloudflared
Write-Host "[5/6] Starting cloudflared tunnel..."
$cfProc = Start-Process -FilePath $cf `
    -ArgumentList "tunnel", "--url", "http://localhost:8765", "--no-autoupdate", "--logfile", "$dir\cf.log" `
    -WindowStyle Hidden `
    -PassThru
Write-Host "  cloudflared PID: $($cfProc.Id)"

# Wait for URL
Write-Host "[6/6] Waiting for tunnel URL (up to 30s)..."
$urlFile = "$dir\tunnel_url.txt"
for ($i=0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $cfLog = "$dir\cf.log") {
        $content = Get-Content $cfLog -Raw -ErrorAction SilentlyContinue
        if ($content -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
            $tunnelUrl = $matches[0]
            Write-Host "  Tunnel URL: $tunnelUrl"
            $tunnelUrl | Out-File $urlFile -Encoding ASCII
            break
        }
    }
    Write-Host "  ...waiting ($i)"
}

if (-not $tunnelUrl) {
    Write-Host "  FAILED to get tunnel URL in 30s"
    Write-Host "  cf.log content:"
    if (Test-Path "$dir\cf.log") { Get-Content "$dir\cf.log" -Tail 20 }
    exit 1
}

Write-Host ""
Write-Host "=== DEPLOYMENT COMPLETE ==="
Write-Host "  Tunnel URL: $tunnelUrl"
Write-Host "  Health: $tunnelUrl/health"
Write-Host "  Viewer: $tunnelUrl/screencast.html"
Write-Host ""
Write-Host "Saving URL to GitHub via Gist API..."
$token = "ghp_K3XgGfQXG7JZWpNNqJ08GEoBtwUopc3a1FYS"  # placeholder, need real
# Actually we'll let server fetch from local file
$urlFile | Write-Host
