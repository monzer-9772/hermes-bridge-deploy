$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$installDir = "C:\Users\abdul\AppData\Local\hermes"
$envDir = "$env:USERPROFILE\.hermes"

# Kill all
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" } | Stop-Process -Force
Get-Process -Name "hermes*" -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Host "=== Check both .env locations ==="
Write-Host "Install dir .env:"
if (Test-Path "$installDir\.env") {
    Get-Content "$installDir\.env"
} else {
    Write-Host "  MISSING"
}
Write-Host ""
Write-Host "User home .env:"
if (Test-Path "$envDir\.env") {
    Get-Content "$envDir\.env"
} else {
    Write-Host "  MISSING"
}
Write-Host ""

# Also check the project .env from install dir
$projectEnv = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\.env"
if (Test-Path $projectEnv) {
    Write-Host "Project .env ($projectEnv):"
    Get-Content $projectEnv
}

# THE REAL FIX: hermes's load_hermes_dotenv uses HERMES_HOME env var
# Default: Path.home() / ".hermes" = C:\Users\abdul\.hermes
# That's where .env is
Write-Host ""
Write-Host "=== Verify config.yaml is in both places ==="
Get-ChildItem $installDir, $envDir -Filter "*.yaml" -EA SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize

Write-Host ""
Write-Host "=== Start with explicit HERMES_HOME pointing to install dir ==="
$env:HERMES_HOME = $installDir
$env:PATH = "$installDir\hermes-agent\venv\Scripts;$env:PATH"

# Also export TELEGRAM_BOT_TOKEN directly
$env:TELEGRAM_BOT_TOKEN = "8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
$env:TELEGRAM_ALLOWED_USERS = "6457326492"
$env:MINIMAX_API_KEY = "sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"

$out = "$envDir\gateway_v4.out"
$err = "$envDir\gateway_v4.err"
Remove-Item $out, $err -EA SilentlyContinue

$proc = Start-Process -FilePath $hermes -ArgumentList "gateway" -WorkingDirectory $installDir -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
Write-Host "  PID: $($proc.Id), HERMES_HOME: $env:HERMES_HOME"
Start-Sleep -Seconds 15
$alive = -not $proc.HasExited
Write-Host "  Alive after 15s: $alive"

Write-Host ""
Write-Host "=== stderr ==="
if (Test-Path $err) { Get-Content $err }
Write-Host ""
Write-Host "=== stdout ==="
if (Test-Path $out) { Get-Content $out -Tail 30 }
