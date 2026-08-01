$ErrorActionPreference = "Stop"
$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$installDir = "C:\Users\abdul\AppData\Local\hermes\hermes-agent"
$envDir = "$env:USERPROFILE\.hermes"

# 1. Stop service if running
Write-Host "[1/8] Stopping service..."
Get-Service HermesGateway -EA SilentlyContinue | Stop-Service -Force -EA SilentlyContinue
Start-Sleep -Seconds 2
# Also kill any running gateway
Get-Process -Name "hermes*" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" } | Stop-Process -Force -EA SilentlyContinue

# 2. Uninstall service
Write-Host "[2/8] Uninstalling service..."
& $hermes gateway uninstall 2>&1 | Select-Object -Last 5

# 3. Remove install dir
Write-Host "[3/8] Removing old install dir..."
if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force
}

# 4. Remove config
Write-Host "[4/8] Removing config..."
if (Test-Path $envDir) {
    Remove-Item -Path $envDir -Recurse -Force
}

# 5. Fresh install
Write-Host "[5/8] Running fresh install (this takes 2-5 min)..."
$env:HERMES_HOME = $env:LOCALAPPDATA + "\hermes"
$installCmd = "iex (irm https://hermes-agent.nousresearch.com/install.ps1)"
Invoke-Expression $installCmd 2>&1 | Select-Object -Last 10

# 6. Verify
Write-Host "[6/8] Verifying..."
$hermes2 = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
if (Test-Path $hermes2) {
    & $hermes2 version 2>&1
} else {
    Write-Host "  hermes not found at expected path"
    exit 1
}

# 7. Write config
Write-Host "[7/8] Writing config..."
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
Write-Host "  Wrote: $envDir\.env"
Write-Host "  Wrote: $envDir\config.yaml"

# 8. Install + start service
Write-Host "[8/8] Installing + starting service..."
& $hermes2 gateway install 2>&1 | Select-Object -Last 5
& $hermes2 gateway start 2>&1 | Select-Object -Last 5
Start-Sleep -Seconds 5
& $hermes2 gateway status 2>&1

# Test message
$token = "8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
$chatId = "6457326492"
$uri = "https://api.telegram.org/bot$token/sendMessage"
$body = @{ chat_id = $chatId; text = "Hermes Agent reinstalled. Send /start to @Kails9772bot" } | ConvertTo-Json
Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body | Out-Null
Write-Host ""
Write-Host "Test message sent. Open @Kails9772bot in Telegram and send /start"
