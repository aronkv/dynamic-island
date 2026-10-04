#!/usr/bin/env python3
# LocalSend multicast discovery listener (protocol v2.2, confirmed against
# github.com/localsend/protocol's real README.md — group/port below are the
# documented defaults, not guessed). No QML/Quickshell.Io primitive exists
# for a raw UDP datagram socket (Quickshell.Io.Socket wraps QLocalSocket,
# Unix-domain only), so this is shelled out to as a Process, as a
# fixed helper script. Prints one JSON line per
# announcement received, unbuffered, for a Quickshell SplitParser to consume.
import json
import os
import socket
import sys
import threading
import time


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

GROUP = "224.0.0.167"
PORT = 53317

# Extension 24: this device's own identity, matching localsend_send.py's
# already-hardcoded outbound alias/deviceModel/fingerprint exactly, so we
# present the same identity whether sending or (now) receiving. Confirmed
# against the real protocol spec (github.com/localsend/protocol) that the
# multicast announcement schema is the /register body plus "announce": true
# — that flag is what tells other listeners "reply to me," per the spec's
# own note that "a response is only triggered when announce is true."
ANNOUNCE_PAYLOAD = json.dumps({
    "alias": "Dynamic Island",
    "version": "2.0",
    "deviceModel": "Linux",
    "deviceType": "desktop",
    "fingerprint": "quickshell-dynamic-island",
    "port": PORT,
    "protocol": "https",
    "download": False,
    "announce": True,
}).encode("utf-8")
ANNOUNCE_INTERVAL_S = 5

# Single-instance guard: SO_REUSEADDR below lets multiple copies of this
# script bind the same UDP port without erroring, which meant a killed-and-
# relaunched `qs` (this project's established restart procedure kills the
# parent PID directly, which does not propagate SIGTERM to children) leaked
# one more orphaned instance of this infinite recvfrom() loop on every
# single restart — confirmed live: 4 were found running simultaneously after
# a normal session's worth of iterative restarts. A PID-file lock makes a
# fresh launch check for and replace any stale/still-alive previous instance
# instead of silently piling up.
LOCK_PATH = "/tmp/localsend_discover.lock"
try:
    with open(LOCK_PATH) as f:
        old_pid = int(f.read().strip())
    os.kill(old_pid, 15)
    time.sleep(0.2)
except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
    pass
with open(LOCK_PATH, "w") as f:
    f.write(str(os.getpid()))

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("", PORT))
mreq = socket.inet_aton(GROUP) + socket.inet_aton("0.0.0.0")
sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

# Fixes the one-way-visibility bug: this device used to only ever listen,
# never announce, so a laptop could see a phone's announcements but the
# phone's own LocalSend app never saw the laptop. A separate send-only
# socket (not the multicast-joined `sock` above) keeps this independent of
# the receive loop below.
announce_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
announce_sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)


def announce_loop():
    while True:
        try:
            announce_sock.sendto(ANNOUNCE_PAYLOAD, (GROUP, PORT))
        except OSError:
            pass
        time.sleep(ANNOUNCE_INTERVAL_S)


threading.Thread(target=announce_loop, daemon=True).start()

# Real bug found live: multicast loopback is on by default on Linux, so
# this process receives its own announce_loop() broadcasts above and would
# otherwise list itself as a discoverable/sendable device (confirmed via a
# headless qs run logging "LocalSend device seen: Dynamic Island... " for
# this exact machine). Filter by our own fixed fingerprint rather than by
# source IP, since IP alone can't distinguish "us" from another device
# behind the same NAT/interface.
OWN_FINGERPRINT = "quickshell-dynamic-island"

while True:
    data, addr = sock.recvfrom(65535)
    try:
        payload = json.loads(data.decode("utf-8"))
    except Exception:
        continue
    if not isinstance(payload, dict) or "alias" not in payload:
        continue
    if payload.get("fingerprint") == OWN_FINGERPRINT:
        continue
    payload["_ip"] = addr[0]
    payload["_seen"] = time.time()
    print(json.dumps(payload), flush=True)
