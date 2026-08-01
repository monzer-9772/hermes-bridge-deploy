$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"
$env:PATH = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts;$env:PATH"

# Kill any running
Get-Process -Name "python*" -EA SilentlyContinue | Where-Object { $_.Path -like "*hermes*" -or $_.CommandLine -like "*hermes*" } | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Host "=== Run gateway in foreground 20s, capture all output ==="
$outFile = "$envDir\test_gw_verbose.out"
$errFile = "$envDir\test_gw_verbose.err"
Remove-Item $outFile, $errFile -EA SilentlyContinue

$proc = Start-Process -FilePath $hermes -ArgumentList "gateway","--verbose" -WorkingDirectory $envDir -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru
Start-Sleep -Seconds 20
$alive = -not $proc.HasExited
Write-Host "  Alive after 20s: $alive"

if (Test-Path $outFile) {
    $size = (Get-Item $outFile).Length
    Write-Host "  stdout size: $size"
    if ($size -gt 0) {
        Write-Host "  === stdout ==="
        Get-Content $outFile
    }
}
if (Test-Path $errFile) {
    $size = (Get-Item $errFile).Length
    Write-Host "  stderr size: $size"
    if ($size -gt 0) {
        Write-Host "  === stderr ==="
        Get-Content $errFile
    }
}
Stop-Process -Id $proc.Id -Force -EA SilentlyContinue

# After 20s, check if /start was answered
Write-Host ""
Write-Host "=== Check recent Telegram messages ==="
$resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/getUpdates" 
$resp | ConvertTo-Json -Depth 5
