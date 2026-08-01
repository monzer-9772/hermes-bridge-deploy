#!/usr/bin/env python3
"""
Hermes Bridge v5 - Visual Edition (Server)

Drop-in successor to server.py (v3) that adds VNC-style visual+interactive
control of the laptop's Chrome browser.

What it adds on top of v3 (server.py):

  *  /start-browser         POST  {url?}      - Boot Chrome with --remote-debugging-port=9222
                                                 on the laptop and return the WS debugger URL.
  *  /screenshot            GET   ?fmt=...    - Current browser frame as base64 PNG (or JPEG).
  *  /browser-status        GET                - Is Chrome running? debugger URL, active tab, etc.
  *  /cdp                   POST  {method,params,tabId?}
                                               - Raw Chrome DevTools Protocol passthrough
                                                 (navigate, click, type, evaluate, etc.).
  *  /cdp-tabs              GET                - List open tabs (title, url, type, webSocketDebuggerUrl).
  *  /screencast            WS                  - Frame-by-frame screenshot push (one frame per
                                                 client message; simple VNC-lite over WS).
  *  /screencast.html       GET                - Tiny viewer page (HTML + canvas) that opens
                                                 /screencast and shows input overlay.

How the laptop side does it
---------------------------
The laptop already runs bridge_agent.py / laptop_agent_v5.py which loads
browser_actions.py. That module speaks raw CDP to chrome.exe on 127.0.0.1:9222.

v5_visual.py does NOT spawn Chrome locally (we run on the server). It delegates
*every* CDP-level call back to the laptop via the existing WebSocket
send_command() pipeline, using:

  * action_type="browser"   for the 22 high-level browser_* actions
  * action_type="cdp_raw"   for arbitrary CDP method passthrough (see below)

To make raw CDP passthrough work, the laptop's browser_actions.py needs a
single new dispatcher function: `browser_cdp_raw(args)`. v5_visual.py falls
back gracefully (returns 501) if the laptop is still on an older build.

The cloudflare tunnel already exposes the server's port, so once the server
runs v5_visual.py the user can:
  curl  https://<tunnel>/browser-status?laptop_id=abdul@abd
  curl  https://<tunnel>/screenshot?laptop_id=abdul@abd
  wscat https://<tunnel>/ws/visual?laptop_id=abdul@abd

Configuration
-------------
  AUTH_TOKEN   same as v3 (default: hm-bridge-2026-secure-token-v3)
  PORT         same default as v3 (8765); task mentions 7777 - override with PORT env
  LAPTOP_ID    default laptop id to use when query param is omitted (abdul@abd)

Designed to be run on the *server* side (this VM/container). Does NOT touch
the existing server.py; run as a separate process on a different port OR
replace server.py once verified.
"""
import asyncio
import base64
import json
import logging
import os
import time
from datetime import datetime, timedelta
from typing import Any, Dict, Optional

from aiohttp import web, WSMsgType

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AUTH_TOKEN = os.environ.get("HERMES_BRIDGE_TOKEN", "hm-bridge-2026-secure-token-v3")
PORT = int(os.environ.get("PORT", "8765"))  # v3 default; set 7777 if you want to match the task
DEFAULT_LAPTOP_ID = os.environ.get("HERMES_DEFAULT_LAPTOP", "abdul@abd")

LOG_FILE = os.environ.get("BRIDGE_LOG_FILE", os.path.join(os.path.dirname(os.path.abspath(__file__)), "v5_visual.log"))
SCREENCAST_DEFAULT_INTERVAL = float(os.environ.get("SCREENCAST_INTERVAL", "0.4"))  # 2.5 fps
SCREENCAST_MAX_FRAMES = int(os.environ.get("SCREENCAST_MAX_FRAMES", "0"))  # 0 = unlimited
SCREENSHOT_DEFAULT_FORMAT = os.environ.get("SCREENSHOT_DEFAULT_FORMAT", "png")  # png|jpeg

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] [v5_visual] %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ],
)
logger = logging.getLogger('hermes-bridge-v5')

# ---------------------------------------------------------------------------
# In-memory state (per laptop_id)
# ---------------------------------------------------------------------------
connected_laptops: Dict[str, Dict[str, Any]] = {}
pending_commands: Dict[str, asyncio.Future] = {}
command_counter = 0
command_lock = asyncio.Lock()

# Per-laptop browser state cache (refreshed on every browser_* call)
browser_state: Dict[str, Dict[str, Any]] = {}


def get_laptop_status(laptop_id: str) -> Dict[str, Any]:
    if laptop_id not in connected_laptops:
        return {'connected': False}
    info = connected_laptops[laptop_id]
    age = (datetime.now() - info['last_seen']).total_seconds()
    return {
        'connected': age < 60,
        'laptop_id': laptop_id,
        'info': info['info'],
        'last_seen': info['last_seen'].isoformat(),
        'age_seconds': age,
        'stale': age > 60,
    }


# ---------------------------------------------------------------------------
# WebSocket: laptop agent <-> server
# ---------------------------------------------------------------------------
async def websocket_handler(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse(heartbeat=15, timeout=3600, autoclose=False,
                                max_msg_size=32 * 1024 * 1024)
    await ws.prepare(request)

    peer = request.remote
    logger.info(f"🔌 New connection from {peer}")
    laptop_id: Optional[str] = None
    authenticated = False

    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    msg_type = data.get('type')

                    if msg_type == 'auth':
                        if data.get('token') == AUTH_TOKEN:
                            authenticated = True
                            await ws.send_json({'type': 'auth_ok'})
                            logger.info(f"✅ Auth OK from {peer}")
                        else:
                            await ws.send_json({'type': 'auth_fail', 'reason': 'invalid_token'})
                            logger.warning(f"❌ Auth FAIL from {peer}")
                            break

                    elif msg_type == 'register' and authenticated:
                        laptop_id = data.get('laptop_id', f"unknown-{peer}")
                        connected_laptops[laptop_id] = {
                            'ws': ws,
                            'info': data.get('info', {}),
                            'last_seen': datetime.now(),
                            'peer': peer,
                            'connected_at': datetime.now(),
                        }
                        logger.info(f"📝 Registered: {laptop_id} ({data.get('info', {}).get('hostname', '?')})")
                        await ws.send_json({'type': 'registered', 'laptop_id': laptop_id})

                    elif msg_type == 'response' and authenticated:
                        cmd_id = data.get('command_id')
                        if cmd_id in pending_commands:
                            pending_commands[cmd_id].set_result(data.get('result'))
                            del pending_commands[cmd_id]

                    elif msg_type == 'heartbeat' and authenticated:
                        if laptop_id in connected_laptops:
                            connected_laptops[laptop_id]['last_seen'] = datetime.now()
                        await ws.send_json({'type': 'heartbeat_ack'})

                    else:
                        if not authenticated and msg_type != 'auth':
                            await ws.send_json({'type': 'error', 'reason': 'not_authenticated'})
                            break

                except json.JSONDecodeError:
                    logger.error(f"Invalid JSON from {peer}")

            elif msg.type == WSMsgType.ERROR:
                logger.error(f"WS error: {ws.exception()}")
                break
    finally:
        if laptop_id and laptop_id in connected_laptops:
            duration = (datetime.now() - connected_laptops[laptop_id].get(
                'connected_at', datetime.now())).total_seconds()
            logger.info(f"❌ Disconnected: {laptop_id} (was connected {duration:.0f}s)")
            del connected_laptops[laptop_id]
        else:
            logger.info(f"❌ Connection closed from {peer}")

    return ws


# ---------------------------------------------------------------------------
# Command dispatch (server -> laptop)
# ---------------------------------------------------------------------------
async def send_command(laptop_id: str, command: Any = None, timeout: int = 30,
                       action_type: str = 'shell', **kwargs) -> Dict[str, Any]:
    """Send a command to a laptop agent and await the response."""
    if laptop_id not in connected_laptops:
        return {'success': False, 'error': f'Laptop {laptop_id} not connected'}

    global command_counter
    async with command_lock:
        command_counter += 1
        cmd_id = f"cmd_{command_counter}"
        future: asyncio.Future = asyncio.Future()
        pending_commands[cmd_id] = future

    msg: Dict[str, Any] = {
        'type': 'command',
        'command_id': cmd_id,
        'action_type': action_type,
    }

    # New: raw CDP passthrough
    if action_type == 'cdp_raw':
        msg['cdp_method'] = kwargs.get('cdp_method', '')
        msg['cdp_params'] = kwargs.get('cdp_params', {})
        msg['tab_id'] = kwargs.get('tab_id')
    elif action_type == 'browser':
        msg['browser_action'] = kwargs.get('browser_action', '')
        msg['browser_args'] = kwargs.get('browser_args', {})
    elif action_type == 'shell':
        msg['command'] = command or ''
    else:
        msg['command'] = command or ''

    try:
        await connected_laptops[laptop_id]['ws'].send_json(msg)
        log_msg = json.dumps(msg)[:120]
        logger.info(f"📤 {cmd_id} -> {laptop_id}: {log_msg}")
        result = await asyncio.wait_for(future, timeout=timeout)
        return result
    except asyncio.TimeoutError:
        if cmd_id in pending_commands:
            del pending_commands[cmd_id]
        return {'success': False, 'error': f'Timeout after {timeout}s'}


# ---------------------------------------------------------------------------
# Convenience: delegate to laptop's browser_actions.py
# ---------------------------------------------------------------------------
async def call_browser(laptop_id: str, action: str, args: Optional[dict] = None,
                       timeout: int = 30) -> Dict[str, Any]:
    """Call a high-level browser_* action on the laptop."""
    return await send_command(
        laptop_id, None, timeout,
        action_type='browser',
        browser_action=action,
        browser_args=args or {},
    )


# ---------------------------------------------------------------------------
# /start-browser  POST  {url?: str, headless?: bool}
# ---------------------------------------------------------------------------
async def start_browser_handler(request: web.Request) -> web.Response:
    """
    Ask the laptop to launch Chrome with --remote-debugging-port=9222 and
    (optionally) navigate to a URL. Returns the debugger URL.

    Implementation: calls the existing browser_open action on the laptop
    (which is defined in browser_actions.py and already starts Chrome with
    the debug flag if it isn't running). This is the v5 Visual Edition's
    idempotent entry point.

    SELF-HOSTED MODE: when v5_visual is running ON the laptop (not on a separate
    server), the laptop is the machine. In that case we skip the WebSocket
    round-trip and call browser_open / launch Chrome directly.
    """
    laptop_id = request.query.get('laptop_id', DEFAULT_LAPTOP_ID)
    try:
        body = await request.json() if request.body_exists else {}
    except Exception:
        body = {}
    url = body.get('url') or 'about:blank'

    # Self-hosted mode: execute locally
    if laptop_id not in connected_laptops and _is_self_hosted():
        result = await _local_browser_open(url)
        browser_state[laptop_id] = {
            'started_at': datetime.now().isoformat(),
            'url': url,
            'result': result,
            'self_hosted': True,
        }
        return web.json_response({
            'success': result.get('success', False),
            'laptop_id': laptop_id,
            'debugger_url_http': 'http://127.0.0.1:9222',
            'debugger_url_ws_root': 'ws://127.0.0.1:9222',
            'self_hosted': True,
            'browser_open_result': result,
        })

    if laptop_id not in connected_laptops:
        return web.json_response(
            {'success': False, 'error': f'Laptop {laptop_id} not connected'},
            status=503,
        )

    # browser_open(url) starts Chrome if needed and navigates.
    result = await call_browser(laptop_id, 'browser_open', {'url': url}, timeout=30)

    # Get the debug URL the laptop is using (it's always 127.0.0.1:9222 on the laptop).
    debug_http = 'http://127.0.0.1:9222'
    debug_ws = 'ws://127.0.0.1:9222'

    browser_state[laptop_id] = {
        'started_at': datetime.now().isoformat(),
        'url': url,
        'result': result,
    }

    return web.json_response({
        'success': result.get('success', False),
        'laptop_id': laptop_id,
        'debugger_url_http': debug_http,
        'debugger_url_ws_root': debug_ws,
        'note': ('Chrome is running on the LAPTOP. The debug port is reachable from '
                 'the laptop only; the server proxies CDP calls through the laptop agent.'),
        'browser_open_result': result,
    })


# ---------------------------------------------------------------------------
# /browser-status  GET
# ---------------------------------------------------------------------------
async def browser_status_handler(request: web.Request) -> web.Response:
    laptop_id = request.query.get('laptop_id', DEFAULT_LAPTOP_ID)

    # Self-hosted mode: query local Chrome directly
    if laptop_id not in connected_laptops and _is_self_hosted():
        tabs_result = await _local_list_tabs()
        chrome_running = tabs_result.get('success', False)
        active = None
        if chrome_running and tabs_result.get('tabs'):
            active = tabs_result['tabs'][0]
        return web.json_response({
            'success': True,
            'laptop_id': laptop_id,
            'laptop_connected': True,
            'self_hosted': True,
            'chrome_running_on_laptop': chrome_running,
            'debugger_url_http': 'http://127.0.0.1:9222',
            'debugger_url_ws_root': 'ws://127.0.0.1:9222',
            'tabs': tabs_result,
            'active_url': active.get('url') if active else None,
            'active_title': active.get('title') if active else None,
            'cached_state': browser_state.get(laptop_id),
        })

    if laptop_id not in connected_laptops:
        return web.json_response(
            {'success': False, 'connected': False,
             'error': f'Laptop {laptop_id} not connected'},
            status=503,
        )

    # 1. List tabs (this also tells us if CDP is reachable on the laptop)
    tabs_result = await call_browser(laptop_id, 'browser_list_tabs', {}, timeout=10)

    # 2. Get current URL of the active tab
    url_result = await call_browser(laptop_id, 'browser_get_url', {}, timeout=10)
    title_result = await call_browser(laptop_id, 'browser_get_title', {}, timeout=10)

    return web.json_response({
        'success': True,
        'laptop_id': laptop_id,
        'laptop_connected': True,
        'chrome_running_on_laptop': tabs_result.get('success', False),
        'debugger_url_http': 'http://127.0.0.1:9222',
        'debugger_url_ws_root': 'ws://127.0.0.1:9222',
        'tabs': tabs_result,
        'active_url': url_result,
        'active_title': title_result,
        'cached_state': browser_state.get(laptop_id),
    })


# ---------------------------------------------------------------------------
# /screenshot  GET  ?fmt=png|jpeg&q=70
# ---------------------------------------------------------------------------
async def screenshot_handler(request: web.Request) -> web.Response:
    laptop_id = request.query.get('laptop_id', DEFAULT_LAPTOP_ID)
    fmt = request.query.get('fmt', SCREENSHOT_DEFAULT_FORMAT).lower()
    if fmt not in ('png', 'jpeg', 'jpg'):
        fmt = 'png'
    quality = int(request.query.get('q', '70'))

    # Self-hosted mode: capture locally via CDP
    if laptop_id not in connected_laptops and _is_self_hosted():
        r = await _local_screenshot_browser(fmt=fmt if fmt in ('png', 'jpeg') else 'png')
        if not r.get('success'):
            return web.json_response(r, status=500)
        return web.json_response({
            'success': True,
            'laptop_id': laptop_id,
            'self_hosted': True,
            'format': r.get('format', fmt),
            'image_base64': r.get('data'),
            'ts': datetime.now().isoformat(),
        })

    if laptop_id not in connected_laptops:
        return web.json_response(
            {'success': False, 'error': f'Laptop {laptop_id} not connected'},
            status=503,
        )

    # browser_screenshot already supports format, full_page, and path. We ask
    # for the in-memory base64 by omitting path and reading the b64 key the
    # laptop returns. (browser_actions.py returns either file path or base64.)
    res = await call_browser(
        laptop_id, 'browser_screenshot',
        {'format': fmt, 'quality': quality, 'return_base64': True},
        timeout=20,
    )

    if not res.get('success', False):
        return web.json_response(res, status=500)

    # Two possible return shapes from the laptop:
    #   a) {'success': True, 'path': 'C:\\...\\screen.png'}
    #   b) {'success': True, 'data': '<base64>', 'format': 'png'}
    if 'data' in res and res['data']:
        b64 = res['data']
    elif 'b64' in res and res['b64']:
        b64 = res['b64']
    elif 'path' in res and res['path']:
        # The laptop may have written to disk; we can't read its disk from the
        # server, so require return_base64. Return a clear error.
        return web.json_response({
            'success': False,
            'error': ('laptop wrote screenshot to disk; pass return_base64=True '
                      'in browser_screenshot args to get inline data'),
            'path': res['path'],
        }, status=500)
    else:
        return web.json_response({
            'success': False,
            'error': 'laptop returned no data/path',
            'raw': res,
        }, status=500)

    return web.json_response({
        'success': True,
        'laptop_id': laptop_id,
        'format': res.get('format', fmt),
        'width': res.get('width'),
        'height': res.get('height'),
        'ts': res.get('ts') or datetime.now().isoformat(),
        'image_base64': b64,
    })


# ---------------------------------------------------------------------------
# /cdp  POST  {method, params, tabId?}
# Raw Chrome DevTools Protocol passthrough.
# Requires the laptop to implement action_type='cdp_raw' (browser_cdp_raw).
# Returns 501 if the laptop doesn't have it yet.
# ---------------------------------------------------------------------------
async def cdp_handler(request: web.Request) -> web.Response:
    laptop_id = request.query.get('laptop_id', DEFAULT_LAPTOP_ID)
    try:
        body = await request.json()
    except Exception:
        return web.json_response({'success': False, 'error': 'invalid JSON'}, status=400)

    method = body.get('method')
    params = body.get('params', {})
    tab_id = body.get('tabId') or body.get('tab_id')

    if not method:
        return web.json_response(
            {'success': False, 'error': "missing 'method' (e.g. 'Page.navigate', 'Runtime.evaluate')"},
            status=400,
        )

    # Self-hosted mode: send CDP locally
    if laptop_id not in connected_laptops and _is_self_hosted():
        r = await _local_cdp(method, params, tab_id)
        return web.json_response({**r, 'self_hosted': True})

    if laptop_id not in connected_laptops:
        return web.json_response(
            {'success': False, 'error': f'Laptop {laptop_id} not connected'},
            status=503,
        )

    result = await send_command(
        laptop_id, None, 30,
        action_type='cdp_raw',
        cdp_method=method,
        cdp_params=params,
        tab_id=tab_id,
    )

    # If the laptop doesn't recognise action_type='cdp_raw', it returns
    # "Unknown action_type" or "action not implemented". Surface a clear 501.
    if (not result.get('success')) and result.get('stderr') and \
       ('not implemented' in result['stderr'].lower() or
        'unknown action' in result['stderr'].lower()):
        return web.json_response({
            'success': False,
            'error': 'laptop does not support raw CDP passthrough yet',
            'hint': ("upgrade laptop's browser_actions.py to include "
                     "`browser_cdp_raw(args)` and dispatch action_type='cdp_raw'"),
            'raw': result,
        }, status=501)

    return web.json_response(result)


# ---------------------------------------------------------------------------
# /cdp-tabs  GET
# ---------------------------------------------------------------------------
async def cdp_tabs_handler(request: web.Request) -> web.Response:
    laptop_id = request.query.get('laptop_id', DEFAULT_LAPTOP_ID)
    if laptop_id not in connected_laptops:
        return web.json_response(
            {'success': False, 'error': f'Laptop {laptop_id} not connected'},
            status=503,
        )
    res = await call_browser(laptop_id, 'browser_list_tabs', {}, timeout=10)
    return web.json_response(res)


# ---------------------------------------------------------------------------
# /screencast  WS  (VNC-lite: stream frames as JSON text frames)
# ---------------------------------------------------------------------------
SCREENCAST_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>Hermes Visual Cast</title>
<style>
  body{margin:0;background:#111;color:#eee;font-family:system-ui,sans-serif}
  #bar{position:fixed;top:0;left:0;right:0;background:#222;padding:6px 10px;
       font-size:12px;display:flex;gap:12px;align-items:center;z-index:10}
  #bar input,#bar button{background:#333;color:#eee;border:1px solid #555;
                          padding:3px 8px;border-radius:3px;font-size:12px}
  #stage{position:absolute;top:32px;bottom:0;left:0;right:0;display:flex;
         align-items:center;justify-content:center;overflow:auto}
  #img{max-width:100%;max-height:100%;image-rendering:pixelated;
       box-shadow:0 0 20px #000}
  #log{position:fixed;bottom:4px;right:8px;font-size:11px;color:#888;
       background:rgba(0,0,0,.5);padding:2px 6px;border-radius:3px;z-index:11}
</style></head>
<body>
<div id="bar">
  <span>🎥 Hermes Visual Cast</span>
  <label>FPS <input id="fps" value="2" size="3"></label>
  <label>Quality <input id="q" value="60" size="3"></label>
  <button id="conn">Connect</button>
  <button id="click">Click test (center)</button>
  <span id="status">disconnected</span>
</div>
<div id="stage"><img id="img" alt="(no frame)"></div>
<div id="log"></div>
<script>
let ws=null, frameCount=0, lastFrame=null;
const img=document.getElementById('img');
const log=document.getElementById('log');
const status=document.getElementById('status');
document.getElementById('conn').onclick=()=>{
  if(ws){ws.close();return}
  const url=(location.protocol==='https:'?'wss://':'ws://')+
            location.host+'/ws/visual?laptop_id=__LAPTOP__&fps='+
            document.getElementById('fps').value+'&q='+
            document.getElementById('q').value;
  ws=new WebSocket(url);
  ws.onopen=()=>{status.textContent='connected';};
  ws.onclose=()=>{status.textContent='disconnected';ws=null;};
  ws.onerror=(e)=>{status.textContent='error';console.error(e);};
  ws.onmessage=(ev)=>{
    const m=JSON.parse(ev.data);
    if(m.type==='frame'){
      img.src='data:image/'+(m.format||'png')+';base64,'+m.data;
      lastFrame=m; frameCount++;
      log.textContent='frame '+frameCount+' ('+m.width+'x'+m.height+')';
    } else if(m.type==='log'){
      console.log('[laptop]',m.msg);
    } else if(m.type==='error'){
      status.textContent='err: '+m.error;
    }
  };
};
img.onclick=(e)=>{
  if(!ws||!lastFrame)return;
  const r=img.getBoundingClientRect();
  const x=Math.round((e.clientX-r.left)*lastFrame.width/r.width);
  const y=Math.round((e.clientY-r.top)*lastFrame.height/r.height);
  ws.send(JSON.stringify({type:'click',x,y,button:'left'}));
};
document.getElementById('click').onclick=()=>{
  if(!ws)return;
  ws.send(JSON.stringify({type:'click',x:400,y:300,button:'left'}));
};
</script>
</body></html>
"""


async def screencast_html_handler(request: web.Request) -> web.Response:
    laptop_id = request.query.get('laptop_id', DEFAULT_LAPTOP_ID)
    html = SCREENCAST_HTML.replace('__LAPTOP__', laptop_id)
    return web.Response(text=html, content_type='text/html')


async def screencast_ws_handler(request: web.Request) -> web.WebSocketResponse:
    """
    VNC-lite: server pushes one screenshot frame per `interval` seconds.
    Client can send input events (click/type/scroll) that the server forwards
    as CDP commands to the laptop.
    """
    laptop_id = request.query.get('laptop_id', DEFAULT_LAPTOP_ID)
    interval = float(request.query.get('fps', '0'))  # we'll invert
    if interval > 0:
        interval = 1.0 / interval
    else:
        interval = SCREENCAST_DEFAULT_INTERVAL
    quality = int(request.query.get('q', '60'))
    fmt = request.query.get('fmt', 'jpeg').lower()
    if fmt not in ('png', 'jpeg', 'jpg'):
        fmt = 'jpeg'

    if laptop_id not in connected_laptops:
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        await ws.send_json({'type': 'error', 'error': f'Laptop {laptop_id} not connected'})
        await ws.close()
        return ws

    ws = web.WebSocketResponse(heartbeat=15, timeout=3600, autoclose=False,
                                max_msg_size=16 * 1024 * 1024)
    await ws.prepare(request)
    logger.info(f"📺 Screencast start: laptop={laptop_id} interval={interval:.2f}s fmt={fmt}")

    frames_sent = 0
    last_frame_data: Optional[bytes] = None  # simple compression: skip identical frames

    async def capture_loop():
        nonlocal frames_sent, last_frame_data
        try:
            while not ws.closed:
                res = await call_browser(
                    laptop_id, 'browser_screenshot',
                    {'format': fmt, 'quality': quality, 'return_base64': True},
                    timeout=20,
                )
                if not res.get('success'):
                    await ws.send_json({'type': 'error', 'error': res.get('error', 'screenshot failed')})
                    await asyncio.sleep(interval)
                    continue
                b64 = res.get('data') or res.get('b64') or ''
                if not b64:
                    await ws.send_json({'type': 'error', 'error': 'empty frame'})
                    await asyncio.sleep(interval)
                    continue
                # crude change detection
                raw = base64.b64decode(b64)
                if raw == last_frame_data:
                    await asyncio.sleep(interval)
                    continue
                last_frame_data = raw
                await ws.send_json({
                    'type': 'frame',
                    'format': res.get('format', fmt),
                    'width': res.get('width'),
                    'height': res.get('height'),
                    'ts': res.get('ts') or datetime.now().isoformat(),
                    'data': b64,
                })
                frames_sent += 1
                if SCREENCAST_MAX_FRAMES and frames_sent >= SCREENCAST_MAX_FRAMES:
                    await ws.send_json({'type': 'log', 'msg': 'max_frames_reached, closing'})
                    break
                await asyncio.sleep(interval)
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"screencast capture error: {e}")
        finally:
            if not ws.closed:
                await ws.close()

    capture_task = asyncio.create_task(capture_loop())

    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    evt = json.loads(msg.data)
                except Exception:
                    continue
                etype = evt.get('type')
                # Forward input events as CDP Input.* commands via raw passthrough
                if etype == 'click':
                    x, y = int(evt.get('x', 0)), int(evt.get('y', 0))
                    button = evt.get('button', 'left')
                    for sub in ('mousePressed', 'mouseReleased'):
                        await send_command(
                            laptop_id, None, 10,
                            action_type='cdp_raw',
                            cdp_method='Input.dispatchMouseEvent',
                            cdp_params={'type': sub, 'x': x, 'y': y,
                                        'button': button, 'clickCount': 1},
                        )
                elif etype == 'type':
                    await send_command(
                        laptop_id, None, 10,
                        action_type='cdp_raw',
                        cdp_method='Input.insertText',
                        cdp_params={'text': evt.get('text', '')},
                    )
                elif etype == 'key':
                    await send_command(
                        laptop_id, None, 10,
                        action_type='cdp_raw',
                        cdp_method='Input.dispatchKeyEvent',
                        cdp_params=evt.get('params', {}),
                    )
                elif etype == 'navigate':
                    await send_command(
                        laptop_id, None, 15,
                        action_type='cdp_raw',
                        cdp_method='Page.navigate',
                        cdp_params={'url': evt.get('url', 'about:blank')},
                    )
                elif etype == 'evaluate':
                    await send_command(
                        laptop_id, None, 10,
                        action_type='cdp_raw',
                        cdp_method='Runtime.evaluate',
                        cdp_params={'expression': evt.get('expression', ''),
                                    'returnByValue': True},
                    )
                else:
                    await ws.send_json({'type': 'log', 'msg': f'unknown event: {etype}'})
            elif msg.type == WSMsgType.ERROR:
                break
    finally:
        capture_task.cancel()
        try:
            await capture_task
        except (asyncio.CancelledError, Exception):
            pass
        logger.info(f"📺 Screencast end: laptop={laptop_id} frames={frames_sent}")

    return ws


# ---------------------------------------------------------------------------
# Existing v3 handlers (unchanged shape, kept for compatibility)
# ---------------------------------------------------------------------------
async def command_handler(request: web.Request) -> web.Response:
    laptop_id = request.query.get('laptop_id')
    if not laptop_id:
        return web.json_response({'error': 'Missing laptop_id'}, status=400)
    try:
        body = await request.json()
        result = await send_command(
            laptop_id,
            body.get('command'),
            body.get('timeout', 30),
            action_type=body.get('action_type', 'shell'),
            browser_action=body.get('browser_action'),
            browser_args=body.get('browser_args'),
        )
        return web.json_response(result)
    except Exception as e:
        return web.json_response({'error': str(e)}, status=500)


async def browser_handler(request: web.Request) -> web.Response:
    laptop_id = request.query.get('laptop_id', DEFAULT_LAPTOP_ID)
    if not laptop_id:
        return web.json_response({'error': 'Missing laptop_id'}, status=400)
    try:
        body = await request.json()
        action = body.get('action', '')
        args = body.get('args', {})
        timeout = body.get('timeout', 30)
        result = await send_command(
            laptop_id, None, timeout,
            action_type='browser',
            browser_action=action,
            browser_args=args,
        )
        return web.json_response(result)
    except Exception as e:
        return web.json_response({'error': str(e)}, status=500)


async def health_handler(request: web.Request) -> web.Response:
    n = len(connected_laptops)
    return web.Response(text=f"Hermes Bridge v5 Visual OK | Connected laptops: {n}\n")


async def status_handler(request: web.Request) -> web.Response:
    laptop_id = request.query.get('laptop_id')
    if laptop_id:
        return web.json_response(get_laptop_status(laptop_id))
    return web.json_response({
        'connected_laptops': [
            {
                'laptop_id': lid,
                'hostname': info['info'].get('hostname', '?'),
                'username': info['info'].get('username', '?'),
                'os': info['info'].get('os', '?'),
                'last_seen': info['last_seen'].isoformat(),
                'age_seconds': (datetime.now() - info['last_seen']).total_seconds(),
            }
            for lid, info in connected_laptops.items()
        ],
        'total_commands': command_counter,
        'version': 'v5_visual',
    })


async def tunnel_url_handler(request: web.Request) -> web.Response:
    railway_domain = os.environ.get("RAILWAY_PUBLIC_DOMAIN")
    if railway_domain:
        url = f"https://{railway_domain}"
        return web.json_response({'url': url, 'ws_url': url.replace('https://', 'wss://') + '/ws'})
    url_file = os.environ.get("TUNNEL_URL_FILE", os.path.join(os.path.dirname(os.path.abspath(__file__)), "tunnel_url.txt"))
    if os.path.exists(url_file):
        with open(url_file) as f:
            url = f.read().strip()
        return web.json_response({'url': url, 'ws_url': url.replace('https://', 'wss://') + '/ws'})
    return web.json_response({
        'url': 'https://personalized-snow-meals-disks.trycloudflare.com',
        'ws_url': 'wss://personalized-snow-meals-disks.trycloudflare.com/ws',
    })


# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------
def make_app() -> web.Application:
    app = web.Application()
    # core
    app.router.add_get('/ws', websocket_handler)
    app.router.add_post('/command', command_handler)
    app.router.add_get('/health', health_handler)
    app.router.add_get('/status', status_handler)
    app.router.add_get('/tunnel-url', tunnel_url_handler)
    # v3 browser shortcut (kept)
    app.router.add_post('/browser', browser_handler)
    # v5 visual endpoints (NEW)
    app.router.add_post('/start-browser', start_browser_handler)
    app.router.add_get('/browser-status', browser_status_handler)
    app.router.add_get('/screenshot', screenshot_handler)
    app.router.add_post('/cdp', cdp_handler)
    app.router.add_get('/cdp-tabs', cdp_tabs_handler)
    # VNC-lite screencast
    app.router.add_get('/ws/visual', screencast_ws_handler)
    app.router.add_get('/screencast.html', screencast_html_handler)
    return app


# ---------------------------------------------------------------------------
# Laptop-side patch helper (print instructions on startup)
# ---------------------------------------------------------------------------
LAPTOP_PATCH_INSTRUCTIONS = """
================================================================
v5_visual.py is running. To enable raw CDP passthrough on the
laptop, add the following to the laptop's browser_actions.py
and restart bridge_agent.py:

  def browser_cdp_raw(args):
      \"\"\"args: {method, params, tab_id?}\"\"\"
      import websocket, json
      import urllib.request
      tabs = json.loads(urllib.request.urlopen(\"http://127.0.0.1:9222/json\").read())
      if not tabs:
          return {\"success\": False, \"error\": \"no tabs\"}
      tab = next((t for t in tabs if t.get(\"id\") == args.get(\"tab_id\")), tabs[0])
      ws = websocket.create_connection(tab[\"webSocketDebuggerUrl\"])
      try:
          ws.send(json.dumps({\"id\": 1, \"method\": args[\"method\"],
                              \"params\": args.get(\"params\") or {}}))
          # Read until we see id=1
          while True:
              m = json.loads(ws.recv())
              if m.get(\"id\") == 1:
                  return {\"success\": True, \"result\": m.get(\"result\"),
                          \"error\": m.get(\"error\")}
      finally:
          ws.close()

  BROWSER_ACTIONS[\"browser_cdp_raw\"] = browser_cdp_raw

Also extend the laptop's command dispatcher to accept
action_type == "cdp_raw" and call browser_cdp_raw({"method": cdp_method,
"params": cdp_params, "tab_id": tab_id}).

Until this is deployed, /cdp will return HTTP 501 with a clear hint.
================================================================
"""


# ---------------------------------------------------------------------------
# Optional: Self-register as a laptop with an upstream Hermes server
# ---------------------------------------------------------------------------
async def self_register_loop(upstream_ws: str, laptop_id: str):
    """
    Connect to the upstream server (server.py) as a laptop WebSocket client.
    Receives command frames, dispatches them locally via _dispatch_local_action,
    and sends back results. This lets v5_visual act as both a server and a laptop.
    """
    import websockets  # local import; not needed for server-only mode

    backoff = 1
    while True:
        try:
            logger.info(f"🔗 Registering with upstream: {upstream_ws} as {laptop_id}")
            async with websockets.connect(
                upstream_ws,
                extra_headers={"Authorization": f"Bearer {AUTH_TOKEN}"},
                ping_interval=20,
                ping_timeout=20,
            ) as ws:
                # Send register frame (server.py expects this format)
                register = {
                    "type": "register",
                    "laptop_id": laptop_id,
                    "version": "v5_visual",
                    "capabilities": ["screenshot", "browser", "cdp", "system"],
                }
                await ws.send(json.dumps(register))
                ack = json.loads(await ws.recv())
                logger.info(f"📝 Register ack: {ack}")
                backoff = 1

                async for msg in ws:
                    try:
                        frame = json.loads(msg)
                    except Exception:
                        continue
                    await _handle_upstream_frame(ws, frame, laptop_id)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning(f"⚠️  Upstream connection lost: {e}; retrying in {backoff}s")
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 30)


async def _handle_upstream_frame(ws, frame, laptop_id):
    """Handle a single command frame from the upstream server."""
    if frame.get("type") != "command":
        return
    cmd_id = frame.get("id")
    action = frame.get("action", "")
    args = frame.get("args", {}) or {}
    logger.info(f"📥 Upstream command: {action} (id={cmd_id})")
    try:
        result = await _dispatch_local_action(action, args)
        await ws.send(json.dumps({
            "type": "result",
            "id": cmd_id,
            "laptop_id": laptop_id,
            "success": True,
            "result": result,
        }))
    except Exception as e:
        logger.exception(f"❌ Command {action} failed: {e}")
        await ws.send(json.dumps({
            "type": "result",
            "id": cmd_id,
            "laptop_id": laptop_id,
            "success": False,
            "error": str(e),
        }))


async def _dispatch_local_action(action: str, args: dict):
    """
    Dispatch a command locally on this laptop using browser_actions / shell_actions.
    This is a thin shim around the laptop-side capabilities. For the v5_visual
    use case, the most common actions are: screenshot, browser.*, shell.*, etc.
    """
    # Dynamic import of laptop modules
    import importlib
    try:
        ba = importlib.import_module("browser_actions")
    except ImportError:
        ba = None
    try:
        sa = importlib.import_module("shell_actions")
    except ImportError:
        sa = None

    if action == "screenshot":
        return _local_screenshot(args)
    if action == "shell":
        if sa and hasattr(sa, "shell_run"):
            return await sa.shell_run(args.get("command", ""))
        return _local_shell(args)
    if action.startswith("browser_"):
        if ba and hasattr(ba, "BROWSER_ACTIONS"):
            fn = ba.BROWSER_ACTIONS.get(action)
            if fn:
                return fn(args)
        return {"success": False, "error": f"browser action {action} not available"}
    return {"success": False, "error": f"unknown action: {action}"}


def _local_screenshot(args):
    """Take a screenshot using mss or PIL.ImageGrab."""
    try:
        import mss
        with mss.mss() as sct:
            monitor = sct.monitors[1]  # primary
            img = sct.grab(monitor)
            from PIL import Image
            import io, base64
            pil = Image.frombytes("RGB", img.size, img.rgb, "raw", "RGB")
            buf = io.BytesIO()
            pil.save(buf, format="PNG")
            b64 = base64.b64encode(buf.getvalue()).decode()
            return {"success": True, "format": "png", "data": b64}
    except Exception as e:
        return {"success": False, "error": f"screenshot failed: {e}"}


def _local_shell(args):
    import subprocess
    cmd = args.get("command", "")
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return {"success": True, "stdout": r.stdout, "stderr": r.stderr, "code": r.returncode}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ---------------------------------------------------------------------------
# Self-hosted mode: v5_visual runs ON the laptop, executes commands locally
# ---------------------------------------------------------------------------
import platform as _platform

def _is_self_hosted() -> bool:
    """Return True if v5_visual is running on the laptop (Windows/macOS)."""
    return _platform.system() in ("Windows", "Darwin")


async def _local_browser_open(url: str) -> dict:
    """Open Chrome locally with --remote-debugging-port=9222."""
    import subprocess
    import os as _os
    # Find Chrome
    candidates = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        _os.path.join(_os.environ.get("LOCALAPPDATA", ""), r"Google\Chrome\Application\chrome.exe"),
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    ]
    chrome = next((c for c in candidates if _os.path.exists(c)), None)
    if not chrome:
        return {"success": False, "error": "Chrome not found in standard locations"}

    # Kill any existing Chrome with remote-debugging
    try:
        subprocess.run(
            ["taskkill", "/F", "/IM", "chrome.exe", "/FI", "WINDOWTITLE eq Chrome*"],
            capture_output=True, timeout=5
        )
    except Exception:
        pass
    await asyncio.sleep(1)

    # Start Chrome
    args = [
        chrome,
        "--remote-debugging-port=9222",
        "--remote-allow-origins=*",
        "--no-first-run",
        "--no-default-browser-check",
        url,
    ]
    try:
        proc = subprocess.Popen(
            args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        # Wait for Chrome to come up
        import urllib.request
        for _ in range(20):
            await asyncio.sleep(0.5)
            try:
                with urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=1) as r:
                    tabs = json.loads(r.read())
                    return {"success": True, "pid": proc.pid, "tabs": len(tabs), "url": url}
            except Exception:
                continue
        return {"success": False, "error": "Chrome started but debug port not responding"}
    except Exception as e:
        return {"success": False, "error": str(e)}


async def _local_cdp(method: str, params: dict, tab_id: str = None) -> dict:
    """Send a raw CDP command to the local Chrome instance."""
    try:
        import urllib.request
        with urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=5) as r:
            tabs = json.loads(r.read())
        if not tabs:
            return {"success": False, "error": "no Chrome tabs"}
        tab = next((t for t in tabs if t.get("id") == tab_id), tabs[0])
        ws_url = tab["webSocketDebuggerUrl"]

        try:
            import websocket  # python-websocket-client
        except ImportError:
            return {"success": False, "error": "websocket-client not installed"}

        ws = websocket.create_connection(ws_url, timeout=10)
        try:
            ws.send(json.dumps({"id": 1, "method": method, "params": params or {}}))
            while True:
                msg = json.loads(ws.recv())
                if msg.get("id") == 1:
                    return {
                        "success": True,
                        "result": msg.get("result"),
                        "error": msg.get("error"),
                    }
        finally:
            ws.close()
    except Exception as e:
        return {"success": False, "error": str(e)}


async def _local_screenshot_browser(tab_id: str = None, fmt: str = "png") -> dict:
    """Take a screenshot of the current Chrome tab via CDP."""
    import base64
    r = await _local_cdp("Page.captureScreenshot", {"format": fmt}, tab_id)
    if not r.get("success"):
        return r
    data = r.get("result", {}).get("data", "")
    return {"success": True, "format": fmt, "data": data}


if __name__ == '__main__':
    logger.info(f"🚀 Hermes Bridge v5 Visual on 0.0.0.0:{PORT}")
    logger.info(f"🔑 Auth token: {AUTH_TOKEN[:15]}...")
    logger.info(f"💻 Default laptop: {DEFAULT_LAPTOP_ID}")
    print(LAPTOP_PATCH_INSTRUCTIONS)

    # Optional: Self-register as a laptop with the upstream server (server.py).
    # This makes v5_visual reachable from the existing control plane without
    # needing a separate bridge_agent to be running.
    app = make_app()

    async def _on_startup(app):
        upstream = os.environ.get("HERMES_UPSTREAM_WS", "").strip()
        laptop_id = os.environ.get("HERMES_LAPTOP_ID", DEFAULT_LAPTOP_ID).strip()
        if not upstream:
            logger.info("ℹ️  No HERMES_UPSTREAM_WS set - skipping self-registration")
            return
        logger.info(f"🔗 Self-registering laptop '{laptop_id}' with upstream {upstream}")
        # Run registration in background; retries forever
        app['register_task'] = asyncio.create_task(self_register_loop(upstream, laptop_id))

    async def _on_cleanup(app):
        task = app.get('register_task')
        if task:
            task.cancel()

    app.on_startup.append(_on_startup)
    app.on_cleanup.append(_on_cleanup)

    web.run_app(app, host='0.0.0.0', port=PORT, print=lambda *a, **k: None)
