# 1. Verify bridge responds
try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/ping" -Method Get
    Write-Host "✅ Bridge /ping: pong=$($r.pong), host=$($r.hostname), user=$($r.user)"
} catch {
    Write-Host "❌ /ping failed: $_"
}

# 2. Test /shell with auth
try {
    $headers = @{ Authorization = "Bearer hm-bridge-2026-secure-token-v3" }
    $body = @{ command = "echo hello from laptop bridge" } | ConvertTo-Json
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/shell" -Method Post -Headers $headers -ContentType "application/json" -Body $body
    Write-Host "✅ /shell: stdout='$($r.stdout.Trim())', returncode=$($r.returncode)"
} catch {
    Write-Host "❌ /shell failed: $_"
}

# 3. Test /shell WITHOUT auth (should fail with 401/403)
try {
    $body = @{ command = "whoami" } | ConvertTo-Json
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/shell" -Method Post -ContentType "application/json" -Body $body
    Write-Host "⚠️  /shell without auth should have been rejected but returned: $($r | ConvertTo-Json -Compress)"
} catch {
    Write-Host "✅ /shell auth check working: $_"
}

# 4. Test screenshot
try {
    $headers = @{ Authorization = "Bearer hm-bridge-2026-secure-token-v3" }
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/screenshot" -Method Post -Headers $headers -TimeoutSec 15
    $bytes = [Convert]::FromBase64String($r.image_base64)
    Write-Host "✅ /screenshot: $($r.width)x$($r.height), $($bytes.Length) bytes"
    # Save to a file we can show
    $path = "C:\Users\abdul\AppData\Local\hermes\bridge\logs\test_screenshot.png"
    [IO.File]::WriteAllBytes($path, $bytes)
    Write-Host "  Saved: $path"
} catch {
    Write-Host "❌ /screenshot failed: $_"
}

# 5. Show bridge logs
Write-Host ""
Write-Host "=== bridge.log (last 20) ==="
$logPath = "C:\Users\abdul\AppData\Local\hermes\bridge\logs\bridge.log"
if (Test-Path $logPath) {
    Get-Content $logPath -Tail 20
}
