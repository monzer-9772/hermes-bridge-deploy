$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"
$installDir = "C:\Users\abdul\AppData\Local\hermes"

# Kill all
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" } | Stop-Process -Force
Get-Process -Name "hermes*" -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Host "=== Inspect default config template ==="
$cfgTemplate = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\config.example.yaml"
if (Test-Path $cfgTemplate) {
    Write-Host "  Found: $cfgTemplate"
    Get-Content $cfgTemplate -Tail 200
} else {
    Write-Host "  No example config, search..."
    Get-ChildItem $installDir -Recurse -Filter "*example*config*.yaml" -EA SilentlyContinue | Select-Object FullName
    Get-ChildItem $installDir -Recurse -Filter "config*.yaml" -EA SilentlyContinue | Select-Object FullName
}

Write-Host ""
Write-Host "=== Show current config.yaml ==="
Get-Content "$envDir\config.yaml"

Write-Host ""
Write-Host "=== Write corrected config (using old schema: telegram: token:) ==="
# Hermes Agent v0.19.1 config schema uses inline telegram config
@"
model:
  provider: minimax
  api_base: "https://api.minimax.io/v1"
  model: "MiniMax-M3"

minimax:
  api_key: "sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"

telegram:
  enabled: true
  token: "8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
  allowed_users:
    - 6457326492

tools:
  web_search:
    backend: "duckduckgo"
  browser:
    backend: "local"
  tts:
    backend: "edge"
"@ | Set-Content -Path "$envDir\config.yaml" -Encoding UTF8
Write-Host "  Wrote new config.yaml"

Write-Host ""
Write-Host "=== Also ensure .env is correct ==="
@"
TELEGRAM_BOT_TOKEN="8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY"
TELEGRAM_ALLOWED_USERS=6457326492
MINIMAX_API_KEY="sk-cp-j8lQAE_2UtcJ7mL4n1Mdajjzvb-Kqq4WY6PSjSoNt-yMNGFtTZz3Lfmn20f91osdD2xeWiFmPUtf8OrECU8r7c91YQLGvH8_vPnAzb31VkCRd4RA_t1kXDk"
"@ | Set-Content -Path "$envDir\.env" -Encoding UTF8
Write-Host "  Wrote new .env"

Write-Host ""
Write-Host "=== Restart gateway ==="
$env:HERMES_HOME = $installDir
$env:PATH = "$installDir\hermes-agent\venv\Scripts;$env:PATH"

$out = "$envDir\gateway_v3.out"
$err = "$envDir\gateway_v3.err"
Remove-Item $out, $err -EA SilentlyContinue

$proc = Start-Process -FilePath $hermes -ArgumentList "gateway" -WorkingDirectory $envDir -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
Write-Host "  PID: $($proc.Id)"
Start-Sleep -Seconds 15
$alive = -not $proc.HasExited
Write-Host "  Alive after 15s: $alive"

Write-Host ""
Write-Host "=== stderr ==="
if (Test-Path $err) { Get-Content $err }
Write-Host ""
Write-Host "=== stdout (last 30) ==="
if (Test-Path $out) { Get-Content $out -Tail 30 }
