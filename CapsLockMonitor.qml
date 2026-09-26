import Quickshell.Io
import QtQuick

// No push event exists for Caps Lock state (Quickshell.Hyprland exposes no
// keyboard/LED state, Hyprland's socket2 has no capslock event). The kernel
// LED class file (/sys/class/leds/input*::capslock/brightness) is the
// cheapest source: a plain file read on a timer, instead of spawning
// `hyprctl devices -j` twice a second. Falls back to hyprctl only if no
// capslock LED exists.
Item {
    id: capsLockMonitor

    readonly property bool active: _active
    property bool _active: false
    property string _ledPath: ""

    Process {
        id: findLed
        command: ["sh", "-c", "ls -d /sys/class/leds/*::capslock 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: capsLockMonitor._ledPath = text.trim()
        }
        Component.onCompleted: running = true
    }

    FileView {
        id: ledFile
        path: capsLockMonitor._ledPath ? capsLockMonitor._ledPath + "/brightness" : ""
        blockLoading: false
        onLoaded: capsLockMonitor._active = parseInt(text().trim(), 10) > 0
    }

    Timer {
        interval: 150
        running: true
        repeat: true
        onTriggered: {
            if (capsLockMonitor._ledPath) ledFile.reload()
            else if (!hyprctlProc.running) hyprctlProc.running = true
        }
    }

    Process {
        id: hyprctlProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                try {
                    const main = JSON.parse(text).keyboards.find(k => k.main)
                    if (main) capsLockMonitor._active = !!main.capsLock
                } catch (e) {}
            }
        }
    }
}
