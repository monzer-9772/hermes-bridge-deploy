$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"
$logDir = "C:\Users\abdul\AppData\Local\hermes\logs"

Write-Host "=== Hermes logs dir ==="
if (Test-Path $logDir) {
    Get-ChildItem $logDir -EA SilentlyContinue | Select-Object Name, Length, LastWriteTime
    Write-Host ""
    Write-Host "=== Latest gateway.log ==="
    Get-ChildItem $logDir -Filter "gateway*" -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object {
        Write-Host "--- $($_.FullName) ---"
        Get-Content $_.FullName -Tail 30
    }
} else {
    Write-Host "  $logDir does not exist"
}

Write-Host ""
Write-Host "=== Check $envDir for any logs ==="
Get-ChildItem $envDir -Recurse -Filter "*.log" -EA SilentlyContinue | Select-Object FullName, Length | Format-List

Write-Host ""
Write-Host "=== Running processes ==="
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" } | Select-Object Id, ProcessName, StartTime
Get-Process -Name "hermes*" -EA SilentlyContinue | Select-Object Id, ProcessName, StartTime
