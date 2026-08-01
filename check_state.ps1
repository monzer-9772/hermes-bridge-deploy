$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"

Write-Host "=== hermes.exe exists? ==="
Test-Path $hermes

Write-Host ""
Write-Host "=== Version ==="
if (Test-Path $hermes) {
    & $hermes version 2>&1
}

Write-Host ""
Write-Host "=== Service ==="
& $hermes gateway status 2>&1
Get-Service HermesGateway -EA SilentlyContinue | Select-Object Name, Status

Write-Host ""
Write-Host "=== Gateway log (last 30) ==="
if (Test-Path "$envDir\gateway.log") {
    Get-Content "$envDir\gateway.log" -Tail 30
} else {
    Write-Host "  no gateway.log"
}
if (Test-Path "$envDir\gateway.err") {
    Write-Host "  gateway.err:"
    Get-Content "$envDir\gateway.err" -Tail 20
}

Write-Host ""
Write-Host "=== Config files ==="
Get-ChildItem $envDir -EA SilentlyContinue | Select-Object Name, Length

Write-Host ""
Write-Host "=== Running hermes processes ==="
Get-Process -Name "hermes*" -EA SilentlyContinue | Select-Object Id, ProcessName, StartTime
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" } | Select-Object Id, ProcessName, StartTime
