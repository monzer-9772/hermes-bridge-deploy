# Triage 2: find the right Python
$ErrorActionPreference = "Continue"

Write-Host "=== Find Right Python ===" -ForegroundColor Cyan

# Check uv python
$uvPy = "C:\Users\abdul\AppData\Roaming\uv\python\cpython-3.11-windows-x86_64-none\python.exe"
if (Test-Path $uvPy) {
    Write-Host ""
    Write-Host "1. uv Python (was running bridge before):" -ForegroundColor Yellow
    & $uvPy -c "import httpx, uvicorn, fastapi; print('  Has httpx:', httpx.__version__); print('  Has uvicorn:', uvicorn.__version__); print('  Has fastapi:', fastapi.__version__)" 2>&1
}

# Check venv Python
$venvPy = "C:\Users\abdul\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe"
if (Test-Path $venvPy) {
    Write-Host ""
    Write-Host "2. venv Python:" -ForegroundColor Yellow
    & $venvPy -c "import httpx, uvicorn, fastapi; print('  Has httpx:', httpx.__version__); print('  Has uvicorn:', uvicorn.__version__); print('  Has fastapi:', fastapi.__version__)" 2>&1
}

# Check which pip can install
Write-Host ""
Write-Host "3. Test pip install in codex Python:" -ForegroundColor Yellow
$codexPy = "C:\Users\abdul\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
& $codexPy -m pip --version 2>&1
& $codexPy -m pip list 2>&1 | Select-String -Pattern "httpx|uvicorn|fastapi"

Write-Host ""
Write-Host "=== Press Enter to close ==="
pause
