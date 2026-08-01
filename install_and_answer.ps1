$ErrorActionPreference = "Continue"
$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"
$env:PATH = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts;$env:PATH"

Write-Host "=== Installing service (auto-answer Y) ==="
# Send Y to prompt
"y" | & $hermes gateway install 2>&1 | Out-String | Write-Host

Start-Sleep -Seconds 3

Write-Host ""
Write-Host "=== Service status ==="
Get-Service HermesGateway -EA SilentlyContinue | Format-List Name, Status, StartType

Write-Host ""
Write-Host "=== Gateway log ==="
if (Test-Path "$envDir\gateway.log") { Get-Content "$envDir\gateway.log" -Tail 30 }
if (Test-Path "$envDir\gateway.err") { Write-Host "ERR:"; Get-Content "$envDir\gateway.err" -Tail 20 }

# Test message
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
