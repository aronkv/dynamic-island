import Quickshell
import Quickshell.Io
import QtQuick

// Polling-based, same convention as CameraMonitor.qml — Quickshell's Io
// module has no directory-watch primitive (only FileView.watchChanges for a
// single known file), so the newest file in the screenshots folder is
// detected via a periodic `ls -t | head -1`, mirroring CameraMonitor's
// fuser-based poll shape exactly.
Item {
    id: screenshotMonitor

    readonly property string latestPath: _latestPath
    property string _latestPath: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: checkProc.running = true
    }

    Process {
        id: checkProc
        command: ["sh", "-c", "ls -t " + Quickshell.env("HOME") + "/Pictures/Screenshots 2>/dev/null | head -1"]

        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const name = text.trim()
                if (name.length > 0) {
                    screenshotMonitor._latestPath = Quickshell.env("HOME") + "/Pictures/Screenshots/" + name
                }
            }
        }
    }
}
