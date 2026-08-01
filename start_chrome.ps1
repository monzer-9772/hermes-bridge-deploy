# Start Chrome with remote debugging
$dir = "C:\Users\mmh\hermes_sync"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

# Find Chrome
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) {
    $chrome = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
}
if (-not (Test-Path $chrome)) {
    $chrome = "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
}
if (-not (Test-Path $chrome)) {
    Write-Host "Chrome not found"
    exit 1
}
Write-Host "Chrome: $chrome"

# Kill any existing Chrome with remote-debugging
Get-Process chrome -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*remote-debugging*"
} | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Start Chrome with remote debugging
Write-Host "Starting Chrome with --remote-debugging-port=9222..."
$proc = Start-Process -FilePath $chrome `
    -ArgumentList "--remote-debugging-port=9222", "--remote-allow-origins=*", "about:blank" `
    -PassThru
Write-Host "  PID: $($proc.Id)"

Start-Sleep -Seconds 3

# Verify
try {
    $tabs = Invoke-RestMethod -Uri "http://127.0.0.1:9222/json" -TimeoutSec 5
    Write-Host "  Tabs: $($tabs.Count)"
    $tabs | ForEach-Object { Write-Host "    $($_.title) - $($_.url)" }
} catch {
    Write-Host "  Chrome not responding: $($_.Exception.Message)"
}
