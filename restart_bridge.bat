@echo off
echo === Hermes Bridge v3.1 Restart ===
echo.

set INSTALL_DIR=C:\Users\abdul\AppData\Local\hermes\bridge
set PYTHON=C:\Users\abdul\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe

if not exist "%PYTHON%" (
    echo Python not found at %PYTHON%
    echo Trying alternative...
    for /f "tokens=*" %%p in ('where python 2^>nul') do set PYTHON=%%p
    if "%PYTHON%"=="" (
        echo No Python found. Aborting.
        pause
        exit /b 1
    )
)

echo Python: %PYTHON%

cd /d %INSTALL_DIR%

REM Kill existing bridges
echo Killing existing bridges...
taskkill /F /IM python.exe /FI "WINDOWTITLE eq *laptop_bridge*" 2>nul
for /f "tokens=*" %%p in ('powershell -Command "Get-Process python -ErrorAction SilentlyContinue | Where-Object { (Get-CimInstance Win32_Process -Filter \"ProcessId=$($_.Id)\").CommandLine -like \"*laptop_bridge*\" } | ForEach-Object { $_.Id }"') do (
    echo Killing PID %%p
    taskkill /F /PID %%p 2>nul
)

REM Download v3.1
echo Downloading v3.1 from GitHub...
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/laptop_bridge_v3.py' -OutFile 'laptop_bridge_v3.py'"

REM Verify
findstr /C:"navigate.ps1" laptop_bridge_v3.py >nul
if errorlevel 1 (
    echo ERROR: v3.1 not downloaded correctly
    pause
    exit /b 1
)
echo v3.1 verified

REM Start bridge
echo Starting bridge...
start "" "%PYTHON%" -m uvicorn laptop_bridge_v3:app --host 127.0.0.1 --port 8765 --app-dir "%INSTALL_DIR%"

echo.
echo Bridge started! Check at http://127.0.0.1:8765/ping
timeout /t 5
pause
