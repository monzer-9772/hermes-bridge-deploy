# The bot is working but not persistent. We need to:
# 1. Send /sethome to register home channel
# 2. Set up auto-start properly so it persists across reboots

Write-Host "=== Send /sethome to register home channel ==="
$body = @{ chat_id = 6457326492; text = "/sethome" } | ConvertTo-Json
$res = Invoke-RestMethod -Uri "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/sendMessage" -Method Post -ContentType "application/json" -Body $body
Write-Host "  Sent: msg_id=$($res.result.message_id)"

Start-Sleep -Seconds 5

# Also add HERMES_HOME to the scheduled task environment
Write-Host ""
Write-Host "=== Update scheduled task to set HERMES_HOME ==="
$task = Get-ScheduledTask -TaskName "Hermes_Gateway"
$task.Actions[0].Execute = "C:\Users\abdul\AppData\Local\hermes\gateway-service\Hermes_Gateway.cmd"
$task.Settings.MultipleInstances = "IgnoreNew"
$task.Settings.DisallowStartIfOnBatteries = $false
$task.Settings.StopIfGoingOnBatteries = $false
$task.Principal.RunLevel = "Highest"

# Add env var to task
$envVars = @(
    "HERMES_HOME=C:\Users\abdul\AppData\Local\hermes"
    "TELEGRAM_BOT_TOKEN=8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
    "TELEGRAM_ALLOWED_USERS=6457326492"
    "MINIMAX_API_KEY=sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"
)
# The .cmd sets HERMES_HOME already? Let me check
Get-Content "C:\Users\abdul\AppData\Local\hermes\gateway-service\Hermes_Gateway.cmd" | Write-Host

# Update the .cmd to include all env vars
@"
@echo off
set "HERMES_HOME=C:\Users\abdul\AppData\Local\hermes"
set "TELEGRAM_BOT_TOKEN=8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
set "TELEGRAM_ALLOWED_USERS=6457326492"
set "MINIMAX_API_KEY=sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"
set "PYTHONIOENCODING=utf-8"
set "HERMES_GATEWAY_DETACHED=1"
set "VIRTUAL_ENV=C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv"
set "PYTHONPATH=C:\Users\abdul\AppData\Local\hermes\hermes-agent;%PYTHONPATH%"
cd /d C:\Users\abdul\AppData\Local\hermes
C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe -m hermes_cli.main gateway run
exit /b 0
"@ | Set-Content "C:\Users\abdul\AppData\Local\hermes\gateway-service\Hermes_Gateway.cmd" -Encoding UTF8
Write-Host ""
Write-Host "  Updated Hermes_Gateway.cmd with env vars"

Write-Host ""
Write-Host "=== Verify ==="
Get-Content "C:\Users\abdul\AppData\Local\hermes\gateway-service\Hermes_Gateway.cmd" | Write-Host
