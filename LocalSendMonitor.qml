import Quickshell
import Quickshell.Io
import QtQuick

// Discovery (Extension 16) + sending (Extension 16 Round 2) + receiving
// (Extension 24). Listens on LocalSend's real multicast group
// (224.0.0.167:53317, confirmed against the actual protocol spec at
// github.com/localsend/protocol — protocol v2.2's documented defaults) for
// device announcements, building a live `devices` list; also announces this
// device's own presence on that same group (localsend_discover.py, fixed in
// Extension 24 — this device used to only ever listen, so a phone could see
// this laptop's discoveries but never see the laptop itself).
//
// No QML/Quickshell.Io primitive exists for a raw UDP datagram socket
// (Quickshell.Io.Socket/SocketServer wrap QLocalSocket — Unix-domain only,
// confirmed via the installed qmltypes; QtNetwork's own qmltypes expose no
// UDP type either, only SslSocket/TCP) — so this shells out to small Python
// helper scripts (localsend_discover.py, localsend_send.py,
// localsend_server.py, all alongside this file) via Process, as a
// fixed helper script (no interpolated/dynamic
// data in the command, so this is safe as a plain argv-list launch of a
// fixed script path).
Item {
    id: localSendMonitor

    // {alias, deviceModel, deviceType, fingerprint, ip, port, protocol, lastSeen}
    property var devices: []

    // Announcements repeat periodically from a real LocalSend instance, but
    // to be safe against a device that only announces once, prune anything
    // not re-seen in a while rather than assuming a single announcement
    // means "still here" forever.
    readonly property int staleAfterMs: 30000

    // Shared by both discovery paths below: a device is learned about either
    // by us overhearing ITS multicast announce (listenerProc), or by a peer
    // that only ever replies to OUR OWN announce via a direct HTTP POST to
    // /register instead of ever multicasting itself (serverProc) — real bug
    // found live: an Android phone does the latter exclusively, so this
    // laptop could see it (it multicasts) and receive from it, but never
    // had it in `devices` to send TO, since only listenerProc used to feed
    // that list. Both paths normalize to the same entry shape here.
    function mergeDevice(payload) {
        if (!payload.alias || !payload.fingerprint) return

        const now = Date.now()
        const entry = {
            alias: payload.alias,
            deviceModel: payload.deviceModel || "",
            deviceType: payload.deviceType || "desktop",
            fingerprint: payload.fingerprint,
            ip: payload._ip || "",
            port: payload.port || 53317,
            protocol: payload.protocol || "https",
            lastSeen: now
        }

        const next = localSendMonitor.devices.filter(d => d.fingerprint !== entry.fingerprint)
        next.push(entry)
        localSendMonitor.devices = next
    }

    Process {
        id: listenerProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/localsend_discover.py"]
        running: true

        stdout: SplitParser {
            onRead: (line) => {
                if (line.trim().length === 0) return
                let payload
                try {
                    payload = JSON.parse(line)
                } catch (e) {
                    return
                }
                localSendMonitor.mergeDevice(payload)
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            const now = Date.now()
            const pruned = localSendMonitor.devices.filter(d => (now - d.lastSeen) < localSendMonitor.staleAfterMs)
            if (pruned.length !== localSendMonitor.devices.length) localSendMonitor.devices = pruned
        }
    }

    // Extension 24: the receiver side. localsend_server.py runs a real
    // HTTPS server implementing the protocol's receiver endpoints (info/
    // register/prepare-upload/upload/cancel, confirmed against the actual
    // spec at github.com/localsend/protocol). Per the explicit user
    // decision, an incoming prepare-upload is never silently auto-accepted
    // — the Python server blocks that HTTP request open and instead prints
    // an "incoming" event line here, waiting for acceptIncoming()/
    // rejectIncoming() to write a decision back over stdin.
    //
    // {sessionId, alias, files: [{fileName, size}]} while a transfer is
    // awaiting the user's decision, else null.
    property var pendingIncoming: null

    Process {
        id: serverProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/localsend_server.py"]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: (line) => {
                if (line.trim().length === 0) return
                let payload
                try {
                    payload = JSON.parse(line)
                } catch (e) {
                    return
                }

                if (payload.event === "incoming") {
                    localSendMonitor.pendingIncoming = {
                        sessionId: payload.sessionId,
                        alias: payload.alias,
                        deviceType: payload.deviceType || "desktop",
                        files: payload.files || []
                    }
                } else if (payload.event === "expired" || payload.event === "cancelled") {
                    // The sender gave up (timeout) or aborted before we
                    // decided — clear the prompt so it doesn't linger for a
                    // transfer that's no longer actually pending.
                    if (localSendMonitor.pendingIncoming && localSendMonitor.pendingIncoming.sessionId === payload.sessionId) {
                        localSendMonitor.pendingIncoming = null
                    }
                } else if (!payload.event) {
                    // A peer that POSTed straight to /register (see
                    // localsend_server.py's handler) rather than ever
                    // multicasting itself — same device-announcement shape
                    // as listenerProc's own payloads, just arriving over
                    // this process's stdout instead.
                    localSendMonitor.mergeDevice(payload)
                }
                // "received" (a file finished writing to ~/Downloads) needs
                // no UI action here — pendingIncoming was already cleared
                // by acceptIncoming() the moment the user made the decision.
            }
        }
    }

    // Writes the user's decision back to localsend_server.py's stdin, which
    // is blocked inside the /prepare-upload HTTP handler waiting for
    // exactly this — see the module docstring's "control channel" note.
    function acceptIncoming() {
        if (!localSendMonitor.pendingIncoming) return
        serverProc.write(JSON.stringify({ sessionId: localSendMonitor.pendingIncoming.sessionId, action: "accept" }) + "\n")
        localSendMonitor.pendingIncoming = null
    }

    function rejectIncoming() {
        if (!localSendMonitor.pendingIncoming) return
        serverProc.write(JSON.stringify({ sessionId: localSendMonitor.pendingIncoming.sessionId, action: "reject" }) + "\n")
        localSendMonitor.pendingIncoming = null
    }

    // Round 2: the actual send flow. Real protocol confirmed from
    // github.com/localsend/protocol's README (v2.2) — register (section
    // 3.1) is only what OTHER devices send back in response to OUR
    // announcement; as the sender initiating a one-off transfer, we skip
    // straight to prepare-upload with our own `info` block, then upload the
    // raw file body (not multipart — the spec's /upload endpoint takes the
    // file bytes directly as the request body). No CA verification in this
    // protocol (fingerprint is "ignored in HTTPS mode" per the spec) — an
    // unverified self-signed TLS connection is the correct, spec-matching
    // trust model here, not a corner cut.
    //
    // Implemented as a Python helper (localsend_send.py, alongside this
    // file) rather than chained curl Process calls — sha256 hashing, JSON
    // building, and a raw-body HTTPS POST with an unverified cert are all
    // straightforward in Python's stdlib and awkward to compose correctly
    // and safely from multiple shelled-out curl invocations. Launched via a
    // fixed argv list (script path + plain arguments, no shell), so a
    // hostile filename/device alias in argv is never a shell-injection risk.
    property string sendStatus: "" // "" | "sending" | "success" | "error"
    property string sendErrorMessage: ""

    function sendFile(device, filePath) {
        localSendMonitor.sendStatus = "sending"
        localSendMonitor.sendErrorMessage = ""
        sendProc.command = [
            "python3",
            Quickshell.env("HOME") + "/.config/quickshell/localsend_send.py",
            filePath,
            device.ip,
            String(device.port),
            device.protocol,
            "Dynamic Island",
            "Linux",
            "quickshell-dynamic-island"
        ]
        sendProc.running = true
        sendTimeoutTimer.restart()
    }

    // A send that never gets a response (a firewalled/unreachable device,
    // or the helper hanging) used to leave sendStatus stuck on "sending"
    // forever, with no way for the UI to recover. Restarted on every
    // sendFile() call, stopped as soon as the process actually finishes
    // (success, a parsed error, or a nonzero exit — see sendProc.onExited)
    // so a fast completion never fires a stale timeout afterward.
    Timer {
        id: sendTimeoutTimer
        interval: 20000
        repeat: false
        onTriggered: {
            if (localSendMonitor.sendStatus === "sending") {
                localSendMonitor.sendStatus = "error"
                localSendMonitor.sendErrorMessage = "Timed out waiting for a response"
                // Actually terminate the hung helper — confirmed by live
                // testing that a QML-side timeout alone leaves the real
                // python process running in the background indefinitely
                // (it only exits on its own internal 15s/120s socket
                // timeouts). sendProc.onExited's own "sending" guard means
                // this won't overwrite the timeout message once it fires.
                sendProc.running = false
            }
        }
    }

    Process {
        id: sendProc

        // Real diagnostic text for the failures that used to be invisible:
        // an unhandled exception in localsend_send.py before it ever prints
        // its JSON result goes to stderr, not stdout, and was previously
        // discarded entirely (no stderr parser existed at all).
        stderr: StdioCollector {
            id: sendStderr
            waitForEnd: true
        }

        stdout: StdioCollector {
            id: sendStdout
            waitForEnd: true
            // No decision-making here on purpose — confirmed by live testing
            // that stdout's onTextChanged can fire before stderr's own
            // waitForEnd has finished flushing, so reading sendStderr.text
            // from inside this handler intermittently saw stale/empty text.
            // onExited below fires only once the process has fully
            // terminated, at which point both collectors are reliably
            // finalized — all parsing happens there instead.
        }

        // The single point of truth for outcome, once the process has
        // genuinely finished (both stdio streams closed). Handles all three
        // real cases: valid success/error JSON on stdout, a crash before any
        // JSON was printed (stdout empty — surface real stderr text instead
        // of a generic message), and a stale timeout that already resolved
        // sendStatus before this fired (guarded by the "sending" check so a
        // late-arriving result never overwrites an already-shown timeout).
        onExited: (exitCode, exitStatus) => {
            sendTimeoutTimer.stop()
            if (localSendMonitor.sendStatus !== "sending") return

            const stdoutText = sendStdout.text ? sendStdout.text.trim() : ""
            let result = null
            if (stdoutText.length > 0) {
                try { result = JSON.parse(stdoutText) } catch (e) { result = null }
            }

            if (result && result.status === "success") {
                localSendMonitor.sendStatus = "success"
            } else if (result && result.status === "error") {
                localSendMonitor.sendStatus = "error"
                localSendMonitor.sendErrorMessage = result.message || "Unknown error"
            } else {
                localSendMonitor.sendStatus = "error"
                const stderrText = sendStderr.text ? sendStderr.text.trim() : ""
                localSendMonitor.sendErrorMessage = stderrText.length > 0
                    ? stderrText.substring(0, 300)
                    : ("Invalid response from send helper (exit code " + exitCode + ")")
            }
        }
    }
}
