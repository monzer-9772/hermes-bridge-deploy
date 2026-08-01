# Hermes Bridge - Clean restart with correct paths
$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes_sync\v4"  # CORRECT path: underscore, with \v4\
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$cloudflared = "$dir\..\cloudflared.exe"

Write-Host "=== Hermes Bridge Clean Restart ==="
Write-Host ""

# 1. Kill all watchdog zombies
Write-Host "[1/5] Killing watchdog zombies..."
$watchdogs = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
    try { $_.CommandLine -like "*watchdog.py*" } catch { $false }
}
$killed = 0
foreach ($w in $watchdogs) {
    try { Stop-Process -Id $w.Id -Force -ErrorAction SilentlyContinue; $killed++ } catch {}
}
Write-Host "  Killed $killed watchdog processes"

# 2. Kill bridge_agent (but NOT launcher)
Write-Host "[2/5] Killing bridge_agent..."
Get-Process python -ErrorAction SilentlyContinue | Where-Object {
    try { $_.CommandLine -like "*bridge_agent*" } catch { $false }
} | ForEach-Object {
    Write-Host "  Killing PID $($_.Id)"
    try { Stop-Process -Id $_.Id -Force } catch {}
}

# 3. Kill any cloudflared
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 4. Verify paths
Write-Host "[3/5] Verifying paths..."
if (-not (Test-Path $dir)) {
    Write-Host "  ERROR: $dir not found"
    exit 1
}
Write-Host "  Dir OK: $dir"
if (-not (Test-Path $py)) {
    Write-Host "  ERROR: python not found at $py"
    exit 1
}
Write-Host "  Python OK: $py"
$cloudflared = Get-ChildItem "$dir\.." -Filter "cloudflared.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cloudflared) {
    $cloudflared = $cloudflared.FullName
    Write-Host "  cloudflared: $cloudflared"
} else {
    Write-Host "  cloudflared: NOT FOUND in parent dir"
    $cloudflared = $null
}

# 5. Start bridge_agent
Write-Host "[4/5] Starting bridge_agent.py..."
$env:PORT = "8765"
$proc = Start-Process -FilePath $py `
    -ArgumentList "-u", "$dir\bridge_agent.py" `
    -WorkingDirectory $dir `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$dir\bridge.log" `
    -RedirectStandardError "$dir\bridge.err" `
    -PassThru
Write-Host "  PID: $($proc.Id)"

Start-Sleep -Seconds 3

# 6. Start cloudflared if available
if ($cloudflared) {
    Write-Host "[5/5] Starting cloudflared tunnel..."
    $cfProc = Start-Process -FilePath $cloudflared `
        -ArgumentList "tunnel", "--url", "http://localhost:8765", "--no-autoupdate" `
        -WindowStyle Hidden `
        -RedirectStandardOutput "$dir\cf.log" `
        -RedirectStandardError "$dir\cf.err" `
        -PassThru
    Write-Host "  cloudflared PID: $($cfProc.Id)"
} else {
    Write-Host "[5/5] Skipping cloudflared (not found)"
}

Write-Host ""
Write-Host "=== Verifying ==="
Start-Sleep -Seconds 3
$conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
if ($conn) {
    Write-Host "Port 8765: LISTENING (PID $($conn.OwningProcess))"
} else {
    Write-Host "Port 8765: NOT listening"
}
Write-Host ""
Write-Host "=== Bridge log (last 10) ==="
if (Test-Path "$dir\bridge.log") {
    Get-Content "$dir\bridge.log" -Tail 10
} else {
    Write-Host "  No log yet"
}
