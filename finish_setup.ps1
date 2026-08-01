$ErrorActionPreference = "Continue"

# Use hermes from its installed location
$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"

Write-Host "=== Hermes version ==="
& $hermes version 2>&1

# Write the config files with our settings
Write-Host ""
Write-Host "=== Writing config files ==="
New-Item -ItemType Directory -Force -Path $envDir | Out-Null

@"
TELEGRAM_BOT_TOKEN="8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
TELEGRAM_ALLOWED_USERS=6457326492
TELEGRAM_HOME_CHANNEL=6457326492
MINIMAX_API_KEY="sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"
"@ | Set-Content -Path "$envDir\.env" -Encoding UTF8
Write-Host "  Wrote: $envDir\.env"

@"
provider:
  name: minimax
  base_url: "https://api.minimax.io/v1"
  model: "MiniMax-M3"

minimax:
  base_url: "https://api.minimax.io/v1"
  api_key: "sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"

gateway:
  telegram:
    enabled: true
    polling: true
    bot_token_env: "TELEGRAM_BOT_TOKEN"
    allowed_users_env: "TELEGRAM_ALLOWED_USERS"

tools:
  web_search:
    backend: "duckduckgo"
  browser:
    backend: "local"
  tts:
    backend: "edge"
  vision:
    enabled: true
  computer_use:
    enabled: true
"@ | Set-Content -Path "$envDir\config.yaml" -Encoding UTF8
Write-Host "  Wrote: $envDir\config.yaml"

# Approve pairing
Write-Host ""
Write-Host "=== Pairing ==="
& $hermes pairing list 2>&1

# Test start gateway in foreground for 10 seconds
Write-Host ""
Write-Host "=== Testing gateway (10s) ==="
$env:HERMES_HOME = $envDir
$proc = Start-Process -FilePath $hermes -ArgumentList "gateway" -WorkingDirectory $envDir -WindowStyle Hidden -RedirectStandardOutput "$envDir\gateway.log" -RedirectStandardError "$envDir\gateway.err" -PassThru
Start-Sleep -Seconds 10
$alive = -not $proc.HasExited
Write-Host "  Gateway alive after 10s: $alive"
if (-not $alive) {
    Write-Host "  gateway.err:"
    if (Test-Path "$envDir\gateway.err") { Get-Content "$envDir\gateway.err" -Tail 15 }
    Write-Host "  gateway.log:"
    if (Test-Path "$envDir\gateway.log") { Get-Content "$envDir\gateway.log" -Tail 15 }
}
Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
Start-Sleep -Seconds 2

# Install as service
Write-Host ""
Write-Host "=== Installing as service ==="
& $hermes gateway install 2>&1 | Select-Object -Last 10

# Start service
Write-Host ""
Write-Host "=== Starting service ==="
& $hermes gateway start 2>&1 | Select-Object -Last 10
Start-Sleep -Seconds 5
& $hermes gateway status 2>&1

# Send test message
Write-Host ""
Write-Host "=== Sending test message to Telegram ==="
$token = "8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
$chatId = "6457326492"
$uri = "https://api.telegram.org/bot$token/sendMessage"
$body = @{ chat_id = $chatId; text = "Hermes Agent v0.19.1 is live on this laptop. Send /help to see commands." } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body | Out-Null
    Write-Host "  ✅ Test message sent to your Telegram"
} catch {
    Write-Host "  ❌ Test message error: $_"
}

Write-Host ""
Write-Host "=== DONE ==="
Write-Host "Open @Kails9772bot in Telegram and send /start"
