$ErrorActionPreference = "Continue"
$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"

# Add hermes to PATH for this session
$env:PATH = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts;$env:PATH"

Write-Host "=== Installing service ==="
& $hermes gateway install 2>&1 | Out-String | Write-Host

Start-Sleep -Seconds 3

Write-Host ""
Write-Host "=== Starting service ==="
& $hermes gateway start 2>&1 | Out-String | Write-Host

Start-Sleep -Seconds 5

Write-Host ""
Write-Host "=== Service status ==="
Get-Service HermesGateway -EA SilentlyContinue | Format-List Name, Status, StartType
& $hermes gateway status 2>&1 | Out-String | Write-Host

Write-Host ""
Write-Host "=== Gateway log ==="
if (Test-Path "$envDir\gateway.log") { Get-Content "$envDir\gateway.log" -Tail 20 }
if (Test-Path "$envDir\gateway.err") { Write-Host "ERR:"; Get-Content "$envDir\gateway.err" -Tail 20 }

# Send test message
$token = "8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
$chatId = "6457326492"
$uri = "https://api.telegram.org/bot$token/sendMessage"
$body = @{ chat_id = $chatId; text = "Hermes Agent ready. Open @Kails9772bot and send /start" } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body | Out-Null
    Write-Host ""
    Write-Host "Test message sent!"
} catch {
    Write-Host "Send error: $_"
}
