#!/usr/bin/env python3
"""Reloads Spotify's page live via the Chrome DevTools Protocol instead
of restarting the whole Electron process — mirrors exactly what
`spicetify watch -s` itself does internally (confirmed by reading
spicetify/cli's own source, src/utils/watcher.go's GetDebuggerPath/
SendReload): GET http://localhost:9222/json/list for Spotify's own
`webSocketDebuggerUrl`, then send a `Runtime.evaluate` CDP command
running `window.location.reload()`.

Requires Spotify to have been launched once with `--remote-debugging-
port=9222 --remote-allow-origins=*` (and devtools enabled via `spicetify
enable-devtools`) — a one-time setup step, not something this script
does itself. If the debugger endpoint isn't reachable (Spotify not
running, or launched without those flags), this silently does nothing —
the caller's own restart-based fallback stays available.

No third-party dependencies — hand-rolls the minimal RFC6455 WebSocket
client handshake + a single masked text frame, since neither
`websocket-client` nor `websockets` is installed and this is a one-shot
fire-and-forget call, not worth adding a dependency for.
"""
import json
import os
import socket
import struct
import subprocess
import time
import urllib.request
import urllib.error
from urllib.parse import urlparse

SPOTIFY_BIN = os.path.expanduser(
    "~/.local/share/spotify-launcher/install/usr/share/spotify/spotify")


def get_debugger_url():
    try:
        with urllib.request.urlopen("http://localhost:9222/json/list", timeout=2) as res:
            targets = json.loads(res.read())
    except (urllib.error.URLError, OSError, json.JSONDecodeError):
        return None
    for target in targets:
        if "spotify" in target.get("url", ""):
            return target.get("webSocketDebuggerUrl")
    return None


def send_reload(ws_url):
    parsed = urlparse(ws_url)
    host, port = parsed.hostname, parsed.port or 80
    path = parsed.path or "/"

    sock = socket.create_connection((host, port), timeout=2)
    key = os.urandom(16)
    import base64
    handshake = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {base64.b64encode(key).decode()}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    sock.sendall(handshake.encode())
    response = sock.recv(4096)
    if b"101" not in response.split(b"\r\n", 1)[0]:
        sock.close()
        raise ConnectionError("WebSocket handshake failed: " + response[:80].decode(errors="replace"))

    payload = json.dumps({
        "id": 0,
        "method": "Runtime.evaluate",
        "params": {"expression": "window.location.reload()"},
    }).encode()

    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    length = len(payload)
    if length <= 125:
        header = struct.pack("!BB", 0x81, 0x80 | length)
    elif length <= 65535:
        header = struct.pack("!BBH", 0x81, 0x80 | 126, length)
    else:
        header = struct.pack("!BBQ", 0x81, 0x80 | 127, length)

    sock.sendall(header + mask + masked)
    sock.close()


def is_spotify_running():
    result = subprocess.run(["pgrep", "-x", "spotify"], capture_output=True)
    return result.returncode == 0


def relaunch_with_debugger():
    """Spotify was open but not started with the debug port on (e.g. the
    user launched it normally, or the very first time this runs) — kill
    it and relaunch the already-installed binary directly with the CDP
    flags. Only spicetify's own `enable-devtools` (a one-time, separate
    step) makes the flag actually take effect; without it Chromium
    ignores --remote-debugging-port for security."""
    subprocess.run(["pkill", "-x", "spotify"])
    time.sleep(1)
    if not os.path.exists(SPOTIFY_BIN):
        return
    subprocess.Popen(
        [SPOTIFY_BIN, "--remote-debugging-port=9222", "--remote-allow-origins=*"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL, start_new_session=True,
    )


def main():
    if not is_spotify_running():
        return

    ws_url = get_debugger_url()
    if not ws_url:
        # Spotify is running but not the debug-enabled instance (normal
        # launch icon/autostart doesn't add our flags) — relaunch it once
        # with them so every subsequent theme switch can live-reload.
        # This one switch still shows a restart; the next ones won't.
        relaunch_with_debugger()
        return

    try:
        send_reload(ws_url)
    except (OSError, ConnectionError):
        pass


if __name__ == "__main__":
    main()
