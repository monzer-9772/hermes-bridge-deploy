$dir = "C:\Users\mmh\hermes_sync"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

# 1. Force kill
Get-NetTCPConnection -LocalPort 8765 -EA SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue }
Get-Process cloudflared -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2

# 2. Delete old file completely
$path = "$dir\v5_visual.py"
if (Test-Path $path) { Remove-Item $path -Force }

# 3. Fresh download
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/v5_visual.py" -OutFile $path -UseBasicParsing
$size = (Get-Item $path).Length
Write-Host "Size: $size"

# 4. Check syntax
$check = & $py -c "import ast; ast.parse(open(r'$path', encoding='utf-8').read()); print('OK')" 2>&1
Write-Host "Syntax: $check"

# 5. Start only if syntax OK
if ($check -eq "OK") {
    $env:PORT = "8765"
    $proc = Start-Process -FilePath $py -ArgumentList "-u", $path -WorkingDirectory $dir -WindowStyle Hidden -RedirectStandardOutput "$dir\v5.log" -RedirectStandardError "$dir\v5.err" -PassThru
    Write-Host "PID: $($proc.Id)"
    Start-Sleep 3
    $c = Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue
    if ($c) { Write-Host "OK_PORT" } else { Write-Host "FAIL"; if (Test-Path "$dir\v5.err") { Get-Content "$dir\v5.err" -Tail 10 } }
}
