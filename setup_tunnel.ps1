$installDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$tunnelDir = "$installDir\tunnel"

New-Item -ItemType Directory -Path $tunnelDir -Force | Out-Null

# Check if cloudflared exists
$cf = Get-Command "cloudflared" -EA SilentlyContinue
if (-not $cf) {
    Write-Host "=== Downloading cloudflared ==="
    $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    $dest = "$tunnelDir\cloudflared.exe"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    Write-Host "  Saved: $dest"
} else {
    Write-Host "cloudflared already installed: $($cf.Source)"
}

# Start tunnel in background pointing to our bridge
Write-Host ""
Write-Host "=== Starting cloudflared tunnel ==="
$logFile = "$tunnelDir\tunnel.log"
$errFile = "$tunnelDir\tunnel.err"
Remove-Item $logFile, $errFile -EA SilentlyContinue

$cfPath = "$tunnelDir\cloudflared.exe"
if (-not (Test-Path $cfPath)) { $cfPath = "cloudflared" }

$proc = Start-Process -FilePath $cfPath -ArgumentList "tunnel","--url","http://127.0.0.1:8765","--no-autoupdate" -WorkingDirectory $tunnelDir -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError $errFile -PassThru
Write-Host "  Tunnel PID: $($proc.Id)"

# Wait for URL to appear in log
$tunnelUrl = $null
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    if (Test-Path $errFile) {
        $content = Get-Content $errFile -Raw -EA SilentlyContinue
        if ($content -match 'https://[a-zA-Z0-9\-]+\.trycloudflare\.com') {
            $tunnelUrl = $matches[0]
            break
        }
    }
    Write-Host "  ...waiting ($($i+1)/30)"
}

if ($tunnelUrl) {
    Write-Host ""
    Write-Host "✅ TUNNEL URL: $tunnelUrl"
    # Save for later
    Set-Content -Path "$tunnelDir\url.txt" -Value $tunnelUrl
} else {
    Write-Host ""
    Write-Host "❌ Tunnel URL not found in 60s"
    if (Test-Path $errFile) { Get-Content $errFile -Tail 30 }
}

# Test it
if ($tunnelUrl) {
    Write-Host ""
    Write-Host "=== Test tunnel ==="
    try {
        $r = Invoke-RestMethod -Uri "$tunnelUrl/ping" -Method Get
        Write-Host "✅ Public /ping: pong=$($r.pong)"
    } catch {
        Write-Host "❌ /ping via tunnel: $_"
    }
    try {
        $headers = @{ Authorization = "Bearer hm-bridge-2026-secure-token-v3" }
        $body = @{ command = "echo tunnel is alive" } | ConvertTo-Json
        $r = Invoke-RestMethod -Uri "$tunnelUrl/shell" -Method Post -Headers $headers -ContentType "application/json" -Body $body
        Write-Host "✅ Public /shell: '$($r.stdout.Trim())'"
    } catch {
        Write-Host "❌ /shell via tunnel: $_"
    }
}
