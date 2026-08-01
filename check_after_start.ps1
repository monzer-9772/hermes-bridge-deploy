# Check Telegram messages
$offset = "571924370"  # after the last /start we sent
$resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/getUpdates?offset=$offset"
Write-Host "=== Recent updates ==="
$resp.result | ForEach-Object {
    $t = $_.message.text
    if ($t.Length -gt 100) { $t = $t.Substring(0, 100) + "..." }
    Write-Host "  msg_id=$($_.message.message_id) text='$t'"
}

# Check gateway is still running
$proc = Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" }
if ($proc) {
    Write-Host ""
    Write-Host "=== Gateway processes (should be 1+) ==="
    $proc | Format-Table Id, ProcessName, StartTime
} else {
    Write-Host "  No gateway running!"
}

# Check stderr latest
$errFile = "$env:USERPROFILE\.hermes\gateway_v4.err"
if (Test-Path $errFile) {
    Write-Host ""
    Write-Host "=== gateway_v4.err (last 20) ==="
    Get-Content $errFile -Tail 20
}

# Check agent.log latest
$agentLog = "C:\Users\abdul\AppData\Local\hermes\logs\agent.log"
if (Test-Path $agentLog) {
    Write-Host ""
    Write-Host "=== agent.log (last 30) ==="
    Get-Content $agentLog -Tail 30
}
