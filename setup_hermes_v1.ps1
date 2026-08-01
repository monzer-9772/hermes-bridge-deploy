$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes_sync"
$py = "C:\Users\mmh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$envDir = "$env:USERPROFILE\.hermes"
$envFile = "$envDir\.env"

# 1. Install hermes-agent
Write-Host "[1/5] Installing hermes-agent..."
& $py -m pip install --upgrade hermes-agent 2>&1 | Select-Object -Last 5

# 2. Create .env
Write-Host "[2/5] Writing .env..."
New-Item -ItemType Directory -Force -Path $envDir | Out-Null
@"
TELEGRAM_BOT_TOKEN="8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
TELEGRAM_ALLOWED_USERS=6457326492
TELEGRAM_HOME_CHANNEL=6457326492
MINIMAX_API_KEY=PLACEHOLDER_NEED_REAL_KEY
MINIMAX_BASE_URL=https://api.minimax.io/v1
MINIMAX_MODEL=MiniMax-M3
"@ | Set-Content -Path $envFile -Encoding UTF8
Write-Host "  Written: $envFile"

# 3. Run hermes setup
Write-Host "[3/5] Running hermes setup..."
& $py -m hermes setup 2>&1 | Select-Object -Last 10

# 4. Approve pairing
Write-Host "[4/5] Approving pairing..."
$pairing = & $py -m hermes pairing list 2>&1
Write-Host "  $pairing"

# 5. Verify
Write-Host "[5/5] Verifying..."
& $py -m hermes --version 2>&1
Write-Host ""
Write-Host "=== DONE ==="
Write-Host "Next: edit $envFile with your real MiniMax API key"
