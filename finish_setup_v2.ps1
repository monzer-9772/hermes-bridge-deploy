# Wait for previous to finish if still running
$ErrorActionPreference = "Continue"
$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"

# Wait for any pending gateway test
Start-Sleep -Seconds 15

# Check if previous gateway died - look at log
Write-Host "=== Previous gateway log ==="
if (Test-Path "$envDir\gateway.err") { Get-Content "$envDir\gateway.err" -Tail 20 }
if (Test-Path "$envDir\gateway.log") { Get-Content "$envDir\gateway.log" -Tail 20 }

# Install as service
Write-Host ""
Write-Host "=== Installing as service ==="
& $hermes gateway install 2>&1 | Select-Object -Last 10

# Start service
Write-Host ""
Write-Host "=== Starting service ==="
& $hermes gateway start 2>&1 | Select-Object -Last 10
Start-Sleep -Seconds 8
& $hermes gateway status 2>&1

# Send test message
Write-Host ""
Write-Host "=== Sending test message to Telegram ==="
$token = "8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
$chatId = "6457326492"
$uri = "https://api.telegram.org/bot$token/sendMessage"
$body = @{ chat_id = $chatId; text = "Hermes Agent v0.19.1 is live. Send /start to your bot @Kails9772bot" } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body | Out-Null
    Write-Host "  Test message sent!"
} catch {
    Write-Host "  Error: $_"
}

Write-Host ""
Write-Host "=== DONE ==="
