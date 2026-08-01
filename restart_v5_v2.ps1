$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes_sync"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

# Kill anything on 8765
$conn = Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue
if ($conn) {
    $conn | ForEach-Object { try { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue } catch {} }
}
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Download with cache buster
$url = "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/v5_visual.py?v=$((Get-Random))"
$v5path = "$dir\v5_visual.py"
Invoke-WebRequest -Uri $url -OutFile $v5path -UseBasicParsing
$size = (Get-Item $v5path).Length
Write-Host "Downloaded v5: $size bytes"

if ($size -lt 40000) {
    Write-Host "ERROR: file too small, download failed"
    exit 1
}

# Verify no IndentationError by parsing the file with Python
$check = & $py -c "import ast; ast.parse(open(r'$v5path', encoding='utf-8').read()); print('OK')" 2>&1
Write-Host "Syntax check: $check"

if ($check -ne "OK") {
    Write-Host "SYNTAX ERROR - aborting start"
    exit 1
}

# Start v5
$env:PORT = "8765"
$proc = Start-Process -FilePath $py `
    -ArgumentList "-u", "$v5path" `
    -WorkingDirectory $dir `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$dir\v5.log" `
    -RedirectStandardError "$dir\v5.err" `
    -PassThru
Write-Host "v5 PID: $($proc.Id)"

Start-Sleep -Seconds 3

$conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
if ($conn) {
    Write-Host "✅ Port 8765: LISTENING"
} else {
    Write-Host "❌ Port 8765: NOT listening"
    if (Test-Path "$dir\v5.err") {
        Write-Host "=== v5.err ==="
        Get-Content "$dir\v5.err" -Tail 15
    }
}
