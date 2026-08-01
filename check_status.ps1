$dir = "C:\Users\mmh\hermes_sync"
Write-Host "=== Status check ==="
Write-Host ""
Write-Host "[1] Port 8765:"
$conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
if ($conn) { Write-Host "  LISTENING (PID $($conn.OwningProcess))" } else { Write-Host "  NOT listening" }

Write-Host ""
Write-Host "[2] v5.log (last 20):"
if (Test-Path "$dir\v5.log") { Get-Content "$dir\v5.log" -Tail 20 } else { Write-Host "  No v5.log" }

Write-Host ""
Write-Host "[3] v5.err (last 20):"
if (Test-Path "$dir\v5.err") { Get-Content "$dir\v5.err" -Tail 20 } else { Write-Host "  No v5.err" }

Write-Host ""
Write-Host "[4] cf.log (last 20):"
if (Test-Path "$dir\cf.log") { Get-Content "$dir\cf.log" -Tail 20 } else { Write-Host "  No cf.log" }

Write-Host ""
Write-Host "[5] tunnel_url.txt:"
if (Test-Path "$dir\tunnel_url.txt") { Get-Content "$dir\tunnel_url.txt" } else { Write-Host "  No tunnel_url.txt" }

Write-Host ""
Write-Host "[6] cloudflared process:"
$cf = Get-Process cloudflared -ErrorAction SilentlyContinue
if ($cf) { $cf | ForEach-Object { Write-Host "  PID $($_.Id)" } } else { Write-Host "  Not running" }

Write-Host ""
Write-Host "[7] Health check via tunnel (if URL exists):"
if (Test-Path "$dir\tunnel_url.txt") {
    $url = (Get-Content "$dir\tunnel_url.txt").Trim()
    Write-Host "  URL: $url"
    try {
        $r = Invoke-RestMethod -Uri "$url/health" -Headers @{Authorization="Bearer hm-bridge-2026-secure-token-v3"} -TimeoutSec 5
        Write-Host "  Health: $r"
    } catch { Write-Host "  Health: FAILED - $($_.Exception.Message)" }
}
