#!/usr/bin/env python3
"""Extension 16 Round 2: performs one LocalSend v2 send (prepare-upload +
upload) to a single already-discovered device. Launched as a fixed argv-list
Process from LocalSendMonitor.qml (no shell involved, so a hostile filename
in argv is not a shell-injection risk) — mirrors localsend_discover.py's
Round 1 precedent of shelling out to Python for what QML/Quickshell.Io has
no native primitive for (here: multipart-free raw-body HTTPS POST with an
unverified self-signed cert, matching real LocalSend clients' own trust
model per the protocol spec's "fingerprint is only used to avoid
self-discovery" — there is no CA-based verification in this protocol).

Text mode: a first argument of the form "text:<payload>" (real paths are
absolute, so they never start with "text:") sends the payload as a LocalSend
text message — a text/plain file whose `preview` carries the text. Receivers
show it as a message and usually answer 204 (nothing to upload); if one asks
for the file anyway, the text is uploaded as a .txt.

Prints exactly one JSON line to stdout when done: either
{"status": "success"} or {"status": "error", "message": "..."}.
"""
import sys
import os
import json
import hashlib
import mimetypes
import ssl
import subprocess
import urllib.request
import urllib.error
import uuid

HOME = os.path.expanduser("~")
CONFIG_DIR = os.path.join(HOME, ".config", "quickshell")
CERT_PATH = os.path.join(CONFIG_DIR, "localsend_cert.pem")
KEY_PATH = os.path.join(CONFIG_DIR, "localsend_key.pem")


def ensure_cert():
    # Same persisted identity localsend_server.py's receiver side already
    # uses (generated once, reused forever) — kept as its own copy rather
    # than a shared import per this project's small-single-purpose-script
    # convention, but must stay in sync if the generation command changes.
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


def main():
    if len(sys.argv) != 8:
        print(json.dumps({"status": "error", "message": "wrong argument count"}))
        return

    file_path, ip, port_str, protocol, alias, device_model, fingerprint = sys.argv[1:8]

    text = None
    if file_path.startswith("text:"):
        text = file_path[len("text:"):]
        if not text:
            print(json.dumps({"status": "error", "message": "empty text"}))
            return
    elif not os.path.isfile(file_path):
        print(json.dumps({"status": "error", "message": "file not found"}))
        return

    try:
        port = int(port_str)
    except ValueError:
        print(json.dumps({"status": "error", "message": "invalid port"}))
        return

    file_id = str(uuid.uuid4())
    if text is not None:
        payload = text.encode("utf-8")
        size = len(payload)
        file_name = file_id + ".txt"
        mime_type = "text/plain"
        sha256 = hashlib.sha256(payload)
    else:
        payload = None
        size = os.path.getsize(file_path)
        file_name = os.path.basename(file_path)
        mime_type = mimetypes.guess_type(file_name)[0] or "application/octet-stream"
        sha256 = hashlib.sha256()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                sha256.update(chunk)

    file_meta = {
        "id": file_id,
        "fileName": file_name,
        "size": size,
        "fileType": mime_type,
        "sha256": sha256.hexdigest(),
    }
    if text is not None:
        file_meta["preview"] = text

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    # Real bug found live: a receiving LocalSend server (confirmed against
    # an actual Android phone) does mutual TLS — it sends a
    # CertificateRequest during the handshake and aborts with a fatal
    # "certificate required" alert if the connecting client doesn't present
    # one, regardless of whether the client verifies the server's cert. The
    # client's own self-signed cert acts as its identity here, same as the
    # server side already does with this exact persisted cert/key pair.
    ensure_cert()
    ctx.load_cert_chain(certfile=CERT_PATH, keyfile=KEY_PATH)

    base = "%s://%s:%d/api/localsend/v2" % (protocol, ip, port)

    prep_body = json.dumps({
        "info": {
            "alias": alias,
            "version": "2.0",
            "deviceModel": device_model,
            "deviceType": "desktop",
            "fingerprint": fingerprint,
            "port": 53317,
            "protocol": "https",
            "download": False,
        },
        "files": {
            file_id: file_meta
        },
    }).encode("utf-8")

    prep_req = urllib.request.Request(
        base + "/prepare-upload",
        data=prep_body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(prep_req, context=ctx, timeout=15) as resp:
            if resp.status == 204:
                # Text message shown by the receiver; nothing to upload.
                print(json.dumps({"status": "success"}))
                return
            prep_resp = json.loads(resp.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        if e.code == 204:
            print(json.dumps({"status": "success", "message": "receiver needs no file transfer"}))
            return
        reasons = {
            400: "invalid request",
            401: "PIN required or invalid",
            403: "rejected by receiver",
            409: "receiver busy with another session",
            429: "too many requests",
            500: "receiver error",
        }
        print(json.dumps({"status": "error", "message": "prepare-upload: HTTP %d (%s)" % (e.code, reasons.get(e.code, "unknown"))}))
        return
    except Exception as e:
        print(json.dumps({"status": "error", "message": "prepare-upload failed: %s" % e}))
        return

    session_id = prep_resp.get("sessionId")
    token = (prep_resp.get("files") or {}).get(file_id)
    if not session_id or not token:
        print(json.dumps({"status": "error", "message": "prepare-upload: missing sessionId/token in response"}))
        return

    upload_url = "%s/upload?sessionId=%s&fileId=%s&token=%s" % (base, session_id, file_id, token)

    if payload is not None:
        file_bytes = payload
    else:
        with open(file_path, "rb") as f:
            file_bytes = f.read()

    upload_req = urllib.request.Request(upload_url, data=file_bytes, method="POST")
    try:
        with urllib.request.urlopen(upload_req, context=ctx, timeout=120) as resp:
            resp.read()
        print(json.dumps({"status": "success"}))
    except urllib.error.HTTPError as e:
        reasons = {
            400: "missing parameters",
            403: "invalid token or IP",
            409: "receiver busy",
            422: "checksum mismatch",
            500: "receiver error",
        }
        print(json.dumps({"status": "error", "message": "upload: HTTP %d (%s)" % (e.code, reasons.get(e.code, "unknown"))}))
    except Exception as e:
        print(json.dumps({"status": "error", "message": "upload failed: %s" % e}))


if __name__ == "__main__":
    main()
