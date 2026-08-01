@echo off
echo === Hermes Bridge v3.1 Restart ===
echo.

set INSTALL_DIR=C:\Users\abdul\AppData\Local\hermes\bridge
set PYTHON=C:\Users\abdul\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe

REM Step 1: Kill existing bridges via PowerShell
echo Killing existing bridges...
powershell -NoProfile -Command "Get-Process python -ErrorAction SilentlyContinue | ForEach-Object { try { $cmd = (Get-CimInstance Win32_Process -Filter ('ProcessId=' + $_.Id)).CommandLine; if ($cmd -like '*laptop_bridge*') { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Write-Host ('Killed PID ' + $_.Id) } } catch {} }"
timeout /t 2 /nobreak >nul

REM Step 2: Download v3.1
echo Downloading v3.1 from GitHub...
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/laptop_bridge_v3.py' -OutFile 'C:\Users\abdul\AppData\Local\hermes\bridge\laptop_bridge_v3.py' -UseBasicParsing"

REM Step 3: Verify
findstr /C:"navigate.ps1" "%INSTALL_DIR%\laptop_bridge_v3.py" >nul
if errorlevel 1 (
    echo ERROR: v3.1 not downloaded correctly
    pause
    exit /b 1
)
echo v3.1 verified

REM Step 4: Start bridge
echo Starting bridge...
cd /d "%INSTALL_DIR%"
start "HermesBridge" "%PYTHON%" -m uvicorn laptop_bridge_v3:app --host 127.0.0.1 --port 8765 --app-dir "%INSTALL_DIR%"

REM Step 5: Wait and ping
echo Waiting for bridge to start...
timeout /t 8 /nobreak >nul

powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8765/ping' -UseBasicParsing -TimeoutSec 5; Write-Host ('Bridge status: ' + $r.StatusCode + ' ' + $r.Content) } catch { Write-Host ('Bridge NOT responding: ' + $_.Exception.Message) }"

echo.
echo Done! Check tunnel URL in browser.
pause
