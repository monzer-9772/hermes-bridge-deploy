$ErrorActionPreference = "Stop"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$envDir = "$env:USERPROFILE\.hermes"
$envFile = "$envDir\.env"
$cfgFile = "$envDir\config.yaml"

# 1. Stop v5_visual + cloudflared (user said remove)
Write-Host "[1/8] Stopping v5_visual + cloudflared..."
Get-NetTCPConnection -LocalPort 8765 -EA SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue } catch {}
}
Get-Process cloudflared -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" -or $_.CommandLine -like "*v5_visual*" } | Stop-Process -Force -EA SilentlyContinue

# 2. Install hermes-agent
Write-Host "[2/8] Installing hermes-agent..."
& $py -m pip install --upgrade hermes-agent 2>&1 | Select-Object -Last 3

# 3. Write .env
Write-Host "[3/8] Writing .env..."
New-Item -ItemType Directory -Force -Path $envDir | Out-Null
@"
TELEGRAM_BOT_TOKEN="8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
TELEGRAM_ALLOWED_USERS=6457326492
TELEGRAM_HOME_CHANNEL=6457326492
MINIMAX_API_KEY="PLACEHOLDER_REPLACE_ME"
"@ | Set-Content -Path $envFile -Encoding UTF8

# 4. Write config.yaml with provider
Write-Host "[4/8] Writing config.yaml..."
@"
provider:
  name: minimax
  base_url: "https://api.minimax.io/v1"
  model: "MiniMax-M3"
  api_key_env: "MINIMAX_API_KEY"

minimax:
  base_url: "https://api.minimax.io/v1"
  api_key: "PLACEHOLDER_REPLACE_ME"

gateway:
  telegram:
    enabled: true
    polling: true
"@ | Set-Content -Path $cfgFile -Encoding UTF8

# 5. Run hermes setup
Write-Host "[5/8] Running hermes setup..."
& $py -m hermes setup 2>&1 | Select-Object -Last 15

# 6. Approve pairing (if needed)
Write-Host "[6/8] Checking pairings..."
& $py -m hermes pairing list 2>&1 | Select-Object -Last 5

# 7. Try to start gateway in foreground (test)
Write-Host "[7/8] Testing gateway start (5s)..."
$proc = Start-Process -FilePath $py -ArgumentList "-m", "hermes", "gateway" -WorkingDirectory $envDir -WindowStyle Hidden -RedirectStandardOutput "$envDir\gateway.log" -RedirectStandardError "$envDir\gateway.err" -PassThru
Start-Sleep -Seconds 5
$alive = -not $proc.HasExited
Write-Host "  Gateway alive after 5s: $alive"
if (-not $alive) {
    Write-Host "  gateway.err:"
    if (Test-Path "$envDir\gateway.err") { Get-Content "$envDir\gateway.err" -Tail 15 }
}
Stop-Process -Id $proc.Id -Force -EA SilentlyContinue

# 8. Install as Windows service
Write-Host "[8/8] Installing as Windows service..."
& $py -m hermes gateway install 2>&1 | Select-Object -Last 10

Write-Host ""
Write-Host "=== DONE ==="
Write-Host "Now edit these files and replace PLACEHOLDER_REPLACE_ME with your MiniMax API key:"
Write-Host "  $envFile"
Write-Host "  $cfgFile"
Write-Host ""
Write-Host "Then start the service:"
Write-Host "  Start-Service HermesGateway"
