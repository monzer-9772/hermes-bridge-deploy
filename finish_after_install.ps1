$ErrorActionPreference = "Continue"
$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"

# Verify
Write-Host "=== Hermes version ==="
if (Test-Path $hermes) {
    & $hermes version 2>&1
} else {
    Write-Host "hermes.exe not found at $hermes"
    # Look in other locations
    Get-ChildItem "C:\Users\abdul\AppData\Local\hermes\" -Recurse -Filter "hermes.exe" -EA SilentlyContinue | Select-Object FullName
    exit 1
}

# Make sure config files exist
Write-Host ""
Write-Host "=== Checking config ==="
if (-not (Test-Path "$envDir\.env")) {
    Write-Host "  .env missing, writing..."
    New-Item -ItemType Directory -Force -Path $envDir | Out-Null
    @"
TELEGRAM_BOT_TOKEN="8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
TELEGRAM_ALLOWED_USERS=6457326492
TELEGRAM_HOME_CHANNEL=6457326492
MINIMAX_API_KEY="sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"
"@ | Set-Content -Path "$envDir\.env" -Encoding UTF8
}

if (-not (Test-Path "$envDir\config.yaml")) {
    Write-Host "  config.yaml missing, writing..."
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
}

# Install + start service
Write-Host ""
Write-Host "=== Installing service ==="
& $hermes gateway install 2>&1 | Select-Object -Last 10

Write-Host ""
Write-Host "=== Starting service ==="
& $hermes gateway start 2>&1 | Select-Object -Last 10
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "=== Service status ==="
& $hermes gateway status 2>&1

# Test message
$token = "8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
$chatId = "6457326492"
$uri = "https://api.telegram.org/bot$token/sendMessage"
$body = @{ chat_id = $chatId; text = "Hermes Agent CLI installed. Open @Kails9772bot and send /start" } | ConvertTo-Json
Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body | Out-Null
Write-Host ""
Write-Host "Test message sent"
