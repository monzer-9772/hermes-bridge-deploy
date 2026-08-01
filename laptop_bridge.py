"""
Laptop Bridge Server
Runs on user's Windows laptop. Exposes HTTP endpoints that
the cloud agent (MiniMax-M3) can call to execute actions
on the local machine: shell, files, browser, screenshots.

Auth: shared secret token in Authorization header.
"""
import os
import sys
import json
import time
import shutil
import asyncio
import subprocess
import base64
from pathlib import Path
from typing import Optional

import httpx
from fastapi import FastAPI, Header, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ---------- Auth ----------
BRIDGE_TOKEN = os.environ.get(
    "BRIDGE_TOKEN",
    "hm-bridge-2026-secure-token-v3"  # override via env in production
)

async def verify_token(authorization: Optional[str] = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    if token != BRIDGE_TOKEN:
        raise HTTPException(status_code=403, detail="Bad token")
    return token

# ---------- App ----------
app = FastAPI(title="Laptop Bridge", version="1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

WORKDIR = Path(os.environ.get("BRIDGE_WORKDIR", "C:/Users/abdul"))
DOWNLOADS = WORKDIR / "Downloads"
DOWNLOADS.mkdir(exist_ok=True)

# ---------- Models ----------
class ShellReq(BaseModel):
    command: str
    cwd: Optional[str] = None
    timeout: int = 60

class ShellRes(BaseModel):
    stdout: str
    stderr: str
    returncode: int
    duration_ms: int

class ReadReq(BaseModel):
    path: str
    max_bytes: int = 200_000

class WriteReq(BaseModel):
    path: str
    content: str
    encoding: str = "utf-8"  # or "base64" for binary

class FileRes(BaseModel):
    path: str
    content: Optional[str] = None
    size: int
    truncated: bool = False

class ScreenshotRes(BaseModel):
    width: int
    height: int
    image_base64: str
    format: str = "png"

class BrowserReq(BaseModel):
    action: str  # "open", "close", "status"
    url: Optional[str] = None
    profile: Optional[str] = "default"

class BrowserRes(BaseModel):
    status: str
    details: dict

class PingRes(BaseModel):
    pong: bool
    hostname: str
    platform: str
    user: str
    cwd: str
    uptime_s: float

# ---------- State ----------
START_TIME = time.time()

# ---------- Endpoints ----------
@app.get("/ping", response_model=PingRes)
async def ping():
    return PingRes(
        pong=True,
        hostname=os.environ.get("COMPUTERNAME", "unknown"),
        platform=sys.platform,
        user=os.environ.get("USERNAME", "unknown"),
        cwd=str(WORKDIR),
        uptime_s=time.time() - START_TIME,
    )

@app.post("/shell", response_model=ShellRes, dependencies=[Depends(verify_token)])
async def shell(req: ShellReq):
    cwd = req.cwd or str(WORKDIR)
    t0 = time.time()
    try:
        proc = await asyncio.create_subprocess_shell(
            req.command,
            cwd=cwd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=req.timeout
            )
        except asyncio.TimeoutError:
            proc.kill()
            return ShellRes(
                stdout="", stderr=f"Timeout after {req.timeout}s",
                returncode=-1, duration_ms=int((time.time()-t0)*1000),
            )
        return ShellRes(
            stdout=stdout.decode("utf-8", errors="replace"),
            stderr=stderr.decode("utf-8", errors="replace"),
            returncode=proc.returncode,
            duration_ms=int((time.time()-t0)*1000),
        )
    except Exception as e:
        return ShellRes(
            stdout="", stderr=f"Error: {e}",
            returncode=-1, duration_ms=int((time.time()-t0)*1000),
        )

@app.post("/read", response_model=FileRes, dependencies=[Depends(verify_token)])
async def read_file(req: ReadReq):
    p = Path(req.path)
    if not p.exists():
        raise HTTPException(404, f"File not found: {req.path}")
    if not p.is_file():
        raise HTTPException(400, f"Not a file: {req.path}")
    size = p.stat().st_size
    truncated = size > req.max_bytes
    with open(p, "rb") as f:
        data = f.read(req.max_bytes if truncated else size)
    return FileRes(
        path=str(p),
        content=base64.b64encode(data).decode("ascii"),
        size=size,
        truncated=truncated,
    )

@app.post("/write", dependencies=[Depends(verify_token)])
async def write_file(req: WriteReq):
    p = Path(req.path)
    p.parent.mkdir(parents=True, exist_ok=True)
    if req.encoding == "base64":
        data = base64.b64decode(req.content)
        with open(p, "wb") as f:
            f.write(data)
    else:
        with open(p, "w", encoding=req.encoding) as f:
            f.write(req.content)
    return {"written": str(p), "size": p.stat().st_size}

@app.post("/screenshot", response_model=ScreenshotRes, dependencies=[Depends(verify_token)])
async def screenshot():
    """Capture the laptop's primary screen."""
    try:
        import mss
        with mss.mss() as sct:
            monitor = sct.monitors[1]  # primary
            img = sct.grab(monitor)
            # mss >= 9 uses .rgb; older used .bmp
            if hasattr(img, "rgb"):
                from PIL import Image
                pil = Image.frombytes("RGB", img.size, img.rgb, "raw", "RGB")
                from io import BytesIO
                buf = BytesIO()
                pil.save(buf, format="PNG")
                data = buf.getvalue()
            else:
                data = bytes(img.bmp) if hasattr(img, "bmp") else bytes(img)
        return ScreenshotRes(
            width=monitor["width"],
            height=monitor["height"],
            image_base64=base64.b64encode(data).decode("ascii"),
            format="png",
        )
    except Exception as e:
        raise HTTPException(500, f"Screenshot failed: {e}")

@app.post("/browser", response_model=BrowserRes, dependencies=[Depends(verify_token)])
async def browser(req: BrowserReq):
    """
    Control a local browser via Playwright (preferred) or system default.
    For simplicity, this uses the OS default to navigate.
    """
    if req.action == "open" and req.url:
        # Windows: start default browser
        try:
            subprocess.Popen(
                ["cmd", "/c", "start", "", req.url],
                shell=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return BrowserRes(
                status="opened",
                details={"url": req.url, "method": "os_default"},
            )
        except Exception as e:
            raise HTTPException(500, f"Failed to open URL: {e}")
    elif req.action == "status":
        # Check if Chrome is running
        try:
            out = subprocess.check_output(
                ["tasklist", "/FI", "IMAGENAME eq chrome.exe"],
                shell=True, text=True,
            )
            running = "chrome.exe" in out.lower()
            return BrowserRes(
                status="ok",
                details={"chrome_running": running},
            )
        except Exception as e:
            return BrowserRes(status="ok", details={"error": str(e)})
    else:
        raise HTTPException(400, f"Unknown action: {req.action}")

@app.get("/health")
async def health():
    return {"status": "ok", "service": "laptop-bridge", "version": "1.0"}

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("BRIDGE_PORT", "8765"))
    host = os.environ.get("BRIDGE_HOST", "127.0.0.1")
    uvicorn.run(app, host=host, port=port, log_level="info")
