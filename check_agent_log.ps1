$logDir = "C:\Users\abdul\AppData\Local\hermes\logs"
$envDir = "$env:USERPROFILE\.hermes"

Write-Host "=== Latest agent.log (last 50 lines) ==="
if (Test-Path "$logDir\agent.log") {
    Get-Content "$logDir\agent.log" -Tail 50
}

Write-Host ""
Write-Host "=== errors.log ==="
if (Test-Path "$logDir\errors.log") {
    Get-Content "$logDir\errors.log" -Tail 30
}

Write-Host ""
Write-Host "=== Check for gateway.log anywhere ==="
Get-ChildItem "C:\Users\abdul\AppData\Local\hermes\" -Recurse -Filter "*.log" -EA SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize

Write-Host ""
Write-Host "=== Kills ALL hermes, then restart clean ==="
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" } | Stop-Process -Force
Get-Process -Name "hermes*" -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Write-Host "  All killed"

# Now run with explicit log
$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$env:HERMES_HOME = "C:\Users\abdul\AppData\Local\hermes"
$env:PATH = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts;$env:PATH"

$out = "$envDir\gateway_clean.out"
$err = "$envDir\gateway_clean.err"
Remove-Item $out, $err -EA SilentlyContinue

Write-Host ""
Write-Host "=== Start gateway in background (logs to files) ==="
$proc = Start-Process -FilePath $hermes -ArgumentList "gateway" -WorkingDirectory $envDir -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
Write-Host "  PID: $($proc.Id)"
Start-Sleep -Seconds 20

$alive = -not $proc.HasExited
Write-Host "  Alive after 20s: $alive"
Write-Host ""
Write-Host "=== stdout ($((Get-Item $out -EA SilentlyContinue).Length) bytes) ==="
if (Test-Path $out) { Get-Content $out }
Write-Host ""
Write-Host "=== stderr ($((Get-Item $err -EA SilentlyContinue).Length) bytes) ==="
if (Test-Path $err) { Get-Content $err }

# Don't kill it - leave it running
Write-Host ""
Write-Host "=== Now check Telegram ==="
Start-Sleep -Seconds 3
$resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/getUpdates?offset=571924368"
$resp.result | ForEach-Object {
    Write-Host "  msg: $($_.message.text) (id: $($_.update_id))"
}
