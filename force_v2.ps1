$dir = "C:\Users\mmh\hermes_sync"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$url = "https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/v5_visual.py"

# 1. Kill
Get-NetTCPConnection -LocalPort 8765 -EA SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue }
Get-Process cloudflared -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2

# 2. Delete + Download with cache-busting headers
$path = "$dir\v5_visual.py"
if (Test-Path $path) { Remove-Item $path -Force }
$cb = Get-Random -Minimum 100000 -Maximum 999999
$dlUrl = "$url?nocache=$cb"
Write-Host "Downloading: $dlUrl"
$req = [System.Net.HttpWebRequest]::Create($dlUrl)
$req.Headers.Add("Cache-Control", "no-cache")
$req.Headers.Add("Pragma", "no-cache")
$req.Timeout = 30000
$resp = $req.GetResponse()
$stream = $resp.GetResponseStream()
$reader = New-Object System.IO.StreamReader($stream)
$content = $reader.ReadToEnd()
$reader.Close()
$resp.Close()
[System.IO.File]::WriteAllText($path, $content)
Write-Host "Size: $((Get-Item $path).Length)"

# 3. Syntax check
$check = & $py -c "import ast; ast.parse(open(r'$path', encoding='utf-8').read()); print('OK')" 2>&1
Write-Host "Syntax: $check"

# 4. Start
if ($check -eq "OK") {
    $env:PORT = "8765"
    $proc = Start-Process -FilePath $py -ArgumentList "-u", $path -WorkingDirectory $dir -WindowStyle Hidden -RedirectStandardOutput "$dir\v5.log" -RedirectStandardError "$dir\v5.err" -PassThru
    Write-Host "PID: $($proc.Id)"
    Start-Sleep 3
    $c = Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue
    if ($c) { Write-Host "OK_PORT" } else { Write-Host "FAIL" }
}
