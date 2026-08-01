$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes_sync"
$envDir = "$env:USERPROFILE\.hermes"
$envFile = "$envDir\.env"

# 1. Stop v5_visual + cloudflared
Write-Host "[1/9] Stopping old services..."
Get-NetTCPConnection -LocalPort 8765 -EA SilentlyContinue | ForEach-Object { try { Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue } catch {} }
Get-Process cloudflared -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue

# 2. Use official Windows installer for hermes-agent
Write-Host "[2/9] Running official Windows installer..."
$installCmd = "iex (irm https://hermes-agent.nousresearch.com/install.ps1)"
Write-Host "  This installs hermes-agent via official installer..."
Write-Host "  Will use %LOCALAPPDATA%\hermes\ + uv for Python"
Write-Host "  May take 2-5 minutes..."

# Run installer - it sets up its own Python via uv
try {
    Invoke-Expression $installCmd
    Write-Host "  Installer completed"
} catch {
    Write-Host "  Installer error: $_"
}

Start-Sleep -Seconds 3

# 3. Verify hermes command works
Write-Host "[3/9] Verifying hermes command..."
$hermesExe = "$env:LOCALAPPDATA\hermes\hermes.exe"
$hermesPy = "$env:LOCALAPPDATA\hermes\hermes-agent"
if (Test-Path $hermesExe) {
    Write-Host "  Found: $hermesExe"
} else {
    Write-Host "  hermes.exe not found at expected path"
}

# Find hermes binary
$found = Get-Command hermes -EA SilentlyContinue
if ($found) {
    Write-Host "  hermes in PATH: $($found.Source)"
    & hermes --version 2>&1 | Select-Object -First 3
} else {
    Write-Host "  hermes NOT in PATH - need to add"
}

# 4. Write .env
Write-Host "[4/9] Writing .env..."
New-Item -ItemType Directory -Force -Path $envDir | Out-Null
@"
TELEGRAM_BOT_TOKEN="8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
TELEGRAM_ALLOWED_USERS=6457326492
TELEGRAM_HOME_CHANNEL=6457326492
MINIMAX_API_KEY="sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"
"@ | Set-Content -Path $envFile -Encoding UTF8

# 5. Run hermes setup
Write-Host "[5/9] Running hermes setup..."
try { hermes setup 2>&1 | Select-Object -Last 10 } catch { Write-Host "  setup: $_" }

# 6. Test hermes gateway start (5s)
Write-Host "[6/9] Testing gateway start..."
$env:HOME = $env:USERPROFILE
$proc = Start-Process -FilePath "hermes" -ArgumentList "gateway" -WorkingDirectory $envDir -WindowStyle Hidden -RedirectStandardOutput "$envDir\gateway.log" -RedirectStandardError "$envDir\gateway.err" -PassThru
Start-Sleep -Seconds 8
$alive = -not $proc.HasExited
Write-Host "  Gateway alive after 8s: $alive"
if (-not $alive) {
    if (Test-Path "$envDir\gateway.err") {
        Write-Host "  gateway.err:"
        Get-Content "$envDir\gateway.err" -Tail 15
    }
    if (Test-Path "$envDir\gateway.log") {
        Write-Host "  gateway.log:"
        Get-Content "$envDir\gateway.log" -Tail 15
    }
}
Stop-Process -Id $proc.Id -Force -EA SilentlyContinue
Start-Sleep -Seconds 2

# 7. Install as service
Write-Host "[7/9] Installing as service..."
try { hermes service install 2>&1 | Select-Object -Last 10 } catch { Write-Host "  service install: $_" }

# 8. Start service
Write-Host "[8/9] Starting service..."
try { Start-Service HermesGateway -EA SilentlyContinue; Get-Service HermesGateway 2>&1 | Select-Object Name, Status } catch { Write-Host "  service start: $_" }

# 9. Test message
Write-Host "[9/9] Sending test message to your Telegram..."
$testMsg = "Hermes Agent is live. Send /help for commands."
$uri = "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/sendMessage"
$body = @{ chat_id = 6457326492; text = $testMsg } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body | Out-Null
    Write-Host "  Test message sent!"
} catch {
    Write-Host "  Test message error: $_"
}

Write-Host ""
Write-Host "=== DONE ==="
Write-Host "Open @Kails9772bot in Telegram and send /start"
