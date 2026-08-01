# Setup cloudflared tunnel
$ErrorActionPreference = "Stop"
$dir = "C:\Users\mmh\hermes_sync"
$cfPath = "$dir\cloudflared.exe"
$cfUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"

Write-Host "=== Cloudflared Setup ==="

# Download
if (-not (Test-Path $cfPath)) {
    Write-Host "Downloading cloudflared..."
    Invoke-WebRequest -Uri $cfUrl -OutFile $cfPath -UseBasicParsing
    Write-Host "  Size: $((Get-Item $cfPath).Length) bytes"
} else {
    Write-Host "Already exists: $cfPath"
}

# Verify it runs
$ver = & $cfPath --version 2>&1
Write-Host "  Version: $ver"

# Start tunnel pointing to bridge_agent's connection
# (Note: bridge_agent is WS client, NOT server. cloudflared needs a local HTTP server)
# We need to either:
# 1. Run a local HTTP server that wraps bridge_agent's WS
# 2. Use cloudflared with --hostname for persistent URL

Write-Host ""
Write-Host "NOTE: bridge_agent.py is a WebSocket CLIENT."
Write-Host "cloudflared needs an HTTP server to tunnel."
Write-Host ""
Write-Host "Options:"
Write-Host "  A) Start v5_visual.py (HTTP server) on 8765, then tunnel to it"
Write-Host "  B) Use cloudflared with --url to set up quick tunnel"
Write-Host ""

# Test that the bridge_agent WS connection works
# (the WS URL is hardcoded in bridge_agent.py)
Write-Host "Bridge agent's WS target: wss://sponsor-brad-satisfy-females.trycloudflare.com/ws"
Write-Host "(if this URL is dead, bridge_agent can't connect)"
