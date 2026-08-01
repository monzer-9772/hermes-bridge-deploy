"""
Laptop Bridge v2: adds task queue + persistent state.
Same FastAPI server, but now has:
- /queue/submit (cloud submits task, gets task_id)
- /queue/worker_tick (laptop worker calls periodically, gets next task)
- /queue/result/<id> (laptop submits result)
- /queue/status/<id> (cloud polls status)
- All previous endpoints (shell, read, write, screenshot, browser)

The "queue" is just an in-memory dict + persisted to SQLite on laptop.
This avoids needing shared DB.
"""
import os
import sys
import json
import time
import shutil
import asyncio
import sqlite3
import subprocess
import base64
import threading
from pathlib import Path
from typing import Optional, Dict, Any, List
from datetime import datetime
from queue import Queue, Empty
from contextlib import contextmanager

import httpx
from fastapi import FastAPI, Header, HTTPException, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ---------- Config ----------
BRIDGE_TOKEN = os.environ.get(
    "BRIDGE_TOKEN", "hm-bridge-2026-secure-token-v3"
)
WORKDIR = Path(os.environ.get("BRIDGE_WORKDIR", "C:/Users/abdul"))
DOWNLOADS = WORKDIR / "Downloads"
DOWNLOADS.mkdir(exist_ok=True)
DB_PATH = WORKDIR / "AppData" / "Local" / "hermes" / "bridge" / "tasks.db"

# ---------- Auth ----------
async def verify_token(authorization: Optional[str] = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    if token != BRIDGE_TOKEN:
        raise HTTPException(status_code=403, detail="Bad token")
    return token

# ---------- DB ----------
_db_lock = threading.Lock()

@contextmanager
def db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), timeout=30)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()

def init_db():
    with db() as conn:
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_type TEXT NOT NULL,
                payload TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                priority INTEGER DEFAULT 5,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                started_at TEXT,
                completed_at TEXT,
                result TEXT,
                error TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status, priority);
        """)

init_db()

# ---------- Task executors ----------
def execute_shell(command: str, cwd: str = None, timeout: int = 30) -> dict:
    try:
        proc = subprocess.run(
            command, cwd=cwd or str(WORKDIR), shell=True,
            capture_output=True, text=True, timeout=timeout,
        )
        return {"stdout": proc.stdout, "stderr": proc.stderr, "returncode": proc.returncode}
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": f"Timeout after {timeout}s", "returncode": -1}
    except Exception as e:
        return {"stdout": "", "stderr": str(e), "returncode": -1}

def execute_read(path: str, max_bytes: int = 200000) -> dict:
    p = Path(path)
    if not p.exists():
        return {"error": f"Not found: {path}"}
    if not p.is_file():
        return {"error": f"Not a file: {path}"}
    data = p.read_bytes()[:max_bytes]
    return {
        "path": str(p),
        "size": p.stat().st_size,
        "content_b64": base64.b64encode(data).decode(),
    }

def execute_write(path: str, content_b64: str, encoding: str = "utf-8") -> dict:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    if encoding == "base64":
        p.write_bytes(base64.b64decode(content_b64))
    else:
        p.write_text(content_b64, encoding=encoding)
    return {"written": str(p), "size": p.stat().st_size}

def execute_screenshot() -> dict:
    import mss
    from PIL import Image
    from io import BytesIO
    with mss.mss() as sct:
        mon = sct.monitors[1]
        img = sct.grab(mon)
        if hasattr(img, "rgb"):
            pil = Image.frombytes("RGB", img.size, img.rgb, "raw", "RGB")
            buf = BytesIO()
            pil.save(buf, format="PNG")
            data = buf.getvalue()
        else:
            data = bytes(img.bmp)
    return {
        "width": mon["width"],
        "height": mon["height"],
        "png_b64": base64.b64encode(data).decode(),
        "size": len(data),
    }

def execute_browser(url: str) -> dict:
    subprocess.Popen(
        ["cmd", "/c", "start", "", url],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return {"opened": url}

EXECUTORS = {
    "shell": lambda p: execute_shell(**p),
    "read_file": lambda p: execute_read(**p),
    "write_file": lambda p: execute_write(**p),
    "screenshot": lambda p: execute_screenshot(),
    "browser_open": lambda p: execute_browser(**p),
}

# ---------- App ----------
app = FastAPI(title="Laptop Bridge v2", version="2.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)

# ---------- Models ----------
class ShellReq(BaseModel):
    command: str
    cwd: Optional[str] = None
    timeout: int = 60

class ReadReq(BaseModel):
    path: str
    max_bytes: int = 200_000

class WriteReq(BaseModel):
    path: str
    content: str
    encoding: str = "utf-8"

class TaskSubmit(BaseModel):
    task_type: str
    payload: dict
    priority: int = 5

class WorkerTickRes(BaseModel):
    task: Optional[dict] = None
    pending_count: int

# ---------- Direct endpoints (v1 compat) ----------
@app.get("/ping")
async def ping():
    return {
        "pong": True,
        "hostname": os.environ.get("COMPUTERNAME", "unknown"),
        "platform": sys.platform,
        "user": os.environ.get("USERNAME", "unknown"),
        "cwd": str(WORKDIR),
        "version": "2.0",
        "uptime_s": time.time() - START_TIME,
    }

START_TIME = time.time()

@app.get("/health")
async def health():
    return {"status": "ok", "service": "laptop-bridge", "version": "2.0"}

@app.post("/shell", dependencies=[Depends(verify_token)])
async def shell(req: ShellReq):
    return execute_shell(req.command, req.cwd, req.timeout)

@app.post("/read", dependencies=[Depends(verify_token)])
async def read_file(req: ReadReq):
    return execute_read(req.path, req.max_bytes)

@app.post("/write", dependencies=[Depends(verify_token)])
async def write_file(req: WriteReq):
    return execute_write(req.path, req.content, req.encoding)

@app.post("/screenshot", dependencies=[Depends(verify_token)])
async def screenshot():
    return execute_screenshot()

@app.post("/browser", dependencies=[Depends(verify_token)])
async def browser(action: str, url: Optional[str] = None):
    if action == "open" and url:
        return execute_browser(url)
    raise HTTPException(400, f"Unknown action: {action}")

# ---------- Queue endpoints (v2 new) ----------
@app.post("/queue/submit", dependencies=[Depends(verify_token)])
async def queue_submit(req: TaskSubmit):
    """Cloud submits a task. Returns task_id."""
    if req.task_type not in EXECUTORS:
        raise HTTPException(400, f"Unknown task type: {req.task_type}. Available: {list(EXECUTORS.keys())}")
    with db() as conn:
        cur = conn.execute(
            "INSERT INTO tasks (task_type, payload, priority) VALUES (?, ?, ?)",
            (req.task_type, json.dumps(req.payload), req.priority),
        )
        task_id = cur.lastrowid
        cur = conn.execute("SELECT COUNT(*) as c FROM tasks WHERE status='pending'")
        pending = cur.fetchone()["c"]
    return {"task_id": task_id, "status": "pending", "pending_count": pending}

@app.post("/queue/worker_tick", response_model=WorkerTickRes, dependencies=[Depends(verify_token)])
async def worker_tick():
    """Laptop worker calls this to claim next task. Auto-executes and writes result."""
    with db() as conn:
        cur = conn.execute(
            """SELECT id, task_type, payload FROM tasks 
               WHERE status='pending' 
               ORDER BY priority, id LIMIT 1"""
        )
        row = cur.fetchone()
        if not row:
            cur = conn.execute("SELECT COUNT(*) as c FROM tasks WHERE status='pending'")
            return {"task": None, "pending_count": cur.fetchone()["c"]}
        
        task_id = row["id"]
        task_type = row["task_type"]
        payload = json.loads(row["payload"])
        
        # Mark running
        conn.execute(
            "UPDATE tasks SET status='running', started_at=CURRENT_TIMESTAMP WHERE id=?",
            (task_id,),
        )
        cur = conn.execute("SELECT COUNT(*) as c FROM tasks WHERE status='pending'")
        pending = cur.fetchone()["c"]
    
    # Execute OUTSIDE the lock
    try:
        result = EXECUTORS[task_type](payload)
        with db() as conn:
            if "error" in result:
                conn.execute(
                    "UPDATE tasks SET status='error', result=?, error=?, completed_at=CURRENT_TIMESTAMP WHERE id=?",
                    (json.dumps(result), result["error"], task_id),
                )
            else:
                conn.execute(
                    "UPDATE tasks SET status='done', result=?, completed_at=CURRENT_TIMESTAMP WHERE id=?",
                    (json.dumps(result), task_id),
                )
    except Exception as e:
        with db() as conn:
            conn.execute(
                "UPDATE tasks SET status='error', error=?, completed_at=CURRENT_TIMESTAMP WHERE id=?",
                (str(e), task_id),
            )
    
    return {
        "task": {"id": task_id, "type": task_type, "result_status": "done"},
        "pending_count": pending,
    }

@app.get("/queue/result/{task_id}", dependencies=[Depends(verify_token)])
async def queue_result(task_id: int, wait: int = 0):
    """Cloud polls for task result. wait=max seconds to block."""
    deadline = time.time() + wait
    while True:
        with db() as conn:
            cur = conn.execute(
                "SELECT status, result, error, started_at, completed_at FROM tasks WHERE id=?",
                (task_id,),
            )
            row = cur.fetchone()
        if not row:
            raise HTTPException(404, f"Task {task_id} not found")
        if row["status"] in ("done", "error"):
            return {
                "task_id": task_id,
                "status": row["status"],
                "result": json.loads(row["result"]) if row["result"] else None,
                "error": row["error"],
                "started_at": row["started_at"],
                "completed_at": row["completed_at"],
            }
        if time.time() >= deadline:
            return {"task_id": task_id, "status": row["status"]}
        time.sleep(0.5)

@app.get("/queue/list", dependencies=[Depends(verify_token)])
async def queue_list(status: Optional[str] = None, limit: int = 20):
    """List tasks, optionally filtered by status."""
    with db() as conn:
        if status:
            cur = conn.execute(
                "SELECT * FROM tasks WHERE status=? ORDER BY id DESC LIMIT ?",
                (status, limit),
            )
        else:
            cur = conn.execute(
                "SELECT * FROM tasks ORDER BY id DESC LIMIT ?", (limit,)
            )
        rows = [dict(r) for r in cur.fetchall()]
    # Decode JSON fields
    for r in rows:
        try: r["payload"] = json.loads(r["payload"])
        except: pass
        if r.get("result"): 
            try: r["result"] = json.loads(r["result"])
            except: pass
    return {"tasks": rows}

# ---------- Background worker (auto-tick) ----------
_worker_thread = None
_worker_stop = threading.Event()
_worker_lock = threading.Lock()

def _process_one_task() -> bool:
    """Process one pending task in-process (no HTTP). Returns True if a task was processed."""
    with _worker_lock:
        with db() as conn:
            cur = conn.execute(
                """SELECT id, task_type, payload FROM tasks
                   WHERE status='pending'
                   ORDER BY priority, id LIMIT 1"""
            )
            row = cur.fetchone()
            if not row:
                return False
            task_id = row["id"]
            task_type = row["task_type"]
            try:
                payload = json.loads(row["payload"])
            except Exception:
                payload = {}
            conn.execute(
                "UPDATE tasks SET status='running', started_at=CURRENT_TIMESTAMP WHERE id=?",
                (task_id,),
            )
        # Execute OUTSIDE the DB lock
        try:
            result = EXECUTORS[task_type](payload)
            with db() as conn:
                if isinstance(result, dict) and "error" in result:
                    conn.execute(
                        "UPDATE tasks SET status='error', result=?, error=?, completed_at=CURRENT_TIMESTAMP WHERE id=?",
                        (json.dumps(result), result.get("error", "unknown"), task_id),
                    )
                else:
                    conn.execute(
                        "UPDATE tasks SET status='done', result=?, completed_at=CURRENT_TIMESTAMP WHERE id=?",
                        (json.dumps(result), task_id),
                    )
        except Exception as e:
            with db() as conn:
                conn.execute(
                    "UPDATE tasks SET status='error', error=?, completed_at=CURRENT_TIMESTAMP WHERE id=?",
                    (str(e), task_id),
                )
        return True

def background_worker():
    """Background thread that processes the queue in-process every 1 second."""
    while not _worker_stop.is_set():
        try:
            _process_one_task()
        except Exception:
            pass
        _worker_stop.wait(1.0)

@app.on_event("startup")
async def start_worker():
    global _worker_thread
    if _worker_thread is None or not _worker_thread.is_alive():
        _worker_thread = threading.Thread(target=background_worker, daemon=True)
        _worker_thread.start()

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("BRIDGE_PORT", "8765"))
    host = os.environ.get("BRIDGE_HOST", "127.0.0.1")
    uvicorn.run(app, host=host, port=port, log_level="info")
