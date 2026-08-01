$ErrorActionPreference = "Continue"
$hermes = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
$envDir = "$env:USERPROFILE\.hermes"

# Add hermes to PATH
$env:PATH = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts;$env:PATH"

Write-Host "=== Test 1: hermes version (5 sec timeout) ==="
$proc = Start-Process -FilePath $hermes -ArgumentList "version" -NoNewWindow -PassThru -RedirectStandardOutput "$envDir\test1.out" -RedirectStandardError "$envDir\test1.err"
$proc.WaitForExit(5000) | Out-Null
Write-Host "  Exit code: $($proc.ExitCode)"
Get-Content "$envDir\test1.out" -EA SilentlyContinue

Write-Host ""
Write-Host "=== Test 2: hermes gateway install (15 sec timeout) ==="
$proc = Start-Process -FilePath $hermes -ArgumentList "gateway","install" -NoNewWindow -PassThru -RedirectStandardOutput "$envDir\test2.out" -RedirectStandardError "$envDir\test2.err"
$proc.WaitForExit(15000) | Out-Null
Write-Host "  Exit code: $($proc.ExitCode)"
Write-Host "  stdout:"
Get-Content "$envDir\test2.out" -EA SilentlyContinue
Write-Host "  stderr:"
Get-Content "$envDir\test2.err" -EA SilentlyContinue

Write-Host ""
Write-Host "=== Test 3: List subcommands ==="
& $hermes --help 2>&1 | Out-String | Write-Host
