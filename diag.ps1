# Diagnostic script - checks current state
$dir = "C:\Users\mmh\hermes-sync"
Write-Host "=== Hermes Bridge Diagnostic ==="
Write-Host ""
Write-Host "[1] Python location:"
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($py) { Write-Host "  $py" } else { Write-Host "  python NOT in PATH" }
$py2 = (Get-Command py -ErrorAction SilentlyContinue).Source
if ($py2) { Write-Host "  py: $py2" }

Write-Host ""
Write-Host "[2] Bridge dir:"
if (Test-Path $dir) {
    Write-Host "  EXISTS: $dir"
    Get-ChildItem $dir -Filter "*.py" | Select-Object -First 10 | ForEach-Object { 
        Write-Host "    $($_.Name) ($($_.Length) bytes)" 
    }
} else {
    Write-Host "  MISSING: $dir"
}

Write-Host ""
Write-Host "[3] v5_visual.py exists?"
$v5path = "$dir\v5_visual.py"
if (Test-Path $v5path) {
    Write-Host "  YES: $v5path ($((Get-Item $v5path).Length) bytes)"
} else {
    Write-Host "  NO"
}

Write-Host ""
Write-Host "[4] Python processes:"
Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $cl = $_.CommandLine
        Write-Host "  PID $($_.Id): $cl"
    } catch {
        Write-Host "  PID $($_.Id): (no access to CommandLine)"
    }
}

Write-Host ""
Write-Host "[5] Port 8765 listening?"
$conn = Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue
if ($conn) {
    $conn | ForEach-Object { Write-Host "  PID $($_.OwningProcess) on 8765" }
} else {
    Write-Host "  Nothing on 8765"
}

Write-Host ""
Write-Host "[6] cloudflared running?"
$cf = Get-Process cloudflared -ErrorAction SilentlyContinue
if ($cf) {
    $cf | ForEach-Object { Write-Host "  PID $($_.Id): $($_.StartTime)" }
} else {
    Write-Host "  No"
}

Write-Host ""
Write-Host "[7] GitHub connectivity test:"
try {
    $r = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/v5_visual.py" -UseBasicParsing -TimeoutSec 5
    Write-Host "  OK: HTTP $($r.StatusCode), $($r.Content.Length) bytes"
} catch {
    Write-Host "  FAIL: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "[8] v5.log (if exists):"
$v5log = "$dir\v5.log"
if (Test-Path $v5log) {
    Get-Content $v5log -Tail 20
} else {
    Write-Host "  No v5.log"
}
