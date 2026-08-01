Start-Sleep -Seconds 10

# Check Telegram updates to see if bot responded
$resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/getUpdates?offset=571924368"
Write-Host "=== Recent messages (last 5) ==="
$resp.result | Select-Object -Last 5 | ForEach-Object {
    Write-Host "  msg_id=$($_.message.message_id) text='$($_.message.text)'"
}

# Send a fresh /start
Write-Host ""
Write-Host "=== Sending fresh /start ==="
$body = @{ chat_id = 6457326492; text = "/start" } | ConvertTo-Json
$res = Invoke-RestMethod -Uri "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/sendMessage" -Method Post -ContentType "application/json" -Body $body
Write-Host "  sent: $($res.result.message_id)"

Start-Sleep -Seconds 10

# Check for response
$offset = $resp.result[-1].update_id + 1
$resp2 = Invoke-RestMethod -Uri "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/getUpdates?offset=$offset"
Write-Host ""
Write-Host "=== New messages after /start ==="
$resp2.result | ForEach-Object {
    Write-Host "  msg_id=$($_.message.message_id) text='$($_.message.text)'"
}

# Check the new log
Write-Host ""
Write-Host "=== Latest agent.log (last 20) ==="
$logDir = "C:\Users\abdul\AppData\Local\hermes\logs"
if (Test-Path "$logDir\agent.log") {
    Get-Content "$logDir\agent.log" -Tail 20
}
