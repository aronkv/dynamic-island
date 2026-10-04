#!/usr/bin/env python3
"""Extension 24: LocalSend v2 receiver. Implements the real protocol's
receiver-side HTTP API (confirmed against github.com/localsend/protocol's
actual README, not guessed) so this device can be discovered AND actually
receive a push from another LocalSend device (previously this project could
only discover + send, never receive — the exact reason a phone could never
see this laptop as a target).

Endpoints implemented, matching the real spec exactly:
  GET  /api/localsend/v2/info           -> our own device info
  POST /api/localsend/v2/register       -> echoes our own device info back
  POST /api/localsend/v2/prepare-upload -> holds the response until the
                                            user accepts/declines on the
                                            Island (per explicit user
                                            decision: no silent auto-accept)
  POST /api/localsend/v2/upload         -> receives the raw file body,
                                            verifies sha256, writes to
                                            ~/Downloads with collision-safe
                                            renaming
  POST /api/localsend/v2/cancel         -> sender-initiated abort

Self-signed HTTPS, no CA verification — matches localsend_send.py's own
already-established trust model (the protocol spec: "fingerprint is only
used to avoid self-discovery," there is no CA-based verification at all).

Talks to LocalSendMonitor.qml the same way localsend_discover.py already
does: one JSON line per event on stdout (unbuffered), for a SplitParser to
consume. Decisions come back the other way, one JSON line per decision on
stdin (Quickshell's Process.write()/stdinEnabled), read on a dedicated
thread since prepare-upload's HTTP handler thread blocks waiting for one.

Fixed device identity (alias/deviceModel/fingerprint) matches what
localsend_send.py already hardcodes for outbound sends, so this device
presents the same identity whether it's sending or receiving.
"""
import json
import os
import socket
import ssl
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


# Exit together with Quickshell. Restarting qs (reload.sh) left this
# process running, reparented to init: an orphaned server kept TCP 53317,
# so the new instance's own server couldn't start, and duplicate
# discovery processes piled up. PR_SET_PDEATHSIG makes the kernel send
# SIGTERM when the parent dies; the getppid() check covers a parent that
# died before the call.
def _die_with_parent():
    try:
        import ctypes
        import signal
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except Exception:
        pass
    if os.getppid() == 1:
        sys.exit(0)


_die_with_parent()

PORT = 53317
HOME = os.path.expanduser("~")
CONFIG_DIR = os.path.join(HOME, ".config", "quickshell")
CERT_PATH = os.path.join(CONFIG_DIR, "localsend_cert.pem")
KEY_PATH = os.path.join(CONFIG_DIR, "localsend_key.pem")
DOWNLOADS_DIR = os.path.join(HOME, "Downloads")

DEVICE_INFO = {
    "alias": "Dynamic Island",
    "version": "2.0",
    "deviceModel": "Linux",
    "deviceType": "desktop",
    "fingerprint": "quickshell-dynamic-island",
    "port": PORT,
    "protocol": "https",
    "download": False,
}

# Single-instance guard — same rationale/pattern as localsend_discover.py's
# own lock: a killed-and-relaunched `qs` doesn't propagate SIGTERM to
# children, so a stale previous instance would otherwise keep the port bound
# and pile up across restarts.
LOCK_PATH = "/tmp/localsend_server.lock"
try:
    with open(LOCK_PATH) as f:
        old_pid = int(f.read().strip())
    os.kill(old_pid, 15)
    time.sleep(0.3)
except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
    pass
with open(LOCK_PATH, "w") as f:
    f.write(str(os.getpid()))


def log(event):
    print(json.dumps(event), flush=True)


def ensure_cert():
    if os.path.isfile(CERT_PATH) and os.path.isfile(KEY_PATH):
        return
    os.makedirs(CONFIG_DIR, exist_ok=True)
    subprocess.run(
        [
            "openssl", "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", KEY_PATH, "-out", CERT_PATH,
            "-days", "3650", "-nodes", "-subj", "/CN=localhost",
        ],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def unique_dest_path(file_name):
    dest = os.path.join(DOWNLOADS_DIR, file_name)
    if not os.path.exists(dest):
        return dest
    base, ext = os.path.splitext(file_name)
    n = 1
    while True:
        candidate = os.path.join(DOWNLOADS_DIR, "%s (%d)%s" % (base, n, ext))
        if not os.path.exists(candidate):
            return candidate
        n += 1


# sessionId -> {
#   "alias": sender alias, "files": {fileId: {"fileName", "size", "sha256",
#   "dest", "written": bool}}, "decision": None|"accept"|"reject"|"cancelled",
#   "event": threading.Event()
# }
sessions = {}
sessions_lock = threading.Lock()

PENDING_TIMEOUT_S = 120


def stdin_reader():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            cmd = json.loads(line)
        except Exception:
            continue
        session_id = cmd.get("sessionId")
        action = cmd.get("action")
        if not session_id or action not in ("accept", "reject"):
            continue
        with sessions_lock:
            session = sessions.get(session_id)
            if session is None or session["decision"] is not None:
                continue
            session["decision"] = action
            session["event"].set()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass  # stdout is reserved for the structured JSON event protocol

    def _send_json(self, code, body):
        payload = json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _send_empty(self, code):
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _read_body(self):
        # The official LocalSend Android client sends the actual file
        # upload with `Transfer-Encoding: chunked` and no Content-Length at
        # all (confirmed live: prepare-upload's small JSON body always came
        # with a real Content-Length, but the follow-up file upload did
        # not) — the old `int(Content-Length or "0")` read 0 bytes for
        # every chunked upload, silently hashing an empty body and always
        # failing the sha256 check with a 422. http.server's
        # BaseHTTPRequestHandler does not decode chunked *request* bodies
        # on its own (only chunked responses), so it's done manually here:
        # each chunk is a hex size line, that many raw bytes, a trailing
        # CRLF, repeated until a 0-size chunk ends the body.
        if (self.headers.get("Transfer-Encoding") or "").lower() == "chunked":
            body = bytearray()
            while True:
                size_line = self.rfile.readline().strip()
                size = int(size_line.split(b";")[0], 16)
                if size == 0:
                    self.rfile.readline()  # trailing CRLF after the 0-chunk
                    break
                body += self.rfile.read(size)
                self.rfile.read(2)  # CRLF after each chunk's data
            return bytes(body)

        length = int(self.headers.get("Content-Length", "0"))
        return self.rfile.read(length) if length else b""

    def do_GET(self):
        if self.path.startswith("/api/localsend/v2/info"):
            self._send_json(200, DEVICE_INFO)
        else:
            self._send_empty(404)

    def do_POST(self):
        if self.path.startswith("/api/localsend/v2/register"):
            # Real bug found live: a peer that only ever responds to OUR
            # multicast announce (rather than also broadcasting its own)
            # POSTs its info here — confirmed via a live capture that an
            # Android phone does exactly this — but this handler used to
            # just read the body and discard it, so this device could send
            # to and receive from a phone, but never actually saw it as a
            # target to send TO (localsend_discover.py's `devices` list only
            # ever grew from multicast announces, which this peer type never
            # sends). Forward it as the same kind of stdout event
            # localsend_discover.py already prints, so LocalSendMonitor.qml
            # can fold it into the one `devices` list either way.
            try:
                info = json.loads(self._read_body().decode("utf-8"))
            except Exception:
                info = {}
            if isinstance(info, dict) and info.get("alias") and info.get("fingerprint"):
                info["_ip"] = self.client_address[0]
                log(info)
            self._send_json(200, DEVICE_INFO)
            return

        if self.path.startswith("/api/localsend/v2/prepare-upload"):
            self._handle_prepare_upload()
            return

        if self.path.startswith("/api/localsend/v2/upload"):
            self._handle_upload()
            return

        if self.path.startswith("/api/localsend/v2/cancel"):
            self._handle_cancel()
            return

        self._send_empty(404)

    def _handle_prepare_upload(self):
        try:
            body = json.loads(self._read_body().decode("utf-8"))
        except Exception:
            self._send_empty(400)
            return

        info = body.get("info") or {}
        files_in = body.get("files") or {}
        if not files_in:
            self._send_empty(400)
            return

        session_id = str(uuid.uuid4())
        files = {}
        for file_id, meta in files_in.items():
            file_name = meta.get("fileName") or file_id
            files[file_id] = {
                "fileName": file_name,
                "size": meta.get("size", 0),
                "sha256": meta.get("sha256"),
                "token": str(uuid.uuid4()),
                "dest": unique_dest_path(file_name),
                "written": False,
            }

        session = {
            "alias": info.get("alias", "Unknown device"),
            "deviceType": info.get("deviceType") or "desktop",
            "files": files,
            "decision": None,
            "event": threading.Event(),
        }
        with sessions_lock:
            sessions[session_id] = session

        log({
            "event": "incoming",
            "sessionId": session_id,
            "alias": session["alias"],
            "deviceType": session.get("deviceType", "desktop"),
            "files": [
                {"fileName": f["fileName"], "size": f["size"]}
                for f in files.values()
            ],
        })

        got_decision = session["event"].wait(timeout=PENDING_TIMEOUT_S)
        with sessions_lock:
            decision = session["decision"]
            if not got_decision and decision is None:
                decision = session["decision"] = "reject"

        if decision == "accept":
            self._send_json(200, {
                "sessionId": session_id,
                "files": {fid: f["token"] for fid, f in files.items()},
            })
        else:
            if not got_decision:
                log({"event": "expired", "sessionId": session_id})
            with sessions_lock:
                sessions.pop(session_id, None)
            self._send_empty(403)

    def _handle_upload(self):
        from urllib.parse import urlparse, parse_qs
        qs = parse_qs(urlparse(self.path).query)
        session_id = (qs.get("sessionId") or [None])[0]
        file_id = (qs.get("fileId") or [None])[0]
        token = (qs.get("token") or [None])[0]

        with sessions_lock:
            session = sessions.get(session_id) if session_id else None
        if not session or session["decision"] != "accept":
            self._send_empty(403)
            return
        file_entry = session["files"].get(file_id)
        if not file_entry or file_entry["token"] != token:
            self._send_empty(403)
            return

        data = self._read_body()

        if file_entry["sha256"]:
            import hashlib
            actual = hashlib.sha256(data).hexdigest()
            if actual != file_entry["sha256"]:
                self._send_empty(422)
                return

        os.makedirs(DOWNLOADS_DIR, exist_ok=True)
        with open(file_entry["dest"], "wb") as f:
            f.write(data)
        file_entry["written"] = True

        log({
            "event": "received",
            "sessionId": session_id,
            "fileName": os.path.basename(file_entry["dest"]),
        })

        self._send_empty(200)

        with sessions_lock:
            if all(f["written"] for f in session["files"].values()):
                sessions.pop(session_id, None)

    def _handle_cancel(self):
        from urllib.parse import urlparse, parse_qs
        qs = parse_qs(urlparse(self.path).query)
        session_id = (qs.get("sessionId") or [None])[0]
        with sessions_lock:
            session = sessions.pop(session_id, None) if session_id else None
        if session is not None:
            session["decision"] = session["decision"] or "cancelled"
            session["event"].set()
            log({"event": "cancelled", "sessionId": session_id})
        self._send_empty(200)


def main():
    ensure_cert()
    threading.Thread(target=stdin_reader, daemon=True).start()

    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=CERT_PATH, keyfile=KEY_PATH)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
