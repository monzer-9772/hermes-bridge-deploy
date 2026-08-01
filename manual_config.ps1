# Run this AFTER you cancel the interactive installer
# or after it exits

$ErrorActionPreference = "Continue"
$envDir = "$env:USERPROFILE\.hermes"
$envFile = "$envDir\.env"
$cfgFile = "$envDir\config.yaml"
$cfgJson = "$envDir\config.json"

New-Item -ItemType Directory -Force -Path $envDir | Out-Null

# 1. Verify hermes is installed
Write-Host "=== hermes version ==="
hermes version 2>&1

# 2. Write config
Write-Host ""
Write-Host "=== Writing config ==="
@"
provider:
  name: minimax
  base_url: "https://api.minimax.io/v1"
  model: "MiniMax-M3"
  api_key_env: "MINIMAX_API_KEY"

minimax:
  base_url: "https://api.minimax.io/v1"
  api_key: "sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"

gateway:
  telegram:
    enabled: true
    polling: true
"@ | Set-Content -Path $cfgFile -Encoding UTF8

@"
TELEGRAM_BOT_TOKEN="8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
TELEGRAM_ALLOWED_USERS=6457326492
TELEGRAM_HOME_CHANNEL=6457326492
MINIMAX_API_KEY="sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"
"@ | Set-Content -Path $envFile -Encoding UTF8

Write-Host "Written: $cfgFile"
Write-Host "Written: $envFile"

# 3. Approve pairing (or create it)
Write-Host ""
Write-Host "=== Pairing ==="
hermes pairing list 2>&1

# 4. Check status
Write-Host ""
Write-Host "=== Status ==="
hermes status 2>&1 | Select-Object -First 20
