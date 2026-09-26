import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick

// Session lock (ext-session-lock via WlSessionLock) with PAM password auth.
// Uses its own minimal PAM service (pam/lock: `auth required pam_unix.so`)
// rather than a system file, so distro PAM stacks can't change its behavior.
// Lock with `qs ipc call lock lock` (or the power menu / idle daemon).
Scope {
    id: lockScreen
    property string wallpaperPath: ""
    property var player: null
    property real batteryPercent: -1
    property bool charging: false

    readonly property bool locked: sessionLock.locked

    function lock() { sessionLock.locked = true }

    IpcHandler {
        target: "lock"
        function lock(): void { lockScreen.lock() }
        function isLocked(): bool { return sessionLock.locked }
    }

    property string _password: ""
    property bool _busy: false
    signal authFailed(string message)

    PamContext {
        id: pam
        configDirectory: Quickshell.shellDir + "/pam"
        config: "lock"

        onResponseRequiredChanged: {
            if (!responseRequired) return
            respond(lockScreen._password)
            lockScreen._password = ""
        }
        onCompleted: (result) => {
            lockScreen._busy = false
            if (result === PamResult.Success) sessionLock.locked = false
            else lockScreen.authFailed("Incorrect password")
        }
        onError: (error) => {
            lockScreen._busy = false
            lockScreen._password = ""
            lockScreen.authFailed("Authentication error")
        }
    }

    function tryUnlock(password) {
        if (_busy) return
        _password = password
        _busy = true
        if (!pam.start()) {
            _busy = false
            _password = ""
            authFailed("Authentication unavailable")
        }
    }

    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            color: "#000000"

            LockContent {
                id: content
                anchors.fill: parent
                wallpaperPath: lockScreen.wallpaperPath
                player: lockScreen.player
                batteryPercent: lockScreen.batteryPercent
                charging: lockScreen.charging
                busy: lockScreen._busy
                onSubmit: (password) => lockScreen.tryUnlock(password)
                Component.onCompleted: focusInput()

                Connections {
                    target: lockScreen
                    function onAuthFailed(message) { content.fail(message) }
                }
            }
        }
    }
}
