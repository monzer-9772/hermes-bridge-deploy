# Use ensurepip to bootstrap pip, then install mss + pillow
$py = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe"

Write-Host "=== Bootstrap pip ==="
& $py -m ensurepip --upgrade 2>&1 | Select-Object -Last 5
Write-Host ""

Write-Host "=== Install mss + pillow ==="
& $py -m pip install --quiet mss pillow 2>&1 | Select-Object -Last 10
Write-Host ""

Write-Host "=== Verify ==="
& $py -c "import mss, PIL; print(f'mss={mss.__version__ if hasattr(mss,chr(0x5F)+chr(0x5F)+chr(118)+chr(101)+chr(114)+chr(115)+chr(105)+chr(111)+chr(110)+chr(0x5F)+chr(0x5F)) else \"ok\"}, PIL={PIL.__version__}')"

Write-Host ""
Write-Host "=== Restart bridge ==="
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.CommandLine -like "*laptop_bridge*" } | Stop-Process -Force
Start-Sleep -Seconds 2

$installDir = "C:\Users\abdul\AppData\Local\hermes\bridge"
$proc = Start-Process -FilePath "$installDir\start_bridge.cmd" -WindowStyle Hidden -PassThru
Write-Host "  Started bridge (PID: $($proc.Id))"

Start-Sleep -Seconds 5

# Test screenshot
try {
    $headers = @{ Authorization = "Bearer hm-bridge-2026-secure-token-v3" }
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8765/screenshot" -Method Post -Headers $headers -TimeoutSec 15
    $bytes = [Convert]::FromBase64String($r.image_base64)
    Write-Host "✅ /screenshot: $($r.width)x$($r.height), $($bytes.Length) bytes"
    $path = "C:\Users\abdul\AppData\Local\hermes\bridge\logs\test_screenshot.png"
    [IO.File]::WriteAllBytes($path, $bytes)
    Write-Host "  Saved: $path"
} catch {
    Write-Host "❌ /screenshot failed: $_"
}
