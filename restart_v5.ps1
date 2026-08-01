$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes_sync"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

# Stop old v5
Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue } catch {}
}
Start-Sleep -Seconds 2

# Download latest v5
$url = "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/v5_visual.py"
Invoke-WebRequest -Uri $url -OutFile "$dir\v5_visual.py" -UseBasicParsing
Write-Host "Downloaded v5: $((Get-Item "$dir\v5_visual.py").Length) bytes"

# Start v5
$env:PORT = "8765"
$proc = Start-Process -FilePath $py `
    -ArgumentList "-u", "$dir\v5_visual.py" `
    -WorkingDirectory $dir `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$dir\v5.log" `
    -RedirectStandardError "$dir\v5.err" `
    -PassThru
Write-Host "v5 PID: $($proc.Id)"
Start-Sleep -Seconds 3

$conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
if ($conn) { Write-Host "Port 8765: LISTENING" } else { Write-Host "FAIL"; if (Test-Path "$dir\v5.err") { Get-Content "$dir\v5.err" -Tail 10 } }
