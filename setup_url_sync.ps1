$installDir = "C:\Users\abdul\AppData\Local\hermes\bridge"

# Create script that updates GitHub with current URL
$syncScript = @"
# Wait for tunnel to be ready
`$errFile = "$installDir\tunnel\tunnel.err"
`$url = `$null
for (`$i = 0; `$i -lt 30; `$i++) {
    Start-Sleep -Seconds 2
    if (Test-Path `$errFile) {
        `$content = Get-Content `$errFile -Raw -EA SilentlyContinue
        if (`$content -match 'https://[a-zA-Z0-9\-]+\.trycloudflare\.com') {
            `$url = `$matches[0]
            break
        }
    }
}

if (`$url) {
    # Save locally
    Set-Content -Path "$installDir\url.txt" -Value `$url
    
    # Push to GitHub repo
    `$token = `$env:GH_TOKEN
    if (`$token) {
        `$body = @{ message = "Auto-update bridge URL"; content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(`$url)) } | ConvertTo-Json
        # Get existing SHA
        `$sha = (Invoke-RestMethod -Uri "https://api.github.com/repos/monzer-9772/hermes-bridge-deploy/contents/bridge_url.txt" -Headers @{ Authorization = "token `$token" }).sha
        if (`$sha) { `$body = (`$body | ConvertFrom-Json) | Select-Object message, content, @{n='sha';e={`$sha}} | ConvertTo-Json -Compress }
        
        `$r = Invoke-RestMethod -Uri "https://api.github.com/repos/monzer-9772/hermes-bridge-deploy/contents/bridge_url.txt" -Method Put -Headers @{ Authorization = "token `$token" } -ContentType "application/json" -Body `$body
        if (`$r.content) { Write-Host "[sync] URL pushed: `$url" }
    }
    
    # Set env var for current process
    `$env:BRIDGE_URL = `$url
    [Environment]::SetEnvironmentVariable("BRIDGE_URL", `$url, "User")
    Write-Host "URL: `$url"
} else {
    Write-Host "No URL found after 60s"
}
"@

# Better version: also detect bridge URL changes and push
$syncScriptPath = "$installDir\sync_url.ps1"
Set-Content -Path $syncScriptPath -Value $syncScript
Write-Host "Created: $syncScriptPath"

# Update tunnel restart to also sync URL
$tunnelWrapper = @"
@echo off
:loop
cd /d "$installDir\tunnel"
del tunnel.log tunnel.err 2>nul
cloudflared tunnel --url http://127.0.0.1:8765 --no-autoupdate > tunnel.log 2> tunnel.err
timeout /t 3 /nobreak >nul
REM After URL is established, sync to GitHub
powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "$syncScriptPath"
timeout /t 7 /nobreak >nul
goto loop
"@
Set-Content -Path "$installDir\restart_tunnel.cmd" -Value $tunnelWrapper
Write-Host "Updated: $installDir\restart_tunnel.cmd (now syncs URL)"

Write-Host ""
Write-Host "=== Test: Run sync now ==="
# Wait for current tunnel
$errFile = "$installDir\tunnel\tunnel.err"
$url = $null
for ($i = 0; $i -lt 10; $i++) {
    if (Test-Path $errFile) {
        $content = Get-Content $errFile -Raw -EA SilentlyContinue
        if ($content -match 'https://[a-zA-Z0-9\-]+\.trycloudflare\.com') {
            $url = $matches[0]
            break
        }
    }
    Start-Sleep -Seconds 2
}

if ($url) {
    Set-Content -Path "$installDir\url.txt" -Value $url
    [Environment]::SetEnvironmentVariable("BRIDGE_URL", $url, "User")
    Write-Host "Current URL: $url"
} else {
    Write-Host "No URL found"
}
