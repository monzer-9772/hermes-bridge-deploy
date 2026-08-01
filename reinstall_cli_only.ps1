$ErrorActionPreference = "Continue"

Write-Host "[1/6] Cleaning up..."
Get-Process -Name "hermes*" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Get-Service HermesGateway -EA SilentlyContinue | Stop-Service -Force -EA SilentlyContinue
Start-Sleep -Seconds 2

$installDir = "C:\Users\abdul\AppData\Local\hermes\hermes-agent"
$envDir = "$env:USERPROFILE\.hermes"

if (Test-Path $installDir) {
    Write-Host "  Removing: $installDir"
    Remove-Item -Path $installDir -Recurse -Force
}
if (Test-Path $envDir) {
    Write-Host "  Removing: $envDir"
    Remove-Item -Path $envDir -Recurse -Force
}

Write-Host ""
Write-Host "[2/6] Downloading install.ps1..."
$installPs1 = "$env:TEMP\install_clean.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1" -OutFile $installPs1 -UseBasicParsing

Write-Host ""
Write-Host "[3/6] Running install.ps1 with -IncludeDesktop:`$false..."
Write-Host "  This skips the desktop GUI build (which fails on Windows)..."
Write-Host "  Takes 2-5 minutes..."

& $installPs1 -IncludeDesktop:$false -NonInteractive 2>&1 | Select-Object -Last 30

Write-Host ""
Write-Host "[4/6] Verifying..."
$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
if (Test-Path $hermes) {
    & $hermes version 2>&1
} else {
    Write-Host "  hermes.exe not found"
    exit 1
}

Write-Host ""
Write-Host "[5/6] Writing config..."
New-Item -ItemType Directory -Force -Path $envDir | Out-Null

@"
TELEGRAM_BOT_TOKEN="8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
TELEGRAM_ALLOWED_USERS=6457326492
TELEGRAM_HOME_CHANNEL=6457326492
MINIMAX_API_KEY="sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"
"@ | Set-Content -Path "$envDir\.env" -Encoding UTF8

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
Write-Host "  Wrote config files"

Write-Host ""
Write-Host "[6/6] Installing + starting service..."
& $hermes gateway install 2>&1 | Select-Object -Last 5
& $hermes gateway start 2>&1 | Select-Object -Last 5
Start-Sleep -Seconds 5
& $hermes gateway status 2>&1

# Test message
$token = "8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
$chatId = "6457326492"
$uri = "https://api.telegram.org/bot$token/sendMessage"
$body = @{ chat_id = $chatId; text = "Hermes Agent reinstalled (CLI only, no desktop). Send /start to @Kails9772bot" } | ConvertTo-Json
Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body | Out-Null
Write-Host ""
Write-Host "Test message sent. Open @Kails9772bot in Telegram and send /start"
